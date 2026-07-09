# GLM Reasoning Patch — oh-my-openagent 本地补丁

## 1. 为什么要 patch

### 问题

oh-my-openagent 的 `model-capability-heuristics.ts` 中，GLM 模型族（`family: "glm"`）未定义 `reasoningEfforts` 字段。这导致 oh-my-openagent 的 `chat.params` 运行时 hook 在每次 LLM 请求时调用 `resolveCompatibleModelSettings()`，将 GLM 模型的 `reasoningEffort` 参数 strip 为 `undefined`。

**实际影响**：用户在 `oh-my-openagent.jsonc` 中为所有 thinking-ON agent/category 配置的 `"variant": "max"` 和 `"reasoningEffort": "max"` 对 GLM-5.2 不生效。虽然 opencode 的 `transform.ts` 为 GLM-5.2 生成了 `variant "max" → {reasoningEffort: "max"}` 的变体映射，但这个 `reasoningEffort: "max"` 随后被 oh-my-openagent 的兼容层 strip 掉。最终 GLM-5.2 API 收不到 `reasoning_effort` 参数，推理深度为服务端默认行为而非用户期望的最高级别。

### 参数流（patch 前）

```
用户配置 variant:"max"
  → transform.ts 映射为 {reasoningEffort:"max"} 合并到 options
  → chat.params hook 调用 resolveCompatibleModelSettings()
  → GLM 族无 reasoningEfforts 定义 → resolveField() 返回 undefined
  → delete output.options.reasoningEffort
  → AI SDK 不发送 reasoning_effort
  → API 收不到 reasoning_effort ✗
```

### 参数流（patch 后）

```
用户配置 variant:"max"
  → transform.ts 映射为 {reasoningEffort:"max"} 合并到 options
  → chat.params hook 调用 resolveCompatibleModelSettings()
  → GLM 族有 reasoningEfforts:["high","max"] → "max" 在支持列表中 → 保留
  → output.options.reasoningEffort = "max"
  → AI SDK 发送 reasoning_effort:"max"
  → API 收到 reasoning_effort:"max" ✓
```

## 2. Patch 原理

### 根因

文件 `model-capability-heuristics.ts`（打包到 dist/index.js 中）的 `HEURISTIC_MODEL_FAMILY_REGISTRY` 数组中，GLM 族定义如下：

```javascript
// 原始（有问题）
{
  family: "glm",
  includes: ["glm"],
  variants: ["low", "medium", "high"],  // 缺少 "max"
  // 缺少 reasoningEfforts → resolveField() 走 familyKnown 分支返回 undefined
}
```

`resolveField()` 的逻辑（model-settings-compatibility.ts L104-113）：
- 如果 `familyCaps` 存在（即定义了 `reasoningEfforts`）且请求值在列表中 → 保留原值
- 如果 `familyCaps` 存在但请求值不在列表中 → 降级查找
- 如果 `familyKnown=true` 但该字段未定义（`familyCaps=undefined`）→ 返回 `undefined`（strip）

### Patch 内容

为 GLM 族添加 `reasoningEfforts`、`max` variant 和别名映射，与 DeepSeek 族的定义方式一致：

