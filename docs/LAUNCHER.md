# Launching the tiny harness

Three ways in: a double-clickable launcher for the browser UI, a terminal REPL, and the plain `dsh`
command line for headless one-shot tasks. This page covers all three, plus what the launcher does.

---

## 1. The launcher

[`Launch Tiny.command`](../Launch%20Tiny.command) sits in the repository root. Double-click it in
Finder and the harness starts in a Terminal window, then opens the Web UI in your default browser.

It also runs from a shell:

```sh
./Launch\ Tiny.command
```

**The Terminal window it opens is the server.** Closing that window (or Ctrl-C) stops the harness.
That is deliberate: you can see the log, and stopping it needs no second command.

### What it checks before booting

In order, stopping with a readable message if any of them fails:

| Check | Why |
|---|---|
| the `dsh` CLI exists | it is inside the macOS app bundle, not on `PATH` |
| a browser-UI profile is present | see [Which profile](#3-which-profile-the-launcher-needs) |
| Ollama answers on `127.0.0.1:11434` | otherwise it tries `ollama serve` and waits 10 s |
| the profile's default model is pulled | `ollama list`, so you get a name to pull rather than a model error later |
| port `3099` is free | a second instance cannot bind it, and the failure would otherwise be cryptic |

### Stopping it

Close the Terminal window, or press Ctrl-C in it. On the next launch the port check passes again.

---

## 2. Desktop shortcut

The repository root is not a convenient place to keep clicking, so put a shortcut on the Desktop:

```sh
ln -s "$PWD/Launch Tiny.command" ~/Desktop/Tiny.command
```

The launcher resolves its own symlinks, so a shortcut does not break `DSH_HOME` — it still boots the
repository it lives in.

> If Finder declines to run the shortcut (double-click does nothing), that is macOS refusing to
> execute a symlink. Copy the file instead of linking it — the only thing that changes is that you
> have to edit the path inside it if the repository ever moves:
>
> ```sh
> cp "Launch Tiny.command" ~/Desktop/Tiny.command
> ```

---

## 3. Which profile the launcher boots

The launcher boots a profile that serves the **browser UI**, because that is what a click-to-start
app can mean — a headless profile takes a task as an argument and has nothing to show.

| Profile | Kind | Started by |
|---|---|---|
| `local` | headless — answers one task, exits | the command line, with a task (§4) |
| `chat` | browser UI, thinking on | this launcher |

`chat` ships in this repository at [`profiles/chat/`](../profiles/chat/). It is the same local
Ollama setup and the same eight tools as `local`, composed from `@deepseek-ai/dsh-base` +
`@deepseek-ai/dsh-web-app` instead of `dsh-headless`. Two differences are worth knowing:

- **Thinking is on** (`reasoningEffort: high`). A conversation is read by a human rather than
  batched, so quality beats throughput — but the cost is roughly 5× wall time on tool-using steps
  (per-call median 3.5 s → 5.7 s). That trade is right here and wrong in `local`. The numbers are
  in [appendix 4 of the evaluation report](../profiles/local/docs/LOCAL-MODEL-EVAL.md).
- **The tool set lives in the agent preset**, not in the top-level entries. The web app selects a
  preset, so the `disabled:` list at the top of `chat`'s patch is inert there; its
  `preset-standard` block is what actually trims the tools.

The launcher checks that the profile directory exists **and** that its `package.json` mounts
`@deepseek-ai/dsh-web-app`. Pointing it at a headless profile stops with a readable message instead
of failing later on `--port`.

Set `TINY_PROFILE` to boot a differently-named browser-UI profile:

```sh
TINY_PROFILE=web ./Launch\ Tiny.command   # the shipped DSH web profile
```

If `profiles/chat/` is missing (you deleted it, say), the launcher stops and names the path.
Rebuild it with:

```sh
DSH_HOME="$PWD" dsh chat --from-default-profile web
```

then copy the `llm-pi-ai` and `agent-default-model` blocks back in from
[`profiles/local/cordis.patch.yml`](../profiles/local/cordis.patch.yml).

---

## 4. The command line (headless)

No launcher needed — `local` answers one task and exits:

```sh
cd "$(git rev-parse --show-toplevel)"
DSH_HOME="$PWD" dsh --profile local "list the files in the current directory"
```

`dsh` is not on `PATH` when only the macOS app is installed:

```sh
DSH_HOME="$PWD" \
  "/Applications/DeepSeek Harness.app/Contents/Resources/runtime/cli/bin/dsh" \
  --profile local "list the files in the current directory"
```

Useful flags, all of which must come **after** the launcher flags and **before** the task:

| Flag | Effect |
|---|---|
| `--json` | newline-delimited run events (tool calls, token usage) instead of just the answer |
| `--session-id <id>` | continue an existing session |
| `--patch <file>` | apply an extra patch layer for this run only |

---

## 5. Overrides

| Variable | Default | Meaning |
|---|---|---|
| `DSH_BIN` | the macOS app bundle path | the `dsh` CLI to run |
| `TINY_PROFILE` | `chat` | profile to boot; must be a browser-UI profile |
| `TINY_PORT` | `3099` | listen port |

Running without a sandbox backend? `bash` will refuse every command. See the note at the end of
[`LOCAL-MODEL-EVAL.md`](profiles/local/docs/LOCAL-MODEL-EVAL.md) — the browser UI additionally has
an approval prompt, so the headless path is the one that needs `DSH_PERMISSION_MODE`.

---

## 6. The terminal chat — `tiny`

[`bin/tiny`](../bin/tiny) is a REPL that keeps a conversation alive in the shell. It talks to the
**headless** profile (`local`), one `dsh` process per turn, and continues the conversation with
`--session-id` — the same multi-turn behaviour the browser UI has, without a browser and without
thinking switched on.

```sh
./bin/tiny                       # start a conversation in the current directory
./bin/tiny "one-shot question"   # answer once and exit
```

To get it as a plain command:

```sh
mkdir -p ~/.local/bin
ln -sfn "$PWD/bin/tiny" ~/.local/bin/tiny
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
```

### Commands

| Command | Effect |
|---|---|
| `/new` | start a new conversation in this directory |
| `/model` | list the models the profile registers, marking the current one |
| `/model <id>` | switch model for the rest of the session |
| `/model reset` | back to the profile's default model |
| `/sessions` | the 15 most recent conversations, with title, age and directory |
| `/sessions <n>` | switch to one of them |
| `/help`, `/exit` | the obvious |

Tool calls print as they happen (`⚙ grep {"pattern": "TODO", …}`), failures in red, and the answer
at the end with wall time and token counts.

### How it works

- **State** lives in `~/.tiny-repl/`: `state.json` (the current session per working directory, plus
  the selected model) and `model.yml`, a one-entry patch layer rewritten whenever `/model` changes.
- **Sessions are per directory.** dsh refuses to adopt a session recorded elsewhere
  (`session "…" was recorded in "/a", not "/b"`), so each directory keeps its own current
  conversation, and `/sessions <n>` refuses to jump to one held in another directory.
- **`/model` only offers registered models** — the list is read out of the profile's
  `llm-pi-ai` → `models`. Add a model there before switching to it.
- It exits rather than guessing if `TINY_PROFILE` names a browser-UI profile, which does not accept
  `--json`.

| Variable | Default | Meaning |
|---|---|---|
| `DSH_BIN` | the macOS app bundle path | the `dsh` CLI to run |
| `TINY_PROFILE` | `local` | profile to chat through — must be a **headless** one |
| `TINY_STATE_DIR` | `~/.tiny-repl` | where the session and the model choice are kept |

---

## 7. Troubleshooting

| Symptom | Cause |
|---|---|
| `profile "chat" does not exist` | `DSH_HOME` is unset or points elsewhere — the launcher sets it, a manual `dsh` call must too |
| the browser opens but the page is `401` | the token is in the printed URL; a bookmark from a previous run will not work, the token changes every start |
| `端口 3099 已被占用` | an earlier instance is still running — find its Terminal window, or `TINY_PORT=3098` |
| the window flashes and disappears | a check failed; run it from a Terminal (`./Launch\ Tiny.command`) to read the message |
| `✗ 找不到 dsh` | the app is not at the default path — `export DSH_BIN=/path/to/dsh` |
