# OpenClaw Base Agents

System-level agents for [OpenClaw](https://openclaw.ai) that handle infrastructure monitoring, security, memory management, scheduling, and configuration auditing. Think of them as the ops team that keeps your OpenClaw installation healthy and organized while your domain agents focus on actual work.

## Agents

| Agent | Persona | Model | What it does |
|-------|---------|-------|-------------|
| **security-watchdog** | Sentinel 🔒 | gemini-3-flash | Monitors fail2ban, ufw, SSH auth logs, open ports. Runs daily quick scans and weekly full audits. Flags intrusion attempts and security drift. |
| **health-monitor** | Pulse 💓 | gemini-3.1-flash-lite | Checks gateway health, RAM/disk/CPU, API key validity, systemd timers. Auto-restarts the gateway if it goes down. Runs 4x/day. |
| **memory-curator** | Archive 🧠 | gemini-3.1-flash-lite | Manages the memory lifecycle across **all** agents. Archives old daily files, promotes insights to long-term memory, deduplicates shared knowledge, maintains a searchable index. |
| **scheduler** | Clockwork ⏰ | gemini-3.1-flash-lite | Manages cron timers, detects scheduling conflicts, tracks execution history. Spawned on-demand to review or modify the schedule. |
| **auditor** | Ledger 📋 | gemini-3-flash | Tracks configuration changes, detects drift from baseline, maintains an append-only changelog, verifies backups. Runs weekly. |

## How They Fit Together

```
main (your primary agent)
├── security-watchdog   → "Is anyone attacking us?"
├── health-monitor      → "Is everything running?"
├── memory-curator      → "Is our knowledge organized?"
├── scheduler           → "Is everything running on time?"
└── auditor             → "Has anything changed unexpectedly?"
```

All five are **leaf agents** — they don't spawn sub-agents. They're spawned by `main` on-demand or by scheduled cron timers. Reports are saved to `~/.openclaw/shared-data/` in dedicated subdirectories.

## Automated Schedule

| Time | Agent | Task |
|------|-------|------|
| Every 6h (00:30, 06:30, 12:30, 18:30) | health-monitor | Quick health check, auto-restart if needed |
| Daily 06:00 | memory-curator | Quick tidy — index new files, flag stale data |
| Daily 07:00 | security-watchdog | Quick scan — fail2ban, ufw, SSH logs |
| Saturday 04:00 | security-watchdog | Full security audit |
| Sunday 03:00 | memory-curator | Full curation — archive, promote, rebuild index |
| Sunday 04:00 | auditor | Full config audit — drift detection, baseline update |

All times in server local time. The `scheduler` agent has no cron — it's spawned on-demand to manage the schedule itself.

## Prerequisites

- [OpenClaw](https://openclaw.ai) installed and running
- An OpenRouter API key (or other LLM provider configured in `models.json`)
- systemd user session support (`loginctl enable-linger <user>`)

## Installation

### 1. Clone the repo

```bash
git clone git@github.com:timothymosg/openclawbaseagents.git ~/dev/OpenClawBaseAgents
cd ~/dev/OpenClawBaseAgents
```

### 2. Set up your API key

Create an environment file (keeps secrets out of systemd unit files):

```bash
echo "OPENROUTER_API_KEY=your-key-here" > ~/.openclaw/env
chmod 600 ~/.openclaw/env
```

### 3. Set up auth profiles

Each agent needs an `auth-profiles.json` in its `agent/` directory. These are git-ignored since they contain API keys. Create them:

```bash
for agent in security-watchdog health-monitor memory-curator scheduler auditor; do
  cat > agents/$agent/agent/auth-profiles.json <<'AUTHEOF'
{
  "openrouter:manual": {
    "provider": "openrouter",
    "token": "YOUR_OPENROUTER_API_KEY",
    "label": "OpenRouter API Key",
    "createdAt": "2026-01-01T00:00:00.000Z"
  }
}
AUTHEOF
done
```

Replace `YOUR_OPENROUTER_API_KEY` with your actual key.

### 4. Register agents in OpenClaw config

Add the entries from `agents.json` to the `agents.list` array in `~/.openclaw/openclaw.json`.

### 5. Run the install script

```bash
./scripts/install.sh
```

This copies agent configs and workspace files to `~/.openclaw/`, deploys systemd timers, and enables them.

### 6. Restart the gateway

```bash
systemctl --user restart openclaw-gateway.service
```

### 7. Verify

```bash
# Check agents are registered
openclaw agents list | grep -E "security|health|memory|scheduler|auditor"

# Check timers are active
systemctl --user list-timers 'openclaw-*'
```

## Uninstalling

```bash
./scripts/uninstall.sh
```

This disables timers, removes agent directories and workspaces. Shared data in `~/.openclaw/shared-data/` is preserved. You'll need to manually remove the agent entries from `openclaw.json`.

## Project Structure

```
OpenClawBaseAgents/
├── README.md
├── CLAUDE.md               # Project instructions for Claude Code
├── agents.json              # Config fragment for openclaw.json
├── .gitignore
├── agents/
│   ├── security-watchdog/
│   │   ├── agent/           # models.json (auth-profiles.json is git-ignored)
│   │   └── workspace/       # IDENTITY.md, SOUL.md, AGENTS.md
│   ├── health-monitor/
│   ├── memory-curator/
│   ├── scheduler/
│   └── auditor/
├── systemd/                 # systemd .timer + .service unit files
│   ├── openclaw-health-check.*
│   ├── openclaw-security-daily.*
│   ├── openclaw-security-weekly.*
│   ├── openclaw-memory-daily.*
│   ├── openclaw-memory-weekly.*
│   └── openclaw-audit-weekly.*
└── scripts/
    ├── install.sh           # Deploy to ~/.openclaw/ and enable timers
    └── uninstall.sh         # Remove agents and disable timers
```

## Development

Edit agent behavior in `agents/{id}/workspace/`:

- **IDENTITY.md** — Agent persona (name, emoji, vibe)
- **SOUL.md** — Core behavior, playbooks, communication style, red lines
- **AGENTS.md** — Session startup, coordination rules, domain boundaries

Edit schedules in `systemd/`. After making changes, run `scripts/install.sh` to deploy.

## Memory Curator — How It Works

The memory-curator is the most complex agent. It manages the full memory lifecycle:

```
Daily memory files (short-term)              Long-term memory
workspace-*/memory/YYYY-MM-DD.md    →        workspace-*/MEMORY.md
         ↓ (after 14 days)                          ↓ (quarterly review)
   Compress into weekly summaries              Prune stale entries
         ↓ (after 30 days)
   Archive to shared-data/archive/
```

It also maintains:
- `~/.openclaw/shared-data/INDEX.md` — searchable index of all shared knowledge
- `~/.openclaw/shared-data/curation/memory-health.json` — memory stats per agent
- Cross-pollination summaries in `shared-data/knowledge/`

## Security Notes

- `auth-profiles.json` files contain API keys and are git-ignored
- systemd services reference `~/.openclaw/env` for the API key (not hardcoded)
- The security-watchdog agent reports findings but never modifies firewall rules or unbans IPs without human approval
- The auditor redacts API keys and tokens in all reports

## License

Private project. Not for redistribution.
