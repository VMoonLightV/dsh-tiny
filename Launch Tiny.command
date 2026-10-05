#!/bin/bash
#
# Launch Tiny — double-click this file to start the tiny harness in your browser.
#
# It boots this folder as a DSH instance (DSH_HOME) and starts a browser-UI profile.
# The Terminal window it opens is the server: closing that window stops it.
#
# Environment overrides:
#   DSH_BIN       path to the dsh CLI   (default: the macOS app bundle)
#   TINY_PROFILE  profile to boot       (default: chat — must be a browser-UI profile)
#   TINY_PORT     listen port           (default: 3099)
#
# See docs/LAUNCHER.md.
#
set -u

# --- where this script really lives, so a Desktop shortcut works too ----------
SELF="$0"
while [ -L "$SELF" ]; do SELF="$(readlink "$SELF")"; done
TINY_DIR="$(cd "$(dirname "$SELF")" && pwd -P)"

export DSH_HOME="$TINY_DIR"
DSH_BIN="${DSH_BIN:-/Applications/DeepSeek Harness.app/Contents/Resources/runtime/cli/bin/dsh}"
PROFILE="${TINY_PROFILE:-chat}"
PORT="${TINY_PORT:-3099}"
OLLAMA="http://127.0.0.1:11434"

pause() { printf '\n按回车关闭这个窗口…'; read -r _; }
die()   { printf '\n✗ %s\n' "$1"; pause; exit 1; }

printf '\n  tiny harness — %s\n\n' "$TINY_DIR"

# --- dsh present? -------------------------------------------------------------
[ -x "$DSH_BIN" ] || die "找不到 dsh：$DSH_BIN
  如果 App 装在别处，先 export DSH_BIN=/path/to/dsh 再运行。"

# --- is the profile we are about to boot here, and does it serve a browser UI? --
if [ ! -d "$TINY_DIR/profiles/$PROFILE" ]; then
  die "档案 \"$PROFILE\" 不在这个仓库里：$TINY_DIR/profiles/$PROFILE
  这个启动器需要一个「浏览器界面」档案。仓库自带的 profiles/local 是 headless 的，
  不能这样启动。如何得到 chat 档案见 docs/LAUNCHER.md。"
fi
if ! grep -q 'dsh-web-app' "$TINY_DIR/profiles/$PROFILE/package.json" 2>/dev/null; then
  die "档案 \"$PROFILE\" 不是浏览器界面档案（它挂载的不是 @deepseek-ai/dsh-web-app）。
  它不接受 --port，这样启动会失败。
  headless 档案请用命令行：DSH_HOME=\"$TINY_DIR\" dsh --profile $PROFILE \"你的任务\"
  详见 docs/LAUNCHER.md。"
fi

# --- ollama up? ---------------------------------------------------------------
if ! curl -s -m 2 "$OLLAMA/api/tags" >/dev/null 2>&1; then
  printf '  Ollama 没在响应，正在启动…\n'
  (ollama serve >/dev/null 2>&1 &)
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    curl -s -m 2 "$OLLAMA/api/tags" >/dev/null 2>&1 && break
    sleep 1
  done
  curl -s -m 2 "$OLLAMA/api/tags" >/dev/null 2>&1 \
    || die "Ollama 起不来。请先在终端里运行： ollama serve"
fi
printf '  ✓ Ollama 就绪\n'

# --- default model pulled? ----------------------------------------------------
MODEL="$(grep -m1 '^    model: ' "$TINY_DIR/profiles/$PROFILE/cordis.patch.yml" 2>/dev/null \
         | sed 's/.*model: //' | tr -d ' ')"
MODEL="${MODEL:-gemma4:e2b-mlx}"
if ! ollama list 2>/dev/null | awk '{print $1}' | grep -qx "$MODEL"; then
  die "本地没有模型 $MODEL。先运行： ollama pull $MODEL"
fi
printf '  ✓ 模型 %s 就绪\n' "$MODEL"

# --- port free? ---------------------------------------------------------------
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  die "端口 $PORT 已被占用——很可能已经有一个 tiny 在跑。
  关掉那个终端窗口（或 kill 掉占用 $PORT 的进程）再启动。"
fi

# --- go -----------------------------------------------------------------------
printf '  ✓ 正在启动 Web UI（浏览器会自动打开）\n'
printf '    关掉这个终端窗口 = 停止服务\n\n'
cd "$DSH_HOME" || die "进不去 $DSH_HOME"
exec "$DSH_BIN" --profile "$PROFILE" --port "$PORT"
