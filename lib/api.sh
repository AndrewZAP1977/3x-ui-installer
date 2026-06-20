# shellcheck shell=bash

### API curl timeouts ###
readonly API_CONNECT_TIMEOUT=5
readonly API_MAX_TIME=30

### API cookie file ###
API_COOKIE_FILE="$(umask 077 && mktemp /tmp/xui-api-cookie.XXXXXX)"

### Cleanup API cookie file ###
cleanup_api_cookie_file() {
    rm -f "${API_COOKIE_FILE:-}"
}
trap cleanup_api_cookie_file EXIT

### API csrf token ###
API_CSRF_TOKEN=""

### API endpoint ###
API_SCHEME="https"
API_HOST="127.0.0.1"
API_PORT=""
API_PATH=""

### Set API endpoint ###
api_set_endpoint() {
    API_SCHEME="$1"
    API_PORT="$2"
    API_PATH="$3"
    API_PATH="${API_PATH#/}"
    API_PATH="${API_PATH%/}"
}

### Build API URL ###
api_url() {
    local path="$1"
    if [[ -n "${API_PATH}" ]]; then
        echo "${API_SCHEME}://${API_HOST}:${API_PORT}/${API_PATH}${path}"
    else
        echo "${API_SCHEME}://${API_HOST}:${API_PORT}${path}"
    fi
}

### Run API curl request ###
api_curl_or_fail() {
    local title="$1"
    local message="$2"
    local response
    local status=0
    shift 2
    response=$(curl -skS \
        --connect-timeout "${API_CONNECT_TIMEOUT}" \
        --max-time "${API_MAX_TIME}" \
        "$@" \
        2>&1) || status=$?
    if (( status != 0 )); then
        {
            echo
            echo "===== ${title} CURL FAILED ====="
            echo "curl exit code: ${status}"
            echo
            echo "CURL OUTPUT:"
            echo "${response}"
            echo
            msg_err "${message}"
        } >&2
        return 1
    fi
    printf '%s' "${response}"
}

### Wait API ready ###
wait_api_ready() {
    local retries=30
    local response
    local url
    url="$(api_url "/csrf-token")"
    while (( retries > 0 )); do
        response=$(curl -sk \
            --connect-timeout 2 \
            --max-time 5 \
            "${url}" \
            2>/dev/null || true)
        if echo "${response}" \
            | jq -e '(.success == true) and (.obj != null)' \
            >/dev/null 2>&1
        then
            return 0
        fi
        sleep 1
        ((retries--))
    done
    echo
    echo "===== API READY CHECK FAILED ====="
    echo "URL: ${url}"
    echo
    echo "LAST RESPONSE:"
    echo "${response}"
    echo
    msg_err "API is not ready"
    return 1
}

### Login to x-ui ###
api_login() {
    local retries=30
    local csrf_response
    local csrf_token
    local login_response
    local csrf_url
    local login_url
    csrf_url="$(api_url "/csrf-token")"
    login_url="$(api_url "/login")"
    API_CSRF_TOKEN=""
    while (( retries > 0 )); do
        rm -f "${API_COOKIE_FILE}"
        csrf_response=$(curl -sk \
            --connect-timeout 2 \
            --max-time 5 \
            -c "${API_COOKIE_FILE}" \
            "${csrf_url}" \
            2>/dev/null || true)
        csrf_token=$(echo "${csrf_response}" \
            | jq -r '.obj' 2>/dev/null || true)
        if [[ -n "${csrf_token}" && "${csrf_token}" != "null" ]]; then
            API_CSRF_TOKEN="${csrf_token}"
            login_response=$(curl -sk \
                --connect-timeout 2 \
                --max-time 5 \
                -b "${API_COOKIE_FILE}" \
                -c "${API_COOKIE_FILE}" \
                -H "Content-Type: application/json" \
                -H "X-CSRF-Token: ${API_CSRF_TOKEN}" \
                -X POST \
                -d "{
                    \"username\":\"${PANEL_USERNAME}\",
                    \"password\":\"${PANEL_PASSWORD}\"
                }" \
                "${login_url}" \
                2>/dev/null || true)
            if echo "${login_response}" | jq -e '.success == true' >/dev/null 2>&1; then
                return 0
            fi
        fi
        sleep 1
        ((retries--))
    done
    echo
    echo "===== API LOGIN FAILED ====="
    echo "CSRF URL:  ${csrf_url}"
    echo "LOGIN URL: ${login_url}"
    echo
    echo "LAST CSRF RESPONSE:"
    echo "${csrf_response}"
    echo
    echo "LAST LOGIN RESPONSE:"
    echo "${login_response}"
    echo
    msg_err "x-ui API login failed"
    return 1
}

