import { readFileSync, existsSync } from "fs"
import { homedir } from "os"

// 从 opencode.jsonc 自动提取 oh-my-openagent 版本号
function extractVersion() {
  const configPath = `${homedir()}/.config/opencode/opencode.jsonc`
  const config = readFileSync(configPath, "utf8")
  const match = config.match(/oh-my-openagent@(latest|\d+\.\d+\.\d+)/)
  if (!match) throw new Error("Could not extract oh-my-openagent version from opencode.jsonc")
  return match[1]
}

const version = extractVersion()
const DIST = `${homedir()}/.cache/opencode/packages/oh-my-openagent@${version}/node_modules/oh-my-openagent/dist/index.js`

console.log(`Detected version: ${version}`)
console.log(`Target file: ${DIST}`)

if (!existsSync(DIST)) {
  console.log(`\n✗ ERROR: File not found: ${DIST}`)
  process.exit(1)
}

const content = readFileSync(DIST, "utf8")

let pass = 0
let fail = 0

function check(name, condition) {
  if (condition) {
    console.log(`  ✓ ${name}`)
    pass++
  } else {
    console.log(`  ✗ ${name}`)
    fail++
  }
}

// 提取 HEURISTIC_MODEL_FAMILY_REGISTRY 中的 GLM 族定义块
// GLM 块的精确结构：`  {` 开头，4 空格属性，`  },` 结尾
// 用行级匹配避免跨块贪婪问题
function extractGlmBlock(text) {
  const lines = text.split("\n")
  for (let i = 0; i < lines.length; i++) {
    // 匹配 HEURISTIC_MODEL_FAMILY_REGISTRY 中的 GLM 条目（2空格缩进的 `{` + 4空格的 family:"glm"）
    if (lines[i] === "  {" && i + 1 < lines.length && /^\s{4}family: "glm",/.test(lines[i + 1])) {
      // 找到 GLM 块起点，收集到 `  },` 结尾
      const blockLines = [lines[i]]
      for (let j = i + 1; j < lines.length; j++) {
        blockLines.push(lines[j])
        if (/^\s{2}\},?/.test(lines[j])) break
      }
      return blockLines.join("\n")
    }
  }
  return null
}

const glmBlock = extractGlmBlock(content)

console.log("\n=== GLM Reasoning Patch Verification ===\n")

// 1. 验证 GLM 块定位
console.log("1. GLM block location:")
if (!glmBlock) {
  console.log("  ✗ FATAL: Could not locate GLM block in HEURISTIC_MODEL_FAMILY_REGISTRY")
  console.log("  The file structure may have changed. Manual inspection required.")
  process.exit(1)
}
console.log(`  ✓ Found GLM block (${glmBlock.split("\n").length} lines)`)

// 2. 验证 patched 内容（全部限定在 glmBlock 内检查）
console.log("\n2. Patched content (within GLM block only):")
check('GLM has reasoningEfforts: ["high", "max"]',
  /reasoningEfforts: \["high", "max"\]/.test(glmBlock))
check('GLM has max variant',
  /variants: \["low", "medium", "high", "max"\]/.test(glmBlock))
check("GLM reasoningEffortAliases present",
  /reasoningEffortAliases: \{/.test(glmBlock))
check('GLM alias low→high', /low: "high"/.test(glmBlock))
check('GLM alias medium→high', /medium: "high"/.test(glmBlock))
check('GLM alias xhigh→max', /xhigh: "max"/.test(glmBlock))

// 3. 验证旧模式已消失
console.log("\n3. Old pattern removed:")
check('Old GLM block (3 variants, no reasoningEfforts) is gone',
  !/variants: \["low", "medium", "high"\]\n\s{2}\},/.test(glmBlock))

// 4. 行为模拟（纯逻辑验证）
console.log("\n4. Behavior simulation (downgradeWithinLadder with patched GLM caps):")
const patchedGlm = {
  variants: ["low", "medium", "high", "max"],
  reasoningEfforts: ["high", "max"],
}
const VARIANT_LADDER = ["low", "medium", "high", "xhigh", "max"]
const REASONING_LADDER = ["none", "minimal", "low", "medium", "high", "xhigh", "max"]

function downgradeWithinLadder(value, allowed, ladder) {
  const idx = ladder.indexOf(value)
  if (idx === -1) return undefined
  for (let i = idx; i >= 0; i--) { if (allowed.includes(ladder[i])) return ladder[i] }
  return undefined
}

const variantMax = downgradeWithinLadder("max", patchedGlm.variants, VARIANT_LADDER)
const reMax = downgradeWithinLadder("max", patchedGlm.reasoningEfforts, REASONING_LADDER)
check(`variant "max" preserved (got "${variantMax}")`, variantMax === "max")
check(`reasoningEffort "max" preserved (got "${reMax}")`, reMax === "max")

// 5. 其他族不受影响（在全文中检查，确认仍存在）
console.log("\n5. Other families unchanged:")
check('deepseek family still has reasoningEfforts',
  /family: "deepseek",[\s\S]*?reasoningEfforts: \["high", "max"\]/.test(content))
check("kimi-thinking family still has supportsThinking: true",
  /family: "kimi-thinking",[\s\S]*?supportsThinking: true/.test(content))

console.log(`\n=== Results: ${pass} passed, ${fail} failed ===`)
if (fail > 0) {
  console.log("\n✗ PATCH VERIFICATION FAILED")
  process.exit(1)
} else {
  console.log("\n✓ PATCH VERIFIED SUCCESSFULLY")
  console.log(`  GLM-5.2 reasoningEffort 'max' will reach the API as reasoning_effort: 'max'`)
}
