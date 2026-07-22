# NordConverter
**By Deano86**

<img width="479" height="307" alt="image" src="https://github.com/user-attachments/assets/60b79ffe-cdc0-4891-98fe-9a2c3bfc7270" />

`NordConverter.sh` is an interactive Bash script that logs in to the NordVPN
Linux client when needed, temporarily connects using NordLynx, and creates an
importable WireGuard `.conf` file.

## Attribution and licensing

NordConverter was originally based on
[NordVPN-Wireguard](https://github.com/sfiorini/NordVPN-Wireguard) by Stefano
Fiorini. It has since been substantially modified with an interactive menu,
integrated browser/callback/token login handling, input validation, safer
cleanup, secure output permissions, and rewritten documentation.

The current NordConverter edition and its modifications are maintained by
**Deano86**.

No license file was identified in the upstream repository when this version was
prepared. Under GitHub's licensing guidance, a public repository without a
license remains subject to standard copyright restrictions. This attribution
does not itself grant permission to reproduce or distribute upstream code. See
[`NOTICE.md`](NOTICE.md) for the full notice.

> This is an unofficial helper. A generated configuration contains a private key.
> Keep it secret, never commit it to source control, and delete it when it is no
> longer needed.

## Install on Ubuntu

This guide supports Ubuntu 20.04 or newer.

```bash
sudo apt update
sudo apt install wireguard-tools iproute2 curl
sh <(curl -sSf https://downloads.nordcdn.com/apps/linux/install.sh)
```

If NordVPN reports that access to `nordvpnd.sock` is denied, add your user to the
`nordvpn` group and reboot:

```bash
sudo usermod -aG nordvpn "$USER"
sudo reboot
```

## Start the generator

Make the script executable, then run it:

```bash
chmod +x NordConverter.sh
./NordConverter.sh
```

NordConverter uses a coloured ASCII terminal interface when output is connected
to a terminal. Set `NO_COLOR=1` for plain output:

```bash
NO_COLOR=1 ./NordConverter.sh
```

The script checks whether the NordVPN CLI is already authenticated. If it is not,
it presents three login choices before generating a configuration.

### Login choice 1: browser on the Ubuntu computer

Choose **Log in using a browser on this computer**. Complete the sign-in page and
select **Continue**, then return to the terminal and press Enter. Nothing needs to
be copied into the script.

### Login choice 2: callback link

Use this when the browser login completes but does not return control to the
NordVPN Linux application, or when the browser is on another device:

1. Complete the NordVPN sign-in page.
2. On the final page, right-click **Continue**.
3. Select **Copy link address**.
4. Return to the script and choose the callback option.
5. Paste the complete link beginning with `nordvpn://`.

The callback is submitted directly to `nordvpn login --callback` and is not saved.
Treat the link as a temporary secret and do not share it.

### Login choice 3: access token

This is convenient for a headless server:

1. Sign in to Nord Account in a browser.
2. Open **NordVPN**.
3. Open **Advanced settings** and select **Get access token**.
4. Generate and copy a token.
5. Choose the token option in the script and paste it at the hidden prompt.

The token is passed to `nordvpn login --token` and is not written to a file. A
non-expiring token should only be used with MFA enabled on the Nord account.

## Choose a server

After login, the menu offers:

1. Recommended server
2. Country or country code
3. City
4. Country and city
5. Exact server, such as `jp35`
6. Specialty group, such as `double_vpn` or `p2p`
7. Custom NordVPN connection arguments

The script shows the selected destination and asks for confirmation before it
connects.

## Direct command-line use

Arguments are passed unchanged to `nordvpn connect`. If login is required and the
command is running in a terminal, the login menu is displayed first.

```bash
./NordConverter.sh Canada
./NordConverter.sh Germany Berlin
./NordConverter.sh jp35
./NordConverter.sh --group double_vpn us
```

Run `./NordConverter.sh --help` for built-in help.

## Generated configuration

The resulting file is named `NordVPN-<server>.conf`. The script:

- sets NordLynx as the connection technology;
- reads the active tunnel address, peer key, private key, and hostname;
- disconnects the temporary NordVPN connection, including after most errors;
- creates the configuration with permissions `600`.

Import the `.conf` file into a WireGuard client. Never share the generated file
because it contains the private key used by that tunnel.

## Official references

- [Install and use NordVPN on Linux](https://support.nordvpn.com/hc/en-us/articles/20196094470929-How-to-install-the-NordVPN-app-on-Linux-distributions)
- [Log in on a headless Linux device using an access token](https://support.nordvpn.com/hc/en-us/articles/20226600447633-How-to-log-in-to-NordVPN-on-Linux-devices-without-a-GUI)
- [GitHub guidance for repositories without a license](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)
