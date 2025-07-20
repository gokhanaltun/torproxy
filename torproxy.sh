#!/bin/bash

TOR_PROXYRC="/etc/tor/torproxyrc"
TOR_PROXYRC_DATA=(
    "VirtualAddrNetwork 10.0.0.0/10"
    "AutomapHostsOnResolve 1"
    "TransPort 9040"
    "DNSPort 5353"
    "ControlPort 9051"
    "RunAsDaemon 1"
    "DataDirectory /var/lib/tor"
)
RESOLV_CONF="/etc/resolv.conf"
RESOLV_CONF_BAK="/etc/resolv.conf.bak"
RESOLV_CONF_CONTENT=(
    "nameserver 127.0.0.1"
)
TOR_USER="debian-tor"
TOR_RUNNING=false

log() {
    echo -e "[INFO] $1"
}

warn() {
    echo -e "[WARN] $1"
}

error() {
    echo -e "[ERROR] $1"
}

check_root() {
    if [ "$(id -u)" != "0" ]; then
        error "This script must be run as root"
        exit 1
    fi
}

get_ip() {
    log "Trying to get external IP through Tor..."
    sleep 5

    EXTERNAL_IP=$(curl --silent https://api.ipify.org)
    if [[ -z "$EXTERNAL_IP" ]]; then
        error "Failed to get current IP."
    else
        log "Current IP: $EXTERNAL_IP"
    fi
}

check_tor_ports() {
    ss -tulnp | grep -qE '9040|9051|5353'
    if [[ $? -ne 0 ]]; then
        error "Tor is not listening on required ports (9040, 9051, 5353)."
        exit 1
    else
        log "Tor ports are active."
    fi
}

wait_for_tor_ports() {
    log "Waiting for Tor ports to be open..."
    for i in {1..10}; do
        ss -tuln | grep -qE '9040|9051|5353' && return
        sleep 1
    done
    error "Tor ports not opened in time."
    $TOR_RUNNING=true
    stop
}

set_torproxyrc() {
    log "Setting torproxyrc..."
    printf "%s\n" "${TOR_PROXYRC_DATA[@]}" > "$TOR_PROXYRC"
    chown "$TOR_USER:$TOR_USER" "$TOR_PROXYRC"
}

set_resolv_conf() {
    if [[ -f "$RESOLV_CONF" && ! -f "$RESOLV_CONF_BAK" ]]; then
        cp "$RESOLV_CONF" "$RESOLV_CONF_BAK"
        log "resolv.conf backup created."
    fi
    printf "%s\n" "${RESOLV_CONF_CONTENT[@]}" > "$RESOLV_CONF"
    log "resolv.conf updated for local DNS."
}

reset_resolv_conf() {
    if [[ -f "$RESOLV_CONF_BAK" ]]; then
        mv "$RESOLV_CONF_BAK" "$RESOLV_CONF"
        log "resolv.conf restored."
    else
        warn "Backup resolv.conf not found!"
    fi
}

set_iptables_rules() {
    log "Applying iptables rules..."

    NON_TOR="192.168.1.0/24 192.168.0.0/24"
    TOR_UID=$(id -u $TOR_USER)
    TRANS_PORT="9040"
    DNS_PORT="5353"

    iptables -F
    iptables -t nat -F
    iptables -t filter -F

    iptables -t nat -A OUTPUT -m owner --uid-owner $TOR_UID -j RETURN

    iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports $DNS_PORT

    for NET in $NON_TOR 127.0.0.0/8; do
        iptables -t nat -A OUTPUT -d $NET -j RETURN
    done

    iptables -t nat -A OUTPUT -p tcp -j REDIRECT --to-ports $TRANS_PORT

    for NET in $NON_TOR 127.0.0.0/8; do
        iptables -A OUTPUT -d $NET -j ACCEPT
    done

    iptables -A OUTPUT -m owner --uid-owner $TOR_UID -j ACCEPT
   
    iptables -A OUTPUT -j DROP
   
    ip6tables -F
    ip6tables -X
    ip6tables -P INPUT DROP
    ip6tables -P FORWARD DROP
    ip6tables -P OUTPUT DROP


    log "iptables rules set."
}

reset_iptables_rules() {
    log "Resetting iptables rules..."
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -t nat -F
    iptables -F
    iptables -X

    ip6tables -P INPUT ACCEPT
    ip6tables -P FORWARD ACCEPT
    ip6tables -P OUTPUT ACCEPT
    ip6tables -F
    ip6tables -X
}

start() {
    if [ "$TOR_RUNNING" = true ]; then
        log "Tor is already running."
    else
        set_torproxyrc
        set_resolv_conf

        log "Killing any existing Tor process on port 9051..."
        fuser -k 9051/tcp > /dev/null 2>&1

        log "Starting Tor manually..."
        su -s /bin/bash -c "tor -f $TOR_PROXYRC" "$TOR_USER" > /dev/null 2>&1 &
        wait_for_tor_ports
        check_tor_ports
        set_iptables_rules

        TOR_RUNNING=true
        get_ip
    fi
}

stop() {
    if [ "$TOR_RUNNING" = true ]; then
        log "Stopping Tor setup..."
        reset_iptables_rules

        fuser -k 9051/tcp > /dev/null 2>&1
        pkill -f "tor -f $TOR_PROXYRC"
        systemctl stop tor

        reset_resolv_conf
        TOR_RUNNING=false
        get_ip
    else
        log "Tor is not running, nothing to stop."
    fi
}

switch() {
    log "Requesting new identity from Tor..."
    echo -e 'AUTHENTICATE ""\nSIGNAL NEWNYM\nQUIT' | nc 127.0.0.1 9051 > /dev/null 2>&1
    sleep 3
    get_ip
}

main() {
    check_root
    trap stop SIGINT

    while true; do
        echo -n "s (start), x (stop), c (switch identity), i (get IP), q (quit): "
        read -r cmd

        case "$cmd" in
            s) start ;;
            x) stop ;;
            c) switch ;;
            i) get_ip ;;
            q) stop; exit 0 ;;
            *) echo "Invalid command" ;;
        esac
    done
}

main
