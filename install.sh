#!/usr/bin/env bash

set -E
set -e

### Validate self-loader install directory ###
validate_bootstrap_install_dir() {
    local dir="$1"
    local canonical_dir
    if [[ -z "${dir}" || "${dir}" != /* ]]; then
        echo "ERROR: unsafe installer directory: ${dir:-<empty>}" >&2
        echo "Installer directory must be an absolute path." >&2
        exit 1
    fi
    if ! command -v realpath >/dev/null 2>&1; then
        echo "ERROR: realpath is required" >&2
        exit 1
    fi
    canonical_dir="$(realpath -m -- "${dir}")"
    case "${canonical_dir}" in
        /root/3x-ui-installer|/root/3x-ui-installer-*)
            ;;
        *)
            echo "ERROR: unsafe installer directory: ${canonical_dir}" >&2
            echo "Allowed paths: /root/3x-ui-installer or /root/3x-ui-installer-*" >&2
            exit 1
            ;;
    esac
    if [[ -e "${canonical_dir}" ]]; then
        if [[ ! -d "${canonical_dir}" ]]; then
            echo "ERROR: installer path exists but is not a directory: ${canonical_dir}" >&2
            exit 1
        fi
        if [[ ! -f "${canonical_dir}/.xui-installer-owned" ]]; then
            if [[ ! -f "${canonical_dir}/install.sh" \
                || ! -d "${canonical_dir}/lib" \
                || ! -d "${canonical_dir}/templates" ]]; then
                echo "ERROR: refusing to replace unowned directory: ${canonical_dir}" >&2
                echo "Remove it manually if you are sure it is safe." >&2
                exit 1
            fi
        fi
    fi
    BOOTSTRAP_INSTALL_DIR="${canonical_dir}"
}

### GitHub self-loader ###
bootstrap_from_github() {
    local repo
    local ref
    local install_dir
    local script_dir
    local tmp_dir
    local archive
    local extracted_dir
    local tarball_url
    repo="${XUI_INSTALLER_REPO:-AndrewZAP1977/3x-ui-installer}"
    ref="${XUI_INSTALLER_REF:-main}"
    install_dir="${XUI_INSTALLER_DIR:-/root/3x-ui-installer}"
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ "${XUI_INSTALLER_BOOTSTRAPPED:-}" == "1" ]]; then
        return 0
    fi
    if [[ -f "${script_dir}/install.sh" \
        && -d "${script_dir}/lib" \
        && -d "${script_dir}/templates" ]]; then
        return 0
    fi
    if [[ "${EUID}" -ne 0 ]]; then
        echo "ERROR: Please run as root." >&2
        echo >&2
        echo "If your VPS uses a sudo user, run:" >&2
        echo >&2
        echo "  sudo -i" >&2
        echo >&2
        echo "Then run the installer command again." >&2
        exit 1
    fi
    validate_bootstrap_install_dir "${install_dir}"
    install_dir="${BOOTSTRAP_INSTALL_DIR}"
    tmp_dir="$(mktemp -d /tmp/3x-ui-installer.XXXXXX)"
    archive="${tmp_dir}/repo.tar.gz"
    extracted_dir="${tmp_dir}/repo"
    tarball_url="https://codeload.github.com/${repo}/tar.gz/${ref}"
    mkdir -p "${extracted_dir}"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "${tarball_url}" -o "${archive}"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "${archive}" "${tarball_url}"
    else
        echo "ERROR: curl or wget is required"
        rm -rf "${tmp_dir}"
        exit 1
    fi
    tar -xzf "${archive}" -C "${extracted_dir}" --strip-components=1
    rm -f "${archive}"
    if [[ ! -f "${extracted_dir}/install.sh" \
        || ! -d "${extracted_dir}/lib" \
        || ! -d "${extracted_dir}/templates" ]]; then
        echo "ERROR: downloaded repository is incomplete"
        rm -rf "${tmp_dir}"
        exit 1
    fi
    rm -rf "${install_dir}"
    mkdir -p "$(dirname "${install_dir}")"
    mv "${extracted_dir}" "${install_dir}"
    touch "${install_dir}/.xui-installer-owned"
    rm -rf "${tmp_dir}"
    export XUI_INSTALLER_BOOTSTRAPPED=1
    exec bash "${install_dir}/install.sh" "$@"
}

bootstrap_from_github "$@"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/api.sh"
source "${SCRIPT_DIR}/lib/domain.sh"
source "${SCRIPT_DIR}/lib/fakesites.sh"
source "${SCRIPT_DIR}/lib/nginx.sh"
source "${SCRIPT_DIR}/lib/runtime.sh"
source "${SCRIPT_DIR}/lib/system.sh"
source "${SCRIPT_DIR}/lib/uninstall.sh"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/xui.sh"
trap 'on_error "${LINENO}" "${BASH_COMMAND}" "$?"' ERR
show_help_if_requested "$@"
require_root
parse_arguments "$@"
handle_uninstall_mode
clear_all
show_install_profile
msg_inf "Installation started"
msg_blank
detect_package_manager
preflight_fixed_ports
install_packages
detect_public_ips
resolve_domains
validate_domains
configure_firewall
generate_runtime_variables
generate_runtime_uris
build_runtime_context
prepare_nginx
render_bootstrap_nginx
enable_bootstrap_configs
validate_nginx
reload_nginx
request_ssl_certificates
cleanup_previous_database
install_xui
generate_runtime_secrets
wait_xui_ready
update_xui_geofiles
configure_xui_credentials
# Panel settings, inbounds, and clients are provisioned through the 3x-ui API.
api_set_endpoint "http" "2053" ""
wait_api_ready
api_login
api_update_xui_settings
restart_xui
wait_xui_ready
api_set_endpoint "https" "$PANEL_PORT" "$PANEL_PATH"
wait_api_ready
api_login
api_update_xray_routing
api_create_reality_inbound
api_create_xhttp_inbound
restart_xui
wait_xui_ready
render_nginx_templates
enable_tls_configs
validate_nginx
prepare_fake_sites
reload_nginx
run_smoke_checks
maybe_setup_xui_fail2ban || msg_inf "Optional Fail2ban/IP Limit setup did not complete"
msg_ok "Installation completed successfully !!!"
echo
wait_before_summary
show_summary
