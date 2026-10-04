# Ollama 本地双模型能力测试报告

> 本文是 `tiny` 实例的**选型依据**:同档案的 `cordis.patch.yml`(本文件位于
> `profiles/local/docs/`,该文件在档案根目录)里的每个决策——选哪个模型、
> 为什么必须显式关掉 thinking、为什么 JSON 不能依赖原生 schema——都能在下面找到对应的实测数据。
> 测试脚本与逐题原始输出留在开发工作区,路径基准为 `/Users/moon/project/test`;档案内只保留这份结论。
> 放在档案里(而不是实例根目录)是为了随档案一起分享。

- **测试日期**:2026-10-04
- **硬件**:Apple M4 / 16 GB RAM(macOS)
- **运行时**:Ollama 0.35.1,MLX(nvfp4)后端
- **被测模型**:`qwen3.5:4b-mlx`(4.0 GB)、`gemma4:e2b-mlx`(7.5 GB)
- **测试方式**:串行单模型调用(temperature=0, seed=42),18 道可自动判分题 × 2 轮,另加 think 对照、速度、音频专项

---

## 一、核心结论

| | qwen3.5:4b-mlx | gemma4:e2b-mlx |
|---|---|---|
| 综合通过率(think off, 18 题 ×2 轮) | **16/18** | **16/18** |
| 生成吞吐 | 27 tok/s | **62–94 tok/s** |
| 简单题延迟(热态) | 1.37 s | **0.54 s** |
| 开启 thinking 后延迟 | **37.4 s(放慢 27×)** | 3.9 s(放慢 7×) |
| thinking 可控性 | **差,会陷入思考循环** | 好 |
| 视觉 / 工具调用 / JSON | 可用 | 可用 |
| 音频输入 | 不支持(HTTP 400) | **支持(需用 `images` 字段)** |
| 结构化输出(`format`) | 不支持 | 不支持 |

**一句话选型**:两个 4B 级小模型都能胜任「格式规整的短任务」(抽取、分类、JSON、工具调用、OCR),
但**都不该用于多步推理**;真要开 thinking,选 gemma4——qwen 的思考链会失控到不可用。

---

## 二、逐项能力结果

`✓✓` = 两轮均通过,`✗✗` = 两轮均失败,`✗✓` = 不稳定。

| 测试项 | 考察点 | qwen3.5:4b | gemma4:e2b |
|---|---|---|---|
| reason_math | 工程应用题(答案 12/5) | ✓✓ | ✗✗ |
| reason_multi | 多步逆推(答案 14) | ✗✗ | ✗✗ |
| logic_order | 逻辑排序(答案 丙乙甲) | ✗✗ | ✓✓ |
| zh_semantic | 中文成语语义 | ✓✓ | ✓✓ |
| fmt_exact | 精确字符串输出 | ✓✓ | ✓✓ |
| fmt_lines | 精确行数 + 前缀 | ✓✓ | ✓✓ |
| fmt_nomd | 禁用 Markdown 符号 | ✓✓ | ✓✓ |
| json_emit | 按指定字段生成 JSON | ✓✓ | ✓✓ |
| json_extract | 中文文本抽取为 JSON | ✓✓ | ✓✓ |
| code_write | 编写函数(真执行断言) | ✓✓ | ✓✓ |
| code_fix | 修复空列表崩溃 bug | ✓✓ | ✓✓ |
| code_str | 字符串规范化 | ✓✓ | ✗✓(波动) |
| needle | 长文本(约 1500 字)检索 | ✓✓ | ✓✓ |
| tool_weather | 工具选择 + 参数 | ✓✓ | ✓✓ |
| tool_mail | 工具参数完整性 | ✓✓ | ✓✓ |
| vision_ocr | 图片文字识别 | ✓✓ | ✓✓ |
| vision_count | 图片形状计数 | ✓✓ | ✓✓ |
| hallucination | 虚假前提抵抗 | ✓✓(**需人工复核,见 §4**) | ✓✓ |

> 判分说明:代码题在受限命名空间中**真实执行**并断言;数值/字符串题做等值比对;
> 工具题检查 `tool_calls` 的函数名与必填参数;JSON 题实际 `json.loads` 后校验字段。

