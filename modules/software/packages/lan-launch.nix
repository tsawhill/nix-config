{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.software.lan-launch;

  lan-launch-exec = pkgs.writeShellScript "lan-launch-exec" ''
    ns="$1"; uid="$2"; gid="$3"
    shift 3
    exec ${lib.getExe' pkgs.util-linux "nsenter"} --net="/var/run/netns/$ns" \
      ${lib.getExe' pkgs.util-linux "unshare"} --mount -- \
      ${lib.getExe pkgs.bash} -c '
        if [ -f "/run/netns-dns/$1/resolv.conf" ]; then
          ${lib.getExe' pkgs.util-linux "mount"} --bind "/run/netns-dns/$1/resolv.conf" /etc/resolv.conf
        fi
        exec ${lib.getExe' pkgs.util-linux "setpriv"} --reuid="$2" --regid="$3" --init-groups -- "''${@:4}"
      ' _ "$ns" "$uid" "$gid" "$@"
  '';
in
{
  options.software.lan-launch = {
    enable = lib.mkEnableOption "lan-launch (run apps over LAN, bypassing VPN)";

    interfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "LAN interfaces to create network namespaces for.";
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Users allowed to run lan-launch without a password.";
    };

    dns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "1.1.1.1"
        "8.8.8.8"
      ];
      description = "DNS servers for the LAN namespace.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

    networking.firewall.extraCommands = lib.mkIf (cfg.interfaces != [ ]) (
      let
        rules = lib.concatStrings (
          lib.imap0 (
            i: iface:
            let
              subnet = "10.200.${toString (200 + i)}";
              veth = "veth-lan-${iface}";
            in
            ''
              iptables -A LAN-LAUNCH -i ${veth} -o ${iface} -j ACCEPT
              iptables -A LAN-LAUNCH -i ${iface} -o ${veth} -m state --state RELATED,ESTABLISHED -j ACCEPT
              iptables -t nat -A LAN-LAUNCH -s ${subnet}.0/24 -o ${iface} -j MASQUERADE
            ''
          ) cfg.interfaces
        );
      in
      ''
        iptables -N LAN-LAUNCH 2>/dev/null || iptables -F LAN-LAUNCH
        iptables -t nat -N LAN-LAUNCH 2>/dev/null || iptables -t nat -F LAN-LAUNCH
        iptables -C FORWARD -j LAN-LAUNCH 2>/dev/null || iptables -A FORWARD -j LAN-LAUNCH
        iptables -t nat -C POSTROUTING -j LAN-LAUNCH 2>/dev/null || iptables -t nat -A POSTROUTING -j LAN-LAUNCH
        ${rules}
      ''
    );

    systemd.services = builtins.listToAttrs (
      lib.imap0 (
        i: iface:
        let
          subnet = "10.200.${toString (200 + i)}";
          veth = "veth-lan-${iface}";
          ip = lib.getExe' pkgs.iproute2 "ip";
        in
        {
          name = "lan-netns-${iface}";
          value = {
            description = "LAN network namespace (${iface})";
            wantedBy = [ "multi-user.target" ];
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              set -e
              ${ip} netns add lan-${iface}
              ${ip} link add ${veth} type veth peer name veth-ns
              ${ip} link set veth-ns netns lan-${iface}

              ${ip} addr add ${subnet}.1/24 dev ${veth}
              ${ip} link set ${veth} up

              ${ip} netns exec lan-${iface} ${ip} link set lo up
              ${ip} netns exec lan-${iface} ${ip} addr add ${subnet}.2/24 dev veth-ns
              ${ip} netns exec lan-${iface} ${ip} link set veth-ns up
              ${ip} netns exec lan-${iface} ${ip} route add default via ${subnet}.1

              mkdir -p /run/netns-dns/lan-${iface}
              printf '%s\n' ${lib.concatMapStringsSep " " (d: "'nameserver ${d}'") cfg.dns} \
                > /run/netns-dns/lan-${iface}/resolv.conf
            '';
            preStop = ''
              ${ip} netns delete lan-${iface} || true
              rm -rf /run/netns-dns/lan-${iface}
            '';
          };
        }
      ) cfg.interfaces
    );

    security.sudo.extraRules = lib.mkIf (cfg.users != [ ]) [
      {
        users = cfg.users;
        commands = [
          {
            command = toString lan-launch-exec;
            options = [
              "NOPASSWD"
              "SETENV"
            ];
          }
        ];
      }
    ];

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "lan-launch" ''
        if [ $# -lt 2 ]; then
          echo "Usage: lan-launch <interface> <command...>" >&2
          exit 1
        fi
        iface="$1"
        shift
        exec sudo --preserve-env ${lan-launch-exec} "lan-$iface" "$(id -u)" "$(id -g)" "$@"
      '')
    ];
  };
}
