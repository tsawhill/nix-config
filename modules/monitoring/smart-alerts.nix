{ config, lib, pkgs, ... }:

let
  cfg = config.my.monitoring;
  notifications = cfg.notifications;
in
{
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
      notifications.mail = {
        enable = true;
        recipient = notifications.recipientEmail;
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
