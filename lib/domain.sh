# shellcheck shell=bash

### Default installer options ###
AUTO_DOMAIN="${AUTO_DOMAIN:-false}"
XUI_VERSION="${XUI_VERSION:-latest}"
UNINSTALL_MODE="${UNINSTALL_MODE:-false}"
INSTALL_PROFILE="${INSTALL_PROFILE:-}"
DOMAIN="${DOMAIN:-}"
REALITY_DOMAIN="${REALITY_DOMAIN:-}"
XHTTP_DOMAIN="${XHTTP_DOMAIN:-}"

### Show help ###
show_help() {
    cat <<'EOF'
Usage:
  bash install.sh [options]

Options:
  -h, --help
      Show this help message and exit.

  -profile, --profile PROFILE
      Select installation profile.
      Values:
        standard
            2-domain setup.
            Domain #1: panel, subscription, fake site.
            Domain #2: TCP REALITY and XHTTP inbound on the same SNI/domain, fake site.
        separate-xhttp-sni
            3-domain setup.
            Domain #1: panel, subscription, fake site.
            Domain #2: TCP REALITY inbound, fake site.
            Domain #3: XHTTP REALITY inbound on its own SNI/domain, fake site.

  -auto-domain, --auto-domain
      Generate temporary domains automatically using third-party cdn-one.org DNS.
      Intended only for testing, disposable VPS deployments, and quick experiments.

  -domain, --domain DOMAIN
      Panel domain.
      Example: --domain panel.example.com

  -reality-domain, --reality-domain DOMAIN
      Reality domain.
      In the standard profile, this also hosts the current baseline XHTTP path.
      Must be different from panel domain.
      Example: --reality-domain reality.example.com

  -xhttp-domain, --xhttp-domain DOMAIN
      XHTTP domain for the separate-xhttp-sni profile.
      Must be different from panel and reality domains.
      Example: --xhttp-domain xhttp.example.com

  -xui-version, --xui-version VERSION
      3x-ui version to install.
      Default: latest
      Examples: --xui-version latest
                --xui-version v3.3.1
                --xui-version 3.3.1

  -uninstall, --uninstall
      Remove installed components, generated configs, certificates,
      fake sites, firewall rules, and installer leftovers.
      Intended only for clean VPS rollback.

Examples:
  bash install.sh --domain panel.example.com --reality-domain reality.example.com

  bash install.sh \
      --domain panel.example.com \
      --reality-domain reality.example.com \
      --xui-version v3.3.1

  bash install.sh --auto-domain --xui-version latest

  bash install.sh --uninstall

Notes:
  - IPv4 A records are required.
  - IPv6 AAAA records are optional.
  - If AAAA records exist, they must point to this VPS IPv6.
  - Designed for clean VPS installation.
EOF
}

### Show help if requested ###
show_help_if_requested() {
    for arg in "$@"; do
        case "$arg" in
            -h|--help)
                show_help
                exit 0
                ;;
        esac
    done
}

### Normalize install profile ###
normalize_install_profile() {
    local profile="$1"
    case "$profile" in
        standard|2domain|two-domain)
            echo "standard"
            ;;
        separate-xhttp-sni|3domain|three-domain|xhttp-sni)
            echo "separate-xhttp-sni"
            ;;
        *)
            return 1
            ;;
    esac
}

### Show selected install profile ###
show_install_profile() {
    case "$INSTALL_PROFILE" in
        standard)
            msg_inf "Installation profile:" "standard — 2 domains"
            ;;
        separate-xhttp-sni)
            msg_inf "Installation profile:" "separate XHTTP SNI — 3 domains"
            ;;
        *)
            msg_inf "Installation profile:" "$INSTALL_PROFILE"
            ;;
    esac
    msg_blank
}

