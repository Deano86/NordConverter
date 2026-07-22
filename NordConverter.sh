#!/usr/bin/env bash

# NordConverter 2.x
# Modified and maintained by Deano86.
# A new implementation based on documented NordVPN CLI and WireGuard behaviour.

set -Eeuo pipefail

readonly APP_NAME="NordConverter"
readonly VERSION="2.0.1"
readonly TUNNEL_INTERFACE="nordlynx"
readonly PROFILE_DNS="103.86.96.100, 103.86.99.100"

declare -a CONNECT_TARGET=()
OUTPUT_DIRECTORY=$PWD
PLAIN_OUTPUT=false
CREATED_CONNECTION=false
WORK_FILE=''

CLR_TITLE=''
CLR_ACCENT=''
CLR_OK=''
CLR_WARN=''
CLR_ERROR=''
CLR_BOLD=''
CLR_FAINT=''
CLR_END=''

usage() {
    cat <<EOF
$APP_NAME $VERSION

Usage:
  ${0##*/}                         Open the interactive menu
  ${0##*/} [destination...]        Pass a destination to nordvpn connect

NordConverter options:
  --output-dir DIRECTORY           Directory for the generated profile
  --no-color                       Disable terminal colours
  -h, --help                       Show help
  -v, --version                    Show version
  --                               Pass all remaining arguments to NordVPN

Examples:
  ${0##*/}
  ${0##*/} Canada
  ${0##*/} Germany Berlin
  ${0##*/} --group p2p gb
  ${0##*/} --output-dir ./profiles Japan
EOF
}

parse_command_line() {
    while (($#)); do
        case "$1" in
            --output-dir)
                (($# >= 2)) || { printf 'Missing directory after --output-dir.\n' >&2; exit 2; }
                OUTPUT_DIRECTORY=$2
                shift 2
                ;;
            --no-color)
                PLAIN_OUTPUT=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -v|--version)
                printf '%s %s\n' "$APP_NAME" "$VERSION"
                exit 0
                ;;
            --)
                shift
                CONNECT_TARGET+=("$@")
                break
                ;;
            *)
                CONNECT_TARGET+=("$1")
                shift
                ;;
        esac
    done
}

configure_style() {
    if [[ -t 1 && "$PLAIN_OUTPUT" == false && -z "${NO_COLOR:-}" ]]; then
        CLR_TITLE=$'\033[1;36m'
        CLR_ACCENT=$'\033[1;34m'
        CLR_OK=$'\033[1;32m'
        CLR_WARN=$'\033[1;33m'
        CLR_ERROR=$'\033[1;31m'
        CLR_BOLD=$'\033[1m'
        CLR_FAINT=$'\033[2m'
        CLR_END=$'\033[0m'
    fi
}

banner() {
    printf '\n%s' "$CLR_TITLE"
    cat <<'EOF'
 _   _               _  ____                          _
| \ | | ___  _ __ __| |/ ___|___  _ ____   _____ _ __| |_ ___ _ __
|  \| |/ _ \| '__/ _` | |   / _ \| '_ \ \ / / _ \ '__| __/ _ \ '__|
| |\  | (_) | | | (_| | |__| (_) | | | \ V /  __/ |  | ||  __/ |
|_| \_|\___/|_|  \__,_|\____\___/|_| |_|\_/ \___|_|   \__\___|_|
EOF
    printf '%s' "$CLR_END"
    printf '%s\n' '------------------------------------------------------------------------'
    printf '  %sNordVPN profile exporter%s    %sv%s%s\n' \
        "$CLR_BOLD" "$CLR_END" "$CLR_FAINT" "$VERSION" "$CLR_END"
    printf '  %sModified and maintained by Deano86%s\n' "$CLR_FAINT" "$CLR_END"
    printf '%s\n' '------------------------------------------------------------------------'
}

section() {
    printf '\n%s-- %s --%s\n\n' "$CLR_ACCENT" "$1" "$CLR_END"
}

say_info() {
    printf '%s[i]%s %s\n' "$CLR_ACCENT" "$CLR_END" "$*"
}

say_ok() {
    printf '%s[+]%s %s\n' "$CLR_OK" "$CLR_END" "$*"
}

say_warn() {
    printf '%s[!]%s %s\n' "$CLR_WARN" "$CLR_END" "$*" >&2
}

fail() {
    printf '%s[x]%s %s\n' "$CLR_ERROR" "$CLR_END" "$*" >&2
    exit 1
}

cleanup() {
    local result=$?

    if [[ -n "$WORK_FILE" && -e "$WORK_FILE" ]]; then
        rm -f -- "$WORK_FILE"
    fi

    if [[ "$CREATED_CONNECTION" == true ]]; then
        say_info 'Disconnecting the temporary NordVPN session...'
        nordvpn disconnect >/dev/null 2>&1 || \
            say_warn 'The temporary NordVPN session could not be disconnected.'
    fi

    return "$result"
}

require_program() {
    command -v "$1" >/dev/null 2>&1 || fail "Required program not found: $1"
}

preflight() {
    local program
    local -a programs=(nordvpn wg ip awk mktemp chmod mv mkdir rm date)

    if ((EUID != 0)); then
        programs+=(sudo)
    fi

    for program in "${programs[@]}"; do
        require_program "$program"
    done
}

wg_read() {
    if ((EUID == 0)); then
        wg "$@"
    else
        sudo wg "$@"
    fi
}

prompt_required() {
    local message=$1
    local reply

    while true; do
        read -r -p "$message" reply
        if [[ -n "$reply" ]]; then
            printf '%s' "$reply"
            return
        fi
        say_warn 'A value is required.'
    done
}

logged_in() {
    nordvpn account >/dev/null 2>&1
}

login_assistant() {
    local choice callback token

    logged_in && return
    [[ -t 0 ]] || fail 'NordVPN login is required; run NordConverter in a terminal first.'

    while ! logged_in; do
        section 'ACCOUNT LOGIN'
        cat <<'EOF'
  [1] Browser       Complete the normal Nord Account login
  [2] Callback      Paste the nordvpn:// link from Continue
  [3] Token         Use a Nord Account access token (headless)
  [4] Exit
EOF
        printf '\n'
        read -r -p "${CLR_BOLD}[?] Select [1-4]: ${CLR_END}" choice

        case "$choice" in
            1)
                nordvpn login || true
                printf '\nComplete the browser login and select Continue.\n'
                read -r -p '[?] Press Enter when finished...'
                ;;
            2)
                callback=$(prompt_required 'Callback URL: ')
                if [[ "$callback" != nordvpn://* ]]; then
                    say_warn 'A callback URL must begin with nordvpn://'
                elif ! nordvpn login --callback "$callback"; then
                    say_warn 'The callback was rejected. Request a new login link.'
                fi
                callback=''
                ;;
            3)
                printf 'Create a token under Nord Account > NordVPN > Advanced settings.\n'
                read -r -s -p 'Access token (hidden): ' token
                printf '\n'
                if [[ -z "$token" ]]; then
                    say_warn 'No token was entered.'
                elif ! nordvpn login --token "$token"; then
                    say_warn 'The token login failed.'
                fi
                token=''
                ;;
            4|q|Q) exit 0 ;;
            *) say_warn 'Choose a number from 1 to 4.' ;;
        esac
    done

    say_ok 'NordVPN account is ready.'
}

choose_destination() {
    local choice first second raw

    while true; do
        section 'DESTINATION'
        cat <<'EOF'
  [1] Automatic         NordVPN recommended server
  [2] Country           Country name or country code
  [3] City              Fastest server matching a city
  [4] Country + city    A city within a selected country
  [5] Server            Exact hostname, such as uk715
  [6] Group             P2P, Double VPN, Onion, or Dedicated IP
  [7] Advanced          Enter NordVPN connect arguments
  [8] Exit
EOF
        printf '\n'
        read -r -p "${CLR_BOLD}[?] Select [1-8]: ${CLR_END}" choice

        case "$choice" in
            1) CONNECT_TARGET=(); return ;;
            2) first=$(prompt_required 'Country/code: '); CONNECT_TARGET=("$first"); return ;;
            3) first=$(prompt_required 'City: '); CONNECT_TARGET=("$first"); return ;;
            4)
                first=$(prompt_required 'Country: ')
                second=$(prompt_required 'City: ')
                CONNECT_TARGET=("$first" "$second")
                return
                ;;
            5) first=$(prompt_required 'Server: '); CONNECT_TARGET=("$first"); return ;;
            6)
                printf 'Examples: p2p, double_vpn, onion_over_vpn, dedicated_ip\n'
                first=$(prompt_required 'Group: ')
                read -r -p 'Optional country/code: ' second
                CONNECT_TARGET=(--group "$first")
                [[ -n "$second" ]] && CONNECT_TARGET+=("$second")
                return
                ;;
            7)
                raw=$(prompt_required 'Arguments: ')
                read -r -a CONNECT_TARGET <<< "$raw"
                return
                ;;
            8|q|Q) exit 0 ;;
            *) say_warn 'Choose a number from 1 to 8.' ;;
        esac
    done
}

