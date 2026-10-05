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

---

## Appendix 4: `gemma4:e4b-mlx` vs `gemma4:e2b-mlx` (2026-10-05)

`gemma4:e4b-mlx` was added to Ollama afterwards and put through the identical prompt set, with the
same profile, the same tools and the same nine tasks, so the two models are directly comparable.

| | `gemma4:e2b-mlx` | `gemma4:e4b-mlx` |
|---|---|---|
| parameters | 5.2 B | 8.1 B |
| size on disk | 7.5 GB | 9.5 GB |
| context / quantisation | 131 072 / nvfp4 | 131 072 / nvfp4 |
| capabilities | completion, vision, audio, tools, thinking | same |

Both models were injected with `--patch` overlays rather than by editing this profile, and
`reasoningEffort` was left unset (= thinking off, matching what `local` ships) except where stated.
Every run below is a separate process against a fresh copy of the fixture tree.

### 1. Tool surface, one task per tool

| Task | `e2b` | `e4b` |
|---|---|---|
| `glob` *.md | ✅ 3.1 s | ✅ 7.3 s |
| `grep` TODO in a file | ✅ 4.8 s | ✅ 7.8 s |
| `read` a specific line | ✅ 5.8 s | ✅ 7.5 s |
| `write` a one-line file | ⚠️ file landed, then `EMPTY_RESPONSE` (exit 1) 20.3 s | ✅ after one rejected call 14.8 s |
| `edit` one word | ✅ after a blocked whole-file rewrite 6.6 s | ✅ after three rejected calls 17.9 s |
| three-step `read`→count→`write` | ✅ 5.6 s | ❌ 22.9 s |
| `read_image`: 2 red circles + 1 blue square | ❌ 6.0 s | ✅ 8.8 s |
| `read_image`: OCR of `HARBOR 7391` | ✅ 4.9 s | ✅ 8.2 s |
| `bash pwd` | ❌ no usable sandbox backend | ❌ same |

Mean wall time over the nine runs above: **6.9 s (`e2b`) vs 11.6 s (`e4b`) — e4b is ~1.7× slower.**

Because single runs say little, the three tasks that separated the models were repeated three
times each:

| Task, three repetitions | `e2b` | `e4b` |
|---|---|---|
| count the shapes (2 red circles, 1 blue square) | 1/3 correct | **3/3 correct** |
| three-step file task → `count.txt` | **3/3 correct** | 0/3 |
| `write` a one-line file | 3/3 files written | 2/3 files written |

Pooled with the first round and with a second repetition inside the real workspace: **the three-step
task is 6/6 for `e2b` and 0/8 for `e4b`** (the extra `e4b` runs were with the permission mode that
lets `bash` run, in case the unusable shell was the real cause — it was not). That is the sharpest
difference in this whole report, and it is not a knowledge difference — it is the escalation trap
below.

#### Token throughput

Measured straight against the Ollama API (`prompt_eval_count`/`prompt_eval_duration` and
`eval_count`/`eval_duration`), outside the harness, medians over three to four runs:

| | prefill @200 tok | prefill @2 600 tok | decode |
|---|---|---|---|
| `e2b` | 2 618 t/s | 2 185 t/s | **70 t/s** |
| `e4b` | 684 t/s | 621 t/s | **50 t/s** |

That asymmetry is the interesting part. `e4b` is 1.56× the parameters but its **prefill is 3.5×
slower**, while its **decode is only 1.4× slower**. Prefill is the number that matters here: `local`
sends ~2 100 tokens of system prompt and tool schemas on *every* call, so the floor under each step
is roughly **0.9 s for `e2b` and 3.3 s for `e4b`** before a single token is generated.

Reading the LLM-call latency out of the session logs (`request/header` → `assistant/message`) confirms
it. Eight one-tool runs, 16 calls:

| | median | mean |
|---|---|---|
| `e2b` | 3.48 s | 3.60 s |
| `e4b` | 6.80 s | 6.99 s |

**1.95× per call** — worse than the 1.7× end-to-end figure, because end-to-end also contains process
startup and tool execution, which cost the same for both models. `e4b` additionally writes more per
step, which is where the remaining gap sits between 1.4× decode and 1.95× per call.

One non-finding: turning thinking on *raises* the measured decode rate slightly (`e2b` 70 → 86 t/s,
`e4b` 50 → 57 t/s). That is an artefact of longer generations amortising per-token overhead, not a
real speed-up — reasoning tokens are generated at the same rate as any other token.

### 2. The escalation trap: `justification` without `sandbox_permissions`

`write`, `edit` and `bash` advertise two optional-looking escalation parameters,
`sandbox_permissions` and `justification`. Supplying `justification` **alone** is always rejected:

```
Error: invalid escalation: justification is only valid together with sandbox_permissions
```

Both models fall into this, but they behave completely differently once they do:

