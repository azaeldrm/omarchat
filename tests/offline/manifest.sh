# The plugin installs with `omarchy plugin add`, which refuses anything that
# fails `omarchy plugin validate`. CI has no Omarchy, so this mirrors the
# validator's checks; where Omarchy is installed, the real one runs too.

# shellcheck source=SCRIPTDIR/../lib.sh
source "$(dirname "$0")/../lib.sh"

manifest="$repo/manifest.json"

if jq -e . "$manifest" >/dev/null 2>&1; then ok "manifest.json is valid JSON"; else fail "manifest.json is valid JSON"; fi
assert_eq "schemaVersion is the number 1" "true" "$(jq '.schemaVersion == 1' "$manifest")"

for field in id name version kinds entryPoints; do
  assert_eq "has required field '$field'" "true" "$(jq --arg f "$field" 'has($f)' "$manifest")"
done

id=$(jq -r '.id' "$manifest")
if [[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $id != *..* && $id != omarchy.* ]]; then
  ok "id '$id' is valid and not in the reserved omarchy.* namespace"
else
  fail "id '$id' is valid and not in the reserved omarchy.* namespace"
fi

while IFS=$'\t' read -r kind entry; do
  if [[ -z $entry ]]; then
    fail "kind '$kind' has an entry point"
  elif [[ $entry == /* || $entry == *..* ]]; then
    fail "entry point '$entry' is a safe relative path"
  elif [[ -f $repo/$entry ]]; then
    ok "kind '$kind' loads $entry, which exists"
  else
    fail "kind '$kind' loads $entry, which exists"
  fi
done < <(jq -r '.kinds[] as $kind | [$kind, (.entryPoints[$kind] // "")] | @tsv' "$manifest")

links=$(find "$repo" -name .git -prune -o -name .scratch -prune -o -type l -print)
assert_eq "no symlinks in the plugin" "" "$links"

assert_eq "LICENSE matches the manifest's license" "MIT" \
  "$(grep -q '^MIT License' "$repo/LICENSE" && jq -r .license "$manifest")"

# Plugins install as plain git checkouts, so the scripts must be executable
# in git itself, not just on this disk.
for script in bin/omarchat-model bin/omarchat-models bin/omarchat-session backends/claude backends/pi tests/run; do
  mode=$(git -C "$repo" ls-files -s "$script" | cut -d' ' -f1)
  if [[ -z $mode ]]; then
    skip "$script is executable in git (not committed yet)"
  else
    assert_eq "$script is executable in git" "100755" "$mode"
  fi
done

if command -v omarchy >/dev/null; then
  if out=$(omarchy plugin validate "$repo" 2>&1); then ok "omarchy plugin validate"; else fail "omarchy plugin validate: $out"; fi
else
  skip "omarchy plugin validate (Omarchy isn't installed)"
fi

finish