### Create REALITY inbound via API ###
api_create_reality_inbound() {
    local response
    response=$(api_curl_or_fail \
        "REALITY CREATE" \
        "Failed to call REALITY inbound API" \
        -b "${API_COOKIE_FILE}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -H "X-CSRF-Token: ${API_CSRF_TOKEN}" \
        -X POST \
        -d "{
            \"enable\": true,
            \"remark\": \"TCP-REALITY\",
            \"listen\": \"127.0.0.1\",
            \"port\": 8443,
            \"protocol\": \"vless\",
            \"expiryTime\": 0,
            \"total\": 0,
            \"settings\": {
                \"clients\": [
                    {
                        \"auth\": \"${CLIENT_AUTH}\",
                        \"comment\": \"\",
                        \"created_at\": ${CURRENT_MS},
                        \"email\": \"${CLIENT_EMAIL}\",
                        \"enable\": true,
                        \"expiryTime\": 0,
                        \"flow\": \"xtls-rprx-vision\",
                        \"id\": \"${XRAY_UUID}\",
                        \"limitIp\": 0,
                        \"password\": \"${CLIENT_PASSWORD}\",
                        \"reset\": 0,
                        \"security\": \"auto\",
                        \"subId\": \"${CLIENT_SUB_ID}\",
                        \"tgId\": 0,
                        \"totalGB\": 0,
                        \"updated_at\": ${CURRENT_MS}
                    }
                ],
                \"decryption\": \"none\",
                \"encryption\": \"none\",
                \"fallbacks\": []
            },
            \"streamSettings\": {
                \"network\": \"tcp\",
                \"security\": \"reality\",
                \"externalProxy\": [
                    {
                        \"forceTls\": \"same\",
                        \"dest\": \"${DOMAIN}\",
                        \"port\": 443,
                        \"remark\": \"\",
                        \"sni\": \"\",
                        \"alpn\": [],
                        \"pinnedPeerCertSha256\": []
                    }
                ],
                \"realitySettings\": {
                    \"show\": false,
                    \"xver\": 0,
                    \"target\": \"127.0.0.1:9443\",
                    \"serverNames\": [
                        \"${REALITY_DOMAIN}\"
                    ],
                    \"privateKey\": \"${PRIVATE_KEY}\",
                    \"minClientVer\": \"\",
                    \"maxClientVer\": \"\",
                    \"maxTimediff\": 0,
                    \"mldsa65Seed\": \"\",
                    \"shortIds\": [
                        \"${SHORT_IDS[0]}\",
                        \"${SHORT_IDS[1]}\",
                        \"${SHORT_IDS[2]}\",
                        \"${SHORT_IDS[3]}\",
                        \"${SHORT_IDS[4]}\",
                        \"${SHORT_IDS[5]}\",
                        \"${SHORT_IDS[6]}\",
                        \"${SHORT_IDS[7]}\"
                    ],
                    \"settings\": {
                        \"publicKey\": \"${PUBLIC_KEY}\",
                        \"fingerprint\": \"random\",
                        \"serverName\": \"\",
                        \"spiderX\": \"/\",
                        \"mldsa65Verify\": \"\"
                    }
                },
                \"tcpSettings\": {
                    \"acceptProxyProtocol\": true,
                    \"header\": {
                        \"type\": \"none\"
                    }
                }
            },
            \"sniffing\": {
                \"enabled\": true,
                \"destOverride\": [
                    \"http\",
                    \"tls\"
                ]
            }
        }" \
        "$(api_url "/panel/api/inbounds/add")") || return 1
    if ! echo "${response}" | jq -e '.success == true' >/dev/null 2>&1; then
        echo
        echo "===== REALITY CREATE FAILED ====="
        echo "${response}"
        echo
        msg_err "Failed to create REALITY inbound"
        return 1
    fi
}

