# Every shell script passes shellcheck.

# shellcheck source=SCRIPTDIR/../lib.sh
source "$(dirname "$0")/../lib.sh"

# Probe rather than `command -v`: a mise shim can exist without a version.
# CI always has it; locally, install it with `mise use -g shellcheck` or
# `omarchy pkg add shellcheck`.
if shellcheck --version >/dev/null 2>&1; then
  shellcheck=(shellcheck)
elif [[ -n ${OMARCHAT_TEST_SHELLCHECK:-} ]]; then
  read -r -a shellcheck <<<"$OMARCHAT_TEST_SHELLCHECK"
else
  skip "shellcheck isn't installed (mise use -g shellcheck, or omarchy pkg add shellcheck)"
  finish
  exit
fi

scripts=(
  bin/omarchat-model bin/omarchat-models bin/omarchat-session
  backends/lib.sh backends/claude backends/pi backends/codex backends/opencode
  tests/run tests/lib.sh
)
for test_script in "$repo"/tests/offline/*.sh "$repo"/tests/live/*.sh; do
  scripts+=("${test_script#"$repo"/}")
done

cd "$repo" || exit 1
for script in "${scripts[@]}"; do
  if out=$("${shellcheck[@]}" -x -s bash "$script" 2>&1); then
    ok "$script"
  else
    fail "$script"
    while IFS= read -r line; do echo "        $line"; done <<<"$out"
  fi
done

finish
