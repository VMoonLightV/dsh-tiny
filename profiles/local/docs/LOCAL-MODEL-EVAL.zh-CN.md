# Ollama 本地双模型能力测试报告

> 本文是 `tiny` 档案的**选型依据**:同档案的 `cordis.patch.yml` 里的每个决策——选哪个模型、
> 为什么必须显式关掉 thinking、为什么 JSON 不能依赖原生 schema——都能在下面找到对应的实测数据。
> 测试脚本与逐题原始输出留在未发布的开发工作区;档案内只保留这份结论。
> 英文版见 `LOCAL-MODEL-EVAL.md`;本文是其中文翻译,测试输出的中文字符串按数据原样保留。

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

路径基准为未发布的开发工作区(测试脚本与原始输出不随档案发布,档案内只保留这份结论)。

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

`write` 是同一类毛病,而且更隐蔽:gemma4 先吐长长的 `content`,然后直接闭合 JSON,
把同样必填的 `file_path` 漏掉。它是**间歇性**的,而且**不是截断**——参数 JSON 能正常解析,
只是少了一个 key。三次尝试里失败 1 次(正文 3.8 KB)、成功 2 次(其中一次正文 4.2 KB)。
提示词现在也点名了 write 的两个参数与顺序。

---

## 附三、工具面实测(2026-10-05)

在实例的隔离副本上,用 `local` 档案 + `gemma4:e2b-mlx` 每个工具跑一道题,
从运行事件流里读回真实的调用与结果。

| 工具 | 结果 | 证据 |
|---|---|---|
| `glob` | ✅ | 列出三个 `.md`,含子目录里的那个 |
| `grep` | ✅ | 精确定位含标记串的唯一文件 |
| `read` | ✅ | 返回文件正文 |
| `write` | ✅ | 创建 `notes.md`,这次 `file_path` 在 |
| `edit` | ✅ | 文件最终精确为 `# Notes\nHELLO\nworld` |
| `todo_write` | ✅ | 建立三项清单 |
| `read_image` | ❌ → 已修 | 见下 |
| `bash` | **未能验证** | 测试所在 shell 无法嵌套 `sandbox-exec`,沙箱后端拒绝了每条命令。这是**测试环境**的产物,不能作为档案本身的证据 |
| `present` | **未执行** | 纯 UI 工具(渲染文件卡片),挂在 `chat` 档案里,没有 headless 路径可以驱动 |

### `read_image` 原本是死的:模态未声明

第一次尝试直接失败:

```
Error: cannot read "picture.png" as an image:
model "gemma4:e2b-mlx" does not declare image input
```

任何省略 `input` 字段的模型条目,pi-ai 都会回落到 `DEFAULT_INPUT = ["text"]`,
随后 `dsh-tool-fs` 拒绝一切图片。这两个条目是手写的、从没声明过它,于是工具被静默废掉
——**尽管 gemma4 确实能看图**。本报告前面的视觉结论是直连 Ollama 测的,根本不经过档案,
所以不可能发现这一点。

声明 `input: [text, image]` 即可修复(`MODALITIES` 只有 `text | image` 两个合法值):
图片能送进模型,它准确认出了蓝色图形是方形。

**但计数仍不可靠。** 在一张「两个红圆 + 一个蓝方」的合成图上,gemma4 两次都答
"三个红圆",以及"一共四个图形"。本报告前面的 `vision_count` 通过**不能外推**——
视觉计数与图像内容强相关。

### thinking 几乎不花钱,却是推理的必需品

一道多步应用题,gemma4,每档跑两次,用 `--patch` 覆盖切换 thinking(不改档案):

| | 耗时 | 输出 | 严格判分 |
|---|---|---|---|
| think off #1 | 7.2 s | `The calculation is:\n1. Total students: 3…`(被截断) | ✘ |
| think off #2 | 3.9 s | `I need to perform a mathematical calcula…`(被截断) | ✘ |
| **think high #1** | 7.1 s | `6` | **✓** |
| **think high #2** | 4.4 s | `6` | **✓** |