### Create XHTTP inbound via API ###
api_create_xhttp_inbound() {
    if [[ "$INSTALL_PROFILE" == "separate-xhttp-sni" ]]; then
        api_create_xhttp_reality_inbound
    else
        api_create_xhttp_socket_inbound
    fi
}

### Create baseline XHTTP Unix-socket inbound via API ###
api_create_xhttp_socket_inbound() {
    local response
    response=$(api_curl_or_fail \
        "XHTTP CREATE" \
        "Failed to call XHTTP inbound API" \
        -b "${API_COOKIE_FILE}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -H "X-CSRF-Token: ${API_CSRF_TOKEN}" \
        -X POST \
        -d "{
            \"enable\": true,
            \"remark\": \"XHTTP-TLS\",
            \"listen\": \"${XHTTP_SOCKET},0666\",
            \"port\": 0,
            \"protocol\": \"vless\",
            \"expiryTime\": 0,
            \"total\": 0,
            \"settings\": {
                \"clients\": [
                    {
                        \"auth\": \"${CLIENT_AUTH}\",
                        \"comment\": \"\",
                        \"created_at\": ${CURRENT_MS},
                        \"email\": \"${CLIENT_EMAIL}\",
                        \"enable\": true,
                        \"expiryTime\": 0,
                        \"flow\": \"\",
                        \"id\": \"${XRAY_UUID}\",
                        \"limitIp\": 0,
                        \"password\": \"${CLIENT_PASSWORD}\",
                        \"reset\": 0,
                        \"security\": \"auto\",
                        \"subId\": \"${CLIENT_SUB_ID}\",
                        \"tgId\": 0,
                        \"totalGB\": 0,
                        \"updated_at\": ${CURRENT_MS}
                    }
                ],
                \"decryption\": \"none\",
                \"encryption\": \"none\"
            },
            \"streamSettings\": {
                \"network\": \"xhttp\",
                \"security\": \"none\",
                \"externalProxy\": [
                    {
                        \"forceTls\": \"tls\",
                        \"dest\": \"${REALITY_DOMAIN}\",
                        \"port\": 443,
                        \"remark\": \"\",
                        \"sni\": \"\",
                        \"alpn\": [\"h2\"],
                        \"pinnedPeerCertSha256\": []
                    }
                ],
                \"xhttpSettings\": {
                    \"path\": \"/${XHTTP_PATH}\",
                    \"host\": \"${REALITY_DOMAIN}\",
                    \"scMaxBufferedPosts\": 30,
                    \"scStreamUpServerSecs\": \"20-80\",
                    \"xPaddingBytes\": \"50-300\",
                    \"mode\": \"auto\"
                }
            },
            \"sniffing\": {
                \"enabled\": true,
                \"destOverride\": [
                    \"http\",
                    \"tls\"
                ]
            }
        }" \
        "$(api_url "/panel/api/inbounds/add")") || return 1
    if ! echo "${response}" | jq -e '.success == true' >/dev/null 2>&1; then
        echo
        echo "===== XHTTP CREATE FAILED ====="
        echo "${response}"
        echo
        msg_err "Failed to create XHTTP inbound"
        return 1
    fi
    ### XHTTP Unix socket uses 0666 intentionally.
    ### nginx must be able to connect to the socket created by Xray.
    ### Hardening to 0660 requires a shared nginx/xray group and separate testing.
}

