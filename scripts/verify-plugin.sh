#!/usr/bin/env bash
# Checks that the plugin's mod loads in a real Claude Code process, without
# spending on a model: the main model named below does not exist, so the
# process fails after the plugins have loaded, and the load is read from the
# debug log. Run it before every push that touches plugin/: a module that does
# not load takes every hook of the plugin with it, and the plugin tests cannot
# see that.
#
# The process has no msgate engine, so the check also shows the plugin loading
# without one: the six agent types register and the session is told, once, that
# the engine is missing.
#
# When MSGATE_ENGINE_DIR names an engine plugin directory (a dist build with
# .claude-plugin/plugin.json and bin/msgate), a second check loads both plugins
# the same way and shows the hidden run type registering beside the six, with no
# missing-engine notice. The engine directory is only read; its state goes to a
# temporary directory.
#
# usage: [MSGATE_ENGINE_DIR=<engine-dir>] scripts/verify-plugin.sh [plugin-dir]
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
plugin=${1:-$root/plugin}
if [ ! -f "$plugin/.claude-plugin/plugin.json" ]; then
  echo "verify-plugin: no plugin at $plugin" >&2
  exit 2
fi
if ! command -v claude >/dev/null 2>&1; then
  echo "verify-plugin: claude is not on PATH" >&2
  exit 2
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/msgate-agents-verify.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/cwd"
log=$work/claude.debug

# claude_load <log> <plugin-dir>...: starts claude with the plugins, in a
# directory of its own. Nothing of the user's: only the project's settings, no
# session kept, no MCP servers and no tools.
claude_load() {
  local out=$1 dirs=() dir
  shift
  for dir in "$@"; do dirs+=(--plugin-dir "$dir"); done
  mkdir -p "$work/cwd"
  (
    cd "$work/cwd" || exit 2
    CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 \
      claude -p "ok" "${dirs[@]}" --setting-sources project --no-session-persistence \
      --strict-mcp-config --settings '{"advisorModel": ""}' --tools "" \
      --model claude-no-such-model --debug-file "$out"
  ) >"$work/stdout" 2>"$work/stderr"
}

# has_log <log>: false, with the stderr of the run, when claude wrote no log.
has_log() {
  [ -s "$1" ] && return 0
  echo "verify-plugin: claude wrote no debug log; stderr:" >&2
  cat "$work/stderr" >&2
  return 1
}

# count_log <log> <pattern>: how many lines match.
count_log() {
  grep -E -c -- "$2" "$1"
}

# check_loaded <log>: the module loaded, hooking the events it answers, and no
# line says it failed, was unloaded or had a hook skipped. Returns 1 on a miss.
check_loaded() {
  local failed=0
  grep -E -q 'hooks module msgate-agents@[^ ]+ loaded .*events: .*session\.start.*agent\.offer' "$1"
  if [ $? -ne 0 ]; then
    echo "verify-plugin: the log does not show the msgate-agents hooks module loaded with session.start and agent.offer" >&2
    failed=1
  fi
  grep -E -i 'msgate-agents.*(did not load|failed to load|was unloaded|hook was skipped)' "$1" >"$work/failures"
  case $? in
    0)
      echo "verify-plugin: the log reports the msgate-agents module failing:" >&2
      head -n 5 "$work/failures" >&2
      failed=1
      ;;
    1) ;;
    *)
      echo "verify-plugin: could not search the log" >&2
      failed=1
      ;;
  esac
  return "$failed"
}

SIX_TYPES='(second-opinion|code-review|cross-check|expert-persona|delegation|adhoc)'
REGISTERED='\$\.agent\.register \(msgate-agents\): msgate-agents:'
MISSING_ENGINE='\$\.ui\.toast \(msgate-agents\): msgate-agents needs the msgate engine plugin 1\.x'

# keep_log <log> <name>: keeps the debug log of a failed check.
keep_log() {
  local kept=${TMPDIR:-/tmp}/$2
  cp "$1" "$kept" && echo "verify-plugin: the debug log is kept at $kept" >&2
}

