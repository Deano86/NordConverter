#!/usr/bin/env bash

# NordConverter
#
# Originally based on NordVPN-Wireguard by Stefano Fiorini:
# https://github.com/sfiorini/NordVPN-Wireguard
#
# This version has been substantially modified with an interactive menu,
# integrated login handling, validation, safer cleanup, and revised
# documentation. See NOTICE.md for attribution and licensing information.

set -Eeuo pipefail

readonly VERSION="1.1.0"
readonly PROGRAM_NAME="${0##*/}"
readonly INTERFACE_NAME="nordlynx"
readonly DEFAULT_DNS="103.86.96.100, 103.86.99.100"

connected_by_script=false

print_banner() {
    printf '\nNordConverter v%s - NordVPN to WireGuard generator\n' "$VERSION"
    printf '%s\n\n' '------------------------------------------------'
}

print_help() {
    cat <<EOF
Usage:
  $PROGRAM_NAME                         Open the interactive menu
  $PROGRAM_NAME [NordVPN destination]   Generate directly

Examples:
  $PROGRAM_NAME
  $PROGRAM_NAME Canada
  $PROGRAM_NAME Germany Berlin
  $PROGRAM_NAME jp35
  $PROGRAM_NAME --group double_vpn us

Options:
  -h, --help       Show this help
  -v, --version    Show the version

Direct destination arguments are passed to "nordvpn connect" unchanged.
If no NordVPN session exists, an interactive login menu is displayed first.
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

need_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command '$1' was not found."
}

is_logged_in() {
    nordvpn account >/dev/null 2>&1
}

login_menu() {
    local choice callback_url access_token

    [[ -t 0 ]] || die "NordVPN is not logged in. Run '$PROGRAM_NAME' in an interactive terminal first."

    while ! is_logged_in; do
        cat <<'EOF'

No active NordVPN login was found.

  1) Log in using a browser on this computer
  2) Paste a nordvpn:// callback link
  3) Log in with an access token (headless/server)
  4) Quit

EOF
        read -r -p 'Choose [1-4]: ' choice

        case "$choice" in
            1)
                printf '\nOpening the NordVPN browser login...\n'
                nordvpn login || true
                printf '\nFinish signing in in the browser and select Continue.\n'
                read -r -p 'Press Enter after completing the browser login...'
                ;;
            2)
                printf '\nAfter signing in, right-click the final Continue button,\n'
                printf 'choose Copy link address, then paste the nordvpn:// link below.\n'
                callback_url=$(prompt_nonempty 'Callback link: ')
                if [[ "$callback_url" != nordvpn://* ]]; then
                    printf 'That does not look like a nordvpn:// callback link.\n' >&2
                    continue
                fi
                if ! nordvpn login --callback "$callback_url"; then
                    printf 'Callback login failed. Generate a fresh link and try again.\n' >&2
                fi
                unset callback_url
                ;;
            3)
                printf '\nGenerate a token in Nord Account under:\n'
                printf 'NordVPN -> Advanced settings -> Get access token.\n'
                read -r -s -p 'Access token (input hidden): ' access_token
                printf '\n'
                if [[ -z "$access_token" ]]; then
                    printf 'No token was entered.\n' >&2
                elif ! nordvpn login --token "$access_token"; then
                    printf 'Token login failed. Check the token and try again.\n' >&2
                fi
                unset access_token
                ;;
            4|q|Q)
                printf 'Cancelled.\n'
                exit 0
                ;;
            *) printf 'Please choose a number from 1 to 4.\n' >&2 ;;
        esac
    done

    printf '\nNordVPN login confirmed.\n'
}

ensure_logged_in() {
    is_logged_in && return
    login_menu
}

cleanup() {
    local exit_code=$?
    if [[ "$connected_by_script" == true ]]; then
        printf 'Disconnecting the temporary NordVPN connection...\n'
        nordvpn disconnect >/dev/null 2>&1 || \
            printf 'Warning: NordVPN could not be disconnected automatically.\n' >&2
    fi
    exit "$exit_code"
}

prompt_nonempty() {
    local prompt=$1 value
    while true; do
        read -r -p "$prompt" value
        [[ -n "$value" ]] && { printf '%s' "$value"; return; }
        printf 'Please enter a value.\n' >&2
    done
}

interactive_destination() {
    local choice country city server group custom
    while true; do
        cat >&2 <<'EOF'
What kind of connection would you like?

  1) Recommended server
  2) Country or country code
  3) City
  4) Country and city
  5) Exact server (for example, jp35)
  6) Specialty server group
  7) Enter custom NordVPN connect arguments
  8) Quit

