# shellcheck shell=bash

### Uninstall settings ###
readonly UNINSTALL_PURGE_PACKAGES=(
    nginx
    nginx-full
    nginx-common
    nginx-core
    sqlite3
    dnsutils
    bind9-dnsutils
    bind9-host
    bind9-libs
    ufw
    jq
    unzip
    wget
)
readonly UNINSTALL_REMOVE_PACKAGES=(
    certbot
    python3-certbot-nginx
)

### Confirm uninstall ###
confirm_uninstall() {
    local answer
    msg_blank
    msg_err "WARNING: destructive uninstall mode"
    msg_blank
    cat <<'EOF'
This will remove components installed by this project:

- 3x-ui service and files
- generated Nginx configuration
- fake sites
- randomfakehtml repository
- Certbot webroot challenge files
- Nginx and Certbot packages
- UFW rules and UFW package
- installer temporary files and generated leftovers
- downloaded installer directory

Let's Encrypt certificates and Certbot account data are preserved.

This mode is intended only for a clean VPS where this installer owns the setup.

Type DELETE to continue.
EOF
    msg_blank
    read -rp "Confirm uninstall: " answer
    if [[ "$answer" != "DELETE" ]]; then
        msg_err "Uninstall cancelled"
        exit 1
    fi
    msg_blank
}

### Remove path ###
remove_path() {
    local path="$1"
    if [[ -e "$path" || -L "$path" ]]; then
        rm -rf "$path"
    fi
}

### Validate installer directory removal path ###
validate_uninstall_installer_dir() {
    local dir="$1"
    local canonical_dir
    if [[ -z "${dir}" || "${dir}" != /* ]]; then
        msg_err "Unsafe installer directory: ${dir:-<empty>}"
        exit 1
    fi
    if ! command -v realpath >/dev/null 2>&1; then
        msg_err "realpath is required"
        exit 1
    fi
    canonical_dir="$(realpath -m -- "${dir}")"
    case "${canonical_dir}" in
        /root/3x-ui-installer|/root/3x-ui-installer-*)
            ;;
        *)
            msg_err "Unsafe installer directory: ${canonical_dir}"
            msg_err "Allowed paths: /root/3x-ui-installer or /root/3x-ui-installer-*"
            exit 1
            ;;
    esac
    if [[ -e "${canonical_dir}" && ! -d "${canonical_dir}" ]]; then
        msg_err "Installer path exists but is not a directory: ${canonical_dir}"
        exit 1
    fi
    if [[ -d "${canonical_dir}" \
        && ! -f "${canonical_dir}/.xui-installer-owned" \
        && ! -f "${canonical_dir}/install.sh" ]]; then
        msg_err "Refusing to remove unowned installer directory: ${canonical_dir}"
        msg_err "Remove it manually if you are sure it is safe."
        exit 1
    fi
    UNINSTALL_INSTALLER_DIR="${canonical_dir}"
}

### Stop and disable service ###
stop_disable_service() {
    local service="$1"
    systemctl stop "$service" 2>/dev/null || true
    systemctl disable "$service" 2>/dev/null || true
}

### Remove 3x-ui ###
uninstall_xui_files() {
    msg_inf "Removing 3x-ui files..."
    stop_disable_service "x-ui"
    remove_path "/etc/systemd/system/x-ui.service"
    remove_path "/usr/local/x-ui"
    remove_path "/etc/x-ui"
    remove_path "/usr/bin/x-ui"
    remove_path "/usr/local/bin/x-ui"
    remove_path "/var/log/x-ui"
    remove_path "/var/lib/x-ui"
    systemctl daemon-reload 2>/dev/null || true
    msg_ok "3x-ui files removed"
}

### Remove Nginx generated files ###
uninstall_nginx_files() {
    msg_inf "Removing Nginx files..."
    stop_disable_service "nginx"
    remove_path "/etc/nginx"
    remove_path "/var/log/nginx"
    remove_path "/var/cache/nginx"
    remove_path "/var/lib/nginx"
    remove_path "/run/nginx.pid"
    msg_ok "Nginx files removed"
}

### Remove Certbot webroot files ###
uninstall_certbot_files() {
    msg_inf "Removing Certbot webroot files..."
    remove_path "/var/www/letsencrypt"
    msg_ok "Certbot webroot files removed"
}

### Remove fake sites ###
uninstall_fake_sites() {
    msg_inf "Removing fake sites..."
    remove_path "/opt/randomfakehtml"
    remove_path "/var/www/html/fakesite_1"
    remove_path "/var/www/html/fakesite_2"
    remove_path "/var/www/html/fakesite_3"
    rmdir --ignore-fail-on-non-empty "/var/www/html" 2>/dev/null || true
    rmdir --ignore-fail-on-non-empty "/var/www" 2>/dev/null || true
    remove_path "/tmp/randomfakehtml.zip"
    remove_path "/tmp/randomfakehtml-master"
    msg_ok "Fake sites removed"
}

### Remove temporary runtime leftovers ###
uninstall_runtime_leftovers() {
    msg_inf "Removing runtime leftovers..."
    find /dev/shm \
        -maxdepth 1 \
        -type s \
        -name 'xui-*.sock' \
        -delete 2>/dev/null || true
    msg_ok "Runtime leftovers removed"
}

### Reset firewall ###
uninstall_firewall() {
    msg_inf "Resetting firewall..."
    if command -v ufw >/dev/null 2>&1; then
        ufw --force reset >/dev/null 2>&1 || true
        ufw --force disable >/dev/null 2>&1 || true
    fi
    msg_ok "Firewall reset"
}

### Remove packages ###
uninstall_packages() {
    msg_inf "Removing packages..."
    if ! command -v apt-get >/dev/null 2>&1; then
        msg_err "apt-get not found; package removal skipped"
        return 0
    fi
    DEBIAN_FRONTEND=noninteractive apt-get remove -y \
        "${UNINSTALL_REMOVE_PACKAGES[@]}" \
        >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get purge -y \
        "${UNINSTALL_PURGE_PACKAGES[@]}" \
        >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -y \
        >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get autoclean -y \
        >/dev/null 2>&1 || true
    msg_ok "Packages removed"
}

### Run uninstall ###
run_uninstall() {
    confirm_uninstall
    msg_inf "Uninstall started"
    msg_blank
    uninstall_xui_files
    uninstall_nginx_files
    uninstall_certbot_files
    uninstall_fake_sites
    uninstall_runtime_leftovers
    uninstall_firewall
    uninstall_packages
    uninstall_installer_files
    msg_blank
    msg_ok "Uninstall completed successfully !!!"
    msg_blank
    cat <<'EOF'
Kept basic system packages:

- bash
- sudo
- python3
- curl
- ca-certificates
- openssl
- iproute2
EOF
    msg_blank
}

### Remove installer files ###
uninstall_installer_files() {
    local installer_dir
    installer_dir="${XUI_INSTALLER_DIR:-/root/3x-ui-installer}"
    msg_inf "Removing installer files..."
    validate_uninstall_installer_dir "${installer_dir}"
    installer_dir="${UNINSTALL_INSTALLER_DIR}"
    remove_path "${installer_dir}"
    msg_ok "Installer files removed"
}

### Handle uninstall mode ###
handle_uninstall_mode() {
    if [[ "$UNINSTALL_MODE" != true ]]; then
        return 0
    fi
    clear_all
    run_uninstall
    exit 0
}
