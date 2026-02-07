#!/bin/bash
set -e

API_URL="https://zone.ruangkerjo.com/api"
CONFIG="/opt/ruangkerjo-agent/config"

cmd="$1"
arg="$2"

invalidate_token() {
    echo "Token tidak valid, agent dihentikan"
    rm -f "$CONFIG"
    systemctl stop ruangkerjo-agent.timer >/dev/null 2>&1
    exit 0
}

pair() {
    [ -z "$arg" ] && echo "Token wajib" && exit 1

    hostname=$(hostname)
    os=$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')

    res=$(curl -s -X POST "$API_URL/pair.php" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "token=$arg" \
        -d "hostname=$hostname" \
        -d "os=$os")

    if echo "$res" | grep -q paired; then
        echo "TOKEN=$arg" > "$CONFIG"
        echo "Paired berhasil"

        systemctl daemon-reload
        systemctl enable ruangkerjo-agent.timer
        systemctl start ruangkerjo-agent.timer
    else
        echo "Gagal pairing:"
        echo "$res"
    fi
}

report() {
    [ ! -f "$CONFIG" ] && exit 0
    source "$CONFIG"

    cpu=$(top -bn1 | awk '/Cpu/ {print 100-$8}')
    ram=$(free | awk '/Mem/ {printf "%.2f", $3/$2*100}')
    disk=$(df / | awk 'END {print $5}' | tr -d '%')
    temp=$(awk '{print $1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)
    load=$(cut -d' ' -f1-3 /proc/loadavg)

    res=$(curl -s -X POST "$API_URL/report.php" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "token=$TOKEN" \
        -d "cpu=$cpu" \
        -d "ram=$ram" \
        -d "disk=$disk" \
        -d "temp=$temp" \
        -d "load=$load")

    echo "$res" | grep -q invalid_token && invalidate_token
}

heartbeat() {
    [ ! -f "$CONFIG" ] && exit 0
    source "$CONFIG"

    res=$(curl -s -X POST "$API_URL/heartbeat.php" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "token=$TOKEN")

    echo "$res" | grep -q invalid_token && invalidate_token
}

command() {
    [ ! -f "$CONFIG" ] && exit 0
    source "$CONFIG"

    res=$(curl -s -X POST "$API_URL/command.php" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "token=$TOKEN")

    echo "$res" | grep -q invalid_token && invalidate_token
    echo "$res" | grep -q '"id"' || exit 0

    id=$(echo "$res" | grep -o '"id":[0-9]*' | cut -d: -f2)
    cmd=$(echo "$res" | sed -n 's/.*"command":"\([^"]*\)".*/\1/p')

    output=$(bash -c "$cmd" 2>&1)

    curl -s -X POST "$API_URL/command.php" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "token=$TOKEN" \
        -d "command_id=$id" \
        --data-urlencode "output=$output" >/dev/null
}

case "$cmd" in
    pair) pair ;;
    report) report ;;
    heartbeat) heartbeat ;;
    command) command ;;
    *)
        echo "Usage:"
        echo "  ruangkerjo-agent pair <TOKEN>"
        ;;
esac
