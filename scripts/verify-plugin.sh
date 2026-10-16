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
# usage: scripts/verify-plugin.sh [plugin-dir]
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

# Nothing of the user's: only the project's settings, no session kept, no MCP
# servers and no tools.
(
  cd "$work/cwd" || exit 2
  CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 \
    claude -p "ok" --plugin-dir "$plugin" --setting-sources project --no-session-persistence \
    --strict-mcp-config --settings '{"advisorModel": ""}' --tools "" \
    --model claude-no-such-model --debug-file "$log"
) >"$work/stdout" 2>"$work/stderr"

if [ ! -s "$log" ]; then
  echo "verify-plugin: claude wrote no debug log; stderr:" >&2
  cat "$work/stderr" >&2
  exit 1
fi

status=0
# The module loaded and hooks the events it answers.
grep -E -q 'hooks module msgate-agents@[^ ]+ loaded .*events: .*session\.start.*agent\.offer' "$log"
if [ $? -ne 0 ]; then
  echo "verify-plugin: the log does not show the msgate-agents hooks module loaded with session.start and agent.offer" >&2
  status=1
fi
# Session start ran: the six types are registered.
registered=$(grep -E -c '\$\.agent\.register \(msgate-agents\): msgate-agents:(second-opinion|code-review|cross-check|expert-persona|delegation|adhoc) listed' "$log")
if [ "$registered" != "6" ]; then
  echo "verify-plugin: the log shows $registered of the 6 agent types registered" >&2
  status=1
fi
# No engine is installed here, so the plugin says so, once.
needed=$(grep -E -c '\$\.ui\.toast \(msgate-agents\): msgate-agents needs the msgate engine plugin 1\.x' "$log")
if [ "$needed" != "1" ]; then
  echo "verify-plugin: expected the one 'needs the msgate engine' toast without an engine, saw $needed" >&2
  status=1
fi
# No line says the module failed to load, was unloaded or had a hook skipped.
grep -E -i 'msgate-agents.*(did not load|failed to load|was unloaded|hook was skipped)' "$log" >"$work/failures"
case $? in
  0)
    echo "verify-plugin: the log reports the msgate-agents module failing:" >&2
    head -n 5 "$work/failures" >&2
    status=1
    ;;
  1) ;;
  *)
    echo "verify-plugin: could not search the log" >&2
    status=1
    ;;
esac

if [ "$status" -eq 0 ]; then
  echo "verify-plugin: ok, the msgate-agents module loaded and the six agent types registered with no engine present"
else
  kept=${TMPDIR:-/tmp}/msgate-agents-verify-plugin.debug
  cp "$log" "$kept" && echo "verify-plugin: the debug log is kept at $kept" >&2
fi
exit "$status"
