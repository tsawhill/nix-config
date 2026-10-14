{
  config,
  lib,
  pkgs,
  networkTopology,
  ...
}:

let
  cfg = config.my.network.router.wanQos;
  inherit (networkTopology) hosts;

  addressOf =
    host:
    if (hosts.${host}.attachment or "lan") == "transit" then
      hosts.${host}.transit.ip
    else
      hosts.${host}.lan.ip;

  ifb = "wanin";
  # Cable modem framing; nat lets CAKE see LAN hosts behind the masquerade.
  cakeCommon = "diffserv4 nat wash docsis";

  wanQos = pkgs.writeShellApplication {
    name = "wan-qos";
    runtimeInputs = [ pkgs.iproute2 ];
    text = ''
      teardown() {
        tc qdisc del dev wan clsact 2>/dev/null || true
        tc qdisc del dev wan root 2>/dev/null || true
        ip link del ${ifb} 2>/dev/null || true
      }

      teardown
      if [ "''${1:-start}" = stop ]; then
        exit 0
      fi
      trap 'teardown; exit 1' ERR

      tc qdisc replace dev wan root cake bandwidth ${toString cfg.uploadMbit}mbit \
        ${cakeCommon} dual-srchost ack-filter

      # Single-queue cake on the ifb topped out near 1.6 Gbit/s, hence cake_mq.
      ip link add ${ifb} numtxqueues ${toString cfg.ingressQueues} \
        numrxqueues ${toString cfg.ingressQueues} type ifb
      ip link set ${ifb} up
      if tc qdisc add dev ${ifb} root cake_mq bandwidth ${toString cfg.downloadMbit}mbit \
        ${cakeCommon} dual-dsthost ingress no-split-gso; then
        tc qdisc add dev wan clsact
        # Restore the DSCP the upload side stored in the connection's ct mark.
        tc filter add dev wan ingress matchall \
          action ctinfo dscp 0x3f 0x40 \
          action mirred egress redirect dev ${ifb}
      else
        echo "cake_mq unavailable (needs Linux 7.0+); download is not shaped" >&2
        ip link del ${ifb}
      fi
    '';
  };
in
{
  options.my.network.router.wanQos = {
    enable = lib.mkEnableOption "CAKE on the WAN, with priority hosts ahead of everything else";

    downloadMbit = lib.mkOption {
      type = lib.types.ints.positive;
      description = "Download shaping rate, a little under the plan so the queue stays here, not at the ISP.";
    };

    uploadMbit = lib.mkOption {
      type = lib.types.ints.positive;
      description = "Upload shaping rate, a little under the plan.";
    };

    priorityHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Topology hosts whose WAN traffic goes ahead of everything else. Everything
        else lands in CAKE's Bulk tin, which keeps about 6% under contention.
        DNS and NTP stay at normal priority whichever host sends them.
      '';
    };

    ingressQueues = lib.mkOption {
      type = lib.types.ints.positive;
      default = 8;
      description = "ifb queues, and so cake_mq instances, that share the download rate.";
    };
  };

  config = lib.mkIf (config.my.network.router.enable && cfg.enable) {
    assertions = [
      {
        assertion = lib.all (host: hosts ? ${host}) cfg.priorityHosts;
        message = "my.network.router.wanQos.priorityHosts names a host that isn't in the topology.";
      }
    ];

    # ct mark: 0x40 = classified, low six bits = the DSCP act_ctinfo restores on download.
    networking.nftables.tables.wan_qos = {
      family = "inet";
      content = ''
        set prio_hosts {
          type ipv4_addr
          ${lib.optionalString (cfg.priorityHosts != [ ])
            "elements = { ${lib.concatMapStringsSep ", " addressOf cfg.priorityHosts} }"
          }
        }

        chain postrouting {
          type filter hook postrouting priority mangle; policy accept;
          oifname != "wan" return
          ip saddr @prio_hosts ct mark set 0x40 return
          meta l4proto { tcp, udp } th dport { 53, 123, 853 } ct mark set 0x40 return
          ct mark set 0x48 ip dscp set cs1
        }
      '';
    };

    systemd.services.wan-qos = {
      description = "Shape WAN traffic with CAKE, priority hosts first";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "nftables.service"
      ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${wanQos}/bin/wan-qos start";
        ExecStop = "${wanQos}/bin/wan-qos stop";
      };
    };

    environment.systemPackages = [ wanQos ];
  };
}
