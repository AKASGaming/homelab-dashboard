#!/usr/bin/env bash
# Fix a corrupted update.sh on TheaterNAS (one-time recovery)
set -euo pipefail
curl -fsSL -o /opt/homelab-dashboard/update.sh.new \
  https://raw.githubusercontent.com/AKASGaming/homelab-dashboard/main/update.sh
sed -i 's/\r$//' /opt/homelab-dashboard/update.sh.new
bash -n /opt/homelab-dashboard/update.sh.new
mv -f /opt/homelab-dashboard/update.sh.new /opt/homelab-dashboard/update.sh
chmod +x /opt/homelab-dashboard/update.sh
cat > /usr/local/bin/update-dashboard <<'EOF'
#!/usr/bin/env bash
exec /opt/homelab-dashboard/update.sh "$@"
EOF
chmod +x /usr/local/bin/update-dashboard
echo "update.sh repaired. Run: sudo update-dashboard"