### Create XHTTP REALITY inbound via API ###
api_create_xhttp_reality_inbound() {
    local response
    response=$(api_curl_or_fail \
        "XHTTP REALITY CREATE" \
        "Failed to call XHTTP REALITY inbound API" \
        -b "${API_COOKIE_FILE}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -H "X-CSRF-Token: ${API_CSRF_TOKEN}" \
        -X POST \
        -d "{
            \"enable\": true,
            \"remark\": \"XHTTP-REALITY\",
            \"listen\": \"127.0.0.1\",
            \"port\": 8444,
            \"protocol\": \"vless\",
            \"tag\": \"in-8444-tcp\",
            \"expiryTime\": 0,
            \"total\": 0,
            \"settings\": {
                \"clients\": [
                    {
                        \"auth\": \"${CLIENT_AUTH}\",
                        \"comment\": \"\",
                        \"created_at\": ${CURRENT_MS},
                        \"email\": \"${CLIENT_EMAIL}\",
                        \"enable\": true,
                        \"expiryTime\": 0,
                        \"flow\": \"\",
                        \"id\": \"${XRAY_UUID}\",
                        \"limitIp\": 0,
                        \"password\": \"${CLIENT_PASSWORD}\",
                        \"reset\": 0,
                        \"security\": \"auto\",
                        \"subId\": \"${CLIENT_SUB_ID}\",
                        \"tgId\": 0,
                        \"totalGB\": 0,
                        \"updated_at\": ${CURRENT_MS}
                    }
                ],
                \"decryption\": \"none\",
                \"encryption\": \"none\"
            },
            \"streamSettings\": {
                \"network\": \"xhttp\",
                \"xhttpSettings\": {
                    \"path\": \"/${XHTTP_PATH}\",
                    \"host\": \"${XHTTP_DOMAIN}\",
                    \"mode\": \"auto\",
                    \"xPaddingBytes\": \"100-1000\",
                    \"scMaxBufferedPosts\": 30,
                    \"scStreamUpServerSecs\": \"20-80\"
                },
                \"security\": \"reality\",
                \"realitySettings\": {
                    \"show\": false,
                    \"xver\": 0,
                    \"target\": \"127.0.0.1:9444\",
                    \"serverNames\": [
                        \"${XHTTP_DOMAIN}\"
                    ],
                    \"privateKey\": \"${PRIVATE_KEY}\",
                    \"minClientVer\": \"\",
                    \"maxClientVer\": \"\",
                    \"maxTimediff\": 0,
                    \"shortIds\": [
                        \"${SHORT_IDS[0]}\",
                        \"${SHORT_IDS[1]}\",
                        \"${SHORT_IDS[2]}\",
                        \"${SHORT_IDS[3]}\",
                        \"${SHORT_IDS[4]}\",
                        \"${SHORT_IDS[5]}\",
                        \"${SHORT_IDS[6]}\",
                        \"${SHORT_IDS[7]}\"
                    ],
                    \"mldsa65Seed\": \"\",
                    \"settings\": {
                        \"publicKey\": \"${PUBLIC_KEY}\",
                        \"fingerprint\": \"random\",
                        \"serverName\": \"\",
                        \"spiderX\": \"/\",
                        \"mldsa65Verify\": \"\"
                    }
                },
                \"externalProxy\": [
                    {
                        \"forceTls\": \"same\",
                        \"dest\": \"${XHTTP_DOMAIN}\",
                        \"port\": 443,
                        \"remark\": \"\",
                        \"sni\": \"\",
                        \"alpn\": [],
                        \"pinnedPeerCertSha256\": []
                    }
                ],
                \"sockopt\": {
                    \"acceptProxyProtocol\": true,
                    \"tcpFastOpen\": true,
                    \"domainStrategy\": \"UseIP\",
                    \"tcpMaxSeg\": 1440,
                    \"tcpKeepAliveInterval\": 60,
                    \"tcpKeepAliveIdle\": 300,
                    \"tcpUserTimeout\": 20000,
                    \"tcpcongestion\": \"bbr\",
                    \"tcpWindowClamp\": 600
                }
            },
            \"sniffing\": {
                \"enabled\": true,
                \"destOverride\": [
                    \"http\",
                    \"tls\"
                ]
            }
        }" \
        "$(api_url "/panel/api/inbounds/add")") || return 1
    if ! echo "${response}" | jq -e '.success == true' >/dev/null 2>&1; then
        echo
        echo "===== XHTTP REALITY CREATE FAILED ====="
        echo "${response}"
        echo
        msg_err "Failed to create XHTTP REALITY inbound"
        return 1
    fi
}