# The plugin alone: the process has no msgate engine, so the check shows the
# plugin loading without one.
claude_load "$log" "$plugin"
has_log "$log" || exit 1

status=0
check_loaded "$log" || status=1
# Session start ran: the six types are registered.
registered=$(count_log "$log" "$REGISTERED$SIX_TYPES listed")
if [ "$registered" != "6" ]; then
  echo "verify-plugin: the log shows $registered of the 6 agent types registered" >&2
  status=1
fi
# No engine is installed here, so the plugin says so, once.
needed=$(count_log "$log" "$MISSING_ENGINE")
if [ "$needed" != "1" ]; then
  echo "verify-plugin: expected the one 'needs the msgate engine' toast without an engine, saw $needed" >&2
  status=1
fi

if [ "$status" -eq 0 ]; then
  echo "verify-plugin: ok, the msgate-agents module loaded and the six agent types registered with no engine present"
else
  keep_log "$log" msgate-agents-verify-plugin.debug
fi

# With an engine: both plugins load, the six types and the hidden run type
# register, and the plugin does not say the engine is missing.
if [ -z "${MSGATE_ENGINE_DIR:-}" ]; then
  echo "verify-plugin: engine check skipped, MSGATE_ENGINE_DIR is not set"
  exit "$status"
fi

engine=$MSGATE_ENGINE_DIR
if [ ! -f "$engine/.claude-plugin/plugin.json" ] || [ ! -x "$engine/bin/msgate" ]; then
  echo "verify-plugin: MSGATE_ENGINE_DIR is not an engine plugin directory (needs .claude-plugin/plugin.json and bin/msgate): $engine" >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "verify-plugin: jq is not on PATH" >&2
  exit 2
fi
# The engine only reads and writes under its own home, which is a temporary one
# here; it links no launcher, prunes nothing and fetches no price list.
export MSGATE_HOME=$work/msgate-home MSGATE_NO_LINK=1 MSGATE_NO_PRUNE=1 MSGATE_PRICES_URL=off

version=$("$engine/bin/msgate" version --json | jq -r '.version // empty')
case $version in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *)
    echo "verify-plugin: could not read the engine version from $engine/bin/msgate version --json" >&2
    exit 2
    ;;
esac
major=${version%%.*}
rest=${version#*.}
minor=${rest%%.*}
if [ "$major" -ne 1 ] || [ "$minor" -lt 1 ]; then
  echo "verify-plugin: the engine at $engine is version $version, below 1.1, which has no hidden run type to check" >&2
  exit 1
fi

engine_log=$work/claude-engine.debug
claude_load "$engine_log" "$plugin" "$engine"
has_log "$engine_log" || exit 1

engine_status=0
check_loaded "$engine_log" || engine_status=1
registered=$(count_log "$engine_log" "$REGISTERED$SIX_TYPES listed")
if [ "$registered" != "6" ]; then
  echo "verify-plugin: with the engine, the log shows $registered of the 6 agent types registered" >&2
  engine_status=1
fi
hidden=$(count_log "$engine_log" "${REGISTERED}run listed")
if [ "$hidden" != "1" ]; then
  echo "verify-plugin: with the engine, the log shows $hidden registrations of the hidden msgate-agents:run type, expected 1" >&2
  engine_status=1
fi
needed=$(count_log "$engine_log" "$MISSING_ENGINE")
if [ "$needed" != "0" ]; then
  echo "verify-plugin: with the engine, the plugin still says the engine is missing ($needed times)" >&2
  engine_status=1
fi

if [ "$engine_status" -eq 0 ]; then
  echo "verify-plugin: ok, with the engine $version the msgate-agents module loaded, the six agent types and the hidden run type registered and no engine notice was shown"
else
  keep_log "$engine_log" msgate-agents-verify-plugin-engine.debug
fi
if [ "$status" -ne 0 ] || [ "$engine_status" -ne 0 ]; then
  exit 1
fi
exit 0
