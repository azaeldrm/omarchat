# Shared by the Omarchat backends. Sourced, not run.
#
# A backend is an executable in this folder, named after the agent, with:
#
#   <agent> check            exit 0 if usable; otherwise print a short reason
#                            ("Not installed", "Not logged in") and exit 1
#   <agent> models           one JSON object per line: {"id": ..., "name": ...}
#   <agent> default          the model to use until one is chosen, as {"id", "name"}
#   <agent> paths            paths the session may write (token refreshes, ...)
#   <agent> encode           typed messages ({"text": ...} lines) -> agent input
#   <agent> translate        agent output -> Omarchat events (<agent>.jq)
#   <agent> session <model>  run a chat: encode | agent | translate
#
# Session input is one JSON object per line, {"text": "..."}. Session output is
# one JSON object per line:
#
#   {"type":"text","delta":"..."}           streamed answer text
#   {"type":"tool","name":"...","query":""} the model is using a tool
#   {"type":"answer","text":"..."}          authoritative final text for the turn
#   {"type":"error","text":"..."}           the turn failed
#   {"type":"done"}                         the turn is over

# Agents with a backend here, as id:name, in the order settings lists them and
# the order Omarchat falls back through when nothing usable is chosen.
omarchat_agents=("claude:Claude Code" "pi:Pi" "codex:Codex" "opencode:OpenCode")

omarchat_agent_name() {
  local entry
  for entry in "${omarchat_agents[@]}"; do
    [[ ${entry%%:*} == "$1" ]] && { echo "${entry#*:}"; return; }
  done
  echo "$1"
}

# Print the real binary for an agent, skipping Omarchy's install-on-first-run
# stubs (and mise shims, which would want to write their cache in the sandbox).
# omarchat-session resolves it before entering the sandbox, where mise can't
# write, and passes it down as OMARCHAT_AGENT_BIN.
omarchat_agent_bin() {
  local name="$1" bin
  if [[ -n ${OMARCHAT_AGENT_BIN:-} ]]; then
    echo "$OMARCHAT_AGENT_BIN"
    return
  fi
  bin=$(mise which "$name" 2>/dev/null) || bin=$(command -v "$name" 2>/dev/null) || return 1
  grep -q '^mise use -g' "$bin" 2>/dev/null && return 1
  echo "$bin"
}