### Update x-ui settings via API ###
api_update_xui_settings() {
    local response
    response=$(api_curl_or_fail \
        "SETTINGS UPDATE" \
        "Failed to call panel settings API" \
        -b "${API_COOKIE_FILE}" \
        -H "Content-Type: application/json" \
        -H "X-CSRF-Token: ${API_CSRF_TOKEN}" \
        -X POST \
        -d "{
            \"webListen\":\"127.0.0.1\",
            \"webDomain\":\"\",
            \"webPort\":${PANEL_PORT},
            \"webCertFile\":\"/etc/letsencrypt/live/${DOMAIN}/fullchain.pem\",
            \"webKeyFile\":\"/etc/letsencrypt/live/${DOMAIN}/privkey.pem\",
            \"webBasePath\":\"/${PANEL_PATH}/\",
            \"sessionMaxAge\":360,
            \"trustedProxyCIDRs\":\"127.0.0.1/32,::1/128\",
            \"panelOutbound\":\"\",
            \"pageSize\":25,
            \"expireDiff\":0,
            \"trafficDiff\":0,
            \"remarkModel\":\"-ieo\",
            \"datepicker\":\"gregorian\",
            \"tgBotEnable\":false,
            \"tgBotToken\":\"\",
            \"tgBotProxy\":\"\",
            \"tgBotAPIServer\":\"\",
            \"tgBotChatId\":\"\",
            \"tgRunTime\":\"@daily\",
            \"tgBotBackup\":false,
            \"tgBotLoginNotify\":true,
            \"tgCpu\":80,
            \"tgLang\":\"en-US\",
            \"timeLocation\":\"Europe/Moscow\",
            \"twoFactorEnable\":false,
            \"twoFactorToken\":\"\",
            \"subEnable\":true,
            \"subJsonEnable\":false,
            \"subTitle\":\"\",
            \"subSupportUrl\":\"\",
            \"subProfileUrl\":\"\",
            \"subAnnounce\":\"\",
            \"subEnableRouting\":false,
            \"subRoutingRules\":\"\",
            \"subListen\":\"127.0.0.1\",
            \"subPort\":${SUB_PORT},
            \"subPath\":\"/${SUB_PATH}/\",
            \"subDomain\":\"\",
            \"subCertFile\":\"/etc/letsencrypt/live/${DOMAIN}/fullchain.pem\",
            \"subKeyFile\":\"/etc/letsencrypt/live/${DOMAIN}/privkey.pem\",
            \"subUpdates\":12,
            \"externalTrafficInformEnable\":false,
            \"externalTrafficInformURI\":\"\",
            \"restartXrayOnClientDisable\":true,
            \"subEncrypt\":true,
            \"subShowInfo\":true,
            \"subEmailInRemark\":true,
            \"subURI\":\"${SUB_URI}\",
            \"subJsonPath\":\"/json/\",
            \"subJsonURI\":\"\",
            \"subClashEnable\":false,
            \"subClashPath\":\"/clash/\",
            \"subClashURI\":\"\",
            \"subClashEnableRouting\":false,
            \"subClashRules\":\"\",
            \"subJsonMux\":\"\",
            \"subJsonRules\":\"\",
            \"subJsonFinalMask\":\"\",
            \"subThemeDir\":\"\",
            \"ldapEnable\":false,
            \"ldapHost\":\"\",
            \"ldapPort\":389,
            \"ldapUseTLS\":false,
            \"ldapBindDN\":\"\",
            \"ldapPassword\":\"\",
            \"ldapBaseDN\":\"\",
            \"ldapUserFilter\":\"(objectClass=person)\",
            \"ldapUserAttr\":\"mail\",
            \"ldapVlessField\":\"vless_enabled\",
            \"ldapSyncCron\":\"@every 1m\",
            \"ldapFlagField\":\"\",
            \"ldapTruthyValues\":\"true,1,yes,on\",
            \"ldapInvertFlag\":false,
            \"ldapInboundTags\":\"\",
            \"ldapAutoCreate\":false,
            \"ldapAutoDelete\":false,
            \"ldapDefaultTotalGB\":0,
            \"ldapDefaultExpiryDays\":0,
            \"ldapDefaultLimitIP\":0,
            \"warpUpdateInterval\":0
        }" \
        "$(api_url "/panel/api/setting/update")") || return 1
    if ! echo "${response}" | jq -e '.success == true' >/dev/null 2>&1; then
        echo
        echo "===== SETTINGS UPDATE FAILED ====="
        echo "${response}"
        echo
        msg_err "Failed to update panel settings"
        return 1
    fi
}