```javascript
// patch 后
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

`reasoningEffortAliases` 的作用：当请求的 reasoningEffort 值不在 `reasoningEfforts` 列表中时，先查别名映射。例如 opencode 的 TUI variant selector 可能发送 "xhigh"，别名映射将其转换为 "max"。

### 参考信息

- oh-my-openagent PR #5672：https://github.com/code-yeongyu/oh-my-openagent/pull/5672 — 与本 patch 完全相同的修改，CI 全绿，待 review
- oh-my-openagent Issue #5300：https://github.com/code-yeongyu/oh-my-openagent/issues/5300 — 最初报告此问题
- DeepSeek 族定义（model-capability-heuristics.ts L86-96）：本 patch 的参照模板
- 审计报告：../../opencode-config-audit-report-final.md §5.5（仓库根目录）

## 3. 文件清单

| 文件 | 说明 |
|---|---|
| `apply-glm-reasoning-patch.sh` | Patch 应用/检查/恢复脚本 |
| `verify-patch.js` | Patch 验证脚本（bun run） |
| `index.js.opencode-cache.<版本>.original` | opencode 缓存中 dist/index.js 的 patch 前备份（文件名含版本号） |
| `index.js.bun-cache.<版本>.original` | bun 缓存中 dist/index.js 的 patch 前备份（文件名含版本号） |
| `glm-family-block-before.txt` | 原始 GLM 族代码块（参考） |
| `glm-family-block-after.txt` | patch 后 GLM 族代码块（参考） |
| `README.md` | 本文档 |

### 被 patch 的文件（2 个副本，路径自动检测）

脚本从 `opencode.jsonc` 的 `plugin` 字段自动提取当前 oh-my-openagent 版本号，定位以下文件：

| 路径模板 | 说明 |
|---|---|
| `~/.cache/opencode/packages/oh-my-openagent@<版本>/node_modules/oh-my-openagent/dist/index.js` | opencode 运行时加载的副本（主要，4 空格缩进） |
| `$BUN_INSTALL_CACHE_DIR/oh-my-openagent@<版本>@@*/dist/index.js`（默认 `~/.bun/install/cache/`） | bun 全局缓存中的副本 |

每个版本的备份文件独立存放（文件名含版本号，互不覆盖）：
- `index.js.opencode-cache.<版本>.original` — 对应版本的 opencode 缓存副本备份
- `index.js.bun-cache.<版本>.original` — 对应版本的 bun 缓存副本备份

> 版本号升级后，脚本会自动定位新版本的文件路径。首次 patch 新版本时会自动创建新备份。

> **⚠️ 不要扩展 patch 范围到其他 dist 文件**
>
> oh-my-openagent 的 `dist/` 目录中有多个 JS 文件包含相同的 `HEURISTIC_MODEL_FAMILY_REGISTRY`（如 `dist/cli/index.js`、`dist/cli-node/index.js`、`dist/tui.js`），但**只需 patch `dist/index.js`**。原因如下：
>
> - **`dist/index.js`（server 插件）**：opencode 运行时通过 `exports["./server"]` 定位此文件并 `await import()` 动态加载。它包含 `chat.params` hook 和 `resolveCompatibleModelSettings()`——正是 strip `reasoningEffort` 的代码路径。**这是唯一需要 patch 的文件。**
> - **`dist/tui.js`（TUI 插件）**：opencode 也会通过 `exports["./tui"]` 动态加载此文件，但它**不包含 `resolveCompatibleModelSettings()` 和 `chat.params` hook**（均为 0 处）——GLM 注册表副本是打包产物，在 TUI 渲染路径中永远不会被执行。
> - **`dist/cli/`、`dist/cli-node/`（standalone CLI）**：standalone `omo` CLI 运行时使用编译后的平台二进制（如 `oh-my-opencode-linux-x64-gnu`），不读取这些 JS 源文件。
> - 源码修复（PR #5672）合入后重建，所有 dist 文件会自动从源码重新生成——patch 只需覆盖重建前的过渡期。
>
> 参见 PR #5672（https://github.com/code-yeongyu/oh-my-openagent/pull/5672）也只修改源码 `model-capability-heuristics.ts` 一处。

## 4. oh-my-openagent 更新后如何判断是否需要重新 patch

### 判断流程

1. 更新 oh-my-openagent 后（修改 opencode.jsonc 中的版本号或运行 opencode 更新），执行：

```bash
cd ~/.config/opencode/local-patches/glm-reasoning
./apply-glm-reasoning-patch.sh --check
```

2. 如果输出 `ALREADY PATCHED` → 无需操作
3. 如果输出 `NOT PATCHED` → 需要重新 patch
4. 如果输出 `WARNING: Original GLM pattern not found` → dist 文件结构发生变化，需要手动检查

### 手动检查方法

```bash
# 检查 GLM 族是否已有 reasoningEfforts
grep -A5 'family: "glm",$' ~/.cache/opencode/packages/oh-my-openagent@*/node_modules/oh-my-openagent/dist/index.js | head -8
```

如果输出包含 `reasoningEfforts` → 官方已修复（PR #5672 合入），删除本 patch 目录即可。
如果输出只有 `variants: ["low", "medium", "high"]` → 仍需 patch。
> 注：dist `index.js` 中约 90 处含 `family: "glm"`（1 处 4 空格缩进的注册表条目 + ~89 处 6 空格缩进的模型目录元数据，二者后续行完全不同）。patch 脚本以精确 4 行块（`family` + `includes` + `variants` + `},`）匹配，只命中注册表那 1 处，不受目录条目干扰；python `content.count()` 守卫要求恰好等于 1，否则报错退出。

## 5. 重新 patch 操作

### 方法一：使用脚本（推荐）

更新 oh-my-openagent 版本号后（修改 `opencode.jsonc` 和 `tui.json` 中的 `plugin` 字段），执行：

```bash
cd ~/.config/opencode/local-patches/glm-reasoning

