{
  pkgs,
  ...
}:

let
  # Developer note:
  # This module exists because Jellyfin currently exposes some media/image API
  # surfaces before normal user authentication has happened. Once Jellyfin
  # hardens those endpoints, the `jellyfin-api-scanner` jail should become much
  # less useful and can probably be removed or relaxed into ordinary rate
  # limiting.
  stateDir = "/var/lib/jellyfin-known-ips";
  stateFile = "${stateDir}/known-ips.tsv";
  retentionDays = "30";

  # Maintains and queries a small "known client IP" cache. A recent successful
  # Jellyfin auth request gives that IP 30 days of grace so normal TVs/phones do
  # not get banned for token refresh weirdness or normal playback endpoints.
  jellyfinKnownIp = pkgs.writeShellApplication {
    name = "jellyfin-known-ip";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gzip
      pkgs.perl
    ];
    text = ''
      set -euo pipefail

      state_file="${stateFile}"
      retention_days="${retentionDays}"

      case "''${1:-}" in
        refresh)
          # Rebuild the durable cache from current and rotated nginx logs. This
          # is intentionally log-derived instead of asking Jellyfin directly so
          # the nginx host can make fail2ban decisions without app credentials.
          mkdir -p "$(dirname "$state_file")"
          perl -MTime::Piece -e '
            use strict;
            use warnings;

            my ($state_file, $retention_days, @patterns) = @ARGV;
            my $cutoff = time - (int($retention_days) * 24 * 60 * 60);
            my %seen;

            if (open my $state, "<", $state_file) {
              while (my $line = <$state>) {
                chomp $line;
                my ($ip, $epoch) = split /\t/, $line, 2;
                next unless defined $ip && defined $epoch && $epoch =~ /^\d+$/;
                next if $epoch < $cutoff;
                $seen{$ip} = $epoch if !exists $seen{$ip} || $epoch > $seen{$ip};
              }
              close $state;
            }

            for my $pattern (@patterns) {
              for my $log (glob $pattern) {
                next unless -f $log;
                my $fh;
                if ($log =~ /\.gz$/) {
                  open $fh, "-|", "gzip", "-cd", "--", $log or next;
                } else {
                  open $fh, "<", $log or next;
                }

                while (my $line = <$fh>) {
                  next unless $line =~ m{^(\S+) - - \[([^\]]+)\] "(\S+) ([^ ]+) HTTP/[0-9.]+" (200|204) \S+ };
                  my ($ip, $stamp, $method, $uri) = ($1, $2, $3, $4);
                  next unless
                    $uri =~ m{^/Users/Me(?:\?|$)}i
                    || ($method eq "POST" && $uri =~ m{^/Users/Authenticate}i)
                    || $uri =~ m{^/Users/[0-9a-f]{32}(?:[/?]|$)}i
                    || ($method eq "POST" && $uri =~ m{^/Sessions/(?:Capabilities/Full|Playing/Progress)(?:\?|$)}i)
                    || $uri =~ m{^/DisplayPreferences/[^ ]*[?&]userId=[0-9a-f]{32}}i
                    || $uri =~ m{[?&]api_key=[0-9a-f]{32}}i
                    || $uri =~ m{[?&]ApiKey=[0-9a-f]{32}};
                  my $epoch = eval {
                    Time::Piece->strptime($stamp, "%d/%b/%Y:%H:%M:%S %z")->epoch;
                  };
                  next unless defined $epoch && $epoch >= $cutoff;
                  $seen{$ip} = $epoch if !exists $seen{$ip} || $epoch > $seen{$ip};
                }
                close $fh;
              }
            }

            my $tmp = "$state_file.tmp.$$";
            open my $out, ">", $tmp or die "open $tmp: $!";
            for my $ip (sort keys %seen) {
              print $out "$ip\t$seen{$ip}\n";
            }
            close $out or die "close $tmp: $!";
            chmod 0644, $tmp;
            rename $tmp, $state_file or die "rename $tmp to $state_file: $!";
          ' "$state_file" "$retention_days" /var/log/nginx/access.log /var/log/nginx/access.log.1 '/var/log/nginx/access.log.*.gz'
          ;;

        check)
          # fail2ban calls this from ignorecommand. Exit 0 means "known client,
          # ignore this failure"; exit 1 means "unknown client, count it".
          # In addition to the cache, scan recent logs directly so a fresh login
          # is trusted before the next timer refresh runs.
          ip="''${2:-}"
          [ -n "$ip" ] || exit 1
          perl -e '
            use strict;
            use warnings;

            my ($state_file, $ip, $retention_days, @patterns) = @ARGV;
            my $cutoff = time - (int($retention_days) * 24 * 60 * 60);

            if (open my $state, "<", $state_file) {
              while (my $line = <$state>) {
                chomp $line;
                my ($known_ip, $epoch) = split /\t/, $line, 2;
                next unless defined $known_ip && defined $epoch && $epoch =~ /^\d+$/;
                exit 0 if $known_ip eq $ip && $epoch >= $cutoff;
              }
              close $state;
            }

            for my $pattern (@patterns) {
              for my $log (glob $pattern) {
                next unless -f $log;
                my $fh;
                if ($log =~ /\.gz$/) {
                  open $fh, "-|", "gzip", "-cd", "--", $log or next;
                } else {
                  open $fh, "<", $log or next;
                }

                while (my $line = <$fh>) {
                  next unless $line =~ m{^\Q$ip\E - - \[([^\]]+)\] "(\S+) ([^ ]+) HTTP/[0-9.]+" (200|204) \S+ };
                  my ($stamp, $method, $uri) = ($1, $2, $3);
                  next unless
                    $uri =~ m{^/Users/Me(?:\?|$)}i
                    || ($method eq "POST" && $uri =~ m{^/Users/Authenticate}i)
                    || $uri =~ m{^/Users/[0-9a-f]{32}(?:[/?]|$)}i
                    || ($method eq "POST" && $uri =~ m{^/Sessions/(?:Capabilities/Full|Playing/Progress)(?:\?|$)}i)
                    || $uri =~ m{^/DisplayPreferences/[^ ]*[?&]userId=[0-9a-f]{32}}i
                    || $uri =~ m{[?&]api_key=[0-9a-f]{32}}i
                    || $uri =~ m{[?&]ApiKey=[0-9a-f]{32}};
                  my $epoch = eval {
                    Time::Piece->strptime($stamp, "%d/%b/%Y:%H:%M:%S %z")->epoch;
                  };
                  exit 0 if defined $epoch && $epoch >= $cutoff;
                }
                close $fh;
              }
            }

            exit 1;
          ' "$state_file" "$ip" "$retention_days" /var/log/nginx/access.log /var/log/nginx/access.log.1 '/var/log/nginx/access.log.*.gz'
          ;;

        *)
          echo "usage: jellyfin-known-ip refresh|check <ip>" >&2
          exit 2
          ;;
      esac
    '';
  };
