# shellcheck shell=bash

### Fake sites repository ###
readonly FAKESITES_REPO_DIR="/opt/randomfakehtml"
readonly FAKESITE1_DIR="/var/www/html/fakesite_1"
readonly FAKESITE2_DIR="/var/www/html/fakesite_2"
readonly FAKESITE3_DIR="/var/www/html/fakesite_3"

### Install fake sites repository ###
install_fakesites_repository() {
    msg_inf "Fake sites repository installation..."
    rm -f /tmp/randomfakehtml.zip
    rm -rf /tmp/randomfakehtml-master
    wget -qO /tmp/randomfakehtml.zip \
        https://github.com/GFW4Fun/randomfakehtml/archive/refs/heads/master.zip \
        || return 1
    unzip -oq /tmp/randomfakehtml.zip -d /tmp \
        || return 1
    rm -rf "$FAKESITES_REPO_DIR"
    mv \
        /tmp/randomfakehtml-master \
        "$FAKESITES_REPO_DIR" \
        || return 1
    rm -f /tmp/randomfakehtml.zip
    rm -rf /tmp/randomfakehtml-master
}

### Check fake site candidate ###
is_valid_fakesite_candidate() {
    local site="$1"
    [[ -d "$site" ]] || return 1
    [[ -s "${site}/index.html" ]] || return 1
    if grep -RqiE '(^|[^[:alnum:]_-])(\.\./)*/?assets/' "$site" \
        --include='*.html' \
        --include='*.htm' \
        --include='*.css' \
        --include='*.js' \
        2>/dev/null; then
        return 1
    fi
    return 0
}

### Add root base href to all fake site HTML files ###
inject_base_href() {
    local site="$1"
    local html_file
    local found=false
    [[ -d "$site" ]] || return 1
    while IFS= read -r -d '' html_file; do
        found=true
        python3 - "$html_file" <<'PY'
from pathlib import Path
import re
import sys
path = Path(sys.argv[1])
html = path.read_text(encoding="utf-8", errors="ignore")
if re.search(r'<base\s+[^>]*href=', html, re.I):
    sys.exit(0)
html, count = re.subn(
    r'(<head\b[^>]*>)',
    r'\1\n    <base href="/">',
    html,
    count=1,
    flags=re.I,
)
if count == 0:
    html = '<base href="/">\n' + html
path.write_text(html, encoding="utf-8")
PY
    done < <(
        find "$site" \
            -type f \
            \( -iname '*.html' -o -iname '*.htm' \) \
            -print0
    )
    [[ "$found" == true ]] || return 1
}

### Get random fake site ###
get_random_fakesite() {
    local site
    local candidates=()
    while IFS= read -r site; do
        if is_valid_fakesite_candidate "$site"; then
            candidates+=("$site")
        fi
    done < <(
        find "$FAKESITES_REPO_DIR" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            ! -name assets \
            ! -name sample_site
    )
    if [[ "${#candidates[@]}" -eq 0 ]]; then
        msg_err "No valid fake site candidates found"
        return 1
    fi
    printf '%s\n' "${candidates[@]}" | shuf -n1
}

### Deploy fake site to target ###
deploy_fakesite_to_target() {
    local template="$1"
    local target="$2"
    rm -rf "${target}"
    mkdir -p "${target}"
    cp -a "${template}/." "${target}/"
    inject_base_href "$target" \
        || return 1
}

### Deploy fake sites ###
deploy_fakesites() {
    local site1
    local site2
    local site3
    site1=$(get_random_fakesite)
    [[ -z "$site1" ]] && return 1
    while true; do
        site2=$(get_random_fakesite)
        [[ -z "$site2" ]] && return 1
        [[ "$site1" != "$site2" ]] && break
    done
    if [[ "$INSTALL_PROFILE" == "separate-xhttp-sni" ]]; then
        while true; do
            site3=$(get_random_fakesite)
            [[ -z "$site3" ]] && return 1
            [[ "$site3" != "$site1" && "$site3" != "$site2" ]] && break
        done
    fi
    deploy_fakesite_to_target \
        "$site1" \
        "$FAKESITE1_DIR" \
        || return 1
    deploy_fakesite_to_target \
        "$site2" \
        "$FAKESITE2_DIR" \
        || return 1
    if [[ "$INSTALL_PROFILE" == "separate-xhttp-sni" ]]; then
        deploy_fakesite_to_target \
            "$site3" \
            "$FAKESITE3_DIR" \
            || return 1
    fi
}

### Verify deployed fake site ###
verify_deployed_fakesite() {
    local site="$1"
    local html_file
    local found=false
    [[ -s "${site}/index.html" ]] || return 1
    while IFS= read -r -d '' html_file; do
        found=true
        grep -qiE '<base[[:space:]][^>]*href=["'\'']/["'\'']' "$html_file" \
            || return 1
    done < <(
        find "$site" \
            -type f \
            \( -iname '*.html' -o -iname '*.htm' \) \
            -print0
    )
    [[ "$found" == true ]] || return 1
}

### Verify fake sites ###
verify_fakesites() {
    verify_deployed_fakesite "$FAKESITE1_DIR" \
        || {
            msg_err "Fake site verification failed: $FAKESITE1_DIR"
            return 1
        }
    verify_deployed_fakesite "$FAKESITE2_DIR" \
        || {
            msg_err "Fake site verification failed: $FAKESITE2_DIR"
            return 1
        }
    if [[ "$INSTALL_PROFILE" == "separate-xhttp-sni" ]]; then
        verify_deployed_fakesite "$FAKESITE3_DIR" \
            || {
                msg_err "Fake site verification failed: $FAKESITE3_DIR"
                return 1
            }
    fi
    msg_ok "Fake sites deployed"
    msg_blank
}

### Prepare fake sites ###
prepare_fake_sites() {
    install_fakesites_repository \
        || return 1
    deploy_fakesites \
        || return 1
    verify_fakesites \
        || return 1
}
