# shellcheck shell=bash

### Create required nginx directories ###
prepare_nginx_directories() {
    mkdir -p /var/www/letsencrypt
    mkdir -p /etc/nginx/stream-enabled
    mkdir -p /etc/nginx/snippets
    mkdir -p /etc/nginx/sites-enabled
    mkdir -p /etc/nginx/sites-available
    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/sites-available/default
    rm -f /etc/nginx/sites-enabled/80.conf
    rm -f /etc/nginx/sites-enabled/panel.conf
    rm -f /etc/nginx/sites-enabled/reality.conf
    rm -f /etc/nginx/sites-enabled/xhttp.conf
    rm -f /etc/nginx/sites-available/80.conf
    rm -f /etc/nginx/sites-available/panel.conf
    rm -f /etc/nginx/sites-available/reality.conf
    rm -f /etc/nginx/sites-available/xhttp.conf
    rm -f /etc/nginx/snippets/includes.conf
    rm -f /etc/nginx/snippets/panel_includes.conf
    rm -f /etc/nginx/snippets/reality_includes.conf
    rm -f /etc/nginx/snippets/xhttp_includes.conf
    rm -f /etc/nginx/stream-enabled/stream.conf
}

### Validate nginx configuration ###
validate_nginx_config() {
    nginx -t >/dev/null 2>&1 || {
        msg_err "Nginx configuration validation failed"
        return 1
    }
}

### Prepare nginx ###
prepare_nginx() {
    prepare_nginx_directories
}

### Render bootstrap nginx templates ###
render_bootstrap_nginx() {
    render_template \
        "${SCRIPT_DIR}/templates/nginx.conf.template" \
        "/etc/nginx/nginx.conf"
    render_template \
        "${SCRIPT_DIR}/templates/80.conf.template" \
        "/etc/nginx/sites-available/80.conf"
}

### Render nginx templates ###
render_nginx_templates() {
    render_template \
        "${SCRIPT_DIR}/templates/80.conf.template" \
        "/etc/nginx/sites-available/80.conf"
    render_template \
        "${SCRIPT_DIR}/templates/panel.conf.template" \
        "/etc/nginx/sites-available/panel.conf"
    render_template \
        "${SCRIPT_DIR}/templates/reality.conf.template" \
        "/etc/nginx/sites-available/reality.conf"
    if [[ "$INSTALL_PROFILE" == "separate-xhttp-sni" ]]; then
        render_template \
            "${SCRIPT_DIR}/templates/xhttp.conf.template" \
            "/etc/nginx/sites-available/xhttp.conf"
    fi
    render_template \
        "${SCRIPT_DIR}/templates/panel_includes.conf.template" \
        "/etc/nginx/snippets/panel_includes.conf"
    render_template \
        "${SCRIPT_DIR}/templates/reality_includes.conf.template" \
        "/etc/nginx/snippets/reality_includes.conf"
    if [[ "$INSTALL_PROFILE" == "separate-xhttp-sni" ]]; then
        render_template \
            "${SCRIPT_DIR}/templates/xhttp_includes.conf.template" \
            "/etc/nginx/snippets/xhttp_includes.conf"
    fi
    render_template \
        "${SCRIPT_DIR}/templates/nginx.conf.template" \
        "/etc/nginx/nginx.conf"
    render_template \
        "${SCRIPT_DIR}/templates/stream.conf.template" \
        "/etc/nginx/stream-enabled/stream.conf"
}

### Validate nginx ###
validate_nginx() {
    validate_nginx_config
}

### Reload nginx ###
reload_nginx() {
    systemctl enable nginx >/dev/null 2>&1
    if ! systemctl restart nginx; then
        msg_err "Failed to reload nginx"
        return 1
    fi
}

### Enable bootstrap configs ###
enable_bootstrap_configs() {
    mkdir -p /etc/nginx/sites-enabled
    ln -sf \
        /etc/nginx/sites-available/80.conf \
        /etc/nginx/sites-enabled/80.conf
}

### Enable TLS configs ###
enable_tls_configs() {
    mkdir -p /etc/nginx/sites-enabled
    ln -sf \
        /etc/nginx/sites-available/panel.conf \
        /etc/nginx/sites-enabled/panel.conf
    ln -sf \
        /etc/nginx/sites-available/reality.conf \
        /etc/nginx/sites-enabled/reality.conf
    if [[ "$INSTALL_PROFILE" == "separate-xhttp-sni" ]]; then
        ln -sf \
            /etc/nginx/sites-available/xhttp.conf \
            /etc/nginx/sites-enabled/xhttp.conf
    fi
}