会话日志确认开关确实生效:两次 `high` 各带 1 个推理块,两次 `off` 都是 0。

所以对推理任务,thinking 不只是"锦上添花"——不开时模型把预算耗在绕圈上,压根没给出可用答案;
而且它**没有带来耗时代价**,这次样本里反而更快,因为不思考的那两次在空转烧 token。
`n=2`,不要过度外推。

正因如此,`chat` 档案在 `agent-default-model` 上设了 `reasoningEffort: high`,而 `local` 保持关闭
——一个是对话界面,一个是批处理一次性执行器。

---

## 附四:`gemma4:e4b-mlx` 与 `gemma4:e2b-mlx` 对比(2026-10-05)

`gemma4:e4b-mlx` 之后才下到本地,用**完全相同的题库、同一个档案、同一套工具、同样九道题**跑了一遍,
因此两个模型可以直接对比。

| | `gemma4:e2b-mlx` | `gemma4:e4b-mlx` |
|---|---|---|
| 参数量 | 5.2 B | 8.1 B |
| 磁盘占用 | 7.5 GB | 9.5 GB |
| 上下文 / 量化 | 131 072 / nvfp4 | 131 072 / nvfp4 |
| 能力 | completion、vision、audio、tools、thinking | 同左 |

两个模型都通过 `--patch` 覆盖注入,不改本档案;除非特别说明,`reasoningEffort` 一律不设(= thinking 关闭,
与本档案出厂状态一致)。下面每一次运行都是独立进程 + 一份全新的夹具目录。

### 1. 工具面:一个工具一道题

| 任务 | `e2b` | `e4b` |
|---|---|---|
| `glob` 找 `*.md` | ✅ 3.1 s | ✅ 7.3 s |
| `grep` 找文件里的 TODO | ✅ 4.8 s | ✅ 7.8 s |
| `read` 指定行 | ✅ 5.8 s | ✅ 7.5 s |
| `write` 单行文件 | ⚠️ 文件写成功,随后 `EMPTY_RESPONSE`(退出码 1)20.3 s | ✅ 一次被拒后成功 14.8 s |
| `edit` 替换一个词 | ✅ 一次整文件重写被拦下后成功 6.6 s | ✅ 三次被拒后成功 17.9 s |
| 三步任务 `read`→数行→`write` | ✅ 5.6 s | ❌ 22.9 s |
| `read_image`:2 个红圆 + 1 个蓝方 | ❌ 6.0 s | ✅ 8.8 s |
| `read_image`:OCR `HARBOR 7391` | ✅ 4.9 s | ✅ 8.2 s |
| `bash pwd` | ❌ 本机没有可用的沙箱后端 | ❌ 同上 |

九次运行的平均耗时:**`e2b` 6.9 s,`e4b` 11.6 s,`e4b` 慢约 1.7 倍。**

单次运行说明不了什么,所以把区分度最大的三道题各重复三次:

| 各重复三次 | `e2b` | `e4b` |
|---|---|---|
| 数形状(2 红圆、1 蓝方) | 1/3 正确 | **3/3 正确** |
| 三步任务 → `count.txt` | **3/3 正确** | 0/3 |
| `write` 单行文件 | 3/3 文件落地 | 2/3 文件落地 |

再并入第一轮、以及一次在真实工作区里的重跑:**三步任务 `e2b` 6/6,`e4b` 0/8**(多出来的两次 `e4b` 运行
用的是让 `bash` 能跑起来的权限模式,用来排除"是不是因为 shell 用不了才失败"——结果不是)。
这是整份报告里最锋利的一条差异,而且它**不是知识差异**,是下面这个 escalation 陷阱。

#### token 速度

直接打 Ollama API 测(`prompt_eval_count`/`prompt_eval_duration` 与 `eval_count`/`eval_duration`),
绕开 harness,取 3~4 次的中位数:

| | prefill @200 tok | prefill @2 600 tok | decode |
|---|---|---|---|
| `e2b` | 2 618 t/s | 2 185 t/s | **70 t/s** |
| `e4b` | 684 t/s | 621 t/s | **50 t/s** |

