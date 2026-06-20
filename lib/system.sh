# shellcheck shell=bash

### Require root privileges ###
require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        msg_err "Please run as root"
        exit 1
    fi
}

### Detect supported OS ###
detect_package_manager() {
    local os_id
    local version_id
    [[ -r /etc/os-release ]] || {
        msg_err "Unsupported OS: /etc/os-release not found"
        return 1
    }
    . /etc/os-release
    os_id="${ID:-}"
    version_id="${VERSION_ID:-}"
    case "${os_id}:${version_id}" in
        debian:12|ubuntu:24.04)
            PACKAGE_MANAGER="apt-get"
            return 0
            ;;
        *)
            msg_err "Unsupported OS: ${PRETTY_NAME:-unknown}"
            msg_err "Supported OS: Debian 12, Ubuntu 24.04"
            return 1
            ;;
    esac
}

### Install Packages ###
install_packages() {
    msg_inf "Updating package lists..."
    DEBIAN_FRONTEND=noninteractive "$PACKAGE_MANAGER" -y update >/dev/null 2>&1
    msg_inf "Installing required packages..."
    DEBIAN_FRONTEND=noninteractive "$PACKAGE_MANAGER" -y install \
        ca-certificates \
        openssl \
        curl \
        wget \
        tar \
        unzip \
        jq \
        bash \
        sudo \
        python3 \
        nginx-full \
        certbot \
        sqlite3 \
        dnsutils \
        iproute2 \
        ufw \
        >/dev/null 2>&1
    msg_ok "Packages installed"
    msg_blank
}

### Check fixed TCP ports before install ###
preflight_fixed_ports() {
    local ports=(80 443 7443 9443 8443)
    local port
    local conflicts=0
    if [[ "$INSTALL_PROFILE" == "separate-xhttp-sni" ]]; then
        ports+=(9444 8444)
    fi
    if ! command -v ss >/dev/null 2>&1; then
        msg_inf "Skipping fixed port preflight: ss not found"
        msg_blank
        return 0
    fi
    msg_inf "Checking fixed TCP ports..."
    for port in "${ports[@]}"; do
        if ss -H -ltn "sport = :${port}" 2>/dev/null | grep -q .; then
            msg_err "TCP port ${port} is already in use"
            ss -H -ltnp "sport = :${port}" 2>/dev/null \
                | sed 's/^/  /' || true
            conflicts=1
        fi
    done
    if (( conflicts != 0 )); then
        msg_err "Fixed port preflight failed"
        msg_err "Stop the conflicting service or run uninstall before installing again."
        return 1
    fi
    msg_ok "Fixed TCP ports are free"
    msg_blank
}

### Validate TCP port ###
is_valid_tcp_port() {
    local port="$1"
    [[ "${port}" =~ ^[0-9]+$ ]] && \
        (( port >= 1 && port <= 65535 ))
}

### Check if port is already in list ###
port_in_list() {
    local needle="$1"
    local item
    shift || true
    for item in "$@"; do
        [[ "${item}" == "${needle}" ]] && return 0
    done
    return 1
}

### Detect SSH ports ###
detect_ssh_ports() {
    local ports=()
    local port
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        port="$(echo "${SSH_CONNECTION}" | awk '{print $4}')"
        if is_valid_tcp_port "${port}" && \
            ! port_in_list "${port}" "${ports[@]}"
        then
            ports+=("${port}")
        fi
    fi
    while IFS= read -r port; do
        if is_valid_tcp_port "${port}" && \
            ! port_in_list "${port}" "${ports[@]}"
        then
            ports+=("${port}")
        fi
    done < <(
        ss -H -ltnp 2>/dev/null \
            | awk '
                /sshd/ {
                    addr = $4
                    n = split(addr, a, ":")
                    port = a[n]
                    sub(":" port "$", "", addr)
                    gsub(/^\[/, "", addr)
                    gsub(/\]$/, "", addr)
                    if (addr == "127.0.0.1" || addr == "::1" || addr ~ /^127\./) {
                        next
                    }
                    print port
                }
            '
    )
    while IFS= read -r port; do
        if is_valid_tcp_port "${port}" && \
            ! port_in_list "${port}" "${ports[@]}"
        then
            ports+=("${port}")
        fi
    done < <(
        sshd -T 2>/dev/null \
            | awk '/^port / { print $2 }'
    )
    if (( ${#ports[@]} == 0 )); then
        ports+=("22")
    fi
    printf '%s\n' "${ports[@]}"
}

### Configure UFW ###
configure_firewall() {
    local ssh_ports=()
    local ssh_port
    local ssh_ports_csv
    mapfile -t ssh_ports < <(detect_ssh_ports)
    ssh_ports_csv="$(IFS=,; echo "${ssh_ports[*]}")"
    msg_inf "Configuring firewall..."
    ufw --force reset >/dev/null 2>&1
    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1
    for ssh_port in "${ssh_ports[@]}"; do
        ufw allow "${ssh_port}/tcp" >/dev/null 2>&1
    done
    ufw allow 80/tcp >/dev/null 2>&1
    ufw allow 443/tcp >/dev/null 2>&1
    ### UDP transports reserve ###
    ### Currently the installer does not create UDP listeners.
    ### This rule is reserved for future Hysteria2 / QUIC-based transports.
    ufw allow 443/udp >/dev/null 2>&1
    ufw --force enable >/dev/null 2>&1
    msg_ok "Firewall configured and enabled: only ports 80/tcp, 443/tcp, 443/udp reserved and SSH TCP ports ${ssh_ports_csv} are open"
    msg_blank
}

### Error handler ###
on_error() {
    local line="$1"
    local command="$2"
    local rc="$3"
    echo
    echo "===== INSTALL FAILED ====="
    echo "LINE: ${line}"
    echo "COMMAND: ${command}"
    echo "EXIT CODE: ${rc}"
    echo "=========================="
    echo
    exit "$rc"
}
