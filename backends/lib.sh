omarchat_agents=("claude:Claude Code" "pi:Pi" "codex:Codex" "opencode:OpenCode")

omarchat_version() {
  # Omarchat's version, from manifest.json.
  jq -r '.version' "$(dirname "${BASH_SOURCE[0]}")/../manifest.json"
}

omarchat_large_model='(^|[^a-z])(opus|fable|sol|astra)([^a-z]|$)'

omarchat_drop_large() {
  # Model lines ({"id", "name", ...}) on stdin, minus the large ones.
  jq -c --arg re "$omarchat_large_model" 'select([.id, .name] | map(. // "" | test($re; "i")) | any | not)'
}

omarchat_is_large() {
  # True if a model id or name is one of the large ones.
  grep -qiE "$omarchat_large_model" <<<"$1"
}

omarchat_agent_name() {
  # An agent id's display name.
  local entry
  for entry in "${omarchat_agents[@]}"; do
    [[ ${entry%%:*} == "$1" ]] && { echo "${entry#*:}"; return; }
  done
  echo "$1"
}

omarchat_agent_bin() {
  # Print an agent's real binary, skipping Omarchy's install-on-first-run stubs.
  local name="$1" bin
  if [[ -n ${OMARCHAT_AGENT_BIN:-} ]]; then
    echo "$OMARCHAT_AGENT_BIN"
    return
  fi
  bin=$(mise which "$name" 2>/dev/null) || bin=$(command -v "$name" 2>/dev/null) || return 1
  head -c 4096 "$bin" 2>/dev/null | grep -qa '^mise use -g' && return 1
  echo "$bin"
}
