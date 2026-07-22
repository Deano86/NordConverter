#!/usr/bin/env bash

# NordConverter
# By Deano86
#
# Originally based on NordVPN-Wireguard by Stefano Fiorini:
# https://github.com/sfiorini/NordVPN-Wireguard
#
# This version has been substantially modified with an interactive menu,
# integrated login handling, validation, safer cleanup, and revised
# documentation. See NOTICE.md for attribution and licensing information.

set -Eeuo pipefail

readonly VERSION="1.2.0"
readonly PROGRAM_NAME="${0##*/}"
readonly INTERFACE_NAME="nordlynx"
readonly DEFAULT_DNS="103.86.96.100, 103.86.99.100"

connected_by_script=false

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_CYAN=$'\033[1;36m'
    C_BLUE=$'\033[1;34m'
    C_GREEN=$'\033[1;32m'
    C_YELLOW=$'\033[1;33m'
    C_RED=$'\033[1;31m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RESET=$'\033[0m'
else
    C_CYAN=''
    C_BLUE=''
    C_GREEN=''
    C_YELLOW=''
    C_RED=''
    C_BOLD=''
    C_DIM=''
    C_RESET=''
fi

readonly C_CYAN C_BLUE C_GREEN C_YELLOW C_RED C_BOLD C_DIM C_RESET

print_banner() {
    printf '\n%s' "$C_CYAN"
    cat <<'EOF'
 _   _               _  ____                          _
| \ | | ___  _ __ __| |/ ___|___  _ ____   _____ _ __| |_ ___ _ __
|  \| |/ _ \| '__/ _` | |   / _ \| '_ \ \ / / _ \ '__| __/ _ \ '__|
| |\  | (_) | | | (_| | |__| (_) | | | \ V /  __/ |  | ||  __/ |
|_| \_|\___/|_|  \__,_|\____\___/|_| |_|\_/ \___|_|   \__\___|_|
EOF
    printf '%s' "$C_RESET"
    printf '%s\n' '------------------------------------------------------------------------'
    printf '  %sNordVPN -> WireGuard configuration generator%s' "$C_BOLD" "$C_RESET"
    printf '  %sv%s%s\n' "$C_DIM" "$VERSION" "$C_RESET"
    printf '  %sBy Deano86%s\n' "$C_DIM" "$C_RESET"
    printf '%s\n\n' '------------------------------------------------------------------------'
}

print_section() {
    printf '\n%s== %s ==%s\n\n' "$C_BLUE" "$1" "$C_RESET"
}

info() {
    printf '%s[i]%s %s\n' "$C_BLUE" "$C_RESET" "$*"
}

success() {
    printf '%s[+]%s %s\n' "$C_GREEN" "$C_RESET" "$*"
}

warn() {
    printf '%s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2
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
    printf '%s[x]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2
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
        print_section 'NORDVPN LOGIN'
        cat <<'EOF'
  [1] Browser login       Sign in on this computer
  [2] Callback link       Paste the final nordvpn:// link
  [3] Access token        Best for a headless server
  [4] Quit
EOF
        printf '\n'
        read -r -p "${C_BOLD}[?] Choose an option [1-4]: ${C_RESET}" choice

        case "$choice" in
            1)
                info 'Opening the NordVPN browser login...'
                nordvpn login || true
                printf '\nFinish signing in, select Continue, then return here.\n'
                read -r -p "${C_BOLD}[?] Press Enter when login is complete...${C_RESET}"
                ;;
            2)
                printf '\nAfter signing in, right-click the final Continue button,\n'
                printf 'choose Copy link address, then paste the nordvpn:// link below.\n'
                callback_url=$(prompt_nonempty 'Callback link: ')
                if [[ "$callback_url" != nordvpn://* ]]; then
                    warn 'That does not look like a nordvpn:// callback link.'
                    continue
                fi
                if ! nordvpn login --callback "$callback_url"; then
                    warn 'Callback login failed. Generate a fresh link and try again.'
                fi
                unset callback_url
                ;;
            3)
                printf '\nGenerate a token in Nord Account under:\n'
                printf 'NordVPN -> Advanced settings -> Get access token.\n'
                read -r -s -p 'Access token (input hidden): ' access_token
                printf '\n'
                if [[ -z "$access_token" ]]; then
                    warn 'No token was entered.'
                elif ! nordvpn login --token "$access_token"; then
                    warn 'Token login failed. Check the token and try again.'
                fi
                unset access_token
                ;;
            4|q|Q)
                printf 'Cancelled.\n'
                exit 0
                ;;
            *) warn 'Please choose a number from 1 to 4.' ;;
        esac
    done

    printf '\n'
    success 'NordVPN login confirmed.'
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
        print_section 'SELECT A DESTINATION' >&2
        cat >&2 <<'EOF'
  [1] Recommended         Fastest available server
  [2] Country             Country name or two-letter code
  [3] City                Fastest server in a city
  [4] Country + city      Narrow the location precisely
  [5] Exact server        For example: jp35
  [6] Specialty group     Double VPN, P2P, Onion, Dedicated IP
  [7] Custom arguments    Advanced NordVPN CLI options
  [8] Quit
EOF
        printf '\n' >&2
        read -r -p "${C_BOLD}[?] Choose an option [1-8]: ${C_RESET}" choice
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
            *) warn 'Please choose a number from 1 to 8.' ;;
        esac
    done
}

confirm_destination() {
    local description='recommended server' answer
    if ((${#CONNECT_ARGS[@]})); then
        printf -v description '%q ' "${CONNECT_ARGS[@]}"
        description=${description% }
    fi
    print_section 'CONFIRM'
    printf '  Destination : %s%s%s\n' "$C_BOLD" "$description" "$C_RESET"
    printf '  Output      : NordVPN-<server>.conf\n\n'
    read -r -p "${C_BOLD}[?] Generate this configuration? [Y/n]: ${C_RESET}" answer
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
    print_section 'GENERATING CONFIGURATION'
    info 'Selecting NordLynx technology...'
    nordvpn set technology NordLynx >/dev/null || die "Could not enable NordLynx."

    info 'Connecting to NordVPN...'
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
    printf '\n'
    success "$output_file was created with permissions 600."
    printf '    Import it into a WireGuard client to use it.\n\n'
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
