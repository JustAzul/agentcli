#!/usr/bin/env bash
# Checks that the plugin's mod loads and mounts its `agentcli` interface in a
# real Claude Code process, without spending on a model: the main model named
# below does not exist, so the process fails after the plugins have loaded, and
# the load is read from the debug log. Run it before every push that touches
# plugin/: a module that does not load takes every hook of the plugin with it,
# and the plugin tests cannot see that for a plugin's own interface.
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

work=$(mktemp -d "${TMPDIR:-/tmp}/agentcli-verify.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/cwd" "$work/home"
log=$work/claude.debug

# Nothing of the user's: only the project's settings, no session kept, no MCP
# servers, no tools, and an agentcli home of its own for the hooks that run it.
(
  cd "$work/cwd" || exit 2
  AGENTCLI_HOME=$work/home AGENTCLI_NO_LINK=1 AGENTCLI_PRICES_URL=off \
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
# The interface is mounted: the engine.create line names it with its methods.
grep -E -q 'engine\.create: .*\$\.agentcli \(agentcli: [a-z, ]*complete' "$log"
if [ $? -ne 0 ]; then
  echo "verify-plugin: the log does not show the agentcli interface mounted" >&2
  status=1
fi
# The module loaded and hooks the interface's event.
grep -E -q 'hooks module agentcli@[^ ]+ loaded .*events: [^ ]*agentcli\.complete' "$log"
if [ $? -ne 0 ]; then
  echo "verify-plugin: the log does not show the agentcli hooks module loaded with agentcli.complete" >&2
  status=1
fi
# No line says the agentcli module failed to load or was unloaded.
grep -E -i 'agentcli.*(did not load|failed to load|was unloaded)|(did not load|failed to load|was unloaded).*agentcli' "$log" >"$work/failures"
case $? in
  0)
    echo "verify-plugin: the log reports the agentcli module failing to load:" >&2
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
  echo "verify-plugin: ok, the agentcli interface is mounted"
else
  kept=${TMPDIR:-/tmp}/agentcli-verify-plugin.debug
  cp "$log" "$kept" && echo "verify-plugin: the debug log is kept at $kept" >&2
fi
exit "$status"
