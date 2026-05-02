{
  # Global SSH trust roots copied from root@build-nix.lan:/root/.ssh/known_hosts.
  programs.ssh.knownHostsFiles = [
    ./known_hosts
  ];
}
