{ config, lib, ... }:

let
  cfg = config.my.monitoring;
  notifications = cfg.notifications;
  smtp = notifications.smtp;
  gotify = notifications.gotify;

  # The SMTP account is only needed when at least one alerting feature is
  # enabled. ZFS maintenance can use this module tree without configuring mail.
  alertsEnabled = cfg.zfsAlerts.enable || cfg.smartAlerts.enable;

  secretPathType = with lib.types; nullOr (coercedTo path toString str);
in
{
  # Shared notification settings. Feature modules consume these paths and
  # addresses, so each host can reuse the same monitoring code with its own
  # SOPS secrets and delivery endpoints.
  options.my.monitoring.notifications = {
    recipientEmail = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Email recipient for monitoring notifications.";
    };

    smtp = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "localhost";
        description = "SMTP server hostname.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 587;
        description = "SMTP server port.";
      };

      user = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "SMTP username.";
      };

      from = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "SMTP envelope sender.";
      };

      passwordFile = lib.mkOption {
        type = secretPathType;
        default = null;
        description = "File containing the SMTP password.";
      };

      auth = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to authenticate to the SMTP server.";
      };

      tls = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to use TLS for SMTP.";
      };

      tlsStarttls = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to use STARTTLS for SMTP.";
      };
    };

    gotify = {
      url = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Gotify message endpoint URL.";
      };

      tokenFile = lib.mkOption {
        type = secretPathType;
        default = null;
        description = "File containing the Gotify application token.";
      };
    };
  };

  config = lib.mkIf alertsEnabled {
    # Fail evaluation early instead of deploying an alerting service that cannot
    # deliver messages.
    assertions = [
      {
        assertion = notifications.recipientEmail != null;
        message = "my.monitoring.notifications.recipientEmail must be set when monitoring alerts are enabled.";
      }
      {
        assertion = smtp.user != null;
        message = "my.monitoring.notifications.smtp.user must be set when monitoring alerts are enabled.";
      }
      {
        assertion = smtp.from != null;
        message = "my.monitoring.notifications.smtp.from must be set when monitoring alerts are enabled.";
      }
      {
        assertion = smtp.passwordFile != null;
        message = "my.monitoring.notifications.smtp.passwordFile must be set when monitoring alerts are enabled.";
      }
      {
        assertion = gotify.url != null;
        message = "my.monitoring.notifications.gotify.url must be set when monitoring alerts are enabled.";
      }
      {
        assertion = gotify.tokenFile != null;
        message = "my.monitoring.notifications.gotify.tokenFile must be set when monitoring alerts are enabled.";
      }
    ];

    # ZED and smartd both send email through msmtp. Gotify is posted directly by
    # each feature-specific wrapper script because the priority differs by alert
    # type.
    programs.msmtp = {
      enable = true;
      accounts.default = {
        auth = smtp.auth;
        tls = smtp.tls;
        host = smtp.host;
        port = smtp.port;
        tls_starttls = smtp.tlsStarttls;
        user = smtp.user;
        from = smtp.from;
        passwordeval = "cat ${smtp.passwordFile}";
      };
    };
  };
}
