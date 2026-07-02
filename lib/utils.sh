# shellcheck shell=bash

### Messages ###
msg_ok() {
    printf "\e[1;32m %-38s %s\e[0m\n" "$1" "$2"
}
msg_err() {
    echo -e "\e[1;31m $1 \e[0m"
}
msg_warn() {
    printf "\e[1;33m %-38s %s\e[0m\n" "$1" "$2"
}
msg_inf() {
    printf "\e[1;36m %-38s %s\e[0m\n" "$1" "$2"
}
msg_blank() {
    echo
}

### Generate random port ###
get_port() {
    echo $(( ((RANDOM << 15) | RANDOM) % 49152 + 10000 ))
}

### Generate random string ###
gen_random_string() {
    local length="$1"
    tr -dc 'a-zA-Z0-9' </dev/urandom | head -c "$length"
    echo
}

### Check if port is free ###
check_free() {
    local port="$1"
    if ss -H -ltn "sport = :${port}" 2>/dev/null | grep -q .; then
        return 1
    fi
    return 0
}

### Generate free port ###
make_port() {
    local port
    while true; do
        port=$(get_port)
        if check_free "$port"; then
            echo "$port"
            break
        fi
    done
}
