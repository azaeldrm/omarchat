# Agent guidelines

## Comments

- Don't add comments to code.
- The one exception: a short docstring directly under a function's definition
  line, saying what it does. In shell, QML, and jq, write it as a comment on
  the first line inside the body:

  ```bash
  omarchat_version() {
    # Omarchat's version, from manifest.json.
    jq -r '.version' "$(dirname "${BASH_SOURCE[0]}")/../manifest.json"
  }
  ```
