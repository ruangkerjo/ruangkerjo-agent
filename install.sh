#!/bin/bash
set -e

INSTALL_DIR="/opt/ruangkerjo-agent"
BIN="/usr/local/bin/ruangkerjo-agent"
GITHUB_RAW="https://raw.githubusercontent.com/ruangkerjo/ruangkerjo-agent/main"

echo "== RuangKerjo Agent Installer =="

# check root
[ "$EUID" -ne 0 ] && echo "Jalankan sebagai root" && exit 1

mkdir -p "$INSTALL_DIR"

echo "→ Download agent"
curl -fsSL "$GITHUB_RAW/agent.sh" -o "$INSTALL_DIR/agent.sh"
chmod +x "$INSTALL_DIR/agent.sh"

ln -sf "$INSTALL_DIR/agent.sh" "$BIN"

##################################
# SYSTEMD SERVICE & TIMER
##################################
cat > /etc/systemd/system/ruangkerjo-agent.service <<EOF
[Unit]
Description=RuangKerjo Agent
After=network-online.target

[Service]
Type=oneshot
ExecStart=$INSTALL_DIR/agent.sh report
ExecStartPost=$INSTALL_DIR/agent.sh heartbeat
ExecStartPost=$INSTALL_DIR/agent.sh command
EOF

cat > /etc/systemd/system/ruangkerjo-agent.timer <<EOF
[Unit]
Description=RuangKerjo Agent Timer

[Timer]
OnBootSec=30
OnUnitActiveSec=60

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload

echo "✔ Agent berhasil diinstall"
echo "Gunakan:"
echo "  ruangkerjo-agent pair <TOKEN>"