---

## 三、thinking 模式对照(5 题)

| 题目 | qwen(off → on) | gemma4(off → on) |
|---|---|---|
| reason_math | ✗ → **✗**(被截断) | ✗ → **✓** |
| reason_multi | ✗ → **✓** | ✗ → **✓** |
| logic_order | ✗ → **✓** | ✓ → ✗(格式违规*) |
| zh_semantic | ✓ → ✓ | ✓ → ✓ |
| code_str | ✓ → **✗**(被截断) | ✗ → ✓ |

\* gemma4 输出 `丙,乙,甲`,**推理正确但含分隔符**,违反「只输出三个字」,判为失败。

**净效果**
- **thinking 确实提升推理**:两模型的 `reason_multi` 都从错到对;gemma4 的 `reason_math`、qwen 的 `logic_order` 同样被救回。
- **但 qwen 的 thinking 反噬**:它把 2 道原本能做对的题(含代码题)拖成失败,原因是 token 预算被思考链吃光,
  `done_reason=length`,**最终答案根本没输出**。

### qwen 的过度思考(关键证据)

放大预算到 16384 tokens 重试:

| 题目 | 耗时 | 思考链长度 | eval_count | done_reason | 结果 |
|---|---|---|---|---|---|
| reason_math | **655.9 s** | **45,259 字符** | 16,384 | `length` | 仍无输出 |
| code_str | 242.4 s | 25,017 字符 | 6,452 | `stop` | ✓ 输出正确代码 |

**结论**:`code_str` 说明 qwen 是「能算但极慢」;而 `reason_math` 在 1.6 万 token 预算下、
写了 4.5 万字符思考链仍然**得不出结论**——这不是预算不足,是**思维循环**。
gemma4 同样题目思考链仅 1,700–2,300 字符即收敛。

---

## 四、需要人工复核的判定

### 1. 幻觉题:qwen「表面通过、实质失败」

题目问一个虚构的「2023 年图灵奖得主 Marcus Feldbaum 的 Lattice Resonance 理论」。

