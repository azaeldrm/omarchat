# opencode ACP messages (opencode acp, JSON-RPC over stdio) -> Omarchat
# events. See lib.sh, and https://agentclientprotocol.com for the protocol.
# backends/opencode answers agent requests itself; only notifications and the
# responses to session/prompt reach this filter. Run with -n: it keeps the
# turn's text so far, to send as the answer when the turn ends.

# "Internal error: Bad Request: {"detail": "..."}" -> the detail.
def readable:
  sub("^Internal error: "; "")
  | (capture("(?<json>\\{.*\\})$").json | fromjson? | .detail // .error.message // .message // empty) // .;

# One agent message -> its events.
def events:
  if .method == "session/update" then
    .params.update
    | if .sessionUpdate == "agent_message_chunk" and .content.type == "text" then
        {type: "text", delta: .content.text}
      elif .sessionUpdate == "tool_call" then
        # A tool call starts with the tool's name as its title.
        {type: "tool", name: (if .title == "websearch" then "web_search" else .title end), query: (.rawInput.query // "")}
      elif .sessionUpdate == "tool_call_update" and .status == "in_progress" and (.title // "" | test("web search"; "i")) and .rawInput.query then
        # The search's query arrives once it runs.
        {type: "tool", name: "web_search", query: .rawInput.query}
      else empty end
  elif has("id") and has("result") then
    # A turn is over.
    (.result.stopReason
     | if . == "max_tokens" then {type: "error", text: "The answer hit the model's length limit."}
       elif . == "refusal" then {type: "error", text: "The model declined to answer."}
       else empty end),
    {type: "done"}
  elif has("id") and has("error") then
    # A failed turn, such as a model this account can't use.
    {type: "error", text: ((.error.message // "") | readable | if . == "" then "opencode returned an error." else . end)},
    {type: "done"}
  else empty end
;

# The text since the last tool call is the turn's answer, unless it failed.
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
