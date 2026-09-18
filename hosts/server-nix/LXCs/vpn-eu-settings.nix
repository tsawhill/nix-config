{
  # Bootstrap the container first, then add the encrypted files described in
  # docs/airvpn-eu-deluge.md. Enable the gateway before moving Deluge.
  gatewayEnable = false;
  delugeEnable = false;
  # Must be [Peer] PublicKey, not the AirVPN device's own public key.
  # AirVPN shares one server key across all endpoints; na1 uses this same key
  # for four cities. Confirm it against the downloaded CH config anyway.
  peerPublicKey = "PyLCXAQT8KkM4T+dUsOQfn+Ub3pGxfGlxkIApuig+hk=";
  # [Interface] Address from the new device's own WireGuard config. Per-device,
  # so it cannot be guessed or copied from another gateway.
  address = "";
}
