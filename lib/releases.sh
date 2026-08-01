# shellcheck shell=bash

### Fetch available 3x-ui releases ###
fetch_xui_release_versions() {
    local releases_json
    releases_json=$(curl -fsSL \
        --connect-timeout 5 \
        --max-time 15 \
        "https://api.github.com/repos/MHSanaei/3x-ui/releases?per_page=100" \
        2>/dev/null || true)
    if [[ -z "${releases_json}" ]]; then
        return 1
    fi
    printf '%s' "${releases_json}" | jq -r '
        [
            .[]
            | select(.draft != true and .prerelease != true)
            | .tag_name
            | select(test("^v?[0-9]+\\.[0-9]+\\.[0-9]+$"))
            | capture("^v?(?<major>[0-9]+)\\.(?<minor>[0-9]+)\\.(?<patch>[0-9]+)$") as $v
            | select(($v.major | tonumber) >= 3)
            | {
                tag: ("v" + $v.major + "." + $v.minor + "." + $v.patch),
                major: ($v.major | tonumber),
                minor: ($v.minor | tonumber),
                patch: ($v.patch | tonumber)
            }
        ]
        | unique_by(.tag)
        | sort_by(.major, .minor, .patch)
        | reverse
        | .[].tag
    ' 2>/dev/null
}

### Select x-ui version interactively ###
select_xui_version_interactive() {
    local versions=()
    local latest_version=""
    local choice=""
    local manual_version=""
    local normalized_version=""
    local index
    local list_index
    if [[ -n "${XUI_VERSION:-}" ]]; then
        return 0
    fi
    if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
        return 0
    fi
    mapfile -t versions < <(fetch_xui_release_versions || true)
    if (( ${#versions[@]} == 0 )); then
        msg_blank
        msg_warn "Failed to fetch 3x-ui release list; using latest."
        msg_inf "You can pin a version with: --xui-version v3.6.0"
        msg_blank
        return 0
    fi
    latest_version="${versions[0]}"
    msg_blank
    printf "\e[1;33mSelect 3x-ui version to install:\e[0m\n" >/dev/tty
    printf "  1) latest (%s)\n" "${latest_version}" >/dev/tty
    index=2
    for list_index in "${!versions[@]}"; do
        printf "  %d) %s\n" "${index}" "${versions[${list_index}]}" >/dev/tty
        ((index++))
    done
    printf "  m) manual version\n" >/dev/tty
    while true; do
        printf "\e[1;33mChoice [1]: \e[0m" >/dev/tty
        read -r choice </dev/tty || choice=""
        choice="${choice:-1}"
        case "${choice}" in
            1)
                XUI_VERSION="latest"
                export XUI_VERSION
                msg_blank
                msg_inf "Selected 3x-ui version:" "latest (${latest_version})"
                msg_blank
                return 0
                ;;
            m|M|manual|MANUAL)
                while true; do
                    printf "\e[1;33mEnter 3x-ui version, for example v3.6.0: \e[0m" >/dev/tty
                    read -r manual_version </dev/tty || manual_version=""
                    normalized_version="$(normalize_xui_version "${manual_version}" 2>/dev/null || true)"
                    if [[ -n "${normalized_version}" ]]; then
                        XUI_VERSION="${normalized_version}"
                        export XUI_VERSION
                        msg_blank
                        msg_inf "Selected 3x-ui version:" "${XUI_VERSION}"
                        msg_blank
                        return 0
                    fi
                    msg_warn "Invalid 3x-ui version:" "${manual_version:-<empty>}"
                done
                ;;
            *[!0-9]*)
                msg_warn "Invalid menu choice:" "${choice}"
                ;;
            *)
                if (( choice >= 2 && choice < index )); then
                    list_index=$((choice - 2))
                    XUI_VERSION="${versions[${list_index}]}"
                    export XUI_VERSION
                    msg_blank
                    msg_inf "Selected 3x-ui version:" "${XUI_VERSION}"
                    msg_blank
                    return 0
                fi
                msg_warn "Invalid menu choice:" "${choice}"
                ;;
        esac
    done
}
