{ config, pkgs, ... }:

let
  alertEmail = "me@tsawhill.org";
in
{
  programs.msmtp = {
    enable = true;
    accounts.default = {
      auth = true;
      tls = true;
      host = "smtp.purelymail.com";
      port = 465;
      tls_starttls = false;
      user = "server@tsawhill.org";
      from = "server@tsawhill.org";
      passwordeval = "cat /run/secrets/smtp_password";
    };
  };

  services.zfs.zed = {
    enableMail = true;
    settings = {
      ZED_EMAIL_ADDR = [ "root" ];
      ZED_EMAIL_OPTS = "'@SUBJECT@'";
      ZED_NOTIFY_VERBOSE = true;
      ZED_NOTIFY_DATA = true;

      ZED_EMAIL_PROG = "${pkgs.writeShellScript "zed-notify" ''
        SUBJECT="$1"
        BODY=$(${pkgs.coreutils}/bin/cat)
        GOTIFY_KEY=$(${pkgs.coreutils}/bin/cat /run/secrets/gotify_key)

        # 1. Gotify Push
        ${pkgs.curl}/bin/curl -s -X POST "https://gotify.tsawhill.org/message" \
          -H "X-Gotify-Key: $GOTIFY_KEY" \
          -F "title=$SUBJECT" \
          -F "message=$BODY" \
          -F "priority=5" > /dev/null
          
        # 2. SMTP Email
        (
          echo "To: ${alertEmail}"
          echo "Subject: $SUBJECT"
          echo ""
          echo "$BODY"
        ) | ${pkgs.msmtp}/bin/msmtp "${alertEmail}"
      ''}";
    };
  };
}
