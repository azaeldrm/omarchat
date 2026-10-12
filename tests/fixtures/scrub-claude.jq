# Scrubs a recorded `claude -p --output-format stream-json` session before it
# becomes a fixture: no ids, paths, account or rate-limit details, and no
# search-result text (third-party pages). The translation never reads them.
select(.type != "rate_limit_event")
| if .type == "system" then
    if .subtype == "init" then {type, subtype, model, tools} else {type, subtype} end
  else . end
| walk(if type == "object" then del(.session_id, .uuid, .request_id, .cwd, .memory_paths) else . end)
| if .type == "user" then
    .message.content |= map(
      if .type == "tool_result" or .type == "web_search_tool_result" then
        .content = "[search results omitted]"
      else . end)
    | del(.tool_use_result, .toolUseResult)
  else . end