- **`e2b`** either omits both fields or sends the pair together, so its calls go through.
- **`e4b`** sends `justification` alone, is rejected, and then **retries the same malformed call
  almost verbatim**. On the worst run it made **19 tool calls and burned 58.5 s and 23 922 context
  tokens without ever creating the file**, then died with `EMPTY_RESPONSE`. It never once paired the
  two fields. On other runs it ends by asserting the file was created when it was not.

Counting every tool call over the 40 prompt-sets that both models ran (environmental failures — the
unusable sandbox backend — excluded):

| | tool calls | self-inflicted errors | failed calls | `invalid escalation` |
|---|---|---|---|---|
| `e2b` | 78 | **9** | 12 % | 0 |
| `e4b` | 115 | **82** | **71 %** | 40 |

That is the whole difference in one table. `e4b` does not misunderstand the tasks — it fails
argument validation, then keeps re-sending the same shape with the wording changed. Of its 82
self-inflicted errors, 40 are `invalid escalation` and 35 are `bash` calls missing `description`: the
same trap one field over. `e2b` logged **zero** escalation errors. The remaining errors are shared
and mundane (7 reads of a file that had not been written yet, 1 write before read, 1 image read as
text).

### 2b. Prompting cannot fix it

The fields cannot be removed from the schema. `dsh-tool-fs` advertises them whenever a confining
backend is mounted (`...sandbox.escalationModes.length > 0 ? sandbox.schemaFields() : {}`), and
disabling either `fs-sandbox` or `sandbox-policy` to suppress the advertisement takes the whole file
tool set down with it: `write` then answers `unknown tool "write"`, and `bash`, `read` and `grep`
never mount at all. So the trap had to be attacked with text — four variants, five repetitions each
on the three-step task:

| variant | added to `personaSuffix` | `e4b` three-step | `e4b` `write` |
|---|---|---|---|
| v0 (shipped) | — | **0/8** | 4/6 |
| v2 | the `justification`/`sandbox_permissions` pairing rule | 1/5 | 2/2 |
| v3 | + "if a call errors, change the arguments; never repeat it" | 0/5 | 2/2 |
| v4 | + "create or modify files with write/edit, never shell redirection" | 0/5 | 2/2 |
| v5 | + a worked example of the exact call to make | 0/5 | 2/2 |

**One success in twenty attempts.** The same sentences do not hurt `e2b` (three-step 3/3 under v4).
An earlier revision of this appendix reported this as 0/8 → 2/2 — that came from a two-run sample and
is **retracted**; at five repetitions the effect is gone.

The transcripts show why. Each of those four sentences is ignored in the same way:

- v4 says *never shell redirection* → `e4b` runs `echo "4" > count.txt`.
- v3/v4 say *do not repeat an erroring call, change the arguments* → it re-sends the identical call,
  editing only the wording of `justification`.
- The pairing rule is stated in prose → it still sends `justification` alone.
- The error text names the missing field verbatim → it does not act on it.

The cleanest demonstration came out of the failed attempt to remove the trap by disabling
`fs-sandbox`. With `write` gone and only `bash` left, `e4b` sent `{"command": …, "justification": …}`
**six times without `description`**, and narrated:

> I must adhere strictly to the syntax: `bash(command: "...", justification: "...")`

It invented a tool signature, obeyed its own invention over both the schema and the system prompt,
and then reported the file as created. **The limitation is not knowing what to do — it is updating
the next tool call from the previous tool result.** No `personaSuffix` can supply that.

### 2c. What does move the needle: thinking

Thinking gives the model a scratchpad in which to reconsider, and it is the one intervention with
evidence behind it:

| `e4b`, three-step task | result |
|---|---|
| thinking off, shipped prompt | 0/8 |
| thinking off, v2 / v3 / v4 / v5 | 1/5, 0/5, 0/5, 0/5 |
| **thinking high, shipped prompt** | **2/5** |

In the run that passed, `e4b` reworded `justification` once, was rejected, and on the next call
**dropped the field entirely** — a genuinely different shape, which is exactly what it never did with
thinking off. It still costs: 23–59 s per run against 13–25 s, and 2/5 is nowhere near `e2b`'s 6/6.

### 2d. What thinking actually costs, once tools are involved

Appendix 3 concluded that thinking was "close to free". That held for a single-step text answer, where
the unthinking run rambles through the same token budget anyway. It does **not** hold once tools are in
play, because the agent thinks again on **every step**. Same four tool tasks, `e2b`, read out of the
session logs:

| | per-call median | per-call mean | steps carrying a reasoning block |
|---|---|---|---|
| thinking off | 3 478 ms | 3 603 ms | 0 / 8 |
| thinking high | 5 700 ms | 6 852 ms | **8 / 8** |

And on a composite task (read `data.csv` → sum the `qty` column → write `sum.txt`), which needs both a
tool plan and arithmetic:

