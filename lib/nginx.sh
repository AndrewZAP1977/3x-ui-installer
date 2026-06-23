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
    if [[ "$INSTALL_PROFILE" == "separate-xhttp-sni" ]]; then
        render_template \
            "${SCRIPT_DIR}/templates/fake_site_includes.conf.template" \
            "/etc/nginx/snippets/reality_includes.conf"
        render_template \
            "${SCRIPT_DIR}/templates/fake_site_includes.conf.template" \
            "/etc/nginx/snippets/xhttp_includes.conf"
    else
        render_template \
            "${SCRIPT_DIR}/templates/reality_includes.conf.template" \
            "/etc/nginx/snippets/reality_includes.conf"
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
        if validate_certificate "$domain"; then
            normalize_certbot_renewal_config "$domain"
            return 0
        fi
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
    validate_certificate "$domain" || return 1
    normalize_certbot_renewal_config "$domain"
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

### Check if Certbot renewal config already uses target webroot ###
certbot_renewal_config_is_normalized() {
    local domain="$1"
    local renewal_file="$2"
    local webroot="/var/www/letsencrypt"
    awk -v domain="$domain" -v webroot="$webroot" '
        function trim(value) {
            gsub(/^[ \t]+|[ \t]+$/, "", value)
            return value
        }
        BEGIN {
            authenticator_ok = 0
            webroot_path_ok = 0
            webroot_map_ok = 0
            in_webroot_map = 0
        }
        /^[[:space:]]*\[\[webroot_map\]\][[:space:]]*$/ {
            in_webroot_map = 1
            next
        }
        in_webroot_map && /^[[:space:]]*\[/ {
            in_webroot_map = 0
        }
        /^[[:space:]]*authenticator[[:space:]]*=/ {
            value = $0
            sub(/^[^=]*=/, "", value)
            value = trim(value)
            if (value == "webroot") {
                authenticator_ok = 1
            }
        }
        /^[[:space:]]*webroot_path[[:space:]]*=/ {
            value = $0
            sub(/^[^=]*=/, "", value)
            value = trim(value)
            if (value == webroot) {
                webroot_path_ok = 1
            }
        }
        in_webroot_map && /^[[:space:]]*[^#[:space:]][^=]*=/ {
            key = $0
            sub(/[[:space:]]*=.*/, "", key)
            key = trim(key)
            value = $0
            sub(/^[^=]*=/, "", value)
            value = trim(value)
            if (key == domain && value == webroot) {
                webroot_map_ok = 1
            }
        }
        END {
            if (authenticator_ok && webroot_path_ok && webroot_map_ok) {
                exit 0
            }
            exit 1
        }
    ' "$renewal_file"
}

### Normalize existing Certbot renewal config to webroot ###
normalize_certbot_renewal_config() {
    local domain="$1"
    local renewal_file="/etc/letsencrypt/renewal/${domain}.conf"
    local webroot="/var/www/letsencrypt"
    local backup_dir
    local backup_file
    local tmp_file
    if [[ ! -f "$renewal_file" ]]; then
        msg_inf "Certbot renewal config:" "missing for $domain; skipping normalization"
        return 0
    fi
    if certbot_renewal_config_is_normalized "$domain" "$renewal_file"; then
        return 0
    fi
    backup_dir="/root/3x-ui-installer-renewal-backups/$(date +%Y%m%d-%H%M%S)"
    backup_file="${backup_dir}/${domain}.conf"
    mkdir -p "$backup_dir"
    cp -a "$renewal_file" "$backup_file"
    tmp_file="$(mktemp)"
    awk -v domain="$domain" -v webroot="$webroot" '
        BEGIN {
            in_renewalparams = 0
            in_webroot_map = 0
            seen_renewalparams = 0
            printed_authenticator = 0
            printed_webroot_path = 0
            printed_webroot_map = 0
        }
        function print_missing_renewalparams() {
            if (!seen_renewalparams) {
                print ""
                print "[renewalparams]"
                seen_renewalparams = 1
                in_renewalparams = 1
            }
            if (!printed_authenticator) {
                print "authenticator = webroot"
                printed_authenticator = 1
            }
            if (!printed_webroot_path) {
                print "webroot_path = " webroot
                printed_webroot_path = 1
            }
        }
        function print_webroot_map() {
            print_missing_renewalparams()
            if (!printed_webroot_map) {
                print ""
                print "[[webroot_map]]"
                print domain " = " webroot
                printed_webroot_map = 1
            }
        }
        /^[[:space:]]*\[\[webroot_map\]\][[:space:]]*$/ {
            print_webroot_map()
            in_webroot_map = 1
            next
        }
        in_webroot_map {
            if ($0 ~ /^[[:space:]]*\[/) {
                in_webroot_map = 0
            } else {
                next
            }
        }
        /^[[:space:]]*\[renewalparams\][[:space:]]*$/ {
            print
            in_renewalparams = 1
            seen_renewalparams = 1
            next
        }
        in_renewalparams && /^[[:space:]]*\[/ {
            print_missing_renewalparams()
            in_renewalparams = 0
        }
        in_renewalparams && /^[[:space:]]*authenticator[[:space:]]*=/ {
            print "authenticator = webroot"
            printed_authenticator = 1
            next
        }
        in_renewalparams && /^[[:space:]]*webroot_path[[:space:]]*=/ {
            print "webroot_path = " webroot
            printed_webroot_path = 1
            next
        }
        {
            print
        }
        END {
            if (in_renewalparams) {
                print_missing_renewalparams()
            }
            if (!printed_webroot_map) {
                print_webroot_map()
            }
        }
    ' "$renewal_file" > "$tmp_file"
    chown --reference="$renewal_file" "$tmp_file" 2>/dev/null || true
    chmod --reference="$renewal_file" "$tmp_file" 2>/dev/null || true
    mv "$tmp_file" "$renewal_file"
    msg_inf "Certbot renewal config:" "normalized for $domain"
    msg_inf "Renewal backup:" "$backup_file"
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