target_description() {
    if ((${#CONNECT_TARGET[@]} == 0)); then
        printf 'recommended server'
    else
        printf '%q ' "${CONNECT_TARGET[@]}"
    fi
}

confirm_job() {
    local answer

    section 'REVIEW'
    printf '  Target       : %s%s%s\n' "$CLR_BOLD" "$(target_description)" "$CLR_END"
    printf '  Output folder: %s\n\n' "$OUTPUT_DIRECTORY"
    read -r -p "${CLR_BOLD}[?] Continue? [Y/n]: ${CLR_END}" answer

    case "${answer:-y}" in
        y|Y|yes|YES|Yes) ;;
        *) say_info 'Cancelled.'; exit 0 ;;
    esac
}

connection_active() {
    nordvpn status 2>/dev/null | awk -F': *' '$1 == "Status" && $2 == "Connected" {found=1} END {exit !found}'
}

clear_existing_connection() {
    local answer

    # No existing connection is the normal case, not an error. Return success so
    # `set -e` does not stop the export immediately after confirmation.
    connection_active || return 0
    say_warn 'NordVPN is already connected. NordConverter must replace that connection temporarily.'
    [[ -t 0 ]] || fail 'Disconnect NordVPN before running non-interactively.'
    read -r -p '[?] Disconnect the current session and continue? [y/N]: ' answer
    case "$answer" in
        y|Y|yes|YES|Yes) nordvpn disconnect >/dev/null || fail 'Could not disconnect NordVPN.' ;;
        *) exit 0 ;;
    esac
}