**不对称才是重点。** `e4b` 参数只有 1.56 倍,但 **prefill 慢了 3.5 倍**,而 **decode 只慢 1.4 倍**。
在这里 prefill 才是有意义的那个数:`local` 每一次调用都要送约 2 100 token 的系统提示词 + 工具 schema,
所以每一步的地板大约是 **`e2b` 0.9 s、`e4b` 3.3 s**,还没开始生成 token。

从会话日志里读 LLM 调用延时(`request/header` → `assistant/message`)可以印证。八次单工具运行、16 次调用:

| | 中位数 | 均值 |
|---|---|---|
| `e2b` | 3.48 s | 3.60 s |
| `e4b` | 6.80 s | 6.99 s |

**单次调用 1.95 倍**——比端到端的 1.7 倍更差,因为端到端里还包含进程启动和工具执行,这两项对两个模型
是一样的。`e4b` 每一步还写得更长,这就是 1.4 倍 decode 与 1.95 倍单次调用之间剩下的那段差距。

一个"非发现":打开 thinking 反而让实测 decode 速率略升(`e2b` 70 → 86 t/s,`e4b` 50 → 57 t/s)。
这只是更长的生成摊薄了每 token 的固定开销,不是真的变快——推理 token 和其他 token 是同速生成的。

### 2. escalation 陷阱:只发 `justification`、不发 `sandbox_permissions`

`write`/`edit`/`bash` 的 schema 里都挂着两个看起来可选的升级参数 `sandbox_permissions` 和
`justification`。**只发 `justification` 一定会被拒**:

```
Error: invalid escalation: justification is only valid together with sandbox_permissions
```

两个模型都会踩,但踩了之后的反应完全相反:

- **`e2b`**:要么两个都不发,要么成对发,所以调用能过。
- **`e4b`**:只发 `justification`,被拒之后**几乎原样重发同一条错误调用**。最坏的一次跑了
  **19 次工具调用、烧掉 58.5 s 和 23 922 上下文 token,文件始终没建出来**,最后以
  `EMPTY_RESPONSE` 收场;它一次都没想过把两个字段配对。另外几次则在结尾声称文件已创建(其实没有)。

把两个模型都跑过的 40 组同题统计一遍(剔除环境性失败——本机沙箱后端不可用):

| | 工具调用 | 自身造成的错误 | 调用失败率 | `invalid escalation` |
|---|---|---|---|---|
| `e2b` | 78 | **9** | 12 % | 0 |
| `e4b` | 115 | **82** | **71 %** | 40 |

一张表就是全部差距。`e4b` **不是没看懂任务**,它是过不了参数校验,然后**换措辞、不换结构**地反复重发。
它那 82 个自身错误里,40 个是 `invalid escalation`,35 个是 `bash` 漏发 `description`——同一个陷阱,
换了一个字段。`e2b` 的 escalation 错误是 **0**。剩下的错误两边共有且很平常(7 次读一个还没写出来的文件、
1 次写前未读、1 次把图片当文本读)。

### 2b. 提示词修不好它

这两个字段没法从 schema 里摘掉。`dsh-tool-fs` 只要有 confining 后端挂载就会 advertise 它们
(`...sandbox.escalationModes.length > 0 ? sandbox.schemaFields() : {}`);而想通过关掉 `fs-sandbox` 或
`sandbox-policy` 来压掉 advertise,会把**整套文件工具一起带走**——`write` 直接回答
`unknown tool "write"`,`bash`、`read`、`grep` 根本挂不上。所以只能拿文本去试。四个变体,三步任务各跑 5 次:

| 变体 | 往 `personaSuffix` 里加了什么 | `e4b` 三步任务 | `e4b` `write` |
|---|---|---|---|
| v0(出厂) | — | **0/8** | 4/6 |
| v2 | `justification` 必须与 `sandbox_permissions` 配对 | 1/5 | 2/2 |
| v3 | + "调用报错就改参数,绝不重发同一条" | 0/5 | 2/2 |
| v4 | + "建文件改文件一律用 write/edit,不要用 shell 重定向" | 0/5 | 2/2 |
| v5 | + 一个"该怎么调用"的具体范例 | 0/5 | 2/2 |

