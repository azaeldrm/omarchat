# Claude Code stream-json (claude -p --output-format stream-json
# --include-partial-messages) -> Omarchat events. See lib.sh.
if .type == "stream_event" and .event.type == "content_block_delta" and .event.delta.type == "text_delta" then
  {type: "text", delta: .event.delta.text}
elif .type == "assistant" then
  .message.content[]? | select(.type == "tool_use" or .type == "server_tool_use")
  | {type: "tool", name: .name, query: (.input.query // "")}
elif .type == "result" then
  (if .is_error then {type: "error", text: (.result // "Something went wrong.")}
   else {type: "answer", text: (.result // "")} end),
  {type: "done"}
else empty end
