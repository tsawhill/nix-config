{
  sops.defaultSopsFile = ./secrets.yaml;
  sops.secrets = {
    gotify_key = { };
    smtp_email = { };
    smtp_password = { };
  };
}
