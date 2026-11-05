if .method == "item/agentMessage/delta" then
  {type: "text", delta: .params.delta}
elif .method == "item/started" and .params.item.type == "webSearch" then
  {type: "tool", name: "web_search", query: (.params.item.query // .params.item.action.queries[0]? // "")}
elif .method == "item/started" and (.params.item.type | IN("userMessage", "agentMessage", "reasoning", "plan", "contextCompaction") | not) then
  {type: "tool", name: .params.item.type,
   query: ([.params.item.server, .params.item.tool, .params.item.namespace] | map(select(. != null)) | join("/"))}
elif .method == "item/completed" and .params.item.type == "agentMessage" then
  {type: "answer", text: (.params.item.text // "")}
elif .method == "error" and .params.willRetry == false then
  {type: "error", text: (.params.error.message // "Codex returned an error.")}
elif .method == "turn/completed" then
  (if .params.turn.status == "failed" and .params.turn.error.message then
     {type: "error", text: .params.turn.error.message}
   else empty end),
  {type: "done"}
elif has("id") and has("error") then
  {type: "error", text: (.error.message // "Codex rejected the request.")}, {type: "done"}
else empty end
