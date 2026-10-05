# tiny — a DeepSeek Harness instance for local Ollama small models

A minimal **[DeepSeek Harness](https://www.deepseek.com/harness/) (DSH)** instance whose agent runs
entirely on small models served by a local [Ollama](https://ollama.com). No cloud API key, no
third-party plugins.

**This project is built on the DeepSeek Harness plugin system.** It is not a fork and ships no
runtime code of its own: it is two DSH *profiles*, each composed from factory plugin bundles plus
one patch layer.

| Profile | What it is | Started by |
|---|---|---|
| [`local`](profiles/local/) | headless — answers one task and exits | `dsh --profile local "…"` |
| [`chat`](profiles/chat/) | browser UI, thinking on | [`Launch Tiny.command`](Launch%20Tiny.command) |

Both mount the same local Ollama provider and the same eight tools. `chat` reaches its tool set
through the web app's agent preset rather than the top-level entries, and is the one that carries a
UI; `local` is the batch runner and is what every measurement here is about.

Everything here was tuned against measurements taken on an Apple M4 / 16 GB with
`gemma4:e2b-mlx`, so the defaults target 2–8 B parameter models rather than frontier models.

## Quick start

**This repository is not standalone.** It is a profile *for* DeepSeek Harness, and nothing here
bundles or redistributes DSH. You need:

1. **[DeepSeek Harness](https://www.deepseek.com/harness/) (DSH) installed** — the `dsh` CLI
   together with the
   `@deepseek-ai/dsh-base` and `@deepseek-ai/dsh-headless` plugin bundles it ships.
2. A running **Ollama** — on **Apple Silicon (macOS)** if you want the default model. Linux and
   CPU-only machines need a different model tag; see [Platform support](#platform-support).
3. The models pulled:

```sh
ollama pull gemma4:e2b-mlx   # the default model — Apple Silicon only
ollama pull qwen3.5:4b-mlx   # optional second model, likewise Apple Silicon only
```

Then clone and run. **`DSH_HOME` must point at this repository root** — the repo *is* the harness
instance, and the profile lives at `profiles/local/`:

```sh
git clone git@github.com:VMoonLightV/dsh-tiny.git tiny
cd tiny
DSH_HOME="$PWD" dsh --profile local "list the files in the current directory"
```

If `dsh` is not on your `PATH` (the macOS app ships it inside the bundle), call it by full path:

```sh
DSH_HOME="$PWD" \
  "/Applications/DeepSeek Harness.app/Contents/Resources/runtime/cli/bin/dsh" \
  --profile local "list the files in the current directory"
```

Inspect the composed configuration without booting anything:

```sh
DSH_HOME="$PWD" dsh --profile local --dump-config
```

### Or double-click it

[`Launch Tiny.command`](Launch%20Tiny.command) in the repository root starts the harness in a
browser instead of answering one task. Double-click it in Finder, or:

```sh
./Launch\ Tiny.command
```

It needs a **browser-UI profile**, which is not what `local` is — see
[`docs/LAUNCHER.md`](docs/LAUNCHER.md) for what it checks, the `DSH_BIN` / `TINY_PROFILE` /
`TINY_PORT` overrides, how to put it on the Desktop, and how to build the `chat` profile it expects.

## Platform support

**The default model is Apple Silicon only.** `gemma4:e2b-mlx` and `qwen3.5:4b-mlx` are MLX builds,
which run on Apple Silicon GPUs — and they are what every measurement in this repository was taken
on.

On Linux, or on any machine without an Apple Silicon GPU, pull a non-MLX tag of the same model and
point the profile at it:

```sh
ollama pull gemma4:e2b-it-q4_K_M
```

then change the `model` field of the `agent-default-model` entry in
[`profiles/local/cordis.patch.yml`](profiles/local/cordis.patch.yml) to `gemma4:e2b-it-q4_K_M`.

Everything else in the profile — the eight-tool surface, thinking off, the system-prompt hint — is
platform-independent. Only the weights change; the throughput and latency figures in the evaluation
report are specific to MLX on an M4 and will not transfer.

## What the profile changes

Every deviation from the factory layer lives in one file,
[`profiles/local/cordis.patch.yml`](profiles/local/cordis.patch.yml). Four decisions:

| Decision | Why |
|---|---|
| Route the agent at `ollama/gemma4:e2b-mlx` (a second model, `qwen3.5:4b-mlx`, stays registered) | gemma4 is 2–4x faster on short tasks — full 18-question suite: 18 s vs 49 s |
| Switch **thinking off**: `reasoningEfforts: {off: none, high: high}` | Ollama defaults to `thinking=on`, which spends the whole output budget on the chain of thought (same task: 1m20s → 14s) |
| Trim the tool surface from 14 families to **8 tools** | the tool schemas cost 4633 tokens against a 651-token system prompt — 7x the context |
| Name `bash`'s two required parameters in the system prompt | without it, gemma4 fills in `justification` instead of the required `description` on 4 out of 4 attempts |

The eight tools are `bash`, `read`, `write`, `edit`, `read_image`, `glob`, `grep`, `todo_write`.

Result, read from `storages/session_projcache` on the same task:

| | toolsTokens | systemTokens |
|---|---|---|
| factory default | 4633 | 651 |
| **this profile** | **1815** | **259** |

To run a different local model, change the `model` field of the `agent-default-model` entry — as
long as that model id is registered in the `llm-pi-ai` models list in the same file.

## Layout

```
.
├── Launch Tiny.command                 double-click launcher for the browser UI
├── profiles/local/                     the headless profile — the batch runner
│   ├── package.json                    bundles: @deepseek-ai/dsh-base + @deepseek-ai/dsh-headless
│   ├── cordis.yml                      composition root, always []
│   ├── cordis.patch.yml                every deviation from the factory layer, commented
│   ├── pnpm-workspace.yaml
│   └── docs/
│       ├── LOCAL-MODEL-EVAL.md         model evaluation report (English)
│       └── LOCAL-MODEL-EVAL.zh-CN.md   same report (Chinese)
├── profiles/chat/                      the browser-UI profile
│   ├── package.json                    bundles: @deepseek-ai/dsh-base + @deepseek-ai/dsh-web-app
│   ├── cordis.yml
│   └── cordis.patch.yml                same Ollama setup; thinking on; tool set via agent preset
├── docs/
│   └── LAUNCHER.md                     what the launcher checks, overrides, troubleshooting
├── sessions/                           runtime state — git-ignored, created on first run
├── storages/                           runtime state — git-ignored, created on first run
├── attachments/                        runtime state — git-ignored, created on first run
└── .gitignore
```

## Read this before trusting the defaults

[`profiles/local/docs/LOCAL-MODEL-EVAL.md`](profiles/local/docs/LOCAL-MODEL-EVAL.md) is the
selection rationale behind every line of the patch, and the source of the numbers above. Its key
limitations, in short:

- **No native structured output.** For these MLX models Ollama's `format` parameter returns
  `{"error": "structured output is unavailable"}`. JSON has to come from prompt constraints plus
  external validation.
- **Multi-step reasoning is weak.** Both models scored 16/18 on the suite, but multi-step backward
  inference scored 0/2. Split complex work into single steps from the outside.
- **Both models are 4B-class.** They are reliable at extraction, classification, JSON, tool calling
  and OCR; they are not a substitute for a frontier model.
- **Thinking stays off on purpose.** Turning it on changes the picture — and on qwen it collapses
  into a reasoning loop (16k-token budget, 45k characters of chain, still no answer).

## Portability

The profile is self-contained: its dependencies are either relative (`link:./plugins/...`) or come
from the factory layer, so `profiles/local/` can be dropped into any `$DSH_HOME/profiles/` and
booted. The only local assumption is the Ollama endpoint, `http://127.0.0.1:11434/v1`.

Never commit `sessions/`, `storages/`, `.anonymous-user-id` or `.credentials.yaml` — `.gitignore`
already excludes all four.

## License

[MIT](LICENSE) © 2026 VMoonLightV

That covers the contents of this repository — the profile configuration, the documentation and the
evaluation report. It does not cover DeepSeek Harness itself, which is distributed separately under
its own terms.
