set -uo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
suite=$(basename "${0%.sh}")
passed=0
failed=0
skipped=0

ok() {
  passed=$((passed + 1))
  echo "  ok    $*"
}

fail() {
  failed=$((failed + 1))
  echo "  FAIL  $*"
}

skip() {
  skipped=$((skipped + 1))
  echo "  skip  $*"
}

assert_eq() {
  # assert_eq <description> <expected> <actual>
  if [[ $2 == "$3" ]]; then
    ok "$1"
  else
    fail "$1"
    echo "        expected: $2"
    echo "        actual:   $3"
  fi
}

assert_contains() {
  # assert_contains <description> <needle> <haystack>
  if [[ $3 == *"$2"* ]]; then ok "$1"; else fail "$1 (missing: $2)"; fi
}

assert_not_contains() {
  # assert_not_contains <description> <needle> <haystack>
  if [[ $3 != *"$2"* ]]; then ok "$1"; else fail "$1 (found: $2)"; fi
}

scratch=$(mktemp -d -t omarchat-test.XXXXXX)
trap 'rm -rf "$scratch"' EXIT

plugin_copy() {
  # Copy bin/ and backends/ to the scratch folder, for stand-in backends; print the path.
  local dir="$scratch/plugin"
  mkdir -p "$dir"
  cp -r "$repo/bin" "$repo/backends" "$dir/"
  echo "$dir"
}

finish() {
  # Print the suite's totals; fail if any test failed.
  echo "  -- $suite: $passed passed, $failed failed, $skipped skipped"
  printf '%s %s %s\n' "$passed" "$failed" "$skipped" >"${OMARCHAT_TEST_RESULTS:-/dev/null}"
  ((failed == 0))
}
