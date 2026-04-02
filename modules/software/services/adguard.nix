{
  networking.firewall.allowedTCPPorts = [
    53
    80
    3000
  ];
  networking.firewall.allowedUDPPorts = [
    53
    80
    3000
  ];
  services.adguardhome = {
    enable = true;
    allowDHCP = false;
    port = 80;
    mutableSettings = true;
    settings = {
      http = {
        pprof = {
          port = 6060;
          enabled = false;
        };
        address = "0.0.0.0:80";
        session_ttl = "720h";
      };
      users = [
        {
          name = "***REDACTED_USERNAME***";
          password = "***REDACTED_BCRYPT_HASH***";
        }
      ];
      auth_attempts = 5;
      block_auth_min = 15;
      http_proxy = "";
      language = "";
      theme = "auto";
      dns = {
        bind_hosts = [ "0.0.0.0" ];
        port = 53;
        anonymize_client_ip = false;
        ratelimit = 0;
        ratelimit_subnet_len_ipv4 = 24;
        ratelimit_subnet_len_ipv6 = 56;
        ratelimit_whitelist = [ ];
        refuse_any = true;
        upstream_dns = [
          # "9.9.9.9"
          "10.73.73.5:5335"
        ];
        upstream_dns_file = "";
        bootstrap_dns = [
          "9.9.9.9"
          "1.1.1.1"
        ];
        fallback_dns = [ ];
        upstream_mode = "load_balance";
        fastest_timeout = "1s";
        allowed_clients = [ ];
        disallowed_clients = [ ];
        blocked_hosts = [
          "version.bind"
          "id.server"
          "hostname.bind"
        ];
        trusted_proxies = [
          "127.0.0.0/8"
          "::1/128"
        ];
        cache_enabled = true;
        cache_size = 4194304;
        cache_ttl_min = 0;
        cache_ttl_max = 0;
        cache_optimistic = false;
        cache_optimistic_answer_ttl = "30s";
        cache_optimistic_max_age = "12h";
        bogus_nxdomain = [ ];
        aaaa_disabled = false;
        enable_dnssec = false;
        edns_client_subnet = {
          custom_ip = "";
          enabled = false;
          use_custom = false;
        };
        max_goroutines = 300;
        handle_ddr = true;
        ipset = [ ];
        ipset_file = "";
        bootstrap_prefer_ipv6 = false;
        upstream_timeout = "10s";
        private_networks = [ ];
        use_private_ptr_resolvers = false;
        local_ptr_upstreams = [ ];
        use_dns64 = false;
        dns64_prefixes = [ ];
        serve_http3 = false;
        use_http3_upstreams = false;
        serve_plain_dns = true;
        hostsfile_enabled = true;
        pending_requests = {
          enabled = true;
        };
      };
      tls = {
        enabled = false;
        server_name = "";
        force_https = false;
        port_https = 443;
        port_dns_over_tls = 853;
        port_dns_over_quic = 853;
        port_dnscrypt = 0;
        dnscrypt_config_file = "";
        allow_unencrypted_doh = false;
        certificate_chain = "";
        private_key = "";
        certificate_path = "";
        private_key_path = "";
        strict_sni_check = false;
      };
      querylog = {
        dir_path = "";
        ignored = [ ];
        interval = "2160h";
        size_memory = 1000;
        enabled = true;
        file_enabled = true;
      };
      statistics = {
        dir_path = "";
        ignored = [ ];
        interval = "24h";
        enabled = true;
      };
      filters = [
        {
          enabled = true;
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
          name = "AdGuard DNS filter";
          id = 1;
        }
        {
          enabled = false;
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt";
          name = "AdAway Default Blocklist";
          id = 2;
        }
      ];
      whitelist_filters = [ ];
      user_rules = [ ];
      dhcp = {
        enabled = false;
        interface_name = "";
        local_domain_name = "lan";
        dhcpv4 = {
          gateway_ip = "";
          subnet_mask = "";
          range_start = "";
          range_end = "";
          lease_duration = 86400;
          icmp_timeout_msec = 1000;
          options = [ ];
        };
        dhcpv6 = {
          range_start = "";
          lease_duration = 86400;
          ra_slaac_only = false;
          ra_allow_slaac = false;
        };
      };
      filtering = {
        blocking_ipv4 = "";
        blocking_ipv6 = "";
        blocked_services = {
          schedule = {
            time_zone = "UTC";
          };
          ids = [ ];
        };
        protection_disabled_until = null;
        safe_search = {
          enabled = false;
          bing = true;
          duckduckgo = true;
          ecosia = true;
          google = true;
          pixabay = true;
          yandex = true;
          youtube = true;
        };
        blocking_mode = "default";
        parental_block_host = "family-block.dns.adguard.com";
        safebrowsing_block_host = "standard-block.dns.adguard.com";
        rewrites = [
          {
            domain = "samba-nix.lan";
            answer = "10.73.73.4";
            enabled = true;
          }
          {
            domain = "unbound-vpn-na-nix.lan";
            answer = "10.73.73.5";
            enabled = true;
          }
          {
            domain = "adguard-nix.lan";
            answer = "10.73.73.6";
            enabled = true;
          }
          {
            domain = "llm-nix.lan";
            answer = "10.73.73.7";
            enabled = true;
          }
          {
            domain = "local-nginx-nix.lan";
            answer = "10.73.73.8";
            enabled = true;
          }
          {
            domain = "vaultwarden-nix.lan";
            answer = "10.73.73.9";
            enabled = true;
          }
          {
            domain = "acme-nix.lan";
            answer = "10.73.73.10";
            enabled = true;
          }
          {
            domain = "socks5-vpn-eunix.lan";
            answer = "10.73.73.11";
            enabled = true;
          }
          {
            domain = "immich-nix.lan";
            answer = "10.73.73.12";
            enabled = true;
          }
          {
            domain = "arrs-nix.lan";
            answer = "10.73.73.13";
            enabled = true;
          }
          {
            domain = "jellyfin-nix.lan";
            answer = "10.73.73.15";
            enabled = true;
          }
          {
            domain = "nextcloud-nix.lan";
            answer = "10.73.73.18";
            enabled = true;
          }
          {
            domain = "deluge-nix.lan";
            answer = "10.73.73.20";
            enabled = true;
          }
          {
            domain = "jellyseerr-nix.lan";
            answer = "10.73.73.26";
            enabled = true;
          }
          {
            domain = "gotify-nix.lan";
            answer = "10.73.73.27";
            enabled = true;
          }
          {
            domain = "pufferpanel-nix.lan";
            answer = "10.73.73.30";
            enabled = true;
          }
          {
            domain = "build-nix.lan";
            answer = "10.73.73.40";
            enabled = true;
          }
          {
            domain = "unifi-nix.lan";
            answer = "10.73.73.41";
            enabled = true;
          }
          {
            domain = "laptop-nix.lan";
            answer = "10.73.73.68";
            enabled = true;
          }
          {
            domain = "desktop-nix.lan";
            answer = "10.73.73.69";
            enabled = true;
          }
          {
            domain = "printer.lan";
            answer = "10.73.73.71";
            enabled = true;
          }
          {
            domain = "deck-nix.lan";
            answer = "10.73.73.73";
            enabled = true;
          }
          {
            domain = "*.tsawhill.org";
            answer = "10.73.73.8";
            enabled = true;
          }
          {
            domain = "tsawhill.org";
            answer = "10.73.73.8";
            enabled = true;
          }
          {
            domain = "remote-nginx-nix.lan";
            answer = "10.50.50.16";
            enabled = true;
          }
          {
            domain = "server-nix.lan";
            answer = "10.73.73.3";
            enabled = true;
          }
          {
            domain = "remote-nginx-nix.lan";
            answer = "10.50.50.16";
            enabled = true;
          }
          {
            domain = "authentik-nix.lan";
            answer = "10.73.73.29";
            enabled = true;
          }
          {
            domain = "syncthing-nix.lan";
            answer = "10.73.73.14";
            enabled = true;
          }
          {
            domain = "romm-nix.lan";
            answer = "10.73.73.19";
            enabled = true;
          }
          {
            domain = "sunshine-nix.lan";
            answer = "10.73.73.140";
            enabled = true;
          }
        ];
        safe_fs_patterns = [ "/var/lib/private/AdGuardHome/userfilters/*" ];
        safebrowsing_cache_size = 1048576;
        safesearch_cache_size = 1048576;
        parental_cache_size = 1048576;
        cache_time = 30;
        filters_update_interval = 24;
        blocked_response_ttl = 10;
        filtering_enabled = true;
        rewrites_enabled = true;
        parental_enabled = false;
        safebrowsing_enabled = false;
        protection_enabled = true;
      };
      clients = {
        runtime_sources = {
          whois = true;
          arp = true;
          rdns = true;
          dhcp = true;
          hosts = true;
        };
        persistent = [ ];
      };
      log = {
        enabled = true;
        file = "";
        max_backups = 0;
        max_size = 100;
        max_age = 3;
        compress = false;
        local_time = false;
        verbose = false;
      };
      os = {
        group = "";
        user = "";
        rlimit_nofile = 0;
      };
      schema_version = 32;
    };
  };
}
