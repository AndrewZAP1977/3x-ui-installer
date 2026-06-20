# shellcheck shell=bash

### Generate UUID ###
generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

### Generate client secrets ###
generate_client_secrets() {
    CLIENT_EMAIL="default_client"
    CLIENT_SUB_ID=$(gen_random_string 16)
    CLIENT_AUTH=$(gen_random_string 16)
    CLIENT_PASSWORD=$(gen_random_string 16)
}

### Generate panel credentials ###
generate_panel_credentials() {
    PANEL_USERNAME="admin"
    PANEL_PASSWORD=$(gen_random_string 20)
}

### Generate X25519 Reality keys ###
generate_reality_keys() {
    local xui_arch
    local xray_binary
    local xray_keys
    xui_arch=$(detect_xui_arch) || return 1
    xray_binary="/usr/local/x-ui/bin/xray-linux-${xui_arch}"
    if [[ ! -x "$xray_binary" ]]; then
        msg_err "Xray binary not found or not executable"
        msg_err "Path: $xray_binary"
        return 1
    fi
    xray_keys=$("$xray_binary" x25519 2>/dev/null) || {
        msg_err "Failed to generate Reality X25519 keys"
        msg_err "Binary: $xray_binary"
        return 1
    }
    PRIVATE_KEY=$(awk -F': ' '/^PrivateKey:/ {print $2}' <<< "$xray_keys")
    PUBLIC_KEY=$(awk -F': ' '/PublicKey/ {print $2}' <<< "$xray_keys")
    if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
        echo
        echo "===== XRAY X25519 OUTPUT ====="
        echo "$xray_keys"
        echo
        msg_err "Failed to parse Reality X25519 keys"
        return 1
    fi
}

### Generate short IDs ###
generate_short_ids() {
    SHORT_IDS=()
    for _ in {1..8}; do
        local bytes=$(( RANDOM % 8 + 1 ))
        SHORT_IDS+=(
            "$(openssl rand -hex "$bytes")"
        )
    done
}

### Generate current timestamp ###
generate_current_timestamp() {
    CURRENT_MS=$(( $(date +%s) * 1000 ))
}

### Generate all runtime secrets ###
generate_runtime_secrets() {
    XRAY_UUID=$(generate_uuid)
    generate_client_secrets
    generate_panel_credentials
    generate_reality_keys
    generate_short_ids
    generate_current_timestamp
}

### Generate runtime variables ###
generate_runtime_variables() {
    PANEL_PORT=$(make_port)
    while true; do
        SUB_PORT=$(make_port)
        if [[ "$SUB_PORT" != "$PANEL_PORT" ]]; then
            break
        fi
    done
    PANEL_PATH=$(gen_random_string 10)
    SUB_PATH=$(gen_random_string 10)
    XHTTP_PATH=$(gen_random_string 10)
    XHTTP_SOCKET="/dev/shm/xui-$(gen_random_string 6).sock"
}

### Generate runtime uris ###
generate_runtime_uris() {
    SUB_URI="https://${DOMAIN}/${SUB_PATH}/"
}

### Build runtime context ###
build_runtime_context() {
    export PANEL_PORT
    export PANEL_PATH
    export SUB_PORT
    export SUB_PATH
    export XHTTP_PATH
    export XHTTP_SOCKET
    export SUB_URI
    export XRAY_UUID
    export CLIENT_EMAIL
    export CLIENT_SUB_ID
    export CLIENT_AUTH
    export CLIENT_PASSWORD
    export PRIVATE_KEY
    export PUBLIC_KEY
    export CURRENT_MS
    export SHORT_IDS
    export PANEL_USERNAME
    export PANEL_PASSWORD
}

### Smoke-check systemd service ###
smoke_check_service() {
    local service="$1"
    if systemctl is-active --quiet "$service"; then
        return 0
    fi
    msg_err "Smoke-check failed: service is not active: $service"
    systemctl status "$service" --no-pager || true
    return 1
}