**20 次里成功 1 次。** 这些句子也不会伤到 `e2b`(v4 下三步任务 3/3)。
本附录取早的一个版本把这里写成 0/8 → 2/2——那是 n=2 的样本,**予以撤回**:重复 5 次后效应消失了。

原因在对话记录里看得很清楚。这四句话被无视的方式一模一样:

- v4 说*不要用 shell 重定向* → `e4b` 照样跑 `echo "4" > count.txt`。
- v3/v4 说*不要重发报错的调用,要改参数* → 它重发**一模一样**的调用,只把 `justification` 换了个说法。
- 配对规则白纸黑字写着 → 它还是只发 `justification`。
- 报错文本**逐字点名**缺哪个字段 → 它不理会。

最干净的证据来自那次想拆掉陷阱的尝试。把 `fs-sandbox` 关掉后 `write` 消失、只剩 `bash`,`e4b` **连续六次**
发出 `{"command": …, "justification": …}`,**始终不带 `description`**,并且这样解释:

> I must adhere strictly to the syntax: `bash(command: "...", justification: "...")`

它**自己发明了一个工具签名,然后同时压过 schema 和系统提示词去遵守它**,最后声称文件已创建。
**它的短板不是"不知道该做什么",而是"无法根据上一条工具结果改写下一次工具调用"。** 这不是
`personaSuffix` 能补上的东西。

### 2c. 真正有用的是 thinking

thinking 给了它一个可以重新考虑的草稿纸,这是唯一有证据支撑的干预:

| `e4b`,三步任务 | 结果 |
|---|---|
| thinking off,出厂提示词 | 0/8 |
| thinking off,v2 / v3 / v4 / v5 | 1/5、0/5、0/5、0/5 |
| **thinking high,出厂提示词** | **2/5** |

那次成功里,`e4b` 先把 `justification` 换了个说法被拒,下一次调用干脆**把这个字段整个删掉**——
这正是它不开 thinking 时从来不会做的事。但代价也在:每轮 23~59 s,而开着的对照组是 13~25 s;
而且 2/5 离 `e2b` 的 6/6 还差得远。

### 2d. 一旦用上工具,thinking 的代价才显现

附三的结论是"thinking 几乎不花时间"。那只对**单步文本回答**成立——不思考的那次反正会以差不多的
token 量空转。**一旦涉及工具就不成立了**,因为 agent **每一步**都要重新思考一次。同样的四道工具题,
`e2b`,从会话日志读出的每次调用耗时:

| | 每次调用中位数 | 均值 | 带推理块的步数 |
|---|---|---|---|
| thinking off | 3 478 ms | 3 603 ms | 0 / 8 |
| thinking high | 5 700 ms | 6 852 ms | **8 / 8** |

再看一道复合任务(读 `data.csv` → 求 `qty` 列之和 → 写进 `sum.txt`),它同时需要工具规划和算术:

| | 成功率 | 工具调用数 | 输出 token | 耗时 |
|---|---|---|---|---|
| thinking off | 2/3 | 2–4 | 99–502 | 3–8 s |
| thinking high | **2/3** | 4–6 | 1 662–2 400 | 24–34 s |

**成功率完全一样,耗时约 5 倍,输出 token 5~10 倍。** 实测每个推理块 200~3 000 字符,而每一步都要付一次。
所以"thinking 免费"只对一次性文本回答成立;对 `local` 存在的意义——用工具干活——它是这个档案里最贵的
一个开关。这也正是 `local` 关、`chat` 开这个分工的依据。

---

### 3. 视觉:唯一明确的胜项

同一张合成图(两个红圆、一个蓝方):`e4b` **4 次全对**;`e2b` **4 次里对 1 次**,另两次答"三个红色圆形"。
`e2b` 有时还会在 `.png` 上选 `read` 而不是 `read_image`,然后拿到 `binary file`——它第一次数形状就是
这么失败的,所以这个差距有一部分是**工具选择**而非感知。OCR 那张(`HARBOR 7391`)两个模型各两次都
一字不差。

