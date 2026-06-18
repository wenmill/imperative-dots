// =============================================================================
//  HermesSessionAgent.qml
// -----------------------------------------------------------------------------
//  A self-contained integration layer between the Floating chat UI and the
//  native Hermes Agent local HTTP API server (the `/api/sessions` namespace on
//  http://localhost:8642).
//
//  It implements the full behavioural contract:
//    1. Session lifecycle  — create / load history / list.
//    2. Live SSE streaming — assistant.delta, tool start/progress/completed,
//                            run.completed — surfaced as signals + a timeline
//                            ListModel the UI binds to directly.
//    3. Fork-on-edit       — clone lineage up to a target message, re-stream the
//                            edited prompt against the new session, and wipe the
//                            now-obsolete tail of the timeline.
//
//  Design notes (why it's built this way):
//    • Qt's XMLHttpRequest does NOT deliver SSE chunks incrementally in this
//      runtime — onreadystatechange only fires on DONE, so a true token stream
//      never arrives. Instead we shell out to `curl -N` (unbuffered) via a
//      Quickshell Process and parse the byte stream line-by-line with a
//      SplitParser. This is the same primitive the rest of the module already
//      uses for streaming, and it is the only reliable way to get live SSE here.
//    • One-shot JSON requests (create / list / history / fork) use curl too, so
//      the whole module has a single, consistent transport with predictable
//      error surfaces (HTTP status is captured out-of-band on the last line).
//    • All persistent UI state lives in this object's properties + the exposed
//      ListModels, so the host (FloatingContent) binds rather than reaches in.
//
//  Public surface (call these from the host):
//      createSession(title, cb)              -> cb(session_id | "")
//      loadHistory(sessionId)                -> hydrates `timeline`
//      listSessions()                        -> hydrates `sessions`
//      sendMessage(text)                     -> streams into `timeline`
//      editAndFork(targetMessageId, newText) -> forks, rewinds, re-streams
//      stop()                                -> aborts an in-flight stream
//
//  Public read state:
//      activeSessionId : string
//      isStreaming     : bool
//      lastError       : string   ("" when clear; "rate_limited" on 429)
//      timeline        : ListModel (the live chat transcript)
//      sessions        : ListModel (history-sidebar source)
//
//  Signals (optional hooks for the host beyond the bound models):
//      sessionCreated(id) / historyLoaded() / sessionsLoaded()
//      streamStarted() / streamFinished() / errorOccurred(kind, detail)
// =============================================================================

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: agent

    // ── Configuration ────────────────────────────────────────────────────────
    // Base of the native Hermes server. The sessions namespace hangs off it.
    property string baseUrl: "http://localhost:8642"
    property string sessionsBase: baseUrl + "/api/sessions"
    // Optional bearer token; left blank for a purely-local server.
    property string authToken: ""

    // ── Capability probe (one-time, diagnostic) ──────────────────────────────
    // We don't yet know how this server scopes individual tools (web search vs
    // execute_code). Probe common discovery endpoints and log what comes back so
    // the gating can target the REAL field names instead of guessing. Results land
    // in `capabilities` and the console.
    property string capabilities: "(unprobed)"
    function probeCapabilities() {
        _probeProc.command = ["bash", "-c",
            "for p in /v1/tools /api/tools /tools /capabilities /v1/capabilities /api/capabilities /v1/models; do " +
            "  echo \"=== $p ===\"; " +
            "  curl -s -m 3 -w ' [%{http_code}]' " + _authHeader() + "'" + _shq(baseUrl) + "'\"$p\" 2>/dev/null | head -c 800; " +
            "  echo; " +
            "done"
        ];
        _probeProc.running = true;
    }
    Process {
        id: _probeProc
        command: ["bash", "-c", "true"]
        stdout: StdioCollector {
            onStreamFinished: {
                agent.capabilities = (this.text || "").substring(0, 1500);
                console.log("[HermesSessionAgent] capability probe:\n" + agent.capabilities);
            }
        }
    }

    // ── Tool gating (mirrors the Chat/Agent slider) ───────────────────────────
    // agentMode      : when FALSE (Chat), all agent tools are suppressed; the only
    //                  exception is web search/fetch when webSearchEnabled is true.
    //                  When TRUE (Agent), the full tool loop is allowed.
    // webSearchEnabled: the web-search toggle (on by default). Even in Chat mode,
    //                  web search/fetch is permitted when this is on — but nothing
    //                  else (no shell, no file writes, no other tools).
    // systemPrompt   : a steering preamble prepended to the turn input so the
    //                  server honours these constraints even if it ignores flags.
    property bool agentMode: false
    property bool webSearchEnabled: true
    // Home Assistant has its OWN toggle (separate from web). When on, Chat may
    // query/control smart-home devices; the web toggle no longer affects this.
    property bool homeAssistantEnabled: true
    // Reasoning/thinking output. Host sets the per-mode default (on for Agent, off
    // for Chat); the tools-menu toggle overrides. When on, we ask the server to
    // stream its reasoning so the Thinking dropdown can populate.
    property bool thinkingEnabled: false
    property string systemPrompt: ""

    // Tools ALWAYS available in Chat mode, regardless of any toggle:
    // vision (analyze images/screenshots) + knowledge & memory (long-term notes,
    // searching past conversations, in-session todos). Never includes shell, file
    // I/O, or code execution. Canonical names + common aliases for matching.
    readonly property var _baseChatTools: [
        // Vision
        "vision", "vision_analyze", "browser_vision", "analyze_image", "image_analyze",
        // Knowledge & memory
        "memory", "memory_store", "memory_search", "remember", "recall", "note",
        "session_search", "search_sessions", "conversation_search", "history_search",
        "todo", "todo_add", "todo_list", "todo_update", "todo_complete", "checklist"
    ]

    // Enabled in Chat ONLY when the WEB toggle is on — web & browsing ONLY.
    // (Home Assistant has moved out to its own list/toggle below.) Includes many
    // common provider/tool-name variants so the server's real web tool isn't
    // accidentally excluded by the allowlist (which would make the model try to
    // "search" and then hallucinate because the actual tool was filtered out).
    readonly property var _webChatTools: [
        "web_search", "websearch", "web.search", "web-search", "WebSearch",
        "web_extract", "web_fetch", "webfetch", "web.fetch", "fetch_url", "url_fetch",
        "web", "internet", "internet_search", "online_search",
        "search", "search_web", "google", "google_search", "bing", "bing_search",
        "duckduckgo", "ddg_search", "tavily", "tavily_search", "serper", "serpapi", "brave_search",
        "browse", "browser", "browser_navigate", "browser_click", "browser_type",
        "browser_scroll", "browser_screenshot", "browser_back", "browser_extract", "browser_open"
    ]

    // Enabled in Chat ONLY when the HOME ASSISTANT toggle is on — device control.
    readonly property var _haChatTools: [
        "ha", "home_assistant", "ha_call_service", "ha_get_state", "ha_get_states",
        "ha_turn_on", "ha_turn_off", "ha_toggle", "ha_set_state", "ha_list_entities",
        "ha_media", "ha_light", "ha_sensor"
    ]

    // ── Observable state ──────────────────────────────────────────────────────
    property string activeSessionId: ""
    property bool   isStreaming: false
    property string lastError: ""            // "", "rate_limited", "network", "http_5xx", ...
    // Last HTTP status from listSessions (for diagnostics): e.g. "200", "0", "429".
    property string lastListStatus: "(none)"
    // First ~600 chars of the last list response body, for shape diagnosis.
    property string lastListSnippet: ""
    // Status + body of the last createSession response, for diagnosis.
    property string lastCreateSnippet: "(none)"
    // Rolling capture of the most recent raw SSE lines (diagnostic): lets us see
    // the server's actual event taxonomy + whether content repeats across frames.
    property string lastStreamLog: ""
    property int _streamLogLines: 0
    // Tally of each SSE event type seen this stream (e.g. {"assistant.delta":42,
    // "run.completed":3}) — exposed via /sse so repeated/segmented patterns show.
    property var _evtCounts: ({})
    property string evtSummary: ""
    // Title the most recent fork was created under (handy for the sidebar).
    property string lastForkTitle: ""

    // The live chat transcript the UI renders. Each row:
    //   role        : "user" | "assistant" | "tool"
    //   messageId   : server message id when known (for fork targeting); may be ""
    //   text        : markdown body (assistant/user) or tool output (tool rows)
    //   streaming   : bool — true while assistant tokens are still arriving
    //   toolName    : string — populated on tool rows
    //   toolStatus  : "running" | "done" | "error"
    //   toolRunCtx  : human label e.g. "Executing Terminal Script…"
    //   toolOutput  : captured stdout/stderr/status payload for the accordion
    //   expanded    : bool — accordion open/closed (UI-owned, persisted per row)
    property ListModel timeline: ListModel {}

    // History-sidebar source. Each row: { id, title, updatedAt }.
    property ListModel sessions: ListModel {}

    // ── Signals ───────────────────────────────────────────────────────────────
    signal sessionCreated(string id)
    signal historyLoaded()
    signal sessionsLoaded()
    signal streamStarted()
    signal streamFinished()
    signal errorOccurred(string kind, string detail)
    // Fired on EVERY timeline mutation (token append, tool row, status flip). The
    // host mirrors on this rather than ListModel.dataChanged, which is unreliable
    // for setProperty in this runtime — that's why streamed answers weren't
    // showing until an unrelated change forced a refresh.
    signal timelineUpdated()

    // Internal: index of the assistant row currently being streamed (-1 = none),
    // and the index of the tool row currently "running" (-1 = none).
    property int _activeAssistantRow: -1
    property int _activeToolRow: -1
    // Set when a tool completes so the next assistant delta opens a fresh row
    // (prevents post-tool text concatenating onto / duplicating the prior answer).
    property bool _needNewAssistantRow: false
    // The canonical accumulated answer text for the CURRENT visible segment. Used
    // to de-duplicate when the server resends full snapshots or repeats the answer.
    property string _turnAnswer: ""
    // The policy string last sent to the server this session. When the current
    // turn's policy matches, we omit it so the prompt prefix stays identical
    // (prompt-cache hit). Reset on new chat / session switch.
    property string _lastPolicySent: ""
    // Carry the edited prompt across an async fork → stream handoff.
    property string _pendingForkPrompt: ""

    // =========================================================================
    //  TRANSPORT HELPERS
    // =========================================================================

    // Build the auth header fragment for curl (empty string when no token).
    function _authHeader() {
        return (authToken && authToken !== "")
            ? "-H 'Authorization: Bearer " + _shq(authToken) + "' "
            : "";
    }

    // Single-quote-escape a string for safe embedding inside a bash -c command.
    function _shq(s) {
        return String(s).split("'").join("'\\''");
    }

    // JSON-encode a value and shell-escape it for a curl --data argument.
    function _jsonArg(obj) {
        return _shq(JSON.stringify(obj));
    }

    // =========================================================================
    //  1. SESSION MANAGEMENT LIFECYCLE
    // =========================================================================

    // ── Create New Session ───────────────────────────────────────────────────
    //   POST /api/sessions   { "title"?: string }  ->  { session_id, ... }
    // Anchors all subsequent turns to the returned id. cb receives the id (or "").
    property var _createCb: null
    function createSession(title, cb) {
        agent._createCb = cb || null;
        var body = {};
        if (title && title !== "") body.title = title;
        // -s silent, -w writes the HTTP code on its own final line so we can
        // distinguish transport success from an empty/garbage body.
        _createProc.command = ["bash", "-c",
            "curl -s -w '\\nHTTP_STATUS:%{http_code}' -X POST " +
            _authHeader() +
            "-H 'Content-Type: application/json' " +
            "--data '" + _jsonArg(body) + "' " +
            "'" + _shq(sessionsBase) + "'"
        ];
        _createProc.running = true;
    }
    Process {
        id: _createProc
        command: ["bash", "-c", "true"]
        stdout: StdioCollector {
            onStreamFinished: {
                var parsed = agent._splitStatus(this.text);
                agent.lastCreateSnippet = "[" + parsed.status + "] " + (parsed.body || "").substring(0, 400);
                console.log("[HermesSessionAgent] createSession HTTP " + parsed.status +
                            " body=" + (parsed.body || "").substring(0, 300));
                if (parsed.status === 429) { agent._flagError("rate_limited", parsed.body); }
                else if (parsed.status >= 500) { agent._flagError("http_5xx", parsed.body); }
                else if (parsed.status === 0) { agent._flagError("network", parsed.body); }
                else {
                    try {
                        var o = JSON.parse(parsed.body);
                        var id = agent._findId(o);
                        if (id !== "") {
                            agent.activeSessionId = id;
                            agent.lastError = "";
                            agent.sessionCreated(id);
                        } else {
                            console.log("[HermesSessionAgent] createSession: no id found in response");
                        }
                        if (agent._createCb) agent._createCb(id);
                    } catch (e) {
                        agent._flagError("bad_json", parsed.body);
                        if (agent._createCb) agent._createCb("");
                    }
                }
                agent._createCb = null;
            }
        }
    }

    // ── Load Session History ──────────────────────────────────────────────────
    //   GET /api/sessions/{id}/messages -> [ {role, content, tool_calls[...]}, ... ]
    // Hydrates `timeline` chronologically, expanding nested tool_calls into the
    // same tool rows the live stream produces, so historical + live render alike.
    function loadHistory(sessionId) {
        var sid = sessionId || activeSessionId;
        if (!sid || sid === "") return;
        activeSessionId = sid;
        _lastPolicySent = "";   // new/loaded session → re-state policy on next turn
        _historyProc.command = ["bash", "-c",
            "curl -s -w '\\nHTTP_STATUS:%{http_code}' " +
            _authHeader() +
            "'" + _shq(sessionsBase + "/" + sid + "/messages") + "'"
        ];
        _historyProc.running = true;
    }
    Process {
        id: _historyProc
        command: ["bash", "-c", "true"]
        stdout: StdioCollector {
            onStreamFinished: {
                var parsed = agent._splitStatus(this.text);
                if (parsed.status === 429) { agent._flagError("rate_limited", parsed.body); return; }
                if (parsed.status === 0 || parsed.status >= 500) {
                    agent._flagError(parsed.status === 0 ? "network" : "http_5xx", parsed.body); return;
                }
                agent.timeline.clear();
                agent._activeAssistantRow = -1;
                agent._activeToolRow = -1;
                agent.lastListSnippet = (parsed.body || "").substring(0, 600);
                try {
                    var root = JSON.parse(parsed.body);
                    // Reuse the tolerant array finder (handles bare arrays, common
                    // wrapper keys like messages/data/items, id-keyed maps, etc.).
                    var arr = agent._extractArray(root);
                    for (var i = 0; i < arr.length; i++) {
                        var m = arr[i];
                        if (!m || typeof m !== "object") continue;
                        var role = agent._pick(m, ["role","sender","author","type"]) || "assistant";
                        role = String(role).toLowerCase();
                        if (role === "human") role = "user";
                        if (role === "ai" || role === "bot" || role === "model") role = "assistant";
                        var mid = agent._pick(m, ["id","message_id","messageId","uuid"]) || "";
                        var content = agent._pick(m, ["content","text","message","body","value"]);
                        // content may itself be an array of parts (OpenAI-style).
                        if (content && typeof content === "object") content = agent._flattenContent(content);
                        content = (content === undefined || content === null) ? "" : String(content);

                        if (role === "user") {
                            agent.timeline.append({
                                role: "user", messageId: mid, text: content,
                                streaming: false, toolName: "", toolStatus: "",
                                toolRunCtx: "", toolOutput: "", thinking: "", expanded: false
                            });
                        } else if (role === "tool" || role === "function") {
                            agent.timeline.append({
                                role: "tool", messageId: mid, text: "",
                                streaming: false,
                                toolName: agent._pick(m, ["name","tool","tool_name"]) || "tool",
                                toolStatus: "done",
                                toolRunCtx: agent._toolLabel(agent._pick(m, ["name","tool","tool_name"]) || "tool"),
                                toolOutput: content, thinking: "", expanded: false
                            });
                        } else {
                            // Assistant turn: render any tool_calls FIRST, then the body.
                            var tcs = m.tool_calls || m.toolCalls || m.tools || [];
                            for (var j = 0; j < tcs.length; j++) {
                                var tc = tcs[j];
                                var tname = agent._pick(tc, ["name","tool_name"]) || (tc.function && tc.function.name) || "tool";
                                agent.timeline.append({
                                    role: "tool", messageId: tc.id || "", text: "",
                                    streaming: false, toolName: tname, toolStatus: "done",
                                    toolRunCtx: agent._toolLabel(tname),
                                    toolOutput: agent._stringify(agent._pick(tc, ["output","result","content","response"]) || ""),
                                    thinking: "", expanded: false
                                });
                            }
                            agent.timeline.append({
                                role: "assistant", messageId: mid, text: content,
                                streaming: false, toolName: "", toolStatus: "",
                                toolRunCtx: "", toolOutput: "", thinking: "", expanded: false
                            });
                        }
                    }
                    console.log("[HermesSessionAgent] loaded " + agent.timeline.count + " timeline rows from " + arr.length + " message(s)");
                    agent.lastError = "";
                    agent.historyLoaded();
                } catch (e) {
                    agent._flagError("bad_json", parsed.body);
                }
            }
        }
    }

    // ── List All Sessions ───────────────────────────────────────────────────
    //   GET /api/sessions -> [ { id, title, updated_at }, ... ]
    // Hydrates the `sessions` model for the history sidebar.
    function listSessions() {
        _listProc.command = ["bash", "-c",
            "curl -s -w '\\nHTTP_STATUS:%{http_code}' " +
            _authHeader() +
            "'" + _shq(sessionsBase) + "'"
        ];
        _listProc.running = true;
    }
    Process {
        id: _listProc
        command: ["bash", "-c", "true"]
        stdout: StdioCollector {
            onStreamFinished: {
                var parsed = agent._splitStatus(this.text);
                agent.lastListStatus = String(parsed.status) + " (len " + (parsed.body ? parsed.body.length : 0) + ")";
                console.log("[HermesSessionAgent] listSessions HTTP " + parsed.status +
                            " bodyLen=" + (parsed.body ? parsed.body.length : 0));
                if (parsed.status === 429) { agent._flagError("rate_limited", parsed.body); return; }
                if (parsed.status === 0 || parsed.status >= 500) {
                    agent._flagError(parsed.status === 0 ? "network" : "http_5xx", parsed.body); return;
                }
                agent.sessions.clear();
                agent.lastListSnippet = (parsed.body || "").substring(0, 600);
                try {
                    var root = JSON.parse(parsed.body);
                    // The server may wrap the list under any of these keys, or hand
                    // back a bare array, or an object map keyed by id.
                    var arr = agent._extractArray(root);
                    // Newest first. Timestamps may be epoch numbers or ISO strings.
                    arr.sort(function(a, b) {
                        var ta = agent._pick(a, ["updated_at","updatedAt","last_active","lastActive","modified","created_at","timestamp"]);
                        var tb = agent._pick(b, ["updated_at","updatedAt","last_active","lastActive","modified","created_at","timestamp"]);
                        var na = parseFloat(ta), nb = parseFloat(tb);
                        if (!isNaN(na) && !isNaN(nb)) return nb - na;   // numeric epochs
                        ta = "" + ta; tb = "" + tb;
                        return tb < ta ? -1 : (tb > ta ? 1 : 0);        // ISO strings
                    });
                    for (var i = 0; i < arr.length; i++) {
                        var s = arr[i];
                        if (s === null || typeof s !== "object") continue;
                        var id = agent._pick(s, ["id","session_id","sessionId","sid","uuid","key","name"]);
                        var title = agent._pick(s, ["title","name","preview","summary","label","first_message","topic"]);
                        var when = agent._pick(s, ["updated_at","updatedAt","last_active","lastActive","modified","created_at","timestamp"]);
                        if ((!id || id === "") && (!title || title === "")) continue;
                        agent.sessions.append({
                            id: id || "",
                            title: (title && title !== "") ? String(title) : (id || "Untitled"),
                            updatedAt: (when === undefined || when === null) ? "" : String(when)
                        });
                    }
                    console.log("[HermesSessionAgent] parsed " + agent.sessions.count + " sessions from " + arr.length + " candidate(s)");
                    agent.lastError = "";
                    agent.sessionsLoaded();
                } catch (e) {
                    agent._flagError("bad_json", parsed.body);
                }
            }
        }
    }

    // ── Session content search index (for the history sidebar) ───────────────
    // The CLI `hermes sessions export` path doesn't run in this Process env, so we
    // search over the working HTTP API instead: fetch each session's messages,
    // build a compact per-session text blob, and expose the index so the host can
    // run the AI semantic match. Reported via searchIndexReady.
    //   searchIndex : array of { id, title, text } — text is a trimmed join of the
    //                 session's messages (used for matching + showing a snippet).
    property var searchIndex: []
    property int _searchPending: 0
    property bool searchBuilding: false
    signal searchIndexReady()

    function buildSearchIndex() {
        if (searchBuilding) return;
        if (sessions.count === 0) { searchIndexReady(); return; }
        searchBuilding = true;
        agent.searchIndex = [];
        agent._searchPending = sessions.count;
        for (var i = 0; i < sessions.count; i++) {
            var s = sessions.get(i);
            _fetchSessionForIndex(s.id, s.title);
        }
    }
    function _fetchSessionForIndex(sid, title) {
        if (!sid || sid === "") { _searchIndexOneDone(); return; }
        var proc = _searchProcComponent.createObject(agent, { sid: sid, title: title });
        if (proc === null) { _searchIndexOneDone(); }
    }
    Component {
        id: _searchProcComponent
        Process {
            property string sid: ""
            property string title: ""
            command: ["bash", "-c",
                "curl -s -m 8 " + agent._authHeader() +
                "'" + agent._shq(agent.sessionsBase + "/" + sid + "/messages") + "'"
            ]
            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    var blob = "";
                    try {
                        var root = JSON.parse(this.text);
                        var arr = agent._extractArray(root);
                        var parts = [];
                        for (var k = 0; k < arr.length; k++) {
                            var m = arr[k];
                            if (!m || typeof m !== "object") continue;
                            var c = agent._pick(m, ["content","text","message","body","value"]);
                            if (c && typeof c === "object") c = agent._flattenContent(c);
                            if (c && c !== "") parts.push(String(c));
                        }
                        blob = parts.join("  ").replace(/\s+/g, " ").substring(0, 1200);
                    } catch (e) { blob = ""; }
                    agent.searchIndex.push({ id: sid, title: title, text: blob });
                    destroy();
                    agent._searchIndexOneDone();
                }
            }
        }
    }
    function _searchIndexOneDone() {
        agent._searchPending -= 1;
        if (agent._searchPending <= 0) {
            agent.searchBuilding = false;
            agent.searchIndexReady();
        }
    }

    // =========================================================================
    //  2. ONGOING CHAT & STREAM PROCESSING  (SSE)
    // =========================================================================
    //   POST /api/sessions/{id}/chat/stream   { "input": "<text>" }
    //
    //   Event hooks consumed (SSE "event:" + "data:" line pairs):
    //     assistant.delta                  -> append token to active bubble
    //     hermes.tool.progress|tool.started -> spinner + run context
    //     tool.completed                   -> stop spinner, fill accordion
    //     run.completed                    -> end of agent loop, re-enable input

    // Append a user row, an empty assistant row to stream into, then open the
    // SSE connection. If there is no active session yet, create one first.
    function sendMessage(text) {
        var t = (text || "").trim();
        if (t === "" || isStreaming) return;
        if (activeSessionId === "") {
            createSession("", function(id) {
                if (id === "") { agent._flagError("no_session", "could not create session"); return; }
                agent._appendAndStream(t);
            });
        } else {
            _appendAndStream(t);
        }
    }

    function _appendAndStream(t) {
        timeline.append({
            role: "user", messageId: "", text: t,
            streaming: false, toolName: "", toolStatus: "",
            toolRunCtx: "", toolOutput: "", thinking: "", expanded: false
        });
        _openStream(activeSessionId, t);
    }

    // Build a COMPACT, stable policy string for the given toggle-state. Short
    // fixed wording (not verbose prose) so the prompt prefix stays small and —
    // crucially — identical across turns with the same toggles, for cache hits.
    function _buildPolicy(fullTools, allowWeb, allowHA) {
        if (fullTools)
            return "[system: Agent mode. Full pre-authorized tool access (shell, files, "
                 + "code, web, all tools). Don't ask approval — call tools and act. "
                 + "Report only real tool output.]";
        // Chat mode: list permitted groups compactly.
        var allow = ["vision", "memory/session-search/todo"];
        if (allowWeb) allow.push("web+browser");
        if (allowHA)  allow.push("home-assistant");
        var p = "[system: Chat mode. Allowed tools: " + allow.join(", ")
              + ". Forbidden: shell, file I/O, code execution"
              + (allowWeb ? "" : ", web/browser")
              + (allowHA ? "" : ", home-assistant") + ".";
        if (allowWeb)
            p += " For current/real-time info you MUST web-search and answer from "
               + "results; never guess; if search fails, say so.";
        return p + "]";
    }

    // Open the unbuffered SSE stream for one turn.
    function _openStream(sessionId, inputText) {
        // Seed the assistant bubble that delta tokens will flow into.
        timeline.append({
            role: "assistant", messageId: "", text: "",
            streaming: true, toolName: "", toolStatus: "",
            toolRunCtx: "", toolOutput: "", thinking: "", expanded: false
        });
        _activeAssistantRow = timeline.count - 1;
        _activeToolRow = -1;
        _needNewAssistantRow = false;
        _turnAnswer = "";
        _sseCarryEvent = "";
        timelineUpdated();
        agent.lastStreamLog = "";
        _streamLogLines = 0;

        isStreaming = true;
        lastError = "";
        streamStarted();

        // ── Build the turn request with tool gating ──
        //   Agent mode → BLANKET full tool access.
        //   Chat mode  → base tools (vision + knowledge/memory) ALWAYS, plus the
        //                web/browser suite IF the web toggle is on, plus Home
        //                Assistant IF the HA toggle is on — each independent. Never
        //                shell, file I/O, or code execution.
        var allowWeb = webSearchEnabled;
        var allowHA  = homeAssistantEnabled;
        var fullTools = agentMode;
        var enableTools = true;   // Chat always has at least the base tools

        var body = { input: inputText };
        body.enable_tools = enableTools;

        if (fullTools) {
            // BLANKET access — let the model use the entire registered tool set.
            body.tool_choice = "auto";
            body.allow_all_tools = true;     // common blanket flag
            body.all_tools = true;           // alt name
            body.unrestricted_tools = true;  // alt name
            // Auto-approve tool execution so the server doesn't stall waiting for an
            // interactive confirmation the GUI can't answer.
            body.auto_approve = true;
            body.auto_approve_tools = true;
            body.require_approval = false;
            body.confirm_tools = false;
            body.skip_approval = true;
            body.yolo = true;                // some agents' "run without asking" flag
            // Deliberately NO allowed_tools key here: omitting the allowlist means
            // "no restriction" on servers that treat the list as a filter.
        } else {
            // Chat mode: base + optional web + optional Home Assistant.
            var allowed = agent._baseChatTools.slice();
            if (allowWeb) allowed = allowed.concat(agent._webChatTools);
            if (allowHA)  allowed = allowed.concat(agent._haChatTools);
            body.allowed_tools = allowed;
            body.tool_choice = "auto";
            // Auto-approve in Chat too: the permitted tools (web/HA/vision/memory)
            // are safe, and without this the server may stall or silently block the
            // web tool — which makes the model fall back to hallucinating an answer.
            body.auto_approve = true;
            body.auto_approve_tools = true;
            body.require_approval = false;
            body.confirm_tools = false;
            body.skip_approval = true;
        }

        // Reasoning/thinking output: ask the server to stream its reasoning when
        // Reasoning effort tracks the Thinking toggle: low when off (snappier,
        // fewer tokens), medium when on. A single canonical flag the server reads;
        // we drop the scattered alt-name flags that bloated the body every turn.
        body.reasoning_effort = thinkingEnabled ? "medium" : "low";
        if (thinkingEnabled) {
            // Only when the user wants reasoning, also set the stream-reasoning
            // flags so the Thinking dropdown can populate.
            body.reasoning = true;
            body.stream_reasoning = true;
            body.include_thoughts = true;
        }

        // ── Policy preamble: compact + STABLE, re-sent ONLY when it changes ──
        // Hermes layers a frontend system message on top of its core prompt, but
        // only caches ITS OWN prompt/skill blocks — our text sits in the prefix
        // region, so a preamble that changes every turn invalidates the prompt
        // cache. We therefore (a) keep it short and fixed per toggle-state, and
        // (b) send it only when the toggle-state actually changed since the last
        // turn. Unchanged turns send just the user's text → identical prefix →
        // cache hit. (Strategy chosen: re-send on toggle change.)
        var policy = _buildPolicy(fullTools, allowWeb, allowHA);
        if (policy !== _lastPolicySent) {
            // Toggle-state changed (or first turn this session): state the policy
            // once, inline AND as body.system, then remember it.
            var pre = (systemPrompt && systemPrompt !== "") ? (systemPrompt + "\n\n" + policy) : policy;
            body.input = pre + "\n\n" + inputText;
            body.system = pre;
            _lastPolicySent = policy;
        } else {
            // Policy unchanged → don't resend it. Keeps the prompt prefix stable
            // for cache hits; the server already has the policy from a prior turn
            // (and from session-creation instructions).
            body.input = inputText;
        }
        var bodyForLog = {};
        for (var bk in body) { if (body.hasOwnProperty(bk) && bk !== "input" && bk !== "system") bodyForLog[bk] = body[bk]; }
        var sentThisTurn = (body.system !== undefined && body.system !== null);
        agent.lastStreamLog = "REQUEST tools: " + JSON.stringify(bodyForLog)
            + "\npolicy: " + (sentThisTurn ? "RESENT this turn" : "cached (not resent — stable prefix)")
            + "\n--- SSE ---\n";
        _streamLogLines = 0;
        agent._evtCounts = ({});

        // -N disables curl's output buffering so each SSE line arrives live.
        // --no-buffer is belt-and-suspenders for older curl. -w appends the
        // final HTTP status as a sentinel line the parser special-cases.
        _streamProc.command = ["bash", "-c",
            "curl -sN --no-buffer -X POST " +
            _authHeader() +
            "-H 'Content-Type: application/json' " +
            "-H 'Accept: text/event-stream' " +
            "--data '" + _jsonArg(body) + "' " +
            "-w '\\nHTTP_STATUS:%{http_code}\\n' " +
            "'" + _shq(sessionsBase + "/" + sessionId + "/chat/stream") + "'"
        ];
        _streamProc.running = true;
    }

    // Abort an in-flight stream (user pressed stop / started a new turn).
    function stop() {
        if (_streamProc.running) _streamProc.running = false;
        _finishStream();
    }

    // SSE accumulator: SplitParser hands us one line at a time. SSE frames are
    // "event: <name>" then "data: <json>" then a blank line. We remember the
    // most recent event name and apply it when its data line arrives.
    property string _sseCarryEvent: ""
    Process {
        id: _streamProc
        command: ["bash", "-c", "true"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                agent._onSseLine(line);
            }
        }
        // If the process dies without a clean run.completed (crash, kill,
        // dropped socket), still release the UI.
        onRunningChanged: {
            if (!running && agent.isStreaming) agent._finishStream();
        }
    }

    function _onSseLine(rawLine) {
        var line = (rawLine === undefined || rawLine === null) ? "" : String(rawLine);

        // Diagnostic: capture the first ~40 raw lines of the stream so we can see
        // the real event names + whether content repeats. Reset per stream.
        if (_streamLogLines < 40 && line.trim() !== "") {
            agent.lastStreamLog += line.substring(0, 160) + "\n";
            _streamLogLines += 1;
            console.log("[SSE] " + line.substring(0, 200));
        }

        // Transport sentinel from curl -w. Lets us catch 429 / 5xx that arrive
        // as a normal (non-SSE) response body.
        if (line.indexOf("HTTP_STATUS:") === 0) {
            var code = parseInt(line.substring("HTTP_STATUS:".length).trim(), 10);
            if (code === 429) agent._flagError("rate_limited", "stream rejected (429)");
            else if (code >= 500) agent._flagError("http_5xx", "stream error " + code);
            else if (code === 0) agent._flagError("network", "stream connection failed");
            return;
        }

        var s = line.replace(/\r$/, "");      // strip trailing CR (CRLF streams)
        if (s === "") { agent._sseCarryEvent = ""; return; }   // frame boundary

        // "event:" line — remember which hook the next data line belongs to.
        if (s.indexOf("event:") === 0) {
            agent._sseCarryEvent = s.substring(6).trim();
            return;
        }
        // Comment/keepalive line.
        if (s.indexOf(":") === 0) return;

        // "data:" line — the payload for the current event.
        if (s.indexOf("data:") === 0) {
            var payload = s.substring(5).trim();
            if (payload === "[DONE]") { agent._handleRunCompleted(null); agent._finishStream(); return; }
            var evt = agent._sseCarryEvent;
            var data = null;
            try { data = JSON.parse(payload); } catch (e) { data = { text: payload }; }

            // Some servers fold the hook name into the data object instead of a
            // separate event: line. Honour whichever is present.
            if ((!evt || evt === "") && data) evt = data.event || data.type || "";

            agent._dispatchEvent(evt, data);
        }
    }

    // Route a parsed SSE event to its handler.
    function _dispatchEvent(evt, data) {
        // Tally for diagnostics (reveals repeated run.completed / segmented deltas).
        var key = (evt && evt !== "") ? evt : "(none)";
        agent._evtCounts[key] = (agent._evtCounts[key] || 0) + 1;
        switch (evt) {
            case "assistant.delta":
            case "message.delta":
            case "delta":
                agent._handleDelta(data); break;

            case "hermes.tool.progress":
            case "tool.started":
            case "tool.progress":
                agent._handleToolStart(data); break;

            case "tool.completed":
            case "tool.result":
                agent._handleToolCompleted(data); break;

            case "run.completed":
            case "response.completed":
            case "done":
                agent._handleRunCompleted(data); break;

            // Reasoning / scratchpad channels: the model's private thinking. Route
            // to a separate `thinking` field (collapsible in the UI), NOT the answer.
            case "thought":
            case "thinking":
            case "reasoning":
            case "assistant.thought":
            case "message.reasoning":
            case "channel":
                agent._handleThought(data); break;

            default:
                // Unknown hook: append ONLY if it's clearly a visible-text token AND
                // not a reasoning channel. Reasoning markers go to _handleThought.
                var dtype = (data && (data.channel || data.type || data.event)) || "";
                dtype = String(dtype).toLowerCase();
                var isThought = (evt && /thought|think|reason|channel/.test(String(evt).toLowerCase()))
                             || /thought|think|reason/.test(dtype);
                if (isThought) { agent._handleThought(data); }
                else if (data && (data.delta || data.text || data.content))
                    agent._handleDelta(data);
        }
    }

    // 1) assistant.delta — append/merge answer tokens, de-duplicating repeats.
    //    Servers vary: some send incremental tokens in `delta`, some resend the
    //    FULL answer-so-far in `content`/`text`, and some (after a tool) re-stream
    //    the whole final answer again. Handling all three naively concatenates and
    //    produces 2–3× repeated text. We keep ONE growing answer per turn and merge.
    function _handleDelta(data) {
        if (!data) return;
        var hasIncremental = (data.delta !== undefined && data.delta !== null && data.delta !== "")
                          || (data.token !== undefined && data.token !== null && data.token !== "");
        var inc  = data.delta || data.token || "";
        var full = data.content || data.text || "";   // possible full-snapshot
        if (inc === "" && full === "") return;

        // Ensure we have a row to write into.
        if (_activeAssistantRow < 0) {
            timeline.append({
                role: "assistant", messageId: "", text: "",
                streaming: true, toolName: "", toolStatus: "",
                toolRunCtx: "", toolOutput: "", thinking: "", expanded: false
            });
            _activeAssistantRow = timeline.count - 1;
            _needNewAssistantRow = false;
            _turnAnswer = "";
        }

        if (hasIncremental) {
            // A tool boundary may flag a genuinely new segment → fresh row.
            if (_needNewAssistantRow) {
                timeline.append({
                    role: "assistant", messageId: "", text: "",
                    streaming: true, toolName: "", toolStatus: "",
                    toolRunCtx: "", toolOutput: "", thinking: "", expanded: false
                });
                _activeAssistantRow = timeline.count - 1;
                _needNewAssistantRow = false;
                _turnAnswer = "";
            }
            _turnAnswer += inc;
            timeline.setProperty(_activeAssistantRow, "text", _turnAnswer);
            timelineUpdated();
            return;
        }

        // Full-snapshot path (`content`/`text` carries the whole answer-so-far).
        var snap = String(full);
        if (snap === _turnAnswer) return;                       // identical → ignore
        if (_turnAnswer !== "" && snap.indexOf(_turnAnswer) === 0) {
            _turnAnswer = snap;                                 // snapshot extends ours → adopt
        } else if (_turnAnswer !== "" && _turnAnswer.indexOf(snap) === 0) {
            return;                                             // snapshot is a prefix → keep ours
        } else if (_needNewAssistantRow) {
            timeline.append({                                   // different segment after a tool
                role: "assistant", messageId: "", text: "",
                streaming: true, toolName: "", toolStatus: "",
                toolRunCtx: "", toolOutput: "", thinking: "", expanded: false
            });
            _activeAssistantRow = timeline.count - 1;
            _needNewAssistantRow = false;
            _turnAnswer = snap;
        } else {
            _turnAnswer = snap;                                 // unrelated snapshot → replace, don't concat
        }
        timeline.setProperty(_activeAssistantRow, "text", _turnAnswer);
        timelineUpdated();
    }

    // Reasoning/thought tokens — accumulate onto the active row's `thinking`
    // field (shown in a collapsible element), NOT the answer body.
    function _handleThought(data) {
        if (_activeAssistantRow < 0) return;
        var tok = "";
        if (data) tok = data.delta || data.text || data.content || data.thought || data.reasoning || "";
        if (tok === "") return;
        var row = timeline.get(_activeAssistantRow);
        timeline.setProperty(_activeAssistantRow, "thinking", (row && row.thinking ? row.thinking : "") + tok);
        timelineUpdated();
    }

    // 2) tool start/progress — spinner + run context. Inserts a tool row BEFORE
    //    the active assistant bubble so the transcript reads tool-then-answer.
    function _handleToolStart(data) {
        var name = (data && (data.name || data.tool || (data.tool_call && data.tool_call.name))) || "tool";
        var ctx  = (data && (data.context || data.message || data.status)) || _toolLabel(name);

        // If we already have a running tool row for this name, just update it.
        if (_activeToolRow >= 0) {
            var r = timeline.get(_activeToolRow);
            if (r && r.toolName === name) {
                timeline.setProperty(_activeToolRow, "toolRunCtx", ctx);
                return;
            }
        }
        // Insert just before the (empty/streaming) assistant bubble if present,
        // else append at the end.
        var insertAt = (_activeAssistantRow >= 0) ? _activeAssistantRow : timeline.count;
        timeline.insert(insertAt, {
            role: "tool", messageId: "",
            text: "",
            streaming: false,
            toolName: name,
            toolStatus: "running",
            toolRunCtx: ctx,
            toolOutput: "",
            thinking: "",
            expanded: false
        });
        _activeToolRow = insertAt;
        // The assistant row shifted down by one.
        if (_activeAssistantRow >= insertAt) _activeAssistantRow += 1;
        timelineUpdated();
    }

    // 3) tool.completed — stop spinner, drop output into the accordion.
    function _handleToolCompleted(data) {
        var out = "";
        if (data) out = _stringify(data.output || data.result || data.content || data.text || data.status || "");
        var ok = !(data && (data.error || data.is_error || data.status === "error"));
        if (_activeToolRow >= 0) {
            timeline.setProperty(_activeToolRow, "toolStatus", ok ? "done" : "error");
            timeline.setProperty(_activeToolRow, "toolOutput", out);
        }
        _activeToolRow = -1;            // ready for the next tool in the loop
        _needNewAssistantRow = true;    // next assistant text is a NEW segment
        timelineUpdated();
    }

    // 4) run.completed — a run segment concluded. Per spec this ends the whole
    //    loop, but some servers emit it per agent step; so we finalise the current
    //    segment and mark that any further assistant text is a new row. The true
    //    end-of-stream is the curl process closing (onRunningChanged → _finishStream).
    function _handleRunCompleted(data) {
        if (data && _activeAssistantRow >= 0) {
            var finalTxt = data.output_text || data.content
                || (data.message && data.message.content) || "";
            if (finalTxt && finalTxt !== "") {
                // Reconcile with the segment's accumulated text. Adopt the final
                // only if it EXTENDS what we have (or we have nothing); if it's a
                // prefix/equal/shorter, keep what streamed. Never append.
                if (_turnAnswer === "" || finalTxt.length > _turnAnswer.length
                        || finalTxt.indexOf(_turnAnswer) === 0) {
                    _turnAnswer = finalTxt;
                    timeline.setProperty(_activeAssistantRow, "text", _turnAnswer);
                }
            }
            var mid = data.message_id || (data.message && data.message.id) || "";
            if (mid !== "") timeline.setProperty(_activeAssistantRow, "messageId", mid);
            timeline.setProperty(_activeAssistantRow, "streaming", false);
        }
        // Next assistant text (if the loop continues) starts a fresh segment.
        _needNewAssistantRow = true;
        timelineUpdated();
        // NOTE: do NOT _finishStream() here — wait for the process to actually close,
        // so a per-step run.completed doesn't prematurely end a multi-step turn.
    }

    // Common teardown for end-of-stream (clean or aborted).
    function _finishStream() {
        if (_activeAssistantRow >= 0)
            timeline.setProperty(_activeAssistantRow, "streaming", false);
        if (_activeToolRow >= 0 && timeline.get(_activeToolRow) &&
            timeline.get(_activeToolRow).toolStatus === "running")
            timeline.setProperty(_activeToolRow, "toolStatus", "done");
        _activeAssistantRow = -1;
        _activeToolRow = -1;
        _sseCarryEvent = "";
        // Summarise event counts (e.g. "assistant.delta×42 run.completed×3").
        var parts = [];
        for (var k in agent._evtCounts) { if (agent._evtCounts.hasOwnProperty(k)) parts.push(k + "×" + agent._evtCounts[k]); }
        agent.evtSummary = parts.join("  ");
        agent.lastStreamLog = "EVENTS: " + agent.evtSummary + "\n" + agent.lastStreamLog;
        console.log("[HermesSessionAgent] stream events: " + agent.evtSummary);
        timelineUpdated();
        if (isStreaming) {
            isStreaming = false;
            streamFinished();
        }
        // Refresh the sidebar so the just-updated session bubbles to the top.
        listSessions();
    }

    // =========================================================================
    //  3. PROMPT EDITING & FORKING WORKFLOW
    // =========================================================================
    //   POST /api/sessions/{active}/fork  { title, target_message_id }
    //     -> { new_session_id }
    //
    //   On edit of an earlier bubble:
    //     1. take its target_message_id
    //     2. fork (clones DB lineage up to that message)
    //     3. switch active session to new_session_id
    //     4. wipe timeline rows AFTER the edit point
    //     5. stream the edited prompt against the new session
    //
    //   Forking (rather than mutating in place) keeps the SQLite lineage and any
    //   tool/file-system paths from the original branch intact.

    // editAndFork: the one call the UI makes when the user confirms an edit.
    //   targetMessageId — id of the user bubble being edited (the fork anchors
    //                     the new branch at that point in history)
    //   newText         — the replacement prompt to send on the new branch
    function editAndFork(targetMessageId, newText) {
        if (activeSessionId === "" || isStreaming) return;
        var t = (newText || "").trim();
        if (t === "") return;

        // Find the row for this message so we can rewind the UI after the fork
        // returns. We rewind to JUST BEFORE that row (the edited prompt is
        // re-sent fresh on the new branch).
        var rewindTo = _rowIndexForMessage(targetMessageId);
        _pendingForkPrompt = t;
        _pendingRewindIndex = rewindTo;

        agent.lastForkTitle = "Edited: " + t.substring(0, 40);
        var body = { title: agent.lastForkTitle, target_message_id: targetMessageId };

        _forkProc.command = ["bash", "-c",
            "curl -s -w '\\nHTTP_STATUS:%{http_code}' -X POST " +
            _authHeader() +
            "-H 'Content-Type: application/json' " +
            "--data '" + _jsonArg(body) + "' " +
            "'" + _shq(sessionsBase + "/" + activeSessionId + "/fork") + "'"
        ];
        _forkProc.running = true;
    }
    property int _pendingRewindIndex: -1
    Process {
        id: _forkProc
        command: ["bash", "-c", "true"]
        stdout: StdioCollector {
            onStreamFinished: {
                var parsed = agent._splitStatus(this.text);
                if (parsed.status === 429) { agent._flagError("rate_limited", parsed.body); agent._pendingForkPrompt = ""; return; }
                if (parsed.status === 0 || parsed.status >= 500) {
                    agent._flagError(parsed.status === 0 ? "network" : "http_5xx", parsed.body);
                    agent._pendingForkPrompt = ""; return;
                }
                try {
                    var o = JSON.parse(parsed.body);
                    var nid = o.new_session_id || o.session_id || o.id || "";
                    if (nid === "") { agent._flagError("fork_failed", parsed.body); agent._pendingForkPrompt = ""; return; }

                    // (4) Wipe the timeline tail after the edit point, silently.
                    if (agent._pendingRewindIndex >= 0) {
                        while (agent.timeline.count > agent._pendingRewindIndex)
                            agent.timeline.remove(agent.timeline.count - 1);
                    }
                    // (3) Switch the active anchor to the new branch.
                    agent.activeSessionId = nid;
                    agent.lastError = "";
                    agent.sessionCreated(nid);

                    // (5) Re-stream the edited prompt against the new session.
                    var prompt = agent._pendingForkPrompt;
                    agent._pendingForkPrompt = "";
                    agent._pendingRewindIndex = -1;
                    if (prompt !== "") agent._appendAndStream(prompt);
                } catch (e) {
                    agent._flagError("bad_json", parsed.body);
                    agent._pendingForkPrompt = "";
                }
            }
        }
    }

    // =========================================================================
    //  SHARED UTILITIES
    // =========================================================================

    // Split a curl response that ends in "\nHTTP_STATUS:NNN" into { body, status }.
    function _splitStatus(raw) {
        var text = (raw === undefined || raw === null) ? "" : String(raw);
        var marker = "HTTP_STATUS:";
        var idx = text.lastIndexOf(marker);
        if (idx < 0) return { body: text, status: 200 };   // no sentinel → assume ok
        var body = text.substring(0, idx).replace(/\s+$/, "");
        var status = parseInt(text.substring(idx + marker.length).trim(), 10);
        if (isNaN(status)) status = 0;
        return { body: body, status: status };
    }

    // Coerce any tool payload (object/array/string) to a displayable string.
    function _stringify(v) {
        if (v === undefined || v === null) return "";
        if (typeof v === "string") return v;
        try { return JSON.stringify(v, null, 2); } catch (e) { return String(v); }
    }

    // Find a session id in a create/response object: check top-level id-ish keys
    // first, then descend into common wrapper objects (session/data/result/…).
    function _findId(o) {
        if (!o || typeof o !== "object") return "";
        var idKeys = ["session_id","sessionId","id","sid","uuid","key"];
        var direct = _pick(o, idKeys);
        if (direct && direct !== "") return String(direct);
        var wrappers = ["session","data","result","conversation","chat","thread","payload"];
        for (var i = 0; i < wrappers.length; i++) {
            var w = o[wrappers[i]];
            if (w && typeof w === "object") {
                var nested = _pick(w, idKeys);
                if (nested && nested !== "") return String(nested);
            }
        }
        // Last resort: shallow scan for any *_id / id field.
        for (var k in o) {
            if (!o.hasOwnProperty(k)) continue;
            if ((k === "id" || /(^|_)id$/.test(k)) && o[k] && typeof o[k] !== "object")
                return String(o[k]);
        }
        return "";
    }

    // Return the first non-empty value among `keys` on object `o`.
    function _pick(o, keys) {
        if (!o || typeof o !== "object") return "";
        for (var i = 0; i < keys.length; i++) {
            var v = o[keys[i]];
            if (v !== undefined && v !== null && v !== "") return v;
        }
        return "";
    }

    // Flatten an OpenAI-style content array ([{type:'text', text:'…'}, …]) or a
    // content object into a plain string.
    function _flattenContent(c) {
        if (c === undefined || c === null) return "";
        if (typeof c === "string") return c;
        if (Array.isArray(c)) {
            var out = "";
            for (var i = 0; i < c.length; i++) {
                var part = c[i];
                if (typeof part === "string") out += part;
                else if (part && typeof part === "object")
                    out += (part.text || part.content || part.value || "");
            }
            return out;
        }
        if (typeof c === "object") return c.text || c.content || c.value || "";
        return String(c);
    }

    // Find the list of session objects inside an arbitrary response shape:
    //   • a bare array
    //   • an object wrapping the array under a common key (sessions/data/items/…)
    //   • an object MAP keyed by id, whose values are session objects
    //   • a deep object: first array-of-objects found anywhere
    function _extractArray(root) {
        if (Array.isArray(root)) return root;
        if (!root || typeof root !== "object") return [];

        var keys = ["sessions","data","items","results","list","conversations",
                    "chats","rows","records","entries","threads"];
        for (var k = 0; k < keys.length; k++) {
            if (Array.isArray(root[keys[k]])) return root[keys[k]];
        }
        // Object map keyed by id → values are the sessions.
        var vals = [];
        var objCount = 0, total = 0;
        for (var key in root) {
            if (!root.hasOwnProperty(key)) continue;
            total++;
            var v = root[key];
            if (v && typeof v === "object" && !Array.isArray(v)) {
                // Stamp the map key as an id if the value lacks one.
                if (v.id === undefined && v.session_id === undefined) v.id = key;
                vals.push(v); objCount++;
            }
        }
        if (objCount > 0 && objCount === total) return vals;

        // Last resort: depth-first search for the first array of objects.
        var found = _findArrayOfObjects(root, 0);
        return found || [];
    }

    function _findArrayOfObjects(node, depth) {
        if (depth > 4 || !node || typeof node !== "object") return null;
        if (Array.isArray(node)) {
            if (node.length > 0 && typeof node[0] === "object") return node;
            return null;
        }
        for (var key in node) {
            if (!node.hasOwnProperty(key)) continue;
            var r = _findArrayOfObjects(node[key], depth + 1);
            if (r) return r;
        }
        return null;
    }

    // Find the timeline row index that carries a given server message id.
    function _rowIndexForMessage(mid) {
        if (!mid || mid === "") return -1;
        for (var i = 0; i < timeline.count; i++) {
            var r = timeline.get(i);
            if (r && r.messageId === mid) return i;
        }
        return -1;
    }

    // Friendly run-context label for a tool name (used when the server doesn't
    // send its own context string).
    function _toolLabel(name) {
        var n = String(name || "").toLowerCase();
        if (n.indexOf("shell") >= 0 || n.indexOf("terminal") >= 0 || n.indexOf("bash") >= 0)
            return "Executing Terminal Script…";
        if (n.indexOf("file") >= 0 || n.indexOf("read") >= 0 || n.indexOf("write") >= 0)
            return "Working with files…";
        if (n.indexOf("search") >= 0 || n.indexOf("web") >= 0)
            return "Searching the web…";
        return "Running " + (name || "tool") + "…";
    }

    // Centralised error surfacing: set state, emit signal, release the UI.
    function _flagError(kind, detail) {
        lastError = kind;
        errorOccurred(kind, _stringify(detail).substring(0, 400));
        if (isStreaming) { isStreaming = false; streamFinished(); }
    }
}
