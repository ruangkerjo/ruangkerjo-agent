#!/bin/bash

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

  json_data=$(jq -n \
    --arg token "$arg" \
    --arg host "$hostname" \
    --arg os "$os" \
    '{token:$token, hostname:$host, os:$os}')

  res=$(curl -s -X POST "$API_URL/pair.php" \
    -H "Content-Type: application/json" \
    -d "$json_data")

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

  json_data=$(jq -n \
    --arg token "$TOKEN" \
    --arg cpu "$cpu" \
    --arg ram "$ram" \
    --arg disk "$disk" \
    --arg temp "$temp" \
    --arg load "$load" \
    '{token:$token, cpu:$cpu, ram:$ram, disk:$disk, temp:$temp, load:$load}')

  res=$(curl -s -X POST "$API_URL/report.php" \
    -H "Content-Type: application/json" \
    -d "$json_data")

  echo "$res" | grep -q invalid_token && invalidate_token
}

heartbeat() {
  [ ! -f "$CONFIG" ] && exit 0
  source "$CONFIG"

  json_data=$(jq -n --arg token "$TOKEN" '{token:$token}')

  res=$(curl -s -X POST "$API_URL/heartbeat.php" \
    -H "Content-Type: application/json" \
    -d "$json_data")

  echo "$res" | grep -q invalid_token && invalidate_token
}

command() {
  [ ! -f "$CONFIG" ] && exit 0
  source "$CONFIG"

  json_data=$(jq -n --arg token "$TOKEN" '{token:$token}')

  res=$(curl -s -X POST "$API_URL/command.php" \
    -H "Content-Type: application/json" \
    -d "$json_data")

  echo "$res" | grep -q invalid_token && invalidate_token
  echo "$res" | grep -q '"id"' || exit 0

  id=$(echo "$res" | grep -o '"id":[0-9]*' | cut -d: -f2)
  cmd=$(echo "$res" | sed -n 's/.*"command":"\([^"]*\)".*/\1/p')

  output=$(bash -c "$cmd" 2>&1)

  json_out=$(jq -n \
    --arg token "$TOKEN" \
    --arg id "$id" \
    --arg output "$output" \
    '{token:$token, command_id:$id, output:$output}')

  curl -s -X POST "$API_URL/command.php" \
    -H "Content-Type: application/json" \
    -d "$json_out" >/dev/null
}

case "$cmd" in
  pair) pair ;;
  report) report ;;
  heartbeat) heartbeat ;;
  command) command ;;
  *)
    echo "Usage:"
    echo "  ruangkerjo-agent pair <TOKEN>"
    echo "  ruangkerjo-agent report"
    echo "  ruangkerjo-agent heartbeat"
    echo "  ruangkerjo-agent command"
    ;;
esac
