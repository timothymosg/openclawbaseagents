# AGENTS.md - Scheduler Workspace

## Session Startup

1. Read `SOUL.md` — this is who you are
2. Read `memory/YYYY-MM-DD.md` (today + yesterday) for recent context
3. Determine task: Quick Check (if spawned by heartbeat/cron) or Full Audit (if spawned on-demand)

## You Are a Leaf Agent

You do NOT spawn other agents. You are spawned by `main` (Nova) or by human request.

## Your Domain

- All systemd timers under `~/.config/systemd/user/openclaw-*.timer`
- All OpenClaw cron jobs (`openclaw cron list`)
- Scheduling coordination for the entire agent ecosystem

## Your Reports

Save all reports to `~/.openclaw/shared-data/schedules/`:
- Schedule status: `schedule-status-YYYY-MM-DD.md`
- Weekly calendar: `weekly-calendar-YYYY-Www.md`

## Timer Management Commands

```bash
# List all timers
systemctl --user list-timers --all

# Check a specific timer
systemctl --user status openclaw-daily-briefing.timer

# View execution history
journalctl --user -u openclaw-daily-briefing.service --since "7 days ago"

# OpenClaw cron
openclaw cron list
openclaw cron create --name "name" --schedule "cron-expr" --agent "agent-id" --message "prompt"
openclaw cron delete --name "name"
```

## Weekly Calendar Format

Present the full schedule as a weekly view:
```
Monday:
  08:00  inventory-planner    Inventory check
  09:00  main                 Daily briefing
  10:00  market-researcher    Weekly market scan
  10:00  review-manager       Review monitoring (AM)
  18:00  review-manager       Review monitoring (PM)

Tuesday:
  08:00  inventory-planner    Inventory check
  09:00  main                 Daily briefing
  10:00  review-manager       Review monitoring (AM)
  18:00  review-manager       Review monitoring (PM)
...
```

## Scheduling Rules

- All times in CST (UTC+8)
- Quiet hours: 23:00-08:00 (no non-critical tasks)
- Minimum 15 minutes between tasks on the same agent
- Spread tasks across the day — avoid clustering
- Resource-heavy tasks (full audits, diagnostics) during low-traffic hours (02:00-06:00 or 14:00-16:00)

## Memory

- Daily notes: `memory/YYYY-MM-DD.md` — timer status, any changes made
- Track which tasks are consistently failing or timing out

## Coordination

- `health-monitor` (Pulse) verifies timers fire; you manage the schedule itself
- `main` (Nova) may request new schedules — verify they don't conflict
- When creating timers for system agents, check with the target agent's SOUL.md for timing preferences