### Select install profile ###
select_install_profile() {
    local choice
    local normalized_profile
    if [[ -n "$INSTALL_PROFILE" ]]; then
        normalized_profile="$(normalize_install_profile "$INSTALL_PROFILE")" || {
            msg_err "Invalid installation profile: $INSTALL_PROFILE"
            msg_err "Allowed profiles: standard, separate-xhttp-sni"
            exit 1
        }
        INSTALL_PROFILE="$normalized_profile"
        export INSTALL_PROFILE
        return 0
    fi
    if [[ -n "$XHTTP_DOMAIN" ]]; then
        INSTALL_PROFILE="separate-xhttp-sni"
        export INSTALL_PROFILE
        return 0
    fi
    if [[ "$AUTO_DOMAIN" == true || -n "$DOMAIN" || -n "$REALITY_DOMAIN" ]]; then
        INSTALL_PROFILE="standard"
        export INSTALL_PROFILE
        return 0
    fi
    clear_all
    echo
    echo "Installation profile"
    echo
    echo "Choose how many public domains this server will use."
    echo
    echo "1) Standard — 2 domains"
    echo "   Domain #1: panel, subscription, fake site."
    echo "   Domain #2: TCP REALITY and XHTTP inbound on the same SNI/domain, fake site."
    echo "   Recommended if you do not need a separate XHTTP domain."
    echo
    echo "2) Separate XHTTP SNI — 3 domains"
    echo "   Domain #1: panel, subscription, fake site."
    echo "   Domain #2: TCP REALITY inbound, fake site."
    echo "   Domain #3: XHTTP REALITY inbound on its own SNI/domain, fake site."
    echo "   Use this if you want XHTTP to have a separate domain."
    echo
    while true; do
        read -rp "Select installation profile [1-2]: " choice
        case "$choice" in
            1)
                INSTALL_PROFILE="standard"
                break
                ;;
            2)
                INSTALL_PROFILE="separate-xhttp-sni"
                break
                ;;
            *)
                msg_err "Please select 1 or 2"
                ;;
        esac
    done
    export INSTALL_PROFILE
}

### Get arguments ###
parse_arguments() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -uninstall|--uninstall)
                UNINSTALL_MODE=true
                shift
                ;;
            -profile|--profile)
                [[ -n "${2:-}" ]] || {
                    msg_err "Missing value for $1"
                    exit 1
                }
                INSTALL_PROFILE="$2"
                shift 2
                ;;
            -auto-domain|--auto-domain)
                AUTO_DOMAIN=true
                shift
                ;;
            -domain|--domain)
                [[ -n "${2:-}" ]] || {
                    msg_err "Missing value for $1"
                    exit 1
                }
                DOMAIN="$2"
                shift 2
                ;;
            -reality-domain|--reality-domain)
                [[ -n "${2:-}" ]] || {
                    msg_err "Missing value for $1"
                    exit 1
                }
                REALITY_DOMAIN="$2"
                shift 2
                ;;
            -xhttp-domain|--xhttp-domain)
                [[ -n "${2:-}" ]] || {
                    msg_err "Missing value for $1"
                    exit 1
                }
                XHTTP_DOMAIN="$2"
                shift 2
                ;;
            -xui-version|--xui-version)
                [[ -n "${2:-}" ]] || {
                    msg_err "Missing value for $1"
                    exit 1
                }
                XUI_VERSION="$2"
                shift 2
                ;;
            *)
                msg_err "Unknown argument: $1"
                exit 1
                ;;
        esac
    done
    if [[ "$UNINSTALL_MODE" == true ]]; then
        return 0
    fi
    select_install_profile
    if [[ "$AUTO_DOMAIN" != true ]]; then
        if [[ "$INSTALL_PROFILE" == "separate-xhttp-sni" ]]; then
            if [[ -z "$DOMAIN" || -z "$REALITY_DOMAIN" || -z "$XHTTP_DOMAIN" ]]; then
                interactive_domain_setup
            fi
        else
            if [[ -z "$DOMAIN" || -z "$REALITY_DOMAIN" ]]; then
                interactive_domain_setup
            fi
        fi
    fi
}

## Remove spaces from domain ###
sanitize_domain() {
    local domain="$1"
    echo "$domain" | tr -d '[:space:]'
}

