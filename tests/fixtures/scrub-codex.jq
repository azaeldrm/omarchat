# Scrubs a recorded Codex app-server stream (OMARCHAT_CODEX_RECORD) before it
# becomes a fixture: no account or rate-limit messages, no ids or paths, and
# no search-result content (third-party pages). The translation never reads
# them.
select((.method // "") | test("^(account/|thread/tokenUsage|thread/started|thread/status)") | not)
| walk(if type == "object" then
    del(.threadId, .turnId, .itemId, .rootTurnId, .id, .cwd, .sessionId, .startedAtMs, .completedAt, .startedAt, .durationMs)
    | if .type == "webSearch" and has("results") then .results = [] else . end
  else . end)
| if has("id") and has("result") then .result = {} else . end
