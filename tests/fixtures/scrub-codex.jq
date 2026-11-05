select((.method // "") | test("^(account/|thread/tokenUsage|thread/started|thread/status)") | not)
| walk(if type == "object" then
    del(.threadId, .turnId, .itemId, .rootTurnId, .id, .cwd, .sessionId, .startedAtMs, .completedAt, .startedAt, .durationMs)
    | if .type == "webSearch" and has("results") then .results = [] else . end
  else . end)
| if has("id") and has("result") then .result = {} else . end
