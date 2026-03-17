# OpenClaw Base Agents

System-level agents for OpenClaw infrastructure management. These are the "ops team" that keeps the platform healthy, secure, and organized.

## Agents

| ID | Persona | Purpose |
|----|---------|---------|
| `security-watchdog` | Sentinel | fail2ban, ufw, SSH, intrusion detection |
| `health-monitor` | Pulse | Gateway health, RAM/disk, API keys, self-healing |
| `memory-curator` | Archive | Memory lifecycle for all agents, shared knowledge index |
| `scheduler` | Clockwork | Cron timer management, schedule coordination |
| `auditor` | Ledger | Config drift detection, change log, backups |

## Project Structure

```
agents/
  {agent-id}/
    agent/              # OpenClaw agent config (models.json, auth-profiles.json)
    workspace/          # Workspace files (IDENTITY.md, SOUL.md, AGENTS.md)
systemd/                # systemd timer + service unit files
scripts/
  install.sh            # Deploy agents to ~/.openclaw/ and enable timers
  uninstall.sh          # Remove agents and disable timers
```

## Development

- Edit agent configs in `agents/{id}/workspace/` (SOUL.md, AGENTS.md, IDENTITY.md)
- Edit schedules in `systemd/`
- Run `scripts/install.sh` to deploy changes to the live OpenClaw installation
- Auth files (`auth-profiles.json`) contain API keys — tracked in .gitignore template, kept locally

## Deployment Target

- OpenClaw config: `~/.openclaw/openclaw.json`
- Agent dirs: `~/.openclaw/agents/{id}/agent/`
- Workspaces: `~/.openclaw/workspace-{id}/`
- Timers: `~/.config/systemd/user/`
- Shared data: `~/.openclaw/shared-data/`
