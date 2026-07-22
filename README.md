# NordConverter

**Modified and maintained by Deano86**

NordConverter creates an importable WireGuard configuration from a temporary
NordLynx connection made by the official NordVPN Linux command-line client.

Version 2 is a new implementation built around the documented NordVPN and
WireGuard command-line interfaces. It replaces the earlier prototype rather than
continuing its source code.

Current release: **2.0.1**

> NordConverter is unofficial and is not affiliated with or endorsed by Nord
> Security or the WireGuard project. Generated profiles contain private keys.

## Requirements

- Ubuntu 20.04 or newer, or a comparable Linux distribution
- Bash 4 or newer
- A valid NordVPN subscription
- The NordVPN Linux CLI
- WireGuard tools and `iproute2`

On Ubuntu:

```bash
sudo apt update
sudo apt install wireguard-tools iproute2 curl
sh <(curl -sSf https://downloads.nordcdn.com/apps/linux/install.sh)
```

If NordVPN cannot access `nordvpnd.sock`:

```bash
sudo usermod -aG nordvpn "$USER"
sudo reboot
```

## Run

```bash
chmod +x NordConverter.sh
./NordConverter.sh
```

The interface guides you through login, destination selection, confirmation,
connection, and export. It supports:

- recommended servers;
- countries and country codes;
- cities and country/city combinations;
- exact server names;
- specialty groups such as P2P and Double VPN;
- advanced NordVPN connection arguments.

## Login assistant

If the NordVPN CLI is not authenticated, NordConverter offers:

1. **Browser login** — complete the standard Nord Account flow.
2. **Callback login** — paste the final link beginning with `nordvpn://`.
3. **Access token** — enter a token at a hidden prompt on a headless machine.

Login values are submitted to the official NordVPN CLI and are not saved by
NordConverter.

## Command-line use

```bash
./NordConverter.sh Canada
./NordConverter.sh Germany Berlin
./NordConverter.sh --group p2p gb
./NordConverter.sh --output-dir ./profiles Japan
```

Use `--` when a NordVPN argument conflicts with a NordConverter option:

```bash
./NordConverter.sh -- --group double_vpn us
```

Other options:

```text
--output-dir DIRECTORY   Select the profile directory
--no-color               Disable terminal colours
-h, --help               Show help
-v, --version            Show the version
```

The standard `NO_COLOR` environment variable is also respected:

```bash
NO_COLOR=1 ./NordConverter.sh
```

## Safety behaviour

NordConverter:

- checks dependencies before connecting;
- asks before replacing an existing NordVPN connection;
- reads the active interface through `wg showconf`;
- writes through a private temporary file and moves it into place atomically;
- never overwrites an existing profile;
- applies file mode `600`;
- attempts to disconnect every temporary session, including after errors.

Generated files are named `NordVPN-<server>.conf`. Treat every generated profile
as a secret because it contains tunnel key material.

## Project status and licensing

See [NOTICE.md](NOTICE.md) for the implementation-history statement, project
credit, third-party names, and licensing status. No rights to NordVPN, NordLynx,
or WireGuard are claimed.

## Official references

- [NordVPN Linux installation and CLI usage](https://support.nordvpn.com/hc/en-us/articles/20196094470929-How-to-install-the-NordVPN-app-on-Linux-distributions)
- [NordVPN access-token login](https://support.nordvpn.com/hc/en-us/articles/20226600447633-How-to-log-in-to-NordVPN-on-Linux-devices-without-a-GUI)
- [WireGuard command-line tools](https://www.wireguard.com/quickstart/)
- [WireGuard trademark policy](https://www.wireguard.com/trademark-policy/)