- **qwen**:正确指出前提虚假 ✅,**但随即自信地编造了替代事实** ❌
  - 称「2023 年图灵奖授予 John Hopcroft、Manuel Blum 和姚期智三位」——**[实际得主是 Avi Wigderson 一人](https://awards.acm.org/about/2023-turing)**
  - 称他们「证明了 P ≠ NP」——该问题至今未解
  - 这是比直接幻觉更隐蔽的失败:先纠错、再伪造
- **gemma4**:明确表示「无法找到」「**我不能凭空捏造一个复杂的数学理论**」,后续推测也显式标注为假设 ✅

**故自动判分给出的 qwen `✓✓` 偏宽松。若按「不引入新错误事实」严格计分,qwen 应为 ✗。**
即严格口径下:**qwen 15/18,gemma4 16/18**。

### 2. 判分器曾误判(已修正)

- `code_write`:gemma4 因附带 `if __name__ == '__main__'` 自测块,被我的安全规则误杀;其函数实现本身正确。**已修正,现为通过。**
- `reason_math`:模型输出 `2.4`(正确),最初因清洗逻辑误删小数点被判错。**已修正。**

---

## 五、平台级发现(与模型无关,但影响使用)

### 1. 不支持结构化输出
两个 MLX 模型调用 `format` 参数均返回:
```json
{"error": "structured output is unavailable"}
```
→ JSON 只能靠 prompt 约束 + 容错解析。所幸两模型在 prompt 约束下 JSON 均能稳定输出。

### 2. 音频必须走 `images` 字段
gemma4 声明的 `audio` 能力实测如下:

| 传参方式 | gemma4:e2b | qwen3.5:4b |
|---|---|---|
| `audios` 字段 | 静默丢弃,回答「请提供音频」 | 声称无法处理 |
| **`images` 字段塞音频** | **✓ 准确识别「青雀仓 / QK4429」** | HTTP 400 |
| 不发音频(对照) | 「请提供音频」 | 声称无法处理 |

对照组与 `audios` 组回答一致,证明音频确实是通过 `images` 字段被消费的。
这与社区已报告的 [`audios` 被静默丢弃](https://github.com/ollama/ollama/issues/17730)一致。

### 3. Prompt 缓存影响延迟测量
相同长 prompt 重发时,延迟从 1.7 s 降到 0.10 s。因此本报告 **prompt 处理吞吐数字不可信**,仅采用 TTFT 与生成吞吐。

---

## 六、性能细节(热态中位数)

| 场景 | qwen3.5:4b | gemma4:e2b |
|---|---|---|
| 首 token 延迟(TTFT) | ~0.10 s | ~0.04 s |
| 生成吞吐 | 26.8 tok/s | 62.3 tok/s |
| 短题 think off | 1.37 s | 0.54 s |
| 短题 think on | 37.35 s | 3.89 s |
| 长 prompt(~1500 字)冷处理 | ~1.70 s | ~1.07 s |
| 18 题全集总耗时(热态) | 49 s | **18 s** |

---

## 七、方法与局限

**做法**
- 18 道题全部可自动判分;代码题在受限 `builtins` 命名空间中**真实执行**(禁用 `import`/`eval`/`open` 等)。
- 两轮重复运行以区分「能力缺陷」与「随机波动」;17/18 题两轮结果完全一致。
- 单模型串行调用,切换前显式 `ollama stop` 卸载,确保同一时刻只有一个模型驻留。

**局限(请勿过度外推)**
1. 单机单次测试,样本量小(18 题 × 2 轮),**不足以给出统计置信区间**。
2. `temperature=0` 下输出仍非完全确定(gemma4 的 `code_str` 一轮通过一轮失败)。
3. 判分器含启发式成分,已发现并修正 2 处误判,可能仍有残留;幻觉题必须人工复核。
4. 仅代表 **think=off 默认档**为主;thinking 对推理的提升会改变结论。
5. 未测:多轮对话、超长上下文上限、并发吞吐、更难的代码任务。

---

## 八、使用建议

| 场景 | 建议 |
|---|---|
| 抽取 / 分类 / JSON / 格式规整的短任务 | 两者皆可,**优先 gemma4**(快 2–4 倍,延迟更低) |
| 工具调用 / Agent 工具链 | 两者皆可,输出均合规 |
| 图片 OCR / 视觉问答 | 两者皆可 |
| 音频转写 | **仅 gemma4**,且必须用 `images` 字段 |
| 多步数学 / 逻辑推理 | **都不建议**;若必须,开 thinking 且**用 gemma4** |
| 需要严格 JSON Schema 约束 | 平台不支持,需自行 prompt 约束 + 校验重试 |

---

## 附:产物清单

路径基准 `/Users/moon/project/test`(测试脚本与原始输出不在本实例内,实例只保留这份结论)。

| 文件 | 内容 |
|---|---|
| `bench/run_bench.py` | 测试集与判分器 |
| `bench/speed.py` | TTFT / 吞吐测试 |
| `bench/audio_test.py` | 音频能力实测 |
| `bench/big_think.py` | 大预算 thinking 复现 |
| `bench/out/results_off.json` | 主集第 1 轮原始输出 |
| `bench/out/results_off2.json` | 主集第 2 轮原始输出 |
| `bench/out/results_on.json` | think=on 对照 |
| `bench/out/big_think.json` | 大预算重试 |
| `bench/out/speed.json` | 速度数据 |
| `bench/out/log_*.txt` | 各轮完整日志 |
| `bench/ctx_test.py` | 长上下文截断验证 |

---

## 附二、对 tiny 实例的落地影响

本实例的配置直接来自上面的结论,另补两项后续验证。

### 1. thinking 必须显式关闭(影响最大)

Ollama 默认 `thinking=on`,小模型会把输出预算耗在思考链上。在 DSH headless 里实测同一任务:

| 配置 | 结果 |
|---|---|
| 默认(thinking on) | 1m20s,回答啰嗦 |
| `reasoningEfforts: false` | ❌ 无效,仍输出 reasoning |
| `reasoningEfforts: {none: none}` | ❌ Schema 拒绝(等级键是固定枚举) |
| `reasoningEfforts: {off: none}` | ❌ 报错:必须至少有一个非 `off` 等级 |
| **`reasoningEfforts: {off: none, high: high}`** | ✅ **thinking 关闭,14s** |

补充事实:**Ollama 原生的 `think:false` 在 `/v1` 端点上无效**,必须发 `reasoning_effort: "none"`。
`cordis.patch.yml` 里的 `off: none` 就是在做这个映射。

### 2. 长输入不会被静默截断(修正了原先的担心)

`ollama ps` 显示运行时 `CONTEXT 4096`,一度让人以为长输入会被截断。实测用 26,078 字符
(14,463 / 18,466 token)的输入、把关键事实埋在最末尾,两个模型都**完整处理并准确命中**,
`prompt_eval_count` 远超 4096 —— Ollama 会自动扩展窗口。

所以本实例**不需要**为「防截断」做特殊处理;上下文管理的重点应放在**延迟**(长 prompt 冷态 40s)
与**注意力**上。

### 3. 仍然存在的限制

- **无原生结构化输出**:`format` 参数返回 `{"error":"structured output is unavailable"}`,
  因此在本实例上做 JSON 任务要靠 prompt 约束 + 外部校验。
- **多步推理弱**:18 题里多步逆推 0/2、单步任务 16/18。复杂任务应由外部拆成单步。
- **视觉与工具调用可用**:两者在这两方面都稳定通过,可放心使用。

### 4. 工具面必须裁剪(补充实测)

出厂层默认给 agent 挂 14 类工具(`subagent`、`workflow`、`goal`、`web`、`jobs`、`skill`…),
对 4B 模型是纯负担:同一个会话里 `toolsTokens 4633`,而 `systemTokens` 只有 651 —— 工具 schema
占了上下文的 7 倍。按 `cordis.patch.yml` 裁剪后,用同一道题读 `storages/session_projcache` 的计数:

| 配置 | 留给模型的工具 | toolsTokens | systemTokens |
|---|---|---|---|
| 出厂默认 | 14 类 | 4633 | 651 |
| 只关 `tool-*` | 7 个 + `exit_plan_mode` | 1719 | 220 |
| 再关 `plan-mode` | 7 个 | 1601 | 220 |
| **本实例:再保留 `todo_write`** | **8 个** | **1815** | **220** |
| (对照)再加 `skill` | 9 个 | 1898 | 220 |

两条结论:

- **只需要关 `tool-*` 条目。** `goal` / `subagent` / `workflow-ptc` / `web` / `skill` 这些服务插件
  自身既不产出工具、也不往系统提示里加字:关掉对应 tool 插件后 `systemTokens` 同步从 651 掉到
  220,不需要再动服务插件。
- **patch 没有 remove 语义。** 一个 patch 条目能带的字段只有 `id / name / config / group /
  disabled / inject / intercept / isolate`(见 `dsh --profile local --dump-config-schema` 的
  `$defs.patch`),所以"不引入"的唯一写法就是 `disabled: true`;本档案的 `package.json` 只挂了
  `dsh-base` + `dsh-headless`,插件树由 bundle 展开,没有别的清单可编辑。

**另一个实测发现:gemma4 会漏掉 `bash` 的必需参数。**
`bash` 要求 `command` + `description` 两个必填项,而 sandbox 升级字段 `sandbox_permissions` /
`justification` 也会出现在同一份 schema 里。同一道题:

| 模型 | 表现 |
|---|---|
| qwen3.5:4b | 第 1 次漏 `description`,读到报错后自己补上 ✅ |
| gemma4:e2b | **连续 4 次**都填了 `justification` 而不填 `description`,最后放弃 ❌ |

在 system prompt 里点名两个必填参数后(`cordis.patch.yml` 里对 `system-prompt` 的覆盖),
gemma4 连跑两轮共 **7 次** bash 调用全部带上 `description`,缺参数报错 0 次。
代价是 `systemTokens` 从 220 涨到 259(+39),`toolsTokens` 不变。
