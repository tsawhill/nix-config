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
      port = 587;
      tls_starttls = true;
      user = "server@tsawhill.org";
      from = "server@tsawhill.org";
      passwordeval = "cat /run/secrets/smtp_password_server";
    };
  };

  services.smartd = {
    enable = true;
    notifications = {
      mail = {
        enable = true;
        recipient = "me@tsawhill.org";
        mailer = "${pkgs.writeShellScript "smartd-notify" ''
          if [ "$1" = "-s" ]; then
              SUBJECT="$2"
          else
              SUBJECT="SMART Alert"
          fi

          BODY=$(${pkgs.coreutils}/bin/cat)
          GOTIFY_KEY=$(${pkgs.coreutils}/bin/cat /run/secrets/gotify_token_zfs)

          # 1. Gotify Push (Priority 8 for hardware issues)
          ${pkgs.curl}/bin/curl -s -X POST "https://gotify.tsawhill.org/message" \
            -H "X-Gotify-Key: $GOTIFY_KEY" \
            -F "title=$SUBJECT" \
            -F "message=$BODY" \
            -F "priority=8" > /dev/null
            
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
  };
}
