#!/usr/bin/env bash

# NordConverter 2.x
# Modified and maintained by Deano86.
# A new implementation based on documented NordVPN CLI and WireGuard behaviour.

set -Eeuo pipefail

readonly APP_NAME="NordConverter"
readonly VERSION="2.2.1"
readonly TUNNEL_INTERFACE="nordlynx"
readonly PROFILE_DNS="103.86.96.100, 103.86.99.100"

declare -a CONNECT_TARGET=()
OUTPUT_DIRECTORY=$PWD
PLAIN_OUTPUT=false
DESTINATION_SUPPLIED=false
ASSUME_YES=false
RECOMMENDED_REQUESTED=false
COUNTRY_REQUEST=''
CITY_REQUEST=''
SERVER_REQUEST=''
GROUP_REQUEST=''
LIST_REQUEST=''
LIST_REQUEST_VALUE=''
SERVER_LIST_LIMIT=25
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
  --recommended                    Use the recommended server
  --country COUNTRY                Connect by country name or code
  --city CITY                      Connect by city (combine with --country)
  --server SERVER                  Connect to an exact server, such as uk715
  --group GROUP                    Select a specialty server group
  --yes                            Accept confirmation prompts
  --list-countries                 Print available countries and exit
  --list-cities COUNTRY            Print cities for a country and exit
  --list-groups                    Print available server groups and exit
  --list-servers                   Print recommended online NordLynx servers
  --limit NUMBER                   Limit --list-servers results (default: 25)
  --no-color                       Disable terminal colours
  -h, --help                       Show help
  -v, --version                    Show version
  --                               Pass all remaining arguments to NordVPN