tunnel_address() {
    local value
    value=$(ip -o -4 address show dev "$TUNNEL_INTERFACE" 2>/dev/null | awk 'NR == 1 {print $4}')
    [[ -n "$value" ]] || fail "No IPv4 address was found on $TUNNEL_INTERFACE."
    printf '%s' "$value"
}

config_field() {
    local field=$1
    local config=$2
    awk -F' *= *' -v wanted="$field" '$1 == wanted {print $2; exit}' <<< "$config"
}

server_label() {
    local status endpoint label
    status=$(nordvpn status 2>/dev/null || true)
    label=$(awk -F': *' '$1 == "Hostname" || $1 == "Current server" {print $2; exit}' <<< "$status")

    if [[ -z "$label" ]]; then
        endpoint=$1
        label=${endpoint%:*}
    fi

    label=${label%%.*}
    label=${label//[^A-Za-z0-9_-]/_}
    [[ -n "$label" ]] || label='profile'
    printf '%s' "$label"
}

write_profile() {
    local address=$1 private_key=$2 listen_port=$3 peer_key=$4 endpoint=$5 label final_path timestamp

    mkdir -p -- "$OUTPUT_DIRECTORY" || fail "Could not create output directory: $OUTPUT_DIRECTORY"
    WORK_FILE=$(mktemp "${OUTPUT_DIRECTORY%/}/.nordconverter.XXXXXX") || fail 'Could not create a temporary output file.'
    label=$(server_label "$endpoint")
    final_path="${OUTPUT_DIRECTORY%/}/NordVPN-${label}.conf"

    if [[ -e "$final_path" ]]; then
        timestamp=$(date '+%Y%m%d-%H%M%S')
        final_path="${OUTPUT_DIRECTORY%/}/NordVPN-${label}-${timestamp}.conf"
    fi

    umask 077
    {
        printf '%s\n' '[Interface]'
        printf 'Address = %s\n' "$address"
        printf 'PrivateKey = %s\n' "$private_key"
        [[ -n "$listen_port" ]] && printf 'ListenPort = %s\n' "$listen_port"
        printf 'DNS = %s\n\n' "$PROFILE_DNS"
        printf '%s\n' '[Peer]'
        printf 'PublicKey = %s\n' "$peer_key"
        printf '%s\n' 'AllowedIPs = 0.0.0.0/0, ::/0'
        printf 'Endpoint = %s\n' "$endpoint"
        printf '%s\n' 'PersistentKeepalive = 25'
    } > "$WORK_FILE"

    chmod 600 "$WORK_FILE"
    mv -- "$WORK_FILE" "$final_path"
    WORK_FILE=''
    GENERATED_PROFILE=$final_path
}

export_profile() {
    local raw_config address private_key listen_port peer_key endpoint

    section 'EXPORT'
    say_info 'Selecting NordLynx...'
    nordvpn set technology NordLynx >/dev/null || fail 'NordLynx could not be selected.'

    say_info 'Connecting to the selected destination...'
    if ((${#CONNECT_TARGET[@]})); then
        nordvpn connect "${CONNECT_TARGET[@]}" || fail 'NordVPN could not establish the requested connection.'
    else
        nordvpn connect || fail 'NordVPN could not establish a recommended connection.'
    fi
    CREATED_CONNECTION=true

    say_info 'Reading the active tunnel profile...'
    raw_config=$(wg_read showconf "$TUNNEL_INTERFACE") || fail 'WireGuard could not read the NordLynx interface.'
    address=$(tunnel_address)
    private_key=$(config_field 'PrivateKey' "$raw_config")
    listen_port=$(config_field 'ListenPort' "$raw_config")
    peer_key=$(config_field 'PublicKey' "$raw_config")
    endpoint=$(config_field 'Endpoint' "$raw_config")

    [[ -n "$private_key" ]] || fail 'The tunnel private key was not present.'
    [[ -n "$peer_key" ]] || fail 'The peer public key was not present.'
    [[ -n "$endpoint" ]] || fail 'The peer endpoint was not present.'

    write_profile "$address" "$private_key" "$listen_port" "$peer_key" "$endpoint"

    if nordvpn disconnect >/dev/null; then
        CREATED_CONNECTION=false
    else
        say_warn 'The profile was saved, but NordVPN did not disconnect cleanly.'
    fi

    printf '\n'
    say_ok "Created $GENERATED_PROFILE"
    say_warn 'This file contains a private key. Store it securely.'
}

main() {
    local interactive=true

    if (($#)); then
        interactive=false
    fi
    parse_command_line "$@"
    configure_style
    banner
    preflight
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    login_assistant
    if [[ "$interactive" == true && ${#CONNECT_TARGET[@]} -eq 0 ]]; then
        choose_destination
    fi
    confirm_job
    clear_existing_connection
    export_profile
}

main "$@"
