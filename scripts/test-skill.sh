#!/bin/sh
# Checks the dispatch skill as text: it covers the six types, the engine's two
# tools and the CLI flags per purpose, carries trigger evals of both kinds, and
# names nothing of the engine's old identity.
#
#   scripts/test-skill.sh
set -u

root=$(cd "$(dirname "$0")/.." && pwd -P)
skill=$root/plugin/skills/dispatch
failures=0

pass() { echo "ok: $1"; }
fail() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }

has() { # <description> <fixed text>
  if grep -r -F -q -- "$2" "$skill/SKILL.md"; then pass "$1"; else fail "$1"; fi
}

for t in second-opinion code-review cross-check expert-persona delegation adhoc; do
  has "SKILL.md names msgate-agents:$t" "msgate-agents:$t"
  if grep -E -q "msgate (exec|review) --purpose $t( |\`)" "$skill/SKILL.md"; then pass "SKILL.md gives the CLI line for $t"; else fail "SKILL.md gives the CLI line for $t"; fi
done
has "SKILL.md names the run tool" 'mcp__msgate__run'
has "SKILL.md names the jobs tool" 'mcp__msgate__jobs'
has "SKILL.md shows explicit --model" '--model gpt-6.1-sol'
has "SKILL.md shows explicit --effort" '--effort xhigh'
has "SKILL.md shows explicit --sandbox" '--sandbox workspace-write'
has "SKILL.md covers cost awareness" 'msgate stats'

# Every CLI line of a purpose in the flag table names the sandbox; all but
# adhoc, which leaves them to the provider, name the model and the effort too.
table=$(grep -E '^\| `(second-opinion|code-review|cross-check|expert-persona|delegation|adhoc)` \| `msgate ' "$skill/SKILL.md")
if [ "$(printf '%s\n' "$table" | wc -l)" -ne 6 ]; then fail "the flag table does not hold the six purposes"; else pass "the flag table holds the six purposes"; fi
if printf '%s\n' "$table" | grep -v -- '--sandbox' >/dev/null; then fail "a purpose in the flag table has no --sandbox"; else pass "every purpose in the flag table names --sandbox"; fi
if printf '%s\n' "$table" | grep -v '`adhoc`' | grep -v -e '--model' -e '--effort' >/dev/null; then fail "a purpose in the flag table lacks --model or --effort"; else pass "every purpose but adhoc names --model and --effort"; fi
if printf '%s\n' "$table" | grep -v '`adhoc`' | grep -v -- '--effort' >/dev/null; then fail "a purpose in the flag table lacks --effort"; fi

old=$(grep -r -i -n -E 'agentcli|--scenario|scenario:' "$skill" | head -n 5)
if [ -n "$old" ]; then fail "the skill names the old identity:
$old"; else pass "the skill names no agentcli command, variable, interface or plugin id"; fi

evals=$skill/evals/evals.json
if [ "$(jq '[.[] | select(.should_trigger == true)] | length' "$evals")" -gt 0 ] && [ "$(jq '[.[] | select(.should_trigger == false)] | length' "$evals")" -gt 0 ]; then
  pass "evals hold queries that trigger and queries that do not"
else
  fail "evals lack one of the two kinds"
fi

[ "$failures" -eq 0 ]