EOF
        read -r -p 'Choose [1-8]: ' choice
        case "$choice" in
            1) CONNECT_ARGS=(); return ;;
            2) country=$(prompt_nonempty 'Country or code: '); CONNECT_ARGS=("$country"); return ;;
            3) city=$(prompt_nonempty 'City: '); CONNECT_ARGS=("$city"); return ;;
            4)
                country=$(prompt_nonempty 'Country: ')
                city=$(prompt_nonempty 'City: ')
                CONNECT_ARGS=("$country" "$city")
                return
                ;;
            5) server=$(prompt_nonempty 'Server name: '); CONNECT_ARGS=("$server"); return ;;
            6)
                printf '\nCommon groups: double_vpn, p2p, onion_over_vpn, dedicated_ip\n' >&2
                group=$(prompt_nonempty 'Group: ')
                read -r -p 'Optional country/code (press Enter to skip): ' country
                CONNECT_ARGS=(--group "$group")
                [[ -n "$country" ]] && CONNECT_ARGS+=("$country")
                return
                ;;
            7)
                custom=$(prompt_nonempty 'Arguments: ')
                # Split into words without evaluating input as shell code.
                read -r -a CONNECT_ARGS <<< "$custom"
                return
                ;;
            8|q|Q) printf 'Cancelled.\n' >&2; exit 0 ;;
            *) printf 'Please choose a number from 1 to 8.\n\n' >&2 ;;
        esac
    done
}

confirm_destination() {
    local description='recommended server' answer
    if ((${#CONNECT_ARGS[@]})); then
        printf -v description '%q ' "${CONNECT_ARGS[@]}"
        description=${description% }
    fi
    printf '\nDestination: %s\n' "$description"
    read -r -p 'Generate this configuration? [Y/n]: ' answer
    case "${answer:-y}" in
        y|Y|yes|YES|Yes) ;;
        *) printf 'Cancelled.\n'; exit 0 ;;
    esac
}

wireguard_address() {
    local address
    if command -v ip >/dev/null 2>&1; then
        address=$(ip -o -4 addr show dev "$INTERFACE_NAME" 2>/dev/null | awk 'NR == 1 {print $4}')
    elif command -v ifconfig >/dev/null 2>&1; then
        address=$(ifconfig "$INTERFACE_NAME" 2>/dev/null | awk '/inet / {print $2; exit}')
        [[ -n "$address" ]] && address="${address}/32"
    else
        die "Neither 'ip' nor 'ifconfig' is installed. Install the iproute2 package."
    fi
    [[ -n "$address" ]] || die "Could not read the IPv4 address from $INTERFACE_NAME."
    printf '%s' "$address"
}

status_value() {
    local label=$1
    awk -F': *' -v wanted="$label" '$1 == wanted {print $2; exit}'
}

generate_config() {
    local address private_key public_key status endpoint server_name output_file
    printf '\nSelecting NordLynx technology...\n'
    nordvpn set technology NordLynx >/dev/null || die "Could not enable NordLynx."

    printf 'Connecting to NordVPN to collect connection parameters...\n'
    if ((${#CONNECT_ARGS[@]})); then
        nordvpn connect "${CONNECT_ARGS[@]}" || die "Unable to connect to NordVPN."
    else
        nordvpn connect || die "Unable to connect to NordVPN."
    fi
    connected_by_script=true

    address=$(wireguard_address)
    private_key=$(sudo wg show "$INTERFACE_NAME" private-key)
    public_key=$(sudo wg show "$INTERFACE_NAME" peers | awk 'NR == 1 {print; exit}')
    status=$(nordvpn status)
    endpoint=$(status_value 'Hostname' <<< "$status")
    [[ -n "$private_key" ]] || die 'Could not obtain the WireGuard private key.'
    [[ -n "$public_key" ]] || die 'Could not obtain the WireGuard peer public key.'
    [[ -n "$endpoint" ]] || die 'Could not obtain the NordVPN server hostname.'

    server_name=${endpoint%%.*}
    server_name=${server_name//[^A-Za-z0-9._-]/_}
    output_file="NordVPN-${server_name}.conf"
    umask 077
    cat > "$output_file" <<EOF
[Interface]
Address = $address
PrivateKey = $private_key
ListenPort = 51820
DNS = $DEFAULT_DNS

[Peer]
PublicKey = $public_key
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $endpoint:51820
PersistentKeepalive = 25
EOF
    chmod 600 "$output_file"

    nordvpn disconnect >/dev/null || die "The config was created, but NordVPN could not be disconnected."
    connected_by_script=false
    printf '\nSuccess: %s was created with permissions 600.\n' "$output_file"
    printf 'Import it into a WireGuard client to use it.\n'
}

main() {
    CONNECT_ARGS=()
    case "${1:-}" in
        -h|--help) print_help; exit 0 ;;
        -v|--version) printf 'NordConverter v%s\n' "$VERSION"; exit 0 ;;
    esac
    need_command nordvpn
    need_command wg
    need_command awk
    need_command sudo
    trap cleanup EXIT INT TERM

    if (($#)); then
        CONNECT_ARGS=("$@")
    else
        print_banner
        interactive_destination
        confirm_destination
    fi

    ensure_logged_in
    generate_config
}

main "$@"
