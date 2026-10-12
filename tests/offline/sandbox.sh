# Every session runs inside bin/omarchat-session's bubblewrap sandbox. A
# stand-in backend reports what it could do from in there: see files in the
# real $HOME, change it, write the paths it declared, and whether /tmp is
# shared with the host. Nothing reaches a real agent.

# shellcheck source=SCRIPTDIR/../lib.sh
source "$(dirname "$0")/../lib.sh"

if ! command -v bwrap >/dev/null; then
  skip "bubblewrap isn't installed"
  finish
  exit
fi
if ! bwrap --ro-bind / / --dev /dev --proc /proc --unshare-pid true 2>/dev/null; then
  skip "bubblewrap can't create namespaces here (unprivileged user namespaces disabled?)"
  finish
  exit
fi

# Work outside /tmp: the sandbox gives sessions a private one, so a plugin
# under /tmp would be invisible inside it (installed plugins live in ~/.config).
rm -rf "$scratch"
scratch=$(mktemp -d -p "$HOME" .omarchat-test.XXXXXX)
plugin=$(plugin_copy)
declared="$scratch/declared"
mkdir -p "$declared"
probe="omarchat-sandbox-probe.$$"
# A file in the real $HOME that no session should be able to see.
secret="$HOME/.omarchat-sandbox-secret.$$"
echo "SECRET-$RANDOM" >"$secret"

cat >"$plugin/backends/claude" <<EOF
#!/bin/bash
case "\${1:-}" in
check) exit 0 ;;
default) echo '{"id":"stub","name":"Stub"}' ;;
paths) echo "$declared" ;;
session)
  read -r _
  [[ -r "$secret" ]] && homeread=visible || homeread=hidden
  touch "\$HOME/$probe" 2>/dev/null && home=allowed || home=denied
  touch "$declared/$probe" 2>/dev/null && declared=allowed || declared=denied
  touch /tmp/$probe 2>/dev/null && tmp=allowed || tmp=denied
  jq -nc --arg text "homeread=\$homeread home=\$home declared=\$declared tmp=\$tmp prompt=\${#OMARCHAT_SYSTEM_PROMPT}" '{type: "answer", text: \$text}'
  echo '{"type":"done"}'
  ;;
esac
EOF
chmod +x "$plugin/backends/claude"

export OMARCHAT_MODEL_FILE="$scratch/model"
export XDG_CACHE_HOME="$scratch/cache"
# The stand-in isn't a real agent binary; skip resolving one.
export OMARCHAT_AGENT_BIN=/bin/true
"$plugin/bin/omarchat-model" set claude stub Stub

report=$(echo '{"text":"hi"}' | timeout 30 "$plugin/bin/omarchat-session" | jq -r 'select(.type == "answer") | .text')

assert_contains "the session can't see files in the real \$HOME" "homeread=hidden" "$report"
assert_contains "the session can write the paths its backend declared" "declared=allowed" "$report"
assert_contains "the session has a /tmp of its own" "tmp=allowed" "$report"
assert_eq "writes to \$HOME never reach the real one" "absent" "$([[ -e $HOME/$probe ]] && echo present || echo absent)"
assert_eq "the sandbox's /tmp isn't the host's" "absent" "$([[ -e /tmp/$probe ]] && echo present || echo absent)"
assert_eq "the declared path really was written" "present" "$([[ -e $declared/$probe ]] && echo present || echo absent)"
if [[ $report =~ prompt=([0-9]+) ]] && ((BASH_REMATCH[1] > 0)); then
  ok "the session hands the backend its system prompt"
else
  fail "the session hands the backend its system prompt ($report)"
fi
rm -f "$HOME/$probe" "/tmp/$probe" "$secret"

# Failures before the sandbox say what's wrong, on stderr, for the card.
"$plugin/bin/omarchat-model" set ghost g/1 Ghost
cat >"$plugin/backends/claude" <<'EOF'
#!/bin/bash
[[ ${1:-} == check ]] && { echo "Not logged in"; exit 1; }
EOF
err=$(echo '{"text":"hi"}' | "$plugin/bin/omarchat-session" 2>&1 >/dev/null)
assert_eq "no usable agent: the session explains instead of starting" "No agent has been set up yet." "$err"

finish
