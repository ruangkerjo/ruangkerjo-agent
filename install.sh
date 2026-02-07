#!/bin/bash
set -e

INSTALL_DIR="/opt/ruangkerjo-agent"
BIN="/usr/local/bin/ruangkerjo-agent"
REPO_RAW="https://raw.githubusercontent.com/ruangkerjo/ruangkerjo-agent/main"

echo "== RuangKerjo Agent Installer =="

if [ "$EUID" -ne 0 ]; then
  echo "❌ Jalankan sebagai root"
  exit 1
fi

echo "→ Menyiapkan direktori"
mkdir -p "$INSTALL_DIR"

echo "→ Download agent"
curl -fsSL "$REPO_RAW/agent.sh" -o "$INSTALL_DIR/agent.sh"

chmod +x "$INSTALL_DIR/agent.sh"
ln -sf "$INSTALL_DIR/agent.sh" "$BIN"

##################################
# SYSTEMD SERVICE
##################################
cat > /etc/systemd/system/ruangkerjo-agent.service <<EOF
[Unit]
Description=RuangKerjo Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$INSTALL_DIR/agent.sh report
ExecStartPost=$INSTALL_DIR/agent.sh heartbeat
ExecStartPost=$INSTALL_DIR/agent.sh command
EOF

##################################
# SYSTEMD TIMER
##################################
cat > /etc/systemd/system/ruangkerjo-agent.timer <<EOF
[Unit]
Description=RuangKerjo Agent Timer

[Timer]
OnBootSec=30
OnUnitActiveSec=60
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now ruangkerjo-agent.timer

echo ""
echo "✔ Agent berhasil diinstall"
echo ""
echo "Langkah selanjutnya:"
echo "  ruangkerjo-agent pair <TOKEN>"
