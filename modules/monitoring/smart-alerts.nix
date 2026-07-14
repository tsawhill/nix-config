{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.monitoring;
  notifications = cfg.notifications;
in
{
  # SMART daemon notifications. smartd gives the mailer a subject through
  # `-s <subject>` and writes the message body on stdin; the wrapper sends both
  # Gotify and SMTP notifications.
  options.my.monitoring.smartAlerts = {
    enable = lib.mkEnableOption "SMART monitoring notifications";

    gotifyPriority = lib.mkOption {
      type = lib.types.int;
      default = 8;
      description = "Gotify priority for SMART notifications.";
    };
  };

  config = lib.mkIf cfg.smartAlerts.enable {
    services.smartd = {
      enable = true;
      defaults.monitored = "-a -W 0,0,45";
      notifications.mail = {
        enable = true;
        recipient = notifications.recipientEmail;
        # Secrets are read at runtime from SOPS-managed files, keeping tokens
        # and SMTP passwords out of the Nix store.
        mailer = "${pkgs.writeShellScript "smartd-notify" ''
          if [ "$1" = "-s" ]; then
            SUBJECT="$2"
          else
            SUBJECT="SMART Alert"
          fi

          BODY=$(${pkgs.coreutils}/bin/cat)
          GOTIFY_KEY=$(${pkgs.coreutils}/bin/cat ${notifications.gotify.tokenFile})

          ${pkgs.curl}/bin/curl -s -X POST "${notifications.gotify.url}" \
            -H "X-Gotify-Key: $GOTIFY_KEY" \
            -F "title=$SUBJECT" \
            -F "message=$BODY" \
            -F "priority=${toString cfg.smartAlerts.gotifyPriority}" > /dev/null

          (
            echo "To: ${notifications.recipientEmail}"
            echo "Subject: $SUBJECT"
            echo ""
            echo "$BODY"
          ) | ${pkgs.msmtp}/bin/msmtp "${notifications.recipientEmail}"
        ''}";
      };
    };
  };
}
