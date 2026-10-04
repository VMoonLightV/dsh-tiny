# Ollama Local Dual-Model Capability Report

> This document is the **selection rationale** for the `tiny` instance: every decision in the
> profile's `cordis.patch.yml` (this file lives in `profiles/local/docs/`; the patch sits at the
> profile root) — which model to pick, why thinking must be switched off explicitly, why JSON
> cannot rely on a native schema — has its supporting measurement below.
> The test scripts and the raw per-question output stay in the (unpublished) development
> workspace; only these conclusions are kept inside the profile.
> A Chinese translation of this report is available as `LOCAL-MODEL-EVAL.zh-CN.md`.
>
> Test-output strings that were Chinese in the original run are kept verbatim as data and glossed
> in English; they have not been translated or altered.

- **Test date**: 2026-10-04
- **Hardware**: Apple M4 / 16 GB RAM (macOS)
- **Runtime**: Ollama 0.35.1, MLX (nvfp4) backend
- **Models under test**: `qwen3.5:4b-mlx` (4.0 GB), `gemma4:e2b-mlx` (7.5 GB)
- **Method**: serial single-model calls (temperature=0, seed=42), 18 auto-gradable questions x 2
  rounds, plus a thinking comparison, speed and audio sub-studies

---

## 1. Headline results

| | qwen3.5:4b-mlx | gemma4:e2b-mlx |
|---|---|---|
| Overall pass rate (think off, 18 questions x 2 rounds) | **16/18** | **16/18** |
| Generation throughput | 27 tok/s | **62–94 tok/s** |
| Simple-question latency (warm) | 1.37 s | **0.54 s** |
| Latency with thinking on | **37.4 s (27x slower)** | 3.9 s (7x slower) |
| Thinking controllability | **Poor — falls into a reasoning loop** | Good |
| Vision / tool calling / JSON | usable | usable |
| Audio input | unsupported (HTTP 400) | **supported (must use the `images` field)** |
| Structured output (`format`) | unsupported | unsupported |

**One-line verdict**: both 4B-class models are up to "well-formed short tasks" (extraction,
classification, JSON, tool calling, OCR), but **neither should be used for multi-step reasoning**.
If you genuinely need thinking, pick gemma4 — qwen's chain of thought runs away to the point of
being unusable.

---

## 2. Per-item capability results

`✓✓` = passed both rounds, `✗✗` = failed both rounds, `✗✓` = unstable.

| Test | What it probes | qwen3.5:4b | gemma4:e2b |
|---|---|---|---|
| reason_math | engineering word problem (answer 12/5) | ✓✓ | ✗✗ |
| reason_multi | multi-step backward inference (answer 14) | ✗✗ | ✗✗ |
| logic_order | logical ordering (expected literal answer `丙乙甲`) | ✗✗ | ✓✓ |
| zh_semantic | Chinese idiom semantics | ✓✓ | ✓✓ |
| fmt_exact | exact string output | ✓✓ | ✓✓ |
| fmt_lines | exact line count + prefix | ✓✓ | ✓✓ |
| fmt_nomd | Markdown symbols forbidden | ✓✓ | ✓✓ |
| json_emit | emit JSON with the specified fields | ✓✓ | ✓✓ |
| json_extract | extract from Chinese text into JSON | ✓✓ | ✓✓ |
| code_write | write a function (really executed and asserted) | ✓✓ | ✓✓ |
| code_fix | fix a crash on an empty list | ✓✓ | ✓✓ |
| code_str | string normalisation | ✓✓ | ✗✓ (unstable) |
| needle | retrieval in a long text (~1500 characters) | ✓✓ | ✓✓ |
| tool_weather | tool selection + arguments | ✓✓ | ✓✓ |
| tool_mail | tool argument completeness | ✓✓ | ✓✓ |
| vision_ocr | text recognition in an image | ✓✓ | ✓✓ |
| vision_count | shape counting in an image | ✓✓ | ✓✓ |
| hallucination | resistance to a false premise | ✓✓ (**needs human review, see §4**) | ✓✓ |