### Update Xray routing via API ###
api_update_xray_routing() {
    local current_response
    local current_obj
    local xray_setting
    local outbound_test_url
    local response
    current_response=$(api_curl_or_fail \
        "XRAY CONFIG READ" \
        "Failed to call Xray config read API" \
        -b "${API_COOKIE_FILE}" \
        -H "Content-Type: application/json" \
        -H "X-CSRF-Token: ${API_CSRF_TOKEN}" \
        -X POST \
        "$(api_url "/panel/api/xray/")") || return 1
    if ! echo "${current_response}" | jq -e '.success == true' >/dev/null 2>&1; then
        echo
        echo "===== XRAY CONFIG READ FAILED ====="
        echo "${current_response}"
        echo
        msg_err "Failed to read Xray config via API"
        return 1
    fi
    current_obj=$(echo "${current_response}" | jq -r '.obj')
    if ! echo "${current_obj}" | jq -e '
        type == "object" and
        (.xraySetting | type == "object")
    ' >/dev/null 2>&1
    then
        echo
        echo "===== UNEXPECTED XRAY API RESPONSE FORMAT ====="
        echo "${current_response}"
        echo
        msg_err "Xray API response does not contain object .obj.xraySetting"
        return 1
    fi
    outbound_test_url=$(echo "${current_obj}" | jq -r \
        '.outboundTestUrl // "https://www.google.com/generate_204"')
    xray_setting=$(echo "${current_obj}" | jq -c '.xraySetting' | jq -c '
        .outbounds = [
            {
                "tag": "direct",
                "protocol": "freedom",
                "settings": {
                    "domainStrategy": "AsIs",
                    "finalRules": [
                        {
                            "action": "allow"
                        }
                    ]
                }
            },
            {
                "tag": "blocked",
                "protocol": "blackhole",
                "settings": {}
            },
            {
                "tag": "IPv4",
                "protocol": "freedom",
                "settings": {
                    "domainStrategy": "UseIPv4"
                }
            }
        ]
        |
        .policy = {
            "system": {
                "statsInboundDownlink": true,
                "statsInboundUplink": true,
                "statsOutboundDownlink": true,
                "statsOutboundUplink": true
            },
            "levels": {
                "0": {
                    "statsUserDownlink": true,
                    "statsUserUplink": true
                }
            }
        }
        |
        .routing = {
            "rules": [
                {
                    "type": "field",
                    "inboundTag": [
                        "api"
                    ],
                    "outboundTag": "api"
                },
                {
                    "type": "field",
                    "protocol": [
                        "bittorrent"
                    ],
                    "outboundTag": "blocked"
                },
                {
                    "type": "field",
                    "ip": [
                        "geoip:private",
                        "geoip:br",
                        "ext:geoip_RU.dat:ru"
                    ],
                    "outboundTag": "blocked"
                },
                {
                    "type": "field",
                    "domain": [
                        "ext:geosite_RU.dat:ru-available-only-inside",
                        "regexp:.*\\.ru$",
                        "regexp:.*\\.su$",
                        "regexp:.*\\.xn--p1ai$"
                    ],
                    "outboundTag": "blocked"
                },
                {
                    "type": "field",
                    "domain": [
                        "geosite:google"
                    ],
                    "outboundTag": "IPv4"
                }
            ],
            "domainStrategy": "AsIs"
        }
    ')
    response=$(api_curl_or_fail \
        "XRAY ROUTING UPDATE" \
        "Failed to call Xray routing update API" \
        -b "${API_COOKIE_FILE}" \
        -H "X-CSRF-Token: ${API_CSRF_TOKEN}" \
        -X POST \
        -F "xraySetting=${xray_setting}" \
        -F "outboundTestUrl=${outbound_test_url}" \
        "$(api_url "/panel/api/xray/update")") || return 1
    if ! echo "${response}" | jq -e '.success == true' >/dev/null 2>&1; then
        echo
        echo "===== XRAY ROUTING UPDATE FAILED ====="
        echo "${response}"
        echo
        msg_err "Failed to update Xray routing via API"
        return 1
    fi
}
