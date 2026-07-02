# shellcheck shell=bash

### Install 3X-UI ###
install_xui() {
    local xui_arch
    local xui_version
    msg_inf "Installing official 3x-ui..."
    xui_arch=$(detect_xui_arch) || return 1
    cd /usr/local || return 1
    xui_version=$(get_xui_version) || return 1
    msg_inf "Selected 3x-ui version:" "${xui_version}"
    download_xui_release "$xui_version" "$xui_arch" || return 1
    stop_xui
    extract_xui_release || return 1
    cd /usr/local/x-ui || return 1
    install_xui_service "$xui_arch" || return 1
    msg_ok "3x-ui installed successfully"
    msg_blank
}

### Detect x-ui architecture ###
detect_xui_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)
            echo "amd64"
        ;;
        aarch64)
            echo "arm64"
        ;;
        armv7l)
            echo "arm32-v7a"
        ;;
        *)
            msg_err "Unsupported architecture: $arch"
            return 1
        ;;
    esac
}

### Normalize and validate x-ui version ###
normalize_xui_version() {
    local version="$1"
    local major
    local minor
    local patch
    if [[ "$version" == "latest" ]]; then
        echo "latest"
        return 0
    fi
    if [[ ! "$version" =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        msg_err "Invalid 3x-ui version: $version"
        msg_err "Expected format: latest, v3.3.1 or 3.3.1"
        return 1
    fi
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    patch="${BASH_REMATCH[3]}"
    if (( major < 3 )); then
        msg_err "Unsupported 3x-ui version: $version"
        msg_err "This installer supports only 3x-ui v3.0.0 and newer"
        return 1
    fi
    echo "v${major}.${minor}.${patch}"
}

### Get x-ui version ###
get_xui_version() {
    local version
    version="${XUI_VERSION:-latest}"
    if [[ "$version" != "latest" ]]; then
        normalize_xui_version "$version"
        return $?
    fi
    version=$(curl -Ls \
        --connect-timeout 5 \
        --max-time 15 \
        https://api.github.com/repos/MHSanaei/3x-ui/releases/latest \
        | jq -r .tag_name)
    if [[ -z "$version" || "$version" == "null" ]]; then
        msg_err "Failed to fetch latest 3x-ui version"
        return 1
    fi
    normalize_xui_version "$version"
}

### Download x-ui release ###
download_xui_release() {
    local version="$1"
    local arch="$2"
    wget -q -O x-ui.tar.gz \
    "https://github.com/MHSanaei/3x-ui/releases/download/${version}/x-ui-linux-${arch}.tar.gz" \
    || {
        msg_err "Failed to download 3x-ui release"
        return 1
    }
}

### Extract x-ui release ###
extract_xui_release() {
    rm -rf /usr/local/x-ui
    tar zxf x-ui.tar.gz || {
        msg_err "Failed to extract x-ui release"
        return 1
    }
    rm -f x-ui.tar.gz
}

### Install x-ui service ###
install_xui_service() {
    local xui_arch="$1"
    chmod +x x-ui
    chmod +x x-ui.sh
    chmod +x "bin/xray-linux-${xui_arch}"
    ln -sf /usr/local/x-ui/x-ui.sh /usr/bin/x-ui
    cp -f x-ui.service.debian \
        /etc/systemd/system/x-ui.service
    systemctl daemon-reload
    systemctl enable x-ui >/dev/null 2>&1
    systemctl start x-ui || {
        msg_err "Failed to start x-ui service"
        return 1
    }
}

### Wait x-ui ready ###
wait_xui_ready() {
    local retries=30
    while (( retries > 0 )); do
        if systemctl is-active --quiet x-ui; then
            return 0
        fi
        sleep 1
        ((retries--))
    done
    msg_err "x-ui failed to start"
    systemctl status x-ui --no-pager || true
    journalctl -u x-ui -n 40 --no-pager || true
    return 1
}

### Stop x-ui ###
stop_xui() {
    systemctl stop x-ui >/dev/null 2>&1 || true
}

### Configure x-ui credentials ###
configure_xui_credentials() {
    /usr/local/x-ui/x-ui setting \
        -username "${PANEL_USERNAME}" \
        -password "${PANEL_PASSWORD}" \
        >/dev/null 2>&1 \
        || {
            msg_err "Failed to configure x-ui credentials"
            return 1
        }
}

### Update geo files ###
update_xui_geofiles() {
    msg_inf "Updating geo files..."
    x-ui update-all-geofiles >/dev/null 2>&1 || {
        msg_err "Failed to update geo files"
        return 1
    }
    msg_ok "Geo files updated"
    msg_blank
}

### Restart x-ui ###
restart_xui() {
    systemctl restart x-ui || {
        msg_err "Failed to restart x-ui service"
        systemctl status x-ui --no-pager || true
        journalctl -u x-ui -n 40 --no-pager || true
        return 1
    }
}

### Cleanup previous x-ui database ###
cleanup_previous_database() {
    systemctl stop x-ui 2>/dev/null || true
    rm -f /etc/x-ui/x-ui.db
    rm -f /etc/x-ui/x-ui.db-shm
    rm -f /etc/x-ui/x-ui.db-wal
}

### Optional Fail2ban / IP Limit setup ###
maybe_setup_xui_fail2ban() {
    msg_blank
    if ! command -v x-ui >/dev/null 2>&1; then
        msg_blank
        msg_warn "x-ui CLI not found; skipping Fail2ban/IP Limit setup."
        msg_blank
        return 0
    fi
    local f2b_installed=0
    local f2b_active=0
    local jail_ready=0
    local mode=""
    local answer=""
    local setup_log=""
    if command -v fail2ban-client >/dev/null 2>&1; then
        f2b_installed=1
    fi
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        f2b_active=1
    fi
    if [[ "${f2b_installed}" == "1" ]] \
        && fail2ban-client status 3x-ipl >/dev/null 2>&1; then
        jail_ready=1
    fi
    if [[ "${f2b_installed}" == "1" \
        && "${f2b_active}" == "1" \
        && "${jail_ready}" == "1" ]]; then
        msg_blank
        msg_ok "Fail2ban/IP Limit already configured."
        msg_blank
        return 0
    fi
    mode="${XUI_INSTALLER_FAIL2BAN:-}"
    if [[ -z "${mode}" ]]; then
        if [[ -r /dev/tty && -w /dev/tty ]]; then
            mode="ask"
        else
            mode="no"
        fi
    fi
    case "${mode}" in
        yes|YES|y|Y|true|TRUE|1)
            ;;
        no|NO|n|N|false|FALSE|0)
            msg_blank
            msg_inf "Skipping Fail2ban/IP Limit setup."
            msg_inf "You can enable it later with: x-ui setup-fail2ban"
            msg_blank
            return 0
            ;;
        ask)
            if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
                msg_blank
                msg_inf "Skipping Fail2ban/IP Limit setup."
                msg_inf "You can enable it later with: x-ui setup-fail2ban"
                msg_blank
                return 0
            fi
            printf "\e[1;33mInstall and configure Fail2ban for 3x-ui IP Limit now? [y/N]: \e[0m" >/dev/tty
            read -r answer </dev/tty || answer=""
            case "${answer}" in
                y|Y|yes|YES)
                    ;;
                *)
                    msg_blank
                    msg_inf "Skipping Fail2ban/IP Limit setup."
                    msg_inf "You can enable it later with: x-ui setup-fail2ban"
                    msg_blank
                    return 0
                    ;;
            esac
            ;;
        *)
            msg_blank
            msg_warn "Unknown XUI_INSTALLER_FAIL2BAN='${mode}', skipping Fail2ban setup."
            msg_inf "Use XUI_INSTALLER_FAIL2BAN=yes to enable it automatically."
            msg_blank
            return 0
            ;;
    esac
    setup_log="$(mktemp /tmp/xui-fail2ban-setup.XXXXXX.log)"
    if x-ui setup-fail2ban >"${setup_log}" 2>&1; then
        if command -v fail2ban-client >/dev/null 2>&1 \
            && fail2ban-client -t >/dev/null 2>&1 \
            && systemctl is-active --quiet fail2ban 2>/dev/null \
            && fail2ban-client status 3x-ipl >/dev/null 2>&1; then
            rm -f "${setup_log}"
            msg_blank
            msg_ok "Fail2ban/IP Limit installed and configured."
            msg_blank
        else
            msg_blank
            msg_warn "Fail2ban setup finished, but verification failed."
            msg_warn "Check manually with: fail2ban-client status 3x-ipl"
            msg_warn "Setup log: ${setup_log}"
            msg_blank
        fi
    else
        msg_blank
        msg_warn "Fail2ban setup failed. Continuing without Fail2ban."
        msg_warn "Setup log: ${setup_log}"
        msg_warn "You can retry later with: x-ui setup-fail2ban"
        msg_blank
    fi
    return 0
}
