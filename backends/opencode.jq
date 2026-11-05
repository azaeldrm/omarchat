def readable:
  # "Internal error: Bad Request: {"detail": "..."}" -> the detail.
  sub("^Internal error: "; "")
  | (capture("(?<json>\\{.*\\})$").json | fromjson? | .detail // .error.message // .message // empty) // .;

def events:
  # One agent message -> its events.
  if .method == "session/update" then
    .params.update
    | if .sessionUpdate == "agent_message_chunk" and .content.type == "text" then
        {type: "text", delta: .content.text}
      elif .sessionUpdate == "tool_call" then
        {type: "tool", name: (if .title == "websearch" then "web_search" else .title end), query: (.rawInput.query // "")}
      elif .sessionUpdate == "tool_call_update" and .status == "in_progress" and (.title // "" | test("web search"; "i")) and .rawInput.query then
        {type: "tool", name: "web_search", query: .rawInput.query}
      else empty end
  elif has("id") and has("result") then
    (.result.stopReason
     | if . == "max_tokens" then {type: "error", text: "The answer hit the model's length limit."}
       elif . == "refusal" then {type: "error", text: "The model declined to answer."}
       else empty end),
    {type: "done"}
  elif has("id") and has("error") then
    {type: "error", text: ((.error.message // "") | readable | if . == "" then "opencode returned an error." else . end)},
    {type: "done"}
  else empty end
;

foreach inputs as $message ({text: "", failed: false, emit: []};
  .emit = []
  | reduce ($message | events) as $event (.;
      if $event.type == "text" then .text += $event.delta | .emit += [$event]
      elif $event.type == "tool" then .text = "" | .emit += [$event]
      elif $event.type == "error" then .failed = true | .emit += [$event]
      elif $event.type == "done" then
        .emit += (if .text != "" and (.failed | not) then [{type: "answer", text: .text}] else [] end) + [$event]
        | .text = "" | .failed = false
      else .emit += [$event] end);
  .emit[])
