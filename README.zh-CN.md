# OpenClaw Base Agents

[English](README.md) | 中文

[OpenClaw](https://openclaw.ai) 的系统级代理，负责基础设施监控、安全防护、内存管理、定时调度和配置审计。可以把它们理解为运维团队——让你的 OpenClaw 保持健康和有序运行，而业务代理专注于实际工作。

## 代理列表

| 代理 | 角色 | 模型 | 功能 |
|------|------|------|------|
| **security-watchdog** | Sentinel 🔒 | gemini-3-flash | 监控 fail2ban、ufw、SSH 认证日志、开放端口。每日快速扫描，每周全面审计。标记入侵尝试和安全漂移。 |
| **health-monitor** | Pulse 💓 | gemini-3.1-flash-lite | 检查网关健康、RAM/磁盘/CPU、API 密钥有效性、systemd 定时器。网关宕机时自动重启。每天运行 4 次。 |
| **memory-curator** | Archive 🧠 | gemini-3.1-flash-lite | 管理**所有**代理的记忆生命周期。归档旧的日志文件、将有价值的洞察提升到长期记忆、去重共享知识、维护可搜索的索引。 |
| **scheduler** | Clockwork ⏰ | gemini-3.1-flash-lite | 管理 cron 定时器、检测调度冲突、跟踪执行历史。按需启动以审查或修改调度。 |
| **auditor** | Ledger 📋 | gemini-3-flash | 跟踪配置变更、检测与基线的偏移、维护仅追加的变更日志、验证备份。每周运行。 |

## 架构关系

```
main（你的主代理）
├── security-watchdog   → "有人在攻击我们吗？"
├── health-monitor      → "所有服务都在正常运行吗？"
├── memory-curator      → "知识库整理好了吗？"
├── scheduler           → "所有任务都按时执行了吗？"
└── auditor             → "有什么意外的变更吗？"
```

五个代理都是**叶子代理**——不会生成子代理。它们由 `main` 按需启动或由定时 cron 任务触发。报告保存到 `~/.openclaw/shared-data/` 的专用子目录中。

## 自动调度

| 时间 | 代理 | 任务 |
|------|------|------|
| 每 6 小时 (00:30, 06:30, 12:30, 18:30) | health-monitor | 快速健康检查，必要时自动重启 |
| 每天 06:00 | memory-curator | 快速整理——索引新文件，标记过期数据 |
| 每天 07:00 | security-watchdog | 快速扫描——fail2ban、ufw、SSH 日志 |
| 周六 04:00 | security-watchdog | 全面安全审计 |
| 周日 03:00 | memory-curator | 全面整理——归档、提升、重建索引 |
| 周日 04:00 | auditor | 全面配置审计——漂移检测、基线更新 |

所有时间为服务器本地时间。`scheduler` 代理没有 cron——按需启动以管理调度本身。

## 前置条件

- 已安装并运行 [OpenClaw](https://openclaw.ai)
- OpenRouter API 密钥（或在 `models.json` 中配置的其他 LLM 提供商）
- systemd 用户会话支持（`loginctl enable-linger <user>`）

## 安装

### 1. 克隆仓库

```bash
git clone git@github.com:timothymosg/openclawbaseagents.git ~/dev/OpenClawBaseAgents
cd ~/dev/OpenClawBaseAgents
```

### 2. 设置 API 密钥

创建环境文件（避免在 systemd 单元文件中硬编码密钥）：

```bash
echo "OPENROUTER_API_KEY=your-key-here" > ~/.openclaw/env
chmod 600 ~/.openclaw/env
```

### 3. 设置认证配置

每个代理需要在其 `agent/` 目录中有一个 `auth-profiles.json`。由于包含 API 密钥，这些文件已被 git 忽略。创建方法：

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

将 `YOUR_OPENROUTER_API_KEY` 替换为你的实际密钥。

### 4. 在 OpenClaw 配置中注册代理

将 `agents.json` 中的条目添加到 `~/.openclaw/openclaw.json` 的 `agents.list` 数组中。

### 5. 运行安装脚本

```bash
./scripts/install.sh
```

此脚本会将代理配置和工作区文件复制到 `~/.openclaw/`，部署 systemd 定时器并启用它们。

### 6. 重启网关

```bash
systemctl --user restart openclaw-gateway.service
```

### 7. 验证

```bash
# 检查代理是否已注册
openclaw agents list | grep -E "security|health|memory|scheduler|auditor"

# 检查定时器是否激活
systemctl --user list-timers 'openclaw-*'
```

## 卸载

```bash
./scripts/uninstall.sh
```

此脚本会禁用定时器、删除代理目录和工作区。`~/.openclaw/shared-data/` 中的共享数据会被保留。你需要手动从 `openclaw.json` 中移除代理条目。

## 项目结构

```
OpenClawBaseAgents/
├── README.md                # 英文文档
├── README.zh-CN.md          # 中文文档
├── CLAUDE.md               # Claude Code 项目指令
├── agents.json              # openclaw.json 的配置片段
├── .gitignore
├── agents/
│   ├── security-watchdog/
│   │   ├── agent/           # models.json（auth-profiles.json 已被 git 忽略）
│   │   └── workspace/       # IDENTITY.md, SOUL.md, AGENTS.md
│   ├── health-monitor/
│   ├── memory-curator/
│   ├── scheduler/
│   └── auditor/
├── shared-data/
│   └── api-throttle/
│       └── config.json      # 各服务限流配置
├── systemd/                 # systemd .timer + .service 单元文件
│   ├── openclaw-health-check.*
│   ├── openclaw-security-daily.*
│   ├── openclaw-security-weekly.*
│   ├── openclaw-memory-daily.*
│   ├── openclaw-memory-weekly.*
│   └── openclaw-audit-weekly.*
└── scripts/
    ├── install.sh           # 部署到 ~/.openclaw/ 并启用定时器
    ├── uninstall.sh         # 移除代理并禁用定时器
    └── api-throttle.sh      # 外部 API 调用的仿人类限流控制器
```

## 开发

编辑代理行为，修改 `agents/{id}/workspace/` 中的文件：

- **IDENTITY.md** — 代理角色设定（名称、表情、风格）
- **SOUL.md** — 核心行为、操作手册、沟通风格、红线规则
- **AGENTS.md** — 会话启动、协调规则、职责边界

编辑调度在 `systemd/` 中。修改后运行 `scripts/install.sh` 进行部署。

## 记忆管理器工作原理

memory-curator 是最复杂的代理，管理完整的记忆生命周期：

```
日常记忆文件（短期）                         长期记忆
workspace-*/memory/YYYY-MM-DD.md    →        workspace-*/MEMORY.md
         ↓（14 天后）                              ↓（季度审查）
   压缩为周总结                                  清理过期条目
         ↓（30 天后）
   归档到 shared-data/archive/
```

同时维护：
- `~/.openclaw/shared-data/INDEX.md` — 所有共享知识的可搜索索引
- `~/.openclaw/shared-data/curation/memory-health.json` — 各代理的记忆统计
- `shared-data/knowledge/` 中的跨代理知识传播摘要

## API 限流控制

所有代理在调用外部 API 时，必须通过集中式限流控制器。这可以防止被外部服务的机器人检测系统识别和封禁，让 API 调用模式看起来像人类操作。

**工作原理：**

```bash
# 不要直接调用 API：
curl -s https://api.telegram.org/bot$TOKEN/getMe

# 代理必须使用限流包装器：
~/.openclaw/api-throttle telegram -- curl -s https://api.telegram.org/bot$TOKEN/getMe
```

**核心特性：**
- 仿人类随机延迟（高斯分布，非均匀分布）
- 按服务的突发限制（时间窗口内最大 N 次调用）
- 错误时指数退避并带抖动
- 会话预热（长时间不活跃后首次调用延迟更长）
- 代理间抖动，防止请求同步
- 完整审计日志：`~/.openclaw/shared-data/api-throttle/throttle.log`

**预配置服务：** `openrouter`、`telegram`、`github`、`resend`、`shopify`、`google`、`generic`

**调优：** 编辑 `~/.openclaw/shared-data/api-throttle/config.json` 以调整各服务的延迟范围、突发限制和退避设置。安装脚本会保留已部署的现有配置。

**监控：**

```bash
~/.openclaw/api-throttle --status              # 所有服务
~/.openclaw/api-throttle --status openrouter   # 单个服务
~/.openclaw/api-throttle --reset telegram      # 清除退避状态
```

## 安全说明

- `auth-profiles.json` 文件包含 API 密钥，已被 git 忽略
- systemd 服务通过 `~/.openclaw/env` 引用 API 密钥（非硬编码）
- security-watchdog 代理仅报告发现，未经人工批准不会修改防火墙规则或解封 IP
- auditor 在所有报告中会对 API 密钥和令牌进行脱敏处理

## 许可证

私有项目，禁止再分发。
