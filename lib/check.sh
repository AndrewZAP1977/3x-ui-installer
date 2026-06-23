#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_DIR"
FAILED=0
msg_ok() {
    echo "[OK] $*"
}
msg_warn() {
    echo "[WARN] $*"
}
msg_err() {
    echo "[ERROR] $*"
}
mark_failed() {
    FAILED=1
}
check_file_exists() {
    local file="$1"
    if [[ -f "$file" ]]; then
        msg_ok "Required file exists: $file"
    else
        msg_err "Required file is missing: $file"
        mark_failed
    fi
}

check_dir_exists() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        msg_ok "Required directory exists: $dir"
    else
        msg_err "Required directory is missing: $dir"
        mark_failed
    fi
}

check_path_absent() {
    local path="$1"
    if [[ ! -e "$path" ]]; then
        msg_ok "Removed legacy path is absent: $path"
    else
        msg_err "Legacy path still exists: $path"
        mark_failed
    fi
}

check_pattern_present() {
    local file="$1"
    local pattern="$2"
    local description="$3"
    if grep -Eq "$pattern" "$file"; then
        msg_ok "$description"
    else
        msg_err "$description"
        msg_err "Pattern not found in $file: $pattern"
        mark_failed
    fi
}

check_pattern_absent() {
    local path="$1"
    local pattern="$2"
    local description="$3"
    if grep -RniE "$pattern" "$path" >/tmp/xui_check_grep.log 2>/dev/null; then
        msg_err "$description"
        cat /tmp/xui_check_grep.log
        rm -f /tmp/xui_check_grep.log
        mark_failed
    else
        msg_ok "$description"
        rm -f /tmp/xui_check_grep.log
    fi
}

