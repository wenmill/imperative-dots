import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Pdf
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: window

    // ── Passed from Main.qml ──
    property var notifModel

    // ── Scaling ──
    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val); }

    // ── Colors ──
    MatugenColors { id: _theme }
    readonly property color base:     _theme.base
    readonly property color mantle:   _theme.mantle
    readonly property color crust:    _theme.crust
    readonly property color text:     _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color overlay1: _theme.overlay1
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color mauve:    _theme.mauve
    readonly property color pink:     _theme.pink
    readonly property color red:      _theme.red
    readonly property color peach:    _theme.peach
    readonly property color yellow:   _theme.yellow
    readonly property color green:    _theme.green
    readonly property color teal:     _theme.teal
    readonly property color sapphire: _theme.sapphire
    readonly property color blue:     _theme.blue

    // ── API Config ──
    // apiKey/apiBaseUrl/selectedModel kept ONLY for learn mode (textbook
    // tutor), which still hits an OpenAI-compatible endpoint directly. Chat
    // routes through Hermes exclusively now.
    property string apiKey: ""
    property string apiBaseUrl: "http://localhost:4000"
    property string selectedModel: "Agentic-Intelligence"
    property string ollamaApiKey: ""
    property bool toolsPopupOpen: false
    property var activeTools: ({})
    property bool isLoading: false
    property bool temporaryChat: false
    property string chatSessionId: "qspopup-default"
    property string chatTitle: ""            // AI-generated title for current chat
    property bool chatHistoryOpen: false     // is the previous-chats dropdown open
    property string chatHistoryQuery: ""     // search box text

    // ── Modes ──
    property string activeMode: "chess"

    readonly property color modeColor1: activeMode === "chess" ? yellow
        : activeMode === "kavita" ? pink
        : activeMode === "chat" ? mauve
        : activeMode === "notes" ? peach
        : green
    readonly property color modeColor2: activeMode === "chess" ? peach
        : activeMode === "kavita" ? mauve
        : activeMode === "chat" ? blue
        : activeMode === "notes" ? yellow
        : teal

    // ── Notes state ──
    property string notesSubMode: "menu"
    property string obsidianVault: ""       // absolute vault path (for the save-safety check)
    property string obsidianVaultName: ""   // vault folder name (for obsidian:// URIs)
    ListModel { id: vaultNotes }
    property string selectedNoteContent: ""
    property string selectedNoteTitle: ""
    property string currentNoteFilepath: ""
    property bool notesLoading: false
    property bool noteAutoSaved: false
    property bool noteExpanding: false   // "Expand with AI" in-progress flag

    // ── Learn state ──
    property string learnSubMode: "home"
    property bool bookLoaded: false
    property string bookTitle: ""
    property string learnDir: Qt.resolvedUrl("").toString().replace("file://","") + "/../../.local/share/quickshell-learn"
    property int currentChapter: 0
    property int totalChapters: 0
    property string currentChapterTitle: ""
    property string currentChapterContent: ""
    property bool learnLoading: false
    property bool isRecording: false
    property string voiceTranscript: ""
    property int learnTypeLen: 0
    property string learnLastResponse: ""
    property string learnDisplayedResponse: learnLastResponse.substring(0, learnTypeLen)
    ListModel { id: bookChapters }
    ListModel { id: learnedTerms }
    ListModel { id: lessonChat }

    // ── Persistence ──
    Process {
        id: cacheSaver; command: ["bash", "-c", "echo idle"]
    }
    Process {
        id: cacheLoader; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "idle" || this.text.trim() === "") return;
                window.onCacheLoaded(this.text.trim());
            }
        }
    }
    property string pendingCacheType: ""

    function saveCache(name, data) {
        let json = JSON.stringify(data);
        let b64 = Qt.btoa(json);
        cacheSaver.command = ["bash", "-c",
            "mkdir -p ~/.cache/qs_ai_state && echo " + b64 + " | base64 -d > ~/.cache/qs_ai_state/" + name + ".json"
        ];
        cacheSaver.running = false;
        cacheSaver.running = true;
    }

    function loadCache(name) {
        window.pendingCacheType = name;
        cacheLoader.command = ["bash", "-c",
            "cat ~/.cache/qs_ai_state/" + name + ".json 2>/dev/null || echo '{}'"
        ];
        cacheLoader.running = false;
        cacheLoader.running = true;
    }

    function onCacheLoaded(text) {
        try {
            let data = JSON.parse(text);
            let t = window.pendingCacheType;

            if (t === "chat") {
                let ts = data.timestamp || 0;
                let now = Math.floor(Date.now() / 1000);
                if (data.sessionId) window.chatSessionId = data.sessionId;
                if (data.title !== undefined) window.chatTitle = data.title || "";
                // Always restore the cached messages (or lack thereof) verbatim
                // so a "New Chat" → close → reopen actually shows an empty chat
                // and not the previous conversation.
                if (now - ts < 10800 && data.messages) {
                    chatMessages.clear();
                    for (let i = 0; i < data.messages.length; i++)
                        chatMessages.append(data.messages[i]);
                    if (data.messages.length > 0) {
                        window.lastResponse = data.messages[data.messages.length - 1].content || "";
                        window.typeLen = window.lastResponse.length;
                    }
                }
                window.loadCache("learn");
            }
            else if (t === "learn") {
                if (data.bookTitle) {
                    window.bookTitle = data.bookTitle || "";
                    window.bookSeriesId = data.bookSeriesId || 0;
                    window.bookLoaded = data.bookLoaded || false;
                    window.learnSubMode = data.learnSubMode || "home";
                    window.currentChapter = data.currentChapter || 0;
                    window.lessonProgress = data.lessonProgress || 0;
                    if (data.chapters && data.chapters.length > 0) {
                        chapterList.clear();
                        for (let i = 0; i < data.chapters.length; i++)
                            chapterList.append(data.chapters[i]);
                    }
                    if (data.vocab && data.vocab.length > 0) {
                        learnedTerms.clear();
                        for (let i = 0; i < data.vocab.length; i++)
                            learnedTerms.append(data.vocab[i]);
                                    window.saveLearnState();
                    }
                    if (data.lessonChat && data.lessonChat.length > 0) {
                        lessonChat.clear();
                        for (let i = 0; i < data.lessonChat.length; i++)
                            lessonChat.append(data.lessonChat[i]);
                    }
                }
                window.loadCache("kavita_last");
            }
            else if (t === "kavita_last") {
                if (data.seriesId && data.libraryId) {
                    window.kavitaLastSeriesId = data.seriesId;
                    window.kavitaLastLibraryId = data.libraryId;
                    window.kavitaLastName = data.name || "";
                    window.kavitaLastFormat = data.format || 0;
                    window.kavitaReadFormat = data.format || 0;
                    // Restore the cached PDF state so reopening the popup
                    // doesn't re-download. The actual file existence is
                    // checked by kavitaCheckPdfCache below before we trust it.
                    if (data.pdfPath) window.kavitaPdfPath = data.pdfPath;
                    if (data.pdfChapterId) window.kavitaPdfChapterId = data.pdfChapterId;
                    if (data.readChapterId) window.kavitaReadChapterId = data.readChapterId;
                    if (data.readPage !== undefined) window.kavitaReadPage = data.readPage;
                    if (data.readTotalPages) window.kavitaReadTotalPages = data.readTotalPages;
                    // Verify the tmpfs file still exists (it gets cleared on
                    // reboot since tmpfs is RAM-backed). If not, clear the
                    // path so kavitaLoadPage knows to re-download.
                    if (window.kavitaPdfPath) {
                        kavitaPdfCacheCheck.command = ["bash", "-c",
                            "[ -s '" + window.kavitaPdfPath.replace(/'/g, "'\\''") + "' ] && echo ok || echo gone"
                        ];
                        kavitaPdfCacheCheck.running = false;
                        kavitaPdfCacheCheck.running = true;
                    }
                }
                window.loadCache("chess");
            }
            else if (t === "chess") {
                // Only restore NON-correspondence games into the full board view.
                // Correspondence is handled separately on the start-page mini-board
                // (restoreCorrFromConfig), so a saved corr game must NOT pull us into
                // the board — that was the "new game opens correspondence" bug.
                if (data.gameId && data.status === "playing" && data.isCorr !== true) {
                    // Don't blindly trust the cache — the game may be over on
                    // Lichess (finished/aborted) since we last saved. Verify it's
                    // still playable before restoring; otherwise drop to the menu
                    // so the user isn't stuck on a dead board.
                    window.chessGameId = data.gameId;
                    window.chessIsWhite = data.isWhite !== false;
                    window.chessOpponent = data.opponent || "Opponent";
                    window.chessVerifyAndRestore();
                }
            }
        } catch(e) {}
    }

    // Always persist current chat state — including when it's empty — so a
    // "New Chat" click followed by closing the popup doesn't restore the
    // previous conversation when the popup reopens. The session ID is also
    // saved so Hermes threads the right history across calls.
    function saveChatState() {
        if (window.temporaryChat) return;
        let msgs = [];
        for (let i = 0; i < chatMessages.count; i++) {
            let m = chatMessages.get(i);
            msgs.push({ role: m.role, content: m.content });
        }
        saveCache("chat", {
            messages: msgs,
            sessionId: window.chatSessionId,
            title: window.chatTitle,
            timestamp: Math.floor(Date.now() / 1000)
        });
    }

    // Archive the current conversation under ~/.local/share/quickshell-chats/
    // and start a brand-new Hermes session. Called when the user clicks
    // "New Chat" — the previous chat stays fully intact in Hermes's own
    // session store (resume/search read from there). We just rotate to a fresh
    // session id and clear the view.
    // Open the Hermes multi-agent Kanban board. Ensures the board exists and the
    // gateway (which hosts the dispatcher + dashboard) is running, then opens the
    // dashboard in the browser. All idempotent: init/start are no-ops if already
    // done. The dashboard is served at http://127.0.0.1:9119.
    // ── Native in-popup Kanban ──
    // Reads the Hermes kanban board via the CLI (`hermes kanban list --json`)
    // and groups tasks by status into columns rendered inside the popup. Also
    // supports adding a task and opening the full web dashboard.
    property bool kanbanOpen: false
    property bool kanbanLoading: false
    property string kanbanError: ""
    ListModel { id: kanbanTasks }   // {id, title, status, assignee}
    function toggleKanban() {
        window.kanbanOpen = !window.kanbanOpen;
        if (window.kanbanOpen) window.fetchKanban();
    }
    function fetchKanban() {
        window.kanbanLoading = true; window.kanbanError = "";
        kanbanFetchProc.command = ["bash", "-c",
            "export PATH=\"$HOME/.local/bin:$HOME/bin:$HOME/.hermes/venv/bin:$HOME/.cargo/bin:$PATH\"; " +
            "hermes kanban init >/dev/null 2>&1 || true; " +
            // Prefer JSON output; fall back to the gateway HTTP API if the CLI
            // lacks --json. Emit a single JSON array of {id,title,status,assignee}.
            "OUT=$(hermes kanban list --json 2>/dev/null); " +
            "if [ -z \"$OUT\" ]; then " +
            "  OUT=$(curl -s 'http://127.0.0.1:9119/api/kanban/tasks' 2>/dev/null); " +
            "fi; " +
            "echo \"$OUT\""
        ];
        kanbanFetchProc.running = false; kanbanFetchProc.running = true;
    }
    Process {
        id: kanbanFetchProc; command: ["bash", "-c", "echo '[]'"]
        stdout: StdioCollector { onStreamFinished: {
            window.kanbanLoading = false;
            kanbanTasks.clear();
            let raw = (this.text || "").trim();
            if (raw === "") { window.kanbanError = "No board data. Is the Hermes gateway running?"; return; }
            try {
                let data = JSON.parse(raw);
                // Accept either a bare array or {tasks:[...]} / {cards:[...]}.
                let arr = Array.isArray(data) ? data : (data.tasks || data.cards || data.items || []);
                for (let i = 0; i < arr.length; i++) {
                    let t = arr[i];
                    kanbanTasks.append({
                        taskId: (t.id || t.taskId || "").toString(),
                        title: t.title || t.name || t.summary || "(untitled)",
                        status: (t.status || t.column || t.state || "todo").toString().toLowerCase(),
                        assignee: t.assignee || t.agent || ""
                    });
                }
                if (arr.length === 0) window.kanbanError = "Board is empty. Add a task below.";
            } catch(e) {
                window.kanbanError = "Couldn't parse board data.";
            }
        }}
    }
    function kanbanAddTask(title) {
        let t = (title || "").trim();
        if (t === "") return;
        let b64 = Qt.btoa(t);
        kanbanAddProc.command = ["bash", "-c",
            "export PATH=\"$HOME/.local/bin:$HOME/bin:$HOME/.hermes/venv/bin:$HOME/.cargo/bin:$PATH\"; " +
            "T=$(echo " + b64 + " | base64 -d); " +
            "hermes kanban create \"$T\" >/dev/null 2>&1 || " +
            "hermes kanban add \"$T\" >/dev/null 2>&1 || true"
        ];
        kanbanAddProc.running = false; kanbanAddProc.running = true;
    }
    Process { id: kanbanAddProc; command: ["bash", "-c", "true"]
        stdout: StdioCollector { onStreamFinished: window.fetchKanban() } }
    function openKanban() {
        // Open the full web dashboard (for drag/drop and richer editing).
        Quickshell.execDetached(["bash", "-c",
            "export PATH=\"$HOME/.local/bin:$HOME/bin:$HOME/.hermes/venv/bin:$HOME/.cargo/bin:$PATH\"; " +
            "hermes kanban init >/dev/null 2>&1 || true; " +
            "if command -v hermes >/dev/null 2>&1 && hermes dashboard >/dev/null 2>&1; then :; " +
            "else " +
            "  if ! hermes gateway status >/dev/null 2>&1; then (hermes gateway start >/dev/null 2>&1 &); sleep 2; fi; " +
            "  xdg-open 'http://127.0.0.1:9119' >/dev/null 2>&1 || true; " +
            "fi"
        ]);
    }

    function startNewChat(temp) {
        // Generate a fresh session id (timestamp-prefixed so ls sorts naturally).
        let now = new Date();
        let pad = function(n) { return n < 10 ? "0" + n : "" + n; };
        let stamp = "" + now.getFullYear() + pad(now.getMonth() + 1) + pad(now.getDate()) +
                    "_" + pad(now.getHours()) + pad(now.getMinutes()) + pad(now.getSeconds());
        window.chatSessionId = (temp ? "qstemp-" : "qspopup-") + stamp;

        // Clear UI state for the new chat.
        chatMessages.clear();
        window.lastResponse = "";
        window.displayedResponse = "";
        window.typeLen = 0;
        window.temporaryChat = (temp === true);
        window.chatTitle = "";        // fresh chat has no title until generated
        window.chatHistoryOpen = false;

        // Write the new session pointer so the next hermes_bridge.sh call resumes
        // by this id. A temporary chat still gets a session id (so multi-turn
        // memory works WITHIN the chat) but is flagged not-to-save so it won't be
        // persisted to the popup's chat cache / surfaced in history.
        if (!window.temporaryChat) window.saveChatState();
        chatSessionWriter.command = ["bash", "-c",
            "mkdir -p \"$HOME/.cache/qs_ai_state\" && " +
            "printf '%s' '" + window.chatSessionId + "' > \"$HOME/.cache/qs_ai_state/hermes_session.txt\""
        ];
        chatSessionWriter.running = false; chatSessionWriter.running = true;

        if (typeof inputField !== "undefined") inputField.forceActiveFocus();
    }
    Process { id: chatArchiver; command: ["bash", "-c", "echo idle"] }
    Process { id: chatSessionWriter; command: ["bash", "-c", "echo idle"] }

    // ── AI-generated chat title ──────────────────────────────────────────
    // After the first exchange, ask Hermes for a 3-5 word title summarizing
    // the conversation. Runs in a throwaway oneshot session so it doesn't
    // pollute the chat's own context. Saved with the chat so it persists.
    function generateChatTitle() {
        if (chatMessages.count < 2) return;        // need at least one exchange
        if (window.chatTitle !== "") return;       // only generate once
        // Build a compact transcript (first user + first assistant msg is enough).
        let parts = [];
        for (let i = 0; i < Math.min(chatMessages.count, 4); i++) {
            let m = chatMessages.get(i);
            parts.push(m.role + ": " + (m.content || "").substring(0, 200));
        }
        let transcript = parts.join("\n").replace(/'/g, "'\\''");
        chatTitleProc.command = ["bash", "-c",
            "printf '%s' 'Summarize this conversation as a 3-5 word title. " +
            "Output ONLY the title, no quotes, no punctuation at the end:\\n\\n" + transcript + "' | " +
            "HERMES_SESSION_OVERRIDE=oneshot ~/.config/hypr/scripts/hermes_bridge.sh 2>/dev/null"
        ];
        chatTitleProc.running = false; chatTitleProc.running = true;
    }
    Process {
        id: chatTitleProc
        command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                let raw = (this.text || "").trim();
                if (raw === "" || raw === "idle") return;
                try {
                    let resp = JSON.parse(raw);
                    let t = (resp.content || "").trim();
                    t = t.replace(/^["'\u201c\u2018]+|["'\u201d\u2019.]+$/g, "");
                    if (t.length > 0 && t.length < 60) {
                        let oldTitle = window.chatSessionId;
                        window.chatTitle = t;
                        // Adopt the friendly title as the session's name in Hermes
                        // AND as our resume key, so future turns resume by it and
                        // the dropdown shows a human-readable title. Find the
                        // session currently named with our placeholder id and
                        // rename it; then repoint the session pointer file.
                        window.chatSessionId = t;
                        chatTitleRenamer.command = ["bash", "-c",
                            "T=" + JSON.stringify(t) + "; OLD=" + JSON.stringify(oldTitle) + "; " +
                            "ID=$(hermes sessions list --source cli 2>/dev/null | grep -F \"$OLD\" | grep -oE '[0-9]{8}_[0-9]{6}_[A-Za-z0-9]+' | head -1); " +
                            "if [ -z \"$ID\" ]; then ID=$(hermes sessions list --source cli 2>/dev/null | grep -oE '[0-9]{8}_[0-9]{6}_[A-Za-z0-9]+' | head -1); fi; " +
                            "[ -n \"$ID\" ] && hermes sessions rename \"$ID\" \"$T\" 2>/dev/null; " +
                            "printf '%s' \"$T\" > \"$HOME/.cache/qs_ai_state/hermes_session.txt\""
                        ];
                        chatTitleRenamer.running = false; chatTitleRenamer.running = true;
                        window.saveChatState();   // persist the title
                    }
                } catch(e) { /* ignore */ }
            }
        }
    }
    Process { id: chatTitleRenamer; command: ["bash", "-c", "echo idle"] }

    // ── Previous-chats history + AI search ───────────────────────────────
    ListModel { id: chatHistoryModel }       // {sessionId, title, ended, preview}
    property bool chatHistoryLoading: false

    // List the user's actual Hermes CLI sessions (the real archive in
    // ~/.hermes/state.db) rather than a parallel JSON store. We parse
    // `hermes sessions list` output into {sessionId(title), title, preview}.
    function loadChatHistory() {
        window.chatHistoryLoading = true;
        chatHistoryLister.command = ["bash", "-c",
            // sessions list prints: Preview | Last Active | Src | ID, columnar.
            // We emit a JSON line per CLI session: the title (if any) is what we
            // resume by; fall back to the raw ID. Preview is the first column.
            "hermes sessions list --source cli 2>/dev/null | " +
            "grep -oE '^.*[0-9]{8}_[0-9]{6}_[A-Za-z0-9]+' | " +
            "while IFS= read -r line; do " +
            "  id=$(printf '%s' \"$line\" | grep -oE '[0-9]{8}_[0-9]{6}_[A-Za-z0-9]+' | tail -1); " +
            "  preview=$(printf '%s' \"$line\" | sed -E 's/[0-9]{8}_[0-9]{6}_[A-Za-z0-9]+.*$//' | sed -E 's/[[:space:]]+(cli|tele|disc|slack|wa)?[[:space:]]*$//' | sed -E 's/[[:space:]]+[0-9]+[a-z]+ ago.*$//'); " +
            "  printf '{\"id\":\"%s\",\"preview\":\"%s\"}\\n' \"$id\" \"$(printf '%s' \"$preview\" | sed 's/\"/\\\\\"/g' | cut -c1-120)\"; " +
            "done"
        ];
        chatHistoryLister.running = false; chatHistoryLister.running = true;
    }
    Process {
        id: chatHistoryLister
        command: ["bash", "-c", "echo"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                let s = (line || "").trim();
                if (s === "") return;
                try {
                    let o = JSON.parse(s);
                    chatHistoryModel.append({
                        sessionId: o.id || "",
                        title: (o.preview && o.preview.length > 0) ? o.preview : (o.id || "Untitled chat"),
                        ended: 0,
                        preview: o.preview || ""
                    });
                } catch(e) { /* skip malformed line */ }
            }
        }
        onRunningChanged: { if (running) chatHistoryModel.clear(); else window.chatHistoryLoading = false; }
    }

    // AI semantic search across the user's REAL Hermes sessions. We export the
    // session archive to JSONL (id + title + a text join of messages), hand the
    // compact index to Hermes, and ask which session IDs match the natural
    // language query. Reads the actual ~/.hermes/state.db archive.
    property string chatSearchResultIds: ""   // comma-separated sessionIds, or "" = show all
    function runChatSearch(query) {
        let q = (query || "").trim();
        if (q === "") { window.chatSearchResultIds = ""; return; }
        let qq = q.replace(/'/g, "'\\''");
        chatSearchProc.command = ["bash", "-c",
            // Export all CLI sessions, build a compact 'TITLE :: preview' index
            // keyed by the title we resume with, then ask Hermes to pick matches.
            "TMP=$(mktemp); hermes sessions export \"$TMP\" --source cli >/dev/null 2>&1; " +
            "IDX=$(jq -rc 'select(.messages) | " +
            "  {t: (.title // .session_id // .id), " +
            "   p: ((.messages // []) | map(.content // \"\") | join(\" \") | .[0:200])} " +
            "  | \"\\(.t) :: \\(.p)\"' \"$TMP\" 2>/dev/null | head -80); " +
            "rm -f \"$TMP\"; " +
            "printf '%s' \"Past conversations, one per line as TITLE :: PREVIEW:\n$IDX\n\nThe user is searching for: '" + qq + "'\nOutput ONLY the matching TITLEs, comma-separated, best first. If none match, output NONE.\" | " +
            "HERMES_SESSION_OVERRIDE=oneshot ~/.config/hypr/scripts/hermes_bridge.sh 2>/dev/null"
        ];
        chatSearchProc.running = false; chatSearchProc.running = true;
    }
    Process {
        id: chatSearchProc
        command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                let raw = (this.text || "").trim();
                if (raw === "" || raw === "idle") return;
                try {
                    let resp = JSON.parse(raw);
                    let ids = (resp.content || "").trim();
                    if (ids === "NONE" || ids === "") window.chatSearchResultIds = "__none__";
                    else window.chatSearchResultIds = ids;
                } catch(e) { window.chatSearchResultIds = ""; }
            }
        }
    }

    // Open one of the user's real Hermes sessions. We point the session file at
    // its title so continued messages resume it, and load its transcript into
    // the view via `hermes sessions export --session-id`.
    function openArchivedChat(sessionTitle) {
        if (sessionTitle === "") return;
        // Archive nothing extra — Hermes already owns the history. Just switch.
        let safeTitle = sessionTitle.replace(/'/g, "'\\''");
        window.chatSessionId = sessionTitle;
        window.chatTitle = sessionTitle;
        window.chatHistoryOpen = false;
        chatArchiveLoader.command = ["bash", "-c",
            "printf '%s' '" + safeTitle + "' > \"$HOME/.cache/qs_ai_state/hermes_session.txt\"; " +
            // Find the session id for this title and export its messages as JSON.
            "ID=$(hermes sessions list --source cli 2>/dev/null | grep -F '" + safeTitle + "' | grep -oE '[0-9]{8}_[0-9]{6}_[A-Za-z0-9]+' | head -1); " +
            "if [ -z \"$ID\" ]; then ID='" + safeTitle + "'; fi; " +
            "TMP=$(mktemp); hermes sessions export \"$TMP\" --session-id \"$ID\" >/dev/null 2>&1; " +
            // Emit a clean {messages:[{role,content}]} object for the QML side.
            "jq -c '{messages: [(.messages // [])[] | select(.role==\"user\" or .role==\"assistant\") | {role, content: (.content // \"\")}]}' \"$TMP\" 2>/dev/null | head -1; " +
            "rm -f \"$TMP\""
        ];
        chatArchiveLoader.running = false; chatArchiveLoader.running = true;
    }
    Process {
        id: chatArchiveLoader
        command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                let raw = (this.text || "").trim();
                if (raw === "" || raw === "idle") return;
                try {
                    let data = JSON.parse(raw);
                    chatMessages.clear();
                    let msgs = data.messages || [];
                    for (let i = 0; i < msgs.length; i++) chatMessages.append(msgs[i]);
                    if (msgs.length > 0) {
                        window.lastResponse = msgs[msgs.length - 1].content || "";
                        window.typeLen = window.lastResponse.length;
                    }
                    window.saveChatState();
                } catch(e) { /* ignore */ }
            }
        }
    }

    function saveLearnState() {
        let chapters = [];
        for (let i = 0; i < chapterList.count; i++) {
            let c = chapterList.get(i);
            chapters.push({ title: c.title, filepath: c.filepath });
        }
        let vocab = [];
        for (let i = 0; i < learnedTerms.count; i++) {
            let v = learnedTerms.get(i);
            vocab.push({ term: v.term, reading: v.reading || "", meaning: v.meaning || "" });
        }
        let chat = [];
        for (let i = 0; i < lessonChat.count; i++) {
            let m = lessonChat.get(i);
            chat.push({ role: m.role, content: m.content });
        }
        saveCache("learn", {
            bookTitle: window.bookTitle, bookSeriesId: window.bookSeriesId,
            bookLoaded: window.bookLoaded, learnSubMode: window.learnSubMode,
            currentChapter: window.currentChapter, chapters: chapters,
            vocab: vocab, lessonChat: chat
        });
    }

    function saveKavitaLast(seriesId, libraryId, name) {
        saveCache("kavita_last", {
            seriesId: seriesId, libraryId: libraryId, name: name,
            format: window.kavitaReadFormat,
            // Persist the PDF scratch path so reopens find the cached file
            // instead of re-downloading. Cleared when switching series.
            pdfPath: window.kavitaPdfPath,
            pdfChapterId: window.kavitaPdfChapterId,
            readChapterId: window.kavitaReadChapterId,
            readPage: window.kavitaReadPage,
            readTotalPages: window.kavitaReadTotalPages
        });
    }

    function saveChessState() {
        saveCache("chess", {
            gameId: window.chessGameId, isWhite: window.chessIsWhite,
            opponent: window.chessOpponent, status: window.chessStatus,
            isCorr: window.chessIsCorr
        });
    }

    property int kavitaLastSeriesId: 0
    property int kavitaLastLibraryId: 0
    property string kavitaLastName: ""
    property int kavitaLastFormat: 0

    // ── Hermes / approval system ──
    Process {
        id: hermesRunner
        command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                window.isLoading = false;
                if (this.text.trim() === "idle" || this.text.trim() === "") return;
                try {
                    let resp = JSON.parse(this.text.trim());
                    if (resp.type === "tool_call") {
                        window.requestApproval(resp.command || "", resp.description || "Hermes wants to run a command");
                        return;
                    }
                    let msg = resp.content || resp.message || "(no output)";
                    chatMessages.append({ role: "assistant", content: msg });
                    window.lastResponse = msg;
                    window.typeLen = 0;
                    window.saveChatState();
                    window.generateChatTitle();   // name the chat after first exchange
                } catch(e) {
                    let raw = this.text.trim();
                    chatMessages.append({ role: "assistant", content: raw.substring(0, 2000) });
                    window.lastResponse = raw;
                    window.typeLen = 0;
                    window.saveChatState();
                }
            }
        }
    }

    function callHermes(query) {
        if (!window.hermesEnabled) return false;
        window.isLoading = true;
        // Hermes's one-shot mode (-z) does NOT reliably persist a session to
        // SQLite (upstream issue #11793), so resuming by title gives no memory.
        // We therefore carry the conversation ourselves: build a transcript from
        // chatMessages and prepend it to the prompt. The last chatMessages entry
        // is the current user turn (just appended in sendMessage), so we include
        // everything before it as history, then the new query.
        let hist = "";
        let n = chatMessages.count;
        // Cap history to the last ~24 turns to bound prompt size.
        let start = Math.max(0, n - 1 - 24);
        for (let i = start; i < n - 1; i++) {
            let m = chatMessages.get(i);
            if (!m || m.content === undefined) continue;
            let who = (m.role === "user") ? "User" : "Assistant";
            hist += who + ": " + m.content + "\n";
        }
        let full = query;
        if (hist !== "") {
            full = "Continue this conversation. Prior turns:\n" + hist +
                   "\nNow respond to the user's latest message:\nUser: " + query;
        }
        let b64 = Qt.btoa(full);
        hermesRunner.command = ["bash", "-c",
            "echo " + b64 + " | base64 -d | HERMES_SESSION_OVERRIDE=oneshot ~/.config/hypr/scripts/hermes_bridge.sh 2>/dev/null"
        ];
        hermesRunner.running = false;
        hermesRunner.running = true;
        return true;
    }

    function reportToolResult(approved, output) {
        let result = approved ? ("[ran successfully] " + output) : "[denied by user]";
        let b64 = Qt.btoa(result);
        hermesRunner.command = ["bash", "-c",
            "echo " + b64 + " | base64 -d | ~/.config/hypr/scripts/hermes_bridge.sh --continue 2>/dev/null"
        ];
        window.isLoading = true;
        hermesRunner.running = false;
        hermesRunner.running = true;
    }

    function requestApproval(cmd, desc) {
        if (window.approvalPolicy === "deny") {
            chatMessages.append({ role: "assistant", content: "Action denied by policy: " + cmd });
            return;
        }
        if (window.approvalPolicy === "auto") { window.runApprovedCommand(cmd); return; }
        window.pendingCommand = cmd;
        window.pendingDescription = desc;
        window.approvalPending = true;
    }

    Process {
        id: cmdRunner; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text.trim();
                let label = window.lastApprovedCmd;
                chatMessages.append({ role: "assistant", content: "[ran] $ " + label + (out ? "\n\n" + out.substring(0, 1500) : "") });
                window.lastResponse = "Ran: " + label;
                window.typeLen = window.lastResponse.length;
                window.saveChatState();
                if (window.hermesEnabled) window.reportToolResult(true, out.substring(0, 500));
            }
        }
    }
    property string lastApprovedCmd: ""

    function runApprovedCommand(cmd) {
        window.lastApprovedCmd = cmd;
        cmdRunner.command = ["bash", "-c", cmd + " 2>&1"];
        cmdRunner.running = false;
        cmdRunner.running = true;
        window.approvalPending = false;
        window.pendingCommand = "";
        window.pendingDescription = "";
    }
    function denyCommand() {
        chatMessages.append({ role: "user", content: "[denied] " + window.pendingCommand });
        let cmd = window.pendingCommand;
        window.approvalPending = false;
        window.pendingCommand = "";
        window.pendingDescription = "";
        if (window.hermesEnabled) window.reportToolResult(false, "User denied: " + cmd);
    }

    // ── Chess state ──
    property string lichessToken: ""
    property bool hermesEnabled: false
    property string hermesEndpoint: "http://localhost:5400/api/agent"
    property string hermesToken: ""
    property string approvalPolicy: "ask"
    property bool approvalPending: false
    property string pendingCommand: ""
    property string pendingDescription: ""
    property string chessGameId: ""
    property string chessStatus: "menu"  // menu | aisetup | seeking | playing | ended | puzzle | analysis
    // When we land on the chess menu, look for an ongoing correspondence game so
    // the start-page mini-board can mirror it (and we don't seek a new one while
    // one is active).
    onChessStatusChanged: { if (window.chessStatus === "menu") window.chessCheckCorrGame(); }
    onActiveModeChanged: { if (window.activeMode !== "chess" && window.activeMode !== "kavita") { window.activeMode = "chess"; return; } if (window.activeMode === "chess" && window.chessStatus === "menu") window.chessCheckCorrGame(); }
    property bool chessIsWhite: true
    property bool chessMyTurn: false
    property string lichessUsername: ""   // my own username, for detecting which color I am
    property var chessBoard: []
    property int chessSelected: -1
    property string chessResult: ""
    property string chessOpponent: ""
    property string chessOppInfo: ""   // hover card text (rating/title/online)
    function chessFetchOpponentInfo() {
        if (window.chessIsAiGame || window.chessOpponent === "") { window.chessOppInfo = ""; return; }
        let name = window.chessOpponent.replace(/[^A-Za-z0-9_-]/g, "");
        if (name === "") return;
        chessOppInfoProc.command = ["bash", "-c",
            "curl -s 'https://lichess.org/api/user/" + name + "' 2>/dev/null | " +
            "jq -r '(\"@\" + .username) + (if .title then \" \"+.title else \"\" end) + \"\\n\" + " +
            "\"blitz \" + ((.perfs.blitz.rating // \"-\")|tostring) + \"  rapid \" + ((.perfs.rapid.rating // \"-\")|tostring) + \"  classical \" + ((.perfs.classical.rating // \"-\")|tostring)' " +
            "2>/dev/null || echo ''"
        ];
        chessOppInfoProc.running = false; chessOppInfoProc.running = true;
    }
    Process { id: chessOppInfoProc; command: ["bash", "-c", "echo ''"]
        stdout: StdioCollector { onStreamFinished: {
            let t = (this.text || "").trim();
            // The jq above references .perfs inside a map where `.` is the perf
            // name string, so ratings won't resolve; do a simpler robust parse here.
            window.chessOppInfo = t;
        }}
    }
    property int chessFromIdx: -1
    property int chessToIdx: -1
    property int chessAiElo: 1500        // stockfish elo for slider (maps to level 1-8)
    property string chessPuzzleFen: ""
    property string chessPuzzleMoves: ""
    property int chessPuzzleRating: 0
    property string chessPuzzleStartFen: ""   // saved for reset
    property int chessPuzzleStep: 0           // next solution move index; even = opponent, odd = user
    property bool chessPuzzleSolved: false
    property string chessPuzzleFeedback: ""   // "" | "correct" | "wrong" | "solved"
    property string chessMoveError: ""        // transient error from Lichess (move rejection, network, etc.)
    // ── Board interaction: drag-to-move + planning arrows ──
    property int chessDragFrom: -1            // realIdx of piece being dragged, -1 = none
    property real chessDragX: 0               // live pointer position (board-local px)
    property real chessDragY: 0
    property bool chessDragging: false
    // Arrows: list of {from, to} realIdx pairs drawn by right-click-drag.
    property var chessArrows: []
    property int chessArrowFrom: -1           // realIdx where a right-drag started
    // ── Premoves ──
    // A queue of moves entered while it's the opponent's turn. When it becomes
    // our turn, the first premove is validated against the current position and
    // played (then the next becomes eligible after the opponent replies). Each
    // entry is { from, to, uci }. Multiple premoves are supported.
    property var chessPremoves: []
    // ── Audiobook control (drives the persistent player in Main.qml) ──
    // The popup never plays audio itself; it writes commands to a file that
    // Main.qml watches, so playback continues after the popup is destroyed.
    property bool audioPlaying: false
    property string audioTitle: ""
    property string audioUrl: ""
    property real audioPosMs: 0
    property real audioDurMs: 0
    property int audioSeriesId: 0   // which library series is currently loaded
    // Resolve an audio series' playable chapter + its saved resume position,
    // then start playback. Kavita exposes the chapter list per series/volume;
    // the LeviBickel fork stores a saved position per audio chapter. We fetch
    // the first chapter id and its progress, then issue the play command.
    function audioPlaySeries(seriesId, title) {
        window.audioSeriesId = seriesId;
        window.audioTitle = title || "Audiobook";
        audioResolveProc.command = ["bash", "-c",
            "U='" + window.kavitaUrl + "'; T='" + window.kavitaToken + "'; SID=" + seriesId + "; " +
            // Get the series' volumes/chapters; take the first chapter id.
            "CH=$(curl -s \"$U/api/Series/volumes?seriesId=$SID\" -H \"Authorization: Bearer $T\" 2>/dev/null | " +
            "  jq -r '[.[].chapters[]?.id] | first // empty' 2>/dev/null); " +
            "[ -z \"$CH\" ] && CH=$(curl -s \"$U/api/Series/chapter?seriesId=$SID\" -H \"Authorization: Bearer $T\" 2>/dev/null | jq -r '.id // empty' 2>/dev/null); " +
            // Saved progress (ms). The fork stores audio position; field name may
            // vary — try a few then default 0. (Confirm against your fork.)
            "POS=$(curl -s \"$U/api/Reader/get-progress?chapterId=$CH\" -H \"Authorization: Bearer $T\" 2>/dev/null | " +
            "  jq -r '(.audioPositionMs // .positionMs // .bookScrollId // 0)' 2>/dev/null); " +
            "echo \"$CH|$POS\""
        ];
        audioResolveProc.running = false; audioResolveProc.running = true;
    }
    Process {
        id: audioResolveProc; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector { onStreamFinished: {
            let raw = (this.text || "").trim();
            if (raw === "" || raw === "idle") return;
            let parts = raw.split("|");
            let chId = parseInt(parts[0]) || 0;
            let pos = parseInt(parts[1]) || 0;
            if (chId <= 0) return;
            window.kavitaAudioChapterId = chId;
            window.audioPlayChapter(chId, window.audioTitle, pos, -1);
        }}
    }
    Process {
        id: audioResumeProc; command: ["bash", "-c", "echo 0"]
        property string _title: ""
        property int _chapter: 0
        stdout: StdioCollector { onStreamFinished: {
            let pos = parseInt((this.text || "0").trim()) || 0;
            window.audioPlayChapter(audioResumeProc._chapter, audioResumeProc._title, pos, -1);
        }}
    }
    // ── Inline mpv control (no external script) ─────────────────────────────
    // The audiobook plays through mpv launched directly from QML. mpv exposes an
    // MPRIS interface (via its mpris plugin) so the TopBar media module controls
    // play-pause/seek over playerctl automatically. We talk to mpv through its
    // JSON IPC socket using socat, all inline here.
    readonly property string mpvSock: "/tmp/qs_kavita_mpv.sock"
    // Search common locations for mpv's MPRIS plugin; empty if not installed.
    readonly property string mpvMprisProbe:
        "for p in /usr/lib/mpv-mpris/mpris.so /usr/lib/mpv/mpris.so " +
        "/etc/mpv/scripts/mpris.so \"$HOME/.config/mpv/scripts/mpris.so\"; do " +
        "[ -f \"$p\" ] && { echo \"$p\"; break; }; done"
    // Send a raw JSON IPC command to the running mpv.
    function mpvIpc(jsonCmd) {
        Quickshell.execDetached(["bash", "-c",
            "printf '%s\\n' '" + jsonCmd.replace(/'/g, "'\\''") + "' | socat - " + window.mpvSock + " 2>/dev/null || true"]);
    }
    function audioSendCmd(obj) { /* retained no-op for any old callers */ }
    Process { id: audioCmdWriter; command: ["bash", "-c", "true"] }
    // Build a Kavita audio stream URL for a chapter. The LeviBickel fork serves
    // audio under the Reader family, which uses the ?apiKey= query param (NOT a
    // Bearer header) — same auth convention as the PDF/image reader endpoints.
    function kavitaAudioUrl(chapterId) {
        return window.kavitaUrl + "/api/Reader/audio?chapterId=" + chapterId +
               "&apiKey=" + window.kavitaApiKey;
    }
    // Start the audiobook for the current chapter, optionally from a position (ms).
    // Launches mpv directly with MPRIS + an IPC socket so the topbar controls it.
    function audioPlayChapter(chapterId, title, startMs, stopMs) {
        window.kavitaAudioChapterId = chapterId;
        let url = window.kavitaAudioUrl(chapterId);
        let startSec = ((startMs !== undefined && startMs >= 0) ? startMs : 0) / 1000.0;
        let safeUrl = url.replace(/'/g, "'\\''");
        let safeTitle = (title || "Audiobook").replace(/'/g, "'\\''");
        // Kill any existing instance, then launch fresh. MPRIS plugin is added only
        // if found, so playback still works without it (topbar just won't see it).
        Quickshell.execDetached(["bash", "-c",
            "pkill -f 'qs_kavita_mpv.sock' 2>/dev/null; sleep 0.2; rm -f " + window.mpvSock + "; " +
            "MPRIS=$(" + window.mpvMprisProbe + "); " +
            // --load-scripts=no stops mpv auto-loading /etc/mpv/scripts (which would
            // double-register MPRIS and fail). We then add mpris ourselves ONCE.
            "ARGS=(--no-video --idle=yes --force-window=no --load-scripts=no --input-ipc-server=" + window.mpvSock +
            " --title='" + safeTitle + "' --start=" + startSec.toFixed(3) + "); " +
            "[ -n \"$MPRIS\" ] && ARGS+=(--script=\"$MPRIS\"); " +
            "setsid mpv \"${ARGS[@]}\" '" + safeUrl + "' >/dev/null 2>&1 &"]);
        window.audioPlaying = true;
    }
    function audioToggle() { window.mpvIpc('{"command":["cycle","pause"]}'); window.audioPlaying = !window.audioPlaying; }
    function audioPause()  { window.mpvIpc('{"command":["set_property","pause",true]}'); window.audioPlaying = false; }
    function audioStop()   { Quickshell.execDetached(["bash", "-c", "pkill -f 'qs_kavita_mpv.sock' 2>/dev/null; rm -f " + window.mpvSock]); window.audioPlaying = false; }
    function audioSeek(ms) { window.mpvIpc('{"command":["set_property","time-pos",' + (ms/1000.0) + ']}'); }
    // Play the companion audiobook starting from a text position. Today this can
    // only start at a PAGE granularity (page→ms is a rough heuristic) because the
    // LeviBickel fork stores a saved position but NOT text↔audio alignment. When
    // the fork later exposes a page/passage→timestamp map, replace the body here:
    //   - `page` is the current PDF/EPUB page
    //   - `selectionText` is the highlighted passage (empty if none)
    //   - if a non-empty selection is given, set stopMs to the selection's end
    // so playback stops at the end of the selection (your spec). For now we start
    // at a page-derived offset and play to the end.
    function audioPlayFromSelection(page, selectionText) {
        if (!window.kavitaHasCompanionAudio) return;
        // Placeholder mapping: 1s per page index. This is intentionally crude and
        // exists so the UI is fully wired; swap for a real lookup once available.
        let startMs = Math.max(0, (page || 0) * 1000);
        let stopMs = -1;   // with alignment data, set to selection end here
        window.audioPlayChapter(window.kavitaAudioChapterId, window.kavitaReadTitle, startMs, stopMs);
    }
    // Poll the player's published state so our buttons reflect reality. Runs while
    // on the Kavita page OR whenever audio is actually playing (so position keeps
    // saving even after you leave Kavita and control it from the top bar).
    Timer {
        id: audioStatePoller; interval: 1000; repeat: true
        running: window.activeMode === "kavita" || window.audioPlaying || window.kavitaAudioChapterId > 0
        onTriggered: audioStateReader.running = false, audioStateReader.running = true
    }
    // Every ~10s while playing, persist the position to Kavita so the title
    // resumes where you left off next session. (Endpoint/field per the fork —
    // confirm; this is the documented Reader progress shape.)
    Timer {
        id: audioSaveTimer; interval: 10000; repeat: true
        running: window.audioPlaying && window.kavitaAudioChapterId > 0
        onTriggered: {
            let body = JSON.stringify({ chapterId: window.kavitaAudioChapterId, audioPositionMs: Math.round(window.audioPosMs) });
            let b64 = Qt.btoa(body);
            audioSaveProc.command = ["bash", "-c",
                "echo " + b64 + " | base64 -d | curl -s -X POST '" + window.kavitaUrl + "/api/Reader/progress' " +
                "-H 'Authorization: Bearer " + window.kavitaToken + "' -H 'Content-Type: application/json' -d @- >/dev/null 2>&1"
            ];
            audioSaveProc.running = false; audioSaveProc.running = true;
            // Also persist locally so it resumes even if Kavita is unreachable.
            Config.saveAudioBookPos(window.kavitaAudioChapterId, window.audioPosMs, window.audioTitle);
        }
    }
    Process { id: audioSaveProc; command: ["bash", "-c", "true"] }
    Process {
        id: audioStateReader
        // Query mpv's IPC socket for live state; emit one compact line we can parse.
        // If mpv isn't running (no socket), emit a 'stopped' marker.
        command: ["bash", "-c",
            "S=/tmp/qs_kavita_mpv.sock; " +
            "if [ ! -S \"$S\" ]; then echo 'STOPPED'; exit 0; fi; " +
            "g(){ printf '{\"command\":[\"get_property\",\"%s\"]}\\n' \"$1\" | socat - \"$S\" 2>/dev/null | jq -r 'select(.error==\"success\")|.data' 2>/dev/null | head -1; }; " +
            "P=$(g pause); T=$(g media-title); POS=$(g time-pos); DUR=$(g duration); " +
            "echo \"PLAYING=$([ \\\"$P\\\" = false ] && echo 1 || echo 0)\"; " +
            "echo \"TITLE=$T\"; echo \"POS=$POS\"; echo \"DUR=$DUR\""]
        stdout: StdioCollector { onStreamFinished: {
            let txt = (this.text || "").trim();
            if (txt === "STOPPED" || txt === "") {
                window.audioPlaying = false; window.audioPosMs = 0; window.audioDurMs = 0;
                return;
            }
            try {
                let lines = txt.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    let eq = lines[i].indexOf("=");
                    if (eq < 0) continue;
                    let k = lines[i].substring(0, eq), v = lines[i].substring(eq + 1);
                    if (k === "PLAYING") window.audioPlaying = (v === "1");
                    else if (k === "TITLE" && v) window.audioTitle = v;
                    else if (k === "POS" && v && v !== "null") window.audioPosMs = Math.round(parseFloat(v) * 1000);
                    else if (k === "DUR" && v && v !== "null") window.audioDurMs = Math.round(parseFloat(v) * 1000);
                }
            } catch(e) {}
        }}
    }

    // ── Game actions feedback ──
    property string chessActionFlash: ""      // transient "Draw offered" etc.
    // ── Clocks ──
    property int chessWhiteMs: 0              // white's remaining time (ms)
    property int chessBlackMs: 0              // black's remaining time (ms)
    property bool chessIsAiGame: false        // true vs Stockfish — clocks hidden
    property bool chessClocksKnown: false     // whether the server gave us clock data
    property bool chessIsCorr: false          // true for correspondence games (no clock, no chat/resign UI)
    // ── Computer analysis ──
    property string chessAnalysisStatus: "none"  // none|requesting|polling|ready|timeout
    property int chessAnalysisPollCount: 0
    property var chessAnalysisWhite: ({})
    property var chessAnalysisBlack: ({})
    property string chessAnalysisMovesStr: ""
    property int chessAnalysisPly: 0          // which ply the analysis board is showing
    // ── In-game chat ──
    property string chessChatRoom: "player"   // player | spectator
    property bool chessChatOpen: false

    // ── Kavita state ──
    property string kavitaUrl: "http://localhost:5000"
    property string kavitaApiKey: ""
    property string kavitaToken: ""
    property bool kavitaConnected: false
    property bool kavitaLoading: false
    ListModel { id: kavitaSeries }
    ListModel { id: kavitaOnDeck }
    ListModel { id: kavitaAllSeries }
    ListModel { id: kavitaLibraryCats }   // {name, count} distinct library categories
    function kavitaRebuildLibraryCats() {
        let counts = {};
        let order = [];
        for (let i = 0; i < kavitaAllSeries.count; i++) {
            let cat = kavitaAllSeries.get(i).libraryName || "Other";
            if (counts[cat] === undefined) { counts[cat] = 0; order.push(cat); }
            counts[cat] += 1;
        }
        kavitaLibraryCats.clear();
        for (let k = 0; k < order.length; k++)
            kavitaLibraryCats.append({ name: order[k], count: counts[order[k]] });
    }
    property string kavitaLibFilter: "all"
    property string kavitaLibExpanded: ""   // which library category is expanded in the nested view
    property string kavitaSubMode: "ondeck"  // "ondeck" | "library" | "serieschapters" | "reading"
    property int kavitaBrowseSeriesId: 0     // series whose chapters are being browsed
    property string kavitaBrowseSeriesName: ""
    property int kavitaBrowseSeriesLib: 0
    property int kavitaBrowseSeriesFmt: 0
    property bool kavitaBrowseLoading: false

    // ── Kavita reader state ──
    property int kavitaReadSeriesId: 0
    property int kavitaReadChapterId: 0
    property int kavitaReadVolumeId: 0
    property int kavitaReadPage: 0
    // Cover-page-then-resume: when a book is opened with saved progress, we
    // show the cover (page 0) but stash the real page here. The first page
    // turn jumps to it.
    property int kavitaResumePage: -1      // -1 = no pending resume
    property bool kavitaOnCoverPage: false
    property int kavitaReadTotalPages: 0
    property string kavitaReadTitle: ""
    property string kavitaReadBookTitle: ""   // individual book/chapter title (when picked from browse)
    property bool kavitaTitleLocked: false    // when true, chapter-info won't overwrite the title
    property string kavitaReadContent: ""
    property bool kavitaReadLoading: false
    property int kavitaReadFormat: 0       // 0=image,3=epub,4=pdf, (fork) audio=see kavitaAudioFormatCode
    // The LeviBickel audiobook fork adds an audio MangaFormat. Standard Kavita
    // uses 0=Image,1=Archive,2=Unknown,3=Epub,4=Pdf; the fork's audio code is
    // most likely 5. Centralized here so it's a one-line fix if the fork differs.
    property int kavitaAudioFormatCode: 5
    // True if the currently-open book IS an audio-only title.
    property bool kavitaIsAudio: window.kavitaReadFormat === window.kavitaAudioFormatCode
    // True if the open book has an accompanying audiobook (text + audio). The
    // fork exposes this; until the exact field is confirmed, default false and
    // flip it from the chapter-info handler when the fork reports companion audio.
    property bool kavitaHasCompanionAudio: false
    property int kavitaAudioChapterId: 0   // chapter id to stream audio from
    // PDF reader (format=4) — Kavita serves raw PDF bytes; we cache locally and render
    // with QtQuick.Pdf (PDFium), matching Kavita's own client-side approach.
    property string kavitaPdfPath: ""      // local cached PDF file path
    property int kavitaPdfChapterId: 0     // which chapterId is currently cached
    ListModel { id: kavitaChapters }

    Timer {
        id: learnTypewriter; interval: 8; repeat: true
        running: learnTypeLen < learnLastResponse.length
        onTriggered: learnTypeLen = Math.min(learnTypeLen + 4, learnLastResponse.length)
    }

    ListModel { id: chatMessages }
    property bool greetingFetched: false
    property string greetingText: "Hey! What can I help you with?"

    property int typeLen: 0
    property string lastResponse: ""
    property string displayedResponse: lastResponse.substring(0, typeLen)
    Timer {
        id: typewriterTimer; interval: 8; repeat: true
        running: typeLen < lastResponse.length
        onTriggered: typeLen = Math.min(typeLen + 4, lastResponse.length)
    }

    // ── Read API config ──
    Process {
        id: configReader; running: true
        command: ["bash", "-c", "cat ~/.config/hypr/ai_config.json 2>/dev/null || echo '{}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let cfg = JSON.parse(this.text.trim());
                    if (cfg.api_key) window.apiKey = cfg.api_key;
                    if (cfg.base_url) window.apiBaseUrl = cfg.base_url;
                    if (cfg.model) window.selectedModel = cfg.model;
                    if (cfg.ollama_api_key) window.ollamaApiKey = cfg.ollama_api_key;
                    if (cfg.lichess_token) { window.lichessToken = cfg.lichess_token; window.chessFetchAccount(); }
                    if (cfg.kavita_url) window.kavitaUrl = cfg.kavita_url;
                    if (cfg.kavita_api_key) window.kavitaApiKey = cfg.kavita_api_key;
                    if (cfg.hermes_enabled !== undefined) window.hermesEnabled = cfg.hermes_enabled;
                    if (cfg.hermes_endpoint) window.hermesEndpoint = cfg.hermes_endpoint;
                    if (cfg.hermes_token) window.hermesToken = cfg.hermes_token;
                    if (cfg.approval_policy) window.approvalPolicy = cfg.approval_policy;
                } catch(e) {}
                if (window.kavitaUrl && window.kavitaApiKey) window.kavitaAuth();
            }
        }
    }

    // ── Note saver (auto-save) ──
    Process {
        id: noteSaver; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() !== "idle") { window.noteAutoSaved = true; autoSavedResetTimer.restart(); }
            }
        }
    }
    Timer {
        id: autoSaveTimer; interval: 1200; repeat: false
        onTriggered: {
            if (window.currentNoteFilepath === "" || noteArea.text.trim() === "") return;
            if (window.obsidianVault !== "" && window.currentNoteFilepath.indexOf(window.obsidianVault) !== 0) { console.warn("Refusing to save note outside vault:", window.currentNoteFilepath); return; }
            let b64 = Qt.btoa(noteArea.text);
            noteSaver.command = ["bash", "-c", "echo " + b64 + " | base64 -d > '" + window.currentNoteFilepath.replace(/'/g, "'\\''") + "'"];
            noteSaver.running = false; noteSaver.running = true;
        }
    }
    Timer { id: autoSavedResetTimer; interval: 2000; repeat: false; onTriggered: window.noteAutoSaved = false }

    // ── Expand with AI (stays inside the notes module) ──
    // Sends the note text to hermes_bridge.sh with a one-shot session (so it
    // doesn't pollute the chat history), then appends the AI's reply to the
    // note below a divider. The user stays on their note the entire time.
    function expandNoteInPlace() {
        let text = noteArea.text.trim();
        if (text === "" || window.noteExpanding) return;
        if (!window.hermesEnabled) {
            noteArea.text = noteArea.text +
                "\n\n---\n\n_Hermes is not enabled. Set `hermes_enabled=true` in `~/.config/hypr/ai_config.json`._\n";
            return;
        }
        window.noteExpanding = true;
        let prompt = "Expand and improve these notes into a well-structured document. " +
                     "Keep the original ideas but add detail, fix grammar, and organize with markdown headers. " +
                     "Respond with ONLY the expanded document — no preface, no commentary.\n\n" + text;
        let b64 = Qt.btoa(prompt);
        noteExpanderProc.command = ["bash", "-c",
            "echo " + b64 + " | base64 -d | " +
            "HERMES_SESSION_OVERRIDE=oneshot " +
            "~/.config/hypr/scripts/hermes_bridge.sh 2>/dev/null"
        ];
        noteExpanderProc.running = false;
        noteExpanderProc.running = true;
    }
    Process {
        id: noteExpanderProc
        command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                window.noteExpanding = false;
                let raw = this.text.trim();
                if (raw === "" || raw === "idle") {
                    noteArea.text = noteArea.text + "\n\n---\n\n_AI expansion failed — no response._\n";
                    return;
                }
                let body = "";
                try {
                    let resp = JSON.parse(raw);
                    if (resp.type === "tool_call") {
                        // We disallow tool calls from the note expander on purpose:
                        // it should be a pure text completion, never a shell command.
                        body = "_AI tried to run a command — ignored. (Use Chat mode for tool use.)_";
                    } else {
                        body = resp.content || resp.message || raw;
                    }
                } catch(e) {
                    body = raw.substring(0, 8000);
                }
                noteArea.text = noteArea.text + "\n\n---\n\n" + body + "\n";
                // Nudge the autosave so the expansion gets persisted to disk.
                if (window.notesSubMode === "edit" && window.currentNoteFilepath !== "") autoSaveTimer.restart();
            }
        }
    }

    function createNewNote() {
        newNoteCreator.command = ["bash", "-c",
            "VAULT=$(find ~/Documents ~/Notes ~/Obsidian -name .obsidian -maxdepth 2 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo $HOME/Notes) && " +
            "mkdir -p $VAULT/QuickNotes && FP=$VAULT/QuickNotes/$(date +%Y-%m-%d_%H%M%S).md && touch $FP && echo $FP"];
        newNoteCreator.running = false; newNoteCreator.running = true;
    }
    Process {
        id: newNoteCreator; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector { onStreamFinished: {
            if (this.text.trim() === "idle") return;
            let fp = this.text.trim(); window.currentNoteFilepath = fp;
            window.selectedNoteTitle = fp.split("/").pop().replace(".md", "");
            noteArea.text = ""; window.notesSubMode = "edit"; noteArea.forceActiveFocus();
        }}
    }

    function fetchVaultNotes() {
        window.notesLoading = true;
        vaultNotesFetcher.command = ["bash", "-c",
            "VAULT=$(find ~/Documents ~/Notes ~/Obsidian -name .obsidian -maxdepth 2 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo $HOME/Notes) && " +
            "echo \"VAULT:::$VAULT\" && " +
            "find $VAULT -name '*.md' -type f -printf '%T@ %p\\n' 2>/dev/null | sort -rn | head -50 | while read ts path; do " +
            "name=$(basename \"$path\" .md); dir=$(dirname \"$path\" | sed \"s|$VAULT/||;s|$VAULT||\"); " +
            "preview=$(head -c 120 \"$path\" 2>/dev/null | tr '\\n' ' '); echo \"$name|||$dir|||$path|||$preview\"; done"];
        vaultNotesFetcher.running = false; vaultNotesFetcher.running = true;
    }
    Process {
        id: vaultNotesFetcher; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector { onStreamFinished: {
            window.notesLoading = false; if (this.text.trim() === "idle") return;
            vaultNotes.clear(); let lines = this.text.trim().split("\n");
            for (let i = 0; i < lines.length; i++) {
                let ln = lines[i];
                if (ln.indexOf("VAULT:::") === 0) {
                    window.obsidianVault = ln.substring(8).trim();
                    window.obsidianVaultName = window.obsidianVault.split("/").pop();
                    continue;
                }
                let parts = ln.split("|||");
                if (parts.length >= 4) vaultNotes.append({ name: parts[0].trim(), folder: parts[1].trim(), filepath: parts[2].trim(), preview: parts[3].trim() }); }
        }}
    }

    // ── Obsidian app integration (in-popup editing stays; these open the real
    // app via the obsidian:// URI scheme). Uses stock URIs plus Advanced URI
    // where it helps. xdg-open needs the URI percent-encoded.
    function obsidianOpenNote(filepath) {
        // Flush any unsaved edits first so Obsidian opens the latest content.
        window.flushNoteNow();
        let vault = window.obsidianVaultName;
        if (vault === "" || !filepath) { Quickshell.execDetached(["bash", "-c", "obsidian >/dev/null 2>&1 &"]); return; }
        // Compute the vault-relative path (Obsidian's `file` param).
        let rel = filepath;
        if (window.obsidianVault !== "" && filepath.indexOf(window.obsidianVault) === 0) {
            rel = filepath.substring(window.obsidianVault.length).replace(/^\//, "");
        }
        rel = rel.replace(/\.md$/, "");
        Quickshell.execDetached(["bash", "-c",
            "U=\"obsidian://open?vault=$(printf '%s' '" + vault.replace(/'/g, "'\\''") +
            "' | jq -sRr @uri)&file=$(printf '%s' '" + rel.replace(/'/g, "'\\''") + "' | jq -sRr @uri)\"; " +
            "xdg-open \"$U\" >/dev/null 2>&1 || obsidian \"$U\" >/dev/null 2>&1 &"
        ]);
    }
    // Open Obsidian's global search prefilled with a query.
    function obsidianSearch(query) {
        let vault = window.obsidianVaultName;
        if (vault === "") { Quickshell.execDetached(["bash", "-c", "obsidian >/dev/null 2>&1 &"]); return; }
        Quickshell.execDetached(["bash", "-c",
            "U=\"obsidian://search?vault=$(printf '%s' '" + vault.replace(/'/g, "'\\''") +
            "' | jq -sRr @uri)&query=$(printf '%s' '" + (query || "").replace(/'/g, "'\\''") + "' | jq -sRr @uri)\"; " +
            "xdg-open \"$U\" >/dev/null 2>&1 || obsidian \"$U\" >/dev/null 2>&1 &"
        ]);
    }
    // Open today's daily note in Obsidian.
    function obsidianDaily() {
        let vault = window.obsidianVaultName;
        Quickshell.execDetached(["bash", "-c",
            (vault === ""
              ? "obsidian >/dev/null 2>&1 &"
              : "U=\"obsidian://daily?vault=$(printf '%s' '" + vault.replace(/'/g, "'\\''") + "' | jq -sRr @uri)\"; xdg-open \"$U\" >/dev/null 2>&1 || obsidian \"$U\" >/dev/null 2>&1 &")
        ]);
    }

    function readNote(filepath, title) {
        window.selectedNoteTitle = title; window.currentNoteFilepath = filepath;
        noteReader.command = ["bash", "-c", "cat '" + filepath.replace(/'/g, "'\\''") + "' 2>/dev/null || echo ''"]; noteReader.running = false; noteReader.running = true;
    }
    Process {
        id: noteReader; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector { onStreamFinished: { if (this.text.trim() !== "idle") { noteArea.text = this.text; window.notesSubMode = "edit"; noteArea.forceActiveFocus(); } } }
    }

    // ── Chess: board helpers ──
    readonly property var chessPieceMap: ({ 'K': '\u2654', 'Q': '\u2655', 'R': '\u2656', 'B': '\u2657', 'N': '\u2658', 'P': '\u2659', 'k': '\u265a', 'q': '\u265b', 'r': '\u265c', 'b': '\u265d', 'n': '\u265e', 'p': '\u265f' })
    function chessPieceChar(p) { return chessPieceMap[p] || ""; }
    // Lichess CDN piece images (cburnett set). QML Image renders SVG fine. The
    // file name is colour+PieceLetter, e.g. white king = "wK", black queen = "bQ".
    // If the network/CDN is unavailable the Image fails silently and we fall back
    // to the unicode glyph beneath it.
    function chessPieceImg(p) {
        if (!p || p === "") return "";
        let isW = (p >= "A" && p <= "Z");
        let letter = p.toUpperCase();
        return "https://lichess1.org/assets/piece/cburnett/" + (isW ? "w" : "b") + letter + ".svg";
    }

    function chessInitBoard() {
        let b = []; let start = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR"; let ranks = start.split("/");
        for (let r = 0; r < 8; r++) { for (let c = 0; c < ranks[r].length; c++) { let ch = ranks[r][c]; if (ch >= '1' && ch <= '8') { for (let e = 0; e < parseInt(ch); e++) b.push(""); } else b.push(ch); } }
        window.chessBoard = b; window.chessBoardChanged();
    }

    // ── Pseudo-legal move targets for a piece (movement rules only) ──
    // Rays for sliders, offsets for knight/king, pushes+captures for pawns.
    // Does NOT filter moves that leave the king in check — that's done by
    // chessComputeTargets below, which wraps this. realIdx is 0=a8..63=h1.
    property var chessLegalTargets: []
    function chessPseudoTargets(realIdx) {
        let out = [];
        if (realIdx < 0) return out;
        let board = window.chessBoard;
        let piece = board[realIdx] || "";
        if (piece === "") return out;
        let white = (piece >= "A" && piece <= "Z");
        let type = piece.toUpperCase();
        let r = Math.floor(realIdx / 8);   // 0=rank8 .. 7=rank1
        let c = realIdx % 8;               // 0=a .. 7=h
        let isEnemy = function(idx){ let p = board[idx]; if (!p) return false; let w = (p >= "A" && p <= "Z"); return w !== white; };
        let isEmpty = function(idx){ return (board[idx] || "") === ""; };
        let inBounds = function(rr, cc){ return rr >= 0 && rr < 8 && cc >= 0 && cc < 8; };
        let pushIf = function(rr, cc, captureOnly, pushOnly){
            if (!inBounds(rr, cc)) return false;
            let idx = rr * 8 + cc;
            if (isEmpty(idx)) { if (!captureOnly) out.push(idx); return true; }  // empty: can continue ray
            if (isEnemy(idx) && !pushOnly) out.push(idx);                        // enemy: capture, stop ray
            return false;                                                       // blocked
        };
        let ray = function(dr, dc){
            let rr = r + dr, cc = c + dc;
            while (inBounds(rr, cc)) {
                let idx = rr * 8 + cc;
                if (isEmpty(idx)) { out.push(idx); }
                else { if (isEnemy(idx)) out.push(idx); break; }
                rr += dr; cc += dc;
            }
        };
        if (type === "P") {
            let dir = white ? -1 : 1;            // white pawns move toward rank8 (decreasing r)
            let startRank = white ? 6 : 1;
            // forward push
            if (inBounds(r + dir, c) && isEmpty((r + dir) * 8 + c)) {
                out.push((r + dir) * 8 + c);
                // double push from start
                if (r === startRank && isEmpty((r + 2 * dir) * 8 + c)) out.push((r + 2 * dir) * 8 + c);
            }
            // captures
            for (let dc2 of [-1, 1]) {
                let rr = r + dir, cc = c + dc2;
                if (inBounds(rr, cc) && isEnemy(rr * 8 + cc)) out.push(rr * 8 + cc);
            }
        } else if (type === "N") {
            let offs = [[-2,-1],[-2,1],[-1,-2],[-1,2],[1,-2],[1,2],[2,-1],[2,1]];
            for (let o of offs) { let rr = r + o[0], cc = c + o[1]; if (inBounds(rr, cc)) { let idx = rr * 8 + cc; if (isEmpty(idx) || isEnemy(idx)) out.push(idx); } }
        } else if (type === "B") {
            ray(-1,-1); ray(-1,1); ray(1,-1); ray(1,1);
        } else if (type === "R") {
            ray(-1,0); ray(1,0); ray(0,-1); ray(0,1);
        } else if (type === "Q") {
            ray(-1,-1); ray(-1,1); ray(1,-1); ray(1,1); ray(-1,0); ray(1,0); ray(0,-1); ray(0,1);
        } else if (type === "K") {
            for (let dr = -1; dr <= 1; dr++) for (let dc3 = -1; dc3 <= 1; dc3++) {
                if (dr === 0 && dc3 === 0) continue;
                let rr = r + dr, cc = c + dc3;
                if (!inBounds(rr, cc)) continue;
                let idx = rr * 8 + cc;
                if (!(isEmpty(idx) || isEnemy(idx))) continue;
                // King may not move into check: simulate the move (king leaves
                // its square, lands on idx) and reject if the destination is
                // attacked by any enemy piece. This also stops the king from
                // "capturing" a defended piece, since the defender attacks idx.
                let sim = board.slice();
                sim[realIdx] = "";
                sim[idx] = piece;
                if (!window.chessSquareAttacked(sim, idx, !white)) out.push(idx);
            }
            // Castling. We don't track explicit rights from move history, so we
            // use the standard preconditions: king on its home square, the rook
            // on its home corner, the squares between empty, the king not
            // currently in check, and the two squares it crosses not attacked.
            // Lichess validates the real move regardless, so this is safe.
            let homeRow = white ? 7 : 0;
            if (r === homeRow && c === 4 && !window.chessSquareAttacked(board, realIdx, !white)) {
                let rookK = white ? "R" : "r";
                // King-side: rook on h-file, f & g empty, e/f/g not attacked.
                if (board[homeRow*8 + 7] === rookK
                        && board[homeRow*8 + 5] === "" && board[homeRow*8 + 6] === ""
                        && !window.chessSquareAttacked(board, homeRow*8 + 5, !white)
                        && !window.chessSquareAttacked(board, homeRow*8 + 6, !white)) {
                    out.push(homeRow*8 + 6);   // king to g-file
                }
                // Queen-side: rook on a-file, b/c/d empty, e/d/c not attacked.
                if (board[homeRow*8 + 0] === rookK
                        && board[homeRow*8 + 1] === "" && board[homeRow*8 + 2] === "" && board[homeRow*8 + 3] === ""
                        && !window.chessSquareAttacked(board, homeRow*8 + 3, !white)
                        && !window.chessSquareAttacked(board, homeRow*8 + 2, !white)) {
                    out.push(homeRow*8 + 2);   // king to c-file
                }
            }
        }
        return out;
    }
    // Fully-legal targets for the piece on realIdx: pseudo-legal moves, minus
    // any that would leave our own king in check (this enforces pins, and the
    // requirement to address an existing check). The king's own moves are
    // already check-filtered in chessPseudoTargets, but we re-validate here too
    // for consistency (cheap, and covers discovered checks on the king move).
    function chessComputeTargets(realIdx) {
        let pseudo = window.chessPseudoTargets(realIdx);
        if (realIdx < 0 || pseudo.length === 0) return pseudo;
        let board = window.chessBoard;
        let piece = board[realIdx] || "";
        if (piece === "") return pseudo;
        let white = (piece >= "A" && piece <= "Z");
        let kingChar = white ? "K" : "k";
        let legal = [];
        for (let i = 0; i < pseudo.length; i++) {
            let to = pseudo[i];
            // Simulate the move on a copy (handles normal moves + captures; en
            // passant/castling are rare enough that pin-accuracy there is not
            // required, and Lichess validates the real move anyway).
            let sim = board.slice();
            sim[to] = piece;
            sim[realIdx] = "";
            // Find our king on the simulated board.
            let kingIdx = -1;
            for (let k = 0; k < 64; k++) { if (sim[k] === kingChar) { kingIdx = k; break; } }
            // If the king isn't found (shouldn't happen), don't filter.
            if (kingIdx < 0) { legal.push(to); continue; }
            // Keep the move only if our king is NOT attacked afterward.
            if (!window.chessSquareAttacked(sim, kingIdx, !white)) legal.push(to);
        }
        return legal;
    }
    // Board-explicit pseudo-legal targets — same movement rules as
    // chessPseudoTargets but operating on a supplied board array (used by the
    // interactive start-page correspondence board, which has its own state).
    function chessPseudoTargetsOn(board, realIdx) {
        let out = [];
        if (realIdx < 0) return out;
        let piece = board[realIdx] || "";
        if (piece === "") return out;
        let white = (piece >= "A" && piece <= "Z");
        let type = piece.toUpperCase();
        let r = Math.floor(realIdx / 8), c = realIdx % 8;
        let isEnemy = function(idx){ let p = board[idx]; if (!p) return false; let w = (p >= "A" && p <= "Z"); return w !== white; };
        let isEmpty = function(idx){ return (board[idx] || "") === ""; };
        let inB = function(rr, cc){ return rr >= 0 && rr < 8 && cc >= 0 && cc < 8; };
        let ray = function(dr, dc){ let rr = r + dr, cc = c + dc;
            while (inB(rr, cc)) { let idx = rr*8+cc; if (isEmpty(idx)) out.push(idx); else { if (isEnemy(idx)) out.push(idx); break; } rr += dr; cc += dc; } };
        if (type === "P") {
            let dir = white ? -1 : 1; let startRank = white ? 6 : 1;
            if (inB(r+dir, c) && isEmpty((r+dir)*8+c)) { out.push((r+dir)*8+c); if (r === startRank && isEmpty((r+2*dir)*8+c)) out.push((r+2*dir)*8+c); }
            for (let dc2 of [-1,1]) { let rr = r+dir, cc = c+dc2; if (inB(rr,cc) && isEnemy(rr*8+cc)) out.push(rr*8+cc); }
        } else if (type === "N") {
            let offs = [[-2,-1],[-2,1],[-1,-2],[-1,2],[1,-2],[1,2],[2,-1],[2,1]];
            for (let o of offs) { let rr = r+o[0], cc = c+o[1]; if (inB(rr,cc)) { let idx = rr*8+cc; if (isEmpty(idx) || isEnemy(idx)) out.push(idx); } }
        } else if (type === "B") { ray(-1,-1); ray(-1,1); ray(1,-1); ray(1,1);
        } else if (type === "R") { ray(-1,0); ray(1,0); ray(0,-1); ray(0,1);
        } else if (type === "Q") { ray(-1,-1); ray(-1,1); ray(1,-1); ray(1,1); ray(-1,0); ray(1,0); ray(0,-1); ray(0,1);
        } else if (type === "K") {
            for (let dr = -1; dr <= 1; dr++) for (let dc3 = -1; dc3 <= 1; dc3++) {
                if (dr === 0 && dc3 === 0) continue;
                let rr = r+dr, cc = c+dc3; if (!inB(rr,cc)) continue;
                let idx = rr*8+cc; if (!(isEmpty(idx) || isEnemy(idx))) continue;
                let sim = board.slice(); sim[realIdx] = ""; sim[idx] = piece;
                if (!window.chessSquareAttacked(sim, idx, !white)) out.push(idx);
            }
            let homeRow = white ? 7 : 0;
            if (r === homeRow && c === 4 && !window.chessSquareAttacked(board, realIdx, !white)) {
                let rookK = white ? "R" : "r";
                if (board[homeRow*8+7] === rookK && board[homeRow*8+5] === "" && board[homeRow*8+6] === ""
                    && !window.chessSquareAttacked(board, homeRow*8+5, !white) && !window.chessSquareAttacked(board, homeRow*8+6, !white)) out.push(homeRow*8+6);
                if (board[homeRow*8+0] === rookK && board[homeRow*8+1] === "" && board[homeRow*8+2] === "" && board[homeRow*8+3] === ""
                    && !window.chessSquareAttacked(board, homeRow*8+3, !white) && !window.chessSquareAttacked(board, homeRow*8+2, !white)) out.push(homeRow*8+2);
            }
        }
        return out;
    }
    // Board-explicit fully-legal targets (filters moves that leave own king in
    // check). `white` is the moving side (used to locate the king).
    function chessComputeTargetsOn(board, realIdx, white) {
        let pseudo = window.chessPseudoTargetsOn(board, realIdx);
        if (realIdx < 0 || pseudo.length === 0) return pseudo;
        let piece = board[realIdx] || "";
        if (piece === "") return pseudo;
        let kingChar = white ? "K" : "k";
        let legal = [];
        for (let i = 0; i < pseudo.length; i++) {
            let to = pseudo[i];
            let sim = board.slice(); sim[to] = piece; sim[realIdx] = "";
            let kingIdx = -1;
            for (let k = 0; k < 64; k++) if (sim[k] === kingChar) { kingIdx = k; break; }
            if (kingIdx < 0) { legal.push(to); continue; }
            if (!window.chessSquareAttacked(sim, kingIdx, !white)) legal.push(to);
        }
        return legal;
    }
    // True if square `idx` is attacked by a piece of color `byWhite` on `board`.
    // Used to keep the king out of check. Considers pawn diagonals, knight
    // jumps, sliding rays (bishop/rook/queen), and adjacent enemy king.
    function chessSquareAttacked(board, idx, byWhite) {
        let r = Math.floor(idx / 8), c = idx % 8;
        let inB = function(rr, cc){ return rr >= 0 && rr < 8 && cc >= 0 && cc < 8; };
        let at = function(rr, cc){ return board[rr * 8 + cc] || ""; };
        let isColor = function(p){ if (!p) return false; let w = (p >= "A" && p <= "Z"); return w === byWhite; };
        // Pawns: a white pawn attacks the two squares diagonally "up" toward
        // rank 8 (decreasing row), a black pawn diagonally "down".
        let pdir = byWhite ? 1 : -1;   // row offset FROM target back TO the attacking pawn
        for (let dc of [-1, 1]) {
            let rr = r + pdir, cc = c + dc;
            if (inB(rr, cc)) { let p = at(rr, cc); if (isColor(p) && p.toUpperCase() === "P") return true; }
        }
        // Knights
        let kn = [[-2,-1],[-2,1],[-1,-2],[-1,2],[1,-2],[1,2],[2,-1],[2,1]];
        for (let o of kn) { let rr = r + o[0], cc = c + o[1]; if (inB(rr, cc)) { let p = at(rr, cc); if (isColor(p) && p.toUpperCase() === "N") return true; } }
        // Diagonal rays (bishop/queen)
        let diag = [[-1,-1],[-1,1],[1,-1],[1,1]];
        for (let d of diag) {
            let rr = r + d[0], cc = c + d[1];
            while (inB(rr, cc)) {
                let p = at(rr, cc);
                if (p) { if (isColor(p) && (p.toUpperCase() === "B" || p.toUpperCase() === "Q")) return true; break; }
                rr += d[0]; cc += d[1];
            }
        }
        // Orthogonal rays (rook/queen)
        let orth = [[-1,0],[1,0],[0,-1],[0,1]];
        for (let d of orth) {
            let rr = r + d[0], cc = c + d[1];
            while (inB(rr, cc)) {
                let p = at(rr, cc);
                if (p) { if (isColor(p) && (p.toUpperCase() === "R" || p.toUpperCase() === "Q")) return true; break; }
                rr += d[0]; cc += d[1];
            }
        }
        // Enemy king adjacency
        for (let dr = -1; dr <= 1; dr++) for (let dc2 = -1; dc2 <= 1; dc2++) {
            if (dr === 0 && dc2 === 0) continue;
            let rr = r + dr, cc = c + dc2;
            if (inB(rr, cc)) { let p = at(rr, cc); if (isColor(p) && p.toUpperCase() === "K") return true; }
        }
        return false;
    }
    // Recompute targets whenever the selection changes.
    onChessSelectedChanged: window.chessLegalTargets = window.chessComputeTargets(window.chessSelected);
    function chessParseFen(fen) {
        let b = []; let ranks = fen.split(" ")[0].split("/");
        for (let r = 0; r < 8; r++) { for (let c = 0; c < ranks[r].length; c++) { let ch = ranks[r][c]; if (ch >= '1' && ch <= '8') { for (let e = 0; e < parseInt(ch); e++) b.push(""); } else b.push(ch); } }
        return b;
    }

    // Inverse of chessParseFen: 64-cell board → FEN placement field (rank 8 first).
    function chessBoardToPlacement(board) {
        if (!board || board.length < 64) return "";
        let out = "";
        for (let r = 0; r < 8; r++) {
            let empty = 0;
            for (let c = 0; c < 8; c++) {
                let p = board[r*8 + c] || "";
                if (p === "" || p === " ") { empty++; }
                else { if (empty > 0) { out += empty; empty = 0; } out += p; }
            }
            if (empty > 0) out += empty;
            if (r < 7) out += "/";
        }
        return out;
    }
    // Apply one UCI move to a board array (returns a new array). Handles en passant,
    // castling (king moves 2 files), and promotion (5th char). Pure: caller owns state.
    function chessApplyOneMove(board, uci) {
        let b = board.slice();
        let ff = uci.charCodeAt(0) - 97; let fr = 8 - parseInt(uci[1]);
        let tf = uci.charCodeAt(2) - 97; let tr = 8 - parseInt(uci[3]);
        let fi = fr * 8 + ff; let ti = tr * 8 + tf;
        let piece = b[fi]; let promo = uci.length > 4 ? uci[4] : "";
        if ((piece === "P" || piece === "p") && ff !== tf && b[ti] === "") b[fr * 8 + tf] = "";
        if (piece === "K" || piece === "k") {
            if (tf - ff === 2) { b[fr * 8 + 5] = b[fr * 8 + 7]; b[fr * 8 + 7] = ""; }
            if (ff - tf === 2) { b[fr * 8 + 3] = b[fr * 8 + 0]; b[fr * 8 + 0] = ""; }
        }
        b[fi] = "";
        if (promo) { let isW = piece === "P"; let pm = {"q": isW?"Q":"q", "r": isW?"R":"r", "b": isW?"B":"b", "n": isW?"N":"n"}; b[ti] = pm[promo] || piece; }
        else { b[ti] = piece; }
        return b;
    }
    function chessApplyMoves(movesStr) {
        let b = chessParseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR");
        if (movesStr.trim() === "") { window.chessBoard = b; window.chessBoardChanged(); return; }
        let moves = movesStr.trim().split(" ");
        for (let m = 0; m < moves.length; m++) b = chessApplyOneMove(b, moves[m]);
        window.chessBoard = b; window.chessBoardChanged();
        window.chessHalfmoveCount = moves.length;
        window.chessMyTurn = (moves.length % 2 === 0) === window.chessIsWhite;
        let last = moves[moves.length - 1];
        window.chessFromIdx = (8 - parseInt(last[1])) * 8 + (last.charCodeAt(0) - 97);
        window.chessToIdx = (8 - parseInt(last[3])) * 8 + (last.charCodeAt(2) - 97);
        // If the opponent has just moved and it's now our turn, fire the next
        // queued premove (validated against the new position).
        if (window.chessStatus === "playing" && window.chessMyTurn && window.chessPremoves.length > 0) {
            Qt.callLater(window.chessTryPlayPremove);
        }
    }
    function chessIdxToUci(idx) { let f = idx % 8; let r = Math.floor(idx / 8); return String.fromCharCode(97 + f) + (8 - r).toString(); }

    // ── Drag-to-move support ──
    // Whether the piece on realIdx belongs to the side the user controls and
    // it's their turn / their move to make (works for both play and puzzle).
    function chessCanPickUp(realIdx) {
        let piece = window.chessBoard[realIdx] || "";
        if (piece === "") return false;
        let isMyPiece = window.chessIsWhite ? (piece >= "A" && piece <= "Z") : (piece >= "a" && piece <= "z");
        if (!isMyPiece) return false;
        // During a live game you can pick up your own piece whether or not it's
        // your turn: on your turn it's a real move, otherwise it queues a premove.
        if (window.chessStatus === "playing") return true;
        if (window.chessStatus === "puzzle") return (window.chessPuzzleStep % 2 === 1) && !window.chessPuzzleSolved;
        return false;
    }
    // Queue a premove (entered while it's the opponent's turn). We don't validate
    // against the *current* position (the opponent hasn't moved yet); validation
    // happens when we try to play it. Premoves chain — you can queue several.
    function chessQueuePremove(fromRealIdx, toRealIdx) {
        if (fromRealIdx < 0 || toRealIdx < 0 || fromRealIdx === toRealIdx) return;
        let fromUci = chessIdxToUci(fromRealIdx);
        let toUci = chessIdxToUci(toRealIdx);
        let move = fromUci + toUci;
        let movingPiece = window.chessBoard[fromRealIdx];
        let toRank = Math.floor(toRealIdx / 8);
        if ((movingPiece === "P" && toRank === 0) || (movingPiece === "p" && toRank === 7)) move += "q";
        let pm = window.chessPremoves.slice();
        pm.push({ from: fromRealIdx, to: toRealIdx, uci: move });
        window.chessPremoves = pm;
        window.chessSelected = -1;
        window.chessBoardChanged();
    }
    function chessClearPremoves() {
        if (window.chessPremoves.length > 0) { window.chessPremoves = []; window.chessBoardChanged(); }
    }
    // When it becomes our turn, try to play the first queued premove. If it's
    // illegal in the actual position (opponent did something unexpected), the
    // whole queue is discarded — standard premove behaviour.
    function chessTryPlayPremove() {
        if (window.chessStatus !== "playing" || !window.chessMyTurn) return;
        if (window.chessPremoves.length === 0) return;
        let pm = window.chessPremoves[0];
        let rest = window.chessPremoves.slice(1);
        // Validate the from-square still holds one of our pieces and to is legal.
        let targets = window.chessComputeTargets(pm.from);
        let ok = false;
        for (let i = 0; i < targets.length; i++) if (targets[i] === pm.to) { ok = true; break; }
        if (!ok) { window.chessPremoves = []; window.chessBoardChanged(); return; }
        window.chessPremoves = rest;   // consume this one; the rest stay queued
        // Play it through the normal optimistic path.
        window.chessBoard = window.chessApplyOneMove(window.chessBoard, pm.uci);
        window.chessHalfmoveCount += 1;
        window.chessFromIdx = pm.from;
        window.chessToIdx = pm.to;
        window.chessSelected = -1;
        window.chessMyTurn = false;
        window.chessBoardChanged();
        chessMakeMove(pm.uci);
    }
    // Commit a drag from one realIdx to another (mirrors click-to-move logic).
    function chessDropMove(fromRealIdx, toRealIdx) {
        if (fromRealIdx < 0 || toRealIdx < 0 || fromRealIdx === toRealIdx) return;
        if (window.chessStatus === "playing") {
            // Not our turn → queue as a premove (chained; multiple allowed).
            if (!window.chessMyTurn) { window.chessQueuePremove(fromRealIdx, toRealIdx); return; }
            // Only allow legal destinations (the dots we showed).
            let targets = window.chessComputeTargets(fromRealIdx);
            let ok = false;
            for (let i = 0; i < targets.length; i++) if (targets[i] === toRealIdx) { ok = true; break; }
            if (!ok) { window.chessSelected = -1; window.chessBoardChanged(); return; }

            let fromUci = chessIdxToUci(fromRealIdx);
            let toUci = chessIdxToUci(toRealIdx);
            let move = fromUci + toUci;
            let movingPiece = window.chessBoard[fromRealIdx];
            let toRank = Math.floor(toRealIdx / 8);
            if ((movingPiece === "P" && toRank === 0) || (movingPiece === "p" && toRank === 7)) move += "q";
            // Optimistically apply the move to the local board so the piece
            // visibly lands immediately, instead of waiting for the game stream
            // to echo it back (which may lag or, if the stream is down, never
            // arrive). The stream's gameState will re-sync the authoritative
            // position when it comes in.
            window.chessBoard = window.chessApplyOneMove(window.chessBoard, move);
            window.chessHalfmoveCount += 1;   // our move is now reflected locally
            window.chessFromIdx = fromRealIdx;
            window.chessToIdx = toRealIdx;
            window.chessSelected = -1;
            window.chessMyTurn = false;     // it's the opponent's move now
            window.chessBoardChanged();
            chessMakeMove(move);            // submit to Lichess
        } else if (window.chessStatus === "puzzle") {
            // Reuse the puzzle click path: select source, then "click" target.
            window.chessSelected = fromRealIdx;
            // Convert realIdx back to display index for the puzzle handler.
            let dispTo = window.chessIsWhite ? toRealIdx : (63 - toRealIdx);
            window.chessPuzzleSquareClicked(dispTo);
        }
    }
    // ── Planning arrows ──
    function chessToggleArrow(fromRealIdx, toRealIdx) {
        if (fromRealIdx < 0 || toRealIdx < 0 || fromRealIdx === toRealIdx) return;
        // The arrow must reflect a legal move of the piece sitting on the
        // from-square — and only for a piece you control on your turn. Each
        // arrow is validated independently against its own from-square, so a
        // previously drawn arrow's piece never interferes with a new one.
        let piece = window.chessBoard[fromRealIdx] || "";
        if (piece === "") return;                       // no piece → no arrow
        let pieceIsWhite = (piece >= "A" && piece <= "Z");
        let isMine = window.chessIsWhite ? pieceIsWhite : !pieceIsWhite;
        // Arrows are a planning aid — allowed for BOTH your pieces and the
        // opponent's (so you can map out their threats too). We validate the
        // destination against the piece's own legal targets regardless of side.
        let targets = window.chessComputeTargets(fromRealIdx);
        let ok = false;
        for (let t = 0; t < targets.length; t++) if (targets[t] === toRealIdx) { ok = true; break; }
        if (!ok) return;

        let arr = window.chessArrows.slice();
        // Toggle: if the same arrow exists, remove it; else add. Tag with `mine`
        // so the canvas can color your arrows vs the opponent's differently.
        let foundAt = -1;
        for (let i = 0; i < arr.length; i++) {
            if (arr[i].from === fromRealIdx && arr[i].to === toRealIdx) { foundAt = i; break; }
        }
        if (foundAt >= 0) arr.splice(foundAt, 1);
        else arr.push({ from: fromRealIdx, to: toRealIdx, mine: isMine });
        window.chessArrows = arr;
    }
    function chessClearArrows() { window.chessArrows = []; }
    // Map a realIdx to the center point (in board-local px) given board pixel size.
    function chessSquareCenter(realIdx, boardPx) {
        // Convert realIdx → display index (respects board flip), then to row/col.
        let disp = window.chessIsWhite ? realIdx : (63 - realIdx);
        let row = Math.floor(disp / 8);
        let col = disp % 8;
        let cell = boardPx / 8;
        return Qt.point(col * cell + cell / 2, row * cell + cell / 2);
    }

    function chessSquareClicked(idx) {
        let realIdx = window.chessIsWhite ? idx : (63 - idx); let piece = window.chessBoard[realIdx];
        let isMine = window.chessIsWhite ? (piece >= "A" && piece <= "Z") : (piece >= "a" && piece <= "z");
        // Premove path: while it's NOT our turn in a live game, a select-then-
        // click on your own piece queues a premove instead of moving.
        if (window.chessStatus === "playing" && !window.chessMyTurn) {
            if (window.chessSelected >= 0) {
                // Second click: queue from selected → target (any non-self square).
                if (realIdx !== window.chessSelected) { window.chessQueuePremove(window.chessSelected, realIdx); return; }
                window.chessSelected = -1; window.chessBoardChanged(); return;
            } else if (isMine) {
                window.chessSelected = realIdx; window.chessBoardChanged(); return;
            }
            return;
        }
        if (window.chessSelected >= 0) {
            // Validate against legal targets of the selected piece.
            let targets = window.chessComputeTargets(window.chessSelected);
            let ok = false;
            for (let i = 0; i < targets.length; i++) if (targets[i] === realIdx) { ok = true; break; }
            if (!ok) {
                // Clicking another own piece reselects; otherwise deselect.
                let isMine = window.chessIsWhite ? (piece >= "A" && piece <= "Z") : (piece >= "a" && piece <= "z");
                window.chessSelected = (isMine && window.chessMyTurn) ? realIdx : -1;
                window.chessBoardChanged();
                return;
            }
            let fromUci = chessIdxToUci(window.chessSelected); let toUci = chessIdxToUci(realIdx); let move = fromUci + toUci;
            let movingPiece = window.chessBoard[window.chessSelected]; let toRank = Math.floor(realIdx / 8);
            if ((movingPiece === "P" && toRank === 0) || (movingPiece === "p" && toRank === 7)) move += "q";
            // Optimistic local apply (same as drag path).
            window.chessBoard = window.chessApplyOneMove(window.chessBoard, move);
            window.chessHalfmoveCount += 1;
            window.chessFromIdx = window.chessSelected;
            window.chessToIdx = realIdx;
            window.chessSelected = -1;
            window.chessMyTurn = false;
            window.chessBoardChanged();
            chessMakeMove(move);
        } else {
            let isMyPiece = window.chessIsWhite ? (piece >= "A" && piece <= "Z") : (piece >= "a" && piece <= "z");
            if (isMyPiece && window.chessMyTurn) { window.chessSelected = realIdx; window.chessBoardChanged(); }
        }
    }
    // ── Chess: puzzle interactivity ──
    // Convention from Lichess: FEN is BEFORE the opponent's setup move.
    // solution[0] is the opponent's auto-played move; solution[1] is the user's first answer.
    // User plays the side OPPOSITE the FEN's "side to move".
    function chessPuzzleSolution() {
        return window.chessPuzzleMoves.split(" ").filter(function(m) { return m.length >= 4; });
    }
    function chessPuzzleSquareClicked(idx) {
        if (window.chessPuzzleSolved) return;
        if (window.chessPuzzleStep % 2 !== 1) return;   // only on user's turn

        let realIdx = window.chessIsWhite ? idx : (63 - idx);
        let piece = window.chessBoard[realIdx];
        let isMyPiece = window.chessIsWhite ? (piece >= "A" && piece <= "Z") : (piece >= "a" && piece <= "z");

        // No selection yet → select own piece, ignore everything else
        if (window.chessSelected < 0) {
            if (isMyPiece) { window.chessSelected = realIdx; window.chessPuzzleFeedback = ""; window.chessBoardChanged(); }
            return;
        }
        // Re-click selected square → deselect
        if (window.chessSelected === realIdx) {
            window.chessSelected = -1; window.chessBoardChanged(); return;
        }
        // Click another own piece → switch selection
        if (isMyPiece) {
            window.chessSelected = realIdx; window.chessPuzzleFeedback = ""; window.chessBoardChanged(); return;
        }

        // Attempt the move
        let fromUci = chessIdxToUci(window.chessSelected);
        let toUci = chessIdxToUci(realIdx);
        let move = fromUci + toUci;
        let movingPiece = window.chessBoard[window.chessSelected];
        let toRank = Math.floor(realIdx / 8);
        if ((movingPiece === "P" && toRank === 0) || (movingPiece === "p" && toRank === 7)) move += "q";

        let solution = chessPuzzleSolution();
        let expected = solution[window.chessPuzzleStep] || "";
        // Match on from+to squares; if expected specifies a different promotion piece, still accept
        // (the user can only pick queen from the click UI; under-promotions are rare in puzzles).
        let attemptBase = move.substring(0, 4);
        let expectedBase = expected.substring(0, 4);
        window.chessSelected = -1;

        if (attemptBase === expectedBase && expected.length >= 4) {
            // Apply the expected move (preserves correct promotion piece if any)
            let nb = chessApplyOneMove(window.chessBoard, expected);
            window.chessBoard = nb;
            window.chessFromIdx = (8 - parseInt(expected[1])) * 8 + (expected.charCodeAt(0) - 97);
            window.chessToIdx = (8 - parseInt(expected[3])) * 8 + (expected.charCodeAt(2) - 97);
            window.chessPuzzleStep += 1;
            window.chessMyTurn = false;
            window.chessBoardChanged();
            if (window.chessPuzzleStep >= solution.length) {
                window.chessPuzzleSolved = true;
                window.chessPuzzleFeedback = "solved";
            } else {
                window.chessPuzzleFeedback = "correct";
                chessPuzzleOpponentTimer.restart();
            }
        } else {
            window.chessPuzzleFeedback = "wrong";
            window.chessBoardChanged();
        }
    }
    function chessResetPuzzle() {
        if (!window.chessPuzzleStartFen) return;
        window.chessBoard = chessParseFen(window.chessPuzzleStartFen);
        let parts = window.chessPuzzleStartFen.split(" ");
        // User plays opposite of FEN's side-to-move
        window.chessIsWhite = parts.length > 1 ? parts[1] !== "w" : false;
        window.chessSelected = -1;
        window.chessFromIdx = -1; window.chessToIdx = -1;
        window.chessPuzzleStep = 0;
        window.chessPuzzleSolved = false;
        window.chessPuzzleFeedback = "";
        window.chessMyTurn = false;
        window.chessBoardChanged();
        chessPuzzleOpponentTimer.restart();
    }
    // Plays the opponent's next move from the solution after a short delay.
    // Used for both the initial setup move (solution[0]) and replies after the user's correct moves.
    Timer {
        id: chessPuzzleOpponentTimer
        interval: 550; repeat: false
        onTriggered: {
            let solution = window.chessPuzzleSolution();
            if (window.chessPuzzleStep >= solution.length) return;
            let mv = solution[window.chessPuzzleStep];
            if (!mv || mv.length < 4) return;
            window.chessBoard = window.chessApplyOneMove(window.chessBoard, mv);
            window.chessFromIdx = (8 - parseInt(mv[1])) * 8 + (mv.charCodeAt(0) - 97);
            window.chessToIdx = (8 - parseInt(mv[3])) * 8 + (mv.charCodeAt(2) - 97);
            window.chessPuzzleStep += 1;
            window.chessBoardChanged();
            if (window.chessPuzzleStep >= solution.length) {
                window.chessPuzzleSolved = true;
                window.chessPuzzleFeedback = "solved";
                window.chessMyTurn = false;
            } else {
                window.chessMyTurn = true;
                window.chessPuzzleFeedback = "";
            }
        }
    }

    property bool chessAiCreating: false   // true while the challenge/ai request is in flight
    function chessStartAi(level, minutes) {
        // Stay on the setup page and show a loading state; we only move to the
        // board once Lichess confirms the game (handled in chessCreateProc).
        window.chessAiCreating = true;
        window.chessCreateError = "";
        window.chessInitBoard(); window.chessSelected = -1; window.chessResult = "";
        let tok = chessSanitizeToken(window.lichessToken);
        // /api/challenge/ai params (mirrors the known-working request):
        //   level         1–8
        //   clock.limit   initial seconds (0–10800); must be a valid clock value
        //   clock.increment  0–60
        //   color, variant  required for a clean request
        let lvl = Math.max(1, Math.min(8, parseInt(level) || 1));
        let lim = Math.max(0, Math.min(10800, Math.round((minutes || 10) * 60)));
        chessCreateProc.command = ["bash", "-c", chessLoggedCmd(
            "POST /api/challenge/ai level=" + lvl + " limit=" + lim,
            "curl -s -X POST 'https://lichess.org/api/challenge/ai' " +
            "-H \"Authorization: Bearer " + tok + "\" " +
            "-H 'Content-Type: application/x-www-form-urlencoded' " +
            "--data-urlencode 'level=" + lvl + "' " +
            "--data-urlencode 'clock.limit=" + lim + "' " +
            "--data-urlencode 'clock.increment=0' " +
            "--data-urlencode 'color=random' " +
            "--data-urlencode 'variant=standard'"
        )];
        chessCreateProc.running = false; chessCreateProc.running = true;
    }
    // Correspondence seek: uses `days` (per-move) instead of a clock. 14 is the
    // Lichess maximum. Same event-stream flow as a normal seek for the game id.
    // ── Start-page correspondence board ──
    // The mini-board on the menu is interactable. If an ongoing correspondence
    // game exists it mirrors that game (and you move in it directly). If not,
    // making a move auto-seeks a 14-day correspondence game and submits that move
    // as move 1. We never start a new seek while a game is active.
    property bool chessHasCorrGame: false       // an ongoing correspondence game exists
    property string chessCorrGameId: ""         // its id (also drives the live mini-board)
    property var chessMenuBoard: chessParseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR")
    property int chessMenuSelected: -1
    property bool chessMenuIsWhite: true
    property bool chessMenuMyTurn: true
    property int chessMenuHalfmoves: 0
    property string chessPendingFirstMove: ""   // move queued while a seek is in flight

    // Check for an ongoing correspondence game when the menu shows. Lichess
    // /api/account/playing lists ongoing games; we pick a correspondence one
    // (speed == "correspondence") and mirror it onto the start-page board.
    function chessCheckCorrGame() {
        if (window.lichessToken === "") return;
        let tok = chessSanitizeToken(window.lichessToken);
        chessCorrCheckProc.command = ["bash", "-c",
            "curl -s 'https://lichess.org/api/account/playing' -H \"Authorization: Bearer " + tok + "\" 2>/dev/null | " +
            "jq -r '([.nowPlaying[]? | select(.speed==\"correspondence\")] | first) as $g | " +
            "if $g then ($g.gameId + \"|\" + ($g.color) + \"|\" + (($g.isMyTurn)|tostring) + \"|\" + ($g.fen)) else \"\" end' 2>/dev/null"
        ];
        chessCorrCheckProc.running = false; chessCorrCheckProc.running = true;
    }
    Process {
        id: chessCorrCheckProc; command: ["bash", "-c", "echo ''"]
        stdout: StdioCollector { onStreamFinished: {
            let raw = (this.text || "").trim();
            if (raw === "") { window.chessHasCorrGame = false; window.chessCorrGameId = ""; if (Config.corrChessGameId !== "") Config.clearCorrChess(); return; }
            let parts = raw.split("|");
            window.chessCorrGameId = parts[0] || "";
            window.chessHasCorrGame = window.chessCorrGameId !== "";
            window.chessMenuIsWhite = (parts[1] === "white");
            window.chessMenuMyTurn = (parts[2] === "true");
            // Render the current FEN onto the mini-board.
            if (parts[3]) {
                window.chessMenuBoard = window.chessParseFen(parts[3].split(" ")[0]);
                window.chessMenuRepaint();
            }
            // Persist the authoritative snapshot so it survives restarts.
            Config.saveCorrChess(window.chessCorrGameId, window.chessMenuIsWhite,
                                 window.chessMenuMyTurn, parts[3] || "");
        }}
    }
    signal chessMenuRepaint()
    // While viewing the menu with a live correspondence game, refresh it
    // periodically so the mini-board reflects the opponent's latest move.
    Timer {
        id: chessCorrMenuPoll
        interval: Config.corrChessRefreshMs > 0 ? Config.corrChessRefreshMs : 8000; repeat: true
        running: window.activeMode === "chess" && window.chessStatus === "menu" && window.lichessToken !== ""
        onTriggered: window.chessCheckCorrGame()
    }

    // A tap-move on the start-page mini board: from→to (real indices in the
    // menu board's own orientation). Branch on whether a corr game is live.
    function chessMenuMove(fromIdx, toIdx) {
        if (fromIdx < 0 || toIdx < 0 || fromIdx === toIdx) return;
        // Build UCI from the menu board orientation.
        let fromUci = chessIdxToUci(fromIdx);
        let toUci = chessIdxToUci(toIdx);
        let mv = fromUci + toUci;
        let mp = window.chessMenuBoard[fromIdx];
        let toRank = Math.floor(toIdx / 8);
        if ((mp === "P" && toRank === 0) || (mp === "p" && toRank === 7)) mv += "q";
        // Optimistic local apply on the mini board.
        window.chessMenuBoard = window.chessApplyOneMove(window.chessMenuBoard, mv);
        window.chessMenuSelected = -1;
        window.chessMenuHalfmoves += 1;
        window.chessMenuRepaint();
        if (window.chessHasCorrGame && window.chessCorrGameId !== "") {
            // Correspondence → submit the move to Lichess but STAY on the start-page
            // mini-board. Never enter the full "playing" board view, never touch
            // chessGameId/chessStatus (those belong to new/AI/live games only).
            window.chessMenuMyTurn = false;   // optimistic: it's the opponent's turn now
            window.chessSubmitCorrMove(window.chessCorrGameId, mv);
            window.persistCorrState();
            // Refresh the mini-board shortly to pick up the server's authoritative state.
            chessCorrMenuSoon.restart();
        } else {
            // No game → seek correspondence, then play this as move 1 once paired.
            window.chessPendingFirstMove = mv;
            window.chessSeekCorrespondence(14);
        }
    }
    // Submit a correspondence move WITHOUT entering the board view or disturbing
    // the live-game state. Posts directly to the corr game id.
    function chessSubmitCorrMove(corrId, move) {
        let tok = chessSanitizeToken(window.lichessToken);
        let gid = (corrId || "").replace(/[^a-zA-Z0-9]/g, "");
        let mv  = (move || "").replace(/[^a-h0-9qrbn]/g, "");
        if (gid === "" || mv === "") return;
        chessCorrMoveProc.command = ["bash", "-c",
            "curl -s -X POST 'https://lichess.org/api/board/game/" + gid + "/move/" + mv + "' " +
            "-H \"Authorization: Bearer " + tok + "\" >/dev/null 2>&1; echo done"];
        chessCorrMoveProc.running = false; chessCorrMoveProc.running = true;
    }
    Process { id: chessCorrMoveProc; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector { onStreamFinished: { /* fire-and-forget; menu poll refreshes board */ } } }
    // Short delayed refresh of the corr mini-board after we submit a move.
    Timer { id: chessCorrMenuSoon; interval: 1200; repeat: false; onTriggered: window.chessCheckCorrGame() }

    // Persist the current correspondence snapshot to Config (survives restarts).
    function persistCorrState() {
        Config.saveCorrChess(
            window.chessCorrGameId,
            window.chessMenuIsWhite,
            window.chessMenuMyTurn,
            window.chessMenuFen()
        );
    }
    // Build a FEN-ish board string from the menu board (board placement only).
    function chessMenuFen() {
        return window.chessBoardToPlacement ? window.chessBoardToPlacement(window.chessMenuBoard) : "";
    }
    // Restore a persisted correspondence game onto the mini-board at startup, so the
    // start page shows the live game immediately without waiting for the network.
    function restoreCorrFromConfig() {
        if (Config.corrChessGameId && Config.corrChessGameId !== "") {
            window.chessCorrGameId = Config.corrChessGameId;
            window.chessHasCorrGame = true;
            window.chessMenuIsWhite = Config.corrChessIsWhite;
            window.chessMenuMyTurn = Config.corrChessMyTurn;
            if (Config.corrChessFen && Config.corrChessFen !== "") {
                window.chessMenuBoard = window.chessParseFen(Config.corrChessFen.split(" ")[0]);
                window.chessMenuRepaint();
            }
        }
        // Then verify against Lichess (authoritative) shortly after.
        chessCorrMenuSoon.restart();
    }
    Timer { id: corrRestoreTimer; interval: 1400; repeat: false; running: true; onTriggered: window.restoreCorrFromConfig() }
    function chessMenuSquareTapped(realIdx) {
        // Only the side to move may pick up a piece. If no corr game, you're the
        // implicit mover (assume white to start) — pieces of the side to move.
        let piece = window.chessMenuBoard[realIdx] || "";
        let myWhite = window.chessHasCorrGame ? window.chessMenuIsWhite : true;
        let canMove = window.chessHasCorrGame ? window.chessMenuMyTurn : true;
        if (window.chessMenuSelected >= 0) {
            if (realIdx === window.chessMenuSelected) { window.chessMenuSelected = -1; window.chessMenuRepaint(); return; }
            // Validate against legal targets of the selected piece on the mini board.
            let targets = window.chessComputeTargetsOn(window.chessMenuBoard, window.chessMenuSelected, myWhite);
            for (let i = 0; i < targets.length; i++) if (targets[i] === realIdx) { window.chessMenuMove(window.chessMenuSelected, realIdx); return; }
            // Otherwise reselect if it's your own piece.
            let isMine = myWhite ? (piece >= "A" && piece <= "Z") : (piece >= "a" && piece <= "z");
            window.chessMenuSelected = (isMine && canMove) ? realIdx : -1;
            window.chessMenuRepaint();
        } else {
            let isMine = myWhite ? (piece >= "A" && piece <= "Z") : (piece >= "a" && piece <= "z");
            if (isMine && canMove) { window.chessMenuSelected = realIdx; window.chessMenuRepaint(); }
        }
    }
    function chessSeekCorrespondence(days) {
        window.chessStatus = "seeking"; window.chessInitBoard(); window.chessSelected = -1; window.chessResult = "";
        window.chessCreateError = "";
        let tok = chessSanitizeToken(window.lichessToken);
        let d = (days !== undefined && days !== null) ? Number(days) : 14;
        chessSeekProc.command = ["bash", "-c", chessLoggedCmd(
            "POST /api/board/seek days=" + d,
            "curl -s --max-time 180 -X POST 'https://lichess.org/api/board/seek' " +
            "-H \"Authorization: Bearer " + tok + "\" " +
            "-H 'Content-Type: application/x-www-form-urlencoded' " +
            "-H 'Accept: application/x-ndjson' " +
            "--data-urlencode 'rated=false' " +
            "--data-urlencode 'days=" + d + "' " +
            "--data-urlencode 'color=random' " +
            "--data-urlencode 'variant=standard'"
        )];
        chessSeekProc.running = false; chessSeekProc.running = true;
        window.chessWatchEvents();
    }
    function chessSeekGame(minutes, increment) {
        window.chessStatus = "seeking"; window.chessInitBoard(); window.chessSelected = -1; window.chessResult = "";
        window.chessCreateError = "";
        let tok = chessSanitizeToken(window.lichessToken);
        let t = (minutes !== undefined && minutes !== null) ? Number(minutes) : 10;
        let inc = (increment !== undefined && increment !== null) ? Number(increment) : 0;
        // IMPORTANT: /api/board/seek does NOT return the game id. It is a
        // long-poll that holds the connection open until an opponent is found;
        // the actual game id arrives via the incoming EVENTS stream as a
        // "gameStart" event. So we do two things:
        //   1) fire the seek (and keep it open so matchmaking proceeds), and
        //   2) open /api/stream/event and watch for gameStart → game.id.
        // The seek body itself is ignored; we don't parse it for an id.
        chessSeekProc.command = ["bash", "-c", chessLoggedCmd(
            "POST /api/board/seek time=" + t + " inc=" + inc,
            "curl -s --max-time 180 -X POST 'https://lichess.org/api/board/seek' " +
            "-H \"Authorization: Bearer " + tok + "\" " +
            "-H 'Content-Type: application/x-www-form-urlencoded' " +
            "-H 'Accept: application/x-ndjson' " +
            "--data-urlencode 'rated=false' " +
            "--data-urlencode 'time=" + t + "' " +
            "--data-urlencode 'increment=" + inc + "' " +
            "--data-urlencode 'color=random' " +
            "--data-urlencode 'variant=standard'"
        )];
        chessSeekProc.running = false; chessSeekProc.running = true;
        // Start watching the events stream for the gameStart.
        window.chessWatchEvents();
    }
    // Open the incoming events stream and watch for a gameStart. When one
    // arrives, capture the game id and enter the board (the normal poll then
    // takes over for moves/clocks/colors). Used for human seeks and accepted
    // challenges, where the id is delivered out-of-band.
    function chessWatchEvents() {
        let tok = chessSanitizeToken(window.lichessToken);
        chessEventProc.command = ["bash", "-c",
            "curl -sN --no-buffer --max-time 180 'https://lichess.org/api/stream/event' " +
            "-H 'Accept: application/x-ndjson' -H \"Authorization: Bearer " + tok + "\" 2>/dev/null"
        ];
        chessEventProc.running = false; chessEventProc.running = true;
    }
    function chessStopEvents() { chessSeekProc.running = false; chessEventProc.running = false; }
    Process {
        id: chessSeekProc; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector { onStreamFinished: {
            // The seek closed. If we're still "seeking" and never got a game,
            // surface that rather than silently bouncing to the menu.
            if (window.chessStatus === "seeking") {
                let raw = (this.text || "").trim();
                window.chessDebugCreate = ("seek closed: " + raw).substring(0, 300);
                // Don't reset here on its own — the event stream may still
                // deliver gameStart momentarily. The watchdog handles giving up.
            }
        }}
    }
    Process {
        id: chessEventProc; command: ["bash", "-c", "echo idle"]
        stdout: SplitParser {
            onRead: (line) => {
                let s = (line || "").trim();
                if (s === "" || s === "idle") return;
                let ev;
                try { ev = JSON.parse(s); } catch(e) { return; }
                if (ev.type === "gameStart" && ev.game && (ev.game.id || ev.game.gameId)) {
                    let gid = ev.game.id || ev.game.gameId;
                    window.chessGameId = gid;
                    window.chessStatus = "playing";
                    window.chessHalfmoveCount = -1;   // force first poll to apply
                    window.chessIsAiGame = false;
                    // color hint if present
                    if (ev.game.color === "white") window.chessIsWhite = true;
                    else if (ev.game.color === "black") window.chessIsWhite = false;
                    window.chessMyTurn = (ev.game.isMyTurn === true);
                    window.saveChessState();
                    window.chessPollSoon();
                    window.chessStopEvents();   // got our game; stop watching
                    // If a start-page correspondence move was queued, submit it
                    // as move 1 now that we're paired (only if it's our turn —
                    // for a random color we may be black and wait instead).
                    if (window.chessPendingFirstMove !== "") {
                        let pend = window.chessPendingFirstMove;
                        window.chessPendingFirstMove = "";
                        if (window.chessMyTurn) Qt.callLater(function(){ window.chessMakeMove(pend); });
                    }
                } else if (ev.type === "gameFinish") {
                    // ignore here; the game poll handles end-of-game
                }
            }
        }
    }
    // Debug: last raw create response + last stream event, surfaced on-screen
    // so we can diagnose game-creation / stream issues without the log file.
    property string chessDebugCreate: ""
    property string chessDebugStream: ""
    // ── Live game sync ───────────────────────────────────────────────────
    // We keep the board in sync with Lichess by polling the game state on a
    // steady timer while a game is in progress. This is simpler and more robust
    // than a long-lived streaming subprocess: one short request, one JSON line,
    // applied to the board. chessHalfmoveCount tracks how many half-moves our
    // local board reflects so we know when the opponent has replied.
    property int chessHalfmoveCount: 0

    function chessMakeMove(move) {
        window.chessClearArrows();   // a move was made — stale plans no longer apply
        let tok = chessSanitizeToken(window.lichessToken);
        let gid = window.chessGameId.replace(/[^a-zA-Z0-9]/g, "");
        let mv  = move.replace(/[^a-h0-9qrbn]/g, "");
        chessMoveProc.command = ["bash", "-c", chessLoggedCmd(
            "POST /api/board/game/" + gid + "/move/" + mv,
            "curl -s -X POST 'https://lichess.org/api/board/game/" + gid + "/move/" + mv + "' " +
            "-H \"Authorization: Bearer " + tok + "\""
        )];
        chessMoveProc.running = false; chessMoveProc.running = true;
        // Poll promptly for the opponent's reply.
        chessPollSoon();
    }

    // Connect to the board game stream and keep it open, processing each NDJSON
    // line as it arrives. A single long-lived connection (not repeated reopens)
    // is how Lichess intends the stream to be consumed and avoids rate-limiting.
    // First line is gameFull; subsequent lines are gameState deltas.
    function chessPollGameState() {
        if (window.chessStatus !== "playing" || !window.chessGameId) return;
        if (chessPollProc.running) return;   // already connected
        let tok = chessSanitizeToken(window.lichessToken);
        let gid = window.chessGameId.replace(/[^a-zA-Z0-9]/g, "");
        chessPollProc.command = ["bash", "-c",
            "curl -sN --no-buffer " +
            "'https://lichess.org/api/board/game/stream/" + gid + "' " +
            "-H 'Accept: application/x-ndjson' -H \"Authorization: Bearer " + tok + "\" 2>/dev/null"
        ];
        chessPollProc.running = false; chessPollProc.running = true;
    }
    // Connect now, and start the watchdog that reconnects on drop.
    function chessPollSoon() { chessPollGameState(); chessPollTimer.start(); }

    // Apply one NDJSON line from the game stream to board/clock/status.
    function chessHandleStreamLine(raw) {
        raw = (raw || "").trim();
        if (raw === "" || raw === "idle") return;   // keep-alive blank line
        window.chessDebugStream = raw.substring(0, 300);
        let ev;
        try { ev = JSON.parse(raw); } catch(e) { return; }
        // Colors (only present on the gameFull line): match our username against
        // the named players; fall back to aiLevel (Stockfish side has aiLevel).
        if (ev.white !== undefined || ev.black !== undefined) {
            let myName = (window.lichessUsername || "").toLowerCase();
            let whiteId = ((ev.white && (ev.white.id || ev.white.name)) || "").toString().toLowerCase();
            let blackId = ((ev.black && (ev.black.id || ev.black.name)) || "").toString().toLowerCase();
            if (myName !== "" && whiteId === myName) window.chessIsWhite = true;
            else if (myName !== "" && blackId === myName) window.chessIsWhite = false;
            else if (ev.white && ev.white.aiLevel) window.chessIsWhite = false;
            else if (ev.black && ev.black.aiLevel) window.chessIsWhite = true;
            let oppObj = window.chessIsWhite ? ev.black : ev.white;
            window.chessIsAiGame = !!((ev.white && ev.white.aiLevel) || (ev.black && ev.black.aiLevel));
            // Correspondence games have speed=="correspondence" (or a days-based
            // clock). They get a stripped UI: no timer, no chat, no resign/etc.
            if (ev.speed !== undefined) window.chessIsCorr = (ev.speed === "correspondence");
            else if (ev.clock === undefined && ev.daysPerTurn !== undefined) window.chessIsCorr = true;
            if (oppObj && oppObj.aiLevel) window.chessOpponent = "Stockfish L" + oppObj.aiLevel;
            else if (oppObj && oppObj.name) window.chessOpponent = oppObj.name;
        }
        // Clocks (ms). Skip AI games; treat the max-int sentinel as "no clock".
        let stObj = (ev.state && ev.state.wtime !== undefined) ? ev.state : (ev.wtime !== undefined ? ev : null);
        let UNLIMITED = 2147483647;
        if (stObj && !window.chessIsAiGame
                && stObj.wtime !== undefined && stObj.btime !== undefined
                && stObj.wtime < UNLIMITED && stObj.btime < UNLIMITED) {
            window.chessWhiteMs = stObj.wtime;
            window.chessBlackMs = stObj.btime;
            window.chessClocksKnown = true;
        }
        // Moves (UCI): gameFull → ev.state.moves, bare gameState → ev.moves.
        let movesUci = (ev.state && ev.state.moves !== undefined) ? ev.state.moves
                     : (ev.moves !== undefined ? ev.moves : null);
        if (movesUci !== null) {
            let n = movesUci.trim() === "" ? 0 : movesUci.trim().split(" ").length;
            if (n !== window.chessHalfmoveCount) {
                window.chessApplyMoves(movesUci);   // rebuilds board + recomputes turn
                window.chessHalfmoveCount = n;
            } else {
                window.chessMyTurn = (n % 2 === 0) === window.chessIsWhite;
            }
        }
        // Status: end the game on a terminal state.
        let st = (ev.state && ev.state.status) ? ev.state.status : ev.status;
        if (st && st !== "started" && st !== "created") {
            window.chessStatus = "ended"; window.chessResult = st;
            window.saveChessState(); chessPollTimer.stop();
        }
    }

    // Format milliseconds as M:SS (or H:MM:SS for long clocks).
    function chessFmtClock(ms) {
        if (ms < 0) ms = 0;
        let totalSec = Math.floor(ms / 1000);
        let h = Math.floor(totalSec / 3600);
        let m = Math.floor((totalSec % 3600) / 60);
        let s = totalSec % 60;
        let pad = function(n){ return (n < 10 ? "0" : "") + n; };
        if (h > 0) return h + ":" + pad(m) + ":" + pad(s);
        return m + ":" + pad(s);
    }
    // Tick the side-to-move's clock down once per second between polls so the
    // display stays live. Polls re-sync to the authoritative server value.
    Timer {
        id: chessClockTick; interval: 1000; repeat: true
        running: window.chessStatus === "playing" && window.chessClocksKnown && !window.chessIsAiGame
        onTriggered: {
            // Whose clock runs = side to move = (halfmove count even → white).
            let whiteToMove = (window.chessHalfmoveCount % 2 === 0);
            if (whiteToMove) window.chessWhiteMs = Math.max(0, window.chessWhiteMs - 1000);
            else window.chessBlackMs = Math.max(0, window.chessBlackMs - 1000);
        }
    }

    // Watchdog: reconnect the stream if it drops while a game is live.
    Timer {
        id: chessPollTimer; interval: 4000; repeat: true; running: false
        onTriggered: {
            if (window.chessStatus === "playing" && window.chessGameId) {
                if (!chessPollProc.running) window.chessPollGameState();
            } else {
                stop();
            }
        }
    }
    Process {
        id: chessPollProc; command: ["bash", "-c", "echo idle"]
        stdout: SplitParser {
            onRead: (line) => { window.chessHandleStreamLine(line); }
        }
    }
    function chessResign() {
        let tok = chessSanitizeToken(window.lichessToken);
        let gid = window.chessGameId.replace(/[^a-zA-Z0-9]/g, "");
        Quickshell.execDetached(["bash", "-c", chessLoggedCmd(
            "POST /api/board/game/" + gid + "/resign",
            "curl -s -X POST 'https://lichess.org/api/board/game/" + gid + "/resign' " +
            "-H \"Authorization: Bearer " + tok + "\""
        )]);
    }
    // Offer / accept a draw (yes), or decline (no).
    function chessOfferDraw(accept) {
        let tok = chessSanitizeToken(window.lichessToken);
        let gid = window.chessGameId.replace(/[^a-zA-Z0-9]/g, "");
        let yn = accept ? "yes" : "no";
        Quickshell.execDetached(["bash", "-c", chessLoggedCmd(
            "POST /api/board/game/" + gid + "/draw/" + yn,
            "curl -s -X POST 'https://lichess.org/api/board/game/" + gid + "/draw/" + yn + "' " +
            "-H \"Authorization: Bearer " + tok + "\""
        )]);
        window.chessActionFlash = accept ? "Draw offered" : "Draw declined";
        chessActionFlashTimer.restart();
    }
    // Propose / accept a takeback (yes), or decline (no).
    function chessTakeback(accept) {
        let tok = chessSanitizeToken(window.lichessToken);
        let gid = window.chessGameId.replace(/[^a-zA-Z0-9]/g, "");
        let yn = accept ? "yes" : "no";
        Quickshell.execDetached(["bash", "-c", chessLoggedCmd(
            "POST /api/board/game/" + gid + "/takeback/" + yn,
            "curl -s -X POST 'https://lichess.org/api/board/game/" + gid + "/takeback/" + yn + "' " +
            "-H \"Authorization: Bearer " + tok + "\""
        )]);
        window.chessActionFlash = accept ? "Takeback proposed" : "Takeback declined";
        chessActionFlashTimer.restart();
    }
    // Add time to the opponent's clock (Lichess only allows giving time to the
    // opponent; the unit is seconds, typically 15).
    function chessAddTime(seconds) {
        let tok = chessSanitizeToken(window.lichessToken);
        let gid = window.chessGameId.replace(/[^a-zA-Z0-9]/g, "");
        let secs = Math.max(1, Math.min(86400, parseInt(seconds) || 15));
        Quickshell.execDetached(["bash", "-c", chessLoggedCmd(
            "POST /api/round/" + gid + "/add-time/" + secs,
            "curl -s -X POST 'https://lichess.org/api/round/" + gid + "/add-time/" + secs + "' " +
            "-H \"Authorization: Bearer " + tok + "\""
        )]);
        window.chessActionFlash = "+" + secs + "s to opponent";
        chessActionFlashTimer.restart();
    }
    // Send a message to the game chat (room: "player" or "spectator").
    property bool chessDebugVisible: false   // toggled by the /debug chat command
    function chessSendChat(text, room) {
        let t = (text || "").trim();
        if (t === "") return;
        // Local slash-commands — handled in-app, never sent to Lichess.
        if (t[0] === "/") {
            let cmd = t.toLowerCase().split(" ")[0];
            if (cmd === "/debug") {
                window.chessDebugVisible = !window.chessDebugVisible;
                chessChatModel.append({ user: "system", text: "Debug info " + (window.chessDebugVisible ? "ON" : "OFF"), room: "spectator" });
            } else if (cmd === "/help") {
                chessChatModel.append({ user: "system", text: "Commands: /debug (toggle diagnostics), /help", room: "spectator" });
            } else {
                chessChatModel.append({ user: "system", text: "Unknown command: " + cmd + "  (try /help)", room: "spectator" });
            }
            return;   // don't transmit slash-commands
        }
        let tok = chessSanitizeToken(window.lichessToken);
        let gid = window.chessGameId.replace(/[^a-zA-Z0-9]/g, "");
        let rm = (room === "spectator") ? "spectator" : "player";
        // URL-encode the message body safely via --data-urlencode.
        chessChatSendProc.command = ["bash", "-c", chessLoggedCmd(
            "POST /api/board/game/" + gid + "/chat",
            "curl -s -X POST 'https://lichess.org/api/board/game/" + gid + "/chat' " +
            "-H \"Authorization: Bearer " + tok + "\" " +
            "--data-urlencode 'room=" + rm + "' " +
            "--data-urlencode text@- <<'QSCHATEOF'\n" + t + "\nQSCHATEOF"
        )];
        chessChatSendProc.running = false; chessChatSendProc.running = true;
        // Show our own message immediately (the stream echo may lag).
        chessChatModel.append({ user: "You", text: t, room: rm });
    }
    Process { id: chessChatSendProc; command: ["bash", "-c", "echo idle"] }

    // ── Computer analysis ──
    // Request Lichess compute a full-game analysis, then fetch the per-move
    // evals + judgments and render them locally on the board.
    // "Learn from my mistakes": once analysis is in, export the game's moves +
    // evals and ask Hermes (the same agent the chat uses) to coach the user
    // through their biggest mistakes. The reply is shown on the analysis page.
    property string chessMistakesReview: ""
    property bool chessMistakesLoading: false
    function chessLearnFromMistakes() {
        if (!window.chessGameId) return;
        window.chessMistakesLoading = true;
        window.chessMistakesReview = "";
        let tok = chessSanitizeToken(window.lichessToken);
        let gid = window.chessGameId.replace(/[^a-zA-Z0-9]/g, "");
        let sideStr = window.chessIsWhite ? "white" : "black";
        // Export the PGN (with evals) and pipe a coaching prompt to Hermes.
        chessMistakesProc.command = ["bash", "-c",
            "PGN=$(curl -s 'https://lichess.org/game/export/" + gid + "?evals=true&clocks=false&literate=true' " +
            "-H 'Accept: application/x-chess-pgn' -H \"Authorization: Bearer " + tok + "\" 2>/dev/null); " +
            "PROMPT=\"You are a chess coach. I played as " + sideStr + ". Here is my game in PGN with engine evals. " +
            "Identify my 3 biggest mistakes (blunders/inaccuracies), explain WHY each was bad and what I should have played, " +
            "and give me one concrete thing to work on. Be encouraging and concise.\\n\\nPGN:\\n$PGN\"; " +
            "echo \"$PROMPT\" | HERMES_SESSION_OVERRIDE=qschess-coach ~/.config/hypr/scripts/hermes_bridge.sh 2>/dev/null"
        ];
        chessMistakesProc.running = false; chessMistakesProc.running = true;
    }
    Process {
        id: chessMistakesProc; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector { onStreamFinished: {
            window.chessMistakesLoading = false;
            let t = (this.text || "").trim();
            if (t === "" || t === "idle") { window.chessMistakesReview = "Couldn't reach the coach. Check Hermes setup in the Agent tab."; return; }
            try { let d = JSON.parse(t); window.chessMistakesReview = d.content || d.response || t; }
            catch(e) { window.chessMistakesReview = t; }
        }}
    }
    function chessRequestAnalysis() {
        if (!window.chessGameId) return;
        window.chessAnalysisStatus = "requesting";
        let tok = chessSanitizeToken(window.lichessToken);
        let gid = window.chessGameId.replace(/[^a-zA-Z0-9]/g, "");
        // POST request-analysis (may 200 immediately if already analysed, or
        // start a job). Either way we then poll the export for the eval array.
        chessAnalysisReqProc.command = ["bash", "-c", chessLoggedCmd(
            "POST /api/game/" + gid + "/analysis",
            "curl -s -o /dev/null -w '%{http_code}' -X POST 'https://lichess.org/api/game/" + gid + "/analysis' " +
            "-H \"Authorization: Bearer " + tok + "\""
        )];
        chessAnalysisReqProc.running = false; chessAnalysisReqProc.running = true;
    }
    Process {
        id: chessAnalysisReqProc; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector { onStreamFinished: {
            // Whatever the POST returned, start polling the export for evals.
            window.chessAnalysisStatus = "polling";
            window.chessAnalysisPollCount = 0;
            chessAnalysisPoll.restart();
        }}
    }
    function chessFetchAnalysis() {
        let tok = chessSanitizeToken(window.lichessToken);
        let gid = window.chessGameId.replace(/[^a-zA-Z0-9]/g, "");
        chessAnalysisFetchProc.command = ["bash", "-c", chessLoggedCmd(
            "GET /game/export/" + gid + " (analysis)",
            "curl -s 'https://lichess.org/game/export/" + gid + "?evals=true&accuracy=true&literate=true&clocks=false' " +
            "-H 'Accept: application/json' -H \"Authorization: Bearer " + tok + "\""
        )];
        chessAnalysisFetchProc.running = false; chessAnalysisFetchProc.running = true;
    }
    Timer {
        id: chessAnalysisPoll; interval: 2500; repeat: false
        onTriggered: window.chessFetchAnalysis()
    }
    Process {
        id: chessAnalysisFetchProc; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector { onStreamFinished: {
            let raw = (this.text || "").trim();
            if (raw === "" || raw === "idle") { chessAnalysisRetry(); return; }
            try {
                let data = JSON.parse(raw);
                if (data.analysis && data.analysis.length > 0) {
                    window.chessApplyAnalysis(data);
                    window.chessAnalysisStatus = "ready";
                } else {
                    chessAnalysisRetry();
                }
            } catch(e) { chessAnalysisRetry(); }
        }}
    }
    function chessAnalysisRetry() {
        window.chessAnalysisPollCount += 1;
        if (window.chessAnalysisPollCount > 20) {     // ~50s total
            window.chessAnalysisStatus = "timeout";
            return;
        }
        chessAnalysisPoll.restart();
    }
    // Parse the export JSON into our analysis model + per-player summary.
    function chessApplyAnalysis(data) {
        let moves = (data.moves || "").split(" ").filter(function(m){ return m.length > 0; });
        let an = data.analysis || [];
        chessAnalysisModel.clear();
        for (let i = 0; i < an.length; i++) {
            let entry = an[i];
            let j = entry.judgment || null;
            chessAnalysisModel.append({
                ply: i,
                san: moves[i] || "",
                evalCp: (entry.eval !== undefined ? entry.eval : 0),
                mate: (entry.mate !== undefined ? entry.mate : 0),
                judgeName: j ? j.name : "",          // Inaccuracy | Mistake | Blunder
                judgeComment: j ? (j.comment || "") : "",
                best: entry.best || "",
                variation: entry.variation || ""
            });
        }
        // Per-player summaries from players.{white,black}.analysis
        let pw = (data.players && data.players.white && data.players.white.analysis) || {};
        let pb = (data.players && data.players.black && data.players.black.analysis) || {};
        window.chessAnalysisWhite = { inaccuracy: pw.inaccuracy||0, mistake: pw.mistake||0, blunder: pw.blunder||0, acpl: pw.acpl||0, accuracy: (data.players&&data.players.white&&data.players.white.accuracy)||0 };
        window.chessAnalysisBlack = { inaccuracy: pb.inaccuracy||0, mistake: pb.mistake||0, blunder: pb.blunder||0, acpl: pb.acpl||0, accuracy: (data.players&&data.players.black&&data.players.black.accuracy)||0 };
        // Build a board position list by replaying SAN-ish UCI from moves so the
        // analysis page can step through positions. We reuse chessApplyMoves
        // logic by storing the move string; stepping rebuilds from scratch.
        window.chessAnalysisMovesStr = data.moves || "";
    }
    function chessEloToLevel(elo) {
        // Map 800-2800 to Stockfish level 1-8
        if (elo <= 800) return 1;
        if (elo >= 2800) return 8;
        return Math.max(1, Math.min(8, Math.round((elo - 800) / 285 + 1)));
    }
    // Open the external webpage/app associated with a module (slider double-click).
    function openModuleWebpage(mode) {
        if (mode === "chess") Quickshell.execDetached(["xdg-open", "https://lichess.org"]);
        else if (mode === "kavita") Quickshell.execDetached(["xdg-open", window.kavitaUrl]);
        else if (mode === "chat") Quickshell.execDetached(["xdg-open", "https://github.com/wenmill"]);
        else if (mode === "notes") window.obsidianOpenNote("");
        else if (mode === "learn") Quickshell.execDetached(["xdg-open", window.kavitaUrl]);
    }

    function chessStartAiFromElo() {
        let level = chessEloToLevel(window.chessAiElo);
        window.chessStartAi(level, 10);
    }
    function chessFetchPuzzle() {
        window.chessStatus = "puzzle";
        // Try the prefetched daily puzzle first — Main.qml's puzzlePrefetcher
        // pulls it at shell start and every 6 hours, so the file is usually
        // already there. Only fall through to a live call if the cache is
        // missing or malformed.
        chessPuzzleCacheReader.command = ["bash", "-c",
            "cat \"$HOME/.cache/qs_ai_state/puzzle_daily.json\" 2>/dev/null"
        ];
        chessPuzzleCacheReader.running = false;
        chessPuzzleCacheReader.running = true;
    }
    Process {
        id: chessPuzzleCacheReader
        command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                let raw = (this.text || "").trim();
                if (raw.length > 0 && raw !== "idle") {
                    // Reuse the same parser by handing the JSON straight to
                    // chessPuzzleProc's handler logic via a synthetic event.
                    try {
                        // Validate it parses + has the expected shape first.
                        let test = JSON.parse(raw);
                        if ((test.puzzle && test.puzzle.fen) || test.fen || (test.game && test.game.fen)) {
                            window.chessApplyPuzzleResponse(raw);
                            return;
                        }
                    } catch(e) { /* fall through to live fetch */ }
                }
                // Cache miss or invalid — do a live fetch (the original flow).
                let tok = chessSanitizeToken(window.lichessToken);
                chessPuzzleProc.command = ["bash", "-c", chessLoggedCmd(
                    "GET /api/puzzle/daily (cache miss)",
                    "curl -s 'https://lichess.org/api/puzzle/daily' -H \"Authorization: Bearer " + tok + "\""
                )];
                chessPuzzleProc.running = false;
                chessPuzzleProc.running = true;
            }
        }
    }
    // /api/puzzle/next returns a random puzzle (rotates each call). Use this for
    // the "Next Puzzle" button so the user isn't stuck on the same daily puzzle.
    function chessFetchNextPuzzle() {
        window.chessStatus = "puzzle";
        let tok = chessSanitizeToken(window.lichessToken);
        chessPuzzleProc.command = ["bash", "-c", chessLoggedCmd(
            "GET /api/puzzle/next",
            "curl -s 'https://lichess.org/api/puzzle/next' -H \"Authorization: Bearer " + tok + "\""
        )];
        chessPuzzleProc.running = false;
        chessPuzzleProc.running = true;
    }
    // Apply a raw JSON puzzle response (from either the cache or a live fetch)
    // to the board state. Shared by chessPuzzleProc and chessPuzzleCacheReader.
    function chessApplyPuzzleResponse(raw) {
        try {
            let data = JSON.parse(raw);
            let puzzle = data.puzzle || data;
            window.chessPuzzleFen = puzzle.fen || (data.game ? data.game.fen : "");
            window.chessPuzzleMoves = (puzzle.solution || []).join(" ");
            window.chessPuzzleRating = puzzle.rating || 0;
            if (window.chessPuzzleFen) {
                window.chessPuzzleStartFen = window.chessPuzzleFen;
                window.chessBoard = window.chessParseFen(window.chessPuzzleFen);
                window.chessBoardChanged();
                // Lichess convention: FEN's side-to-move is the OPPONENT, who plays
                // solution[0] automatically. The user plays the opposite color.
                let parts = window.chessPuzzleFen.split(" ");
                window.chessIsWhite = parts.length > 1 ? parts[1] !== "w" : false;
                window.chessMyTurn = false;
                window.chessSelected = -1;
                window.chessFromIdx = -1;
                window.chessToIdx = -1;
                window.chessPuzzleStep = 0;
                window.chessPuzzleSolved = false;
                window.chessPuzzleFeedback = "";
                chessPuzzleOpponentTimer.restart();   // auto-play opponent's setup move
            }
        } catch(e) {
            window.chessStatus = "menu";
        }
    }
    Process {
        id: chessPuzzleProc
        command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector { onStreamFinished: {
            if (this.text.trim() === "idle") return;
            window.chessApplyPuzzleResponse(this.text.trim());
        }}
    }
    // Sanitise the Lichess token before interpolating into any bash command.
    // Lichess tokens are alnum + "_" + "-", but defend against pathological input.
    function chessSanitizeToken(t) { return (t || "").replace(/[^A-Za-z0-9_\-]/g, ""); }

    // Fetch my own Lichess username so we can tell which color I'm playing in a
    // given game (by matching white.id / black.id against it). Also probes the
    // token's scopes so we can warn if a required one (board:play) is missing.
    property var chessTokenScopes: []
    property bool chessHasBoardPlay: true   // assume ok until proven otherwise
    property bool chessHasChallengeWrite: true
    function chessFetchAccount() {
        let tok = chessSanitizeToken(window.lichessToken);
        if (tok === "") return;
        chessAccountProc.command = ["bash", "-c",
            "curl -s 'https://lichess.org/api/account' -H \"Authorization: Bearer " + tok + "\" 2>/dev/null"
        ];
        chessAccountProc.running = false; chessAccountProc.running = true;
        // /api/token/test echoes back the scopes granted to the token.
        chessScopeProc.command = ["bash", "-c",
            "curl -s -X POST 'https://lichess.org/api/token/test' " +
            "-H 'Content-Type: application/x-www-form-urlencoded' " +
            "--data-urlencode 'tokens=" + tok + "' 2>/dev/null"
        ];
        chessScopeProc.running = false; chessScopeProc.running = true;
    }
    Process {
        id: chessAccountProc; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector { onStreamFinished: {
            let raw = (this.text || "").trim();
            if (raw === "" || raw === "idle") return;
            try {
                let acc = JSON.parse(raw);
                if (acc.username) window.lichessUsername = acc.username;
                else if (acc.id) window.lichessUsername = acc.id;
            } catch(e) {}
        }}
    }
    Process {
        id: chessScopeProc; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector { onStreamFinished: {
            let raw = (this.text || "").trim();
            if (raw === "" || raw === "idle") return;
            try {
                // Response: { "<token>": { "scopes": "board:play,challenge:write", ... } }
                // or { "<token>": null } for an unknown token. We only DOWNGRADE
                // the flags when we positively parse a scope list that's missing
                // an entry — never when parsing is ambiguous, so we don't show a
                // false warning when the token actually works.
                let obj = JSON.parse(raw);
                let entry = null;
                for (let k in obj) { entry = obj[k]; break; }
                if (!entry || entry.scopes === undefined || entry.scopes === null) return;  // can't tell → leave optimistic
                let scopesStr = entry.scopes || "";
                let list = scopesStr.split(",").map(function(s){ return s.trim(); }).filter(function(s){ return s.length > 0; });
                if (list.length === 0) return;   // empty/ambiguous → leave optimistic
                window.chessTokenScopes = list;
                window.chessHasBoardPlay = list.indexOf("board:play") >= 0;
                window.chessHasChallengeWrite = list.indexOf("challenge:write") >= 0;
            } catch(e) { /* parse failure → leave flags optimistic, no false warning */ }
        }}
    }

    // Wrap a bash one-liner so its stderr is appended to a debug log and the
    // action is timestamped in the log too. Use this for every Lichess HTTP
    // call so failures (401, 404, network, DNS, etc.) leave a trace instead
    // of vanishing into /dev/null.
    function chessLoggedCmd(desc, body) {
        let safeDesc = (desc || "").replace(/[\"'\\$`]/g, "");
        // Capture both stderr (network errors, curl messages) AND stdout (response
        // body, HTTP error pages, JSON error responses) so failures aren't silent.
        // The response body is also forwarded to the caller's stdout for parsing.
        // curl -s silences progress; we add -w '\nHTTP %{http_code}\n' which prints
        // the status code on stdout — Quickshell's parser ignores the trailer
        // because it picks the JSON line, and the log gets a clear status code.
        return "mkdir -p \"$HOME/.cache/quickshell\" && " +
               "echo \"[$(date '+%F %T')] " + safeDesc + "\" >> \"$HOME/.cache/quickshell/lichess.log\" && " +
               "{ " + body + " ; } 2>>\"$HOME/.cache/quickshell/lichess.log\" | " +
               "tee -a \"$HOME/.cache/quickshell/lichess.log\"";
    }

    // Auto-clear chessMoveError after a few seconds so the banner doesn't linger.
    Timer { id: chessMoveErrorTimer; interval: 4000; repeat: false; onTriggered: window.chessMoveError = "" }

    // Before resuming a cached "playing" game, ask Lichess whether it's still
    // ongoing. A finished/aborted/missing game would otherwise leave the user
    // stuck on a dead board with no terminal event to clear it.
    function chessVerifyAndRestore() {
        let tok = chessSanitizeToken(window.lichessToken);
        let gid = window.chessGameId.replace(/[^a-zA-Z0-9]/g, "");
        chessVerifyProc.command = ["bash", "-c",
            "curl -s 'https://lichess.org/game/export/" + gid + "?moves=false&clocks=false&evals=false&opening=false' " +
            "-H 'Accept: application/json' -H \"Authorization: Bearer " + tok + "\" 2>/dev/null"
        ];
        chessVerifyProc.running = false;
        chessVerifyProc.running = true;
    }
    Process {
        id: chessVerifyProc; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector { onStreamFinished: {
            let raw = (this.text || "").trim();
            if (raw === "" || raw === "idle") { window.chessResetToMenu(); return; }
            try {
                let g = JSON.parse(raw);
                // status "started" / "created" = still live; anything else
                // (mate, resign, draw, aborted, timeout, etc.) = over.
                if (g.status === "started" || g.status === "created") {
                    window.chessStatus = "playing";
                    window.chessHalfmoveCount = -1;   // force next poll to apply moves
                    window.chessPollSoon();
                } else {
                    window.chessResetToMenu();
                }
            } catch(e) { window.chessResetToMenu(); }
        }}
    }
    // Clear chess state and return to the menu (used when a restored game is
    // dead, or as a manual escape hatch).
    function chessResetToMenu() {
        window.chessStatus = "menu";
        window.chessGameId = "";
        window.chessSelected = -1;
        window.chessFromIdx = -1;
        window.chessToIdx = -1;
        window.chessResult = "";
        window.chessMoveError = "";
        window.chessClearArrows();
        window.chessClearPremoves();
        window.chessInitBoard();
        chessPollTimer.stop();
        window.chessStopEvents();   // stop any pending seek + event stream
        window.saveChessState();
    }

    // Shared 8x8 board cell. Used by both the puzzle and playing views — same look,
    // same selection/last-move highlighting; routes clicks to whichever handler is active.
    Component {
        id: chessSquareDelegate
        Rectangle {
            id: sq
            width: parent.width / 8; height: parent.height / 8
            property int row: Math.floor(index / 8)
            property int col: index % 8
            property bool isLight: (row + col) % 2 === 0
            property int realIdx: window.chessIsWhite ? index : (63 - index)
            property string piece: window.chessBoard[realIdx] || ""
            property bool isSelected: window.chessSelected === realIdx
            property bool isLastFrom: window.chessFromIdx === realIdx
            property bool isLastTo: window.chessToIdx === realIdx
            property bool isDragSource: window.chessDragging && window.chessDragFrom === realIdx
            // Is this square part of a queued premove (either end of any premove)?
            property bool isPremove: {
                let pms = window.chessPremoves;
                for (let i = 0; i < pms.length; i++) if (pms[i].from === realIdx || pms[i].to === realIdx) return true;
                return false;
            }
            property bool wrongFlash: window.chessStatus === "puzzle"
                                       && window.chessPuzzleFeedback === "wrong"
                                       && isLastFrom
            // Fancier square: subtle vertical gradient + bevel highlight.
            gradient: Gradient {
                GradientStop { position: 0.0; color: sq.squareColorTop }
                GradientStop { position: 1.0; color: sq.squareColorBottom }
            }
            property color baseLight: Qt.rgba(window.surface2.r, window.surface2.g, window.surface2.b, 1.0)   // matugen light square
            property color baseDark:  Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 1.0)   // matugen dark square
            property color squareColorTop: isSelected
                   ? Qt.rgba(window.yellow.r, window.yellow.g, window.yellow.b, 0.75)
                   : isPremove ? Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.6)
                   : wrongFlash ? Qt.rgba(window.red.r, window.red.g, window.red.b, 0.5)
                   : (isLastFrom || isLastTo) ? Qt.rgba(window.blue.r, window.blue.g, window.blue.b, 0.45)
                   : isLight ? Qt.lighter(baseLight, 1.04) : Qt.lighter(baseDark, 1.12)
            property color squareColorBottom: isSelected
                   ? Qt.rgba(window.yellow.r, window.yellow.g, window.yellow.b, 0.55)
                   : isPremove ? Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.4)
                   : wrongFlash ? Qt.rgba(window.red.r, window.red.g, window.red.b, 0.3)
                   : (isLastFrom || isLastTo) ? Qt.rgba(window.blue.r, window.blue.g, window.blue.b, 0.28)
                   : isLight ? baseLight : baseDark
            Behavior on squareColorTop { ColorAnimation { duration: 120 } }
            Behavior on squareColorBottom { ColorAnimation { duration: 120 } }

            // Coordinate labels: file letters on bottom row, rank numbers on left col.
            Text {
                visible: sq.col === 0
                anchors.left: parent.left; anchors.top: parent.top
                anchors.leftMargin: window.s(2); anchors.topMargin: window.s(1)
                text: window.chessIsWhite ? (8 - sq.row).toString() : (sq.row + 1).toString()
                font.family: "JetBrains Mono"; font.pixelSize: parent.width * 0.16; font.weight: Font.Bold
                color: sq.isLight ? Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.85) : Qt.rgba(window.surface2.r, window.surface2.g, window.surface2.b, 0.85)
            }
            Text {
                visible: sq.row === 7
                anchors.right: parent.right; anchors.bottom: parent.bottom
                anchors.rightMargin: window.s(2); anchors.bottomMargin: window.s(1)
                text: window.chessIsWhite ? String.fromCharCode(97 + sq.col) : String.fromCharCode(104 - sq.col)
                font.family: "JetBrains Mono"; font.pixelSize: parent.width * 0.16; font.weight: Font.Bold
                color: sq.isLight ? Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.85) : Qt.rgba(window.surface2.r, window.surface2.g, window.surface2.b, 0.85)
            }

            // Move hint: filled dot on empty legal targets, ring on captures.
            property bool isLegalTarget: {
                let t = window.chessLegalTargets;
                for (let i = 0; i < t.length; i++) if (t[i] === sq.realIdx) return true;
                return false;
            }
            Rectangle {
                visible: sq.isLegalTarget && sq.piece === ""
                anchors.centerIn: parent
                width: parent.width * 0.30; height: width; radius: width / 2
                color: Qt.rgba(window.green.r, window.green.g, window.green.b, 0.45)
            }
            // Capture indicator: a ring around an enemy piece that can be taken.
            Rectangle {
                visible: sq.isLegalTarget && sq.piece !== ""
                anchors.centerIn: parent
                width: parent.width * 0.92; height: width; radius: width / 2
                color: "transparent"
                border.color: Qt.rgba(window.green.r, window.green.g, window.green.b, 0.55)
                border.width: Math.max(2, parent.width * 0.06)
            }

            // The piece glyph — a fallback shown beneath the CDN image. Hidden
            // while this square's piece is being dragged (the floating drag piece
            // is drawn on the overlay instead).
            Text {
                id: pieceGlyph
                anchors.centerIn: parent
                visible: !sq.isDragSource && sq.piece !== "" && pieceImg.status !== Image.Ready
                text: window.chessPieceChar(sq.piece)
                font.pixelSize: parent.width * 0.78
                color: sq.piece >= "A" && sq.piece <= "Z" ? "#fafafa" : "#15151f"
                style: Text.Outline
                styleColor: sq.piece >= "A" && sq.piece <= "Z" ? "#444444" : "#bbbbbb"
                layer.enabled: true
            }
            // Lichess CDN piece image (cburnett). Renders over the glyph; if it
            // fails to load (offline/CDN down) the glyph above stays visible.
            Image {
                id: pieceImg
                anchors.centerIn: parent
                visible: !sq.isDragSource && sq.piece !== "" && status === Image.Ready
                width: parent.width * 0.86; height: width
                source: sq.piece !== "" ? window.chessPieceImg(sq.piece) : ""
                sourceSize.width: 128; sourceSize.height: 128
                fillMode: Image.PreserveAspectFit
                asynchronous: true; cache: true; smooth: true
            }
        }
    }


    // ── Chess analysis + chat models ──
    ListModel { id: chessAnalysisModel }   // per-ply {ply,san,evalCp,mate,judgeName,judgeComment,best,variation}
    ListModel { id: chessChatModel }       // {user, text, room}
    Timer { id: chessActionFlashTimer; interval: 4000; repeat: false; onTriggered: window.chessActionFlash = "" }

    // ── Fancy interactive board ──
    // A complete board: framed grid + a single MouseArea that handles
    // click-to-move, drag-to-move (left button) and planning arrows
    // (right button drag). Used by both the puzzle and the live game.
    Component {
        id: chessBoardComponent
        Item {
            id: boardRoot
            // Outer frame / bevel
            Rectangle {
                anchors.fill: parent
                radius: window.s(10)
                color: Qt.rgba(0.16, 0.13, 0.11, 1.0)     // dark wood frame
                border.color: Qt.rgba(0.30, 0.24, 0.20, 1.0); border.width: 1
                // Inner play area
                Item {
                    id: boardInner
                    anchors.fill: parent
                    anchors.margins: window.s(7)
                    property real cell: width / 8

                    Grid {
                        id: boardGrid
                        anchors.fill: parent
                        columns: 8; rows: 8
                        Repeater { model: 64; delegate: chessSquareDelegate }
                    }

                    // ── Planning arrows overlay ──
                    Canvas {
                        id: arrowCanvas
                        anchors.fill: parent
                        property var arrows: window.chessArrows
                        property int dragFrom: window.chessArrowFrom
                        property real liveX: window.chessDragX
                        property real liveY: window.chessDragY
                        property bool liveArrow: window.chessArrowFrom >= 0
                        onArrowsChanged: requestPaint()
                        onLiveXChanged: if (liveArrow) requestPaint()
                        onLiveYChanged: if (liveArrow) requestPaint()
                        onLiveArrowChanged: requestPaint()
                        Connections { target: window; function onChessIsWhiteChanged() { arrowCanvas.requestPaint(); } }

                        function drawArrow(ctx, x1, y1, x2, y2) {
                            let headLen = boardInner.cell * 0.32;
                            let ang = Math.atan2(y2 - y1, x2 - x1);
                            // Shorten the line so the head sits nicely.
                            let endX = x2 - Math.cos(ang) * headLen * 0.8;
                            let endY = y2 - Math.sin(ang) * headLen * 0.8;
                            ctx.lineWidth = boardInner.cell * 0.16;
                            ctx.lineCap = "round";
                            ctx.lineJoin = "round";
                            ctx.beginPath();
                            ctx.moveTo(x1, y1); ctx.lineTo(endX, endY); ctx.stroke();
                            // Arrowhead
                            ctx.beginPath();
                            ctx.moveTo(x2, y2);
                            ctx.lineTo(x2 - headLen * Math.cos(ang - Math.PI / 6), y2 - headLen * Math.sin(ang - Math.PI / 6));
                            ctx.lineTo(x2 - headLen * Math.cos(ang + Math.PI / 6), y2 - headLen * Math.sin(ang + Math.PI / 6));
                            ctx.closePath(); ctx.fill();
                        }
                        // L-shaped (knight) arrow: travels the longer leg first,
                        // then turns 90° into the shorter leg — like chess.com.
                        function drawKnightArrow(ctx, x1, y1, x2, y2) {
                            let dx = x2 - x1, dy = y2 - y1;
                            // Corner: go the long axis first, then turn.
                            let cornerX, cornerY;
                            if (Math.abs(dx) > Math.abs(dy)) { cornerX = x2; cornerY = y1; }  // horizontal then vertical
                            else { cornerX = x1; cornerY = y2; }                              // vertical then horizontal
                            let headLen = boardInner.cell * 0.32;
                            // Direction of the final (post-corner) segment for the head.
                            let ang = Math.atan2(y2 - cornerY, x2 - cornerX);
                            let endX = x2 - Math.cos(ang) * headLen * 0.8;
                            let endY = y2 - Math.sin(ang) * headLen * 0.8;
                            ctx.lineWidth = boardInner.cell * 0.16;
                            ctx.lineCap = "round";
                            ctx.lineJoin = "round";
                            ctx.beginPath();
                            ctx.moveTo(x1, y1);
                            ctx.lineTo(cornerX, cornerY);
                            ctx.lineTo(endX, endY);
                            ctx.stroke();
                            // Arrowhead on the final segment.
                            ctx.beginPath();
                            ctx.moveTo(x2, y2);
                            ctx.lineTo(x2 - headLen * Math.cos(ang - Math.PI / 6), y2 - headLen * Math.sin(ang - Math.PI / 6));
                            ctx.lineTo(x2 - headLen * Math.cos(ang + Math.PI / 6), y2 - headLen * Math.sin(ang + Math.PI / 6));
                            ctx.closePath(); ctx.fill();
                        }
                        // True if the from→to delta is a knight's L move.
                        function isKnightMove(fromIdx, toIdx) {
                            let fr = Math.floor(fromIdx / 8), fc = fromIdx % 8;
                            let tr = Math.floor(toIdx / 8), tc = toIdx % 8;
                            let dr = Math.abs(tr - fr), dc = Math.abs(tc - fc);
                            return (dr === 1 && dc === 2) || (dr === 2 && dc === 1);
                        }
                        onPaint: {
                            let ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            ctx.strokeStyle = Qt.rgba(0.95, 0.65, 0.15, 0.85);   // amber
                            ctx.fillStyle = Qt.rgba(0.95, 0.65, 0.15, 0.85);
                            for (let i = 0; i < arrows.length; i++) {
                                // Your arrows = amber; opponent-piece arrows = sky blue.
                                if (arrows[i].mine === false) {
                                    ctx.strokeStyle = Qt.rgba(0.30, 0.65, 0.95, 0.85);
                                    ctx.fillStyle = Qt.rgba(0.30, 0.65, 0.95, 0.85);
                                } else {
                                    ctx.strokeStyle = Qt.rgba(0.95, 0.65, 0.15, 0.85);
                                    ctx.fillStyle = Qt.rgba(0.95, 0.65, 0.15, 0.85);
                                }
                                let p1 = window.chessSquareCenter(arrows[i].from, width);
                                let p2 = window.chessSquareCenter(arrows[i].to, width);
                                // Knight moves get an L-shaped (bent) arrow; the piece
                                // on the from-square decides, with a geometry fallback.
                                let piece = window.chessBoard[arrows[i].from] || "";
                                let knight = (piece.toUpperCase() === "N") || isKnightMove(arrows[i].from, arrows[i].to);
                                if (knight) drawKnightArrow(ctx, p1.x, p1.y, p2.x, p2.y);
                                else drawArrow(ctx, p1.x, p1.y, p2.x, p2.y);
                            }
                            // Live (in-progress) arrow while right-dragging
                            if (liveArrow) {
                                let pf = window.chessSquareCenter(dragFrom, width);
                                ctx.strokeStyle = Qt.rgba(0.95, 0.65, 0.15, 0.55);
                                ctx.fillStyle = Qt.rgba(0.95, 0.65, 0.15, 0.55);
                                let piece2 = window.chessBoard[dragFrom] || "";
                                if (piece2.toUpperCase() === "N") drawKnightArrow(ctx, pf.x, pf.y, liveX, liveY);
                                else drawArrow(ctx, pf.x, pf.y, liveX, liveY);
                            }
                        }
                    }

                    // ── Floating dragged piece ──
                    Text {
                        id: dragPiece
                        visible: window.chessDragging && window.chessDragFrom >= 0
                        text: window.chessDragging ? window.chessPieceChar(window.chessBoard[window.chessDragFrom] || "") : ""
                        font.pixelSize: boardInner.cell * 0.9
                        color: {
                            let p = window.chessBoard[window.chessDragFrom] || "";
                            return (p >= "A" && p <= "Z") ? "#fafafa" : "#15151f";
                        }
                        style: Text.Outline
                        styleColor: {
                            let p = window.chessBoard[window.chessDragFrom] || "";
                            return (p >= "A" && p <= "Z") ? "#444444" : "#bbbbbb";
                        }
                        x: window.chessDragX - width / 2
                        y: window.chessDragY - height / 2
                        z: 100
                    }

                    // ── Unified interaction layer ──
                    MouseArea {
                        id: boardMouse
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        hoverEnabled: true
                        property int pressIdxDisplay: -1     // display index where press started
                        property int pressRealIdx: -1
                        property bool leftDragging: false

                        function idxAt(px, py) {
                            let c = Math.floor(px / boardInner.cell);
                            let r = Math.floor(py / boardInner.cell);
                            if (c < 0 || c > 7 || r < 0 || r > 7) return -1;
                            return r * 8 + c;
                        }
                        function realAt(px, py) {
                            let disp = idxAt(px, py);
                            if (disp < 0) return -1;
                            return window.chessIsWhite ? disp : (63 - disp);
                        }

                        onPressed: function(mouse) {
                            let real = realAt(mouse.x, mouse.y);
                            if (real < 0) return;
                            if (mouse.button === Qt.RightButton) {
                                // Begin a planning arrow.
                                window.chessArrowFrom = real;
                                window.chessDragX = mouse.x; window.chessDragY = mouse.y;
                                return;
                            }
                            // Left button — clear arrows (like lichess) and maybe start a drag.
                            if (window.chessArrows.length > 0) window.chessClearArrows();
                            pressRealIdx = real;
                            pressIdxDisplay = idxAt(mouse.x, mouse.y);
                            if (window.chessCanPickUp(real)) {
                                window.chessDragFrom = real;
                                window.chessDragX = mouse.x; window.chessDragY = mouse.y;
                                window.chessDragging = true;
                                window.chessSelected = real;   // show source highlight
                                window.chessBoardChanged();
                            }
                        }
                        onPositionChanged: function(mouse) {
                            window.chessDragX = mouse.x; window.chessDragY = mouse.y;
                            if (window.chessDragging) leftDragging = true;
                        }
                        onReleased: function(mouse) {
                            if (mouse.button === Qt.RightButton) {
                                let real = realAt(mouse.x, mouse.y);
                                if (window.chessArrowFrom >= 0 && real >= 0) {
                                    if (real === window.chessArrowFrom) {
                                        // tap with no drag — ignore (could highlight square later)
                                    } else {
                                        window.chessToggleArrow(window.chessArrowFrom, real);
                                    }
                                }
                                window.chessArrowFrom = -1;
                                return;
                            }
                            // Left release
                            if (window.chessDragging) {
                                let dropReal = realAt(mouse.x, mouse.y);
                                window.chessDragging = false;
                                let from = window.chessDragFrom;
                                window.chessDragFrom = -1;
                                if (leftDragging && dropReal >= 0 && dropReal !== from) {
                                    window.chessDropMove(from, dropReal);
                                } else if (!leftDragging) {
                                    // Treated as a click — fall through to click handler.
                                    if (window.chessStatus === "playing") window.chessSquareClicked(pressIdxDisplay);
                                    else if (window.chessStatus === "puzzle") window.chessPuzzleSquareClicked(pressIdxDisplay);
                                }
                                leftDragging = false;
                                window.chessBoardChanged();
                            } else {
                                // No piece picked up — plain click (select / move target).
                                let disp = idxAt(mouse.x, mouse.y);
                                if (disp >= 0) {
                                    if (window.chessStatus === "playing") window.chessSquareClicked(disp);
                                    else if (window.chessStatus === "puzzle") window.chessPuzzleSquareClicked(disp);
                                }
                            }
                        }
                        onCanceled: {
                            window.chessDragging = false; window.chessDragFrom = -1;
                            window.chessArrowFrom = -1; leftDragging = false;
                        }
                    }
                }
            }
        }
    }

    Process {
        id: chessCreateProc; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector { onStreamFinished: {
            if (this.text.trim() === "idle") return;
            window.chessDebugCreate = this.text.trim().substring(0, 400);
            // Lichess /api/challenge/ai returns a single JSON object: {"id":"xxx",...}
            // Lichess /api/board/seek returns NDJSON (possibly multiple lines).
            // We try each non-empty line until we find a game ID.
            let lines = this.text.trim().split("\n");
            let gameId = "";
            let myColorHint = "";   // "white"/"black" from the create response, if present
            for (let i = lines.length - 1; i >= 0 && !gameId; i--) {
                let line = lines[i].trim();
                if (!line) continue;
                try {
                    let data = JSON.parse(line);
                    // /api/challenge/ai → data.id (and data.color = my color)
                    if (data.id) { gameId = data.id; if (data.color) myColorHint = data.color; }
                    // /api/board/seek event stream → data.game.gameId
                    else if (data.game && data.game.gameId) { gameId = data.game.gameId; }
                    // Some responses nest under gameId directly
                    else if (data.gameId) { gameId = data.gameId; }
                } catch(e) { continue; }
            }
            if (gameId) {
                window.chessAiCreating = false;
                window.chessGameId = gameId;
                window.chessStatus = "playing";   // enter the board
                window.chessInitBoard();
                window.chessHalfmoveCount = 0;
                window.chessSelected = -1; window.chessFromIdx = -1; window.chessToIdx = -1;
                // Color: use the response hint if present, else assume white for
                // now. The very next poll reads the authoritative gameFull and
                // corrects color (by matching our username) + turn, so a random
                // assignment that made us black is fixed within ~1s.
                if (myColorHint === "black") window.chessIsWhite = false;
                else window.chessIsWhite = true;
                window.chessMyTurn = window.chessIsWhite;
                window.saveChessState();
                // Start the live poller; the first poll reads the authoritative
                // gameFull and corrects color/turn within ~1s.
                window.chessPollSoon();
            } else {
                // No game id — surface WHY instead of silently bouncing. Look for
                // an error field in any line; Lichess returns {"error":"..."} for
                // bad scope, rate limits, etc.
                let errMsg = "";
                for (let i = 0; i < lines.length && !errMsg; i++) {
                    let line = lines[i].trim();
                    if (!line) continue;
                    try {
                        let d = JSON.parse(line);
                        if (d.error) {
                            if (typeof d.error === "string") errMsg = d.error;
                            else {
                                // Nested validation object, e.g. {"time":["Invalid"]}.
                                // Flatten to a readable string.
                                let parts = [];
                                for (let k in d.error) {
                                    let v = d.error[k];
                                    parts.push(k + ": " + (Array.isArray(v) ? v.join(", ") : v));
                                }
                                errMsg = parts.length ? parts.join("; ") : JSON.stringify(d.error);
                            }
                        }
                    } catch(e) {
                        // Non-JSON (e.g. an HTML login wall) — show a hint.
                        if (line.indexOf("<") === 0 || line.toLowerCase().indexOf("html") >= 0)
                            errMsg = "Unexpected HTML response (token may be invalid)";
                    }
                }
                if (errMsg === "") {
                    if (!window.chessHasBoardPlay) errMsg = "Token missing 'board:play' scope — regenerate it (tap the warning on the menu).";
                    else if (!window.chessHasChallengeWrite) errMsg = "Token missing 'challenge:write' scope — regenerate it.";
                    else errMsg = "Lichess returned no game. Check token scopes (board:play + challenge:write).";
                }
                window.chessCreateError = errMsg;
                // If we were creating an AI game, stay on the setup page so the
                // error shows there; otherwise (human seek) fall back to menu.
                if (window.chessAiCreating) { window.chessStatus = "aisetup"; }
                else { window.chessStatus = "menu"; }
                window.chessAiCreating = false;
                chessCreateErrorTimer.restart();
            }
        }}
    }
    // Holds the most recent game-creation error so the user sees why a game
    // didn't start, instead of a silent bounce back to the menu.
    property string chessCreateError: ""
    Timer { id: chessCreateErrorTimer; interval: 8000; repeat: false; onTriggered: window.chessCreateError = "" }
    Process { id: chessMoveProc; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector { onStreamFinished: {
            let t = this.text.trim();
            if (!t || t === "idle") return;
            try {
                let data = JSON.parse(t);
                if (data.ok === true) return;   // success — the gameState event will update the board
                if (data.error) {
                    window.chessMoveError = String(data.error);
                    chessMoveErrorTimer.restart();
                    return;
                }
                // Unrecognised shape — show it raw, capped
                window.chessMoveError = t.length > 80 ? t.substring(0, 80) + "…" : t;
                chessMoveErrorTimer.restart();
            } catch(e) {
                // Empty / non-JSON response → curl failed (no network, DNS, etc.)
                window.chessMoveError = "Move failed (no response from Lichess)";
                chessMoveErrorTimer.restart();
            }
        }}
    }

    Component.onCompleted: { window.chessInitBoard(); window.loadCache("chat"); window.fetchGreeting(); }

    // Greeting flow:
    //   1. Main.qml prefetches the greeting in the background at shell start
    //      and every hour, writing it to ~/.cache/qs_ai_state/greeting.txt.
    //   2. The popup just reads that file on load — instant display, no
    //      waiting on Hermes mid-open.
    //   3. If the cache is somehow empty (first boot, Hermes down, etc.), we
    //      fall back to a live one-shot fetch via the bridge.
    function fetchGreeting() {
        greetingCacheReader.command = ["bash", "-c",
            "cat \"$HOME/.cache/qs_ai_state/greeting.txt\" 2>/dev/null"
        ];
        greetingCacheReader.running = false;
        greetingCacheReader.running = true;
    }
    Process {
        id: greetingCacheReader
        command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                let g = (this.text || "").trim();
                if (g.length > 0 && g.length < 200) {
                    window.greetingText = g;
                    window.greetingFetched = true;
                } else {
                    // Cache miss — fire a live one-shot to populate immediately
                    // (the prefetcher will also fill the file for next time).
                    greetingFetcherProc.command = ["bash", "-c",
                        "DAY=$(date +%Y%m%d) && RND=$(od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -d ' ' || echo $RANDOM) && " +
                        "printf '%s' \"Give me a brief, friendly greeting (one short sentence, max 12 words). " +
                        "Vary it from previous greetings. Seed: $RND. No emojis.\" | " +
                        "HERMES_SESSION_OVERRIDE=\"greeting-$DAY\" " +
                        "~/.config/hypr/scripts/hermes_bridge.sh 2>/dev/null"
                    ];
                    greetingFetcherProc.running = false;
                    greetingFetcherProc.running = true;
                }
            }
        }
    }
    Process {
        id: greetingFetcherProc
        command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                let raw = this.text.trim();
                if (raw === "" || raw === "idle") { window.greetingFetched = true; return; }
                try {
                    let resp = JSON.parse(raw);
                    let g = (resp.content || "").trim();
                    g = g.replace(/^["'\u201c\u2018]+|["'\u201d\u2019]+$/g, "");
                    if (g.length > 0 && g.length < 200) {
                        window.greetingText = g;
                        // Cache it so next open is instant.
                        greetingCacheWriter.command = ["bash", "-c",
                            "mkdir -p \"$HOME/.cache/qs_ai_state\" && " +
                            "printf '%s' " + JSON.stringify(g) + " > \"$HOME/.cache/qs_ai_state/greeting.txt\""
                        ];
                        greetingCacheWriter.running = false;
                        greetingCacheWriter.running = true;
                    }
                } catch(e) {
                    if (raw.length < 200 && raw.indexOf("\n") < 0) window.greetingText = raw;
                }
                window.greetingFetched = true;
            }
        }
    }
    Process { id: greetingCacheWriter; command: ["bash", "-c", "echo idle"] }

    // ── Auto-save notes on any transition that could lose the buffer ──
    // Called from: popup close, "Back to menu" button, every module-switch
    // click in the side nav. Synchronous-from-the-user's-perspective: the
    // autosave Timer is cancelled and the bytes are flushed to disk
    // immediately so we never have a pending-write window during a transition.
    //
    // Cheap to call when there's nothing to save (early-returns), so it's
    // safe to fire on every nav click without thinking about it.
    // Rename the current note's file on disk to match a new title. Sanitizes the
    // name, keeps it in the same folder, preserves the .md extension, flushes the
    // buffer first, then moves the file and re-points currentNoteFilepath.
    function renameCurrentNote(newTitle) {
        let t = (newTitle || "").trim();
        if (t === "" || window.currentNoteFilepath === "") return;
        if (t === window.selectedNoteTitle) return;   // unchanged
        // Disallow path separators / leading dots; collapse anything odd.
        let safe = t.replace(/[\/\\]/g, "-").replace(/^\.+/, "").trim();
        if (safe === "") return;
        // Save current edits to the OLD path first so nothing is lost.
        window.flushNoteNow();
        let oldPath = window.currentNoteFilepath;
        let dir = oldPath.substring(0, oldPath.lastIndexOf("/"));
        let newPath = dir + "/" + safe + ".md";
        if (newPath === oldPath) { window.selectedNoteTitle = safe; return; }
        noteRenamer.command = ["bash", "-c",
            "OLD='" + oldPath.replace(/'/g, "'\\''") + "'; NEW='" + newPath.replace(/'/g, "'\\''") + "'; " +
            "if [ -e \"$NEW\" ]; then echo EXISTS; else mv \"$OLD\" \"$NEW\" && echo OK; fi"
        ];
        noteRenamer.running = false; noteRenamer.running = true;
        // Optimistically update state; the process result corrects on conflict.
        window._pendingRenamePath = newPath; window._pendingRenameTitle = safe;
    }
    property string _pendingRenamePath: ""
    property string _pendingRenameTitle: ""
    Process { id: noteRenamer; command: ["bash", "-c", "true"]
        stdout: StdioCollector { onStreamFinished: {
            let r = (this.text || "").trim();
            if (r === "OK" && window._pendingRenamePath !== "") {
                window.currentNoteFilepath = window._pendingRenamePath;
                window.selectedNoteTitle = window._pendingRenameTitle;
            }
            // On EXISTS we leave the old path/title in place (no clobber).
            window._pendingRenamePath = ""; window._pendingRenameTitle = "";
        }}
    }
    function flushNoteNow() {
        if (window.notesSubMode !== "edit") return;
        if (window.currentNoteFilepath === "") return;
        if (noteArea.text === "") return;   // never overwrite a file with an empty buffer
        if (window.obsidianVault !== "" && window.currentNoteFilepath.indexOf(window.obsidianVault) !== 0) {
            console.warn("Refusing to save note outside vault:", window.currentNoteFilepath);
            return;
        }
        autoSaveTimer.stop();
        let b64 = Qt.btoa(noteArea.text);
        noteSaver.command = ["bash", "-c",
            "echo " + b64 + " | base64 -d > '" + window.currentNoteFilepath.replace(/'/g, "'\\''") + "'"
        ];
        noteSaver.running = false;
        noteSaver.running = true;
        window.noteAutoSaved = true;
        autoSavedResetTimer.restart();
    }
    onVisibleChanged: {
        if (!visible) {
            window.flushNoteNow();
            // Note: we intentionally do NOT clear the PDF scratch here. The
            // tmpfs cache persists for the login session so reopening the
            // popup is instant (no 3-second re-download of a multi-MB PDF).
            // It gets evicted only when:
            //   (a) the user switches to a different series (kavitaOpenSeries
            //       does its own per-book reset), or
            //   (b) the system reboots (tmpfs disappears on logout/restart).
        }
    }

    // Wipe any tmpfs scratch PDFs and reset the PdfDocument source. Kept as a
    // function for explicit "clean up everything" callers (e.g. configurable
    // privacy mode in the future). Not called automatically on popup close
    // anymore — that was forcing a 3-second re-download every reopen.
    function kavitaClearPdfScratch() {
        window.kavitaPdfPath = "";
        window.kavitaPdfChapterId = 0;
        kavitaPdfCleanupProc.command = ["bash", "-c",
            "SDIR=\"${XDG_RUNTIME_DIR:-/tmp}/quickshell-kavita\"; " +
            "[ -d \"$SDIR\" ] && find \"$SDIR\" -maxdepth 1 -name 'chapter_*.pdf' -delete 2>/dev/null; " +
            "true"
        ];
        kavitaPdfCleanupProc.running = false;
        kavitaPdfCleanupProc.running = true;
    }
    Process { id: kavitaPdfCleanupProc; command: ["bash", "-c", "echo idle"] }

    // Verifies the cached PDF still exists at the path we restored from disk.
    // tmpfs evaporates on reboot, so the path could point at nothing — in
    // which case we clear our state so kavitaLoadPage will re-download.
    Process {
        id: kavitaPdfCacheCheck
        command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() !== "ok") {
                    window.kavitaPdfPath = "";
                    window.kavitaPdfChapterId = 0;
                }
            }
        }
    }

    // ── Kavita authentication ──
    function kavitaAuth() {
        if (!window.kavitaUrl || !window.kavitaApiKey) return;
        kavitaAuthProc.command = ["bash", "-c", "curl -s -X POST '" + window.kavitaUrl + "/api/Plugin/authenticate?apiKey=" + window.kavitaApiKey + "&pluginName=quickshell-learn' -H 'Content-Type: application/json' 2>/dev/null"];
        kavitaAuthProc.running = false; kavitaAuthProc.running = true;
    }
    Process { id: kavitaAuthProc; command: ["bash", "-c", "echo idle"]; stdout: StdioCollector { onStreamFinished: { if (this.text.trim() === "idle") return; try { let data = JSON.parse(this.text.trim()); if (data.token) { window.kavitaToken = data.token; window.kavitaConnected = true; window.kavitaFetchSeries(); } } catch(e) { window.kavitaConnected = false; } } } }

    function kavitaFetchSeries() {
        if (!window.kavitaToken) return; window.kavitaLoading = true;
        kavitaSeriesProc.command = ["bash", "-c", "curl -s -X POST '" + window.kavitaUrl + "/api/Series/all-v2' -H 'Authorization: Bearer " + window.kavitaToken + "' -H 'Content-Type: application/json' -d '{\"statements\":[],\"combination\":1,\"sortOptions\":{\"sortField\":1,\"isAscending\":true},\"limitTo\":0}' 2>/dev/null"];
        kavitaSeriesProc.running = false; kavitaSeriesProc.running = true;
    }
    Process { id: kavitaSeriesProc; command: ["bash", "-c", "echo idle"]; stdout: StdioCollector { onStreamFinished: {
        window.kavitaLoading = false; if (this.text.trim() === "idle") return;
        try { let data = JSON.parse(this.text.trim()); kavitaSeries.clear(); kavitaAllSeries.clear(); let arr = data || [];
            for (let i = 0; i < arr.length; i++) { let entry = { seriesId: arr[i].id || 0, name: arr[i].name || "Unknown", libraryName: arr[i].libraryName || "", libraryId: arr[i].libraryId || 0, pages: arr[i].pages || 0, pagesRead: arr[i].pagesRead || 0, format: arr[i].format || 0 };
                kavitaAllSeries.append(entry); if ((arr[i].libraryName || "").toLowerCase() === "textbooks") kavitaSeries.append(entry); } window.kavitaRebuildLibraryCats(); window.kavitaFetchOnDeck(); } catch(e) {}
    }}}
    function kavitaFetchOnDeck() {
        if (!window.kavitaToken) return;
        kavitaOnDeckProc.command = ["bash", "-c", "curl -s '" + window.kavitaUrl + "/api/Series/on-deck?pageNumber=0&pageSize=20' -H 'Authorization: Bearer " + window.kavitaToken + "' 2>/dev/null"];
        kavitaOnDeckProc.running = false; kavitaOnDeckProc.running = true;
    }
    Process { id: kavitaOnDeckProc; command: ["bash", "-c", "echo idle"]; stdout: StdioCollector { onStreamFinished: { if (this.text.trim() === "idle") return; try { let data = JSON.parse(this.text.trim()); kavitaOnDeck.clear(); let arr = data || []; for (let i = 0; i < arr.length; i++) kavitaOnDeck.append({ seriesId: arr[i].id || 0, name: arr[i].name || "Unknown", libraryName: arr[i].libraryName || "", libraryId: arr[i].libraryId || 0, pages: arr[i].pages || 0, pagesRead: arr[i].pagesRead || 0, format: arr[i].format || 0 }); } catch(e) {} } } }
    function kavitaOpenSeries(sid, lid, name, fmt) {
        // If we're switching to a DIFFERENT book, reset every piece of
        // per-book reader state so the new book opens clean instead of
        // inheriting the previous book's page/chapter/cached-pdf.
        let switching = (window.kavitaLastSeriesId !== sid);

        window.kavitaLastSeriesId = sid;
        window.kavitaLastLibraryId = lid;
        window.kavitaLastName = name || "";
        window.kavitaLastFormat = fmt || 0;
        window.kavitaReadFormat = fmt || 0;
        window.saveKavitaLast(sid, lid, name || "");
        window.kavitaReadTitle = name || "";
        window.kavitaReadBookTitle = "";
        window.kavitaTitleLocked = false;   // direct series open uses series name
        window.kavitaReadSeriesId = sid;
        window.kavitaReadLoading = true;
        window.kavitaReadContent = "";

        if (switching) {
            // Hard-reset reader state — these were sticky across books and
            // would cause the new book to render as if it were the old one.
            window.kavitaReadChapterId = 0;
            window.kavitaReadVolumeId = 0;
            window.kavitaReadPage = 0;
            window.kavitaReadTotalPages = 0;
            // Evict the previous book's PDF so PdfDocument re-downloads
            // for the new series (kavitaLoadPage will refill on the new
            // chapter; we also wipe the tmpfs scratch file).
            window.kavitaPdfPath = "";
            window.kavitaPdfChapterId = 0;
            kavitaPdfSwitchClean.command = ["bash", "-c",
                "SDIR=\"${XDG_RUNTIME_DIR:-/tmp}/quickshell-kavita\"; " +
                "[ -d \"$SDIR\" ] && find \"$SDIR\" -maxdepth 1 -name 'chapter_*.pdf' -delete 2>/dev/null; " +
                "true"
            ];
            kavitaPdfSwitchClean.running = false;
            kavitaPdfSwitchClean.running = true;
            // Clear chapter list so the dropdown reflects the new series.
            kavitaChapters.clear();
        }

        window.kavitaSubMode = "reading";
        // Fetch continue point — Kavita tells us where the user left off
        kavitaContinueProc.command = ["bash", "-c",
            "curl -s -X POST '" + window.kavitaUrl + "/api/Reader/continue-point?seriesId=" + sid + "' " +
            "-H 'Authorization: Bearer " + window.kavitaToken + "' 2>/dev/null"
        ];
        kavitaContinueProc.running = false;
        kavitaContinueProc.running = true;
    }
    Process { id: kavitaPdfSwitchClean; command: ["bash", "-c", "echo idle"] }
    Process {
        id: kavitaContinueProc; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector { onStreamFinished: {
            if (this.text.trim() === "idle") return;
            try {
                let cp = JSON.parse(this.text.trim());
                window.kavitaReadChapterId = cp.chapterId || 0;
                window.kavitaReadVolumeId = cp.volumeId || 0;
                // Open on the cover/title page (0) for a nice intro, but remember
                // where the user actually left off. The first time they turn the
                // page off the cover, we jump straight to their saved spot so
                // they continue their book — with a title page to start.
                let savedPage = cp.pageNum || 0;
                if (savedPage > 0) {
                    window.kavitaResumePage = savedPage;   // pending jump target
                    window.kavitaOnCoverPage = true;
                    window.kavitaReadPage = 0;             // show the cover first
                } else {
                    window.kavitaResumePage = -1;
                    window.kavitaOnCoverPage = false;
                    window.kavitaReadPage = 0;
                }
                if (window.kavitaReadChapterId > 0) {
                    window.kavitaLoadChapterInfo();
                } else {
                    window.kavitaFetchChapters();
                }
            } catch(e) { window.kavitaFetchChapters(); }
        }}
    }

    // Fetch all chapters for the series (for chapter navigation)
    // ── Browse a series' individual books/chapters (library drill-in) ──
    // Instead of opening a series directly on its first chapter, this fetches
    // the chapter list and shows it so the user can pick a specific book.
    ListModel { id: kavitaBrowseChapters }   // {chapterId, volumeId, title, pages, pagesRead}
    function kavitaBrowseSeries(sid, lid, name, fmt) {
        window.kavitaBrowseSeriesId = sid;
        window.kavitaBrowseSeriesName = name || "";
        window.kavitaBrowseSeriesLib = lid;
        window.kavitaBrowseSeriesFmt = fmt || 0;
        window.kavitaBrowseLoading = true;
        kavitaBrowseChapters.clear();
        window.kavitaSubMode = "serieschapters";
        kavitaBrowseProc.command = ["bash", "-c",
            "curl -s '" + window.kavitaUrl + "/api/Series/series-detail?seriesId=" + sid + "' " +
            "-H 'Authorization: Bearer " + window.kavitaToken + "' 2>/dev/null"
        ];
        kavitaBrowseProc.running = false;
        kavitaBrowseProc.running = true;
    }
    Process {
        id: kavitaBrowseProc; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector { onStreamFinished: {
            window.kavitaBrowseLoading = false;
            if (this.text.trim() === "idle") return;
            try {
                let detail = JSON.parse(this.text.trim());
                kavitaBrowseChapters.clear();
                // Collect chapters with their owning volume's name when available,
                // since the volume name (e.g. "Volume 1", "Vol. 3") is usually the
                // best distinguisher between books in a series.
                let raw = [];
                if (detail.storylineChapters && detail.storylineChapters.length > 0) {
                    raw = detail.storylineChapters;
                } else {
                    let vols = detail.volumes || [];
                    for (let v = 0; v < vols.length; v++) {
                        let vol = vols[v];
                        let vchs = vol.chapters || [];
                        for (let c = 0; c < vchs.length; c++)
                            raw.push(Object.assign({}, vchs[c], {
                                volumeId: vol.id,
                                _volName: vol.name || "",
                                _volNumber: vol.number
                            }));
                    }
                    let loose = detail.chapters || [];
                    for (let i = 0; i < loose.length; i++) raw.push(loose[i]);
                    let specials = detail.specials || [];
                    for (let i = 0; i < specials.length; i++) raw.push(specials[i]);
                }
                let isSentinel = function(s){ s = (s || "").toString().trim(); return !s || s === "0" || s === "-100000"; };
                let fileBase = function(ch){
                    // Last resort: derive a name from the file path (basename, no ext).
                    if (ch.files && ch.files.length > 0 && ch.files[0].filePath) {
                        let p = ch.files[0].filePath;
                        let base = p.split("/").pop().split("\\").pop();
                        return base.replace(/\.[A-Za-z0-9]+$/, "");
                    }
                    return "";
                };
                for (let i = 0; i < raw.length; i++) {
                    let ch = raw[i];
                    if (!ch || !ch.id) continue;
                    let tn  = (ch.titleName || "").trim();
                    let vt  = (ch.volumeTitle || "").trim();
                    let vn  = (ch._volName || "").trim();
                    let rng = (ch.range || "").trim();
                    let label = "";
                    // Priority order, most-specific first:
                    if (!isSentinel(tn) && tn !== window.kavitaBrowseSeriesName) {
                        label = tn;                                   // explicit custom title
                    } else if (!isSentinel(vn) && vn !== window.kavitaBrowseSeriesName) {
                        label = vn;                                   // volume name ("Volume 1")
                    } else if (!isSentinel(vt) && vt !== window.kavitaBrowseSeriesName) {
                        label = vt;                                   // volume title
                    } else if (ch._volNumber !== undefined && ch._volNumber !== null && !isSentinel(ch._volNumber)) {
                        label = "Volume " + ch._volNumber;            // numbered volume
                    } else if (!isSentinel(rng)) {
                        label = ((ch.volumeId && ch.volumeId > 0) ? "Volume " : "Chapter ") + rng;
                    } else if (ch.number !== undefined && ch.number !== null && !isSentinel(ch.number)) {
                        label = "Chapter " + ch.number;
                    } else {
                        let fb = fileBase(ch);
                        label = fb !== "" ? fb : ("Book " + (i + 1));  // filename, else positional
                    }
                    kavitaBrowseChapters.append({
                        chapterId: ch.id, volumeId: ch.volumeId || 0,
                        title: label, pages: ch.pages || 0, pagesRead: ch.pagesRead || 0
                    });
                }
            } catch(e) { /* leave empty */ }
        }}
    }
    // Open a specific chapter the user picked from the browse list.
    function kavitaOpenChapter(chapterId, volumeId, pagesRead, pages, bookTitle) {
        // Audio series: tapping a chapter PLAYS it through the persistent
        // player (Main.qml) rather than opening the text reader. Resume from the
        // saved position is handled by audioPlaySeries' resolver path; here we
        // already have the chapter id, so play it directly.
        if (window.kavitaBrowseSeriesFmt === window.kavitaAudioFormatCode) {
            window.kavitaReadChapterId = chapterId;
            window.kavitaAudioChapterId = chapterId;
            window.audioSeriesId = window.kavitaBrowseSeriesId;
            // Resume from the saved position: fetch progress for this chapter,
            // then play from there (audioResumeProc → audioPlayChapter).
            let tok2 = window.kavitaToken;
            audioResumeProc.command = ["bash", "-c",
                "curl -s '" + window.kavitaUrl + "/api/Reader/get-progress?chapterId=" + chapterId + "' " +
                "-H 'Authorization: Bearer " + tok2 + "' 2>/dev/null | " +
                "jq -r '(.audioPositionMs // .positionMs // 0)' 2>/dev/null || echo 0"
            ];
            audioResumeProc._title = bookTitle || window.kavitaBrowseSeriesName;
            audioResumeProc._chapter = chapterId;
            audioResumeProc.running = false; audioResumeProc.running = true;
            return;   // stay on the chapter list; playback runs in the background
        }
        // Set up the reader state for this exact chapter, then go to reading.
        window.kavitaLastSeriesId = window.kavitaBrowseSeriesId;
        window.kavitaLastLibraryId = window.kavitaBrowseSeriesLib;
        window.kavitaLastName = window.kavitaBrowseSeriesName;
        window.kavitaLastFormat = window.kavitaBrowseSeriesFmt;
        window.kavitaReadFormat = window.kavitaBrowseSeriesFmt;
        // Header shows the book's own title. If the book title is just the
        // generic "Book N" or duplicates the series, fall back to the series
        // name so the header still reads sensibly.
        window.kavitaReadBookTitle = bookTitle || "";
        if (bookTitle && bookTitle !== "" && bookTitle !== window.kavitaBrowseSeriesName) {
            window.kavitaReadTitle = bookTitle;
        } else {
            window.kavitaReadTitle = window.kavitaBrowseSeriesName;
        }
        window.kavitaTitleLocked = true;   // don't let chapter-info clobber our choice
        window.kavitaReadSeriesId = window.kavitaBrowseSeriesId;
        window.saveKavitaLast(window.kavitaBrowseSeriesId, window.kavitaBrowseSeriesLib, window.kavitaBrowseSeriesName);
        // Reset reader state for the new book, then point at the chosen chapter.
        window.kavitaReadChapterId = chapterId;
        window.kavitaReadVolumeId = volumeId || 0;
        window.kavitaReadPage = 0;
        window.kavitaReadTotalPages = 0;
        window.kavitaPdfPath = "";
        window.kavitaPdfChapterId = 0;
        // Copy the browsed chapter list into the reader's chapter model so
        // kavitaLoadChapterInfo() does NOT refetch + reset to the first chapter
        // (that was yanking the user back to book 1).
        kavitaChapters.clear();
        for (let i = 0; i < kavitaBrowseChapters.count; i++) {
            let c = kavitaBrowseChapters.get(i);
            kavitaChapters.append({ chapterId: c.chapterId, volumeId: c.volumeId, title: c.title, pages: c.pages, pagesRead: c.pagesRead });
        }
        // Cover-then-resume: if there's prior progress, show cover first.
        if (pagesRead && pagesRead > 0) {
            window.kavitaResumePage = pagesRead;
            window.kavitaOnCoverPage = true;
        } else {
            window.kavitaResumePage = -1;
            window.kavitaOnCoverPage = false;
        }
        window.kavitaReadLoading = true;
        window.kavitaReadContent = "";
        window.kavitaSubMode = "reading";
        window.kavitaLoadChapterInfo();
    }

    function kavitaFetchChapters() {
        kavitaChapterListProc.command = ["bash", "-c",
            "curl -s '" + window.kavitaUrl + "/api/Series/series-detail?seriesId=" + window.kavitaReadSeriesId + "' " +
            "-H 'Authorization: Bearer " + window.kavitaToken + "' 2>/dev/null"
        ];
        kavitaChapterListProc.running = false;
        kavitaChapterListProc.running = true;
    }
    Process {
        id: kavitaChapterListProc; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector { onStreamFinished: {
            if (this.text.trim() === "idle") return;
            try {
                let detail = JSON.parse(this.text.trim());
                kavitaChapters.clear();
                // Kavita's SeriesDetailDto has four chapter-bearing arrays:
                //   storylineChapters — unified reading order (Kavita UI uses this)
                //   volumes[*].chapters — chapters under each volume
                //   chapters — loose chapters not under a volume
                //   specials — one-off extras (PDFs often live here)
                // Prefer storylineChapters when present; else combine the others.
                let raw = [];
                if (detail.storylineChapters && detail.storylineChapters.length > 0) {
                    raw = detail.storylineChapters;
                } else {
                    let vols = detail.volumes || [];
                    for (let v = 0; v < vols.length; v++) {
                        let vchs = vols[v].chapters || [];
                        for (let c = 0; c < vchs.length; c++) {
                            raw.push(Object.assign({}, vchs[c], { volumeId: vols[v].id }));
                        }
                    }
                    let loose = detail.chapters || [];
                    for (let i = 0; i < loose.length; i++) raw.push(loose[i]);
                    let specials = detail.specials || [];
                    for (let i = 0; i < specials.length; i++) raw.push(specials[i]);
                }
                for (let i = 0; i < raw.length; i++) {
                    let ch = raw[i];
                    if (!ch || !ch.id) continue;
                    let label = ch.titleName || ch.title || ch.range || "";
                    if (!label || label === "0" || label === "-100000") {
                        label = "Chapter " + (ch.number || (i + 1));
                    }
                    kavitaChapters.append({
                        chapterId: ch.id, volumeId: ch.volumeId || 0,
                        title: label,
                        pages: ch.pages || 0, pagesRead: ch.pagesRead || 0
                    });
                }
                // If we don't have a chapter yet, use the first one
                if (window.kavitaReadChapterId === 0 && kavitaChapters.count > 0) {
                    let first = kavitaChapters.get(0);
                    window.kavitaReadChapterId = first.chapterId;
                    window.kavitaReadVolumeId = first.volumeId;
                    window.kavitaReadPage = 0;
                }
                if (window.kavitaReadChapterId > 0) window.kavitaLoadChapterInfo();
                else {
                    window.kavitaReadLoading = false;
                    window.kavitaReadContent = "No chapters found.";
                    // Diagnostic — surface what Kavita actually returned.
                    diagKavitaLog.command = ["bash", "-c",
                        "mkdir -p \"$HOME/.cache/quickshell\" && " +
                        "echo \"[$(date '+%F %T')] reader series-detail returned no chapters. Keys: " +
                        Object.keys(detail).join(",") + " sizes: vols=" + (detail.volumes||[]).length +
                        " chs=" + (detail.chapters||[]).length + " specs=" + (detail.specials||[]).length +
                        " story=" + (detail.storylineChapters||[]).length + "\" >> \"$HOME/.cache/quickshell/kavita.log\""
                    ];
                    diagKavitaLog.running = false; diagKavitaLog.running = true;
                }
            } catch(e) {
                window.kavitaReadLoading = false;
                window.kavitaReadContent = "Error loading series.";
                diagKavitaLog.command = ["bash", "-c",
                    "mkdir -p \"$HOME/.cache/quickshell\" && " +
                    "echo \"[$(date '+%F %T')] reader series-detail parse failed: " + String(e).replace(/[\"\\\\]/g, "") + "\" >> \"$HOME/.cache/quickshell/kavita.log\""
                ];
                diagKavitaLog.running = false; diagKavitaLog.running = true;
            }
        }}
    }

    // Get page count for current chapter, then load the page
    function kavitaLoadChapterInfo() {
        kavitaChInfoProc.command = ["bash", "-c",
            "curl -s '" + window.kavitaUrl + "/api/Reader/chapter-info?chapterId=" + window.kavitaReadChapterId + "' " +
            "-H 'Authorization: Bearer " + window.kavitaToken + "' 2>/dev/null"
        ];
        kavitaChInfoProc.running = false;
        kavitaChInfoProc.running = true;
    }
    Process {
        id: kavitaChInfoProc; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector { onStreamFinished: {
            if (this.text.trim() === "idle") return;
            try {
                let info = JSON.parse(this.text.trim());
                window.kavitaReadTotalPages = info.pages || 1;
                // Title: when the user picked a specific book from the browse
                // list we lock the title to that book's name. Otherwise fall
                // back to the series name (info.title is the chapter title,
                // often empty/filename for single-file PDFs).
                if (!window.kavitaTitleLocked) {
                    if (info.seriesName && info.seriesName.trim() !== "" && info.seriesName !== "0") {
                        window.kavitaReadTitle = info.seriesName;
                    } else if (window.kavitaReadTitle === "" && info.title) {
                        window.kavitaReadTitle = info.title;
                    }
                }
                // Clamp page to valid range
                if (window.kavitaReadPage >= window.kavitaReadTotalPages)
                    window.kavitaReadPage = window.kavitaReadTotalPages - 1;
                if (window.kavitaReadPage < 0) window.kavitaReadPage = 0;
                window.kavitaLoadPage(window.kavitaReadPage);
                // Only fetch the chapter list if we truly don't have one yet.
                // (kavitaOpenChapter pre-populates it so we skip this and avoid
                // the refetch resetting us back to the first chapter.)
                if (kavitaChapters.count === 0) window.kavitaFetchChapters();
            } catch(e) { window.kavitaReadLoading = false; window.kavitaReadContent = "Error loading chapter info."; }
        }}
    }

    // Load a specific page — format-aware
    //   0 (image/manga/comics): /api/Reader/image → QML Image (streamed, no cache)
    //   3 (epub):               /api/Book/{id}/book-page → HTML in RichText (streamed, no cache)
    //   4 (pdf):                /api/Reader/pdf → scratch file (RAM-backed tmpfs), rendered by QtQuick.Pdf
    //
    // Important: this module is a *viewer*, not a downloader. PDFs land in
    // $XDG_RUNTIME_DIR (tmpfs — RAM-backed, evaporates on reboot) and are
    // deleted whenever the user switches chapters or closes the popup. We
    // never keep a persistent copy on disk.
    function kavitaLoadPage(page) {
        window.kavitaReadPage = page;

        if (window.kavitaReadFormat === 4) {
            // PDF: if the file's already cached for this chapter, the page
            // change is a pure UI rebind on PdfPageImage.currentFrame — no
            // network, no loading flag (toggling it caused a visible flicker).
            // Only mark "loading" when we genuinely have to download.
            if (window.kavitaPdfChapterId !== window.kavitaReadChapterId || window.kavitaPdfPath === "") {
                window.kavitaReadLoading = true;
                let chapId = window.kavitaReadChapterId;
                // /api/Reader/pdf is in Kavita's "Reader" family which authenticates
                // via the apiKey query parameter, NOT via Bearer token. Sending
                // only `Authorization: Bearer ...` returns HTTP 400
                // ("The apiKey field is required."). This matches how
                // /api/Reader/image works (also apiKey, no Bearer).
                kavitaPdfDownloadProc.command = ["bash", "-c",
                    "mkdir -p \"$HOME/.cache/quickshell\" && " +
                    "echo \"[$(date '+%F %T')] GET /api/Reader/pdf?chapterId=" + chapId + "&apiKey=...\" >> \"$HOME/.cache/quickshell/kavita.log\" && " +
                    "SDIR=\"${XDG_RUNTIME_DIR:-/tmp}/quickshell-kavita\" && mkdir -p \"$SDIR\" && chmod 700 \"$SDIR\" && " +
                    "find \"$SDIR\" -maxdepth 1 -name 'chapter_*.pdf' -delete 2>/dev/null; " +
                    "OUT=\"$SDIR/chapter_" + chapId + ".pdf\" && " +
                    "HTTP=$(curl -s -o \"$OUT\" -w '%{http_code}' " +
                    "'" + window.kavitaUrl + "/api/Reader/pdf?chapterId=" + chapId +
                    "&apiKey=" + window.kavitaApiKey + "' " +
                    "2>>\"$HOME/.cache/quickshell/kavita.log\") && " +
                    "if [ \"$HTTP\" = \"200\" ] && [ -s \"$OUT\" ]; then echo \"$OUT\"; " +
                    "else " +
                    "  BODY=$(head -c 400 \"$OUT\" 2>/dev/null | tr -d '\\n' | tr -d '\\r'); " +
                    "  echo \"[$(date '+%F %T')] PDF download FAILED http=$HTTP bytes=$(stat -c%s \"$OUT\" 2>/dev/null || echo 0) body=$BODY\" >> \"$HOME/.cache/quickshell/kavita.log\"; " +
                    "  rm -f \"$OUT\"; echo ''; fi"
                ];
                kavitaPdfDownloadProc.running = false;
                kavitaPdfDownloadProc.running = true;
            } else {
                window.kavitaReadLoading = false;
                window.kavitaSaveProgress();
            }
        } else if (window.kavitaReadFormat === 3) {
            window.kavitaReadLoading = true;
            // EPUB — fetch HTML
            kavitaPageProc.command = ["bash", "-c",
                "curl -s '" + window.kavitaUrl + "/api/Book/" + window.kavitaReadChapterId + "/book-page?page=" + page + "' " +
                "-H 'Authorization: Bearer " + window.kavitaToken + "' 2>/dev/null"
            ];
            kavitaPageProc.running = false;
            kavitaPageProc.running = true;
        } else {
            // Image-based (manga, comics, archive) — set the image URL directly.
            // Kavita accepts apiKey as query param so QML Image can load it without
            // custom headers. No loading flag toggle here: the QML Image element
            // handles its own progressive load and the previous page stays
            // painted until the next is ready, so flipping pages is smooth.
            window.kavitaReadContent = window.kavitaUrl +
                "/api/Reader/image?chapterId=" + window.kavitaReadChapterId +
                "&page=" + page +
                "&apiKey=" + window.kavitaApiKey;
            window.kavitaSaveProgress();
        }
    }
    // PDF download — runs curl with bearer auth, caches under ~/.cache/quickshell-kavita
    Process {
        id: kavitaPdfDownloadProc; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector { onStreamFinished: {
            let out = this.text.trim();
            if (out === "idle" || out === "") {
                window.kavitaReadLoading = false;
                window.kavitaReadContent = "Failed to download PDF from Kavita.";
                return;
            }
            window.kavitaPdfPath = out;
            window.kavitaPdfChapterId = window.kavitaReadChapterId;
            // PdfDocument.statusChanged will turn off loading; do a safety fallback timer too.
            window.kavitaSaveProgress();
        }}
    }
    Process {
        id: kavitaPageProc; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector { onStreamFinished: {
            window.kavitaReadLoading = false;
            if (this.text.trim() === "idle" || this.text.trim() === "") {
                window.kavitaReadContent = "<p style='color:gray'>Empty page or unsupported format.</p>";
                return;
            }
            let raw = this.text.trim();
            // Check for Kavita error responses (JSON with status/message)
            if (raw.startsWith("{")) {
                try {
                    let err = JSON.parse(raw);
                    if (err.status || err.message || err.title) {
                        window.kavitaReadContent = "<p style='color:gray'>Kavita error: " +
                            (err.message || err.title || "Unknown error") + "</p>";
                        return;
                    }
                } catch(e) { /* not JSON error, treat as content */ }
            }
            window.kavitaReadContent = raw;
            if (typeof readerFlick !== "undefined") readerFlick.contentY = 0;
            window.kavitaSaveProgress();
        }}
    }

    // Save reading progress back to Kavita
    function kavitaSaveProgress() {
        let payload = JSON.stringify({
            volumeId: window.kavitaReadVolumeId,
            chapterId: window.kavitaReadChapterId,
            pageNum: window.kavitaReadPage,
            seriesId: window.kavitaReadSeriesId,
            libraryId: window.kavitaLastLibraryId
        });
        kavitaProgressProc.command = ["bash", "-c",
            "echo '" + payload.replace(/'/g, "'\\''") + "' | curl -s -X POST '" + window.kavitaUrl + "/api/Reader/progress' " +
            "-H 'Authorization: Bearer " + window.kavitaToken + "' " +
            "-H 'Content-Type: application/json' -d @- 2>/dev/null"
        ];
        kavitaProgressProc.running = false;
        kavitaProgressProc.running = true;
        // Also persist locally so reopen finds the cached PDF + last page.
        // Cheap (one JSON write) and keeps the on-disk cache state authoritative.
        if (window.kavitaLastSeriesId > 0) {
            window.saveKavitaLast(window.kavitaLastSeriesId,
                                  window.kavitaLastLibraryId,
                                  window.kavitaLastName);
        }
    }
    Process { id: kavitaProgressProc; command: ["bash", "-c", "echo idle"] }

    // Navigate pages / chapters
    // If we're sitting on the cover page with a pending resume target, the
    // first forward navigation jumps straight to where the user left off
    // (their saved continue-point) instead of advancing to page 1. Returns
    // true if it consumed the navigation (caller should stop).
    function kavitaConsumeResumeJump(dir) {
        if (window.kavitaOnCoverPage && window.kavitaResumePage > 0 && dir > 0) {
            let target = window.kavitaResumePage;
            window.kavitaOnCoverPage = false;
            window.kavitaResumePage = -1;
            if (target < window.kavitaReadTotalPages) {
                window.kavitaLoadPage(target);
            } else {
                window.kavitaLoadPage(1);   // safety: saved page out of range
            }
            return true;
        }
        // Any backward move or a page change also cancels the pending resume
        // (the user chose to navigate manually from the cover).
        if (window.kavitaOnCoverPage) {
            window.kavitaOnCoverPage = false;
            window.kavitaResumePage = -1;
        }
        return false;
    }
    function kavitaNextPage() {
        if (window.kavitaConsumeResumeJump(+1)) return;
        if (window.kavitaReadPage < window.kavitaReadTotalPages - 1) {
            window.kavitaLoadPage(window.kavitaReadPage + 1);
        } else {
            // Try next chapter
            window.kavitaNextChapter();
        }
    }
    function kavitaPrevPage() {
        window.kavitaConsumeResumeJump(-1);
        if (window.kavitaReadPage > 0) {
            window.kavitaLoadPage(window.kavitaReadPage - 1);
        } else {
            window.kavitaPrevChapter();
        }
    }

    // ── Wheel-scroll debouncing ──────────────────────────────────────────
    // Without this, every notch of the scroll wheel fires kavitaLoadPage()
    // immediately. Each load forks a bash+curl process (for image/EPUB) and
    // re-binds Image.source, queuing several in-flight network fetches at
    // once. That's the lag the user feels. We accumulate wheel direction
    // here and commit the net page change after the wheel settles, so
    // ten quick scrolls turn into ONE page jump, not ten queued ones.
    property int kavitaPendingWheel: 0   // positive = forward pages, negative = back
    Timer {
        id: kavitaWheelCommit
        interval: 60
        repeat: false
        onTriggered: {
            let delta = window.kavitaPendingWheel;
            window.kavitaPendingWheel = 0;
            if (delta === 0) return;
            // First forward scroll off the cover jumps to the saved page.
            if (window.kavitaConsumeResumeJump(delta > 0 ? 1 : -1) && delta > 0) return;
            // Multi-page jumps go directly to the target page without firing
            // intermediate page loads — one network call instead of N.
            let target = window.kavitaReadPage + delta;
            if (target < 0) {
                window.kavitaPrevChapter();
            } else if (target >= window.kavitaReadTotalPages) {
                window.kavitaNextChapter();
            } else {
                window.kavitaLoadPage(target);
            }
        }
    }
    function kavitaWheelStep(dir) {
        // dir: +1 for next page, -1 for previous page
        window.kavitaPendingWheel += dir;
        kavitaWheelCommit.restart();
    }
    function kavitaNextChapter() {
        for (let i = 0; i < kavitaChapters.count - 1; i++) {
            if (kavitaChapters.get(i).chapterId === window.kavitaReadChapterId) {
                let next = kavitaChapters.get(i + 1);
                window.kavitaReadChapterId = next.chapterId;
                window.kavitaReadVolumeId = next.volumeId;
                window.kavitaReadPage = 0;
                window.kavitaLoadChapterInfo();
                return;
            }
        }
    }
    function kavitaPrevChapter() {
        for (let i = 1; i < kavitaChapters.count; i++) {
            if (kavitaChapters.get(i).chapterId === window.kavitaReadChapterId) {
                let prev = kavitaChapters.get(i - 1);
                window.kavitaReadChapterId = prev.chapterId;
                window.kavitaReadVolumeId = prev.volumeId;
                window.kavitaReadPage = 0;
                window.kavitaLoadChapterInfo();
                return;
            }
        }
    }
    function kavitaOpenInBrowser() {
        Quickshell.execDetached(["xdg-open",
            window.kavitaUrl + "/library/" + window.kavitaLastLibraryId + "/series/" + window.kavitaReadSeriesId]);
    }

    // Learn ↔ Kavita bridge — uses Kavita's existing chapter API directly
    // instead of downloading whole volumes and MIME-sniffing them. Chapters
    // come straight from /api/Series/series-detail; each chapter's text is
    // extracted lazily on click by kavita_learn_extract.sh.
    function learnFromKavitaSeries(seriesId, name, fmt) {
        if (!window.kavitaToken) return;
        window.learnLoading = true;
        window.bookTitle = name || "Unknown";
        window.bookLoaded = false;
        window.currentChapter = 0;
        window.kavitaReadSeriesId = seriesId;
        window.kavitaReadFormat = fmt || 0;
        bookChapters.clear();
        kavitaLearnSeriesProc.command = ["bash", "-c",
            "mkdir -p \"$HOME/.cache/quickshell\" && " +
            "echo \"[$(date '+%F %T')] GET /api/Series/series-detail seriesId=" + seriesId + " (learn)\" >> \"$HOME/.cache/quickshell/kavita.log\" && " +
            "curl -s '" + window.kavitaUrl + "/api/Series/series-detail?seriesId=" + seriesId + "' " +
            "-H 'Authorization: Bearer " + window.kavitaToken + "' 2>>\"$HOME/.cache/quickshell/kavita.log\""
        ];
        kavitaLearnSeriesProc.running = false; kavitaLearnSeriesProc.running = true;
    }
    Process {
        id: kavitaLearnSeriesProc; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector { onStreamFinished: {
            window.learnLoading = false;
            let t = this.text.trim();
            if (!t || t === "idle") { window.bookTitle = "Could not load series."; return; }
            try {
                let detail = JSON.parse(t);
                // Kavita's SeriesDetailDto has FOUR chapter-bearing arrays:
                //   storylineChapters — unified reading order (used by Kavita's UI)
                //   volumes[*].chapters — chapters grouped by volume
                //   chapters — "loose" chapters (chapters not under a volume)
                //   specials — special chapters (one-off extras; many PDF textbooks
                //              end up here when there's just one file per series)
                // We prefer storylineChapters when present (it dedupes + orders for us).
                // If absent, we combine the other three so nothing is missed.
                let raw = [];
                if (detail.storylineChapters && detail.storylineChapters.length > 0) {
                    raw = detail.storylineChapters;
                } else {
                    let vols = detail.volumes || [];
                    for (let v = 0; v < vols.length; v++) {
                        let vchs = vols[v].chapters || [];
                        for (let c = 0; c < vchs.length; c++) raw.push(vchs[c]);
                    }
                    let loose = detail.chapters || [];
                    for (let i = 0; i < loose.length; i++) raw.push(loose[i]);
                    let specials = detail.specials || [];
                    for (let i = 0; i < specials.length; i++) raw.push(specials[i]);
                }
                let chs = [];
                for (let i = 0; i < raw.length; i++) {
                    let ch = raw[i];
                    if (!ch || !ch.id) continue;
                    // Kavita's actual field names: title / titleName / range / number.
                    let label = ch.titleName || ch.title || ch.range || "";
                    if (!label || label === "0" || label === "-100000") {
                        label = "Chapter " + (ch.number || (i + 1));
                    }
                    chs.push({ chapterId: ch.id, pages: ch.pages || 0, title: label });
                }
                bookChapters.clear();
                for (let i = 0; i < chs.length; i++) {
                    bookChapters.append({
                        title: chs[i].title, chIndex: i,
                        chapterId: chs[i].chapterId, pageCount: chs[i].pages
                    });
                }
                window.totalChapters = chs.length;
                window.bookLoaded = chs.length > 0;
                window.currentChapter = 0;
                if (chs.length === 0) {
                    // Diagnostic: log the response shape so the user can see why.
                    window.bookTitle = "No chapters found for: " + (window.bookTitle || "this series");
                    diagKavitaLog.command = ["bash", "-c",
                        "echo \"[$(date '+%F %T')] series-detail returned no chapters. Top-level keys: " +
                        Object.keys(detail).join(",") + "\" >> \"$HOME/.cache/quickshell/kavita.log\""
                    ];
                    diagKavitaLog.running = false; diagKavitaLog.running = true;
                } else {
                    window.saveLearnMeta();
                }
            } catch(e) {
                window.bookTitle = "Error parsing Kavita response.";
                diagKavitaLog.command = ["bash", "-c",
                    "echo \"[$(date '+%F %T')] series-detail parse error: " + String(e).replace(/[\"\\\\]/g, "") + "\" >> \"$HOME/.cache/quickshell/kavita.log\""
                ];
                diagKavitaLog.running = false; diagKavitaLog.running = true;
            }
        }}
    }
    Process { id: diagKavitaLog; command: ["bash", "-c", "echo idle"] }

    // Persist the learn book selection (so loadLearnConfig can restore it).
    function saveLearnMeta() {
        let chs = [];
        for (let i = 0; i < bookChapters.count; i++) {
            let c = bookChapters.get(i);
            chs.push({ title: c.title, chIndex: c.chIndex,
                       chapterId: c.chapterId, pageCount: c.pageCount });
        }
        let meta = { title: window.bookTitle, seriesId: window.kavitaReadSeriesId,
                     format: window.kavitaReadFormat, total: chs.length, chapters: chs };
        let body = JSON.stringify(meta).replace(/'/g, "'\\''");
        learnMetaSaver.command = ["bash", "-c",
            "mkdir -p \"$HOME/.local/share/quickshell-learn\" && " +
            "printf '%s' '" + body + "' > \"$HOME/.local/share/quickshell-learn/book_meta.json\""
        ];
        learnMetaSaver.running = false; learnMetaSaver.running = true;
    }
    Process { id: learnMetaSaver; command: ["bash", "-c", "echo idle"] }

    function loadLearnConfig() {
        learnConfigLoader.command = ["bash", "-c",
            "LDIR=\"$HOME/.local/share/quickshell-learn\" && " +
            "cat \"$LDIR/book_meta.json\" 2>/dev/null && echo '|||SPLIT|||' && " +
            "cat \"$LDIR/progress.json\" 2>/dev/null"
        ];
        learnConfigLoader.running = false; learnConfigLoader.running = true;
    }
    Process {
        id: learnConfigLoader; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector { onStreamFinished: {
            if (this.text.trim() === "idle") return;
            let parts = this.text.split("|||SPLIT|||");
            try {
                let meta = JSON.parse(parts[0].trim());
                window.bookTitle = meta.title || "";
                window.totalChapters = meta.total || 0;
                window.bookLoaded = meta.total > 0;
                if (meta.seriesId) window.kavitaReadSeriesId = meta.seriesId;
                if (meta.format !== undefined) window.kavitaReadFormat = meta.format;
                bookChapters.clear();
                let mc = meta.chapters || [];
                for (let i = 0; i < mc.length; i++) {
                    // Forward-compat with the old schema (filepath-only). If a
                    // restored entry has no chapterId, it's stale and unusable
                    // — the user should re-pick the series.
                    bookChapters.append({
                        title: mc[i].title,
                        chIndex: mc[i].chIndex !== undefined ? mc[i].chIndex : (mc[i].index || i),
                        chapterId: mc[i].chapterId || 0,
                        pageCount: mc[i].pageCount || 0
                    });
                }
            } catch(e) {}
            if (parts.length > 1) {
                try {
                    let prog = JSON.parse(parts[1].trim());
                    window.currentChapter = prog.current_chapter || 0;
                    learnedTerms.clear();
                    let vocab = prog.vocab || [];
                    for (let i = 0; i < vocab.length; i++) {
                        learnedTerms.append(vocab[i]); window.saveLearnState();
                    }
                } catch(e) {}
            }
        }}
    }
    Timer { id: learnBootTimer; interval: 1200; repeat: false; running: true; onTriggered: window.loadLearnConfig() }

    // Lazy-load a chapter's plain text from Kavita (cached on disk).
    function loadChapter(index) {
        if (index < 0 || index >= bookChapters.count) return;
        let ch = bookChapters.get(index);
        window.currentChapter = index;
        window.currentChapterTitle = ch.title;
        if (!ch.chapterId) {
            window.currentChapterContent = "This book entry is stale. Re-pick the series from Kavita.";
            return;
        }
        chapterLoader.command = ["bash", "-c",
            "KAVITA_URL=\"" + window.kavitaUrl + "\" " +
            "KAVITA_TOKEN=\"" + window.kavitaToken + "\" " +
            "KAVITA_API_KEY=\"" + window.kavitaApiKey + "\" " +
            "\"$HOME/.config/hypr/scripts/quickshell/kavita_learn_extract.sh\" " +
            ch.chapterId + " " + ch.pageCount + " " + window.kavitaReadFormat
        ];
        chapterLoader.running = false; chapterLoader.running = true;
    }
    Process { id: chapterLoader; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector { onStreamFinished: {
            if (this.text.trim() !== "idle") window.currentChapterContent = this.text;
            // If a lesson was waiting on this chapter to load, start it now that
            // the text is actually available (fixes the empty-chapter race where
            // a fixed timer fired before the async fetch finished).
            if (window._lessonPendingStart) {
                window._lessonPendingStart = false;
                window.beginLessonNow();
            }
        }}
    }
    property bool _lessonPendingStart: false

    function startLesson() {
        if (!window.bookLoaded) return; if (learnedTerms.count > 0) window.exportVocabToObsidian();
        window.learnSubMode = "lesson"; window.learnLoading = true; lessonChat.clear();
        // Mark that we want to begin the lesson as soon as the chapter text
        // arrives; loadChapter is async, so beginLessonNow() runs from the
        // chapterLoader completion handler (with a timeout fallback below).
        window._lessonPendingStart = true;
        window.loadChapter(window.currentChapter);
        lessonStartFallback.restart();
    }
    // Fallback: if the chapter fetch is very slow or fails, don't hang forever —
    // start after 8s regardless (the tutor will note if text is missing).
    Timer { id: lessonStartFallback; interval: 8000; repeat: false; onTriggered: {
        if (window._lessonPendingStart) { window._lessonPendingStart = false; window.beginLessonNow(); }
    }}
    function beginLessonNow() {
        let vocabList = []; for (let i = 0; i < learnedTerms.count; i++) { let t = learnedTerms.get(i); vocabList.push(t.term + " (" + t.meaning + ")"); }
        // Embed the chapter text DIRECTLY in the prompt. Relying on the model to
        // go read a file with a tool was unreliable from one-shot mode; the model
        // always sees what's inline. The bridge caps stdin at 100KB, which fits a
        // typical chapter; we trim to ~24k chars to leave room for the reply.
        let book = (window.currentChapterContent || "").substring(0, 24000);
        let prompt = "You are a friendly language tutor (Duolingo-style). The student is studying from a textbook.\n\n" +
            "=== BEGIN CHAPTER TEXT ===\n" + book + "\n=== END CHAPTER TEXT ===\n\n" +
            "Terms the student already knows: " + (vocabList.length ? vocabList.join(", ") : "(none yet)") + "\n\n" +
            "Using the chapter text above, begin the lesson now: 1) briefly introduce what this chapter covers, 2) teach the key vocabulary and grammar from it, 3) give a short practice exercise drawn from this chapter. " +
            "Mix the target language with English explanations. Keep it focused and encouraging, not too long. " +
            "At the very end, list any NEW vocabulary, one per line, in EXACTLY this format: VOCAB:term|reading|meaning  (example: VOCAB:\u98df\u3079\u308b|\u305f\u3079\u308b|to eat)";
        window.runLearnPrompt(prompt);
    }
    // Send a prompt to Hermes via the bridge. Because Hermes one-shot mode does
    // not reliably persist sessions (upstream #11793), we DON'T rely on a named
    // session for memory — we use oneshot mode and carry the full lesson context
    // (chapter + transcript) in the prompt itself, assembled by the callers.
    function runLearnPrompt(prompt) {
        let promptB64 = Qt.btoa(prompt);
        learnApiCaller.command = ["bash", "-c",
            "echo " + promptB64 + " | base64 -d | HERMES_SESSION_OVERRIDE=oneshot " +
            "~/.config/hypr/scripts/hermes_bridge.sh 2>/dev/null"
        ];
        learnApiCaller.running = false; learnApiCaller.running = true;
    }
    function sendLearnMessage(text) {
        if (text.trim() === "" || window.learnLoading) return; lessonChat.append({ role: "user", content: text }); window.learnLoading = true; window.learnTypeLen = 0; window.learnLastResponse = "";
        // Rebuild the full context every turn (chapter excerpt + transcript), since
        // one-shot mode is stateless. This guarantees the tutor remembers the
        // lesson without depending on Hermes session persistence.
        let book = (window.currentChapterContent || "").substring(0, 12000);
        let hist = "";
        for (let i = 0; i < lessonChat.count; i++) {
            let m = lessonChat.get(i); if (!m || m.content === undefined) continue;
            hist += (m.role === "user" ? "Student" : "Tutor") + ": " + m.content + "\n";
        }
        let prompt = "You are a friendly language tutor continuing a lesson from this textbook chapter.\n\n" +
            "=== CHAPTER TEXT ===\n" + book + "\n=== END CHAPTER ===\n\n" +
            "Lesson so far:\n" + hist + "\n" +
            "Evaluate the student's latest message for correctness, continue teaching vocabulary/grammar from this chapter, and give the next small exercise. " +
            "Be encouraging and concise. End with any NEW vocabulary as VOCAB:term|reading|meaning lines.";
        window.runLearnPrompt(prompt);
    }
    Process { id: learnApiCaller; command: ["bash", "-c", "echo idle"]; stdout: StdioCollector { onStreamFinished: { if (this.text.trim() === "idle") return; window.learnLoading = false;
        try {
            // Hermes bridge returns {"type":"message","content":"..."}.
            let data = JSON.parse(this.text.trim());
            let resp = (data.content !== undefined) ? data.content
                     : (data.choices && data.choices[0] && data.choices[0].message ? data.choices[0].message.content : "");
            if (!resp || resp.trim() === "") { throw new Error("empty"); }
            let lines = resp.split("\n"); let cleanLines = [];
            for (let i = 0; i < lines.length; i++) { if (lines[i].trim().startsWith("VOCAB:")) { let parts = lines[i].trim().substring(6).split("|"); if (parts.length >= 3) { let exists = false; for (let j = 0; j < learnedTerms.count; j++) { if (learnedTerms.get(j).term === parts[0].trim()) { exists = true; break; } } if (!exists) { learnedTerms.append({ term: parts[0].trim(), reading: parts[1].trim(), meaning: parts[2].trim(), mastery: 1 }); window.saveLearnState(); } } } else { cleanLines.push(lines[i]); } }
            let cleanResp = cleanLines.join("\n").trim(); lessonChat.append({ role: "assistant", content: cleanResp }); window.learnLastResponse = cleanResp; window.learnTypeLen = 0; window.saveLearnProgress();
        } catch(e) { lessonChat.append({ role: "assistant", content: "Couldn't reach the tutor. Check that Hermes is set up (Agent tab), then try again." }); window.learnLastResponse = "Couldn't reach the tutor."; window.learnTypeLen = 0; } } } }

    function startRecording() { window.isRecording = true; window.voiceTranscript = ""; voiceRecorderProc.command = ["bash", "-c", "arecord -f S16_LE -r 16000 -c 1 -t wav /tmp/qs_learn_voice.wav 2>/dev/null || pw-record --format=s16 --rate=16000 --channels=1 /tmp/qs_learn_voice.wav 2>/dev/null || parecord --format=s16le --rate=16000 --channels=1 /tmp/qs_learn_voice.wav 2>/dev/null"]; voiceRecorderProc.running = false; voiceRecorderProc.running = true; }
    function stopRecording() { window.isRecording = false; voiceRecorderProc.signal(15); voiceTranscribeDelay.restart(); }
    Process { id: voiceRecorderProc; command: ["bash", "-c", "echo idle"] }
    Timer { id: voiceTranscribeDelay; interval: 500; repeat: false; onTriggered: { voiceTranscriberProc.command = ["bash", "-c", "if command -v whisper >/dev/null 2>&1; then whisper /tmp/qs_learn_voice.wav --model tiny --language auto --output_format txt --output_dir /tmp 2>/dev/null && cat /tmp/qs_learn_voice.txt 2>/dev/null; elif command -v whisper-cpp >/dev/null 2>&1; then whisper-cpp -f /tmp/qs_learn_voice.wav 2>/dev/null; else echo '[Voice requires whisper. Install: pip install openai-whisper]'; fi"]; voiceTranscriberProc.running = false; voiceTranscriberProc.running = true; } }
    Process { id: voiceTranscriberProc; command: ["bash", "-c", "echo idle"]; stdout: StdioCollector { onStreamFinished: { if (this.text.trim() !== "idle" && this.text.trim() !== "") { window.voiceTranscript = this.text.trim(); if (!window.voiceTranscript.startsWith("[")) { window.sendLearnMessage(window.voiceTranscript); window.voiceTranscript = ""; } } } } }

    function saveLearnProgress() { let vocab = []; for (let i = 0; i < learnedTerms.count; i++) { let t = learnedTerms.get(i); vocab.push({ term: t.term, reading: t.reading, meaning: t.meaning, mastery: t.mastery }); }
        let prog = JSON.stringify({ current_chapter: window.currentChapter, vocab: vocab }); let escaped = prog.replace(/'/g, "'\\''");
        learnProgressSaver.command = ["bash", "-c", "echo '" + escaped + "' > $HOME/.local/share/quickshell-learn/progress.json"]; learnProgressSaver.running = false; learnProgressSaver.running = true; }
    Process { id: learnProgressSaver; command: ["bash", "-c", "echo idle"] }

    function exportVocabToObsidian() { if (learnedTerms.count === 0) return;
        let lines = ["# " + window.bookTitle + " — Vocabulary", "", "**Chapter " + (window.currentChapter + 1) + "**: " + window.currentChapterTitle, "**Exported**: " + new Date().toISOString().split("T")[0], "**Total terms**: " + learnedTerms.count, "", "---", "", "| Term | Reading | Meaning | Mastery |", "|------|---------|---------|---------|"];
        for (let i = 0; i < learnedTerms.count; i++) { let t = learnedTerms.get(i); let stars = "●".repeat(Math.min(t.mastery, 5)) + "○".repeat(Math.max(5 - t.mastery, 0)); lines.push("| " + t.term + " | " + t.reading + " | " + t.meaning + " | " + stars + " |"); }
        lines.push("", "---", "", "## Key Ideas", "", "_Auto-generated from learning session. Review and expand as needed._");
        let content = lines.join("\n"); let b64 = Qt.btoa(content); let safeName = window.bookTitle.replace(/[^a-zA-Z0-9_\- ]/g, "").replace(/ /g, "_");
        vocabExporter.command = ["bash", "-c", "VAULT=$(find ~/Documents ~/Notes ~/Obsidian -name .obsidian -maxdepth 2 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo $HOME/Notes) && mkdir -p $VAULT/Learning && echo " + b64 + " | base64 -d > \"$VAULT/Learning/" + safeName + "_vocab.md\" && echo exported"];
        vocabExporter.running = false; vocabExporter.running = true; }
    Process { id: vocabExporter; command: ["bash", "-c", "echo idle"] }

    function advanceChapter() { if (window.currentChapter < window.totalChapters - 1) { window.exportVocabToObsidian(); window.currentChapter++; window.saveLearnProgress(); window.startLesson(); } }

    Timer { id: focusTimer; interval: 600; repeat: false; running: true; onTriggered: inputField.forceActiveFocus() }

    // ── Send message — Hermes-only ──
    function sendMessage(query) {
        if (query.trim() === "" || isLoading) return;
        chatMessages.append({ role: "user", content: query });
        window.saveChatState();
        if (window.hermesEnabled) { if (window.callHermes(query)) return; }
        chatMessages.append({ role: "assistant", content: "Hermes is not enabled. Set hermes_enabled=true in ~/.config/hypr/ai_config.json." });
        window.lastResponse = "Hermes is not enabled."; window.typeLen = 0; window.saveChatState();
    }

    // ── Orbit ──
    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle { from: 0; to: 12.5663706; duration: 180000; loops: Animation.Infinite; running: true }

    // ── Intro ──
    property real introMain: 0
    property real introTop: 0
    property real introChat: 0
    property real introInput: 0
    ParallelAnimation {
        running: true
        NumberAnimation { target: window; property: "introMain"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutQuart }
        SequentialAnimation { PauseAnimation { duration: 100 } NumberAnimation { target: window; property: "introTop"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutBack; easing.overshoot: 1.0 } }
        SequentialAnimation { PauseAnimation { duration: 200 } NumberAnimation { target: window; property: "introChat"; from: 0; to: 1.0; duration: 850; easing.type: Easing.OutQuart } }
        SequentialAnimation { PauseAnimation { duration: 350 } NumberAnimation { target: window; property: "introInput"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutExpo } }
    }

    // ═══════════════════════════════════════════
    // UI
    // ═══════════════════════════════════════════
    Item {
        anchors.fill: parent; scale: 0.92 + (0.08 * introMain); opacity: introMain
        transform: Translate { y: window.s(15) * (1 - introMain) }

        Rectangle {
            anchors.fill: parent; radius: window.s(20); color: window.base
            border.color: Qt.rgba(window.modeColor1.r, window.modeColor1.g, window.modeColor1.b, 0.15); border.width: 1
            Behavior on border.color { ColorAnimation { duration: 500 } }
            clip: true

            // ── Floating tools popup ──
            Rectangle {
                id: toolsFloat; visible: window.toolsPopupOpen && window.activeMode === "chat"
                width: window.s(160); height: visible ? toolsFloatCol.implicitHeight + window.s(12) : 0
                anchors.left: parent.left; anchors.leftMargin: window.s(26); anchors.bottom: parent.bottom; anchors.bottomMargin: window.s(100)
                radius: window.s(10); color: window.mantle; border.color: window.surface1; border.width: 1; z: 100; clip: true
                Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutQuint } }
                Rectangle { anchors.fill: parent; anchors.margins: -1; radius: parent.radius + 1; color: "transparent"; border.color: Qt.rgba(0,0,0,0.3); border.width: 2; z: -1 }
                Column {
                    id: toolsFloatCol; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: window.s(6); spacing: window.s(2)
                    Repeater {
                        model: ListModel { ListElement { icon: "󰍉"; label: "Web Search" } ListElement { icon: "󰈙"; label: "Read File" } ListElement { icon: "󰗀"; label: "Image Gen" } ListElement { icon: "󰘦"; label: "Code" } ListElement { icon: "󰗊"; label: "Translate" } }
                        delegate: Rectangle {
                            width: parent.width; height: window.s(28); radius: window.s(6)
                            color: tItemMa.containsMouse ? window.surface1 : "transparent"
Behavior on color { ColorAnimation { duration: 80 } }
                            Row { anchors.left: parent.left; anchors.leftMargin: window.s(8); anchors.verticalCenter: parent.verticalCenter; spacing: window.s(8)
                                Text { text: icon; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(13); color: window.activeTools[label] ? window.green : (tItemMa.containsMouse ? window.mauve : window.overlay1)
Behavior on color { ColorAnimation { duration: 100 } }
anchors.verticalCenter: parent.verticalCenter }
                                Text { text: label; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.activeTools[label] ? window.text : window.subtext0; anchors.verticalCenter: parent.verticalCenter } }
                            Text { anchors.right: parent.right; anchors.rightMargin: window.s(8); anchors.verticalCenter: parent.verticalCenter; text: "󰄬"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(13); color: window.green; visible: window.activeTools[label] === true }
                            MouseArea { id: tItemMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { let tools = window.activeTools; tools[label] = !tools[label]; window.activeTools = tools; inputField.forceActiveFocus(); } }
                        }
                    }
                }
            }

            // ── Previous-chats dropdown (with AI search) ──
            // Floats centered, just below the header, hovering over the
            // conversation area (rather than pinned to a corner).
            Rectangle {
                id: chatHistoryPanel
                visible: window.chatHistoryOpen && window.activeMode === "chat"
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top; anchors.topMargin: window.s(64)
                width: Math.min(window.s(420), parent.width - window.s(40))
                height: visible ? window.s(380) : 0
                radius: window.s(12); color: window.mantle
                border.color: window.surface1; border.width: 1; z: 200; clip: true
                Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutQuint } }
                Rectangle { anchors.fill: parent; anchors.margins: -1; radius: parent.radius + 1; color: "transparent"; border.color: Qt.rgba(0,0,0,0.3); border.width: 2; z: -1 }

                ColumnLayout {
                    anchors.fill: parent; anchors.margins: window.s(10); spacing: window.s(8)

                    // AI search bar
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: window.s(34)
                        radius: window.s(8); color: window.surface0
                        border.color: chatSearchInput.activeFocus ? window.mauve : window.surface1; border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 120 } }
                        RowLayout { anchors.fill: parent; anchors.leftMargin: window.s(10); anchors.rightMargin: window.s(8); spacing: window.s(6)
                            Text { text: "󰍉"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(13); color: window.overlay1 }
                            TextInput {
                                id: chatSearchInput
                                Layout.fillWidth: true
                                font.family: "JetBrains Mono"; font.pixelSize: window.s(11); color: window.text
                                clip: true; selectByMouse: true
                                onTextChanged: window.chatHistoryQuery = text
                                // Enter runs the AI semantic search
                                Keys.onReturnPressed: window.runChatSearch(text)
                                Keys.onEnterPressed: window.runChatSearch(text)
                                Text { anchors.fill: parent; visible: parent.text === ""; verticalAlignment: Text.AlignVCenter
                                    text: "Search chats in plain English…"; font: parent.font; color: window.overlay0 }
                            }
                            Text { visible: chatSearchInput.text !== ""; text: "󰅖"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(12); color: window.overlay1
                                MouseArea { anchors.fill: parent; anchors.margins: -window.s(4); cursorShape: Qt.PointingHandCursor
                                    onClicked: { chatSearchInput.text = ""; window.chatSearchResultIds = ""; } } }
                        }
                    }

                    Text { visible: window.chatHistoryLoading; text: "Loading…"; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.overlay0 }

                    // Scrollable list of past chats
                    ListView {
                        id: chatHistoryView
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true; spacing: window.s(4); model: chatHistoryModel
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { width: window.s(3); policy: ScrollBar.AsNeeded
                            contentItem: Rectangle { implicitWidth: window.s(3); radius: window.s(1); color: window.surface2 } }
                        delegate: Rectangle {
                            width: chatHistoryView.width
                            // Hide rows not in the AI search result set (when a search is active).
                            property bool matchesSearch: {
                                if (window.chatSearchResultIds === "") return true;       // no search
                                if (window.chatSearchResultIds === "__none__") return false;
                                // Search returns titles; match against this row's title.
                                return window.chatSearchResultIds.indexOf(model.title) >= 0;
                            }
                            height: matchesSearch ? chCol.implicitHeight + window.s(12) : 0
                            visible: height > 0; clip: true; radius: window.s(8)
                            color: chRowMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.7) : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.4)
                            Behavior on color { ColorAnimation { duration: 100 } }
                            ColumnLayout { id: chCol; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: window.s(8); spacing: window.s(2)
                                Text { text: model.title; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(11); color: chRowMa.containsMouse ? window.text : window.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                                Text { text: model.preview; font.family: "JetBrains Mono"; font.pixelSize: window.s(8); color: window.overlay0; elide: Text.ElideRight; Layout.fillWidth: true; maximumLineCount: 2; wrapMode: Text.Wrap }
                            }
                            MouseArea { id: chRowMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: window.openArchivedChat(model.sessionId) }
                        }
                    }
                    Text { visible: chatHistoryModel.count === 0 && !window.chatHistoryLoading
                        text: "No previous chats yet."; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.overlay0
                        Layout.alignment: Qt.AlignHCenter }
                }
            }

            // ── Native Kanban board (in-popup) ──
            // Columns grouped by status, populated from `hermes kanban list`.
            // Toggled by the Kanban header button (right-click opens the full
            // web dashboard for drag/drop). Add tasks inline.
            Rectangle {
                visible: window.kanbanOpen && window.activeMode === "chat"
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top; anchors.topMargin: window.s(64)
                width: Math.min(window.s(520), parent.width - window.s(24))
                height: visible ? Math.min(parent.height - window.s(96), window.s(440)) : 0
                radius: window.s(12); color: window.mantle
                border.color: window.surface1; border.width: 1; z: 200; clip: true
                Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutQuint } }

                ColumnLayout { anchors.fill: parent; anchors.margins: window.s(10); spacing: window.s(8)
                    // Header
                    RowLayout { Layout.fillWidth: true; spacing: window.s(8)
                        Text { text: "󰕮"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(15); color: window.teal }
                        Text { text: "Kanban"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(13); color: window.text }
                        Item { Layout.fillWidth: true }
                        // Refresh
                        Rectangle { Layout.preferredWidth: window.s(28); Layout.preferredHeight: window.s(26); radius: window.s(6)
                            color: kbRefMa.containsMouse ? window.surface1 : "transparent"
                            Text { anchors.centerIn: parent; text: "󰑐"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(13); color: window.sapphire }
                            MouseArea { id: kbRefMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.fetchKanban() } }
                        // Open full dashboard
                        Rectangle { Layout.preferredWidth: window.s(28); Layout.preferredHeight: window.s(26); radius: window.s(6)
                            color: kbWebMa.containsMouse ? window.surface1 : "transparent"
                            Text { anchors.centerIn: parent; text: "󰖟"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(13); color: window.teal }
                            MouseArea { id: kbWebMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.openKanban() } }
                        // Close
                        Rectangle { Layout.preferredWidth: window.s(28); Layout.preferredHeight: window.s(26); radius: window.s(6)
                            color: kbCloseMa.containsMouse ? window.surface1 : "transparent"
                            Text { anchors.centerIn: parent; text: "󰅖"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(13); color: window.overlay1 }
                            MouseArea { id: kbCloseMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.kanbanOpen = false } }
                    }
                    // Status / loading / error line
                    Text { visible: window.kanbanLoading || window.kanbanError !== ""
                        text: window.kanbanLoading ? "Loading board…" : window.kanbanError
                        font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.kanbanLoading ? window.overlay1 : window.peach
                        Layout.fillWidth: true; wrapMode: Text.Wrap }
                    // Columns: To Do / In Progress / Done
                    RowLayout { Layout.fillWidth: true; Layout.fillHeight: true; spacing: window.s(6)
                        Repeater {
                            model: [ {key:"todo", label:"To Do", col:window.overlay1, match:["todo","backlog","open","new","pending"]},
                                     {key:"doing", label:"In Progress", col:window.yellow, match:["doing","in_progress","inprogress","active","wip","started"]},
                                     {key:"done", label:"Done", col:window.green, match:["done","closed","complete","completed","finished"]} ]
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true; Layout.fillHeight: true; radius: window.s(8)
                                color: Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.4)
                                border.color: window.surface1; border.width: 1; clip: true
                                ColumnLayout { anchors.fill: parent; anchors.margins: window.s(6); spacing: window.s(4)
                                    RowLayout { Layout.fillWidth: true; spacing: window.s(4)
                                        Rectangle { width: window.s(7); height: window.s(7); radius: window.s(4); color: modelData.col; anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: modelData.label; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(9); color: modelData.col } }
                                    ListView { Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: window.s(4)
                                        boundsBehavior: Flickable.StopAtBounds
                                        model: kanbanTasks
                                        delegate: Loader {
                                            width: ListView.view ? ListView.view.width : 0
                                            // Only show this card in the column matching its status.
                                            active: modelData.match.indexOf(model.status) >= 0
                                                    || (modelData.key === "todo" && modelData.match.indexOf(model.status) < 0
                                                        && ["doing","in_progress","inprogress","active","wip","started","done","closed","complete","completed","finished"].indexOf(model.status) < 0)
                                            visible: active
                                            sourceComponent: Rectangle {
                                                width: parent ? parent.width : 0
                                                height: kbCardTxt.implicitHeight + window.s(12); radius: window.s(6)
                                                color: Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.5)
                                                ColumnLayout { anchors.fill: parent; anchors.margins: window.s(6); spacing: window.s(2)
                                                    Text { id: kbCardTxt; text: model.title; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.text; Layout.fillWidth: true; wrapMode: Text.Wrap }
                                                    Text { visible: model.assignee !== ""; text: "󰀄 " + model.assignee; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(8); color: window.overlay1 } }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    // Add-task input
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: window.s(32); radius: window.s(8)
                        color: window.surface0; border.color: kbAddInput.activeFocus ? window.teal : window.surface1; border.width: 1
                        RowLayout { anchors.fill: parent; anchors.leftMargin: window.s(10); anchors.rightMargin: window.s(6); spacing: window.s(6)
                            TextInput { id: kbAddInput; Layout.fillWidth: true; verticalAlignment: Text.AlignVCenter
                                font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.text; clip: true; selectByMouse: true
                                Keys.onReturnPressed: { window.kanbanAddTask(text); text = ""; }
                                Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; visible: parent.text === ""; text: "Add a task…"; font: parent.font; color: window.overlay0 } }
                            Rectangle { Layout.preferredWidth: window.s(28); Layout.preferredHeight: window.s(24); radius: window.s(6)
                                color: kbAddMa.containsMouse ? window.teal : window.surface1
                                Text { anchors.centerIn: parent; text: "󰐕"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(12); color: kbAddMa.containsMouse ? window.crust : window.teal }
                                MouseArea { id: kbAddMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { window.kanbanAddTask(kbAddInput.text); kbAddInput.text = ""; } } }
                        }
                    }
                }
            }            Rectangle { width: parent.width * 0.9; height: width; radius: width / 2; x: parent.width / 2 - width / 2 + Math.sin(window.globalOrbitAngle * 1.5) * window.s(-150); y: parent.height / 2 - height / 2 + Math.cos(window.globalOrbitAngle * 1.5) * window.s(-100); opacity: 0.06; color: window.modeColor2
Behavior on color { ColorAnimation { duration: 500 } } }

            ColumnLayout {
                anchors.fill: parent; anchors.margins: window.s(20); spacing: window.s(10)

                // ── Header ──
                RowLayout {
                    Layout.fillWidth: true; Layout.minimumHeight: window.s(36); Layout.maximumHeight: window.s(36); spacing: window.s(12); opacity: introTop
                    transform: Translate { y: window.s(-10) * (1.0 - introTop) }
                    // Module slider. Single click switches module; double-click on a
                    // module's button opens that module's associated webpage/app.
                    Rectangle { Layout.preferredWidth: window.s(200); Layout.fillHeight: true; radius: window.s(10); color: window.surface0; border.color: window.surface1; border.width: 1
                        property var modes: ["chess", "kavita"]; property int modeIdx: Math.max(0, modes.indexOf(window.activeMode))
                        Rectangle { id: modeSlideInd; width: (parent.width - window.s(2)) / 2; height: parent.height - window.s(2); y: window.s(1); radius: window.s(8); x: parent.modeIdx * width + window.s(1)
Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
                            property color c1: window.activeMode === "chess" ? window.yellow : window.pink
                            property color c2: window.activeMode === "chess" ? window.peach : window.mauve
                            Behavior on c1 { ColorAnimation { duration: 300 } }
Behavior on c2 { ColorAnimation { duration: 300 } }
                            gradient: Gradient { orientation: Gradient.Horizontal
GradientStop { position: 0.0; color: modeSlideInd.c1 }
GradientStop { position: 1.0; color: modeSlideInd.c2 } } }
                        RowLayout { anchors.fill: parent; spacing: 0
                            Item { Layout.fillWidth: true; Layout.fillHeight: true
Text { anchors.centerIn: parent; text: "󰡛"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(14); color: window.activeMode === "chess" ? "#ffffff" : window.overlay0
Behavior on color { ColorAnimation { duration: 200 } } }
MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { window.flushNoteNow(); window.activeMode = "chess"; } onDoubleClicked: window.openModuleWebpage("chess") } }
                            Item { Layout.fillWidth: true; Layout.fillHeight: true
Text { anchors.centerIn: parent; text: "󰗚"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(14); color: window.activeMode === "kavita" ? "#ffffff" : window.overlay0
Behavior on color { ColorAnimation { duration: 200 } } }
MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { window.flushNoteNow(); window.activeMode = "kavita"; if (window.kavitaConnected) { if (window.kavitaLastSeriesId > 0 && window.kavitaLastName !== "") { window.kavitaOpenSeries(window.kavitaLastSeriesId, window.kavitaLastLibraryId, window.kavitaLastName, window.kavitaLastFormat || 0); } else { window.kavitaFetchOnDeck(); } } else window.kavitaAuth(); } onDoubleClicked: window.openModuleWebpage("kavita") } }
                        }
                    }
                    // Right side of header — context-aware, fills remaining width.
                    //   Kavita reading → LIBRARY pill, then book title to its right.
                    //   Chat          → AI-generated chat title, previous-chats
                    //                    dropdown, and New Chat button.
                    Item { Layout.fillWidth: true; Layout.fillHeight: true
                        // ── Kavita reading: clickable title opens the library chooser ──
                        RowLayout {
                            anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            spacing: window.s(6)
                            visible: window.activeMode === "kavita" && window.kavitaSubMode === "reading"
                            Item { Layout.fillWidth: true }
                            // the category-grouped book chooser. A small chevron hints
                            // that it's interactive.
                            // Title button fills the available header space; the
                            // text elides, the chevron stays at a fixed size. Using
                            // RowLayout (not Row + anchors) avoids the circular
                            // width dependency that was collapsing the title to 0.
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: window.s(28); radius: window.s(8)
                                color: kavTitleMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.7) : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                                RowLayout { id: kavTitleRow; anchors.fill: parent; anchors.leftMargin: window.s(8); anchors.rightMargin: window.s(8); spacing: window.s(6)
                                    Text {
                                        Layout.fillWidth: true
                                        text: window.kavitaReadTitle
                                        font.family: "JetBrains Mono"; font.weight: Font.Medium
                                        font.pixelSize: window.s(10)
                                        color: kavTitleMa.containsMouse ? window.text : window.subtext0
                                        elide: Text.ElideRight; horizontalAlignment: Text.AlignRight
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    Text { id: chevK
                                        text: "󰍝"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(11)
                                        color: kavTitleMa.containsMouse ? window.pink : window.overlay1
                                        verticalAlignment: Text.AlignVCenter }
                                }
                                MouseArea { id: kavTitleMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { window.kavitaSaveProgress(); window.kavitaSubMode = "library"; window.kavitaFetchSeries(); } }
                            }
                        }
                        // ── Chat: [title ▾ opens history] ............ [New Chat] ──
                        RowLayout {
                            anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            spacing: window.s(8)
                            visible: window.activeMode === "chat"
                            // Title doubles as the previous-chats dropdown toggle.
                            Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: window.s(28); radius: window.s(8)
                                color: chatTitleMa.containsMouse || window.chatHistoryOpen ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.7) : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                                RowLayout { id: chatTitleRow; anchors.fill: parent; anchors.leftMargin: window.s(8); anchors.rightMargin: window.s(8); spacing: window.s(6)
                                    Text { id: chevC
                                        text: "󰍝"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(11)
                                        color: window.chatHistoryOpen ? window.mauve : (chatTitleMa.containsMouse ? window.mauve : window.overlay1)
                                        verticalAlignment: Text.AlignVCenter }
                                    Text {
                                        Layout.fillWidth: true
                                        text: window.chatTitle !== "" ? window.chatTitle : "New conversation"
                                        font.family: "JetBrains Mono"; font.weight: Font.Medium
                                        font.pixelSize: window.s(10)
                                        color: window.chatTitle !== "" ? (chatTitleMa.containsMouse ? window.text : window.subtext0) : window.overlay0
                                        elide: Text.ElideRight; horizontalAlignment: Text.AlignLeft
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                                MouseArea { id: chatTitleMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { window.chatHistoryOpen = !window.chatHistoryOpen; if (window.chatHistoryOpen) window.loadChatHistory(); } }
                            }
                            // Kanban board button — opens the Hermes multi-agent
                            // Kanban dashboard (served by the gateway at :9119).
                            // If the gateway/board isn't up yet, the helper starts
                            // them, then opens the dashboard.
                            Rectangle {
                                Layout.preferredWidth: kanbanRow.implicitWidth + window.s(16); Layout.preferredHeight: window.s(28); radius: window.s(8)
                                color: hdrKanbanMa.containsMouse ? Qt.rgba(window.teal.r, window.teal.g, window.teal.b, 0.18) : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.5)
                                border.color: hdrKanbanMa.containsMouse ? window.teal : Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.5); border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Row { id: kanbanRow; anchors.centerIn: parent; spacing: window.s(6)
                                    Text { text: "󰕮"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(13); color: window.teal; anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: "Kanban"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(10); color: hdrKanbanMa.containsMouse ? window.text : window.subtext0; anchors.verticalCenter: parent.verticalCenter } }
                                MouseArea {
                                    id: hdrKanbanMa; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: (mouse) => {
                                        if (mouse.button === Qt.RightButton) window.openKanban();   // full web dashboard
                                        else window.toggleKanban();                                  // in-popup board
                                    }
                                }
                            }
                            // New Chat button (right edge)
                            Rectangle {
                                Layout.preferredWidth: newChatRow.implicitWidth + window.s(16); Layout.preferredHeight: window.s(28); radius: window.s(8)
                                color: hdrNewChatMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.5)
                                border.color: hdrNewChatMa.containsMouse ? window.mauve : Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.5); border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Row { id: newChatRow; anchors.centerIn: parent; spacing: window.s(6)
                                    Text { text: "󰝒"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(13); color: window.mauve; anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: "New Chat"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(10); color: hdrNewChatMa.containsMouse ? window.text : window.subtext0; anchors.verticalCenter: parent.verticalCenter } }
                                MouseArea {
                                    id: hdrNewChatMa; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: (mouse) => {
                                        if (mouse.button === Qt.RightButton) window.startNewChat(true);   // temporary
                                        else window.startNewChat(false);                                   // normal
                                    }
                                }
                            }
                        }
                        // ── Chess: icon-only actions on the LEFT, opponent name
                        // (with hover account card) on the RIGHT. Clocks are
                        // centered above the board. Only while a game is active. ──
                        RowLayout {
                            anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            spacing: window.s(6)
                            visible: window.activeMode === "chess" && (window.chessStatus === "playing" || window.chessStatus === "ended")
                            // Icon-only action buttons (no words): Draw · Takeback ·
                            // Resign while playing; Analysis once the game is over.
                            Repeater {
                                model: window.chessStatus === "playing"
                                    ? (window.chessIsCorr ? []
                                       : [ {ic:"󰦘", col:window.yellow, act:"draw",     tip:"Offer draw"},
                                           {ic:"󰕍", col:window.blue,   act:"takeback", tip:"Takeback"},
                                           {ic:"󰗽", col:window.red,    act:"resign",   tip:"Resign"} ])
                                    : [ {ic:"󰋙", col:window.mauve,  act:"analysis", tip:"Analysis"} ]
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.preferredWidth: window.s(30); Layout.preferredHeight: window.s(28); radius: window.s(6)
                                    color: hdrTbMa.containsMouse ? Qt.rgba(modelData.col.r, modelData.col.g, modelData.col.b, 0.18) : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.5)
                                    border.color: hdrTbMa.containsMouse ? modelData.col : window.surface1; border.width: 1
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                    Text { anchors.centerIn: parent; text: modelData.ic; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(13); color: modelData.col }
                                    ToolTip.visible: hdrTbMa.containsMouse; ToolTip.text: modelData.tip; ToolTip.delay: 400
                                    MouseArea { id: hdrTbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (modelData.act === "draw") window.chessOfferDraw(true);
                                            else if (modelData.act === "takeback") window.chessTakeback(true);
                                            else if (modelData.act === "resign") window.chessResign();
                                            else if (modelData.act === "analysis") { window.chessStatus = "analysis"; window.chessRequestAnalysis(); }
                                        } }
                                }
                            }
                            // Add-time (+) — only for real opponents.
                            Rectangle {
                                visible: !window.chessIsAiGame && !window.chessIsCorr && window.chessStatus === "playing"
                                Layout.preferredWidth: window.s(30); Layout.preferredHeight: window.s(28); radius: window.s(6)
                                color: hdrAddTimeMa.containsMouse ? Qt.rgba(window.teal.r, window.teal.g, window.teal.b, 0.20) : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.5)
                                border.color: hdrAddTimeMa.containsMouse ? window.teal : window.surface1; border.width: 1
                                Behavior on color { ColorAnimation { duration: 100 } }
                                Text { anchors.centerIn: parent; text: "󰐕"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(13); color: window.teal }
                                ToolTip.visible: hdrAddTimeMa.containsMouse; ToolTip.text: "Give opponent +15s"; ToolTip.delay: 400
                                MouseArea { id: hdrAddTimeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: window.chessAddTime(15) }
                            }
                            Item { Layout.fillWidth: true }
                            // Whose-turn dot
                            Rectangle {
                                visible: window.chessStatus === "playing"
                                Layout.preferredWidth: window.s(8); Layout.preferredHeight: window.s(8); radius: window.s(4)
                                color: window.chessMyTurn ? window.green : window.overlay0
                            }
                            // Opponent name — hovering fetches & shows account info
                            // (rating, title, online) like Lichess's hover card.
                            Rectangle {
                                Layout.preferredWidth: oppNameTxt.implicitWidth + window.s(14); Layout.preferredHeight: window.s(28); radius: window.s(6)
                                color: oppNameMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.7) : "transparent"
                                Behavior on color { ColorAnimation { duration: 100 } }
                                Text { id: oppNameTxt; anchors.centerIn: parent
                                    text: window.chessOpponent !== "" ? window.chessOpponent : "Opponent"
                                    font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(11); color: window.text }
                                MouseArea { id: oppNameMa; anchors.fill: parent; hoverEnabled: true
                                    onEntered: window.chessFetchOpponentInfo()
                                    onClicked: { if (window.chessOpponent !== "" && !window.chessIsAiGame) Quickshell.execDetached(["xdg-open", "https://lichess.org/@/" + window.chessOpponent]); } }
                                // Hover account card
                                Rectangle {
                                    visible: oppNameMa.containsMouse && !window.chessIsAiGame && window.chessOppInfo !== ""
                                    width: oppInfoTxt.implicitWidth + window.s(18); height: oppInfoTxt.implicitHeight + window.s(14)
                                    anchors.top: parent.bottom; anchors.right: parent.right; anchors.topMargin: window.s(4)
                                    radius: window.s(8); color: window.crust; border.color: window.surface2; border.width: 1; z: 100
                                    Text { id: oppInfoTxt; anchors.centerIn: parent
                                        text: window.chessOppInfo
                                        font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.text
                                        horizontalAlignment: Text.AlignLeft }
                                }
                            }
                        }
                    }
                }
                Item { Layout.fillWidth: true; Layout.fillHeight: true; visible: window.activeMode === "chat"
                    ColumnLayout { anchors.fill: parent; spacing: window.s(8)

                        // ── Top bar: temp indicator only (New Chat now lives in
                        // the global header inline with the module slider) ──
                        RowLayout { Layout.fillWidth: true; Layout.preferredHeight: window.s(28); spacing: window.s(8)
                            visible: window.temporaryChat
                            Item { Layout.fillWidth: true }
                            Text { text: "Temporary — not saved"; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.peach; Layout.alignment: Qt.AlignVCenter }
                        }

                        // Greeting (empty state)
                        Item { Layout.fillWidth: true; Layout.fillHeight: true; visible: chatMessages.count === 0; opacity: introChat
                            ColumnLayout { anchors.centerIn: parent; spacing: window.s(12); width: parent.width * 0.8
                                Text { text: window.greetingFetched ? window.greetingText : "..."; font.family: "JetBrains Mono"; font.weight: Font.Medium; font.pixelSize: window.s(14); color: window.text; Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter; opacity: window.greetingFetched ? 1.0 : 0.3
Behavior on opacity { NumberAnimation { duration: 600 } } } } }

                        // Messages — constrained to a centered column (max ~720px)
                        // so the conversation reads down the middle rather than
                        // spanning edge to edge.
                        Item { Layout.fillWidth: true; Layout.fillHeight: true; visible: chatMessages.count > 0
                            ListView { id: chatView
                                width: Math.min(parent.width, window.s(640))
                                anchors.horizontalCenter: parent.horizontalCenter
                                height: parent.height
                                model: chatMessages; clip: true; spacing: window.s(8); onCountChanged: positionViewAtEnd(); opacity: introChat
                            ScrollBar.vertical: ScrollBar { width: window.s(3); policy: ScrollBar.AsNeeded; contentItem: Rectangle { implicitWidth: window.s(3); radius: window.s(1); color: window.surface2 } }
                            delegate: Item { width: ListView.view ? ListView.view.width : 0; height: msgOuter.implicitHeight + window.s(8)
                                ColumnLayout { id: msgOuter; anchors.left: model.role === "assistant" ? parent.left : undefined; anchors.right: model.role === "user" ? parent.right : undefined; anchors.top: parent.top; width: Math.min(parent.width * 0.85, msgContent.implicitWidth + window.s(28)); spacing: window.s(4)
                                    Text { text: model.role === "user" ? "You" : "Hermes"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(10); color: model.role === "user" ? window.modeColor1 : window.overlay1; Layout.alignment: model.role === "user" ? Qt.AlignRight : Qt.AlignLeft }
                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: msgContent.implicitHeight + window.s(16); radius: window.s(12)
                                        color: model.role === "user" ? Qt.rgba(window.modeColor1.r, window.modeColor1.g, window.modeColor1.b, 0.12) : "transparent"
                                        border.color: model.role === "user" ? Qt.rgba(window.modeColor1.r, window.modeColor1.g, window.modeColor1.b, 0.2) : "transparent"; border.width: model.role === "user" ? 1 : 0
                                        TextEdit { id: msgContent; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: model.role === "user" ? window.s(10) : window.s(4); anchors.topMargin: model.role === "user" ? window.s(8) : window.s(4)
                                            text: { if (model.role === "assistant" && index === chatMessages.count - 1) return window.displayedResponse; return model.content; }
                                            font.family: "JetBrains Mono"; font.pixelSize: window.s(12); color: window.text; wrapMode: TextEdit.Wrap; textFormat: TextEdit.PlainText
                                            // Read-only but selectable so the user can copy AI replies.
                                            readOnly: true; selectByMouse: true; selectByKeyboard: true; persistentSelection: true
                                            selectionColor: Qt.rgba(window.modeColor1.r, window.modeColor1.g, window.modeColor1.b, 0.4)
                                            selectedTextColor: window.text
                                            // Right-click context menu for Copy/Select All.
                                            MouseArea {
                                                anchors.fill: parent; acceptedButtons: Qt.RightButton
                                                cursorShape: Qt.IBeamCursor; propagateComposedEvents: true
                                                onClicked: function(mouse) { if (mouse.button === Qt.RightButton) msgCtxMenu.popup() }
                                            }
                                            Menu {
                                                id: msgCtxMenu
                                                MenuItem { text: "Copy"; enabled: msgContent.selectedText.length > 0
                                                    onTriggered: msgContent.copy() }
                                                MenuItem { text: "Select all"; onTriggered: msgContent.selectAll() }
                                            }
                                        } } } } }
                        }

                        // Loading — uses Hermes's signature caduceus glyph (⚕) to
                        // match the agent's own visual identity, instead of the
                        // Arch nerd-font logo we previously had.
                        RowLayout { Layout.fillWidth: true; Layout.preferredHeight: window.s(28); visible: window.isLoading; spacing: window.s(8); Layout.leftMargin: window.s(12)
                            Text { text: "⚕"; font.family: "JetBrains Mono"; font.pixelSize: window.s(14); color: window.mauve
                                RotationAnimation on rotation { running: window.isLoading; loops: Animation.Infinite; from: 0; to: 360; duration: 2000 } }
                            Text { text: "Thinking"; font.family: "JetBrains Mono"; font.pixelSize: window.s(11); color: window.overlay1; property int dots: 0
                                Timer { interval: 400; repeat: true; running: window.isLoading; onTriggered: parent.dots = (parent.dots + 1) % 4 }
                                Component.onCompleted: text = Qt.binding(function() { return "Thinking" + ".".repeat(dots); }) } }

                        // ── Input box ──
                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: window.s(90); radius: window.s(16); color: window.surface0
                            border.color: inputField.activeFocus ? window.modeColor1 : window.surface1; border.width: inputField.activeFocus ? 2 : 1
Behavior on border.color { ColorAnimation { duration: 200 } }
                            opacity: introInput; transform: Translate { y: window.s(15) * (1.0 - introInput) }
                            ColumnLayout { anchors.fill: parent; anchors.margins: window.s(8); spacing: window.s(4)
                                TextInput { id: inputField; Layout.fillWidth: true; Layout.minimumHeight: window.s(30); Layout.maximumHeight: window.s(30); verticalAlignment: TextInput.AlignVCenter
                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(13); color: window.text; clip: true; selectByMouse: true; leftPadding: window.s(6)
                                    selectionColor: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.3)
                                    Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; leftPadding: window.s(6); visible: !inputField.text && !inputField.activeFocus; text: "Ask anything..."; font: inputField.font; color: window.overlay0 }
                                    Keys.onReturnPressed: { if (text.trim() !== "" && !window.isLoading) { window.sendMessage(text.trim()); text = ""; } } }
                                RowLayout { Layout.fillWidth: true; Layout.minimumHeight: window.s(30); Layout.maximumHeight: window.s(30); spacing: window.s(6)
                                    Rectangle { Layout.preferredWidth: window.s(30); Layout.fillHeight: true; radius: window.s(8); color: toolMa.containsMouse ? window.surface1 : "transparent"; border.color: window.toolsPopupOpen ? window.mauve : "transparent"; border.width: 1
Behavior on color { ColorAnimation { duration: 120 } }
                                        Text { anchors.centerIn: parent; text: "+"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(16); color: window.toolsPopupOpen ? window.mauve : window.overlay0; rotation: window.toolsPopupOpen ? 45 : 0
Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
Behavior on color { ColorAnimation { duration: 200 } } }
                                        MouseArea { id: toolMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.toolsPopupOpen = !window.toolsPopupOpen } }
                                    Item { Layout.fillWidth: true }
                                    Rectangle { Layout.preferredWidth: window.s(30); Layout.preferredHeight: window.s(30); radius: window.s(8); color: sendMa.containsMouse ? window.modeColor1 : window.surface1
Behavior on color { ColorAnimation { duration: 120 } }
                                        Text { anchors.centerIn: parent; text: "󰒊"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(15); color: sendMa.containsMouse ? window.crust : window.text }
                                        MouseArea { id: sendMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (inputField.text.trim() !== "" && !window.isLoading) { window.sendMessage(inputField.text.trim()); inputField.text = ""; } } } }
                                }
                            }
                        }
                    }
                }

                // ══════════════════════════════════════
                // NOTES MODE (Obsidian) — unchanged
                // ══════════════════════════════════════
                Item { Layout.fillWidth: true; Layout.fillHeight: true; visible: window.activeMode === "notes"
                    ColumnLayout { anchors.fill: parent; spacing: window.s(8); opacity: introChat
                        Item { Layout.fillWidth: true; Layout.fillHeight: true; visible: window.notesSubMode === "menu"
                            ColumnLayout { anchors.fill: parent; spacing: window.s(8)
                                RowLayout { Layout.fillWidth: true; spacing: window.s(8)
Item { Layout.fillWidth: true }
                                    Rectangle { Layout.preferredWidth: window.s(30); Layout.preferredHeight: window.s(28); radius: window.s(8); color: newNoteMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"; border.color: newNoteMa.containsMouse ? window.green : Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.5); border.width: 1
Behavior on color { ColorAnimation { duration: 120 } }
                                        Text { anchors.centerIn: parent; text: "󰐕"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(16); color: window.green }
                                        MouseArea { id: newNoteMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.createNewNote() } } }
                                Text { Layout.alignment: Qt.AlignHCenter; visible: window.notesLoading; text: "Loading vault..."; font.family: "JetBrains Mono"; font.pixelSize: window.s(12); color: window.overlay0 }
                                Item { Layout.fillWidth: true; Layout.fillHeight: true; visible: !window.notesLoading && vaultNotes.count === 0
                                    ColumnLayout { anchors.centerIn: parent; spacing: window.s(12)
                                        Text { text: "󰠮"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(40); color: window.overlay0; Layout.alignment: Qt.AlignHCenter }
                                        Text { text: "No notes yet"; font.family: "JetBrains Mono"; font.pixelSize: window.s(13); color: window.overlay0; Layout.alignment: Qt.AlignHCenter }
                                        Text { text: "Tap + to create your first note"; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.overlay0; Layout.alignment: Qt.AlignHCenter } } }
                                ListView { id: vaultListView; Layout.fillWidth: true; Layout.fillHeight: true; visible: !window.notesLoading && vaultNotes.count > 0; model: vaultNotes; clip: true; spacing: window.s(4); boundsBehavior: Flickable.StopAtBounds
                                    ScrollBar.vertical: ScrollBar { width: window.s(3); policy: ScrollBar.AsNeeded; contentItem: Rectangle { implicitWidth: window.s(3); radius: window.s(1); color: window.surface2 } }
                                    delegate: Rectangle { width: ListView.view.width; height: noteItemCol.implicitHeight + window.s(16); radius: window.s(8)
                                        color: noteItemMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.6) : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.35)
                                        border.color: noteItemMa.containsMouse ? Qt.rgba(window.peach.r, window.peach.g, window.peach.b, 0.5) : "transparent"; border.width: 1
Behavior on color { ColorAnimation { duration: 100 } }
Behavior on border.color { ColorAnimation { duration: 100 } }
                                        ColumnLayout { id: noteItemCol; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: window.s(8); spacing: window.s(3)
                                            RowLayout { Layout.fillWidth: true; spacing: window.s(6)
Text { text: "󰈙"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(12); color: window.peach }
                                                Text { text: model.name; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(11); color: noteItemMa.containsMouse ? window.text : window.subtext0; elide: Text.ElideRight; Layout.fillWidth: true
Behavior on color { ColorAnimation { duration: 100 } } }
                                                Text { visible: model.folder !== ""; text: model.folder; font.family: "JetBrains Mono"; font.pixelSize: window.s(8); color: window.overlay0 } }
                                            Text { visible: model.preview !== ""; text: model.preview; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.overlay0; Layout.fillWidth: true; elide: Text.ElideRight; maximumLineCount: 1 } }
                                        MouseArea { id: noteItemMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.readNote(model.filepath, model.name) } } }
                                RowLayout { Layout.fillWidth: true; spacing: window.s(6); visible: !window.notesLoading && vaultNotes.count > 0
                                    Text { text: vaultNotes.count + " notes"; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.overlay0; Layout.fillWidth: true }
                                    // Daily note (Obsidian)
                                    Rectangle { Layout.preferredWidth: dailyRow.implicitWidth + window.s(14); Layout.preferredHeight: window.s(24); radius: window.s(6); color: dailyMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"
Behavior on color { ColorAnimation { duration: 100 } }
                                        Row { id: dailyRow; anchors.centerIn: parent; spacing: window.s(4)
Text { text: "󰃭"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(12); color: window.mauve; anchors.verticalCenter: parent.verticalCenter }
Text { text: "Daily"; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.subtext0; anchors.verticalCenter: parent.verticalCenter } }
                                        MouseArea { id: dailyMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.obsidianDaily() } }
                                    // Open the Obsidian app
                                    Rectangle { Layout.preferredWidth: obsRow.implicitWidth + window.s(14); Layout.preferredHeight: window.s(24); radius: window.s(6); color: obsMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"
Behavior on color { ColorAnimation { duration: 100 } }
                                        Row { id: obsRow; anchors.centerIn: parent; spacing: window.s(4)
Text { text: "󰠮"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(12); color: window.mauve; anchors.verticalCenter: parent.verticalCenter }
Text { text: "Obsidian"; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.subtext0; anchors.verticalCenter: parent.verticalCenter } }
                                        MouseArea { id: obsMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.obsidianOpenNote("") } }
                                    Rectangle { Layout.preferredWidth: refreshRow.implicitWidth + window.s(14); Layout.preferredHeight: window.s(24); radius: window.s(6); color: refreshMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"
Behavior on color { ColorAnimation { duration: 100 } }
                                        Row { id: refreshRow; anchors.centerIn: parent; spacing: window.s(4)
Text { text: "󰑐"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(12); color: window.sapphire; anchors.verticalCenter: parent.verticalCenter }
Text { text: "Refresh"; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.subtext0; anchors.verticalCenter: parent.verticalCenter } }
                                        MouseArea { id: refreshMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.fetchVaultNotes() } } }
                            }
                        }
                        // Note editor
                        Item { Layout.fillWidth: true; Layout.fillHeight: true; visible: window.notesSubMode === "edit"
                            ColumnLayout { anchors.fill: parent; spacing: window.s(8)
                                RowLayout { Layout.fillWidth: true; spacing: window.s(8)
                                    Rectangle { Layout.preferredWidth: window.s(30); Layout.preferredHeight: window.s(28); radius: window.s(8); color: backMenuMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"
Behavior on color { ColorAnimation { duration: 80 } }
                                        Text { anchors.centerIn: parent; text: "󰁍"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(16); color: window.peach }
                                        MouseArea { id: backMenuMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { window.flushNoteNow(); window.notesSubMode = "menu"; window.fetchVaultNotes(); } } }
                                    // Editable title — rename the note file. Commit on Enter or focus loss.
                                    TextInput { id: noteTitleInput
                                        Layout.fillWidth: true
                                        text: window.selectedNoteTitle
                                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(13); color: window.text
                                        selectByMouse: true; clip: true
                                        onEditingFinished: window.renameCurrentNote(text)
                                        Keys.onReturnPressed: { window.renameCurrentNote(text); noteArea.forceActiveFocus(); }
                                        Text { anchors.fill: parent; visible: parent.text === ""; text: "Untitled"; font: parent.font; color: window.overlay0; verticalAlignment: Text.AlignVCenter } }
                                    Text { visible: window.noteAutoSaved; text: "Saved"; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.green; opacity: window.noteAutoSaved ? 1.0 : 0.0
Behavior on opacity { NumberAnimation { duration: 300 } } }
                                    Rectangle { Layout.preferredWidth: aiExpandRow.implicitWidth + window.s(16); Layout.preferredHeight: window.s(28); radius: window.s(8)
                                        color: window.noteExpanding ? Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.15)
                                             : aiExpandMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8)
                                             : "transparent"
                                        border.color: window.noteExpanding ? window.mauve
                                                    : aiExpandMa.containsMouse ? window.mauve
                                                    : Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.5)
                                        border.width: 1
                                        opacity: noteArea.text.trim() === "" ? 0.4 : 1.0
Behavior on color { ColorAnimation { duration: 120 } }
                                        Row { id: aiExpandRow; anchors.centerIn: parent; spacing: window.s(6)
Text { text: window.noteExpanding ? "󰦖" : "󰚩"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(13); color: window.mauve; anchors.verticalCenter: parent.verticalCenter
    RotationAnimation on rotation { running: window.noteExpanding; loops: Animation.Infinite; from: 0; to: 360; duration: 1200 } }
Text { text: window.noteExpanding ? "Thinking…" : "Expand with AI"; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: aiExpandMa.containsMouse || window.noteExpanding ? window.text : window.subtext0; anchors.verticalCenter: parent.verticalCenter } }
                                        MouseArea { id: aiExpandMa; anchors.fill: parent; hoverEnabled: true
                                            cursorShape: window.noteExpanding || noteArea.text.trim() === "" ? Qt.ArrowCursor : Qt.PointingHandCursor
                                            enabled: !window.noteExpanding && noteArea.text.trim() !== ""
                                            onClicked: window.expandNoteInPlace() } } }
                                // Borderless editor — write directly on the popup background.
                                Item { Layout.fillWidth: true; Layout.fillHeight: true
                                    TextEdit { id: noteArea; anchors.fill: parent; font.family: "JetBrains Mono"; font.pixelSize: window.s(12); color: window.text; wrapMode: TextEdit.Wrap; selectByMouse: true; selectionColor: Qt.rgba(window.peach.r, window.peach.g, window.peach.b, 0.3)
                                        Text { anchors.left: parent.left; anchors.top: parent.top; visible: !noteArea.text && !noteArea.activeFocus; text: "Start typing..."; font: noteArea.font; color: window.overlay0 }
                                        onTextChanged: { if (window.notesSubMode === "edit" && window.currentNoteFilepath !== "") autoSaveTimer.restart(); } } }
                            }
                        }
                    }
                }

                // ══════════════════════════════════════
                // LEARN MODE — unchanged
                // ══════════════════════════════════════
                Item { Layout.fillWidth: true; Layout.fillHeight: true; visible: window.activeMode === "learn"
                    ColumnLayout { anchors.fill: parent; spacing: window.s(8); opacity: introChat
                        // HOME
                        Item { Layout.fillWidth: true; Layout.fillHeight: true; visible: window.learnSubMode === "home"
                            ColumnLayout { anchors.fill: parent; spacing: window.s(10)
                                RowLayout { Layout.fillWidth: true; spacing: window.s(8)
Item { Layout.fillWidth: true }
                                    Rectangle { visible: learnedTerms.count > 0; Layout.preferredWidth: vocabBtnRow.implicitWidth + window.s(16); Layout.preferredHeight: window.s(28); radius: window.s(8); color: vocabBtnMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"; border.color: vocabBtnMa.containsMouse ? window.yellow : Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.5); border.width: 1
Behavior on color { ColorAnimation { duration: 120 } }
                                        Row { id: vocabBtnRow; anchors.centerIn: parent; spacing: window.s(5)
Text { text: "󰗊"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(13); color: window.yellow; anchors.verticalCenter: parent.verticalCenter }
Text { text: learnedTerms.count + " words"; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: vocabBtnMa.containsMouse ? window.text : window.subtext0; anchors.verticalCenter: parent.verticalCenter } }
                                        MouseArea { id: vocabBtnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.learnSubMode = "vocab" } } }
                                // No book — Kavita browser
                                Item { Layout.fillWidth: true; Layout.fillHeight: true; visible: !window.bookLoaded
                                    ColumnLayout { anchors.fill: parent; spacing: window.s(10)
                                        Item { Layout.fillWidth: true; Layout.fillHeight: true; visible: !window.kavitaConnected && !window.kavitaLoading
                                            ColumnLayout { anchors.centerIn: parent; spacing: window.s(16); width: parent.width * 0.85
                                                Text { text: "󰂺"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(48); color: window.green; Layout.alignment: Qt.AlignHCenter; opacity: 0.6 }
                                                Text { text: "Connect to Kavita"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(14); color: window.text; Layout.alignment: Qt.AlignHCenter }
                                                Text { text: "Add your Kavita API key to ai_config.json to browse textbooks from your library."; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.subtext0; Layout.fillWidth: true; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter }
                                                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: kavitaHintCol.implicitHeight + window.s(20); radius: window.s(10); color: Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.45); border.color: Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.5); border.width: 1
                                                    ColumnLayout { id: kavitaHintCol; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: window.s(10); spacing: window.s(6)
                                                        Text { text: "~/.config/hypr/ai_config.json"; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); font.weight: Font.Bold; color: window.overlay1 }
                                                        Text { text: '  "kavita_url": "http://localhost:5000"\n  "kavita_api_key": "your-api-key"'; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.green; Layout.fillWidth: true; wrapMode: Text.Wrap } } }
                                                Rectangle { Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: retryRow.implicitWidth + window.s(20); Layout.preferredHeight: window.s(32); radius: window.s(8); color: retryMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.5); border.color: retryMa.containsMouse ? window.green : Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.5); border.width: 1
Behavior on color { ColorAnimation { duration: 120 } }
                                                    Row { id: retryRow; anchors.centerIn: parent; spacing: window.s(6)
Text { text: "󰑐"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(13); color: window.green; anchors.verticalCenter: parent.verticalCenter }
Text { text: "Reconnect"; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: retryMa.containsMouse ? window.text : window.subtext0; anchors.verticalCenter: parent.verticalCenter } }
                                                    MouseArea { id: retryMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { configReader.running = false; configReader.running = true; } } } } }
                                        Item { Layout.fillWidth: true; Layout.fillHeight: true; visible: window.kavitaConnected
                                            ColumnLayout { anchors.fill: parent; spacing: window.s(8)
                                                RowLayout { Layout.fillWidth: true; spacing: window.s(8)
Text { text: "󰂺"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(16); color: window.green }
Text { text: "Textbooks"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(13); color: window.text }
Rectangle { Layout.preferredWidth: window.s(8); Layout.preferredHeight: window.s(8); radius: window.s(4); color: window.green }
Item { Layout.fillWidth: true }
                                                    Rectangle { Layout.preferredWidth: window.s(28); Layout.preferredHeight: window.s(28); radius: window.s(8); color: kavRefreshMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"
Behavior on color { ColorAnimation { duration: 80 } }
Text { anchors.centerIn: parent; text: "󰑐"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(14); color: window.sapphire }
MouseArea { id: kavRefreshMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.kavitaFetchSeries() } } }
                                                Text { visible: window.kavitaLoading || window.learnLoading; text: window.learnLoading ? "Downloading & processing..." : "Loading library..."; font.family: "JetBrains Mono"; font.pixelSize: window.s(11); color: window.overlay0; Layout.alignment: Qt.AlignHCenter }
                                                Text { visible: !window.kavitaLoading && !window.learnLoading && kavitaSeries.count === 0; text: "No books found in your Textbooks library."; font.family: "JetBrains Mono"; font.pixelSize: window.s(11); color: window.overlay0; Layout.alignment: Qt.AlignHCenter; Layout.topMargin: window.s(20) }
                                                ListView { Layout.fillWidth: true; Layout.fillHeight: true; visible: !window.kavitaLoading && !window.learnLoading && kavitaSeries.count > 0; model: kavitaSeries; clip: true; spacing: window.s(4); boundsBehavior: Flickable.StopAtBounds
                                                    ScrollBar.vertical: ScrollBar { width: window.s(3); policy: ScrollBar.AsNeeded; contentItem: Rectangle { implicitWidth: window.s(3); radius: window.s(1); color: window.surface2 } }
                                                    delegate: Rectangle { width: ListView.view.width; height: kavSeriesCol.implicitHeight + window.s(16); radius: window.s(8); color: kavSeriesMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.6) : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.35); border.color: kavSeriesMa.containsMouse ? Qt.rgba(window.green.r, window.green.g, window.green.b, 0.5) : "transparent"; border.width: 1
Behavior on color { ColorAnimation { duration: 100 } }
Behavior on border.color { ColorAnimation { duration: 100 } }
                                                        ColumnLayout { id: kavSeriesCol; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: window.s(10); spacing: window.s(3)
                                                            RowLayout { Layout.fillWidth: true; spacing: window.s(8)
Text { text: "󰂺"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(14); color: window.green }
Text { text: model.name; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(11); color: kavSeriesMa.containsMouse ? window.text : window.subtext0; elide: Text.ElideRight; Layout.fillWidth: true
Behavior on color { ColorAnimation { duration: 100 } } } }
                                                            RowLayout { Layout.fillWidth: true; spacing: window.s(8)
Text { visible: model.libraryName !== ""; text: model.libraryName; font.family: "JetBrains Mono"; font.pixelSize: window.s(8); color: window.overlay0 }
Text { visible: model.pages > 0; text: model.pages + " pages"; font.family: "JetBrains Mono"; font.pixelSize: window.s(8); color: window.overlay0 } } }
                                                        MouseArea { id: kavSeriesMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.learnFromKavitaSeries(model.seriesId, model.name, model.format || 0) } } }
                                                Text { visible: kavitaSeries.count > 0; text: kavitaSeries.count + " books"; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.overlay0 }
                                                // ── Audiobook play/pause bar ──
                                                // Sits after the books section. Toggles the companion/last audiobook
                                                // via mpv (which the TopBar media module controls over MPRIS).
                                                // Resumes from the position persisted in Config.
                                                Rectangle {
                                                    visible: Config.audioBookChapterId > 0 || window.kavitaAudioChapterId > 0 || window.audioPlaying
                                                    Layout.fillWidth: true; Layout.preferredHeight: window.s(40); Layout.topMargin: window.s(6)
                                                    radius: window.s(10)
                                                    color: Qt.rgba(window.pink.r, window.pink.g, window.pink.b, 0.12)
                                                    border.color: Qt.rgba(window.pink.r, window.pink.g, window.pink.b, 0.35); border.width: 1
                                                    RowLayout {
                                                        anchors.fill: parent; anchors.leftMargin: window.s(10); anchors.rightMargin: window.s(10); spacing: window.s(10)
                                                        // Play / pause toggle
                                                        Rectangle {
                                                            Layout.preferredWidth: window.s(30); Layout.preferredHeight: window.s(30); radius: window.s(15)
                                                            color: audioPlayMa.containsMouse ? window.pink : Qt.rgba(window.pink.r, window.pink.g, window.pink.b, 0.25)
                                                            Behavior on color { ColorAnimation { duration: 120 } }
                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: window.audioPlaying ? "󰏤" : "󰐊"
                                                                font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(15)
                                                                color: audioPlayMa.containsMouse ? window.crust : window.pink
                                                            }
                                                            MouseArea {
                                                                id: audioPlayMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    if (window.audioPlaying) {
                                                                        window.audioToggle();   // pause
                                                                    } else if (window.kavitaAudioChapterId > 0) {
                                                                        window.audioToggle();   // resume current
                                                                    } else if (Config.audioBookChapterId > 0) {
                                                                        // Resume the persisted audiobook from its saved position.
                                                                        window.audioPlayChapter(Config.audioBookChapterId, Config.audioBookTitle || "Audiobook", Config.audioBookPosMs, -1);
                                                                    }
                                                                }
                                                            }
                                                        }
                                                        ColumnLayout {
                                                            Layout.fillWidth: true; spacing: -2
                                                            Text {
                                                                text: window.audioTitle !== "" ? window.audioTitle : (Config.audioBookTitle !== "" ? Config.audioBookTitle : "Audiobook")
                                                                font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(10)
                                                                color: window.text; elide: Text.ElideRight; Layout.fillWidth: true
                                                            }
                                                            Text {
                                                                text: window.audioPlaying ? "Playing · controllable from the top bar" : "Paused"
                                                                font.family: "JetBrains Mono"; font.pixelSize: window.s(8); color: window.overlay1
                                                            }
                                                        }
                                                        // Stop
                                                        Rectangle {
                                                            Layout.preferredWidth: window.s(26); Layout.preferredHeight: window.s(26); radius: window.s(8)
                                                            color: audioStopMa.containsMouse ? Qt.rgba(window.red.r, window.red.g, window.red.b, 0.25) : "transparent"
                                                            Text { anchors.centerIn: parent; text: "󰓛"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(12); color: audioStopMa.containsMouse ? window.red : window.overlay0 }
                                                            MouseArea { id: audioStopMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.audioStop() }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                // Book loaded
                                Item { Layout.fillWidth: true; Layout.fillHeight: true; visible: window.bookLoaded
                                    ColumnLayout { anchors.fill: parent; spacing: window.s(10)
                                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: window.s(70); radius: window.s(12); color: Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.45); border.color: Qt.rgba(window.green.r, window.green.g, window.green.b, 0.3); border.width: 1
                                            RowLayout { anchors.fill: parent; anchors.margins: window.s(12); spacing: window.s(12)
                                                Rectangle { Layout.preferredWidth: window.s(46); Layout.preferredHeight: window.s(46); radius: window.s(10); gradient: Gradient { GradientStop { position: 0.0; color: window.green }
GradientStop { position: 1.0; color: window.teal } }
Text { anchors.centerIn: parent; text: "󰂺"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(22); color: window.crust } }
                                                ColumnLayout { Layout.fillWidth: true; spacing: window.s(4)
                                                    Text { text: window.bookTitle; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(13); color: window.text; elide: Text.ElideRight; Layout.fillWidth: true }
                                                    Text { text: "Chapter " + (window.currentChapter + 1) + " of " + window.totalChapters; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.subtext0 }
                                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: window.s(4); radius: window.s(2); color: Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.5)
                                                        Rectangle { width: parent.width * ((window.currentChapter + 1) / Math.max(window.totalChapters, 1)); height: parent.height; radius: parent.radius; gradient: Gradient { orientation: Gradient.Horizontal
GradientStop { position: 0.0; color: window.green }
GradientStop { position: 1.0; color: window.teal } }
Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutQuart } } } } } } }
                                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: window.s(44); radius: window.s(10); gradient: Gradient { orientation: Gradient.Horizontal
GradientStop { position: 0.0; color: continueMa.containsMouse ? Qt.lighter(window.green, 1.1) : window.green }
GradientStop { position: 1.0; color: continueMa.containsMouse ? Qt.lighter(window.teal, 1.1) : window.teal } }
                                            Row { anchors.centerIn: parent; spacing: window.s(8)
Text { text: "󰐊"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(18); color: window.crust; anchors.verticalCenter: parent.verticalCenter }
Text { text: "Continue Lesson"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(13); color: window.crust; anchors.verticalCenter: parent.verticalCenter } }
                                            MouseArea { id: continueMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.startLesson() } }
                                        ListView { Layout.fillWidth: true; Layout.fillHeight: true; model: bookChapters; clip: true; spacing: window.s(3); boundsBehavior: Flickable.StopAtBounds
                                            ScrollBar.vertical: ScrollBar { width: window.s(3); policy: ScrollBar.AsNeeded; contentItem: Rectangle { implicitWidth: window.s(3); radius: window.s(1); color: window.surface2 } }
                                            delegate: Rectangle { width: ListView.view.width; height: window.s(36); radius: window.s(8); color: chItemMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.6) : (model.chIndex === window.currentChapter ? Qt.rgba(window.green.r, window.green.g, window.green.b, 0.12) : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.25)); border.color: model.chIndex === window.currentChapter ? Qt.rgba(window.green.r, window.green.g, window.green.b, 0.4) : "transparent"; border.width: 1
Behavior on color { ColorAnimation { duration: 100 } }
                                                RowLayout { anchors.fill: parent; anchors.margins: window.s(8); spacing: window.s(8)
Text { text: model.chIndex <= window.currentChapter ? "󰄬" : "󰝦"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(12); color: model.chIndex < window.currentChapter ? window.green : model.chIndex === window.currentChapter ? window.teal : window.overlay0 }
Text { text: model.title; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); font.weight: model.chIndex === window.currentChapter ? Font.Bold : Font.Medium; color: model.chIndex <= window.currentChapter ? window.text : window.subtext0; elide: Text.ElideRight; Layout.fillWidth: true } }
                                                MouseArea { id: chItemMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { window.currentChapter = model.chIndex; window.saveLearnState(); window.startLesson(); } } } }
                                        RowLayout { Layout.fillWidth: true
Text { text: learnedTerms.count + " terms learned"; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.overlay0; Layout.fillWidth: true }
                                            Rectangle { Layout.preferredWidth: newBookRow.implicitWidth + window.s(14); Layout.preferredHeight: window.s(24); radius: window.s(6); color: newBookMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"
Behavior on color { ColorAnimation { duration: 100 } }
                                                Row { id: newBookRow; anchors.centerIn: parent; spacing: window.s(4)
Text { text: "󰐕"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(11); color: window.sapphire; anchors.verticalCenter: parent.verticalCenter }
Text { text: "New book"; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.subtext0; anchors.verticalCenter: parent.verticalCenter } }
                                                MouseArea { id: newBookMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (learnedTerms.count > 0) window.exportVocabToObsidian(); window.bookLoaded = false; } } } }
                                    }
                                }
                            }
                        }
                        // LESSON
                        Item { Layout.fillWidth: true; Layout.fillHeight: true; visible: window.learnSubMode === "lesson"
                            ColumnLayout { anchors.fill: parent; spacing: window.s(8)
                                RowLayout { Layout.fillWidth: true; spacing: window.s(8)
                                    Rectangle { Layout.preferredWidth: window.s(30); Layout.preferredHeight: window.s(28); radius: window.s(8); color: learnBackMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"
Behavior on color { ColorAnimation { duration: 80 } }
Text { anchors.centerIn: parent; text: "󰁍"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(16); color: window.green }
MouseArea { id: learnBackMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.learnSubMode = "home" } }
                                    ColumnLayout { Layout.fillWidth: true; spacing: window.s(2)
Text { text: window.currentChapterTitle; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(12); color: window.text; elide: Text.ElideRight; Layout.fillWidth: true }
Text { text: "Ch " + (window.currentChapter + 1) + "/" + window.totalChapters; font.family: "JetBrains Mono"; font.pixelSize: window.s(8); color: window.overlay0 } }
                                    Rectangle { visible: learnedTerms.count > 0; Layout.preferredWidth: lessonVocRow.implicitWidth + window.s(12); Layout.preferredHeight: window.s(24); radius: window.s(6); color: lessonVocMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"
Behavior on color { ColorAnimation { duration: 100 } }
                                        Row { id: lessonVocRow; anchors.centerIn: parent; spacing: window.s(4)
Text { text: "󰗊"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(11); color: window.yellow; anchors.verticalCenter: parent.verticalCenter }
Text { text: learnedTerms.count.toString(); font.family: "JetBrains Mono"; font.pixelSize: window.s(9); font.weight: Font.Bold; color: window.yellow; anchors.verticalCenter: parent.verticalCenter } }
                                        MouseArea { id: lessonVocMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.learnSubMode = "vocab" } }
                                    Rectangle { visible: window.currentChapter < window.totalChapters - 1; Layout.preferredWidth: window.s(30); Layout.preferredHeight: window.s(28); radius: window.s(8); color: nextChMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"; border.color: nextChMa.containsMouse ? window.teal : Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.5); border.width: 1
Behavior on color { ColorAnimation { duration: 80 } }
Text { anchors.centerIn: parent; text: "󰒭"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(16); color: window.teal }
MouseArea { id: nextChMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.advanceChapter() } } }
                                ListView { id: lessonView; Layout.fillWidth: true; Layout.fillHeight: true; model: lessonChat; clip: true; spacing: window.s(8); onCountChanged: positionViewAtEnd()
                                    ScrollBar.vertical: ScrollBar { width: window.s(3); policy: ScrollBar.AsNeeded; contentItem: Rectangle { implicitWidth: window.s(3); radius: window.s(1); color: window.surface2 } }
                                    delegate: Rectangle { width: ListView.view.width; height: lessonMsgCol.implicitHeight + window.s(20); color: model.role === "assistant" ? Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.3) : "transparent"; radius: window.s(8)
                                        ColumnLayout { id: lessonMsgCol; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: window.s(10); spacing: window.s(4)
                                            RowLayout { spacing: window.s(6)
Text { text: model.role === "user" ? "󰀄" : "󰗊"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(13); color: model.role === "user" ? window.blue : window.green }
Text { text: model.role === "user" ? "You" : "Tutor"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(10); color: model.role === "user" ? window.blue : window.green } }
                                            TextEdit { text: { if (model.role === "assistant" && index === lessonChat.count - 1) return window.learnDisplayedResponse; return model.content; }
font.family: "JetBrains Mono"; font.pixelSize: window.s(11); color: window.text; Layout.fillWidth: true; wrapMode: TextEdit.Wrap; textFormat: TextEdit.PlainText
readOnly: true; selectByMouse: true; selectByKeyboard: true; persistentSelection: true
selectionColor: Qt.rgba(window.green.r, window.green.g, window.green.b, 0.3) } } } }
                                RowLayout { Layout.fillWidth: true; Layout.preferredHeight: window.s(24); visible: window.learnLoading; spacing: window.s(8); Layout.leftMargin: window.s(10)
                                    Text { text: "󰗊"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(14); color: window.green }
                                    Text { text: "Teaching"; font.family: "JetBrains Mono"; font.pixelSize: window.s(11); color: window.overlay1; property int dots: 0
Timer { interval: 400; repeat: true; running: window.learnLoading; onTriggered: parent.dots = (parent.dots + 1) % 4 }
Component.onCompleted: text = Qt.binding(function() { return "Teaching" + ".".repeat(dots); }) } }
                                Text { visible: window.voiceTranscript !== "" && window.voiceTranscript.startsWith("["); text: window.voiceTranscript; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.peach; Layout.fillWidth: true; wrapMode: Text.Wrap }
                                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: window.s(44); radius: window.s(12); color: Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.6); border.color: learnInput.activeFocus ? window.green : Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.6); border.width: learnInput.activeFocus ? 2 : 1
Behavior on border.color { ColorAnimation { duration: 200 } }
                                    RowLayout { anchors.fill: parent; anchors.margins: window.s(6); spacing: window.s(6)
                                        Rectangle { Layout.preferredWidth: window.s(32); Layout.preferredHeight: window.s(32); radius: window.s(10); color: window.isRecording ? window.red : (micMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent")
Behavior on color { ColorAnimation { duration: 120 } }
                                            Rectangle { anchors.fill: parent; radius: parent.radius; color: window.red; visible: window.isRecording; opacity: micPulse.running ? 0.3 : 0
Behavior on opacity { NumberAnimation { duration: 600 } }
SequentialAnimation on opacity { id: micPulse; running: window.isRecording; loops: Animation.Infinite
NumberAnimation { to: 0.5; duration: 600 }
NumberAnimation { to: 0.1; duration: 600 } } }
                                            Text { anchors.centerIn: parent; text: window.isRecording ? "󰍬" : "󰍮"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(16); color: window.isRecording ? window.crust : (micMa.containsMouse ? window.green : window.overlay1)
Behavior on color { ColorAnimation { duration: 120 } } }
                                            MouseArea { id: micMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (window.isRecording) window.stopRecording(); else window.startRecording(); } } }
                                        TextInput { id: learnInput; Layout.fillWidth: true; Layout.fillHeight: true; verticalAlignment: TextInput.AlignVCenter; font.family: "JetBrains Mono"; font.pixelSize: window.s(12); color: window.text; clip: true; selectByMouse: true; leftPadding: window.s(4); selectionColor: Qt.rgba(window.green.r, window.green.g, window.green.b, 0.3)
                                            Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; leftPadding: window.s(4); visible: !learnInput.text && !learnInput.activeFocus; text: "Type or speak..."; font: learnInput.font; color: window.overlay0 }
                                            Keys.onReturnPressed: { if (text.trim() !== "" && !window.learnLoading) { window.sendLearnMessage(text.trim()); text = ""; } } }
                                        Rectangle { Layout.preferredWidth: window.s(32); Layout.preferredHeight: window.s(32); radius: window.s(10); color: learnSendMa.containsMouse ? window.green : Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8)
Behavior on color { ColorAnimation { duration: 120 } }
Text { anchors.centerIn: parent; text: "󰒊"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(15); color: learnSendMa.containsMouse ? window.crust : window.text }
                                            MouseArea { id: learnSendMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (learnInput.text.trim() !== "" && !window.learnLoading) { window.sendLearnMessage(learnInput.text.trim()); learnInput.text = ""; } } } }
                                    }
                                }
                            }
                        }
                        // VOCAB
                        Item { Layout.fillWidth: true; Layout.fillHeight: true; visible: window.learnSubMode === "vocab"
                            ColumnLayout { anchors.fill: parent; spacing: window.s(8)
                                RowLayout { Layout.fillWidth: true; spacing: window.s(8)
                                    Rectangle { Layout.preferredWidth: window.s(30); Layout.preferredHeight: window.s(28); radius: window.s(8); color: vocBackMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"
Behavior on color { ColorAnimation { duration: 80 } }
Text { anchors.centerIn: parent; text: "󰁍"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(16); color: window.green }
MouseArea { id: vocBackMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.learnSubMode = "home" } }
                                    Text { text: "󰗊"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(18); color: window.yellow }
Text { text: "Vocabulary"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(14); color: window.text }
Item { Layout.fillWidth: true }
Text { text: learnedTerms.count + " terms"; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.overlay0 } }
                                Text { visible: learnedTerms.count === 0; text: "No vocabulary learned yet. Start a lesson to build your word list!"; font.family: "JetBrains Mono"; font.pixelSize: window.s(11); color: window.overlay0; Layout.fillWidth: true; wrapMode: Text.Wrap; Layout.alignment: Qt.AlignHCenter; horizontalAlignment: Text.AlignHCenter; Layout.topMargin: window.s(40) }
                                ListView { Layout.fillWidth: true; Layout.fillHeight: true; visible: learnedTerms.count > 0; model: learnedTerms; clip: true; spacing: window.s(4); boundsBehavior: Flickable.StopAtBounds
                                    ScrollBar.vertical: ScrollBar { width: window.s(3); policy: ScrollBar.AsNeeded; contentItem: Rectangle { implicitWidth: window.s(3); radius: window.s(1); color: window.surface2 } }
                                    delegate: Rectangle { width: ListView.view.width; height: window.s(52); radius: window.s(8); color: Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.35)
                                        RowLayout { anchors.fill: parent; anchors.margins: window.s(10); spacing: window.s(10)
                                            Rectangle { Layout.preferredWidth: window.s(6); Layout.preferredHeight: window.s(30); radius: window.s(3); color: model.mastery >= 4 ? window.green : model.mastery >= 2 ? window.yellow : window.peach }
                                            ColumnLayout { Layout.fillWidth: true; spacing: window.s(2)
RowLayout { spacing: window.s(8)
Text { text: model.term; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(13); color: window.text }
Text { visible: model.reading !== "" && model.reading !== model.term; text: model.reading; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.subtext0 } }
Text { text: model.meaning; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.overlay1; elide: Text.ElideRight; Layout.fillWidth: true } } } } }
                            }
                        }
                    }
                }

                // ══════════════════════════════════════
                // CHESS MODE (Lichess)
                // ══════════════════════════════════════
                Item { Layout.fillWidth: true; Layout.fillHeight: true; visible: window.activeMode === "chess"
                    ColumnLayout { anchors.fill: parent; spacing: window.s(6); opacity: introChat

                        // ── MENU ──
                        Item { Layout.fillWidth: true; Layout.fillHeight: true
                            visible: window.chessStatus === "menu"

                            ColumnLayout {
                                anchors.centerIn: parent; spacing: window.s(14); width: parent.width * 0.9

                                // Game-creation error banner (token scope, etc.)
                                Rectangle {
                                    visible: window.chessCreateError !== ""
                                    Layout.fillWidth: true; Layout.preferredHeight: errBannerText.implicitHeight + window.s(14)
                                    radius: window.s(8); color: Qt.rgba(window.red.r, window.red.g, window.red.b, 0.12)
                                    border.color: Qt.rgba(window.red.r, window.red.g, window.red.b, 0.4); border.width: 1
                                    Text {
                                        id: errBannerText
                                        anchors.fill: parent; anchors.margins: window.s(7)
                                        text: window.chessCreateError
                                        font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.red
                                        wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                    }
                                }

                                // No token warning
                                Text {
                                    visible: window.lichessToken === ""
                                    text: "Add lichess_token to ai_config.json\nlichess.org/account/oauth/token"
                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.subtext0
                                    Layout.fillWidth: true; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                                }

                                // Missing-scope warning — board:play is required to
                                // play moves / seek games, challenge:write to start a
                                // game vs Stockfish. Tapping opens a pre-filled token
                                // creation page with the right scopes ticked.
                                Rectangle {
                                    visible: window.lichessToken !== "" && (!window.chessHasBoardPlay || !window.chessHasChallengeWrite)
                                    Layout.fillWidth: true; Layout.preferredHeight: scopeCol.implicitHeight + window.s(16)
                                    radius: window.s(8); color: Qt.rgba(window.peach.r, window.peach.g, window.peach.b, 0.14)
                                    border.color: Qt.rgba(window.peach.r, window.peach.g, window.peach.b, 0.45); border.width: 1
                                    ColumnLayout { id: scopeCol; anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.margins: window.s(8); spacing: window.s(4)
                                        Text {
                                            Layout.fillWidth: true; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                                            font.family: "JetBrains Mono"; font.pixelSize: window.s(9); font.weight: Font.Bold; color: window.peach
                                            text: "Your token is missing a required scope: " +
                                                  ((!window.chessHasBoardPlay ? "board:play " : "") + (!window.chessHasChallengeWrite ? "challenge:write" : "")).trim()
                                        }
                                        Text {
                                            Layout.fillWidth: true; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                                            font.family: "JetBrains Mono"; font.pixelSize: window.s(8); color: scopeLinkMa.containsMouse ? window.text : window.subtext0
                                            text: "Tap to create a new token with the right scopes, then paste it into ai_config.json and restart."
                                        }
                                        MouseArea { id: scopeLinkMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: Quickshell.execDetached(["xdg-open",
                                                "https://lichess.org/account/oauth/token/create?scopes[]=board:play&scopes[]=challenge:write&scopes[]=puzzle:read&description=imperative-dots"]) }
                                    }
                                }

                                // ── Correspondence board (full size, like the in-game
                                // board). It's the primary surface; the other game
                                // options sit below it. Tap a piece to move — if no
                                // correspondence game is active that seeks a 14-day
                                // game and plays the move; if one is live it mirrors
                                // that game and submits directly into it.
                                Text {
                                    visible: window.lichessToken !== ""
                                    text: "Correspondence"
                                    font.family: "JetBrains Mono"; font.weight: Font.Bold
                                    font.pixelSize: window.s(11); color: window.overlay1
                                }
                                Item {
                                    visible: window.lichessToken !== ""
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: corrBoardCol.implicitHeight
                                    ColumnLayout { id: corrBoardCol; anchors.fill: parent; spacing: window.s(4)
                                        // Full-width 8x8 board, same sizing as the
                                        // in-game board, drawn with the Lichess CDN set.
                                        Rectangle {
                                            Layout.fillWidth: true; Layout.preferredHeight: width
                                            radius: window.s(8); clip: true
                                            border.color: window.chessMenuSelected >= 0 ? window.sapphire : window.surface1; border.width: window.chessMenuSelected >= 0 ? 2 : 1
                                            Behavior on border.color { ColorAnimation { duration: 120 } }
                                            Grid {
                                                id: corrGrid
                                                anchors.fill: parent; anchors.margins: window.s(2)
                                                columns: 8; rows: 8
                                                property real cell: width / 8
                                                // Repaint when the menu board changes (our move, opponent move, or a corr-game refresh).
                                                property int rev: 0
                                                Connections { target: window; function onChessMenuRepaint() { corrGrid.rev++; } }
                                                Repeater {
                                                    model: 64
                                                    delegate: Item {
                                                        width: corrGrid.cell; height: corrGrid.cell
                                                        property int row: Math.floor(index / 8)
                                                        property int col: index % 8
                                                        // Orient by our color when a corr game is live (so our
                                                        // pieces are at the bottom); otherwise white-at-bottom.
                                                        property int realIdx: window.chessMenuIsWhite ? index : (63 - index)
                                                        property var _r: corrGrid.rev   // dependency to force re-eval
                                                        property string pc: window.chessMenuBoard[realIdx] || ""
                                                        property bool isSel: window.chessMenuSelected === realIdx
                                                        property bool isTarget: {
                                                            let _ = corrGrid.rev;
                                                            if (window.chessMenuSelected < 0) return false;
                                                            let tg = window.chessComputeTargetsOn(window.chessMenuBoard, window.chessMenuSelected, window.chessMenuIsWhite ? true : true);
                                                            for (let i = 0; i < tg.length; i++) if (tg[i] === realIdx) return true;
                                                            return false;
                                                        }
                                                        Rectangle { anchors.fill: parent
                                                            color: isSel ? Qt.rgba(window.yellow.r, window.yellow.g, window.yellow.b, 0.55)
                                                                  : (row + col) % 2 === 0 ? Qt.lighter(window.surface2, 1.04) : window.surface0 }
                                                        // Legal-move dot
                                                        Rectangle { anchors.centerIn: parent; visible: isTarget && pc === ""
                                                            width: parent.width * 0.28; height: width; radius: width/2
                                                            color: Qt.rgba(window.green.r, window.green.g, window.green.b, 0.55) }
                                                        Rectangle { anchors.fill: parent; visible: isTarget && pc !== ""; color: "transparent"
                                                            border.color: Qt.rgba(window.green.r, window.green.g, window.green.b, 0.7); border.width: 2; radius: window.s(3) }
                                                        Image {
                                                            anchors.centerIn: parent
                                                            width: parent.width * 0.86; height: width
                                                            visible: pc !== "" && status === Image.Ready
                                                            source: pc !== "" ? window.chessPieceImg(pc) : ""
                                                            sourceSize.width: 128; sourceSize.height: 128
                                                            fillMode: Image.PreserveAspectFit
                                                            asynchronous: true; cache: true; smooth: true
                                                        }
                                                        Text { anchors.centerIn: parent
                                                            visible: pc !== ""
                                                            text: window.chessPieceChar(pc)
                                                            font.pixelSize: parent.width * 0.74
                                                            color: pc >= "A" && pc <= "Z" ? "#fafafa" : "#15151f"
                                                            z: -1 }
                                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                            onClicked: window.chessMenuSquareTapped(realIdx) }
                                                    }
                                                }
                                            }
                                            // Hint shown only when no game is active and nothing selected.
                                            Rectangle { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottomMargin: window.s(6)
                                                visible: !window.chessHasCorrGame && window.chessMenuSelected < 0
                                                radius: window.s(6); color: Qt.rgba(window.crust.r, window.crust.g, window.crust.b, 0.7)
                                                width: hintTxt.implicitWidth + window.s(14); height: hintTxt.implicitHeight + window.s(8)
                                                Text { id: hintTxt; anchors.centerIn: parent; text: "Move a piece to start a correspondence game"
                                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.subtext0 } }
                                        }
                                        Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                                            text: window.chessHasCorrGame
                                                ? (window.chessMenuMyTurn ? "Your move — correspondence" : "Waiting for opponent — correspondence")
                                                : "14 days/move. Move a piece to seek + play it."
                                            font.family: "JetBrains Mono"; font.pixelSize: window.s(8); color: window.overlay0 }
                                    }
                                }

                                // Other game modes, below the board.
                                Text {
                                    visible: window.lichessToken !== ""
                                    text: "Play Online"
                                    font.family: "JetBrains Mono"; font.weight: Font.Bold
                                    font.pixelSize: window.s(11); color: window.overlay1
                                }
                                GridLayout {
                                    visible: window.lichessToken !== ""
                                    Layout.fillWidth: true; columns: 3; columnSpacing: window.s(6); rowSpacing: window.s(6)

                                    Repeater {
                                        model: ListModel {
                                            ListElement { label: "8+0";   desc: "Rapid"; mins: 8;  inc: 0 }
                                            ListElement { label: "10+0";  desc: "Rapid"; mins: 10; inc: 0 }
                                            ListElement { label: "10+5";  desc: "Rapid"; mins: 10; inc: 5 }
                                            ListElement { label: "10+15"; desc: "Rapid"; mins: 10; inc: 15 }
                                            ListElement { label: "15+0";  desc: "Rapid"; mins: 15; inc: 0 }
                                            ListElement { label: "15+10"; desc: "Classical"; mins: 15; inc: 10 }
                                        }
                                        delegate: Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: window.s(60)
                                            radius: window.s(10)
                                            color: hgMa.containsMouse ? window.surface1 : window.surface0
                                            border.color: hgMa.containsMouse ? window.yellow : window.surface1
                                            border.width: 1
                                            Behavior on color { ColorAnimation { duration: 100 } }

                                            ColumnLayout {
                                                anchors.centerIn: parent; spacing: window.s(3)
                                                Text {
                                                    text: label
                                                    font.family: "JetBrains Mono"; font.weight: Font.Black
                                                    font.pixelSize: window.s(15); color: hgMa.containsMouse ? window.yellow : window.text
                                                    Layout.alignment: Qt.AlignHCenter
                                                    Behavior on color { ColorAnimation { duration: 100 } }
                                                }
                                                Text {
                                                    text: desc
                                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(8)
                                                    color: window.overlay0
                                                    Layout.alignment: Qt.AlignHCenter
                                                }
                                            }
                                            MouseArea {
                                                id: hgMa; anchors.fill: parent; hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: window.chessSeekGame(mins, inc)
                                            }
                                        }
                                    }
                                }


                                // Bottom row: [vs Stockfish] [Daily Puzzle]
                                RowLayout {
                                    visible: window.lichessToken !== ""
                                    Layout.fillWidth: true; spacing: window.s(6)

                                    // vs Stockfish — wide button
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: window.s(50)
                                        radius: window.s(10)
                                        color: aiSetupMa.containsMouse ? window.surface1 : window.surface0
                                        border.color: aiSetupMa.containsMouse ? window.peach : window.surface1
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 100 } }

                                        RowLayout {
                                            anchors.centerIn: parent; spacing: window.s(8)
                                            Text {
                                                text: "󰡛"
                                                font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(20)
                                                color: aiSetupMa.containsMouse ? window.peach : window.overlay1
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                            }
                                            ColumnLayout {
                                                spacing: 0
                                                Text {
                                                    text: "vs Stockfish"
                                                    font.family: "JetBrains Mono"; font.weight: Font.Bold
                                                    font.pixelSize: window.s(11)
                                                    color: aiSetupMa.containsMouse ? window.text : window.subtext0
                                                }
                                                Text {
                                                    text: "Choose difficulty"
                                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(8)
                                                    color: window.overlay0
                                                }
                                            }
                                        }
                                        MouseArea {
                                            id: aiSetupMa; anchors.fill: parent; hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: window.chessStatus = "aisetup"
                                        }
                                    }

                                    // Daily Puzzle — square button
                                    Rectangle {
                                        Layout.preferredWidth: window.s(50)
                                        Layout.preferredHeight: window.s(50)
                                        radius: window.s(10)
                                        color: puzzleMa.containsMouse ? window.surface1 : window.surface0
                                        border.color: puzzleMa.containsMouse ? window.green : window.surface1
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 100 } }

                                        ColumnLayout {
                                            anchors.centerIn: parent; spacing: window.s(2)
                                            Text {
                                                text: "󰠱"
                                                font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(18)
                                                color: puzzleMa.containsMouse ? window.green : window.overlay1
                                                Layout.alignment: Qt.AlignHCenter
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                            }
                                            Text {
                                                text: "Puzzle"
                                                font.family: "JetBrains Mono"; font.pixelSize: window.s(7)
                                                color: window.overlay0
                                                Layout.alignment: Qt.AlignHCenter
                                            }
                                        }
                                        MouseArea {
                                            id: puzzleMa; anchors.fill: parent; hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: window.chessFetchPuzzle()
                                        }
                                    }
                                }
                            }
                        }

                        // ── AI SETUP (elo slider) ──
                        Item { Layout.fillWidth: true; Layout.fillHeight: true
                            visible: window.chessStatus === "aisetup"

                            ColumnLayout {
                                anchors.centerIn: parent; spacing: window.s(16); width: parent.width * 0.85

                                // Back
                                RowLayout {
                                    Layout.fillWidth: true; spacing: window.s(8)
                                    Rectangle {
                                        Layout.preferredWidth: window.s(28); Layout.preferredHeight: window.s(28)
                                        radius: window.s(8)
                                        color: aiBackMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"
                                        Behavior on color { ColorAnimation { duration: 80 } }
                                        Text { anchors.centerIn: parent; text: "󰁍"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(15); color: window.yellow }
                                        MouseArea { id: aiBackMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.chessStatus = "menu" }
                                    }
                                    Text {
                                        text: "vs Stockfish"
                                        font.family: "JetBrains Mono"; font.weight: Font.Bold
                                        font.pixelSize: window.s(14); color: window.text
                                    }
                                }

                                // Elo display
                                Text {
                                    text: window.chessAiElo.toString()
                                    font.family: "JetBrains Mono"; font.weight: Font.Black
                                    font.pixelSize: window.s(36); color: window.yellow
                                    Layout.alignment: Qt.AlignHCenter
                                }
                                Text {
                                    text: window.chessAiElo < 1000 ? "Beginner" :
                                          window.chessAiElo < 1400 ? "Casual" :
                                          window.chessAiElo < 1800 ? "Intermediate" :
                                          window.chessAiElo < 2200 ? "Advanced" :
                                          window.chessAiElo < 2600 ? "Expert" : "Maximum"
                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(11)
                                    color: window.overlay1
                                    Layout.alignment: Qt.AlignHCenter
                                }

                                // Slider + Play button on one line
                                RowLayout {
                                    Layout.fillWidth: true; spacing: window.s(8)
                                    Text { text: "800"; font.family: "JetBrains Mono"; font.pixelSize: window.s(8); color: window.overlay0 }
                                    Slider {
                                        id: eloSlider
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: window.s(28)
                                        from: 800; to: 2800; stepSize: 100
                                        live: true
                                        // Set the initial position once instead of binding `value`
                                        // to chessAiElo (a live binding fights the user's drag).
                                        Component.onCompleted: value = window.chessAiElo
                                        onValueChanged: if (pressed || Math.abs(value - window.chessAiElo) >= stepSize) window.chessAiElo = value
                                        onMoved: window.chessAiElo = value
                                        Connections {
                                            target: window
                                            function onChessAiEloChanged() {
                                                if (!eloSlider.pressed && eloSlider.value !== window.chessAiElo)
                                                    eloSlider.value = window.chessAiElo;
                                            }
                                        }

                                        background: Rectangle {
                                            x: eloSlider.leftPadding; y: eloSlider.topPadding + eloSlider.availableHeight / 2 - height / 2
                                            width: eloSlider.availableWidth; height: window.s(6); radius: window.s(3)
                                            color: window.surface1
                                            Rectangle {
                                                width: eloSlider.visualPosition * parent.width; height: parent.height; radius: parent.radius
                                                gradient: Gradient {
                                                    orientation: Gradient.Horizontal
                                                    GradientStop { position: 0.0; color: window.green }
                                                    GradientStop { position: 0.5; color: window.yellow }
                                                    GradientStop { position: 1.0; color: window.red }
                                                }
                                            }
                                        }
                                        handle: Rectangle {
                                            x: eloSlider.leftPadding + eloSlider.visualPosition * (eloSlider.availableWidth - width)
                                            y: eloSlider.topPadding + eloSlider.availableHeight / 2 - height / 2
                                            width: window.s(20); height: window.s(20); radius: window.s(10)
                                            color: eloSlider.pressed ? window.yellow : window.text
                                            border.color: window.surface0; border.width: 2
                                        }
                                    }
                                    Text { text: "2800"; font.family: "JetBrains Mono"; font.pixelSize: window.s(8); color: window.overlay0 }

                                    // Play button (inline, right of the slider)
                                    Rectangle {
                                        Layout.preferredWidth: aiPlayRow.implicitWidth + window.s(20)
                                        Layout.preferredHeight: window.s(40)
                                        radius: window.s(10)
                                        opacity: window.chessAiCreating ? 0.7 : 1.0
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: aiPlayMa.containsMouse ? Qt.lighter(window.yellow, 1.1) : window.yellow }
                                            GradientStop { position: 1.0; color: aiPlayMa.containsMouse ? Qt.lighter(window.peach, 1.1) : window.peach }
                                        }
                                        Row {
                                            id: aiPlayRow
                                            anchors.centerIn: parent; spacing: window.s(6)
                                            Text {
                                                text: window.chessAiCreating ? "󰦖" : "󰐊"
                                                font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(16); color: window.crust; anchors.verticalCenter: parent.verticalCenter
                                                RotationAnimation on rotation { running: window.chessAiCreating; loops: Animation.Infinite; from: 0; to: 360; duration: 1000 }
                                            }
                                            Text {
                                                text: window.chessAiCreating ? "Starting…" : ("Play L" + window.chessEloToLevel(window.chessAiElo))
                                                font.family: "JetBrains Mono"; font.weight: Font.Black
                                                font.pixelSize: window.s(12); color: window.crust
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                        MouseArea { id: aiPlayMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            enabled: !window.chessAiCreating
                                            onClicked: window.chessStartAiFromElo() }
                                    }
                                }
                                // Error banner on the setup page (e.g. invalid time control, scope)
                                Rectangle {
                                    visible: window.chessCreateError !== ""
                                    Layout.fillWidth: true; Layout.preferredHeight: aiErrText.implicitHeight + window.s(14)
                                    radius: window.s(8); color: Qt.rgba(window.red.r, window.red.g, window.red.b, 0.12)
                                    border.color: Qt.rgba(window.red.r, window.red.g, window.red.b, 0.4); border.width: 1
                                    Text { id: aiErrText; anchors.fill: parent; anchors.margins: window.s(7)
                                        text: window.chessCreateError; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.red
                                        wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                }
                            }
                        }

                        // ── SEEKING ──
                        Item { Layout.fillWidth: true; Layout.fillHeight: true; visible: window.chessStatus === "seeking"
                            ColumnLayout { anchors.centerIn: parent; spacing: window.s(12)
                                Text { text: "\u265e"; font.pixelSize: window.s(40); color: window.yellow; Layout.alignment: Qt.AlignHCenter
                                    SequentialAnimation on opacity { loops: Animation.Infinite; running: window.chessStatus === "seeking"
                                        NumberAnimation { to: 0.3; duration: 600 }
                                        NumberAnimation { to: 1.0; duration: 600 } } }
                                Text { text: "Finding opponent..."; font.family: "JetBrains Mono"; font.pixelSize: window.s(14); color: window.subtext0; Layout.alignment: Qt.AlignHCenter }
                                Rectangle { Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: cancelSeekRow.implicitWidth + window.s(20); Layout.preferredHeight: window.s(30); radius: window.s(8)
                                    color: cancelSeekMa.containsMouse ? window.surface1 : window.surface0
                                    border.color: cancelSeekMa.containsMouse ? window.red : window.surface1; border.width: 1
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                    Row { id: cancelSeekRow; anchors.centerIn: parent; spacing: window.s(6)
                                        Text { text: "Cancel"; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); font.weight: Font.Bold; color: cancelSeekMa.containsMouse ? window.red : window.subtext0; anchors.verticalCenter: parent.verticalCenter } }
                                    MouseArea { id: cancelSeekMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { chessCreateProc.running = false; window.chessStatus = "menu"; } } }
                            }
                        }

                        // ── PUZZLE ──
                        Item { Layout.fillWidth: true; Layout.fillHeight: true
                            visible: window.chessStatus === "puzzle"

                            ColumnLayout { anchors.fill: parent; spacing: window.s(4)
                                RowLayout { Layout.fillWidth: true; spacing: window.s(6)
                                    Rectangle {
                                        Layout.preferredWidth: window.s(28); Layout.preferredHeight: window.s(28); radius: window.s(8)
                                        color: pzBackMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"
                                        Behavior on color { ColorAnimation { duration: 80 } }
                                        Text { anchors.centerIn: parent; text: "󰁍"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(15); color: window.yellow }
                                        MouseArea { id: pzBackMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.chessStatus = "menu" }
                                    }
                                    Text { text: "Daily Puzzle"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(13); color: window.text }
                                    Item { Layout.fillWidth: true }
                                    Text { visible: window.chessPuzzleRating > 0; text: "Rating: " + window.chessPuzzleRating; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.overlay0 }
                                }
                                // Puzzle board — fancy interactive board (drag + arrows)
                                Item { Layout.fillWidth: true; Layout.preferredHeight: width; Layout.maximumHeight: parent.height - window.s(70)
                                    Loader { anchors.fill: parent; sourceComponent: chessBoardComponent }
                                }
                                // Feedback row: shows whose turn / result, plus a reset button
                                RowLayout { Layout.fillWidth: true; spacing: window.s(6)
                                    Text {
                                        Layout.fillWidth: true
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: window.s(10)
                                        font.weight: window.chessPuzzleFeedback === "" ? Font.Normal : Font.Bold
                                        color: window.chessPuzzleFeedback === "solved" ? window.green
                                             : window.chessPuzzleFeedback === "wrong" ? window.red
                                             : window.chessPuzzleFeedback === "correct" ? window.green
                                             : window.overlay0
                                        text: {
                                            if (window.chessPuzzleFeedback === "solved") return "✓ Solved!";
                                            if (window.chessPuzzleFeedback === "wrong")  return "✗ Not quite — try again";
                                            if (window.chessPuzzleFeedback === "correct") return "✓ Good move";
                                            if (window.chessPuzzleStep === 0) return "Loading position…";
                                            if (window.chessPuzzleStep % 2 === 1) return "Your turn — find the best move for " + (window.chessIsWhite ? "White" : "Black");
                                            return "Opponent is moving…";
                                        }
                                    }
                                    Rectangle {
                                        Layout.preferredWidth: pzResetRow.implicitWidth + window.s(14); Layout.preferredHeight: window.s(26); radius: window.s(6)
                                        color: pzResetMa.containsMouse ? window.surface1 : "transparent"
                                        border.color: pzResetMa.containsMouse ? window.yellow : window.surface1; border.width: 1
                                        visible: window.chessPuzzleStartFen !== ""
                                        Row { id: pzResetRow; anchors.centerIn: parent; spacing: window.s(4)
                                            Text { text: window.chessPuzzleSolved ? "Try Again" : "Reset"
                                                   font.family: "JetBrains Mono"; font.pixelSize: window.s(9)
                                                   color: pzResetMa.containsMouse ? window.yellow : window.subtext0
                                                   anchors.verticalCenter: parent.verticalCenter } }
                                        MouseArea { id: pzResetMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.chessResetPuzzle() }
                                    }
                                    // Fetch a fresh puzzle from /api/puzzle/next so the user
                                    // isn't stuck replaying the same daily puzzle.
                                    Rectangle {
                                        Layout.preferredWidth: pzNextRow.implicitWidth + window.s(14); Layout.preferredHeight: window.s(26); radius: window.s(6)
                                        color: pzNextMa.containsMouse ? window.surface1 : "transparent"
                                        border.color: pzNextMa.containsMouse ? window.green : window.surface1; border.width: 1
                                        Row { id: pzNextRow; anchors.centerIn: parent; spacing: window.s(4)
                                            Text { text: "Next ›"
                                                   font.family: "JetBrains Mono"; font.pixelSize: window.s(9)
                                                   color: pzNextMa.containsMouse ? window.green : window.subtext0
                                                   anchors.verticalCenter: parent.verticalCenter } }
                                        MouseArea { id: pzNextMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.chessFetchNextPuzzle() }
                                    }
                                }
                            }
                        }

                        // ── PLAYING / ENDED ──
                        Item { Layout.fillWidth: true; Layout.fillHeight: true
                            visible: window.chessStatus === "playing" || window.chessStatus === "ended"

                            ColumnLayout { anchors.fill: parent; spacing: window.s(4)
                                // ── Centered clocks (opponent's, then yours). Name +
                                // turn now live in the global header. Hidden vs Stockfish. ──
                                RowLayout {
                                    Layout.alignment: Qt.AlignHCenter; spacing: window.s(10)
                                    visible: !window.chessIsAiGame && !window.chessIsCorr && window.chessClocksKnown
                                    // Opponent clock
                                    Rectangle {
                                        Layout.preferredWidth: oppClockTxt.implicitWidth + window.s(18); Layout.preferredHeight: window.s(30); radius: window.s(8)
                                        property bool running: (window.chessHalfmoveCount % 2 === 0) !== window.chessIsWhite
                                        color: running ? Qt.rgba(window.green.r, window.green.g, window.green.b, 0.16) : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.6)
                                        border.color: running ? window.green : window.surface1; border.width: 1
                                        Text { id: oppClockTxt; anchors.centerIn: parent
                                            text: window.chessFmtClock(window.chessIsWhite ? window.chessBlackMs : window.chessWhiteMs)
                                            font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(14); color: window.text }
                                    }
                                    Text { text: "󰓦"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(12); color: window.overlay0 }
                                    // Your clock
                                    Rectangle {
                                        Layout.preferredWidth: myClockTxt.implicitWidth + window.s(18); Layout.preferredHeight: window.s(30); radius: window.s(8)
                                        property bool running: (window.chessHalfmoveCount % 2 === 0) === window.chessIsWhite
                                        color: running ? Qt.rgba(window.green.r, window.green.g, window.green.b, 0.16) : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.6)
                                        border.color: running ? window.green : window.surface1; border.width: 1
                                        Text { id: myClockTxt; anchors.centerIn: parent
                                            text: window.chessFmtClock(window.chessIsWhite ? window.chessWhiteMs : window.chessBlackMs)
                                            font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(14); color: window.text }
                                    }
                                }
                                // Premove hint
                                Text { Layout.fillWidth: true; visible: window.chessPremoves.length > 0
                                    text: window.chessPremoves.length + (window.chessPremoves.length === 1 ? " premove queued (tap board to clear-on-replay)" : " premoves queued")
                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(8); color: window.mauve; horizontalAlignment: Text.AlignHCenter }
                                // Action flash / status line
                                Text {
                                    Layout.fillWidth: true
                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(9)
                                    color: window.chessActionFlash !== "" ? window.teal
                                         : window.chessMoveError !== "" ? window.red
                                         : window.chessMyTurn ? window.green : window.overlay0
                                    text: window.chessActionFlash !== "" ? window.chessActionFlash
                                        : window.chessMoveError !== "" ? "✗ " + window.chessMoveError
                                        : window.chessMyTurn ? "Your turn"
                                        : window.chessStatus === "playing" ? "Waiting for opponent…"
                                        : window.chessResult !== "" ? "Game over — " + window.chessResult : ""
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                // Debug strip — shows the latest create response and
                                // stream event so we can see why a game isn't starting.
                                // (Temporary diagnostic.)
                                Text {
                                    Layout.fillWidth: true
                                    visible: window.chessDebugVisible
                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(7); color: window.overlay0
                                    wrapMode: Text.Wrap; maximumLineCount: 4; elide: Text.ElideRight
                                    text: "create: " + window.chessDebugCreate + "\nstream: " + window.chessDebugStream
                                }
                                // ── Board (top, fills) ──
                                Item { Layout.fillWidth: true; Layout.preferredHeight: width; Layout.maximumHeight: parent.height - window.s(220)
                                    Loader { anchors.fill: parent; sourceComponent: chessBoardComponent }
                                }
                                // ── In-game chat panel (while PLAYING). On game end
                                // this hides and the analysis bar below takes its place. ──
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: window.s(150)
                                    visible: window.chessStatus === "playing" && !window.chessIsCorr
                                    radius: window.s(8); color: Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.4)
                                    border.color: window.surface1; border.width: 1; clip: true
                                    ColumnLayout { anchors.fill: parent; anchors.margins: window.s(6); spacing: window.s(4)
                                        ListView { id: chessChatView
                                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: window.s(2)
                                            model: chessChatModel; boundsBehavior: Flickable.StopAtBounds
                                            onCountChanged: positionViewAtEnd()
                                            delegate: RowLayout { width: chessChatView.width ? chessChatView.width : 0; spacing: window.s(5)
                                                Text { text: model.user + ":"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(9); color: model.room === "spectator" ? window.overlay1 : window.mauve }
                                                Text { text: model.text; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.subtext0; wrapMode: Text.Wrap; Layout.fillWidth: true } }
                                            // Placeholder when no messages yet
                                            Text { anchors.centerIn: parent; visible: chessChatModel.count === 0
                                                text: "No messages yet"; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.overlay0 }
                                        }
                                        // Preset quick-message buttons (the canned messages Lichess supports).
                                        Flow { Layout.fillWidth: true; spacing: window.s(4)
                                            Repeater {
                                                model: [
                                                    { label: "Hi",  msg: "Hi!" },
                                                    { label: "GL HF", msg: "Good luck, have fun!" },
                                                    { label: "GG",  msg: "Good game" },
                                                    { label: "WP",  msg: "Well played" },
                                                    { label: "TY",  msg: "Thank you" },
                                                    { label: "GTG", msg: "Got to go" },
                                                    { label: "Bye", msg: "Bye!" }
                                                ]
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    width: presetTxt.implicitWidth + window.s(14); height: window.s(22); radius: window.s(11)
                                                    color: presetMa.containsMouse ? window.green : Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.6)
                                                    border.color: window.surface1; border.width: 1
                                                    Behavior on color { ColorAnimation { duration: 100 } }
                                                    Text { id: presetTxt; anchors.centerIn: parent; text: modelData.label
                                                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(8)
                                                        color: presetMa.containsMouse ? window.crust : window.subtext0 }
                                                    MouseArea { id: presetMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                        onClicked: window.chessSendChat(modelData.msg, window.chessChatRoom) }
                                                }
                                            }
                                        }
                                        RowLayout { Layout.fillWidth: true; spacing: window.s(4)
                                            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: window.s(26); radius: window.s(6); color: window.surface0; border.color: chessChatInput.activeFocus ? window.green : window.surface1; border.width: 1
                                                TextInput { id: chessChatInput; anchors.fill: parent; anchors.leftMargin: window.s(8); anchors.rightMargin: window.s(8); verticalAlignment: Text.AlignVCenter
                                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.text; clip: true; selectByMouse: true
                                                    Keys.onReturnPressed: { window.chessSendChat(text, window.chessChatRoom); text = ""; }
                                                    Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; visible: parent.text === ""; text: "Message…"; font: parent.font; color: window.overlay0 } } }
                                            Rectangle { Layout.preferredWidth: window.s(40); Layout.preferredHeight: window.s(26); radius: window.s(6); color: chessSendMa.containsMouse ? window.green : window.surface0; border.color: window.surface1; border.width: 1
                                                Text { anchors.centerIn: parent; text: "Send"; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); font.weight: Font.Bold; color: chessSendMa.containsMouse ? window.crust : window.subtext0 }
                                                MouseArea { id: chessSendMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { window.chessSendChat(chessChatInput.text, window.chessChatRoom); chessChatInput.text = ""; } } }
                                        }
                                    }
                                }
                                // ── Analysis bar — replaces the chat panel once the
                                // game is over. Offers a Lichess computer analysis and
                                // a "learn from my mistakes" review. ──
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: window.s(150)
                                    visible: window.chessStatus === "ended"
                                    radius: window.s(8); color: Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.4)
                                    border.color: window.surface1; border.width: 1; clip: true
                                    ColumnLayout { anchors.fill: parent; anchors.margins: window.s(10); spacing: window.s(8)
                                        Text { text: window.chessResult !== "" ? "Game over — " + window.chessResult : "Game over"
                                            font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(12); color: window.text
                                            Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
                                        Text { text: window.chessAnalysisStatus === "requesting" ? "Requesting analysis…"
                                                  : window.chessAnalysisStatus === "polling" ? "Analyzing your game…"
                                                  : window.chessAnalysisStatus === "ready" ? "Analysis ready — open the Analysis page."
                                                  : "Get a full computer analysis of this game, then review your mistakes."
                                            font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.subtext0
                                            Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap }
                                        RowLayout { Layout.fillWidth: true; spacing: window.s(8)
                                            // Request computer analysis
                                            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: window.s(36); radius: window.s(8)
                                                color: anaReqMa.containsMouse ? Qt.rgba(window.blue.r, window.blue.g, window.blue.b, 0.18) : window.surface0
                                                border.color: anaReqMa.containsMouse ? window.blue : window.surface1; border.width: 1
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                                RowLayout { anchors.centerIn: parent; spacing: window.s(6)
                                                    Text { text: window.chessAnalysisStatus === "requesting" || window.chessAnalysisStatus === "polling" ? "󰦖" : "󰋙"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(14); color: window.blue
                                                        RotationAnimation on rotation { running: window.chessAnalysisStatus === "requesting" || window.chessAnalysisStatus === "polling"; loops: Animation.Infinite; from: 0; to: 360; duration: 1200 } }
                                                    Text { text: "Computer analysis"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(10); color: anaReqMa.containsMouse ? window.text : window.subtext0 } }
                                                MouseArea { id: anaReqMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: { window.chessStatus = "analysis"; window.chessRequestAnalysis(); } }
                                            }
                                            // Learn from my mistakes
                                            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: window.s(36); radius: window.s(8)
                                                color: anaLearnMa.containsMouse ? Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.18) : window.surface0
                                                border.color: anaLearnMa.containsMouse ? window.mauve : window.surface1; border.width: 1
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                                RowLayout { anchors.centerIn: parent; spacing: window.s(6)
                                                    Text { text: "󰧑"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(14); color: window.mauve }
                                                    Text { text: "Learn from mistakes"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(10); color: anaLearnMa.containsMouse ? window.text : window.subtext0 } }
                                                MouseArea { id: anaLearnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: { window.chessStatus = "analysis"; window.chessRequestAnalysis(); window.chessLearnFromMistakes(); } }
                                            }
                                        }
                                    }
                                }
                                    Item { Layout.fillWidth: true }
                                    Rectangle { Layout.preferredWidth: newGameRow.implicitWidth + window.s(14); Layout.preferredHeight: window.s(26); radius: window.s(6)
                                        color: newGameMa.containsMouse ? window.surface1 : window.surface0
                                        border.color: newGameMa.containsMouse ? window.green : window.surface1; border.width: 1
                                        Row { id: newGameRow; anchors.centerIn: parent; spacing: window.s(4)
                                            Text { text: "New Game"; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: newGameMa.containsMouse ? window.green : window.subtext0; anchors.verticalCenter: parent.verticalCenter } }
                                        MouseArea { id: newGameMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: { window.chessStatus = "menu"; window.chessGameId = ""; window.chessSelected = -1; window.chessFromIdx = -1; window.chessToIdx = -1; window.chessInitBoard(); chessPollTimer.stop(); window.saveChessState(); } } }
                                    Item { Layout.fillWidth: true }
                                }
                            }
                        }

                        // ══════════════════════════════════════
                        // ANALYSIS / MISTAKES PAGE
                        // ══════════════════════════════════════
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            visible: window.chessStatus === "analysis"
                            ColumnLayout { anchors.fill: parent; spacing: window.s(6)
                                // Header: back + status
                                RowLayout { Layout.fillWidth: true; spacing: window.s(6)
                                    Rectangle { Layout.preferredWidth: window.s(28); Layout.preferredHeight: window.s(28); radius: window.s(8)
                                        color: anBackMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"
                                        Text { anchors.centerIn: parent; text: "󰁍"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(15); color: window.mauve }
                                        MouseArea { id: anBackMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: window.chessStatus = (window.chessGameId !== "" ? "ended" : "menu") } }
                                    Text { text: "Computer Analysis"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(13); color: window.text }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        font.family: "JetBrains Mono"; font.pixelSize: window.s(9)
                                        color: window.chessAnalysisStatus === "ready" ? window.green : window.chessAnalysisStatus === "timeout" ? window.red : window.overlay1
                                        text: window.chessAnalysisStatus === "requesting" ? "Requesting…"
                                            : window.chessAnalysisStatus === "polling" ? "Computing… (" + window.chessAnalysisPollCount + ")"
                                            : window.chessAnalysisStatus === "ready" ? "Done"
                                            : window.chessAnalysisStatus === "timeout" ? "Timed out — open on lichess.org"
                                            : ""
                                    }
                                }
                                // ── Coach's "learn from my mistakes" review ──
                                Rectangle {
                                    visible: window.chessMistakesLoading || window.chessMistakesReview !== ""
                                    Layout.fillWidth: true; Layout.preferredHeight: Math.min(coachCol.implicitHeight + window.s(16), window.s(220))
                                    radius: window.s(10); color: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.08)
                                    border.color: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.35); border.width: 1; clip: true
                                    Flickable { anchors.fill: parent; anchors.margins: window.s(8); contentHeight: coachCol.implicitHeight; clip: true
                                        ColumnLayout { id: coachCol; width: parent.width; spacing: window.s(4)
                                            RowLayout { spacing: window.s(6)
                                                Text { text: "󰧑"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(13); color: window.mauve }
                                                Text { text: window.chessMistakesLoading ? "Coach is reviewing your game…" : "Coach's review"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(10); color: window.mauve } }
                                            TextEdit { visible: window.chessMistakesReview !== ""
                                                text: window.chessMistakesReview
                                                font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.text
                                                Layout.fillWidth: true; wrapMode: TextEdit.Wrap; textFormat: TextEdit.PlainText
                                                readOnly: true; selectByMouse: true; selectByKeyboard: true
                                                selectionColor: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.3) }
                                        }
                                    }
                                }
                                // Per-player summary (accuracy + mistake counts)
                                RowLayout { Layout.fillWidth: true; spacing: window.s(8)
                                    visible: window.chessAnalysisStatus === "ready"
                                    Repeater {
                                        model: [ {who:"White", d: window.chessAnalysisWhite}, {who:"Black", d: window.chessAnalysisBlack} ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            Layout.fillWidth: true; Layout.preferredHeight: sumCol.implicitHeight + window.s(12)
                                            radius: window.s(8); color: Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.4); border.color: window.surface1; border.width: 1
                                            ColumnLayout { id: sumCol; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: window.s(8); spacing: window.s(2)
                                                Text { text: modelData.who + (modelData.d.accuracy ? "  ·  " + modelData.d.accuracy + "% acc" : ""); font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(10); color: window.text }
                                                RowLayout { spacing: window.s(8)
                                                    Text { text: "󰊪 " + (modelData.d.inaccuracy||0); font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(9); color: window.yellow }
                                                    Text { text: "✗ " + (modelData.d.mistake||0); font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.peach }
                                                    Text { text: "?? " + (modelData.d.blunder||0); font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.red }
                                                    Text { text: "ACPL " + (modelData.d.acpl||0); font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.overlay1 } }
                                            }
                                        }
                                    }
                                }
                                // Move list with eval + judgments — click a move to step the board
                                ListView {
                                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: window.s(2)
                                    model: chessAnalysisModel; boundsBehavior: Flickable.StopAtBounds
                                    ScrollBar.vertical: ScrollBar { width: window.s(3); policy: ScrollBar.AsNeeded; contentItem: Rectangle { implicitWidth: window.s(3); radius: window.s(1); color: window.surface2 } }
                                    delegate: Rectangle {
                                        required property var model
                                        width: ListView.view ? ListView.view.width : 0
                                        height: anRow.implicitHeight + window.s(8); radius: window.s(6)
                                        color: model.judgeName === "Blunder" ? Qt.rgba(window.red.r, window.red.g, window.red.b, 0.12)
                                             : model.judgeName === "Mistake" ? Qt.rgba(window.peach.r, window.peach.g, window.peach.b, 0.12)
                                             : model.judgeName === "Inaccuracy" ? Qt.rgba(window.yellow.r, window.yellow.g, window.yellow.b, 0.10)
                                             : "transparent"
                                        RowLayout { id: anRow; anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: window.s(8); anchors.rightMargin: window.s(8); spacing: window.s(8)
                                            Text { text: (Math.floor(model.ply/2)+1) + (model.ply%2===0 ? "." : "…"); font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.overlay0; Layout.preferredWidth: window.s(28) }
                                            Text { text: model.san; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(10); color: window.text; Layout.preferredWidth: window.s(46) }
                                            Text { visible: model.judgeName !== ""; text: model.judgeName; font.family: "JetBrains Mono"; font.pixelSize: window.s(8); font.weight: Font.Bold
                                                color: model.judgeName === "Blunder" ? window.red : model.judgeName === "Mistake" ? window.peach : window.yellow }
                                            Text { Layout.fillWidth: true; text: model.judgeComment; font.family: "JetBrains Mono"; font.pixelSize: window.s(8); color: window.overlay1; elide: Text.ElideRight }
                                            Text { text: model.mate !== 0 ? "#" + model.mate : (model.evalCp >= 0 ? "+" : "") + (model.evalCp/100).toFixed(1); font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.subtext0; Layout.preferredWidth: window.s(40); horizontalAlignment: Text.AlignRight }
                                        }
                                    }
                                }
                                // Open full analysis on lichess
                                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: window.s(28); radius: window.s(8)
                                    color: anLiMa.containsMouse ? window.surface1 : window.surface0; border.color: window.surface1; border.width: 1
                                    Text { anchors.centerIn: parent; text: "Open full analysis on lichess.org"; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: anLiMa.containsMouse ? window.mauve : window.subtext0 }
                                    MouseArea { id: anLiMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: Quickshell.execDetached(["xdg-open", "https://lichess.org/" + window.chessGameId]) }
                                }
                            }
                        }
                    }

                // ══════════════════════════════════════
                // KAVITA MODE — in-popup reader
                // ══════════════════════════════════════
                Item { Layout.fillWidth: true; Layout.fillHeight: true; visible: window.activeMode === "kavita"
                    ColumnLayout { anchors.fill: parent; spacing: window.s(8); opacity: introChat

                        // ── Top bar (shown when NOT reading) — minimal: just connected dot + spacer ──
                        RowLayout { Layout.fillWidth: true; spacing: window.s(8)
                            visible: window.kavitaSubMode !== "reading"
                            Rectangle { visible: window.kavitaConnected; Layout.preferredWidth: window.s(8); Layout.preferredHeight: window.s(8); radius: window.s(4); color: window.green }
                            Item { Layout.fillWidth: true }
                        }

                        // ── Not connected ──
                        Item { Layout.fillWidth: true; Layout.fillHeight: true; visible: !window.kavitaConnected
                            ColumnLayout { anchors.centerIn: parent; spacing: window.s(12); width: parent.width * 0.85
                                Text { text: "Add kavita_url and kavita_api_key to ai_config.json"; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.subtext0; Layout.fillWidth: true; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter }
                                Rectangle { Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: window.s(100); Layout.preferredHeight: window.s(30); radius: window.s(8); color: kavRMa.containsMouse ? window.surface1 : window.surface0; border.color: window.surface1; border.width: 1
                                    Text { anchors.centerIn: parent; text: "Reconnect"; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: kavRMa.containsMouse ? window.text : window.subtext0 }
                                    MouseArea { id: kavRMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { configReader.running = false; configReader.running = true; } } } } }

                        // ── Continue reading card (on-deck sub-mode) ──
                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: window.kavitaLastName !== "" ? window.s(44) : 0
                            visible: window.kavitaConnected && window.kavitaSubMode === "ondeck" && window.kavitaLastName !== ""
                            radius: window.s(10)
                            color: contMa.containsMouse ? Qt.rgba(window.pink.r, window.pink.g, window.pink.b, 0.15) : Qt.rgba(window.pink.r, window.pink.g, window.pink.b, 0.08)
                            border.color: Qt.rgba(window.pink.r, window.pink.g, window.pink.b, 0.3); border.width: 1
Behavior on color { ColorAnimation { duration: 100 } }
                            RowLayout { anchors.fill: parent; anchors.leftMargin: window.s(12); anchors.rightMargin: window.s(12); spacing: window.s(8)
                                Text { text: "Continue"; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.pink }
                                Text { text: window.kavitaLastName; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(11); color: window.text; elide: Text.ElideRight; Layout.fillWidth: true } }
                            MouseArea { id: contMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: window.kavitaOpenSeries(window.kavitaLastSeriesId, window.kavitaLastLibraryId, window.kavitaLastName, window.kavitaReadFormat) } }

                        // ── On Deck list ──
                        ListView { Layout.fillWidth: true; Layout.fillHeight: true
                            visible: window.kavitaConnected && window.kavitaSubMode === "ondeck"
                            model: kavitaOnDeck; clip: true; spacing: window.s(6); boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar { width: window.s(3); policy: ScrollBar.AsNeeded; contentItem: Rectangle { implicitWidth: window.s(3); radius: window.s(1); color: window.surface2 } }
                            delegate: Rectangle { width: ListView.view ? ListView.view.width : 0; height: dkCol.implicitHeight + window.s(14); radius: window.s(10)
                                color: dkMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.6) : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.35)
                                border.color: dkMa.containsMouse ? Qt.rgba(window.pink.r, window.pink.g, window.pink.b, 0.5) : "transparent"; border.width: 1
Behavior on color { ColorAnimation { duration: 100 } }
                                ColumnLayout { id: dkCol; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: window.s(8); spacing: window.s(4)
                                    Text { text: model.name; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(12); color: dkMa.containsMouse ? window.text : window.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                                    RowLayout { Layout.fillWidth: true; spacing: window.s(8)
                                        Text { text: model.libraryName; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.pink }
                                        Rectangle { Layout.fillWidth: true; height: window.s(4); radius: window.s(2); color: window.surface1
                                            Rectangle { width: model.pages > 0 ? parent.width * (model.pagesRead / model.pages) : 0; height: parent.height; radius: parent.radius; color: window.pink } }
                                        Text { text: model.pages > 0 ? Math.round(model.pagesRead / model.pages * 100) + "%" : ""; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.overlay1 } } }
                                MouseArea { id: dkMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: window.kavitaOpenSeries(model.seriesId, model.libraryId, model.name, model.format) } } }

                        // ── Library browser (nested: category → books) ──
                        Item { Layout.fillWidth: true; Layout.fillHeight: true
                            visible: window.kavitaConnected && window.kavitaSubMode === "library"
                            ColumnLayout { anchors.fill: parent; spacing: window.s(6)
                                Text { text: "Library"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(13); color: window.text; Layout.leftMargin: window.s(2) }
                                // Build the list of distinct library categories from the series.
                                ListView {
                                    id: libCatView
                                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: window.s(4)
                                    boundsBehavior: Flickable.StopAtBounds
                                    model: kavitaLibraryCats
                                    ScrollBar.vertical: ScrollBar { width: window.s(3); policy: ScrollBar.AsNeeded; contentItem: Rectangle { implicitWidth: window.s(3); radius: window.s(1); color: window.surface2 } }
                                    delegate: Column {
                                        id: catCol
                                        width: libCatView.width
                                        spacing: window.s(3)
                                        required property var model
                                        property string catName: model.name
                                        property bool expanded: window.kavitaLibExpanded === catName
                                        // Category header (click to expand/collapse)
                                        Rectangle {
                                            width: parent.width; height: window.s(34); radius: window.s(8)
                                            color: catMa.containsMouse || catCol.expanded ? Qt.rgba(window.pink.r, window.pink.g, window.pink.b, 0.15) : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.4)
                                            border.color: catCol.expanded ? Qt.rgba(window.pink.r, window.pink.g, window.pink.b, 0.5) : window.surface1; border.width: 1
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                            RowLayout { anchors.fill: parent; anchors.leftMargin: window.s(10); anchors.rightMargin: window.s(10); spacing: window.s(8)
                                                Text { text: catCol.catName; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(11); color: window.text; Layout.fillWidth: true }
                                                Text { text: catCol.model.count + " books"; font.family: "JetBrains Mono"; font.pixelSize: window.s(8); color: window.overlay1 }
                                                Text { text: catCol.expanded ? "󰍝" : "󰍞"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(12); color: window.pink }
                                            }
                                            MouseArea { id: catMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: window.kavitaLibExpanded = (window.kavitaLibExpanded === catCol.catName ? "" : catCol.catName) }
                                        }
                                        // Nested book list — every series whose libraryName matches
                                        // this category. Rows collapse to 0 height when not in
                                        // this category or when the category is collapsed.
                                        Repeater {
                                            model: kavitaAllSeries
                                            delegate: Rectangle {
                                                required property var model
                                                property bool show: catCol.expanded && ((model.libraryName || "Other") === catCol.catName)
                                                width: libCatView.width - window.s(16)
                                                x: window.s(16)
                                                visible: show
                                                height: show ? bkCol.implicitHeight + window.s(10) : 0
                                                radius: window.s(6)
                                                color: bkMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.6) : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.25)
                                                border.color: bkMa.containsMouse ? Qt.rgba(window.pink.r, window.pink.g, window.pink.b, 0.4) : "transparent"; border.width: 1
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                                ColumnLayout { id: bkCol; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: window.s(7); spacing: window.s(2)
                                                    RowLayout { Layout.fillWidth: true; spacing: window.s(6)
                                                        Text { text: bkRect.model.name; font.family: "JetBrains Mono"; font.weight: Font.Medium; font.pixelSize: window.s(10); color: bkMa.containsMouse ? window.text : window.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                                                        // Small tag marking audio titles.
                                                        Text { visible: bkRect.model.format === window.kavitaAudioFormatCode
                                                            text: "󰓃 audio"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(8); color: window.pink }
                                                    }
                                                    RowLayout { Layout.fillWidth: true; spacing: window.s(6); visible: bkRect.model.pagesRead > 0
                                                        Rectangle { Layout.fillWidth: true; height: window.s(3); radius: window.s(1); color: window.surface1
                                                            Rectangle { width: bkRect.model.pages > 0 ? parent.width * (bkRect.model.pagesRead / bkRect.model.pages) : 0; height: parent.height; radius: parent.radius; color: window.pink } }
                                                        Text { text: bkRect.model.pages > 0 ? Math.round(bkRect.model.pagesRead / bkRect.model.pages * 100) + "%" : ""; font.family: "JetBrains Mono"; font.pixelSize: window.s(8); color: window.overlay1 } }
                                                }
                                                MouseArea { id: bkMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: window.kavitaBrowseSeries(bkRect.model.seriesId, bkRect.model.libraryId, bkRect.model.name, bkRect.model.format) }
                                                property var bkRect: this
                                            }
                                        }
                                    }
                                }
                                Text { text: kavitaAllSeries.count + " series in " + kavitaLibraryCats.count + " libraries"; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.overlay0 }
                            }
                        }

                        // ══════════════════════════════
                        // SERIES CHAPTERS — pick an individual book
                        // ══════════════════════════════
                        Item { Layout.fillWidth: true; Layout.fillHeight: true
                            visible: window.kavitaConnected && window.kavitaSubMode === "serieschapters"
                            ColumnLayout { anchors.fill: parent; spacing: window.s(6)
                                // Header: back to library + series name
                                RowLayout { Layout.fillWidth: true; spacing: window.s(6)
                                    Rectangle { Layout.preferredWidth: window.s(28); Layout.preferredHeight: window.s(28); radius: window.s(8)
                                        color: scBackMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"
                                        Text { anchors.centerIn: parent; text: "󰁍"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(15); color: window.pink }
                                        MouseArea { id: scBackMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: { window.kavitaSubMode = "library"; } } }
                                    Text { text: window.kavitaBrowseSeriesName; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(12); color: window.text; elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                                Text { visible: window.kavitaBrowseLoading; text: "Loading books…"; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.overlay0; Layout.leftMargin: window.s(4) }
                                Text { visible: !window.kavitaBrowseLoading && kavitaBrowseChapters.count === 0
                                    text: "No books found in this series."; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.overlay0; Layout.leftMargin: window.s(4) }
                                // Book list
                                ListView {
                                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: window.s(4)
                                    model: kavitaBrowseChapters; boundsBehavior: Flickable.StopAtBounds
                                    ScrollBar.vertical: ScrollBar { width: window.s(3); policy: ScrollBar.AsNeeded; contentItem: Rectangle { implicitWidth: window.s(3); radius: window.s(1); color: window.surface2 } }
                                    delegate: Rectangle {
                                        required property var model
                                        width: ListView.view ? ListView.view.width : 0
                                        height: scCol.implicitHeight + window.s(14); radius: window.s(8)
                                        color: scMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.6) : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.35)
                                        border.color: scMa.containsMouse ? Qt.rgba(window.pink.r, window.pink.g, window.pink.b, 0.5) : "transparent"; border.width: 1
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                        ColumnLayout { id: scCol; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: window.s(8); spacing: window.s(3)
                                            RowLayout { Layout.fillWidth: true; spacing: window.s(8)
                                                // Audio chapters show a play/pause glyph reflecting current state.
                                                Text { visible: window.kavitaBrowseSeriesFmt === window.kavitaAudioFormatCode
                                                    text: (window.kavitaAudioChapterId === model.chapterId && window.audioPlaying) ? "󰏤" : "󰐊"
                                                    font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(14); color: window.pink
                                                    Layout.alignment: Qt.AlignVCenter }
                                                Text { text: model.title; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(11); color: scMa.containsMouse ? window.text : window.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                                            }
                                            RowLayout { Layout.fillWidth: true; spacing: window.s(8)
                                                // Audio: interactive scrub slider for the
                                                // currently-playing chapter. Click or drag
                                                // anywhere on the track to seek; the fill
                                                // shows current position.
                                                Item {
                                                    visible: window.kavitaBrowseSeriesFmt === window.kavitaAudioFormatCode && window.kavitaAudioChapterId === model.chapterId && window.audioDurMs > 0
                                                    Layout.fillWidth: true; Layout.preferredHeight: window.s(14)
                                                    Rectangle {
                                                        id: scrubTrack
                                                        anchors.left: parent.left; anchors.right: parent.right
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        height: scrubMa.containsMouse || scrubMa.pressed ? window.s(6) : window.s(3)
                                                        radius: height / 2; color: window.surface1
                                                        Behavior on height { NumberAnimation { duration: 120 } }
                                                        // Played portion.
                                                        Rectangle {
                                                            id: scrubFill
                                                            width: window.audioDurMs > 0 ? parent.width * (window.audioPosMs / window.audioDurMs) : 0
                                                            height: parent.height; radius: parent.radius; color: window.pink
                                                        }
                                                        // Draggable knob.
                                                        Rectangle {
                                                            visible: scrubMa.containsMouse || scrubMa.pressed
                                                            width: window.s(10); height: window.s(10); radius: window.s(5)
                                                            color: window.pink
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            x: Math.max(0, Math.min(parent.width - width, scrubFill.width - width / 2))
                                                        }
                                                    }
                                                    MouseArea {
                                                        id: scrubMa
                                                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                        // Tap or drag to seek. Convert x→fraction→ms.
                                                        function seekToX(mx) {
                                                            let frac = Math.max(0, Math.min(1, mx / width));
                                                            window.audioSeek(Math.round(frac * window.audioDurMs));
                                                        }
                                                        onClicked: (m) => seekToX(m.x)
                                                        onPositionChanged: (m) => { if (pressed) seekToX(m.x); }
                                                    }
                                                }
                                                Text { visible: window.kavitaBrowseSeriesFmt === window.kavitaAudioFormatCode && window.kavitaAudioChapterId === model.chapterId && window.audioDurMs > 0
                                                    text: window.chessFmtClock(window.audioPosMs) + " / " + window.chessFmtClock(window.audioDurMs)
                                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(8); color: window.overlay1 }
                                                // Text books: page count + read progress.
                                                Text { visible: window.kavitaBrowseSeriesFmt !== window.kavitaAudioFormatCode && model.pages > 0; text: model.pages + " pages"; font.family: "JetBrains Mono"; font.pixelSize: window.s(8); color: window.overlay1 }
                                                Rectangle { visible: window.kavitaBrowseSeriesFmt !== window.kavitaAudioFormatCode && model.pagesRead > 0; Layout.fillWidth: true; height: window.s(3); radius: window.s(1); color: window.surface1
                                                    Rectangle { width: model.pages > 0 ? parent.width * (model.pagesRead / model.pages) : 0; height: parent.height; radius: parent.radius; color: window.pink } }
                                                Text { visible: window.kavitaBrowseSeriesFmt !== window.kavitaAudioFormatCode && model.pagesRead > 0; text: model.pages > 0 ? Math.round(model.pagesRead / model.pages * 100) + "%" : ""; font.family: "JetBrains Mono"; font.pixelSize: window.s(8); color: window.overlay1 } }
                                        }
                                        MouseArea { id: scMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                // Audio chapter already playing → toggle pause/resume.
                                                if (window.kavitaBrowseSeriesFmt === window.kavitaAudioFormatCode && window.kavitaAudioChapterId === model.chapterId) {
                                                    window.audioToggle();
                                                } else {
                                                    window.kavitaOpenChapter(model.chapterId, model.volumeId, model.pagesRead, model.pages, model.title);
                                                }
                                            } }
                                    }
                                }
                                Text { visible: kavitaBrowseChapters.count > 0; text: kavitaBrowseChapters.count + " books"; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.overlay0 }
                            }
                        }

                        // ══════════════════════════════
                        // READER VIEW
                        // ══════════════════════════════
                        Item { Layout.fillWidth: true; Layout.fillHeight: true
                            visible: window.kavitaConnected && window.kavitaSubMode === "reading"

                            ColumnLayout { anchors.fill: parent; spacing: window.s(6)

                                // Progress bar (title moved to global header above).
                                // Clickable: tap anywhere on the track to jump to that
                                // page. The visible bar is thin but the MouseArea is
                                // taller so it's easy to hit.
                                Item { Layout.fillWidth: true; Layout.preferredHeight: window.s(14)
                                    visible: !window.kavitaReadLoading
                                    Rectangle {
                                        id: kavitaProgTrack
                                        anchors.left: parent.left; anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: kavitaProgMa.containsMouse ? window.s(6) : window.s(3)
                                        radius: height / 2; color: window.surface1
                                        Behavior on height { NumberAnimation { duration: 120 } }
                                        Rectangle { width: window.kavitaReadTotalPages > 0 ? parent.width * ((window.kavitaReadPage + 1) / window.kavitaReadTotalPages) : 0
                                            height: parent.height; radius: parent.radius
                                            gradient: Gradient { orientation: Gradient.Horizontal
GradientStop { position: 0.0; color: window.pink }
GradientStop { position: 1.0; color: window.mauve } }
                                            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutQuart } } }
                                        // Hover preview tick
                                        Rectangle { visible: kavitaProgMa.containsMouse; width: window.s(2); height: parent.height + window.s(4)
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: Math.max(0, Math.min(parent.width - width, kavitaProgMa.mouseX - width / 2))
                                            radius: window.s(1); color: window.text; opacity: 0.6 }
                                    }
                                    MouseArea {
                                        id: kavitaProgMa
                                        anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: function(mouse) {
                                            if (window.kavitaReadTotalPages <= 0) return;
                                            let frac = Math.max(0, Math.min(1, mouse.x / width));
                                            let target = Math.round(frac * (window.kavitaReadTotalPages - 1));
                                            window.kavitaLoadPage(target);
                                        }
                                    }
                                }

                                // Loading state
                                Item { Layout.fillWidth: true; Layout.fillHeight: true; visible: window.kavitaReadLoading
                                    Text { anchors.centerIn: parent; text: "Loading..."; font.family: "JetBrains Mono"; font.pixelSize: window.s(12); color: window.overlay0 } }

                                // Image reader (manga, comics, archives) — the
                                // whole image is sized to fit inside the visible
                                // area so the user never has to scroll within a
                                // single page. Wheel scroll moves between pages.
                                Item { id: readerImageFlick
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    visible: !window.kavitaReadLoading && window.kavitaReadFormat !== 3 && window.kavitaReadFormat !== 4
                                    clip: true

                                    Image {
                                        id: readerImage
                                        anchors.fill: parent
                                        source: window.kavitaReadContent
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        cache: false

                                        // Wheel = page navigation (down/right → next, up/left → prev)
                                        WheelHandler {
                                            target: null
                                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                            property real accum: 0
                                            onWheel: function(event) {
                                                accum += event.angleDelta.y;
                                                if (accum <= -120) { accum = 0; window.kavitaWheelStep(+1); }
                                                else if (accum >= 120) { accum = 0; window.kavitaWheelStep(-1); }
                                                event.accepted = true;
                                            }
                                        }
                                        // Tap left/right halves still works as a fallback
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: function(mouse) {
                                                if (mouse.x < parent.width / 2) window.kavitaPrevPage()
                                                else window.kavitaNextPage()
                                            }
                                        }
                                    }

                                    // Page counter overlay (bottom-right). Same component
                                    // as the PDF reader's counter — kept duplicated rather
                                    // than factored out because Quickshell's component
                                    // system makes inline overlays cheaper than wrapped
                                    // Components for one-off uses.
                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: window.s(8)
                                        width: imgPageCounterText.implicitWidth + window.s(14)
                                        height: imgPageCounterText.implicitHeight + window.s(6)
                                        radius: window.s(8)
                                        color: Qt.rgba(window.crust.r, window.crust.g, window.crust.b, 0.75)
                                        border.color: Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.6)
                                        border.width: 1
                                        visible: window.kavitaReadTotalPages > 0
                                        Text {
                                            id: imgPageCounterText
                                            anchors.centerIn: parent
                                            text: (window.kavitaReadPage + 1) + " / " + window.kavitaReadTotalPages
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: window.s(10)
                                            font.weight: Font.Medium
                                            color: window.subtext0
                                        }
                                    }
                                }

                                // EPUB reader — paged through Kavita's book-page
                                // endpoint, so scroll wheel = page nav (matching
                                // image/PDF behavior; consistent UX).
                                Item { id: readerFlick
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    visible: !window.kavitaReadLoading && window.kavitaReadFormat === 3
                                    clip: true

                                    Flickable {
                                        anchors.fill: parent
                                        contentWidth: width; contentHeight: readerText.implicitHeight
                                        boundsBehavior: Flickable.StopAtBounds
                                        flickableDirection: Flickable.VerticalFlick
                                        clip: true

                                        ScrollBar.vertical: ScrollBar { width: window.s(3); policy: ScrollBar.AsNeeded
                                            contentItem: Rectangle { implicitWidth: window.s(3); radius: window.s(1); color: window.surface2 } }

                                        Text { id: readerText
                                            width: parent.width
                                            text: window.kavitaReadContent
                                            font.family: "JetBrains Mono"; font.pixelSize: window.s(12)
                                            color: window.text; wrapMode: Text.Wrap
                                            textFormat: Text.RichText; lineHeight: 1.6
                                            leftPadding: window.s(4); rightPadding: window.s(4)
                                            topPadding: window.s(4)
                                            onLinkActivated: function(link) { Quickshell.execDetached(["xdg-open", link]); }
                                        }

                                        WheelHandler {
                                            target: null
                                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                            property real accum: 0
                                            onWheel: function(event) {
                                                accum += event.angleDelta.y;
                                                if (accum <= -120) { accum = 0; window.kavitaWheelStep(+1); }
                                                else if (accum >= 120) { accum = 0; window.kavitaWheelStep(-1); }
                                                event.accepted = true;
                                            }
                                        }
                                    }
                                }

                                // PDF reader (format 4) — QtQuick.Pdf (PDFium). Mirrors how Kavita's
                                // own web UI handles PDFs: server delivers raw bytes, client renders.
                                Item {
                                    id: readerPdfItem
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    visible: window.kavitaReadFormat === 4

                                    PdfDocument {
                                        id: kavitaPdfDoc
                                        source: window.kavitaPdfPath ? ("file://" + window.kavitaPdfPath) : ""
                                        onStatusChanged: function(s) {
                                            if (kavitaPdfDoc.status === PdfDocument.Ready) {
                                                if (kavitaPdfDoc.pageCount > 0) window.kavitaReadTotalPages = kavitaPdfDoc.pageCount;
                                                window.kavitaReadLoading = false;
                                            } else if (kavitaPdfDoc.status === PdfDocument.Error) {
                                                window.kavitaReadLoading = false;
                                                window.kavitaReadContent = "PDF failed to load. See ~/.cache/quickshell/kavita.log";
                                            }
                                        }
                                    }

                                    // PDF view fills the available space and the
                                    // page image is fitted by height so the whole
                                    // page is always visible. Scroll wheel changes
                                    // pages; clicking the left/right half is still
                                    // a fallback. The PdfPageImage's sourceSize
                                    // controls render resolution for crispness.
                                    Item {
                                        anchors.fill: parent
                                        clip: true

                                        PdfPageImage {
                                            id: pdfPage
                                            anchors.fill: parent
                                            document: kavitaPdfDoc
                                            currentFrame: window.kavitaReadPage
                                            // Quantize sourceSize.width to the nearest 32px so subpixel
                                            // layout changes (which happen on every popup open due to
                                            // recreate + relayout) don't invalidate PDFium's per-page
                                            // raster cache. Without this, every reopen reset the cache
                                            // key and forced a fresh raster on every page.
                                            sourceSize.width: {
                                                let target = Math.min(parent.width * 2, 2400);
                                                return Math.round(target / 32) * 32;
                                            }
                                            fillMode: Image.PreserveAspectFit
                                        }

                                        // Wheel = page nav (matches image reader UX)
                                        WheelHandler {
                                            target: null
                                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                            property real accum: 0
                                            onWheel: function(event) {
                                                accum += event.angleDelta.y;
                                                if (accum <= -120) { accum = 0; window.kavitaWheelStep(+1); }
                                                else if (accum >= 120) { accum = 0; window.kavitaWheelStep(-1); }
                                                event.accepted = true;
                                            }
                                        }

                                        // Click left/right halves as a fallback
                                        MouseArea {
                                            anchors.fill: parent
                                            acceptedButtons: Qt.LeftButton
                                            onClicked: function(mouse) {
                                                if (mouse.x < parent.width / 2) window.kavitaPrevPage();
                                                else window.kavitaNextPage();
                                            }
                                        }
                                    }
                                    // Sequential preloader (replaces a 25-Repeater that
                                    // fired all loads at once). We walk one offset at a
                                    // time and only advance when PDFium signals Ready,
                                    // so page+1 finishes BEFORE page+2 starts. Forward
                                    // offsets first (1..12), then backward (-1..-12),
                                    // since forward is the common scroll direction.
                                    //
                                    // Resets whenever the user lands on a new page.
                                    PdfPageImage {
                                        id: pdfPreloadSlot
                                        visible: false
                                        document: kavitaPdfDoc
                                        sourceSize.width: pdfPage.sourceSize.width
                                        asynchronous: true

                                        // Walks 0..23 → offset sequence [+1, +2, ..., +12, -1, -2, ..., -12]
                                        property int step: 0
                                        // basePage is assigned imperatively (Component.onCompleted +
                                        // Connections) rather than bound, to avoid a binding loop with
                                        // currentFrame/targetOffset.
                                        property int basePage: 0
                                        property int targetOffset: {
                                            if (pdfPreloadSlot.step < 12) return pdfPreloadSlot.step + 1;        // +1 .. +12
                                            if (pdfPreloadSlot.step < 24) return -(pdfPreloadSlot.step - 11);    // -1 .. -12
                                            return 0;                                                            // done
                                        }
                                        currentFrame: {
                                            let raw = pdfPreloadSlot.basePage + pdfPreloadSlot.targetOffset;
                                            if (raw < 0) return 0;
                                            let maxPage = Math.max(0, kavitaPdfDoc.pageCount - 1);
                                            if (raw > maxPage) return maxPage;
                                            return raw;
                                        }
                                        Component.onCompleted: pdfPreloadSlot.basePage = window.kavitaReadPage
                                        onStatusChanged: function(s) {
                                            // Advance to the next preload slot once this one
                                            // finishes (either Ready or Error — don't stall on errors).
                                            if (pdfPreloadSlot.step < 24 && (pdfPreloadSlot.status === Image.Ready || pdfPreloadSlot.status === Image.Error)) {
                                                pdfPreloadSlot.step += 1;
                                            }
                                        }
                                        // When the user navigates to a new page, restart the
                                        // sequence from offset +1 anchored on the new page.
                                        Connections {
                                            target: window
                                            function onKavitaReadPageChanged() {
                                                pdfPreloadSlot.step = 0;
                                                pdfPreloadSlot.basePage = window.kavitaReadPage;
                                            }
                                        }
                                    }

                                    // Page counter overlay (bottom-right). Floats above the
                                    // PdfPageImage rather than living in the layout below it,
                                    // so it doesn't reduce the area available for the page.
                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: window.s(8)
                                        width: pageCounterText.implicitWidth + window.s(14)
                                        height: pageCounterText.implicitHeight + window.s(6)
                                        radius: window.s(8)
                                        color: Qt.rgba(window.crust.r, window.crust.g, window.crust.b, 0.75)
                                        border.color: Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.6)
                                        border.width: 1
                                        visible: window.kavitaReadTotalPages > 0
                                        Text {
                                            id: pageCounterText
                                            anchors.centerIn: parent
                                            text: (window.kavitaReadPage + 1) + " / " + window.kavitaReadTotalPages
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: window.s(10)
                                            font.weight: Font.Medium
                                            color: window.subtext0
                                        }
                                    }
                                }

                                // Bottom page nav row — kept in tree but hidden;
                                // page changes now happen via scroll wheel on the
                                // image/PDF surface (see WheelHandlers below).
                                RowLayout { Layout.fillWidth: true; Layout.preferredHeight: window.s(36); spacing: window.s(6)
                                    visible: false

                                    // Prev
                                    Rectangle { Layout.preferredWidth: window.s(40); Layout.fillHeight: true; radius: window.s(8)
                                        color: rdrPrevMa.containsMouse ? window.surface1 : window.surface0; border.color: window.surface1; border.width: 1
                                        Behavior on color { ColorAnimation { duration: 80 } }
                                        Text { anchors.centerIn: parent; text: "󰒮"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(16); color: window.kavitaReadPage > 0 ? window.pink : window.overlay0 }
                                        MouseArea { id: rdrPrevMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.kavitaPrevPage() } }

                                    // Chapter dropdown (tap to show chapter list)
                                    Rectangle { Layout.fillWidth: true; Layout.fillHeight: true; radius: window.s(8)
                                        color: rdrChMa.containsMouse ? window.surface1 : window.surface0; border.color: window.surface1; border.width: 1
                                        Behavior on color { ColorAnimation { duration: 80 } }
                                        Text { anchors.centerIn: parent
                                            text: window.kavitaReadTitle.length > 25 ? window.kavitaReadTitle.substring(0, 25) + "…" : window.kavitaReadTitle
                                            font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.subtext0 }
                                        MouseArea { id: rdrChMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: rdrChapterPopup.visible = !rdrChapterPopup.visible } }

                                    // Next
                                    Rectangle { Layout.preferredWidth: window.s(40); Layout.fillHeight: true; radius: window.s(8)
                                        color: rdrNextMa.containsMouse ? window.surface1 : window.surface0; border.color: window.surface1; border.width: 1
                                        Behavior on color { ColorAnimation { duration: 80 } }
                                        Text { anchors.centerIn: parent; text: "󰒭"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(16); color: window.pink }
                                        MouseArea { id: rdrNextMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.kavitaNextPage() } }
                                }

                                // Chapter popup list (floats above nav bar when visible)
                                Rectangle { id: rdrChapterPopup; visible: false
                                    Layout.fillWidth: true; Layout.preferredHeight: Math.min(kavitaChapters.count * window.s(32), window.s(200))
                                    radius: window.s(8); color: window.mantle; border.color: window.surface1; border.width: 1; clip: true

                                    ListView { anchors.fill: parent; anchors.margins: window.s(4); model: kavitaChapters; clip: true; spacing: window.s(2); boundsBehavior: Flickable.StopAtBounds
                                        ScrollBar.vertical: ScrollBar { width: window.s(3); policy: ScrollBar.AsNeeded; contentItem: Rectangle { implicitWidth: window.s(3); radius: window.s(1); color: window.surface2 } }
                                        delegate: Rectangle { width: ListView.view ? ListView.view.width : 0; height: window.s(30); radius: window.s(6)
                                            color: model.chapterId === window.kavitaReadChapterId
                                                ? Qt.rgba(window.pink.r, window.pink.g, window.pink.b, 0.15)
                                                : (chNavMa.containsMouse ? window.surface1 : "transparent")
                                            RowLayout { anchors.fill: parent; anchors.leftMargin: window.s(8); anchors.rightMargin: window.s(8); spacing: window.s(6)
                                                Text { text: model.chapterId === window.kavitaReadChapterId ? "󰐊" : "󰈙"
                                                    font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(11)
                                                    color: model.chapterId === window.kavitaReadChapterId ? window.pink : window.overlay0 }
                                                Text { text: model.title; font.family: "JetBrains Mono"; font.pixelSize: window.s(9)
                                                    font.weight: model.chapterId === window.kavitaReadChapterId ? Font.Bold : Font.Medium
                                                    color: model.chapterId === window.kavitaReadChapterId ? window.pink : window.subtext0
                                                    elide: Text.ElideRight; Layout.fillWidth: true }
                                                Text { visible: model.pages > 0 && model.pagesRead > 0
                                                    text: Math.round(model.pagesRead / model.pages * 100) + "%"
                                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(8); color: window.overlay0 } }
                                            MouseArea { id: chNavMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    window.kavitaReadChapterId = model.chapterId;
                                                    window.kavitaReadVolumeId = model.volumeId;
                                                    window.kavitaReadPage = 0;
                                                    window.kavitaLoadChapterInfo();
                                                    rdrChapterPopup.visible = false;
                                                } } } }
                                }
                            }
                        }
                    }
                }

            }
        }
    }
}
