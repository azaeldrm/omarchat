# Scrubs a recorded `pi --mode rpc` session before it becomes a fixture: no
# search-result text (third-party pages) and no response ids. The
# translation never reads them.
def omit: map(if .type == "text" then .text = "[search results omitted]" else . end);
walk(
  if type == "object" then
    del(.responseId, .id)
    | if .role == "toolResult" and (.content | type) == "array" then .content |= omit else . end
  else . end)
| if .type == "tool_execution_end" and (.result.content | type) == "array" then .result.content |= omit else . end
