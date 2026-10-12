# Pi RPC events (pi --mode rpc) -> Omarchat events. See lib.sh.
if .type == "message_update" and .assistantMessageEvent.type == "text_delta" then
  {type: "text", delta: .assistantMessageEvent.delta}
elif .type == "tool_execution_start" then
  {type: "tool", name: .toolName, query: (.args.query // "")}
elif .type == "message_end" and .message.role == "assistant" then
  if .message.stopReason == "error" then
    {type: "error", text: (.message.errorMessage // "The model returned an error.")}
  elif .message.stopReason == "stop" then
    {type: "answer", text: ([.message.content[]? | select(.type == "text") | .text] | join(""))}
  else empty end
elif .type == "response" and .success == false then
  {type: "error", text: (.error // "Pi rejected the request.")}, {type: "done"}
elif .type == "agent_settled" then
  {type: "done"}
else empty end