> Grading notes: code questions are **really executed** in a restricted namespace and asserted;
> numeric and string questions are compared for equality; tool questions check the `tool_calls`
> function name and required arguments; JSON questions are actually `json.loads`-ed and then
> field-checked.

---

## 3. Thinking-mode comparison (5 questions)

| Question | qwen (off → on) | gemma4 (off → on) |
|---|---|---|
| reason_math | ✗ → **✗** (truncated) | ✗ → **✓** |
| reason_multi | ✗ → **✓** | ✗ → **✓** |
| logic_order | ✗ → **✓** | ✓ → ✗ (format violation*) |
| zh_semantic | ✓ → ✓ | ✓ → ✓ |
| code_str | ✓ → **✗** (truncated) | ✗ → ✓ |

\* gemma4 emitted `丙,乙,甲`: **the reasoning is correct but it contains separators**, which
violates "output exactly three characters", so it was graded as a failure.

**Net effect**

- **Thinking does improve reasoning**: `reason_multi` went from wrong to right for both models;
  gemma4's `reason_math` and qwen's `logic_order` were rescued as well.
- **But thinking backfires on qwen**: it dragged 2 questions that had previously been correct
  (including a code question) into failure, because the token budget was eaten by the chain of
  thought and `done_reason=length` — **the final answer was never emitted at all**.

### qwen's overthinking (key evidence)

Retried with the budget raised to 16384 tokens:

| Question | Wall time | Chain-of-thought length | eval_count | done_reason | Result |
|---|---|---|---|---|---|
| reason_math | **655.9 s** | **45,259 characters** | 16,384 | `length` | still no output |
| code_str | 242.4 s | 25,017 characters | 6,452 | `stop` | ✓ emitted correct code |

**Conclusion**: `code_str` shows qwen is "able to compute, but extremely slow". `reason_math`,
given a 16k-token budget, wrote a 45k-character chain and **still reached no conclusion** — that is
not a budget shortfall, it is a **reasoning loop**. On the same question gemma4's chain converged
after only 1,700–2,300 characters.

---

## 4. Judgements that need human review

### 1. Hallucination question: qwen "passes on the surface, fails in substance"

The question asks about a fictitious "Lattice Resonance theory by Marcus Feldbaum, 2023 Turing
Award winner".