### Validate domain format ###
validate_domain() {
    local domain="$1"
    local label
    [[ -n "$domain" ]] || return 1
    [[ "$domain" != *..* ]] || return 1
    [[ "$domain" =~ ^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || return 1
    IFS='.' read -ra labels <<< "$domain"
    for label in "${labels[@]}"; do
        [[ -n "$label" ]] || return 1
        [[ ${#label} -le 63 ]] || return 1
        [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
    done
    return 0
}

### Ask user for domain and assign variable ###
request_domain() {
    local output_var="$1"
    local prompt="$2"
    local domain
    while true; do
        read -rp "$prompt: " domain \
            || return 1
        domain=$(sanitize_domain "$domain")
        if validate_domain "$domain"; then
            printf -v "$output_var" '%s' "$domain"
            return 0
        fi
        msg_err "Invalid domain format"
    done
}

### Normalize public IPv4 ###
normalize_ipv4() {
    local ip="$1"
    python3 -c '
import ipaddress
import sys
try:
    ip = ipaddress.ip_address(sys.argv[1])
    if ip.version != 4:
        sys.exit(1)
    if not ip.is_global:
        sys.exit(1)
    print(str(ip))
except Exception:
    sys.exit(1)
' "$ip" 2>/dev/null
}

### Resolve domain IPv4 ###
resolve_domain_ipv4() {
    local domain="$1"
    dig +short A "$domain" \
        | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
        | sort -u
}

### Normalize IPv6 ###
normalize_ipv6() {
    local ip="$1"
    python3 -c '
import ipaddress
import sys
try:
    print(ipaddress.ip_address(sys.argv[1]).compressed.lower())
except Exception:
    sys.exit(1)
' "$ip" 2>/dev/null
}

### Resolve domain IPv6 ###
resolve_domain_ipv6() {
    local domain="$1"
    local ip
    local normalized_ip
    while read -r ip; do
        [[ -n "$ip" ]] || continue
        normalized_ip=$(normalize_ipv6 "$ip") || continue
        echo "$normalized_ip"
    done < <(dig +short AAAA "$domain")
    return 0
}

### Format DNS records ###
format_dns_records() {
    local records="$1"
    if [[ -z "$records" ]]; then
        echo "absent"
        return 0
    fi
    awk '
        BEGIN { first = 1 }
        {
            if (!first) {
                printf ", "
            }
            printf "%s", $0
            first = 0
        }
        END {
            printf "\n"
        }
    ' <<< "$records"
}

### Validate domain DNS ###
validate_domain_dns() {
    local domain="$1"
    local label="$2"
    local resolved_a
    local resolved_aaaa
    local resolved_a_display
    local resolved_aaaa_display
    local bad_a
    local bad_aaaa
    resolved_a=$(resolve_domain_ipv4 "$domain")
    resolved_aaaa=$(resolve_domain_ipv6 "$domain")
    resolved_a_display=$(format_dns_records "$resolved_a")
    resolved_aaaa_display=$(format_dns_records "$resolved_aaaa")
    msg_inf "${label} Domain:" "$domain"
    msg_inf "${label} DNS A:" "$resolved_a_display"
    msg_inf "${label} DNS AAAA:" "$resolved_aaaa_display"
    ### IPv4 A record is required ###
    if [[ -z "$resolved_a" ]]; then
        msg_err "${label} domain does not have A record"
        msg_err "Domain: $domain"
        msg_err "Expected VPS IPv4: $PUBLIC_IP4"
        msg_err "Create an A record, then run installer again"
        return 1
    fi
    bad_a=$(grep -Fxv "$PUBLIC_IP4" <<< "$resolved_a" || true)
    if [[ -n "$bad_a" ]]; then
        msg_err "${label} domain A record mismatch"
        msg_err "Domain: $domain"
        msg_err "Current DNS A: $resolved_a_display"
        msg_err "Expected VPS IPv4: $PUBLIC_IP4"
        msg_err "Fix the A record, then run installer again"
        return 1
    fi
    ### IPv6 AAAA record is optional, but if present it must be correct ###
    if [[ -n "$resolved_aaaa" ]]; then
        if [[ -z "$PUBLIC_IP6" || "$PUBLIC_IP6" == "absent" ]]; then
            msg_err "${label} domain has AAAA record, but VPS IPv6 was not detected"
            msg_err "Domain: $domain"
            msg_err "Current DNS AAAA: $resolved_aaaa_display"
            msg_err "Fix or remove the AAAA record, then run installer again"
            return 1
        fi
        bad_aaaa=$(grep -Fxiv "$PUBLIC_IP6" <<< "$resolved_aaaa" || true)
        if [[ -n "$bad_aaaa" ]]; then
            msg_err "${label} domain AAAA record mismatch"
            msg_err "Domain: $domain"
            msg_err "Current DNS AAAA: $resolved_aaaa_display"
            msg_err "Expected VPS IPv6: $PUBLIC_IP6"
            msg_err "Fix or remove the AAAA record, then run installer again"
            return 1
        fi
    fi
    return 0
}

### Show auto-domain warning ###
show_auto_domain_warning() {
    msg_inf "Auto-domain mode:" "uses third-party cdn-one.org DNS"
    msg_inf "Auto-domain scope:" "testing/disposable VPS only; use your own domains for production"
    msg_blank
}

### Resolve domains ###
resolve_domains() {
    msg_inf "Resolving domains..."
    msg_blank
    if [[ "$AUTO_DOMAIN" == true ]]; then
        show_auto_domain_warning
        generate_auto_domains
    fi
    if [[ -n "$DOMAIN" ]]; then
        DOMAIN="$(sanitize_domain "$DOMAIN")"
    fi
    if [[ -n "$REALITY_DOMAIN" ]]; then
        REALITY_DOMAIN="$(sanitize_domain "$REALITY_DOMAIN")"
    fi
    if [[ -n "$XHTTP_DOMAIN" ]]; then
        XHTTP_DOMAIN="$(sanitize_domain "$XHTTP_DOMAIN")"
    fi
    export DOMAIN
    export REALITY_DOMAIN
    export XHTTP_DOMAIN
}

### Validate domains ###
validate_domains() {
    msg_inf "Validating domains..."
    msg_blank
    if [[ -z "$DOMAIN" ]]; then
        msg_err "DOMAIN is required"
        return 1
    fi
    if [[ -z "$REALITY_DOMAIN" ]]; then
        msg_err "REALITY_DOMAIN is required"
        return 1
    fi
    if [[ "$INSTALL_PROFILE" == "separate-xhttp-sni" && -z "$XHTTP_DOMAIN" ]]; then
        msg_err "XHTTP_DOMAIN is required for separate-xhttp-sni profile"
        return 1
    fi
    if [[ "$DOMAIN" == "$REALITY_DOMAIN" ]]; then
        msg_err "DOMAIN and REALITY_DOMAIN must be different"
        return 1
    fi
    if [[ "$INSTALL_PROFILE" == "separate-xhttp-sni" ]]; then
        if [[ "$DOMAIN" == "$XHTTP_DOMAIN" || "$REALITY_DOMAIN" == "$XHTTP_DOMAIN" ]]; then
            msg_err "DOMAIN, REALITY_DOMAIN, and XHTTP_DOMAIN must be different"
            return 1
        fi
    fi
    validate_domain "$DOMAIN" || {
        msg_err "Invalid DOMAIN format"
        return 1
    }
    validate_domain "$REALITY_DOMAIN" || {
        msg_err "Invalid REALITY_DOMAIN format"
        return 1
    }
    if [[ "$INSTALL_PROFILE" == "separate-xhttp-sni" ]]; then
        validate_domain "$XHTTP_DOMAIN" || {
            msg_err "Invalid XHTTP_DOMAIN format"
            return 1
        }
    fi
    validate_domain_dns "$DOMAIN" "Panel" || return 1
    msg_blank
    validate_domain_dns "$REALITY_DOMAIN" "Reality" || return 1
    msg_blank
    if [[ "$INSTALL_PROFILE" == "separate-xhttp-sni" ]]; then
        validate_domain_dns "$XHTTP_DOMAIN" "XHTTP" || return 1
        msg_blank
    fi
    msg_ok "Domain validation complete"
    msg_blank
}

### Interactive domain setup ###
interactive_domain_setup() {
    local choice
    if [[ -z "$DOMAIN" && -z "$REALITY_DOMAIN" ]]; then
        clear_all
        echo
        echo "Domain selection"
        echo
        echo "1) Use my own domains/subdomains"
        echo "2) Generate free domains automatically"
        echo
        while true; do
            read -rp "Select option [1-2]: " choice
            case "$choice" in
                1)
                    break
                ;;
                2)
                    AUTO_DOMAIN=true
                    export AUTO_DOMAIN
                    return
                ;;
                *)
                    msg_err "Please select 1 or 2"
                ;;
            esac
        done
    fi
    while true; do
        if [[ -z "$DOMAIN" ]]; then
            request_domain \
            DOMAIN \
                "Enter domain for panel" \
            || return 1
        fi
        if [[ -z "$REALITY_DOMAIN" ]]; then
            request_domain \
            REALITY_DOMAIN \
                "Enter domain for reality" \
            || return 1
        fi
        if [[ "$INSTALL_PROFILE" == "separate-xhttp-sni" && -z "$XHTTP_DOMAIN" ]]; then
            request_domain \
            XHTTP_DOMAIN \
                "Enter domain for XHTTP" \
            || return 1
        fi
        echo
        echo "Domain configuration"
        echo
        printf " %-20s %s\n" \
            "Panel Domain:" \
            "$DOMAIN"
        printf " %-20s %s\n" \
            "Reality Domain:" \
            "$REALITY_DOMAIN"
        if [[ "$INSTALL_PROFILE" == "separate-xhttp-sni" ]]; then
            printf " %-20s %s\n" \
                "XHTTP Domain:" \
                "$XHTTP_DOMAIN"
        fi
        echo
        read -rp "Is everything correct? [Y/n]: " choice
        case "$choice" in
            ""|y|Y)
                break
            ;;
            n|N)
                DOMAIN=""
                REALITY_DOMAIN=""
                XHTTP_DOMAIN=""
                echo
            ;;
            *)
                DOMAIN=""
                REALITY_DOMAIN=""
                XHTTP_DOMAIN=""
                echo
            ;;
        esac
    done
    export DOMAIN
    export REALITY_DOMAIN
}

