{ config, lib, pkgs, ... }:

let
  cfg = config.my.monitoring;
  notifications = cfg.notifications;
in
{
  options.my.monitoring.zfsAlerts = {
    enable = lib.mkEnableOption "ZFS ZED monitoring notifications";

    gotifyPriority = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "Gotify priority for ZFS ZED notifications.";
    };
  };

  config = lib.mkIf cfg.zfsAlerts.enable {
    services.zfs.zed = {
      enableMail = true;
      settings = {
        ZED_EMAIL_ADDR = [ notifications.smtp.from ];
        ZED_EMAIL_OPTS = "'@SUBJECT@'";
        ZED_NOTIFY_VERBOSE = true;
        ZED_NOTIFY_DATA = true;

        ZED_EMAIL_PROG = "${pkgs.writeShellScript "zed-notify" ''
          SUBJECT="$1"
          BODY=$(${pkgs.coreutils}/bin/cat)
          GOTIFY_KEY=$(${pkgs.coreutils}/bin/cat ${notifications.gotify.tokenFile})

          ${pkgs.curl}/bin/curl -s -X POST "${notifications.gotify.url}" \
            -H "X-Gotify-Key: $GOTIFY_KEY" \
            -F "title=$SUBJECT" \
            -F "message=$BODY" \
            -F "priority=${toString cfg.zfsAlerts.gotifyPriority}" > /dev/null

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
