# OpenCode 配置文件全面检视报告（最终版）

> 检视范围：`~/.config/opencode/` 目录下的 3 个 JSON 配置文件
> 检视日期：2026-07-05
> 参考源码：[opencode](https://github.com/sst/opencode)、[oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent)
> 验证方法：源码逐行追踪 + bun 运行时兼容层测试 + opencode 命令实际执行
> 插件版本：oh-my-openagent@4.15.1

---

## 目录

1. [配置文件概览与验证基础](#1-配置文件概览与验证基础)
2. [opencode.jsonc 逐项检视](#2-opencodejsonc-逐项检视)
3. [oh-my-openagent.jsonc 逐项检视](#3-oh-my-openagentjsonc-逐项检视)
4. [tui.json 逐项检视](#4-tuijson-逐项检视)
5. [thinking / variant / reasoningEffort 深度分析（源码+运行时双重验证）](#5-thinking--variant--reasoningeffort-深度分析)
6. [Agent/Category 模型分配与并发分析](#6-agentcategory-模型分配与并发分析)
7. [问题汇总与改进建议](#7-问题汇总与改进建议)
8. [附录：验证方法与关键源码引用](#8-附录验证方法与关键源码引用)

---

## 1. 配置文件概览与验证基础

### 1.1 文件清单

| 文件 | 大小 | 用途 |
|---|---|---|
| `opencode.jsonc` | 1,400 B | opencode 主配置（provider/model/mcp/plugin） |
| `oh-my-openagent.jsonc` | 13,191 B | oh-my-openagent 插件配置（agent/category/团队/回退） |
| `tui.json` | 58 B | opencode TUI 插件配置 |

### 1.2 实际命令验证结果

**认证状态**（`opencode auth list` 执行结果）：

```
Kimi For Coding — api     ← 已认证
DeepSeek        — api     ← 已认证
Hugging Face    — HF_TOKEN (环境变量，已被 disabled_providers 禁用)
```

zhipuai-coding-plan 通过 `opencode.jsonc` 中的 `{file:./.secrets/ZHIPU_AI_CODING_PLAN_API_KEY}` 配置认证，无需 `opencode auth`。三个 provider 认证状态均正常。

**在线模型列表**（`opencode models` 执行结果）：

```
deepseek/deepseek-chat
deepseek/deepseek-reasoner
deepseek/deepseek-v4-flash
deepseek/deepseek-v4-pro
kimi-for-coding/k2p5
kimi-for-coding/k2p6
kimi-for-coding/k2p7
kimi-for-coding/kimi-k2-thinking
zhipuai-coding-plan/glm-4.5-air
zhipuai-coding-plan/glm-4.6v
zhipuai-coding-plan/glm-4.7
zhipuai-coding-plan/glm-5-turbo
zhipuai-coding-plan/glm-5.1
zhipuai-coding-plan/glm-5.2
zhipuai-coding-plan/glm-5v-turbo
```

配置中引用的所有模型均在线可用。

### 1.3 用户 Provider/模型能力矩阵

以下基于用户提供的信息整理（未经独立 benchmark 验证，作为配置合理性分析的输入）：

| Provider | 模型 | 逻辑推理 | 编程 | 多模态 | 1M上下文 | 并发度 | 费用 |
|---|---|---|---|---|---|---|---|
| zhipuai-coding-plan | glm-5.2 | 1（最强） | 1 | 否 | 是 | 3-5（低） | 免费（订阅内） |
| zhipuai-coding-plan | glm-5-turbo | 5 | 5 | 否 | 否 | 3-5（共享） | 免费 |
| zhipuai-coding-plan | glm-4.6v | — | — | 是 | 否 | 3-5（共享） | 免费 |
| kimi-for-coding | k2p7 | 3-4 | 3 | 是 | 否 | ~30 | 免费（订阅内） |
| deepseek | deepseek-v4-pro | 2 | 2 | 否 | 是 | ~500 | 付费 |
| deepseek | deepseek-v4-flash | 4-5 | 4 | 否 | 是 | ~500 | 付费（较低） |

Provider 额度特点（用户判断）：zhipuai-coding-plan 额度略高于 kimi-for-coding；两者均不超限时免费；deepseek 按量付费。

---

## 2. opencode.jsonc 逐项检视

### 2.1 `$schema`

```jsonc
"$schema": "https://opencode.ai/config.json"
```

正确。指向 opencode 官方配置 Schema。

### 2.2 `autoupdate`

```jsonc
"autoupdate": "notify"
```

正确。合法值为 `true` / `false` / `"notify"`。`"notify"` 在有新版本时仅通知不自动更新。

### 2.3 `plugin`

```jsonc
"plugin": ["oh-my-openagent@4.15.1"]
```

正确。固定版本号利于可复现性。此处的 plugin 声明通过 `kind: "server"` 加载 oh-my-openagent 的服务端入口点（`./server` → `dist/index.js`），提供事件监听、模型解析、agent 行为控制等核心功能。

### 2.4 `disabled_providers`

```jsonc
"disabled_providers": ["opencode", "huggingface", "ollama-cloud"]
```

正确。禁用三个不使用的内置 provider。注：HuggingFace 虽有环境变量 `HF_TOKEN` 但已被禁用，不影响。

### 2.5 `provider`

```jsonc
"provider": {
  "zhipuai-coding-plan": {
    "options": {
      "apiKey": "{file:./.secrets/ZHIPU_AI_CODING_PLAN_API_KEY}"
    }
  }
}
```

正确。zhipuai-coding-plan 需要手动声明 provider 块（含 apiKey）。kimi-for-coding 和 deepseek 为 opencode 内置 provider，通过 `opencode auth` 命令认证（已确认），无需在此声明。

### 2.6 `model`

```jsonc
"model": "zhipuai-coding-plan/glm-5.2"
```

正确。与 oh-my-openagent.jsonc 中的 thinking-ON agent/category 一致，使用最新版本。[已从 glm-5.1 修改为 glm-5.2]

### 2.7 `small_model`

```jsonc
"small_model": "kimi-for-coding/k2p7"
```

用户决定保留。k2p7 虽然对标题生成等轻量任务属于过度配置，但调用频率极低（每会话约 1 次），额度消耗微乎其微。

### 2.8 `mcp`

```jsonc
"mcp": {
  "zai-mcp-server": { "type": "local", ... },
  "web-search-prime": { "type": "remote", ... },
  "web-reader": { "type": "remote", ... },
  "zread": { "type": "remote", ... }
}
```

正确。四个 MCP 服务器均来自 ZhipuAI 生态：
- `zai-mcp-server`：本地服务器，`Z_AI_MODE: "ZHIPU"` + `{file:...}` API Key
- `web-search-prime` / `web-reader` / `zread`：远程服务器，`Authorization` Header + Bearer Token
- 所有密钥引用路径一致，使用不同的密钥文件（API_KEY vs BEARER_API_KEY），符合 ZhipuAI 的双密钥体系

### 2.9 缺失配置项审视

基于 opencode v1 官方 schema（`https://opencode.ai/config.json`，`additionalProperties: false`），opencode.jsonc 支持 35 个顶层配置项。当前文件使用了其中 8 个（`$schema`、`autoupdate`、`plugin`、`disabled_providers`、`provider`、`model`、`small_model`、`mcp`），未使用的相关项审视如下：

| schema 可选字段 | 是否需要添加 | 理由 |
|---|---|---|
| `enabled_providers` | 不需要 | schema 描述为"设置后仅启用这些 provider，禁用所有其他"。当前用黑名单模式（`disabled_providers`）即可，provider 数量少，不需要白名单 |
| `permission` | 不需要 | opencode 内置默认权限规则已覆盖常见场景；oh-my-openagent 会进一步管理 agent 级权限 |
| `instructions` | 不需要 | 用于添加额外指令文件。当前无此需求 |
| `default_agent` | 不需要 | 未设置时 oh-my-openagent 默认注册 sisyphus 为默认 agent |
| `experimental` | 不需要 | 无实验特性需求 |
| `command` | 不需要 | 无自定义命令需求 |

> **纠正**：`telemetry`、`theme`、`keybinds` **不是** opencode.jsonc 的 schema 字段（`additionalProperties: false` 意味着未定义的字段会被拒绝）。`telemetry` 是 oh-my-openagent.jsonc 的字段；`theme` 和 `keybinds` 是 tui.json 的字段。此前版本报告中将这些列为 opencode.jsonc 的"可选添加项"是错误的。

---

## 3. oh-my-openagent.jsonc 逐项检视

### 3.1 顶层配置项

| 配置项 | 当前值 | 评估 |
|---|---|---|
| `$schema` | oh-my-openagent schema URL | 正确 |
| `auto_update` | `false` | 合理——手动控制插件更新 |
| `experimental` | `{}` | 空对象，无实验特性启用 |
| `hashline_edit` | `true` | 正确——启用 hashline 编辑模式 |
| `model_fallback` | `true` | 正确——启用全局模型回退 |

### 3.2 `git_master`

```jsonc
"git_master": {
  "git_env_prefix": "GIT_MASTER=1",
  "commit_footer": true,
  "include_co_authored_by": true
}
```

正确。三个字段均在 Schema 中定义，配置合理。

### 3.3 `codegraph`

```jsonc
"codegraph": {
  "enabled": true,
  "auto_init": false,
  "auto_provision": false,
  "telemetry": false
}
```

合理。`auto_init: false` 表示新项目需手动运行 `codegraph init`。若常在新项目中使用可改为 `true`。`telemetry: false` 关闭遥测，正确。

### 3.4 `team_mode`

```jsonc
"team_mode": {
  "enabled": true,
  "max_parallel_members": 4,
  "max_members": 8,
  "tmux_visualization": true,
  "max_member_turns": 1000,
  "max_messages_per_run": 20000,
  "max_wall_clock_minutes": 240,
  "message_payload_max_bytes": 65536,
  "recipient_unread_max_bytes": 262144,
  "mailbox_poll_interval_ms": 3000
}
```

基本合理。一个关注点：

`max_parallel_members: 4` 的并发风险：Team Mode 是唯一能产生真正并行 glm-5.2 请求的场景。若 4 个并行成员全部路由到 thinking-ON category（使用 glm-5.2），加上 sisyphus 协调者可能同时活跃，峰值并发 glm-5.2 请求 = 4-5，触及 zhipuai 3-5 并发上限。

用户决定保留 4。若 team_mode 使用频率较高且常分配 thinking-ON category，可留意是否触发限流。

### 3.5 `tmux`

```jsonc
"tmux": {
  "enabled": true,
  "layout": "main-vertical",
  "isolation": "inline",
  "main_pane_size": 60,
  "main_pane_min_width": 120,
  "agent_pane_min_width": 40
}
```

正确。布局和尺寸参数合理。

### 3.6 `runtime_fallback`

```jsonc
"runtime_fallback": {
  "enabled": true,
  "max_fallback_attempts": 6,
  "cooldown_seconds": 120,
  "restore_primary_after_cooldown": true
}
```

配置完善。6 次回退尝试对 2-3 级 fallback 链绰绰有余；120 秒冷却期合理；冷却后恢复主模型确保 fallback 是临时措施。

### 3.7 `agents` — 逐 Agent 检视

#### 模型与 fallback 配置总览

| Agent | 主模型 | Thinking | Variant | reasoningEffort | Fallback 链 |
|---|---|---|---|---|---|
| sisyphus | glm-5.2 | enabled | max | max | deepseek-v4-pro → k2p7 |
| hephaestus | glm-5.2 | enabled | max | max | deepseek-v4-pro → k2p7 |
| prometheus | glm-5.2 | enabled | max | max | deepseek-v4-pro → k2p7 |
| oracle | glm-5.2 | enabled | max | max | deepseek-v4-pro → k2p7 |
| metis | glm-5.2 | enabled | max | max | deepseek-v4-pro → k2p7 |
| momus | deepseek-v4-pro | enabled | max | max | glm-5.2 → k2p7 |
| librarian | k2p7 | disabled | — | none | glm-5-turbo → deepseek-v4-flash |
| explore | k2p7 | disabled | — | none | glm-5-turbo → deepseek-v4-flash |
| multimodal-looker | k2p7 | enabled (budgetTokens=16384) | max | max | glm-4.6v |
| atlas | k2p7 | disabled | — | none | glm-5-turbo → deepseek-v4-flash |
| sisyphus-junior | k2p7 | disabled | — | none | glm-5-turbo → deepseek-v4-flash |

#### 各 Agent 设计意图与匹配度

**sisyphus（主编排器）** — 合理
- glm-5.2 + thinking=ON：编排需要最强推理 + 深度意图解析
- 频率极高（每次交互），但由于同步阻塞式委托不会与其他 glm-5.2 agent 并发

**hephaestus（深度自主执行）** — 合理
- `allow_non_gpt_model: true` 设置正确（此字段仅在 hephaestus 的 Schema 中允许）
- glm-5.2 + 1M 上下文：长程自主任务需要最强推理 + 最长上下文

**prometheus / oracle / metis** — 合理
- glm-5.2 + thinking=ON：规划/审查/分析需要深度推理
- 均为串行管线组件，不并发

**momus（计划评审）** — 可讨论
- 主模型 deepseek-v4-pro（付费）：设计意图是与规划者 glm-5.2 使用不同模型族，避免认知偏见
- 若评审频率低可接受；若高可改为 k2p7 主（同样与 glm-5.2 不同族，且免费）

**librarian / explore（检索类）** — 合理
- k2p7 + thinking=OFF：速度优先，高频并行
- kimi 的高并发能力（约 30）完美匹配 explore 的 3-5 并发需求

**multimodal-looker（多媒体分析）** — 合理
- k2p7 主（多模态能力）+ glm-4.6v fallback（多模态备选）：两个多模态模型可用
- thinking=ON：内容理解需要推理
- 注：glm-4.6v 已通过 `opencode models` 确认在线可用

**atlas / sisyphus-junior（执行类）** — 合理
- k2p7 + thinking=OFF：执行/工作者任务速度优先
- sisyphus-junior 频率最高（所有 category 任务的执行者），kimi 高并发匹配

### 3.8 `categories` — 逐 Category 检视

#### 模型与 fallback 配置总览

| Category | 主模型 | Thinking | Variant | reasoningEffort | Fallback 链 |
|---|---|---|---|---|---|
| visual-engineering | glm-5.2 | enabled | max | max | k2p7 → deepseek-v4-pro |
| ultrabrain | glm-5.2 | enabled | max | max | deepseek-v4-pro → k2p7 |
| deep | glm-5.2 | enabled | max | max | deepseek-v4-pro → k2p7 |
| artistry | k2p7 | enabled (budgetTokens=16384) | max | max | glm-5.2 → deepseek-v4-pro |
| quick | glm-5-turbo | disabled | — | none | k2p7 → deepseek-v4-flash |
| unspecified-low | k2p7 | disabled | — | none | glm-5-turbo → deepseek-v4-flash |
| unspecified-high | glm-5.2 | enabled | max | max | deepseek-v4-pro → k2p7 |
| writing | glm-5.2 | disabled | — | none | deepseek-v4-pro → k2p7 |

#### 各 Category 分析

**visual-engineering（前端 UI/UX）** — 合理
- glm-5.2 主模型：社区反馈 glm-5.2 前端能力优于 k2p7
- fallback k2p7 → deepseek-v4-pro：k2p7 也有前端能力，deepseek 兜底

**ultrabrain（硬核逻辑）** — 合理
- glm-5.2 主模型：综合逻辑推理最强
- thinking=ON + variant=max：硬核逻辑必须最大深度思考

**deep（深度自主）** — 合理
- glm-5.2 + 1M 上下文：自主问题解决需要深度推理 + 长上下文

**artistry（创意求解）** — 可讨论
- 主模型 k2p7，fallback 到 glm-5.2
- 若 artistry 任务涉及硬逻辑（非常规算法设计），glm-5.2 主更优
- 若偏向发散性创意，k2p7 可提供差异化视角
- 当前配置将更强模型放在 fallback 位——属偏好选择

**quick（快速小任务）** — 合理
- glm-5-turbo 主模型：单文件改动/typo 修复不需要强推理
- fallback k2p7 → deepseek-v4-flash：免费优先

**unspecified-low（低复杂度通用）** — 合理
- k2p7 主模型：低复杂度任务不需要最强模型，kimi 高并发匹配

**unspecified-high（高复杂度通用）** — 合理
- glm-5.2 主模型：高复杂度需要最强推理

**writing（文档写作）** — 可讨论
- glm-5.2 + thinking=OFF：配置注释称"写作是生成任务，不是推理任务"
- 分析详见 [§5.4](#54-thinking-off-各模型实际效果)

### 3.9 缺失配置项审视

| 缺失项 | 是否需要添加 | 理由 |
|---|---|---|
| `telemetry` | 已添加 `"telemetry": false` | 关闭 oh-my-openagent 遥测 [已修改] |
| `default_run_agent` | 不需要 | 未设置时默认为 sisyphus（oh-my-openagent 内置行为） |

---

## 4. tui.json 逐项检视

### 当前内容

```json
{
    "plugin": ["oh-my-openagent@4.15.1"]
}
```

### 结论：必须保留，不可删除

tui.json 和 opencode.jsonc 中的 plugin 声明加载**不同的入口点**，功能完全不同：

**oh-my-openagent 的 package.json 有两个入口点**：
- `./server` → `./dist/index.js`（服务端入口：事件监听、模型解析、agent 行为控制）
- `./tui` → `./dist/tui.js`（TUI 入口：侧边栏显示、prompt 输入框渲染）

**opencode 的插件加载机制根据 `PluginKind` 加载不同入口点**：
- opencode.jsonc 的 plugin → 通过 `plugin/index.ts` 以 `kind: "server"` 加载 → 执行 `./server` 入口
- tui.json 的 plugin → 通过 `plugin/tui/runtime.ts` 以 `kind: "tui"` 加载 → 执行 `./tui` 入口

**oh-my-openagent 服务端插件甚至主动自愈 tui.json**（`create-plugin-module.ts`）：如果 tui.json 中缺少 plugin 声明，oh-my-openagent 会自动写入以确保 TUI 功能正常。

如果删除 tui.json 中的 plugin 声明，oh-my-openagent 的侧边栏显示和 prompt 输入框等 TUI 功能将无法加载。

---

## 5. thinking / variant / reasoningEffort 深度分析

> 本节是整份报告最核心的部分。所有结论均通过源码逐行追踪 + bun 运行时兼容层测试双重验证。

### 5.1 参数流全链路

```
用户 oh-my-openagent.jsonc 配置
  ↓ applyOverrides() → deepMerge()（agent-overrides.ts）
AgentConfig（thinking / variant / reasoningEffort 字段）
  ↓ opencode session/llm/request.ts L80-91
  ├── variant → model.variants[variant] 查询（transform.ts 变体映射）
  │   → 合并到 options（如 reasoningEffort: "max"）
  ├── base → ProviderTransform.options()（transform.ts）
  │   → 包含模型特定的默认参数
  └── options（合并 base + model.options + agent.options + variant_body）
       ↓ request.ts L114 → plugin.trigger("chat.params", ...)
       ↓ oh-my-openagent chat-params.ts hook（运行时执行！）
       ├── applyAgentVariant() → 设置 message.variant（从 agent 配置）
       ├── getSessionPromptParams() → 读取此前注入的 thinking/reasoningEffort（子agent场景）
       │   （注：参数由 delegate-task/background-agent 等在委派阶段通过
       │    applySessionPromptParams() 写入，非在 hook 内写入）
       └── resolveCompatibleModelSettings() 兼容层处理
            ↓ 修改后的 options → 最终 API 请求体
```

### 5.2 opencode transform.ts 关键行为

#### 5.2.1 变体映射（variants() 函数）

**GLM-5.2（@ai-sdk/openai-compatible）**：transform.ts L698-702
```typescript
return {
  high: { reasoningEffort: "high" },
  max:  { reasoningEffort: "max" },
}
```
→ variant "max" 映射为 `{reasoningEffort: "max"}`，合并到 options 中。

**k2p7（@ai-sdk/anthropic）**：transform.ts L710-722
```typescript
if (id.includes("kimi") || id.includes("k2p") || ...) return {}
```
→ 变体目录为空 `{}`。variant 查询结果为 undefined，无效果。

**deepseek-v4-pro/flash（@ai-sdk/openai-compatible）**：transform.ts L863-871
```typescript
const efforts = [...WIDELY_SUPPORTED_EFFORTS]  // ["low", "medium", "high"]
if (model.api.id.toLowerCase().includes("deepseek-v4")) {
  efforts.push("max")
}
return Object.fromEntries(efforts.map(e => [e, { reasoningEffort: e }]))
```
→ variant "max" 映射为 `{reasoningEffort: "max"}`。

**glm-5-turbo / glm-4.6v（非 glm-5.2 的 GLM 模型）**：transform.ts L716
```typescript
if (id.includes("glm") && !glm52) return {}
```
→ 变体目录为空，variant 无效果。

#### 5.2.2 默认 options（options() 函数）

**zhipuai 模型（含 glm-5.2、glm-5-turbo、glm-4.6v）**：transform.ts L1120-1128
```typescript
if (["zai", "zhipuai"].some(id => input.model.providerID.includes(id)) &&
    input.model.api.npm === "@ai-sdk/openai-compatible") {
  result["thinking"] = { type: "enabled", clear_thinking: false }
}
```
→ 所有 zhipuai-coding-plan 模型的 base options **始终包含** `thinking: {type: "enabled", clear_thinking: false}`。

**k2p7（@ai-sdk/anthropic）**：transform.ts L1152-1161
```typescript
if (modelId.includes("k2p") || ...) {
  result["thinking"] = {
    type: "enabled",
    budgetTokens: Math.min(16_000, Math.floor(model.limit.output / 2 - 1)),
  }
}
```
→ k2p7 的 base options **始终包含** `thinking: {type: "enabled", budgetTokens: ~16000}`。

### 5.3 oh-my-openagent 兼容层运行时测试结果

通过 bun 直接执行 `resolveCompatibleModelSettings()` 的结果（实际运行，非推断）。

> **注意**：此测试是对兼容层函数的独立隔离测试，输入参数为合成的 `{variant:"max", reasoningEffort:"max", thinking:{type:"enabled"}}`。在实际运行流程中，各模型的 thinking 参数来源不同（见 §5.2.2）：zhipuai 和 k2p7 由 transform.ts base options 注入 thinking；deepseek 的 base options **不**包含 thinking。此差异在 §5.4 的实际结论中体现。

#### Thinking-ON 配置（variant=max, reasoningEffort=max, thinking={type:enabled}）

| 模型 | variant 结果 | reasoningEffort 结果 | thinking 结果 | 变更说明 |
|---|---|---|---|---|
| glm-5.2 | max→**high**（降级） | max→**undefined**（strip） | **{type:enabled}**（保留） | variant 降级 + reasoningEffort strip |
| k2p7 | max→**high**（降级） | max→**undefined**（strip） | **{type:enabled}**（保留） | variant 降级 + reasoningEffort strip |
| deepseek-v4-pro | **max**（保留） | **max**（保留） | **{type:enabled}**（保留） | 无变更 |
| deepseek-v4-flash | **max**（保留） | **max**（保留） | **{type:enabled}**（保留） | 无变更 |
| glm-5-turbo | max→**high**（降级） | max→**undefined**（strip） | **{type:enabled}**（保留） | 同 glm-5.2 |
| glm-4.6v | max→**high**（降级） | max→**undefined**（strip） | **{type:enabled}**（保留） | 同 glm-5.2 |

#### Thinking-OFF 配置（reasoningEffort=none, thinking={type:disabled}）

| 模型 | reasoningEffort 结果 | thinking 结果 | 变更说明 |
|---|---|---|---|
| glm-5.2 | none→**undefined**（strip） | **{type:disabled}**（保留） | reasoningEffort strip |
| k2p7 | none→**undefined**（strip） | **{type:disabled}**（保留） | reasoningEffort strip |
| deepseek-v4-pro | none→**undefined**（strip） | **{type:disabled}**（保留） | "none"不在deepseek支持的["high","max"]中，降级失败→strip |
| deepseek-v4-flash | none→**undefined**（strip） | **{type:disabled}**（保留） | 同上 |
| glm-5-turbo | none→**undefined**（strip） | **{type:disabled}**（保留） | reasoningEffort strip |
| glm-4.6v | none→**undefined**（strip） | **{type:disabled}**（保留） | reasoningEffort strip |

### 5.4 各模型推理控制最终结论

#### 根因分析

兼容层 strip reasoningEffort 的根因在于 `model-capability-heuristics.ts` 中各模型族的定义：

| 模型族 | variants | reasoningEfforts | supportsThinking |
|---|---|---|---|
| glm | ["low","medium","high"] | **未定义** | 未定义 |
| kimi-thinking | ["low","medium","high"] | **未定义** | true |
| deepseek | ["low","medium","high","max"] | ["high","max"] | 未定义 |

- GLM 族和 kimi-thinking 族**未定义 reasoningEfforts** → resolveField() 走到 `familyKnown` 分支 → 返回 undefined → **reasoningEffort 被 strip**
- GLM 族和 kimi-thinking 族 variants 最高到 "high" → "max" 被降级为 "high"
- deepseek 族定义了 reasoningEfforts: ["high","max"] → "max" 被保留

#### GLM-5.2（zhipuai-coding-plan，thinking-ON agent 主模型）

参数到达 API 的实际状态：

1. `thinking: {type: "enabled", clear_thinking: false}` — 来自 transform.ts base options（L1120-1128），通过 AI SDK pass-through 机制到达 API 请求体 ✓
2. `reasoning_effort: "max"` — 来自 variant "max" 映射，但被 chat.params hook strip ✗

最终效果：GLM-5.2 收到 `thinking: {type: "enabled", clear_thinking: false}`，推理功能开启。但**不收到** `reasoning_effort` 参数，推理深度由 GLM 服务端默认行为决定（推测默认为 "high" 级别，具体取决于 GLM API 实现，未从官方文档独立验证）。

**结论：thinking 功能正常开启，但用户配置的最高推理深度（max）未生效。**

#### k2p7（kimi-for-coding，thinking-ON agent 主模型）

1. `thinking: {type: "enabled", budgetTokens: ~16000}` — 来自 transform.ts base options（L1152-1161），通过 Anthropic 协议原生发送 ✓
2. variant/reasoningEffort — 无效果（transform.ts 变体目录为空 + 兼容层 strip）

注意：当子 agent 被委派时，`applySessionPromptParams` 会用 oh-my-openagent.jsonc 中的 thinking 配置覆盖 base options 中的 thinking。如果用户配置为 `{type: "enabled"}`（不带 budgetTokens），则 base options 中的 budgetTokens=16000 会被覆盖丢失。

**结论：thinking 功能正常开启。可通过在配置中显式设置 budgetTokens 进一步控制推理深度。**

#### deepseek-v4-pro/flash（deepseek，thinking-ON fallback）

1. `reasoning_effort: "max"` — 来自 variant "max" 映射，兼容层保留，通过 OpenAI Chat 协议发送 ✓
2. thinking — OpenAI Chat 协议 body 无此字段，不发送（deepseek 通过 reasoning_effort 控制推理，不需要 thinking 参数）

**结论：推理控制完全正常。reasoning_effort: "max" 成功到达 API。**

#### thinking-OFF 各模型实际效果

| 模型 | thinking.type: "disabled" | 实际推理关闭？ | 原因 |
|---|---|---|---|
| k2p7（主模型） | 通过 Anthropic 协议发送 ✓ | **是** ✓ | thinking.type 通过 Anthropic 协议原生生效 |
| glm-5-turbo（quick 主模型） | 通过 pass-through 发送 | 取决于API | 发送 `thinking:{type:"disabled"}` 到 API，GLM API 是否尊重此参数取决于服务端实现 |
| glm-5.2（writing 主模型） | 同上 | 取决于API | 同上 |
| deepseek-v4-flash（fallback） | OpenAI body 无此字段→不发送 | **否** | 无法通过参数控制；deepseek-v4-flash 标记为 reasoning: true |

对于子 agent 场景（通过委派执行），`applySessionPromptParams` 会将 oh-my-openagent 配置中的 `thinking: {type: "disabled"}` 注入到 chat.params hook 的 output.options 中，覆盖 base options 中的默认 `thinking: {type: "enabled"}`。

> **路径依赖说明**：k2p7 thinking-OFF 的可靠关闭仅在**委派路径**（子 agent 场景）下成立。当前 librarian/explore/atlas/sisyphus-junior 均为子 agent，始终通过委派执行，因此 thinking-OFF 可靠生效。若未来这些 agent 被直接用作主 agent（不经过委派），transform.ts base options 会强制注入 `thinking:{type:"enabled"}`，覆盖用户的 disabled 配置——与 §5.4 中 GLM-5.2 主 agent 的问题同构。

### 5.5 能否让各模型按预期控制推理？

#### 问题 1：GLM-5.2 如何让 reasoning_effort: "max" 生效？

**根因**：oh-my-openagent 的 `model-capability-heuristics.ts` 中 GLM 族未定义 `reasoningEfforts`。chat.params hook 在运行时 strip 了 reasoningEffort。

**可行的 workaround**：本地 patch oh-my-openagent 的 `model-capability-heuristics.ts`，为 GLM 族添加 reasoningEfforts。这正是 GitHub PR #5672 做的变更：

```typescript
// 原始
{
  family: "glm",
  includes: ["glm"],
  variants: ["low", "medium", "high"],
}
// 修改为
{
  family: "glm",
  includes: ["glm"],
  variants: ["low", "medium", "high", "max"],
  reasoningEfforts: ["high", "max"],
  reasoningEffortAliases: {
    low: "high",
    medium: "high",
    xhigh: "max",
  },
}
```

patch 后的参数流：hook 不再 strip reasoningEffort → AI SDK 的 `compatibleOptions.reasoningEffort = "max"` → L600 赋值 `reasoning_effort: "max"` → API 收到正确的参数。

实施方式：`bun patch @oh-my-openagent/model-core`（或直接编辑本地安装副本）。此 patch 不受 opencode 更新影响，但 oh-my-openagent 插件更新时需重新应用。

**不可行的方案**（已排除）：在 opencode provider config 中定义自定义 variant 写入 snake_case `reasoning_effort`。经完整源码追踪确认不可行——AI SDK `@ai-sdk/openai-compatible` 的 `getArgs()` 有显式覆盖行将 `reasoning_effort` 设为 undefined。

**官方修复状态**：
- oh-my-openagent PR #5672：Open，CI 全绿且 mergeable，但无维护者 review（445 个 open PR 积压）
- opencode PR #34283：Open，修改 transform.ts 的 GLM-5.2 variant "max" 为 "xhigh"
- 两个 PR 需同时合入才能完全解决

#### 问题 2：k2p7 如何最大化推理深度？

k2p7 的 thinking 已通过 Anthropic 协议正常工作。可通过添加 budgetTokens 进一步提升：

k2p7 output limit = 32768 tokens。opencode transform.ts 默认设置 budgetTokens = min(16000, output/2-1) = 16000。用户可在 oh-my-openagent 配置中显式覆盖：

```jsonc
// 为 k2p7 thinking-ON 的 agent/category
"thinking": {
  "type": "enabled",
  "budgetTokens": 24000  // 留出 ~8000 tokens 给实际输出
}
```

建议范围：16000-24000。不建议超过 28000（仅留 ~4000 tokens 输出，复杂答案可能被截断）。

#### 问题 3：thinking-OFF 对 glm/deepseek 能否关闭推理？

- k2p7：thinking.type: "disabled" 可靠关闭 ✓
- glm-5-turbo / glm-5.2：通过 pass-through 发送 `thinking:{type:"disabled"}`，但 GLM API 是否尊重此参数取决于服务端实现（无法从源码确认）
- deepseek-v4-flash：无法关闭推理。OpenAI 协议层不发送 thinking 参数，reasoningEffort "none" 被兼容层 strip（deepseek 仅支持 high/max）

实际影响评估：额外推理消耗在免费额度内（zhipuai）或可接受范围内（deepseek-flash 费用极低）。thinking-OFF agent 的主模型是 k2p7（推理已可靠关闭），glm/deepseek 仅在 fallback 时触发。

---

## 6. Agent/Category 模型分配与并发分析

### 6.1 Provider 并发约束

| Provider | 估计并发度 | 费用模式 |
|---|---|---|
| zhipuai-coding-plan | 3-5（低，共享） | 免费（订阅内） |
| kimi-for-coding | ~30 | 免费（订阅内） |
| deepseek | ~500 | 付费 |

### 6.2 工作流串/并行关系

oh-my-openagent 的编排器（Sisyphus）采用同步阻塞式委托——委派子任务时编排器自身暂停，等待子任务返回。

| 组合 | 能否并发？ | 原因 |
|---|---|---|
| sisyphus 与任何 category | 否 | 同步委派，sisyphus 阻塞 |
| sisyphus 与 oracle | 否 | Oracle 是阻塞性后台 |
| 任意两个 category（单会话） | 否 | 一次委派一个，串行执行 |
| metis/prometheus/momus 之间 | 否 | 规划管线严格串行 |
| Team Mode 多个成员 | **是** | 并行执行，唯一并发场景 |

### 6.3 典型工作流的并发推演

| 场景 | 频率估计 | 峰值 glm-5.2 | vs 3-5 限制 | 峰值 k2p7 | vs ~30 限制 |
|---|---|---|---|---|---|
| 日常代码任务 | ~70% | 1 | 安全 | 2-3 | 安全 |
| Oracle 顾问 | ~15% | 1 | 安全 | 0-3 | 安全 |
| 规划管线 | ~5% | 1 | 安全 | 0 | 安全 |
| Hephaestus 后台 | ~3% | 2 | 安全 | 2-3 | 安全 |
| Team Mode（混合 category） | ~3% | 2-3 | 安全 | 0-8 | 安全 |
| Team Mode（全 thinking-ON） | ~2% | **4-5** | **边缘** | 0 | 安全 |

### 6.4 模型分配合理性总结

**thinking-ON agent/category（使用 glm-5.2）**：
- sisyphus / hephaestus / prometheus / oracle / metis / visual-engineering / ultrabrain / deep / unspecified-high 均使用 glm-5.2 主模型 → 合理（最强推理+最长上下文）
- momus 使用 deepseek-v4-pro → 合理（多样性设计，避免与规划者同族偏见）
- multimodal-looker / artistry 使用 k2p7 → 合理（多模态需求 / 差异化视角）
- 所有 thinking-ON agent/category 的 fallback 链均包含 deepseek-v4-pro → 合理（推理能力排名第二，高并发）

**thinking-OFF agent/category（使用 k2p7 或 glm-5-turbo）**：
- librarian / explore / atlas / sisyphus-junior / unspecified-low 使用 k2p7 → 合理（高并发匹配高频任务）
- quick 使用 glm-5-turbo → 合理（快速、免费、轻量任务）
- writing 使用 glm-5.2 + thinking-OFF → 可讨论（glm-5.2 推理能力被闲置，但通过委派路径 thinking 可被覆盖为 disabled）

**并发匹配度**：
- 高频并行 agent（explore/librarian/sisyphus-junior）使用 k2p7（并发 ~30）→ 完美匹配
- 低频深度 agent（sisyphus/hephaestus/oracle）使用 glm-5.2（并发 3-5）→ 可接受（串行执行，仅 Team Mode 有风险）
- 三个 provider 的能力被充分利用：zhipuai 用于深度推理，kimi 用于高并发执行，deepseek 用于兜底和多视角

---

## 7. 问题汇总与改进建议（已反映用户最终决策）

> 以下汇总反映用户在 2026-07-05 审阅后做出的最终配置决策。标记 [已修改] 的项用户已实际更改了配置文件。

### 已完成的修改

| # | 文件 | 修改内容 | 状态 |
|---|---|---|---|
| 1 | opencode.jsonc | `model` 从 `glm-5.1` 改为 `glm-5.2` | [已修改] |
| 2 | oh-my-openagent.jsonc | 添加 `"telemetry": false` | [已修改] |
| 3 | oh-my-openagent.jsonc | multimodal-looker / artistry 的 thinking 添加 `"budgetTokens": 16384` | [已修改] |

### 用户决定保留现状的项

| # | 项 | 用户决策 | 理由 |
|---|---|---|---|
| 4 | small_model 保持 k2p7 | 保留不改 | 用户决定 |
| 5 | max_parallel_members 保持 4 | 保留不改 | 用户决定 |
| 6 | writing 使用 glm-5.2 | 保留不改 | writing 需要长上下文能力，k2p7 不具备 1M 上下文，不适合 |
| 7 | artistry 使用 k2p7 主模型 | 保留不改 | 需要设置一个与其他主模型不同的模型，确保能找到不一样的思路进行创意性思考和突破；使用频率相对较多 |
| 8 | momus 使用 deepseek-v4-pro | 保留不改 | momus 使用频率很低，deepseek-v4-pro 费用可控 |

### 仍需关注的发现

| # | 发现 | 详情 | 当前状态 |
|---|---|---|---|
| 9 | **GLM-5.2 reasoningEffort 被运行时 strip** | oh-my-openagent chat.params hook 将 GLM-5.2 的 reasoningEffort 从 options 中删除。用户配置的 `variant: "max"` 和 `reasoningEffort: "max"` 对 GLM-5.2 实际不生效。thinking 功能通过 transform.ts base options 正常开启，但推理深度为服务端默认而非用户期望的 "max"。 | **已通过本地 patch 修复**。patch 详情见 `~/.config/opencode/local-patches/glm-reasoning/`。PR #5672 合入后可移除 patch |
| 10 | **GLM-5.2 thinking 对主 agent 不可控** | transform.ts 对所有 zhipuai 模型始终设置 `thinking: {type: "enabled"}`。对于主 agent（不经过委派路径），oh-my-openagent 的 thinking 配置无法覆盖此默认值。当前所有 thinking-ON 主 agent 恰好需要 thinking 开启，因此无实际影响。 | 接受现状（当前配置不需要关闭主 agent 的 thinking） |
| 11 | **thinking-OFF 对 glm/deepseek 无法可靠关闭** | 仅 k2p7 能在委派路径下可靠关闭推理。glm/deepseek 模型的 thinking 参数在 OpenAI 协议层不被发送或服务端可能忽略。 | 接受现状（额外消耗在可接受范围内；thinking-OFF agent 主模型为 k2p7，推理已可靠关闭） |

### 不需要修改的已验证项

| 项 | 结论 |
|---|---|
| tui.json 的 plugin 声明 | **必须保留**——加载 TUI 入口点（./tui），与 opencode.jsonc 的 server 入口点功能完全不同 |
| kimi-for-coding 认证 | **已确认正常**——`opencode auth list` 显示已认证 |
| deepseek 认证 | **已确认正常**——`opencode auth list` 显示已认证 |
| zhipuai-coding-plan/glm-4.6v 可用性 | **已确认存在**——`opencode models` 列表中存在 |
| zhipuai-coding-plan/glm-5.2 可用性 | **已确认存在**——`opencode models` 列表中存在 |
| kimi-for-coding/k2p7 可用性 | **已确认存在**——`opencode models` 列表中存在 |
| deepseek/deepseek-v4-pro 可用性 | **已确认存在**——`opencode models` 列表中存在 |
| MCP 服务器配置 | **正确**——四个 ZhipuAI MCP 服务器配置合理，密钥引用正确 |

---

## 8. 附录：验证方法与关键源码引用

### 8.1 兼容层运行时测试

通过 bun 直接执行 oh-my-openagent 的 `resolveCompatibleModelSettings()` 函数，对 6 个模型分别测试 thinking-ON 和 thinking-OFF 配置，获得了确定性的参数处理结果。

### 8.2 实际命令验证

- `opencode auth list`：确认 kimi-for-coding 和 deepseek 认证状态正常
- `opencode models`：确认 glm-5.2、k2p7、glm-4.6v、deepseek-v4-pro 等模型在线可用

### 8.3 关键源码文件

| 文件 | 作用 | 关键行 |
|---|---|---|
| opencode `provider/transform.ts` | 变体映射 + 默认 options | L698-702（GLM-5.2 variant）、L710-722（k2p7 空 variant）、L863-871（deepseek-v4 variant）、L1120-1128（zhipuai thinking 默认）、L1152-1161（k2p7 thinking 默认） |
| opencode `session/llm/request.ts` | 请求构建管线 | L80-82（variant lookup）、L86-91（options 合并）、L114（chat.params hook 触发） |
| opencode `session/prompt.ts` | 用户消息创建 | L648-654（variant 解析——检查 variant 是否存在于 model.variants） |
| opencode `agent/agent.ts` | AgentConfig 类型 | L35-55（Info schema——注意：无 thinking/reasoningEffort 字段） |
| oh-my-openagent `model-capability-heuristics.ts` | 模型族启发式规则 | L75-79（glm 族：无 reasoningEfforts）、L58-66（kimi-thinking 族：supportsThinking=true）、L86-96（deepseek 族：reasoningEfforts=["high","max"]） |
| oh-my-openagent `model-settings-compatibility.ts` | 兼容层参数处理 | L51-52（VARIANT_LADDER / REASONING_LADDER）、L83-117（resolveField——strip 逻辑）、L119-217（resolveCompatibleModelSettings） |
| oh-my-openagent `plugin/chat-params.ts` | 运行时 chat.params hook | L91-110（storedPromptParams 应用）、L118-134（兼容层调用）、L145-149（reasoningEffort strip 执行）、L183-189（thinking 处理） |
| oh-my-openagent `shared/agent-variant.ts` | variant 解析与应用 | L92-101（applyAgentVariant——设置 message.variant） |
| oh-my-openagent `agents/builtin-agents/agent-overrides.ts` | agent 配置覆盖 | L38-56（mergeAgentConfig——deepMerge 用户配置） |
| oh-my-openagent `shared/session-prompt-params-helpers.ts` | 会话参数存储 | L11-31（applySessionPromptParams——子 agent thinking/reasoningEffort 注入） |

### 8.4 相关 GitHub Issue/PR

| 编号 | 标题 | 状态 | 与本配置的关系 |
|---|---|---|---|
| oh-my-openagent #5672 | fix(model-core): support GLM max reasoning effort | Open, CI 全绿 | 直接修复 GLM reasoningEffort strip 问题 |
| oh-my-openagent #5300 | Add GLM-5.2 "max" reasoning effort support | Open | #5672 修复的 issue |
| opencode #34283 | fix(provider): expose xhigh instead of max for GLM-5.2 | Open | 修改 transform.ts 的 variant 映射 |

### 8.5 opencode.jsonc 修改情况

```jsonc
// 修改 1（已完成）：model 版本一致性
"model": "zhipuai-coding-plan/glm-5.2",  // 原 glm-5.1，已修改

// 修改 2（用户决定保留）：small_model
"small_model": "kimi-for-coding/k2p7",  // 曾建议改为 glm-5-turbo，用户决定保留 k2p7
```

### 8.6 oh-my-openagent.jsonc 修改情况

```jsonc
// 修改 3（已完成）：为 k2p7 thinking-ON 的 agent/category 添加 budgetTokens

// multimodal-looker
"multimodal-looker": {
  "thinking": {
    "type": "enabled",
    "budgetTokens": 16384  // 已添加（原建议 24000，用户选择 16384）
  },
  // ... 其余不变
}

// artistry category
"artistry": {
  "thinking": {
    "type": "enabled",
    "budgetTokens": 16384  // 已添加（原建议 24000，用户选择 16384）
  },
  // ... 其余不变
}

// 修改 4（已完成）：添加 telemetry: false
"telemetry": false,
```

### 8.7 GLM-5.2 reasoningEffort 本地 patch（已实施）

具体的 patch 原理和参数流分析详见 [§5.5 问题 1](#问题-1glm-52-如何让-reasoning_effort-max-生效)。

本地 patch 已实施，完整的脚本、备份、验证工具和文档位于：

```
~/.config/opencode/local-patches/glm-reasoning/
├── apply-glm-reasoning-patch.sh     # patch 应用/检查/恢复脚本（自动检测版本号）
├── verify-patch.js                   # patch 验证脚本（11 项检查）
├── index.js.opencode-cache.4.15.1.original  # patch 前备份
├── index.js.bun-cache.4.15.1.original       # patch 前备份
├── glm-family-block-before.txt       # 原始 GLM 族代码块（参考）
├── glm-family-block-after.txt        # patch 后 GLM 族代码块（参考）
└── README.md                         # 完整文档（原理、操作、更新流程）
```

日常使用：
- 检查 patch 状态：`./apply-glm-reasoning-patch.sh --check`
- oh-my-openagent 更新后重新 patch：`./apply-glm-reasoning-patch.sh` + `bun run verify-patch.js`
- 恢复原始文件：`./apply-glm-reasoning-patch.sh --revert`
- PR #5672 合入后可删除整个 `local-patches/glm-reasoning/` 目录

---

*报告结束*