### Get public IPv4 ###
get_public_ipv4() {
    local ip
    local normalized_ip
    ip=$(ip -4 route get 1.1.1.1 2>/dev/null \
        | awk '
            {
                for (i = 1; i <= NF; i++) {
                    if ($i == "src") {
                        print $(i + 1)
                        exit
                    }
                }
            }
        ' || true)
    if [[ -n "$ip" ]]; then
        normalized_ip=$(normalize_ipv4 "$ip") || normalized_ip=""
        if [[ -n "$normalized_ip" ]]; then
            echo "$normalized_ip"
            return 0
        fi
    fi
    ip=$(curl -4 -s \
        --connect-timeout 3 \
        --max-time 5 \
        ipv4.icanhazip.com 2>/dev/null \
        | tr -d '[:space:]' || true)
    if [[ -n "$ip" ]]; then
        normalized_ip=$(normalize_ipv4 "$ip") || normalized_ip=""
        if [[ -n "$normalized_ip" ]]; then
            echo "$normalized_ip"
            return 0
        fi
    fi
    return 0
}

### Get public IPv6 ###
get_public_ipv6() {
    local ip
    local normalized_ip
    ip=$(ip -6 route get 2620:fe::fe 2>/dev/null \
        | grep -Po 'src \K\S*' \
        | head -n1)
    if [[ -n "$ip" ]]; then
        normalized_ip=$(normalize_ipv6 "$ip") || normalized_ip=""
        if [[ -n "$normalized_ip" ]]; then
            echo "$normalized_ip"
            return 0
        fi
    fi
    ip=$(curl -6 -s \
        --connect-timeout 3 \
        --max-time 5 \
        ipv6.icanhazip.com 2>/dev/null \
        | tr -d '[:space:]' || true)
    if [[ -n "$ip" ]]; then
        normalized_ip=$(normalize_ipv6 "$ip") || normalized_ip=""
        if [[ -n "$normalized_ip" ]]; then
            echo "$normalized_ip"
            return 0
        fi
    fi
    return 0
}

### Detect public IP addresses ###
detect_public_ips() {
    PUBLIC_IP4=$(get_public_ipv4)
    if [[ -z "$PUBLIC_IP4" ]]; then
        msg_err "Failed to detect public IPv4"
        msg_err "IPv4 is required for this installer"
        return 1
    fi
    PUBLIC_IP6=$(get_public_ipv6)
    [[ -n "$PUBLIC_IP6" ]] || PUBLIC_IP6="absent"
    export PUBLIC_IP4
    export PUBLIC_IP6
    msg_inf "Detected VPS IPv4:" "${PUBLIC_IP4}"
    msg_inf "Detected VPS IPv6:" "${PUBLIC_IP6}"
    msg_blank
}

### Generate automatic domains ###
generate_auto_domains() {
    if [[ -z "$PUBLIC_IP4" ]]; then
        msg_err "PUBLIC_IP4 is not defined"
        return 1
    fi
    DOMAIN="${PUBLIC_IP4}.cdn-one.org"
    REALITY_DOMAIN="${PUBLIC_IP4//./-}.cdn-one.org"
    if [[ "$INSTALL_PROFILE" == "separate-xhttp-sni" ]]; then
        XHTTP_DOMAIN="x-${PUBLIC_IP4//./-}.cdn-one.org"
    fi
    export DOMAIN
    export REALITY_DOMAIN
    export XHTTP_DOMAIN
}
