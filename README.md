NordVPN to WireGuard configuration generator

An interactive Bash script that temporarily connects with the NordVPN Linux CLI,
reads the active NordLynx parameters, and creates an importable WireGuard `.conf`
file.

> This is an unofficial helper. The generated file contains a private key. Keep it
> secret, do not commit it to source control, and delete it when no longer needed.

## Install on Ubuntu

```bash
sudo apt update
sudo apt install wireguard-tools iproute2 curl
sh <(curl -sSf https://downloads.nordcdn.com/apps/linux/install.sh)
nordvpn login
```

If access to `nordvpnd.sock` is denied, run `sudo usermod -aG nordvpn "$USER"`
and reboot.

## Interactive use

```bash
chmod +x NordVpnToWireguard.sh
./NordVpnToWireguard.sh
```

Choose a recommended server, country, city, exact server, or specialty group from
the menu. The script asks for confirmation before connecting.

## Direct use

Arguments are passed unchanged to `nordvpn connect`:

```bash
./NordVpnToWireguard.sh Canada
./NordVpnToWireguard.sh Germany Berlin
./NordVpnToWireguard.sh jp35
./NordVpnToWireguard.sh --group double_vpn us
```

Run `./NordVpnToWireguard.sh --help` for help. The generated
`NordVPN-<server>.conf` is created with permissions `600`; never share or commit
it because it contains a private key.
