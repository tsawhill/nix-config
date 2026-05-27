{ config, lib, ... }:

let
  cfg = config.my.router;

  inherit (lib)
    any
    attrValues
    concatMapStringsSep
    concatStringsSep
    hasInfix
    hasPrefix
    head
    length
    mkIf
    optionalString
    ;

  interfaces = attrValues cfg.interfaces;
  lanInterfaces = map (iface: iface.name) (
    builtins.filter (iface: iface.role == "lan" || iface.role == "internal") interfaces
  );
  wanInterfaces = map (iface: iface.name) (builtins.filter (iface: iface.role == "wan") interfaces);

  quote = value: ''"${value}"'';
  nftSet = values: "{ ${concatStringsSep ", " values} }";
  nftQuotedSet = values: nftSet (map quote values);
  portsSet = ports: nftSet (map toString ports);
  wanSet = nftQuotedSet wanInterfaces;
  lanSet = nftQuotedSet lanInterfaces;

  # Aliases become nft sets in every table that may reference them. nft sets
  # are table-scoped, so duplicating them is intentional.
  aliasSets = concatMapStringsSep "\n" (
    alias:
    ''
      set ${alias.name} {
        type ${alias.nftType}
        ${optionalString (any (value: hasInfix "/" value) alias.values) "flags interval"}
        elements = ${nftSet alias.values}
      }
    ''
  ) (attrValues cfg.firewall.aliases);

  asList = value: if builtins.isList value then value else [ value ];
  stripBang =
    value: builtins.substring 1 ((builtins.stringLength value) - 1) value;

  addressExpr =
    field: matcher:
    let
      values = asList matcher;
    in
    if matcher == "any" || values == [ ] then
      ""
    else if builtins.isString matcher && hasPrefix "!" matcher then
      "${field} != ${stripBang matcher}"
    else if length values == 1 then
      "${field} ${head values}"
    else
      "${field} ${nftSet values}";

  commentExpr =
    rule:
    optionalString (rule.comment != null) " comment \"${rule.comment}\"";

  renderForwardRule =
    action: inInterface: rule:
    let
      protocols =
        if rule.protocols == [ ] && rule.ports != [ ] then
          [
            "tcp"
            "udp"
          ]
        else
          rule.protocols;

      common = concatStringsSep " " (
        builtins.filter (part: part != "") [
          ''iifname "${inInterface}"''
          (addressExpr "ip saddr" rule.from)
          (addressExpr "ip daddr" rule.to)
          (optionalString (rule.outInterface != null) ''oifname "${rule.outInterface}"'')
        ]
      );

      renderProtocol =
        protocol:
        concatStringsSep " " (
          builtins.filter (part: part != "") [
            common
            (optionalString (protocol != null && rule.ports == [ ]) "meta l4proto ${protocol}")
            (optionalString (protocol != null && rule.ports != [ ]) "${protocol} dport ${portsSet rule.ports}")
            action
          ]
        )
        + commentExpr rule;
    in
    if protocols == [ ] then
      "${common} ${action}${commentExpr rule}"
    else
      concatMapStringsSep "\n" renderProtocol protocols;

  interfaceForwardRules = concatMapStringsSep "\n" (
    inInterface:
    let
      rules = cfg.firewall.rules.${inInterface};
    in
    concatStringsSep "\n" [
      (concatMapStringsSep "\n" (renderForwardRule "drop" inInterface) rules.block)
      (concatMapStringsSep "\n" (renderForwardRule "accept" inInterface) rules.allow)
    ]
  ) (builtins.attrNames cfg.firewall.rules);

  allowedWanRules = ''
    ${optionalString (cfg.firewall.allowedWan.tcp != [ ]) ''iifname ${wanSet} tcp dport ${portsSet cfg.firewall.allowedWan.tcp} accept''}
    ${optionalString (cfg.firewall.allowedWan.udp != [ ]) ''iifname ${wanSet} udp dport ${portsSet cfg.firewall.allowedWan.udp} accept''}
  '';

  blockForwardRules = concatMapStringsSep "\n" (
    rule:
    ''
      ${optionalString (rule.inInterface != null) ''iifname "${rule.inInterface}"''} ip saddr ${rule.source} ip daddr != ${rule.destination} drop comment "${rule.name}"
    ''
  ) cfg.firewall.blockForward;

  policyMarkRules = concatMapStringsSep "\n" (
    rule:
    ''
      ${optionalString (rule.source != null) "ip saddr ${rule.source}"} ${optionalString (rule.destination != null) "ip daddr ${rule.destination}"} meta mark set ${toString rule.mark}${optionalString (rule.comment != null) " comment \"${rule.comment}\""}
    ''
  ) cfg.firewall.policyRules;

  policyRouteRules = concatMapStringsSep "\n" (
    rule:
    let
      client = cfg.wireguard.clients.${rule.via};
    in
    concatStringsSep " " (
      builtins.filter (part: part != "") [
        (addressExpr "ip saddr" rule.from)
        (addressExpr "ip daddr" rule.to)
        "meta mark set ${toString client.fwMark}"
      ]
    )
    + commentExpr rule
  ) cfg.firewall.policyRoutes;

  portForwardPreroutingRules = concatMapStringsSep "\n" (
    forward:
    concatMapStringsSep "\n" (
      protocol:
      ''iifname "${forward.inInterface}" ${protocol} dport ${toString forward.originalPort} dnat to ${forward.destination}:${toString forward.destinationPort} comment "${forward.name}"''
    ) forward.protocols
  ) cfg.firewall.portForwards;

  portForwardAcceptRules = concatMapStringsSep "\n" (
    forward:
    concatMapStringsSep "\n" (
      protocol:
      ''${protocol} dport ${toString forward.destinationPort} ip daddr ${forward.destination} accept comment "${forward.name}"''
    ) forward.protocols
  ) cfg.firewall.portForwards;

  masqueradeRules = concatMapStringsSep "\n" (
    iface: ''oifname "${iface}" masquerade''
  ) (wanInterfaces ++ cfg.firewall.masqueradeInterfaces);
