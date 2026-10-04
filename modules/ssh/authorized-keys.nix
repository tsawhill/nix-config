# Applies ./access.nix: authorized keys for this host, plus /etc/ssh/access.json
# so the nushell ssh completer can offer only user@host pairs this login can use.
{
  config,
  lib,
  networkTopology,
  ...
}:

let
  access = import ./access.nix;

  incusGuests = lib.attrNames (
    lib.filterAttrs (_: host: (host.incus.manager or null) == "server-nix") networkTopology.hosts
  );

  targetHosts = target: if target == "incus-guests" then incusGuests else [ target ];

  # key -> [ { host, user } ]
  logins = lib.mapAttrs (
    _: targets:
    lib.concatLists (
      lib.mapAttrsToList (
        target: users: lib.concatMap (host: map (user: { inherit host user; }) users) (targetHosts target)
      ) targets
    )
  ) access.grants;

  hostName = config.networking.hostName;

  # user -> keys allowed to log in as them here
  keysHere = lib.zipAttrs (
    lib.concatLists (
      lib.mapAttrsToList (
        key: hostLogins:
        map (login: { ${login.user} = access.keys.${key}; }) (
          lib.filter (login: login.host == hostName) hostLogins
        )
      ) logins
    )
  );

  inherit (networkTopology.lib) fqdn;

  # Every name a managed host shows up under in known_hosts.
  hostAliases =
    host:
    let
      entry = networkTopology.hosts.${host};
    in
    [
      host
      (fqdn host)
    ]
    ++ lib.optional (entry ? lan.ip) entry.lan.ip
    ++ lib.optional (entry ? wgRemote.ip) entry.wgRemote.ip
    ++ lib.optional (entry ? transit.ip) entry.transit.ip;

  unknownKeys = lib.attrNames (builtins.removeAttrs access.grants (lib.attrNames access.keys));
  unknownTargets = lib.filter (
    target: target != "incus-guests" && !networkTopology.hosts ? ${target}
  ) (lib.unique (lib.concatMap lib.attrNames (lib.attrValues access.grants)));
in
{
  assertions = [
    {
      assertion = unknownKeys == [ ];
      message = "modules/ssh/access.nix: grants for unknown keys: ${toString unknownKeys}";
    }
    {
      assertion = unknownTargets == [ ];
      message = "modules/ssh/access.nix: targets not in topology: ${toString unknownTargets}";
    }
  ];

  users.users = lib.mapAttrs (_: keys: { openssh.authorizedKeys.keys = keys; }) keysHere;

  environment.etc."ssh/access.json".text = builtins.toJSON {
    managed = lib.concatMap hostAliases (
      lib.unique (map (login: login.host) (lib.concatLists (lib.attrValues logins)))
    );
    reachable = lib.mapAttrs (_: map (login: "${login.user}@${fqdn login.host}")) logins;
  };
}