run_bash_syntax_check() {
    local file
    msg_ok "Running bash syntax checks"
    bash -n install.sh || {
        msg_err "Bash syntax failed: install.sh"
        mark_failed
    }
    for file in lib/*.sh; do
        [[ -f "$file" ]] || continue
        bash -n "$file" || {
            msg_err "Bash syntax failed: $file"
            mark_failed
        }
    done
}

run_shellcheck_if_available() {
    local files=()
    files+=("install.sh")
    files+=(lib/*.sh)
    if ! command -v shellcheck >/dev/null 2>&1; then
        msg_warn "ShellCheck is not installed; skipped"
        return 0
    fi
    msg_ok "Running ShellCheck"
    if shellcheck "${files[@]}"; then
        msg_ok "ShellCheck passed"
    else
        msg_warn "ShellCheck found issues"
        msg_warn "ShellCheck is currently non-fatal in this project checker"
    fi
}

echo
echo "===== x-ui-pro_api_lab project check ====="
echo
check_file_exists "install.sh"
check_file_exists "README.md"
check_dir_exists "lib"
check_dir_exists "templates"
check_file_exists "lib/api.sh"
check_file_exists "lib/domain.sh"
check_file_exists "lib/fakesites.sh"
check_file_exists "lib/nginx.sh"
check_file_exists "lib/runtime.sh"
check_file_exists "lib/system.sh"
check_file_exists "lib/utils.sh"
check_file_exists "lib/xui.sh"
check_file_exists "lib/check.sh"
check_file_exists "templates/80.conf.template"
check_file_exists "templates/nginx.conf.template"
check_file_exists "templates/panel.conf.template"
check_file_exists "templates/panel_includes.conf.template"
check_file_exists "templates/fake_https_site.conf.template"
check_file_exists "templates/reality_includes.conf.template"
check_file_exists "templates/fake_site_includes.conf.template"
check_file_exists "templates/stream.conf.template"
check_path_absent "lib/args.sh"
check_path_absent "lib/database.sh"
check_path_absent "lib/network.sh"
check_path_absent "lib/packages.sh"
check_path_absent "lib/payloads.sh"
check_path_absent "lib/secrets.sh"
check_path_absent "lib/ssl.sh"
check_path_absent "lib/summary.sh"
check_path_absent "lib/template.sh"
check_path_absent "lib/xray.sh"
check_path_absent "lib/inbounds"
check_path_absent "templates/nginx"
check_path_absent "templates/xrayTemplateConfig.json"
echo
echo "===== Static source checks ====="
echo
check_pattern_present "install.sh" 'show_help_if_requested' "install.sh calls show_help_if_requested"
check_pattern_present "install.sh" 'require_root' "install.sh calls require_root"
check_pattern_present "install.sh" 'detect_public_ips' "install.sh calls detect_public_ips"
check_pattern_present "install.sh" 'run_smoke_checks' "install.sh calls run_smoke_checks"
check_pattern_present "lib/domain.sh" 'XUI_VERSION' "domain.sh contains XUI_VERSION default/argument handling"
check_pattern_present "lib/domain.sh" 'xui-version' "domain.sh contains --xui-version argument"
check_pattern_present "lib/domain.sh" 'show_help_if_requested' "domain.sh contains show_help_if_requested"
check_pattern_present "lib/domain.sh" 'is_global' "domain.sh validates public/global IPv4"
check_pattern_present "lib/domain.sh" 'printf -v "\$output_var"' "domain.sh request_domain assigns result through output variable"
check_pattern_present "lib/domain.sh" 'request_domain[[:space:]]*\\' "domain.sh uses request_domain helper"
check_pattern_present "lib/domain.sh" '^[[:space:]]*DOMAIN[[:space:]]*\\' "domain.sh passes DOMAIN as request_domain output variable"
check_pattern_present "lib/domain.sh" '^[[:space:]]*REALITY_DOMAIN[[:space:]]*\\' "domain.sh passes REALITY_DOMAIN as request_domain output variable"
check_pattern_absent "lib/domain.sh" 'DOMAIN=\$\(request_domain|REALITY_DOMAIN=\$\(request_domain' "domain.sh does not capture request_domain stdout"
check_pattern_present "lib/domain.sh" 'show_auto_domain_warning' "domain.sh shows auto-domain third-party warning"
check_pattern_present "lib/domain.sh" 'third-party cdn-one.org DNS' "domain.sh warns about third-party auto-domain DNS"
check_pattern_present "README.md" 'third-party `cdn-one.org`' "README documents auto-domain third-party DNS dependency"
check_pattern_present "README.md" 'mozaroc-style auto-domain examples' "README mentions mozaroc-style auto-domain context without ownership claim"
check_pattern_present "README.md" 'For long-lived or production installations, use your own domains' "README recommends own domains for production"
check_pattern_present "lib/xui.sh" 'normalize_xui_version' "xui.sh contains normalize_xui_version"
check_pattern_present "lib/xui.sh" 'v3\.0\.0' "xui.sh documents/enforces v3.0.0 minimum"
check_pattern_present "lib/runtime.sh" 'run_smoke_checks' "runtime.sh contains run_smoke_checks"
check_pattern_present "lib/runtime.sh" 'Failed to parse Reality X25519 keys' "runtime.sh validates parsed Reality keys"
check_pattern_present "lib/runtime.sh" 'smoke_check_subscription_url' "runtime.sh contains subscription body smoke-check"
check_pattern_present "lib/system.sh" 'ca-certificates' "system.sh installs ca-certificates"
check_pattern_present "lib/system.sh" 'openssl' "system.sh installs openssl"
check_pattern_present "lib/fakesites.sh" 'randomfakehtml-master' "fakesites.sh handles randomfakehtml temp directory"
check_pattern_present "templates/stream.conf.template" 'proxy_timeout' "stream template contains proxy_timeout"
check_pattern_present "templates/stream.conf.template" 'proxy_connect_timeout' "stream template contains proxy_connect_timeout"
check_pattern_present "templates/stream.conf.template" 'tcp_nodelay' "stream template contains tcp_nodelay"
check_pattern_present "lib/api.sh" 'trustedXForwardedFor' "api.sh configures XHTTP trustedXForwardedFor"
check_pattern_present "lib/api.sh" '"fingerprint": "firefox"' "api.sh uses explicit Firefox Reality fingerprint"
check_pattern_absent "lib/api.sh" '"fingerprint": "random"' "api.sh does not use random Reality fingerprint"
check_pattern_present "lib/runtime.sh" 'separate-xhttp-sni' "runtime.sh handles profile-specific XHTTP path"
check_pattern_present "lib/runtime.sh" ',/api/ver1/date,/logos/logo_img/png' "runtime.sh uses human-looking XHTTP path for separate-xhttp-sni"
check_pattern_present "lib/nginx.sh" 'fake_site_includes\.conf\.template' "nginx.sh renders fake-site-only includes for profile-specific snippets"
check_pattern_present "lib/nginx.sh" 'xhttp_includes\.conf' "nginx.sh renders xhttp include snippet for separate-xhttp-sni"
check_pattern_present "templates/reality_includes.conf.template" 'grpc_pass grpc://unix' "standard reality include contains XHTTP unix socket proxy"
check_pattern_absent "templates/fake_site_includes.conf.template" 'grpc_pass grpc://unix|### XHTTP ###' "fake-site-only include does not contain XHTTP unix socket proxy"
check_pattern_present "lib/nginx.sh" 'nginx_supports_http2_on_directive' "nginx.sh detects nginx HTTP/2 directive syntax support"
check_pattern_present "lib/nginx.sh" 'PANEL_LISTEN_DIRECTIVE' "nginx.sh renders panel HTTP/2 listen placeholder"
check_pattern_present "templates/panel.conf.template" '{{PANEL_LISTEN_DIRECTIVE}}' "panel template uses HTTP/2 listen placeholder"
check_pattern_present "templates/panel.conf.template" '{{HTTP2_DIRECTIVE}}' "panel template uses standalone HTTP/2 directive placeholder"
check_pattern_present "lib/nginx.sh" 'render_fake_https_site_template' "nginx.sh renders shared fake HTTPS site template"
check_pattern_present "lib/nginx.sh" 'fake_https_site\.conf\.template' "nginx.sh uses shared fake HTTPS site template"
check_pattern_present "lib/nginx.sh" 'reality_includes\.conf' "nginx.sh renders reality include through shared fake HTTPS template"
check_pattern_present "lib/nginx.sh" 'xhttp_includes\.conf' "nginx.sh renders xhttp include through shared fake HTTPS template"
check_pattern_present "templates/fake_https_site.conf.template" '{{FAKE_SITE_DOMAIN}}' "fake HTTPS template uses domain placeholder"
check_pattern_present "templates/fake_https_site.conf.template" '{{FAKE_SITE_LISTEN_DIRECTIVE}}' "fake HTTPS template uses listen placeholder"
check_pattern_present "templates/fake_https_site.conf.template" '{{FAKE_SITE_ROOT}}' "fake HTTPS template uses root placeholder"
check_pattern_present "templates/fake_https_site.conf.template" '{{FAKE_SITE_INCLUDE}}' "fake HTTPS template uses include placeholder"
check_pattern_present "templates/fake_https_site.conf.template" '{{HTTP2_DIRECTIVE}}' "fake HTTPS template uses HTTP/2 directive placeholder"
check_pattern_present "lib/nginx.sh" 'normalize_certbot_renewal_config' "nginx.sh normalizes existing Certbot renewal configs"
check_pattern_present "lib/nginx.sh" 'certbot_renewal_config_is_normalized' "nginx.sh detects normalized Certbot renewal configs"
check_pattern_present "lib/nginx.sh" '3x-ui-installer-renewal-backups' "nginx.sh backs up renewal configs before rewriting"
check_pattern_present "lib/nginx.sh" 'webroot_path = ' "nginx.sh rewrites renewal webroot_path"
check_pattern_present "lib/nginx.sh" 'printed_webroot_path' "nginx.sh adds missing renewal webroot_path"
check_pattern_present "lib/nginx.sh" '\[renewalparams\]' "nginx.sh preserves or creates renewalparams section"
check_pattern_present "lib/nginx.sh" '\[\[webroot_map\]\]' "nginx.sh rewrites renewal webroot_map"
check_pattern_absent "install.sh" 'lib/(args|database|network|packages|payloads|secrets|ssl|summary|template|xray)\.sh|lib/inbounds/' "install.sh does not source removed legacy files"
check_pattern_absent "install.sh" '^[[:space:]]*clear[[:space:]]*$' "No raw clear commands remain in install.sh"
check_pattern_absent "install.sh" 'python3-certbot-nginx' "python3-certbot-nginx package is not used in install.sh"
check_pattern_absent "lib" '^[[:space:]]*clear[[:space:]]*$' "No raw clear commands remain in lib"
check_pattern_absent "lib/system.sh" 'python3-certbot-nginx' "python3-certbot-nginx package is not used in system.sh"
echo
echo "===== Bash checks ====="
echo
run_bash_syntax_check
echo
echo "===== Optional ShellCheck ====="
echo
run_shellcheck_if_available
echo
if [[ "$FAILED" -eq 0 ]]; then
    echo "===== PROJECT CHECK PASSED ====="
    exit 0
fi
echo "===== PROJECT CHECK FAILED ====="
exit 1