in
{
  config = mkIf cfg.enable {
    # Disable the NixOS iptables-style firewall and install a full nftables
    # ruleset. The generated rules are intentionally small and expose escape
    # hatches for site-specific policy that does not deserve a typed option yet.
    networking = {
      firewall.enable = false;
      nftables.enable = true;
    };

    networking.nftables.ruleset = ''
      table inet router_filter {
        ${aliasSets}

        chain input {
          type filter hook input priority filter; policy drop;
          iifname "lo" accept
          ct state established,related accept
          iifname ${lanSet} accept
          ${allowedWanRules}
          ${cfg.firewall.extraInputRules}
        }

        chain forward {
          type filter hook forward priority filter; policy drop;
          ct state established,related accept
          ${blockForwardRules}
          ${interfaceForwardRules}
          iifname ${lanSet} accept
          iifname ${wanSet} oifname ${lanSet} drop
          ${portForwardAcceptRules}
          ${cfg.firewall.extraEarlyForwardRules}
          ${cfg.firewall.extraForwardRules}
        }
      }

      table ip router_nat {
        ${aliasSets}

        chain prerouting {
          type nat hook prerouting priority dstnat; policy accept;
          ${portForwardPreroutingRules}
          ${cfg.firewall.extraPreroutingRules}
        }

        chain postrouting {
          type nat hook postrouting priority srcnat; policy accept;
          ${masqueradeRules}
          ${cfg.firewall.extraPostroutingRules}
        }
      }

      table ip router_mangle {
        ${aliasSets}

        chain prerouting {
          type filter hook prerouting priority mangle; policy accept;
          ${policyRouteRules}
          ${policyMarkRules}
          ${cfg.firewall.extraMangleRules}
        }
      }
    '';

    assertions = map (rule: {
      assertion =
        builtins.hasAttr rule.via cfg.wireguard.clients
        && cfg.wireguard.clients.${rule.via}.fwMark != null;
      message = "my.router.firewall.policyRoutes via=${rule.via} must reference a WireGuard client with fwMark set.";
    }) cfg.firewall.policyRoutes;
  };
}
