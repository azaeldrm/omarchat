# Codex app-server messages (codex app-server, JSON-RPC over stdio) -> Omarchat
# events. See lib.sh, and https://developers.openai.com/codex/app-server for
# the protocol. backends/codex answers server requests itself; only
# notifications and responses reach this filter.
if .method == "item/agentMessage/delta" then
  {type: "text", delta: .params.delta}
elif .method == "item/started" and .params.item.type == "webSearch" then
  {type: "tool", name: "web_search", query: (.params.item.query // .params.item.action.queries[0]? // "")}
elif .method == "item/started" and (.params.item.type | IN("userMessage", "agentMessage", "reasoning", "plan", "contextCompaction") | not) then
  # Anything else that does work (commands, file changes, image views, MCP
  # calls) is reported by its item type, so the tests can see it was tried.
  {type: "tool", name: .params.item.type,
   query: ([.params.item.server, .params.item.tool, .params.item.namespace] | map(select(. != null)) | join("/"))}
elif .method == "item/completed" and .params.item.type == "agentMessage" then
  # Each agent message is authoritative for its text; the turn's last one is
  # the answer.
  {type: "answer", text: (.params.item.text // "")}
elif .method == "error" and .params.willRetry == false then
  {type: "error", text: (.params.error.message // "Codex returned an error.")}
elif .method == "turn/completed" then
  (if .params.turn.status == "failed" and .params.turn.error.message then
     {type: "error", text: .params.turn.error.message}
   else empty end),
  {type: "done"}
elif has("id") and has("error") then
  # A rejected request, such as a turn on a model this account can't use.
  {type: "error", text: (.error.message // "Codex rejected the request.")}, {type: "done"}
else empty end
