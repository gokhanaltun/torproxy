#!/bin/bash

TOR_PROXYRC="/etc/tor/torproxyrc"
TOR_PROXYRC_HASH="96119f314be151b839c8ad8418fd38a22ab60c79ce7a472ed73d3ad9f0f4c25e"
TOR_PROXYRC_DATA=(
    "VirtualAddrNetwork 10.0.0.0/10"
    "AutomapHostsOnResolve 1"
    "TransPort 9040"
    "DNSPort 5353"
    "ControlPort 9051"
    "RunAsDaemon 1"
)
RESOLV_CONF="/etc/resolv.conf"
RESOLV_CONF_BAK="/etc/resolv.conf.bak"
RESOLV_CONF_CONTENT="nameserver 127.0.0.1"

active=0

check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "This script must be run as root" 1>&2
        exit 1
    fi
}

get_ip() {
    echo "Getting current ip..."
    sleep 5
    EXTERNAL_IP=$(curl --silent "https://api.ipify.org")
    echo "Current ip: $EXTERNAL_IP"

    if [[ -z "$EXTERNAL_IP" ]]; then
        echo "Failed to get current ip."
    fi
}

set_torproxyrc() {
    echo "Checking rc file: $TOR_PROXYRC"
    
    valid=1
    
    if [[ -f "$TOR_PROXYRC" ]]; then
        echo "Checking rc file hash..."
        
        FILE_HASH=$(sha256sum $TOR_PROXYRC | awk '{print $1}')
        
        if [[ "$FILE_HASH" != "$TOR_PROXYRC_HASH" ]]; then
            valid=0
        fi
    else
        valid=0
    fi

    if [[ $valid -eq 0 ]]; then
        echo "Rewriting the RC file..." 
        printf "%s\n" "${TOR_PROXYRC_DATA[@]}" > "$TOR_PROXYRC"
    fi
}

set_resolv_conf() {
    if [[ -f "$RESOLV_CONF" ]]; then
        mv $RESOLV_CONF $RESOLV_CONF_BAK
        echo "Backup of resolv.conf created."
    fi
    
    echo "$RESOLV_CONF_CONTENT" > "$RESOLV_CONF"
    echo "resolv.conf has been updated."
}

reset_resolv_conf() {
    if [[ -f "$RESOLV_CONF_BAK" ]]; then
        mv $RESOLV_CONF_BAK $RESOLV_CONF
        echo "resolv.conf has been restored from backup."
    else
        echo "Backup file not found. Cannot restore $RESOLV_CONF."
    fi
}

set_iptables_rules() {
    NON_TOR="192.168.1.0/24 192.168.0.0/24"
    TOR_UID=$(id -ur debian-tor)
    TRANS_PORT="9040"

    iptables -F
    iptables -t nat -F

    iptables -t nat -A OUTPUT -m owner --uid-owner $TOR_UID -j RETURN
    iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports 5353
    for NET in $NON_TOR 127.0.0.0/9 127.128.0.0/10; do
    iptables -t nat -A OUTPUT -d $NET -j RETURN
    done
    iptables -t nat -A OUTPUT -p tcp --syn -j REDIRECT --to-ports $TRANS_PORT

    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    for NET in $NON_TOR 127.0.0.0/8; do
    iptables -A OUTPUT -d $NET -j ACCEPT
    done
    iptables -A OUTPUT -m owner --uid-owner $TOR_UID -j ACCEPT
    iptables -A OUTPUT -j REJECT
}

reset_iptables_rules() {
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -t nat -F
    iptables -t mangle -F
    iptables -F
    iptables -X
}

start() {
    set_torproxyrc
    set_resolv_conf
    
    echo "Starting tor..."
    systemctl start tor

    echo "Clearing control port..."
    fuser -k 9051/tcp > /dev/null 2>&1

    echo "Starting new tor daemon..."
    sudo -u debian-tor tor -f /etc/tor/torproxyrc > /dev/null

    echo "Setting up iptables rules..."
    set_iptables_rules
    
    get_ip

    active=1
}

stop() {
    if [ "$active" -eq 1 ]; then
        echo "Resetting iptables rules..."
        reset_iptables_rules
        
        echo "Clearing control port..."
        fuser -k 9051/tcp > /dev/null 2>&1

        echo "Stopping tor daemon..."
        pkill -f "tor -f /etc/tor/torproxyrc"

        echo "Stopping tor..."
        systemctl stop tor

        echo "Restoring resolv.conf..."
        reset_resolv_conf

        get_ip

        active=0
    fi
}

switch() {
    echo "Requesting new identity..."
    echo -e "AUTHENTICATE \"\" \nSIGNAL NEWNYM"  | nc -w 2 127.0.0.1 9051 > /dev/null 2>&1
    
    get_ip
}

sigint_handler() {
    echo -e "\n"
    stop
    exit 0
}

trap sigint_handler SIGINT

main() {
    check_root
    while true; do
        echo -n "s for start, x for stop, c for switch, i for ip, q for quit: "
        read command

        case "$command" in
            s)
                if [ "$active" -eq 0 ]; then
                    start
                else
                    echo "Already running"
                fi
                ;;
            x)
                if [ "$active" -eq 1 ]; then
                    stop
                else
                    echo "Not running"
                fi
                ;;
            c)
                if [ "$active" -eq 1 ]; then
                    switch
                else
                    echo "Not running"
                fi
                ;;
            i)
                get_ip
                ;;
            q)
                stop
                exit 0
                ;;
            *)
                echo "Invalid option, try again."
                ;;
        esac
    done
}

main