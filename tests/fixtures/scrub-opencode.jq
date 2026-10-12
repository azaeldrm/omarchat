# Scrubs a recorded opencode ACP stream (OMARCHAT_OPENCODE_RECORD) before it
# becomes a fixture: no usage or command listings, no ids, and no
# search-result content (third-party pages). The translation never reads
# them.
select((.params.update.sessionUpdate // "") | IN("usage_update", "available_commands_update") | not)
| walk(if type == "object" then
    del(.sessionId, .toolCallId, .messageId, .usage, ._meta, .rawOutput)
    | if (.content | type) == "array" then del(.content) else . end
  else . end)
