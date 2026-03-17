#!/usr/bin/env bash
set -euo pipefail

# OpenClaw Base Agents — Uninstall Script
# Disables timers and removes system agent files (preserves shared-data)

OPENCLAW_DIR="$HOME/.openclaw"
SYSTEMD_DIR="$HOME/.config/systemd/user"

AGENTS=(security-watchdog health-monitor memory-curator scheduler auditor)
TIMERS=(
  openclaw-security-daily
  openclaw-security-weekly
  openclaw-health-check
  openclaw-memory-daily
  openclaw-memory-weekly
  openclaw-audit-weekly
)

echo "=== OpenClaw Base Agents Uninstaller ==="
echo ""

# --- Disable timers ---
echo "Disabling timers..."
for timer in "${TIMERS[@]}"; do
  if systemctl --user is-enabled "${timer}.timer" &>/dev/null; then
    systemctl --user disable --now "${timer}.timer"
    echo "  Disabled: ${timer}.timer"
  fi
  rm -f "$SYSTEMD_DIR/${timer}.timer" "$SYSTEMD_DIR/${timer}.service"
done
systemctl --user daemon-reload

# --- Remove agent dirs and workspaces ---
echo ""
echo "Removing agent files..."
for agent in "${AGENTS[@]}"; do
  echo "  Removing: $agent"
  rm -rf "$OPENCLAW_DIR/agents/$agent"
  rm -rf "$OPENCLAW_DIR/workspace-$agent"
done

echo ""
echo "=== Done ==="
echo "NOTE: shared-data/ was preserved. Remove manually if needed."
echo "NOTE: You must manually remove these agents from openclaw.json."