# 脚本会自动从 opencode.jsonc 提取新版本号，定位新文件路径
./apply-glm-reasoning-patch.sh

# 验证
bun run verify-patch.js
```

脚本会自动处理：
- 从 opencode.jsonc 提取新版本号（如 `4.16.0`）
- 定位 `~/.cache/opencode/packages/oh-my-openagent@<版本>/...` 和 bun 缓存
- 首次 patch 新版本时自动创建备份
- 如果官方已修复（GLM 族已有 reasoningEfforts），自动跳过并提示

### 方法二：手动 patch

如果 dist 文件结构发生变化（脚本无法自动匹配），需要手动定位并修改 GLM 族定义：

```bash
# 1. 定位 GLM 族定义
grep -n 'family: "glm",$' dist/index.js
# 找到 HEURISTIC_MODEL_FAMILY_REGISTRY 中的条目（通常在 minimax 族之前）

# 2. 手动编辑，将：
#     family: "glm",
#     includes: ["glm"],
#     variants: ["low", "medium", "high"]
# 改为：
#     family: "glm",
#     includes: ["glm"],
#     variants: ["low", "medium", "high", "max"],
#     reasoningEfforts: ["high", "max"],
#     reasoningEffortAliases: {
#       low: "high",
#       medium: "high",
#       xhigh: "max",
#     },
```

### 恢复原始文件

```bash
./apply-glm-reasoning-patch.sh --revert
```

## 6. 测试验证

Patch 后执行验证：

```bash
cd ~/.config/opencode/local-patches/glm-reasoning
bun run verify-patch.js
```

预期输出：11 项全部 ✓ 通过。

在实际 opencode 会话中验证：启动 opencode，向 sisyphus agent 发送一个需要推理的问题，观察 GLM-5.2 的响应中是否包含更深度的推理内容（reasoning 部分更长或更详细）。可通过 opencode 的 debug 模式或网络抓包确认 API 请求体中是否包含 `reasoning_effort: "max"`。

## 7. 适用版本

- 创建时 oh-my-openagent 版本: 4.15.1 (2026-07-05)
- 已验证适用版本: 4.15.1, 4.16.0, 4.16.1
- 最近复核: 2026-07-10 — 4.16.1 源码 `model-capability-heuristics.ts` GLM 族（L75-79）仍缺 `reasoningEfforts`/`max`/`aliases`；dist `index.js` OLD_CODE 唯一匹配（L21468-21471）；opencode `transform.ts`（L698-703）仍为 GLM-5.2 发出 `reasoningEffort:"max"`；strip 根因 `resolveField`（L112-113）未变。dist 于 2026-07-10 01:09 被重新安装（patch 被覆盖），已重新应用并验证（11/11 ✓）
- 脚本自动适配当前版本（从 opencode.jsonc 提取），无需手动修改版本号
- 备份文件名含版本号（如 `index.js.opencode-cache.4.15.1.original`、`index.js.opencode-cache.4.16.0.original`、`index.js.opencode-cache.4.16.1.original`），不同版本的备份互不覆盖
- PR #5672 截至 2026-07-10 仍未合入（源码 L75-79 仍缺字段）；合入后本 patch 可移除（脚本 `--check` 会自动检测官方修复并跳过）