- **qwen**: correctly called out the false premise ✅, **but then confidently fabricated
  replacement facts** ❌
  - claimed the 2023 Turing Award went to John Hopcroft, Manuel Blum and Andrew Chi-Chih Yao —
    **[the actual winner was Avi Wigderson, alone](https://awards.acm.org/about/2023-turing)**
  - claimed they "proved P ≠ NP" — that problem is still open
  - this is a subtler failure than outright hallucination: correct the premise first, then fabricate
- **gemma4**: stated plainly that it "could not find" anything and that "**I cannot invent a
  complex mathematical theory out of thin air**", and explicitly flagged its later speculation as
  an assumption ✅

**So the automatic grader's `✓✓` for qwen is too lenient. Under a strict "introduces no new false
facts" rule, qwen should be ✗.**
That is, under the strict reading: **qwen 15/18, gemma4 16/18**.

### 2. The grader misjudged twice (both fixed)

- `code_write`: gemma4 was killed by my safety rule for appending an
  `if __name__ == '__main__'` self-test block; the function implementation itself was correct.
  **Fixed; it now passes.**
- `reason_math`: the model output `2.4` (correct), but the cleaning logic stripped the decimal
  point and marked it wrong. **Fixed.**

---

## 5. Platform-level findings (model-independent, but they affect how you use this)

### 1. No structured output

Both MLX models return this for the `format` parameter:

```json
{"error": "structured output is unavailable"}
```

→ JSON can only be obtained through prompt constraints plus tolerant parsing. Fortunately both
models emit stable JSON under prompt constraints.

### 2. Audio has to travel in the `images` field

gemma4's declared `audio` capability, as measured:

| How it was passed | gemma4:e2b | qwen3.5:4b |
|---|---|---|
| `audios` field | silently dropped; replied "please provide the audio" | claimed it cannot process it |
| **audio stuffed into the `images` field** | **✓ correctly transcribed `青雀仓 / QK4429`** | HTTP 400 |
| no audio sent (control) | "please provide the audio" | claimed it cannot process it |

The control group and the `audios` group answered identically, which proves the audio really was
consumed through the `images` field. This matches the community report that
[`audios` is silently dropped](https://github.com/ollama/ollama/issues/17730).

### 3. Prompt caching skews latency measurement

Re-sending the same long prompt dropped latency from 1.7 s to 0.10 s. So this report's
**prompt-processing throughput figures are not trustworthy**; only TTFT and generation throughput
are used.

---

## 6. Performance detail (warm medians)

| Scenario | qwen3.5:4b | gemma4:e2b |
|---|---|---|
| Time to first token (TTFT) | ~0.10 s | ~0.04 s |
| Generation throughput | 26.8 tok/s | 62.3 tok/s |
| Short question, think off | 1.37 s | 0.54 s |
| Short question, think on | 37.35 s | 3.89 s |
| Long prompt (~1500 characters), cold | ~1.70 s | ~1.07 s |
| Full 18-question suite (warm) | 49 s | **18 s** |

---

## 7. Method and limitations

**What was done**

- All 18 questions are auto-gradable; code questions are **really executed** inside a restricted
  `builtins` namespace (`import`/`eval`/`open` etc. disabled).
- Every question was run twice, to separate "capability gap" from "random variation"; 17 of 18
  questions gave identical results across rounds.
- Models were called serially, with an explicit `ollama stop` before switching, so that only one
  model was resident at a time.

**Limitations (do not over-extrapolate)**

1. Single machine, single session, small sample (18 questions x 2 rounds) — **not enough to give a
   statistical confidence interval**.
2. At `temperature=0` the output is still not fully deterministic (gemma4's `code_str` passed one
   round and failed the other).
3. The grader contains heuristics; 2 misjudgements were found and fixed, and more may remain. The
   hallucination question always requires human review.
4. This mostly reflects the **default think=off setting**; thinking changes the picture for reasoning.
5. Not tested: multi-turn dialogue, the upper bound of very long context, concurrent throughput,
   harder coding tasks.

---

## 8. Usage recommendations

| Scenario | Recommendation |
|---|---|
| Extraction / classification / JSON / well-formed short tasks | Either, but **prefer gemma4** (2–4x faster, lower latency) |
| Tool calling / agent tool chains | Either; both emit compliant output |
| Image OCR / visual Q&A | Either |
| Audio transcription | **gemma4 only**, and the audio must go in the `images` field |
| Multi-step maths / logical reasoning | **Neither**; if you must, turn thinking on and **use gemma4** |
| Strict JSON Schema enforcement | Unsupported by the platform; you need prompt constraints plus validate-and-retry |

---

## Appendix: artefact inventory

Relative to the (unpublished) development workspace. The test scripts and raw output are not part
of this repository; only these conclusions are.

| File | Contents |
|---|---|
| `bench/run_bench.py` | test set and grader |
| `bench/speed.py` | TTFT / throughput tests |
| `bench/audio_test.py` | audio capability measurements |
| `bench/big_think.py` | large-budget thinking reproduction |
| `bench/out/results_off.json` | main set, round 1 raw output |
| `bench/out/results_off2.json` | main set, round 2 raw output |
| `bench/out/results_on.json` | think=on comparison |
| `bench/out/big_think.json` | large-budget retry |
| `bench/out/speed.json` | speed data |
| `bench/out/log_*.txt` | full logs per round |
| `bench/ctx_test.py` | long-context truncation check |

---

## Appendix 2: what this means for the tiny instance

This instance's configuration comes straight from the conclusions above, plus two follow-up
verifications.

### 1. Thinking must be switched off explicitly (biggest impact)

Ollama defaults to `thinking=on`, and a small model then spends its output budget on the chain of
thought. Measured in DSH headless on the same task:

| Configuration | Result |
|---|---|
| default (thinking on) | 1m20s, verbose answer |
| `reasoningEfforts: false` | ❌ no effect; reasoning still emitted |
| `reasoningEfforts: {none: none}` | ❌ rejected by the schema (level keys are a fixed enum) |
| `reasoningEfforts: {off: none}` | ❌ error: at least one non-`off` level is required |
| **`reasoningEfforts: {off: none, high: high}`** | ✅ **thinking off, 14s** |

Additional fact: **Ollama's native `think:false` has no effect on the `/v1` endpoint**; you must
send `reasoning_effort: "none"`. The `off: none` in `cordis.patch.yml` is exactly that mapping.

### 2. Long inputs are not silently truncated (an earlier worry, corrected)

`ollama ps` showed `CONTEXT 4096` at runtime, which once suggested long inputs would be cut off.
Measured with a 26,078-character input (14,463 / 18,466 tokens) and the key fact buried at the very
end, both models **processed it in full and hit the fact exactly**, with `prompt_eval_count` far
above 4096 — Ollama expands the window automatically.

So this instance **needs no** special handling to "prevent truncation"; the real context-management
concerns are **latency** (a long prompt takes 40s cold) and **attention**.

### 3. Remaining limitations

- **No native structured output**: the `format` parameter returns
  `{"error":"structured output is unavailable"}`, so JSON work on this instance needs prompt
  constraints plus external validation.
- **Weak multi-step reasoning**: on the 18 questions, multi-step backward inference scored 0/2 while
  single-step tasks scored 16/18. Complex work should be split into single steps externally.
- **Vision and tool calling are fine**: both models passed these consistently and can be used freely.

### 4. The tool surface had to be trimmed (follow-up measurement)

The factory layer mounts 14 tool families on the agent by default (`subagent`, `workflow`, `goal`,
`web`, `jobs`, `skill`, …), which is pure overhead for a 4B model: in a single session
`toolsTokens 4633` against `systemTokens 651` — the tool schemas take up 7x the context of the
system prompt. After trimming via `cordis.patch.yml`, reading the counts from
`storages/session_projcache` on the same task:

| Configuration | Tools left to the model | toolsTokens | systemTokens |
|---|---|---|---|
| factory default | 14 families | 4633 | 651 |
| disable `tool-*` only | 7 + `exit_plan_mode` | 1719 | 220 |
| also disable `plan-mode` | 7 | 1601 | 220 |
| **this instance: also keep `todo_write`** | **8** | **1815** | **220** |
| (for comparison) add `skill` back | 9 | 1898 | 220 |

Two conclusions:

- **Only the `tool-*` entries need disabling.** The service plugins `goal` / `subagent` /
  `workflow-ptc` / `web` / `skill` produce no tools themselves and add nothing to the system
  prompt: once the matching tool plugin is off, `systemTokens` drops from 651 to 220 in step, with
  no need to touch the service plugins.
- **A patch has no remove semantics.** A patch entry can only carry `id / name / config / group /
  disabled / inject / intercept / isolate` (see `$defs.patch` from
  `dsh --profile local --dump-config-schema`), so `disabled: true` is the only way to express "do
  not mount this". This profile's `package.json` mounts only `dsh-base` + `dsh-headless`; the plugin
  tree is expanded from those bundles, and there is no other manifest to edit.

**One more finding: gemma4 omits a required `bash` parameter.**
`bash` requires both `command` and `description`, while the sandbox-escalation fields
`sandbox_permissions` / `justification` sit in the same schema. Same task:

| Model | Behaviour |
|---|---|
| qwen3.5:4b | missed `description` on the first try, added it after reading the error ✅ |
| gemma4:e2b | filled in `justification` instead of `description` **4 times in a row**, then gave up ❌ |

After naming both required parameters in the system prompt (the `system-prompt` override in
`cordis.patch.yml`), gemma4 sent `description` on all **7** bash calls across two runs, with 0
missing-parameter errors. The cost is `systemTokens` rising from 220 to 259 (+39); `toolsTokens` is
unchanged.

`write` has the same failure mode, one level worse: gemma4 emits the long `content` value first and
then closes the JSON without appending the also-required `file_path`. It is intermittent and it is
*not* truncation — the arguments JSON parses cleanly, the key is simply absent. Over three attempts,
one failed (3.8 KB body) and two succeeded, one of them with a 4.2 KB body. The prompt now names
write's parameters and their order as well.

---

## Appendix 3: tool-surface test (2026-10-05)

One task per tool, run against the `local` profile with `gemma4:e2b-mlx` in an isolated copy of the
instance, reading tool calls and results out of the run's event stream.

| Tool | Result | Evidence |
|---|---|---|
| `glob` | ✅ | listed three `.md` files, including one in a subdirectory |
| `grep` | ✅ | located the single file containing a marker token |
| `read` | ✅ | returned the file body |
| `write` | ✅ | created `notes.md`; `file_path` was present this time |
| `edit` | ✅ | the file ended up as exactly `# Notes\nHELLO\nworld` |
| `todo_write` | ✅ | built a three-item list |
| `read_image` | ❌ → now fixed | see below |
| `bash` | **not verified** | the test shell could not nest `sandbox-exec`, so the sandbox backend refused every command. That is an artefact of where the test ran, not evidence about the profile |
| `present` | **not executed** | a UI-only tool that renders file cards. It is mounted in the `chat` profile, and there is no headless path to exercise it |

### `read_image` was dead: an undeclared input modality

The first attempt failed with:

```
Error: cannot read "picture.png" as an image:
model "gemma4:e2b-mlx" does not declare image input
```

pi-ai falls back to `DEFAULT_INPUT = ["text"]` for any model entry that omits the `input` field, and
`dsh-tool-fs` then refuses every image. These entries were hand-written and never declared it, so
the tool was silently unusable — **even though gemma4 does handle images**. The vision results
earlier in this report were obtained by calling Ollama directly, which never consults the profile,
so they could not have caught it.

Declaring `input: [text, image]` fixes it (`MODALITIES` is exactly `text | image`): the image now
reaches the model, which correctly identified the blue shape as a square.

**Counting is still unreliable.** On a synthetic image holding two red circles and one blue square,
gemma4 answered "three red circles" twice, and "four shapes in total". The `vision_count` pass
earlier in this report does not generalise — treat vision counting as content-dependent.

### Thinking is close to free, and necessary for reasoning

A multi-step word problem, gemma4, two runs each way, thinking switched with a `--patch` overlay
rather than by editing the profile:

| | Wall time | Output | Strictly correct |
|---|---|---|---|
| think off #1 | 7.2 s | `The calculation is:\n1. Total students: 3…` (cut off) | ✘ |
| think off #2 | 3.9 s | `I need to perform a mathematical calcula…` (cut off) | ✘ |
| **think high #1** | 7.1 s | `6` | **✓** |
| **think high #2** | 4.4 s | `6` | **✓** |

The session log confirms the switch took effect: the two `high` runs carry one reasoning block each,
the two `off` runs none.

On reasoning work thinking is therefore not merely nice to have — without it the model spent its
budget rambling and never emitted a usable answer. Nor did it cost wall time; on this sample it was
slightly *faster*, because the unthinking runs burn tokens going nowhere. `n=2`: do not over-read it.

Because of this the `chat` profile sets `reasoningEffort: high` on `agent-default-model`, while
`local` stays off — one is a conversation UI, the other a batch one-shot runner.
