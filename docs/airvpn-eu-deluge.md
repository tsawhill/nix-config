# Swiss AirVPN gateway and Deluge cutover

The new Incus guest is `networking-vpn-out-eu1-nix`, proposed LAN address
`10.73.73.44`, MAC `02:5f:6e:64:80:44`. Its dedicated AirVPN device address
is `10.169.2.22/32`. Only Swiss (`CH`) endpoints are selected, including
automatic failover. The NA gateway and its clients are independent.

`hosts/server-nix/LXCs/vpn-eu-settings.nix` contains two rollout switches:
`gatewayEnable` and `delugeEnable`. Both start false so the container can
bootstrap without secrets and Deluge is not routed to an unprovisioned guest.
The new Colmena host is manual-only until onboarding is finished.

## 1. Bootstrap

Check that the proposed LAN IP is unused. Add an OPNsense DHCP reservation
for the IP/MAC above: the declarative DHCP replacement is still disabled.
Topology alone does not install a reservation on OPNsense.

Commit and push the reviewed configuration. Deploy `adguard-nix` to install
the new DNS rewrite, and `build-nix` to update nixos-factory's embedded
topology. Each deployment requires approval when performed by an agent.

On build-nix, run:

```sh
nixos-factory
```

Choose **create**, hostname **networking-vpn-out-eu1-nix**, and the desired
root storage pool. Use the declared IP/MAC. The factory creates the guest,
records its SSH trust and public age recipient in `.sops.yaml`, updates
build-nix, and deploys the guest's bootstrap configuration. It performs
deployments, so an agent must obtain approval before running it.

Keep `gatewayEnable = false` during this step. No AirVPN secret is needed
for the initial container deployment.

## 2. Add the encrypted runtime values

After the factory adds `&networking-vpn-out-eu1-nix`, uncomment the
`*networking-vpn-out-eu1-nix` recipient in BOTH new creation rules at the end
of `.sops.yaml`, before creating the files. The gateway credential file is
for build-nix and the gateway; the port file is additionally for deluge-nix.

Run these commands yourself from the repository root. Agents must not read
the values or run SOPS.

```sh
sops modules/secrets/server/LXCs/networking-vpn-out-eu1-nix.yaml
```

Enter this structure, replacing the placeholders with values from the
dedicated device's downloaded WireGuard config and a Gotify application:

```yaml
wireguard_private_key: "<Interface PrivateKey>"
wireguard_preshared_key: "<Peer PresharedKey>"
gotify_token: "<Gotify application token>"
```

Reserve an AirVPN TCP+UDP port for the **new device**, keeping the remote
and local port the same. Using a new reservation avoids reusing the port
already present in this repository's history.

```sh
sops modules/secrets/server/LXCs/deluge-vpn.yaml
```

```yaml
forwarded_port: "<reserved port number, digits only>"
```

Only the encrypted YAML files should enter Git. The gateway uses a root-only
SOPS-rendered nftables fragment; Deluge reads the same secret at startup and
for its firewall. The number is never evaluated into the Nix store. It is
still visible to local administrators and remote peers; encryption here
prevents publishing the reservation in source, not observation of traffic.

## 3. Enable the gateway, then Deluge

1. Set `gatewayEnable = true`, leaving `delugeEnable = false`. Commit and
   push the config and encrypted files. Deploy `networking-vpn-out-eu1-nix`.
2. Check `systemctl status vpn-egress-initialise.service` and use
   `sudo airvpn-switch` on that host to verify a working Swiss exit.
3. Set `delugeEnable = true`, commit and push, then deploy `deluge-nix`.
   Deluge now has its default route through `.44`, with LAN and remote
   management routes retained. IPv6 is disabled by the VPN client module.
   Its existing `/root/.config/deluge/core.conf` is preserved except for
   listen ports, random-port selection, UPnP, and NAT-PMP.
4. On Deluge, verify `ip -4 route get 1.1.1.1` goes via `.44` and
   `curl -4 https://1.1.1.1/cdn-cgi/trace` shows the gateway's VPN exit.
   Verify the reserved port using AirVPN's port checker while Deluge is
   listening. Keep output containing the port private.
5. Verify `vpn-egress-health.timer` is active. An approved outage test should
   show Deluge losing external connectivity while the tunnel is unavailable,
   then recovering through another Swiss endpoint. Existing peers may need
   to reconnect after an exit change.

After onboarding, the gateway's Colmena tag can change from `null` to
`"weekly"`. Never deploy Deluge's cutover before the gateway passes checks.

The previous port remains in Git history. No history rewrite is performed.