| | success | tool calls | output tokens | wall time |
|---|---|---|---|---|
| thinking off | 2/3 | 2–4 | 99–502 | 3–8 s |
| thinking high | **2/3** | 4–6 | 1 662–2 400 | 24–34 s |

**Identical success, ~5× the wall time, 5–10× the output tokens.** Reasoning blocks measured
200–3 000 characters each, and every step paid for one. So "thinking is free" is true only of a
one-shot text answer; for the tool-using work `local` exists to do it is the most expensive knob in
the profile. That is what settles the split — `local` stays off, `chat` stays high.

---

### 3. Vision: the one clear capability win

On the same synthetic image (two red circles, one blue square) `e4b` was correct **4 times out of
4**; `e2b` was correct **1 time out of 4** and twice answered "three red circles". `e2b` also
sometimes reaches for `read` instead of `read_image` on a `.png` and then gets `binary file`, which
is what happened in its first shapes run — so part of the gap is tool selection, not perception.
The OCR image (`HARBOR 7391`) was transcribed exactly by both, twice each.

Counting remains content-dependent even for `e4b`; treat this as "e4b is better at images", not as
"e4b counts reliably".

### 4. Multi-step reasoning: no advantage

Three word problems with exact integer answers (7, 4, 27), two repetitions each, graded on the final
number:

| | thinking off | thinking high |
|---|---|---|
| `e2b` | 3/6 | 5/6 |
| `e4b` | 2/6 | 4/6 |

`e4b` is not better here, and at n=6 these differences are inside the noise. Both fail the same way:
the "give away half plus half an apple" problem is mis-modelled from the start, and the
thinking-off runs emit their chain directly into the answer channel. `e4b`'s unthinking output was
the worst in the set — one run emitted **2 674 output tokens** of tangled algebra and still answered
3.

The thinking switch behaves the same as before: the session log carries `reasoningEffort: "high"`
and one reasoning block per `high` run, and neither for the `off` runs. For `e4b`, turning thinking
on moved it from 2/6 to 4/6 at roughly the same cost — 11.4 s mean per run over six `high` runs
against 11.9 s over six `off` runs. That mean is dominated by whichever run pays for loading the
model, so read it as "no worse", not as "faster".

---

### 5. `bash` is finally verified

The `bash` tool was the one unresolved item from Appendix 3, blocked by this host having no usable
sandbox backend (`sandbox-exec: sandbox_apply: Operation not permitted`). Running the same profile
with the permission mode turned off closes it:

```sh
DSH_HOME=~/workspace/profiles/tiny DSH_PERMISSION_MODE=danger-full-access \
  dsh --profile local --patch ./e4b.yml "run pwd and tell me the output"
# tool_call bash {"command":"pwd","description":"Print the current working directory path"}
# tool_result completed "/tmp/e4btest\n"
# final: The output of the `pwd` command is `/tmp/e4btest`.
```

So `bash` works, and `e4b` sends `command` and `description` correctly when it is not distracted by
the escalation fields. The earlier failure was the host, not the profile — but note the consequence
for this profile as shipped: **on a host without a sandbox backend, `local` can read, write and
search but cannot execute anything**, because there is no mode in which the tool will run unconfined
without the caller opting in.

---

### 6. Recommendation

Keep `gemma4:e2b-mlx` as the default. `e4b` is 60 % larger, 1.7× slower end to end (1.95× per LLM
call), no better at reasoning, and it fails **71 % of its tool calls** against `e2b`'s 12 %. It is
registered as a third model in both profiles (`llm-pi-ai` in `profiles/local` and `profiles/chat`)
so the image case can be selected deliberately — and it should not be pointed at multi-step file
tasks under any prompt tried here.

Two conclusions follow from the experiments above:

1. **Do not try to prompt the escalation trap away.** Four variants, 20 runs, one success; the
   sentence that looked like it worked over two runs did not survive five. If `e4b` is going to be
   used at all, give it thinking — 0/8 → 2/5 is the only measured improvement, and it is still not
   close to `e2b`. The "tell it to use `write` instead of shell redirection" line was tried (v4) and
   changed nothing.
2. **The real fix is upstream in DSH, not in this profile.** `validateEscalationArgs` treats a lone
   `justification` as an error; ignoring a stray `justification` when `sandbox_permissions` is absent
   would remove the trap for every small model — and the model most likely to read a schema field
   description carefully is exactly the model that falls into it. The profile cannot express that
   change, and both ways of suppressing the schema fields cost the file tools.

One consequence of the investigation is worth keeping regardless of model choice: on a host with no
usable sandbox backend, `local` can read, write and search but **cannot execute anything** — `bash`
refuses to run unconfined and there is no profile-level setting that changes that, only the caller's
`DSH_PERMISSION_MODE`.