Examples:
  ${0##*/}
  ${0##*/} Canada
  ${0##*/} Germany Berlin
  ${0##*/} --country Germany --city Berlin --yes
  ${0##*/} --group p2p --country gb --yes
  ${0##*/} --list-cities united_kingdom
  ${0##*/} --list-servers --country gb --limit 20
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
            --recommended)
                RECOMMENDED_REQUESTED=true
                DESTINATION_SUPPLIED=true
                shift
                ;;
            --country)
                (($# >= 2)) || { printf 'Missing value after --country.\n' >&2; exit 2; }
                COUNTRY_REQUEST=$2
                DESTINATION_SUPPLIED=true
                shift 2
                ;;
            --city)
                (($# >= 2)) || { printf 'Missing value after --city.\n' >&2; exit 2; }
                CITY_REQUEST=$2
                DESTINATION_SUPPLIED=true
                shift 2
                ;;
            --server)
                (($# >= 2)) || { printf 'Missing value after --server.\n' >&2; exit 2; }
                SERVER_REQUEST=$2
                DESTINATION_SUPPLIED=true
                shift 2
                ;;
            --group)
                (($# >= 2)) || { printf 'Missing value after --group.\n' >&2; exit 2; }
                GROUP_REQUEST=$2
                DESTINATION_SUPPLIED=true
                shift 2
                ;;
            --yes|-y)
                ASSUME_YES=true
                shift
                ;;
            --list-countries)
                LIST_REQUEST='countries'
                shift
                ;;
            --list-cities)
                (($# >= 2)) || { printf 'Missing country after --list-cities.\n' >&2; exit 2; }
                LIST_REQUEST='cities'
                LIST_REQUEST_VALUE=$2
                shift 2
                ;;
            --list-groups)
                LIST_REQUEST='groups'
                shift
                ;;
            --list-servers)
                LIST_REQUEST='servers'
                shift
                ;;
            --limit)
                (($# >= 2)) || { printf 'Missing number after --limit.\n' >&2; exit 2; }
                [[ "$2" =~ ^[0-9]+$ ]] && ((10#$2 >= 1 && 10#$2 <= 100)) || {
                    printf '%s\n' '--limit must be a number from 1 to 100.' >&2
                    exit 2
                }
                SERVER_LIST_LIMIT=$((10#$2))
                shift 2
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
                if (($#)); then
                    CONNECT_TARGET+=("$@")
                    DESTINATION_SUPPLIED=true
                fi
                break
                ;;
            *)
                CONNECT_TARGET+=("$1")
                DESTINATION_SUPPLIED=true
                shift
                ;;
        esac
    done
}

build_structured_target() {
    local structured=false

    [[ -n "$COUNTRY_REQUEST$CITY_REQUEST$SERVER_REQUEST$GROUP_REQUEST" ]] && structured=true

    if [[ "$RECOMMENDED_REQUESTED" == true ]]; then
        [[ "$structured" == false && ${#CONNECT_TARGET[@]} -eq 0 ]] || \
            fail '--recommended cannot be combined with another destination.'
        CONNECT_TARGET=()
        return
    fi

    if [[ -n "$SERVER_REQUEST" ]]; then
        [[ -z "$COUNTRY_REQUEST$CITY_REQUEST$GROUP_REQUEST" && ${#CONNECT_TARGET[@]} -eq 0 ]] || \
            fail '--server cannot be combined with country, city, group, or raw arguments.'
        CONNECT_TARGET=("$SERVER_REQUEST")
        return
    fi

    if [[ -n "$GROUP_REQUEST" ]]; then
        [[ -z "$CITY_REQUEST" ]] || fail '--group cannot be combined with --city.'
        if ((${#CONNECT_TARGET[@]} == 1)) && [[ -z "$COUNTRY_REQUEST" ]]; then
            COUNTRY_REQUEST=${CONNECT_TARGET[0]}
            CONNECT_TARGET=()
        fi
        ((${#CONNECT_TARGET[@]} == 0)) || fail 'Use --group GROUP --country COUNTRY, or place raw arguments after --.'
        CONNECT_TARGET=(--group "$GROUP_REQUEST")
        [[ -n "$COUNTRY_REQUEST" ]] && CONNECT_TARGET+=("$COUNTRY_REQUEST")
        return
    fi

    if [[ -n "$COUNTRY_REQUEST$CITY_REQUEST" ]]; then
        ((${#CONNECT_TARGET[@]} == 0)) || fail 'Named destination options cannot be combined with raw arguments.'
        [[ -n "$COUNTRY_REQUEST" ]] && CONNECT_TARGET+=("$COUNTRY_REQUEST")
        [[ -n "$CITY_REQUEST" ]] && CONNECT_TARGET+=("$CITY_REQUEST")
    fi

    # Optional structured fields may be absent. Always report successful target
    # construction after validation so `set -e` does not treat that as an error.
    return 0
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

country_lookup_value() {
    local value=$1
    printf '%s' "${value// /_}"
}

show_countries() {
    section 'AVAILABLE COUNTRIES'
    nordvpn countries || say_warn 'NordVPN could not retrieve the country list.'
    printf '\n'
}

show_cities() {
    local country=$1 lookup
    lookup=$(country_lookup_value "$country")
    section "AVAILABLE CITIES: $country"
    nordvpn cities "$lookup" || say_warn "NordVPN could not retrieve cities for $country."
    printf '\n'
}

show_groups() {
    section 'AVAILABLE SERVER GROUPS'
    nordvpn groups || say_warn 'NordVPN could not retrieve the server-group list.'
    printf '\n'
}

server_api_ready() {
    if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        say_warn "Server listing requires the optional packages 'curl' and 'jq'."
        say_warn 'On Ubuntu: sudo apt install curl jq'
        return 1
    fi
}

resolve_country_id() {
    local country=$1 key countries_json country_id
    key=${country,,}
    key=${key// /_}
    key=${key//-/_}

    if ! countries_json=$(curl -fsSL 'https://api.nordvpn.com/v1/servers/countries'); then
        say_warn 'The NordVPN country catalogue could not be downloaded.'
        return 1
    fi

    country_id=$(jq -r --arg key "$key" '
        [ .[] | select(
            ((.code // "") | ascii_downcase) == $key or
            ((.name // "") | ascii_downcase | gsub("[ _-]+"; "_")) == $key
        ) ][0].id // empty
    ' <<< "$countries_json")

    if [[ -z "$country_id" ]]; then
        say_warn "No API country matched: $country"
        return 1
    fi

    printf '%s' "$country_id"
}

show_servers() {
    local country=${1:-} country_id='' server_json count
    local -a request=(
        curl -fsSLG 'https://api.nordvpn.com/v1/servers/recommendations'
        --data-urlencode "limit=$SERVER_LIST_LIMIT"
        --data-urlencode 'filters[servers.status]=online'
        --data-urlencode 'filters[servers_technologies][identifier]=wireguard_udp'
    )

    server_api_ready || return 1

    if [[ -n "$country" ]]; then
        country_id=$(resolve_country_id "$country") || return 1
        request+=(--data-urlencode "filters[country_id]=$country_id")
    fi

    section "RECOMMENDED ONLINE SERVERS${country:+: $country}"
    say_info "Requesting up to $SERVER_LIST_LIMIT NordLynx servers..."
    if ! server_json=$("${request[@]}"); then
        say_warn 'The NordVPN server API request failed.'
        return 1
    fi

    if ! jq -e 'type == "array"' >/dev/null <<< "$server_json"; then
        say_warn 'The NordVPN server API returned an unexpected response.'
        return 1
    fi

    count=$(jq 'length' <<< "$server_json")
    if ((count == 0)); then
        say_warn 'No matching online NordLynx servers were returned.'
        return 1
    fi

    printf '%-24s %-22s %-22s %s\n' 'HOSTNAME' 'COUNTRY' 'CITY' 'LOAD'
    printf '%-24s %-22s %-22s %s\n' '------------------------' '----------------------' '----------------------' '----'
    jq -r '.[] | [
        (.hostname // "-"),
        (.locations[0].country.name // "-"),
        (.locations[0].country.city.name // "-"),
        ((.load // 0 | tostring) + "%")
    ] | @tsv' <<< "$server_json" |
        awk -F '\t' '{printf "%-24s %-22s %-22s %s\n", $1, $2, $3, $4}'
    printf '\n'
}

run_list_request() {
    case "$LIST_REQUEST" in
        countries) show_countries ;;
        cities) show_cities "$LIST_REQUEST_VALUE" ;;
        groups) show_groups ;;
        servers) show_servers "$COUNTRY_REQUEST" || fail 'Unable to list servers.' ;;
        *) fail "Unknown list request: $LIST_REQUEST" ;;
    esac
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
  [5] Server            Browse and select an exact hostname
  [6] Group             P2P, Double VPN, Onion, or Dedicated IP
  [7] Raw connect args  Arguments placed after "nordvpn connect"
  [8] Exit
EOF
        printf '\n'
        read -r -p "${CLR_BOLD}[?] Select [1-8]: ${CLR_END}" choice

        case "$choice" in
            1) CONNECT_TARGET=(); return ;;
            2)
                show_countries
                first=$(prompt_required 'Country/code: ')
                CONNECT_TARGET=("$first")
                return
                ;;
            3)
                show_countries
                first=$(prompt_required 'Country containing the city: ')
                show_cities "$first"
                second=$(prompt_required 'City: ')
                CONNECT_TARGET=("$first" "$second")
                return
                ;;
            4)
                show_countries
                first=$(prompt_required 'Country: ')
                show_cities "$first"
                second=$(prompt_required 'City: ')
                CONNECT_TARGET=("$first" "$second")
                return
                ;;
            5)
                read -r -p 'Optional country/code filter (Enter for any): ' first
                show_servers "$first" || true
                second=$(prompt_required 'Server hostname (for example, uk715): ')
                second=${second%.nordvpn.com}
                CONNECT_TARGET=("$second")
                return
                ;;
            6)
                show_groups
                first=$(prompt_required 'Group: ')
                read -r -p 'Optional country/code: ' second
                CONNECT_TARGET=(--group "$first")
                [[ -n "$second" ]] && CONNECT_TARGET+=("$second")
                return
                ;;
            7)
                section 'NORDVPN CONNECT HELP'
                nordvpn help connect 2>/dev/null || nordvpn help || true
                cat <<'EOF'

Enter only the part that normally follows "nordvpn connect".
Examples:
  uk715
  united_kingdom london
  --group p2p gb
  --group double_vpn us

Do not enter "nordvpn connect" itself.
EOF
                printf '\n'
                raw=$(prompt_required 'Connect arguments: ')
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

    if [[ "$ASSUME_YES" == true ]]; then
        say_info 'Confirmation accepted by --yes.'
        return 0
    fi

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

    if [[ "$ASSUME_YES" == true ]]; then
        nordvpn disconnect >/dev/null || fail 'Could not disconnect NordVPN.'
        return 0
    fi

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
    parse_command_line "$@"
    configure_style
    build_structured_target
    banner
    preflight
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    login_assistant
    if [[ -n "$LIST_REQUEST" ]]; then
        run_list_request
        exit 0
    fi
    if [[ "$DESTINATION_SUPPLIED" == false ]]; then
        choose_destination
    fi
    confirm_job
    clear_existing_connection
    export_profile
}

main "$@"
