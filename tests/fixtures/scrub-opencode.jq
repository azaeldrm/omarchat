select((.params.update.sessionUpdate // "") | IN("usage_update", "available_commands_update") | not)
| walk(if type == "object" then
    del(.sessionId, .toolCallId, .messageId, .usage, ._meta, .rawOutput)
    | if (.content | type) == "array" then del(.content) else . end
  else . end)
