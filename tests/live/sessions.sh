# Real chats, no stand-ins: each agent that's installed and logged in here
# answers through bin/omarchat-session (so inside the sandbox), keeps context
# across turns, and every turn ends cleanly. Checks Omarchat's plumbing, not
# the model's wording. Costs a little usage.
#
# Models: OMARCHAT_TEST_<AGENT>_MODEL (e.g. OMARCHAT_TEST_PI_MODEL), else
# Claude Haiku 5.5 for Claude Code and each other agent's own default.

# shellcheck source=SCRIPTDIR/../lib.sh
source "$(dirname "$0")/../lib.sh"

export OMARCHAT_MODEL_FILE="$scratch/model"
export XDG_CACHE_HOME="$scratch/cache"

# shellcheck source=SCRIPTDIR/../../backends/lib.sh
source "$repo/backends/lib.sh"

# OMARCHAT_TEST_<AGENT>_MODEL, else the agent's own default (Claude: Haiku).
test_model() {
  local override="OMARCHAT_TEST_${1^^}_MODEL"
  if [[ -n ${!override:-} ]]; then
    echo "${!override}"
  elif [[ $1 == claude ]]; then
    echo claude-haiku-5-5
  else
    "$repo/backends/$1" default | jq -r .id
  fi
}

for entry in "${omarchat_agents[@]}"; do
  agent=${entry%%:*}
  if ! reason=$("$repo/backends/$agent" check); then
    skip "$agent: $reason"
    continue
  fi
  model=$(test_model "$agent")
  "$repo/bin/omarchat-model" set "$agent" "$model" "$model"

  # A word the model can't guess, so remembering it proves the session kept
  # the first turn: the same agent process carries the whole conversation.
  word="omarchat$RANDOM$RANDOM"
  events=$(timeout 200 python3 -I "$repo/tests/live/converse.py" 90 "$repo/bin/omarchat-session" -- \
    "Remember this word: $word. Reply with just: ok" \
    "What was the word I asked you to remember? Reply with just the word.")

  error=$(jq -r 'select(.type == "error") | .text' <<<"$events" | head -1)
  if [[ -n $error ]]; then
    fail "$agent ($model): $error"
    continue
  fi
  first=$(jq -r 'select(.turn == 1 and .type == "answer") | .text' <<<"$events")
  second=$(jq -r 'select(.turn == 2 and .type == "answer") | .text' <<<"$events")
  if [[ -n $first ]]; then ok "$agent ($model): answers"; else fail "$agent ($model): answers"; fi
  assert_contains "$agent: remembers the first turn" "$word" "$second"
  assert_eq "$agent: both turns end with done" "2" "$(jq -r 'select(.type == "done") | .turn' <<<"$events" | sort -u | wc -l)"
  if jq -e 'select(.type == "text")' <<<"$events" >/dev/null; then ok "$agent: streams text"; else fail "$agent: streams text"; fi
done

finish
