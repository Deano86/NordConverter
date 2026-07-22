# NordConverter

**Modified and maintained by Deano86**

NordConverter creates an importable WireGuard configuration from a temporary
NordLynx connection made by the official NordVPN Linux command-line client.

Version 2 is a new implementation built around the documented NordVPN and
WireGuard command-line interfaces. It replaces the earlier prototype rather than
continuing its source code.

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
sudo apt install wireguard-tools iproute2 curl jq
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
- live country lists from `nordvpn countries`;
- live country-specific city lists from `nordvpn cities COUNTRY`;
- live specialty-group lists from `nordvpn groups`;
- live recommended-server lists from NordVPN's server API;
- countries, country codes, cities, and country/city combinations;
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

NordConverter can run without the interactive destination menu. Named options
are recommended for scripts because they make the intended destination clear.

```bash
./NordConverter.sh --recommended --yes
./NordConverter.sh --country Canada --yes
./NordConverter.sh --country Germany --city Berlin --yes
./NordConverter.sh --server uk715 --yes
./NordConverter.sh --group p2p --country gb --yes
./NordConverter.sh --country Japan --output-dir ./profiles --yes
```

Positional destinations remain supported:

```bash
./NordConverter.sh Canada
./NordConverter.sh Germany Berlin
./NordConverter.sh uk715
```

### Complete NordConverter option reference

| Option | Value | Purpose |
| --- | --- | --- |
| `--recommended` | none | Use NordVPN's recommended server |
| `--country` | name or code | Select a country, such as `Canada`, `gb`, or `united_kingdom` |
| `--city` | city name | Select a city; it can be combined with `--country` |
| `--server` | server name | Select an exact server, such as `uk715` |
| `--group` | group name | Select a specialty group, such as `p2p` or `double_vpn` |
| `--output-dir` | directory | Choose where the generated profile is written |
| `--yes`, `-y` | none | Accept confirmation and existing-connection replacement prompts |
| `--list-countries` | none | Print the current NordVPN country list and exit |
| `--list-cities` | country | Print cities for one country and exit |
| `--list-groups` | none | Print the current specialty-group list and exit |
| `--list-servers` | none | Print recommended online NordLynx servers and exit |
| `--limit` | 1–100 | Set the maximum number of server results; default is `25` |
| `--no-color` | none | Disable terminal colours |
| `--help`, `-h` | none | Show built-in help |
| `--version`, `-v` | none | Show the NordConverter version |
| `--` | arguments | Pass all remaining arguments directly to `nordvpn connect` |

### Discover valid values

Values are supplied by the installed NordVPN client, so the live lists are more
reliable than a static list in this README:

```bash
./NordConverter.sh --list-countries
./NordConverter.sh --list-cities united_kingdom
./NordConverter.sh --list-groups
./NordConverter.sh --list-servers
./NordConverter.sh --list-servers --country united_kingdom --limit 20
```

Equivalent native NordVPN commands are:

```bash
nordvpn countries
nordvpn cities united_kingdom
nordvpn groups
```

The NordVPN Linux CLI does not currently expose a native command that enumerates
individual server hostnames. `--list-servers` therefore requests recommended
online servers from NordVPN's `api.nordvpn.com/v1/servers/recommendations`
endpoint and filters for NordLynx support. It displays:

- hostname;
- country;
- city;
- current reported load.

Server listing requires `curl` and `jq`. The endpoint is operated by NordVPN but
is separate from the Linux CLI and may change independently. NordConverter limits
requests to at most 100 records and does not download the complete server
catalogue.

In the interactive menu, choose **Server** to display this list and then type the
desired hostname. Both `uk715` and `uk715.nordvpn.com` are accepted; the suffix is
removed before the hostname is passed to the NordVPN client.

Common group values include `p2p`, `double_vpn`, `onion_over_vpn`, and
`dedicated_ip`. Availability depends on the account, region, and installed
NordVPN client.

### Advanced passthrough

The interactive **Advanced** choice splits the entered text into arguments and
passes them to `nordvpn connect` without evaluating them as shell commands.
It displays `nordvpn help connect` first, so the available native arguments match
the installed NordVPN client. Enter only the portion after `nordvpn connect`, not
the command itself.

Examples entered at the Option 7 prompt:

```text
uk715
united_kingdom london
--group p2p gb
--group double_vpn us
```

For non-interactive raw arguments, place `--` before the native NordVPN
connection arguments:

```bash
./NordConverter.sh --yes -- --group double_vpn gb
```

This executes the connection stage as if the destination arguments had been
supplied to:

```bash
nordvpn connect --group double_vpn gb
```

Because NordVPN may add or remove CLI options, use the installed client's help
for the authoritative raw-argument list:

```bash
nordvpn help connect
man nordvpn
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
