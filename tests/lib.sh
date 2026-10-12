# Shared by the test suites. Sourced, not run.
#
# Each suite is a bash script that sources this file, calls `ok` / `fail` /
# `skip` (or the assert helpers), and ends with `finish`. tests/run adds up the
# results.

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

# assert_eq <description> <expected> <actual>
assert_eq() {
  if [[ $2 == "$3" ]]; then
    ok "$1"
  else
    fail "$1"
    echo "        expected: $2"
    echo "        actual:   $3"
  fi
}

# assert_contains <description> <needle> <haystack>
assert_contains() {
  if [[ $3 == *"$2"* ]]; then ok "$1"; else fail "$1 (missing: $2)"; fi
}

# assert_not_contains <description> <needle> <haystack>
assert_not_contains() {
  if [[ $3 != *"$2"* ]]; then ok "$1"; else fail "$1 (found: $2)"; fi
}

# A scratch directory removed when the suite exits.
scratch=$(mktemp -d -t omarchat-test.XXXXXX)
trap 'rm -rf "$scratch"' EXIT

# A copy of bin/ and backends/ in the scratch directory, for tests that swap
# in stand-in backends. Prints its path.
plugin_copy() {
  local dir="$scratch/plugin"
  mkdir -p "$dir"
  cp -r "$repo/bin" "$repo/backends" "$dir/"
  echo "$dir"
}

finish() {
  echo "  -- $suite: $passed passed, $failed failed, $skipped skipped"
  printf '%s %s %s\n' "$passed" "$failed" "$skipped" >"${OMARCHAT_TEST_RESULTS:-/dev/null}"
  ((failed == 0))
}
