#!/usr/bin/env bash
set -euo pipefail

# OpenClaw Base Agents — Install Script
# Deploys system agents to ~/.openclaw/ and enables systemd timers

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OPENCLAW_DIR="$HOME/.openclaw"
SYSTEMD_DIR="$HOME/.config/systemd/user"

AGENTS=(security-watchdog health-monitor memory-curator scheduler auditor)

echo "=== OpenClaw Base Agents Installer ==="
echo "Source: $PROJECT_DIR"
echo "Target: $OPENCLAW_DIR"
echo ""

# --- Deploy agent configs ---
for agent in "${AGENTS[@]}"; do
  echo "Deploying agent: $agent"

  # Agent dir (models.json, auth-profiles.json)
  agent_dir="$OPENCLAW_DIR/agents/$agent/agent"
  mkdir -p "$agent_dir"
  cp "$PROJECT_DIR/agents/$agent/agent/models.json" "$agent_dir/"
  if [ -f "$PROJECT_DIR/agents/$agent/agent/auth-profiles.json" ]; then
    cp "$PROJECT_DIR/agents/$agent/agent/auth-profiles.json" "$agent_dir/"
  fi

  # Workspace (IDENTITY.md, SOUL.md, AGENTS.md)
  workspace_dir="$OPENCLAW_DIR/workspace-$agent"
  mkdir -p "$workspace_dir"
  cp "$PROJECT_DIR/agents/$agent/workspace/IDENTITY.md" "$workspace_dir/"
  cp "$PROJECT_DIR/agents/$agent/workspace/SOUL.md" "$workspace_dir/"
  cp "$PROJECT_DIR/agents/$agent/workspace/AGENTS.md" "$workspace_dir/"
done

# --- Create shared-data directories ---
echo ""
echo "Ensuring shared-data directories..."
mkdir -p "$OPENCLAW_DIR/shared-data"/{security,health,schedules,audit,audit/backups,curation,knowledge,archive,archive/agent-memory,api-throttle,api-throttle/state}

# --- Deploy API throttle ---
echo "Deploying API throttle controller..."
cp "$PROJECT_DIR/scripts/api-throttle.sh" "$OPENCLAW_DIR/shared-data/api-throttle/api-throttle.sh"
chmod +x "$OPENCLAW_DIR/shared-data/api-throttle/api-throttle.sh"
if [ ! -f "$OPENCLAW_DIR/shared-data/api-throttle/config.json" ]; then
  cp "$PROJECT_DIR/shared-data/api-throttle/config.json" "$OPENCLAW_DIR/shared-data/api-throttle/config.json"
  echo "  Installed default throttle config"
else
  echo "  Throttle config already exists — preserved (update manually if needed)"
fi
# Create convenience symlink
ln -sf "$OPENCLAW_DIR/shared-data/api-throttle/api-throttle.sh" "$OPENCLAW_DIR/api-throttle"

# --- Deploy systemd timers ---
echo ""
echo "Deploying systemd timers..."
mkdir -p "$SYSTEMD_DIR"
cp "$PROJECT_DIR/systemd/"*.service "$SYSTEMD_DIR/"
cp "$PROJECT_DIR/systemd/"*.timer "$SYSTEMD_DIR/"

echo "Reloading systemd..."
systemctl --user daemon-reload

# --- Enable timers ---
echo "Enabling timers..."
for timer in "$PROJECT_DIR/systemd/"*.timer; do
  timer_name="$(basename "$timer")"
  systemctl --user enable --now "$timer_name"
  echo "  Enabled: $timer_name"
done

echo ""
echo "=== Done ==="
echo "Agents deployed: ${AGENTS[*]}"
echo "Run 'openclaw agents list' to verify."
echo "Run 'systemctl --user list-timers' to check schedules."