### Render template file ###
render_template() {
    local template_file="$1"
    local output_file="$2"
    local xhttp_server_name=""
    local xhttp_stream_map=""
    local xhttp_stream_upstream=""
    if [[ "$INSTALL_PROFILE" == "separate-xhttp-sni" ]]; then
        xhttp_server_name=" ${XHTTP_DOMAIN}"
        xhttp_stream_map="${XHTTP_DOMAIN}  xray2;"
        xhttp_stream_upstream="upstream xray2 { server 127.0.0.1:8444; }"
    fi
    sed \
        -e "s|{{DOMAIN}}|$DOMAIN|g" \
        -e "s|{{REALITY_DOMAIN}}|$REALITY_DOMAIN|g" \
        -e "s|{{XHTTP_DOMAIN}}|$XHTTP_DOMAIN|g" \
        -e "s|{{XHTTP_SERVER_NAME}}|$xhttp_server_name|g" \
        -e "s|{{XHTTP_STREAM_MAP}}|$xhttp_stream_map|g" \
        -e "s|{{XHTTP_STREAM_UPSTREAM}}|$xhttp_stream_upstream|g" \
        -e "s|{{PANEL_PORT}}|$PANEL_PORT|g" \
        -e "s|{{PANEL_PATH}}|$PANEL_PATH|g" \
        -e "s|{{SUB_PORT}}|$SUB_PORT|g" \
        -e "s|{{SUB_PATH}}|$SUB_PATH|g" \
        -e "s|{{XHTTP_PATH}}|$XHTTP_PATH|g" \
        -e "s|{{XHTTP_SOCKET}}|$XHTTP_SOCKET|g" \
        -e "s|{{FAKESITE1_ROOT}}|/var/www/html/fakesite_1/|g" \
        -e "s|{{FAKESITE2_ROOT}}|/var/www/html/fakesite_2/|g" \
        -e "s|{{FAKESITE3_ROOT}}|/var/www/html/fakesite_3/|g" \
        "$template_file" > "$output_file"
}

### Request SSL certificate ###
request_ssl_certificate() {
    local domain="$1"
    local log_dir="/var/log/3x-ui-installer"
    local safe_domain
    local log_file
    local diagnostic_lines
    if certificate_exists "$domain"; then
        validate_certificate "$domain" && return 0
    fi
    mkdir -p "$log_dir"
    safe_domain="${domain//[^a-zA-Z0-9._-]/_}"
    log_file="${log_dir}/certbot-${safe_domain}.log"
    if ! certbot certonly \
        --webroot \
        -w /var/www/letsencrypt \
        -d "$domain" \
        --agree-tos \
        --register-unsafely-without-email \
        --non-interactive \
        >"$log_file" 2>&1; then
        msg_err "Failed to request SSL certificate for $domain"
        diagnostic_lines="$(
            grep -Ei \
                "too many|rate|limit|unauthorized|invalid|timeout|connection|refused|nxdomain|servfail|detail|error|failed" \
                "$log_file" | tail -n 5 || true
        )"
        if [[ -n "$diagnostic_lines" ]]; then
            msg_inf "Certbot diagnostic lines:"
            printf '%s\n' "$diagnostic_lines" | sed 's/^/  /'
        fi
        msg_inf "Full Certbot log:"
        echo "  $log_file"
        msg_inf "Show details:"
        echo "  tail -n 80 $log_file"
        return 1
    fi
    validate_certificate "$domain"
}

### Check certificate exists ###
certificate_exists() {
    local domain="$1"
    [[ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]] && \
    [[ -f "/etc/letsencrypt/live/${domain}/privkey.pem" ]]
}

### Validate SSL certificate ###
validate_certificate() {
    local domain="$1"
    openssl x509 \
        -in "/etc/letsencrypt/live/${domain}/fullchain.pem" \
        -noout \
        -checkend 86400 \
        >/dev/null 2>&1 \
        || {
            msg_err "SSL certificate is missing or expired for $domain"
            return 1
        }
}

### Request SSL certificates ###
request_ssl_certificates() {
    msg_inf "Requesting SSL certificates..."
    request_ssl_certificate "$DOMAIN"
    request_ssl_certificate "$REALITY_DOMAIN"
    if [[ "$INSTALL_PROFILE" == "separate-xhttp-sni" ]]; then
        request_ssl_certificate "$XHTTP_DOMAIN"
    fi
    msg_ok "SSL certificates are ready"
    msg_blank
}
