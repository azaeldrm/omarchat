# Choosing a model: the fallback through usable agents, the "no agent" state,
# the header label, saving a choice, the model list's reasons, and the marks
# on refused models. Uses stand-in backends, so nothing touches a real agent.

# shellcheck source=SCRIPTDIR/../lib.sh
source "$(dirname "$0")/../lib.sh"

plugin=$(plugin_copy)
for agent in claude pi; do
  cat >"$plugin/backends/$agent" <<'EOF'
#!/bin/bash
# Stand-in backend driven by STUB_<AGENT>_CHECK (empty: usable; "silent": fails
# without a reason; anything else: the reason) and STUB_<AGENT>_MODELS (lines).
agent=$(basename "$0")
check="STUB_${agent^^}_CHECK"
models="STUB_${agent^^}_MODELS"
case "${1:-}" in
check)
  [[ -z ${!check:-} ]] && exit 0
  [[ ${!check} == silent ]] || echo "${!check}"
  exit 1
  ;;
models) sed '/^$/d' <<<"${!models:-}" ;;
default) sed '/^$/d' <<<"${!models:-}" | head -1 ;;
paths) ;;
esac
EOF
  chmod +x "$plugin/backends/$agent"
done

export OMARCHAT_MODEL_FILE="$scratch/model"
export XDG_CACHE_HOME="$scratch/cache"
export STUB_CLAUDE_MODELS=$'{"id":"c1","name":"Claude One"}\n{"id":"c2","name":"Claude Two"}'
export STUB_PI_MODELS='{"id":"p/1","name":"Pi One","provider":"p"}'
model="$plugin/bin/omarchat-model"
models="$plugin/bin/omarchat-models"
tab=$'\t'

reset() {
  rm -f "$OMARCHAT_MODEL_FILE"
  rm -rf "$XDG_CACHE_HOME"
  unset STUB_CLAUDE_CHECK STUB_PI_CHECK
}

# Fallback when nothing has been chosen.
reset
assert_eq "nothing chosen: the first usable agent's default" "claude${tab}c1${tab}Claude One" "$("$model")"
assert_eq "header label names model and agent" "Claude One · Claude Code" "$("$model" --label)"

STUB_CLAUDE_CHECK="Not installed" assert_eq "first agent unusable: falls through to the next" \
  "pi${tab}p/1${tab}Pi One" "$(STUB_CLAUDE_CHECK="Not installed" "$model")"

export STUB_CLAUDE_CHECK="Not installed" STUB_PI_CHECK="Not logged in"
assert_eq "no usable agent: reports none" "none${tab}${tab}" "$("$model")"
assert_eq "no usable agent: the label says so" "No agent set up" "$("$model" --label)"
reset

# A saved choice wins while its agent is usable.
"$model" set pi p/1 "Pi One"
assert_eq "set saves agent, model, and name" "pi${tab}p/1${tab}Pi One" "$(cat "$OMARCHAT_MODEL_FILE")"
assert_eq "a usable saved choice is used" "pi${tab}p/1${tab}Pi One" "$("$model")"
assert_eq "a saved choice that becomes unusable falls back, unsaved" \
  "claude${tab}c1${tab}Claude One|pi${tab}p/1${tab}Pi One" \
  "$(STUB_PI_CHECK="Not logged in" "$model")|$(cat "$OMARCHAT_MODEL_FILE")"
"$model" set ghost g/1 "Ghost"
assert_eq "a saved agent Omarchat has no backend for falls back" "claude${tab}c1${tab}Claude One" "$("$model")"
reset

# The model list for settings.
listing=$(STUB_CLAUDE_CHECK="Not logged in" "$models")
assert_eq "an unusable agent is listed with its reason and no models" '{"available":false,"reason":"Not logged in","models":0}' \
  "$(jq -c '.agents[] | select(.id == "claude") | {available, reason, models: (.models | length)}' <<<"$listing")"
assert_eq "a usable agent lists its models by name" '["Pi One"]' \
  "$(jq -c '[.agents[] | select(.id == "pi") | .models[].name]' <<<"$listing")"
assert_eq "agents keep their display names and order" '["Claude Code","Pi"]' "$(jq -c '[.agents[].name]' <<<"$listing")"

assert_eq "a usable agent with no models says so" '{"available":false,"reason":"No models found"}' \
  "$(STUB_PI_MODELS="" "$models" | jq -c '.agents[] | select(.id == "pi") | {available, reason}')"
assert_eq "an agent that fails without a reason is unavailable, not empty" '{"available":false,"reason":"Unavailable"}' \
  "$(STUB_CLAUDE_CHECK=silent "$models" | jq -c '.agents[] | select(.id == "claude") | {available, reason}')"

# Refused models are marked for a week.
reset
"$models" >/dev/null
"$model" set claude c2 "Claude Two"
"$model" unavailable "Not on your plan"
assert_eq "a refused model carries the reason" '[{"id":"c1","unavailable":null},{"id":"c2","unavailable":"Not on your plan"}]' \
  "$("$models" --cached | jq -c '[.agents[] | select(.id == "claude") | .models[] | {id, unavailable}]')"
marks="$XDG_CACHE_HOME/omarchat/unavailable.json"
jq '.["claude/c2"].at -= 8 * 86400' "$marks" >"$marks.tmp" && mv "$marks.tmp" "$marks"
assert_eq "a mark older than a week is ignored" "null" \
  "$("$models" --cached | jq -c '.agents[] | select(.id == "claude") | .models[] | select(.id == "c2") | .unavailable')"
assert_eq "--cached without a cache builds one" "true" \
  "$(rm -rf "$XDG_CACHE_HOME"; "$models" --cached | jq '.agents | length == 2')"

finish
