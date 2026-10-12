/**
 * Omarchat web search for Pi.
 *
 * The only tool an Omarchat Pi session gets. It searches through Exa's hosted
 * MCP endpoint (the service opencode's websearch uses), which works without an
 * API key; set EXA_API_KEY for higher limits. The model chooses the query and
 * nothing else: there is no URL parameter, so it can't reach this machine or
 * the local network, only the fixed search endpoint.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const ENDPOINT = "https://mcp.exa.ai/mcp";
const RESULTS = 6;
const MAX_CHARS = 12000;
const RETRY_DELAY_MS = 3000;

// The keyless tier rate-limits in short bursts and says so in a normal
// result. Treat that as a failure, so the model doesn't read it as findings.
// Match Exa's own wording: results about other rate limits must pass.
const RATE_LIMITED = /hit Exa's free MCP rate limit/i;

async function search(query: string, signal?: AbortSignal): Promise<string> {
	const key = process.env.EXA_API_KEY;
	const url = key ? `${ENDPOINT}?exaApiKey=${encodeURIComponent(key)}` : ENDPOINT;

	const response = await fetch(url, {
		method: "POST",
		signal,
		headers: {
			"Content-Type": "application/json",
			Accept: "application/json, text/event-stream",
		},
		body: JSON.stringify({
			jsonrpc: "2.0",
			id: 1,
			method: "tools/call",
			params: {
				name: "web_search_exa",
				arguments: { query, numResults: RESULTS, type: "auto", livecrawl: "fallback" },
			},
		}),
	});
	if (!response.ok) throw new Error(`Web search failed (HTTP ${response.status})`);

	// The endpoint answers as server-sent events; the JSON-RPC reply is the
	// last `data:` line. Fall back to the raw body for plain JSON.
	const body = await response.text();
	const data = body
		.split("\n")
		.filter((line) => line.startsWith("data:"))
		.map((line) => line.slice(5).trim())
		.pop();
	const reply = JSON.parse(data ?? body);
	if (reply.error) throw new Error(reply.error.message ?? "Web search failed");

	return (reply.result?.content ?? [])
		.filter((part: { type: string }) => part.type === "text")
		.map((part: { text: string }) => part.text)
		.join("\n\n");
}

export default function omarchatWebSearch(pi: ExtensionAPI) {
	pi.registerTool({
		name: "web_search",
		label: "Web search",
		description:
			"Search the web for current or specific information. Returns the titles, URLs, and excerpts of the top results.",
		promptSnippet: "Search the web for current or specific facts",
		parameters: Type.Object({
			query: Type.String({ description: "What to search for" }),
		}),
		async execute(_toolCallId, params, signal) {
			let text = await search(params.query, signal);
			if (RATE_LIMITED.test(text)) {
				await new Promise((resolve) => setTimeout(resolve, RETRY_DELAY_MS));
				text = await search(params.query, signal);
			}
			if (RATE_LIMITED.test(text)) {
				throw new Error(
					"Exa's free search is rate-limited right now. Try again in a minute, or set EXA_API_KEY (free at exa.ai) for higher limits.",
				);
			}
			text = text.slice(0, MAX_CHARS);

			return {
				content: [{ type: "text", text: text || "No results." }],
				details: { query: params.query },
			};
		},
	});
}