### Smoke-check nginx config ###
smoke_check_nginx_config() {
    nginx -t >/dev/null 2>&1 || {
        msg_err "Smoke-check failed: nginx config is invalid"
        nginx -t || true
        return 1
    }
}

### Smoke-check TCP listener ###
smoke_check_tcp_listener() {
    local name="$1"
    local port="$2"
    local retries=30
    while (( retries > 0 )); do
        if ss -H -ltn "sport = :${port}" 2>/dev/null | grep -q .; then
            return 0
        fi
        sleep 1
        ((retries--))
    done
    msg_err "Smoke-check failed: TCP listener not found: ${name} on port ${port}"
    ss -ltnp | grep -E ":${port}\\b" || true
    return 1
}

### Smoke-check Unix socket ###
smoke_check_unix_socket() {
    local name="$1"
    local socket_path="$2"
    local retries=15
    while (( retries > 0 )); do
        if [[ -S "$socket_path" ]]; then
            return 0
        fi
        sleep 1
        ((retries--))
    done
    msg_err "Smoke-check failed: Unix socket not found: ${name}"
    msg_err "Socket path: ${socket_path}"
    return 1
}

### Smoke-check HTTPS URL through local nginx SNI ###
smoke_check_https_url() {
    local name="$1"
    local host="$2"
    local url="$3"
    local code
    code=$(curl -skL \
        --connect-timeout 5 \
        --max-time 20 \
        --resolve "${host}:443:127.0.0.1" \
        -o /dev/null \
        -w "%{http_code}" \
        "$url" \
        2>/dev/null || true)
    case "$code" in
        2*|3*|401|403)
            return 0
            ;;
        *)
            msg_err "Smoke-check failed: ${name}"
            msg_err "URL: ${url}"
            msg_err "HTTP code: ${code:-000}"
            return 1
            ;;
    esac
}

### Smoke-check panel URL ###
smoke_check_panel_url() {
    local name="$1"
    local host="$2"
    local url="$3"
    local code
    local body_file
    body_file=$(mktemp /tmp/xui-panel-smoke.XXXXXX)
    code=$(curl -skL \
        --connect-timeout 5 \
        --max-time 20 \
        --resolve "${host}:443:127.0.0.1" \
        -o "$body_file" \
        -w "%{http_code}" \
        "$url" \
        2>/dev/null || true)
    case "$code" in
        2*|3*|401|403)
            ;;
        *)
            rm -f "$body_file"
            msg_err "Smoke-check failed: ${name}"
            msg_err "URL: ${url}"
            msg_err "HTTP code: ${code:-000}"
            return 1
            ;;
    esac
    if [[ ! -s "$body_file" ]]; then
        rm -f "$body_file"
        msg_err "Smoke-check failed: ${name}"
        msg_err "URL: ${url}"
        msg_err "Panel response is empty"
        return 1
    fi
    if ! grep -qiE '3x-ui|x-ui|/assets/' "$body_file"; then
        rm -f "$body_file"
        msg_err "Smoke-check failed: ${name}"
        msg_err "URL: ${url}"
        msg_err "Panel response does not look like 3x-ui"
        return 1
    fi
    rm -f "$body_file"
}

### Smoke-check subscription URL ###
smoke_check_subscription_url() {
    local name="$1"
    local host="$2"
    local url="$3"
    local code
    local body_file
    body_file=$(mktemp /tmp/xui-sub-smoke.XXXXXX)
    code=$(curl -skL \
        --connect-timeout 5 \
        --max-time 20 \
        --resolve "${host}:443:127.0.0.1" \
        -o "$body_file" \
        -w "%{http_code}" \
        "$url" \
        2>/dev/null || true)
    case "$code" in
        2*|3*)
            ;;
        *)
            rm -f "$body_file"
            msg_err "Smoke-check failed: ${name}"
            msg_err "URL: ${url}"
            msg_err "HTTP code: ${code:-000}"
            return 1
            ;;
    esac
    if [[ ! -s "$body_file" ]]; then
        rm -f "$body_file"
        msg_err "Smoke-check failed: ${name}"
        msg_err "URL: ${url}"
        msg_err "Subscription response is empty"
        return 1
    fi
    if grep -qiE '<!doctype|<html|<head|<body' "$body_file"; then
        rm -f "$body_file"
        msg_err "Smoke-check failed: ${name}"
        msg_err "URL: ${url}"
        msg_err "Subscription response looks like HTML fake site"
        return 1
    fi
    rm -f "$body_file"
}

