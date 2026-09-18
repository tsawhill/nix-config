{
  # Bootstrap the container first, then add the encrypted files described in
  # docs/airvpn-eu-deluge.md. Enable the gateway before moving Deluge.
  gatewayEnable = false;
  delugeEnable = false;
  # Must be [Peer] PublicKey, not the AirVPN device's own public key.
  peerPublicKey = "PyLCXAQT8KkM4T+dUsOQfn+Ub3pGxfGlxkIApuig+hk=";
}