in
{
  environment.systemPackages = [ jellyfinKnownIp ];

  # Keep the known-client cache warm. This is only a performance/availability
  # helper; ignorecommand can still scan logs directly if the cache is stale.
  systemd.services.jellyfin-known-ips-refresh = {
    description = "Refresh recently authenticated Jellyfin client IPs";
    after = [ "nginx.service" ];
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "jellyfin-known-ips";
      ExecStart = "${jellyfinKnownIp}/bin/jellyfin-known-ip refresh";
    };
  };

  systemd.timers.jellyfin-known-ips-refresh = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "5m";
      Persistent = true;
    };
  };

  systemd.services.fail2ban = {
    wants = [ "jellyfin-known-ips-refresh.service" ];
    after = [ "jellyfin-known-ips-refresh.service" ];
  };

  services.fail2ban.jails = {
    # Strict auth-failure jail for unknown Jellyfin clients. Known clients are
    # ignored via jellyfin-known-ip so a legitimate device with an expired token
    # does not immediately ban itself.
    "jellyfin-nginx" = {
      settings = {
        enabled = true;
        backend = "polling";
        maxretry = 3;
        findtime = "10m";
        failregex = ''^<HOST> - - \[[^\]]+\] "(GET|POST|HEAD) /(?:Users/Me(?:\?[^ ]*)?|Users/[0-9a-fA-F]{32}(?:[/?][^ ]*)?|Users/Authenticate[^ ]*) HTTP/[0-9.]+" 401\b.*'';
        ignorecommand = "${jellyfinKnownIp}/bin/jellyfin-known-ip check <HOST>";
        action = ''iptables-multiport[name=jellyfin-nginx, port="http,https", protocol=tcp]'';
        logpath = "/var/log/nginx/access.log";
        port = "http, https";
      };
    };

    # Temporary hardening for unauthenticated or weakly-authenticated Jellyfin
    # media surfaces. This targets scanner traffic against stream/image/download
    # endpoints that have appeared in Jellyfin advisories; known clients are
    # ignored so normal playback remains usable. Requests carrying an API key in
    # the URL are also ignored here so an expired-token playback retry from a
    # new IP does not immediately ban a real user.
    "jellyfin-api-scanner" = {
      settings = {
        enabled = true;
        backend = "polling";
        maxretry = 3;
        findtime = "15m";
        failregex = ''^<HOST> - - \[[^\]]+\] "(GET|POST|HEAD) (/(?i:videos|audio)/[^ /?]+/[^ ]*(?:stream|hls|master|main|live\.m3u8)[^ ]*|/(?i:items)/[^ /?]+/(?i:images|download|file|playbackinfo)[^ ]*|/(?i:images)/(?i:remote)[^ ]*|/.*[?&](?i:imageUrl|StreamOptions|mediaSourceId|deviceProfile|ApiKey)=[^ ]*) HTTP/[0-9.]+" [1-5][0-9]{2}\b.*'';
        ignoreregex = ''^<HOST> - - \[[^\]]+\] "[^"]*[?&](?i:ApiKey|api_key)=[^ "]+ HTTP/[0-9.]+" .*'';
        ignorecommand = "${jellyfinKnownIp}/bin/jellyfin-known-ip check <HOST>";
        action = ''iptables-multiport[name=jellyfin-api-scanner, port="http,https", protocol=tcp]'';
        logpath = "/var/log/nginx/access.log";
        port = "http, https";
      };
    };
  };
}