### Run post-install smoke checks ###
run_smoke_checks() {
    msg_inf "Running smoke checks..."
    ### Services ###
    smoke_check_service "nginx"
    smoke_check_service "x-ui"
    ### Nginx config ###
    smoke_check_nginx_config
    ### Common TCP listeners ###
    smoke_check_tcp_listener "public HTTPS / SNI stream" "443"
    smoke_check_tcp_listener "panel nginx backend" "7443"
    smoke_check_tcp_listener "reality fallback nginx backend" "9443"
    smoke_check_tcp_listener "3x-ui panel" "$PANEL_PORT"
    smoke_check_tcp_listener "3x-ui subscription" "$SUB_PORT"
    smoke_check_tcp_listener "Xray REALITY inbound" "8443"
    if [[ "$INSTALL_PROFILE" == "separate-xhttp-sni" ]]; then
        smoke_check_tcp_listener "xhttp fallback nginx backend" "9444"
        smoke_check_tcp_listener "Xray XHTTP REALITY inbound" "8444"
    else
        ### Baseline XHTTP Unix socket ###
        smoke_check_unix_socket "XHTTP inbound" "$XHTTP_SOCKET"
    fi
    ### HTTPS routes through local nginx with SNI ###
    smoke_check_https_url \
        "panel fake site" \
        "$DOMAIN" \
        "https://${DOMAIN}/"
    smoke_check_https_url \
        "reality fake site" \
        "$REALITY_DOMAIN" \
        "https://${REALITY_DOMAIN}/"
    if [[ "$INSTALL_PROFILE" == "separate-xhttp-sni" ]]; then
        smoke_check_https_url \
            "xhttp fake site" \
            "$XHTTP_DOMAIN" \
            "https://${XHTTP_DOMAIN}/"
    fi
    smoke_check_panel_url \
        "panel URL" \
        "$DOMAIN" \
        "https://${DOMAIN}/${PANEL_PATH}/"
    smoke_check_subscription_url \
        "subscription URL" \
        "$DOMAIN" \
        "${SUB_URI}${CLIENT_SUB_ID}"
    msg_ok "Smoke checks passed"
    msg_blank
}

### Clear All ###
clear_all() {
    if [[ -t 1 ]]; then
        clear || true
    fi
}

### Wait before showing summary ###
wait_before_summary() {
    if [[ ! -t 0 ]]; then
        return 0
    fi
    msg_blank
    read -rp "Press Enter to show installation summary..."
}

### Final installation summary ###
show_summary() {
    clear_all
    echo
    echo "=========================================================="
    echo
    echo    "3X-UI INSTALLATION COMPLETED"
    echo
    echo    "Username:"
    echo    "${PANEL_USERNAME}"
    echo
    echo    "Password:"
    echo    "${PANEL_PASSWORD}"
    echo
    echo    "Panel URL:"
    echo    "https://${DOMAIN}/${PANEL_PATH}/"
    echo
    echo    "Subscription URL:"
    echo    "${SUB_URI}${CLIENT_SUB_ID}"
    echo
    echo    "Fake Site #1:"
    echo    "https://${DOMAIN}"
    echo
    echo    "Fake Site #2:"
    echo    "https://${REALITY_DOMAIN}"
    echo
    if [[ "$INSTALL_PROFILE" == "separate-xhttp-sni" ]]; then
        echo    "Fake Site #3:"
        echo    "https://${XHTTP_DOMAIN}"
        echo
    fi
    echo "=========================================================="
    echo
    echo "Save this information before closing the terminal."
    echo
    echo "=========================================================="
}