即便对 `e4b`,数数仍然依赖具体内容。结论应该读成"`e4b` 更擅长看图",而不是"`e4b` 能可靠数数"。

### 4. 多步推理:没有优势

三道有唯一整数答案的应用题(7、4、27),每档各跑两次,按最终数字判分:

| | thinking off | thinking high |
|---|---|---|
| `e2b` | 3/6 | 5/6 |
| `e4b` | 2/6 | 4/6 |

`e4b` 在这里并不更强,而且 n=6 时这些差值都在噪声范围内。两个模型栽在同一处:那道"给一半再加半个
苹果"的题从建模第一步就错了;而不开 thinking 时,它们会把整条推理链直接吐进答案通道。`e4b` 不思考时
的输出是全场最差的——有一次吐了 **2 674 个输出 token** 的乱麻代数,最后答了个 3。

thinking 开关的表现与之前一致:会话日志里 `high` 带 `reasoningEffort: "high"` 且每次一个推理块,
`off` 两者都没有。对 `e4b`,打开 thinking 把它从 2/6 抬到 4/6,代价基本持平——六次 `high` 平均每轮
11.4 s,六次 `off` 是 11.9 s。这个均值主要由"哪一轮承担了模型加载"决定,所以只该读成"没有更贵",
不该读成"更快"。

---

### 5. `bash` 终于验证过了

`bash` 是附三里唯一没验成的项,卡在本机没有可用的沙箱后端
(`sandbox-exec: sandbox_apply: Operation not permitted`)。把权限模式关掉再跑同一个档案就通了:

```sh
DSH_HOME=~/workspace/profiles/tiny DSH_PERMISSION_MODE=danger-full-access \
  dsh --profile local --patch ./e4b.yml "run pwd and tell me the output"
# tool_call bash {"command":"pwd","description":"Print the current working directory path"}
# tool_result completed "/tmp/e4btest\n"
# final: The output of the `pwd` command is `/tmp/e4btest`.
```

所以 `bash` 是好的,而且 `e4b` 在不被 escalation 字段干扰时能把 `command` 和 `description` 发对。
之前那次失败是本机的问题,不是档案的问题。但请留意它对**出厂状态**的含义:**在没有沙箱后端的主机上,
`local` 能读、能写、能搜,但什么命令都执行不了**——因为除非调用方显式选择,没有任何模式能让它非受限地运行。

---

### 6. 建议

**默认模型继续用 `gemma4:e2b-mlx`。** `e4b` 大 60%、端到端慢 1.7 倍(单次 LLM 调用慢 1.95 倍)、
推理没有更准,而且它的**工具调用失败率是 71%,`e2b` 是 12%**。值得把它作为第二个模型列出来,用在
看图这种它明确更强的场景;**但不要在任何提示词下让它做多步文件任务。**

上面几个实验给出两条结论:

1. **不要试图用提示词绕开 escalation 陷阱。** 四个变体、20 次运行、成功 1 次;那个"看起来有效"的句子
   只在 n=2 时成立,重复 5 次就没了。如果一定要用 `e4b`,就给它开 thinking——0/8 → 2/5 是唯一有实测
   支撑的改善,而且仍然远不如 `e2b`。"告诉它用 `write` 而不是 shell 重定向"那条也试过(v4),毫无作用。
2. **真正的修复在 DSH 上游,不在这个档案里。** `validateEscalationArgs` 把单独出现的 `justification`
   当成错误;如果在 `sandbox_permissions` 缺席时**忽略**这个多余字段,陷阱对所有小模型都会消失——而
   最容易认真读 schema 字段描述、因而最容易掉进去的,恰恰是能力更强的那个模型。档案层表达不了这个
   改动,而两种压掉 schema 字段的办法都会赔上文件工具。

另有一条与模型选择无关、但值得记住的结论:在没有可用沙箱后端的主机上,`local` 能读、能写、能搜,
但**什么命令都执行不了**——`bash` 拒绝非受限运行,而且没有任何档案层设置能改变这一点,只有调用方自己的
`DSH_PERMISSION_MODE` 可以。
