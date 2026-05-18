import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
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
    property string ollamaApiKey: ""           // Ollama Cloud key — exported to Hermes by hermes_bridge.sh
    property bool toolsPopupOpen: false
    property var activeTools: ({})             // { "Web Search": true, ... }
    property bool isLoading: false
    property bool temporaryChat: false         // when true, saveChatState() no-ops

    // ── Modes ──
    property string activeMode: "chat"

    // Per-mode accent colors
    readonly property color modeColor1: activeMode === "chess" ? yellow
        : activeMode === "kavita" ? pink
        : activeMode === "chat" ? mauve
        : activeMode === "notes" ? peach
        : green
    readonly property color modeColor2: activeMode === "chess" ? peach
        : activeMode === "kavita" ? mauve
        : activeMode === "chat" ? blue
        : activeMode === "notes" ? yellow
        : teal // "chess" | "kavita" | "chat" | "notes" | "learn"

    // ── Notes state ──
    property string notesSubMode: "menu" // "menu" | "edit"
    ListModel { id: vaultNotes }
    property string selectedNoteContent: ""
    property string selectedNoteTitle: ""
    property string currentNoteFilepath: ""
    property bool notesLoading: false
    property bool noteAutoSaved: false

    // ── Learn state ──
    property string learnSubMode: "home" // "home" | "lesson" | "vocab"
    property bool bookLoaded: false
    property string bookTitle: ""
    property string learnDir: Qt.resolvedUrl("").toString().replace("file://","") + "/../.local/share/quickshell-learn"
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

    // ── Persistence (save/load state to ~/.cache/qs_ai_state/) ──
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
                // Restore chat if last message within 3 hours
                let ts = data.timestamp || 0;
                let now = Math.floor(Date.now() / 1000);
                if (now - ts < 10800 && data.messages && data.messages.length > 0) {
                    chatMessages.clear();
                    for (let i = 0; i < data.messages.length; i++)
                        chatMessages.append(data.messages[i]);
                    window.lastResponse = data.messages[data.messages.length - 1].content || "";
                    window.typeLen = window.lastResponse.length;
                }
                // Chain: load learn next
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
                    // Restore chapters
                    if (data.chapters && data.chapters.length > 0) {
                        chapterList.clear();
                        for (let i = 0; i < data.chapters.length; i++)
                            chapterList.append(data.chapters[i]);
                    }
                    // Restore vocab
                    if (data.vocab && data.vocab.length > 0) {
                        learnedTerms.clear();
                        for (let i = 0; i < data.vocab.length; i++)
                            learnedTerms.append(data.vocab[i]);
                                    window.saveLearnState();
                    }
                    // Restore lesson chat
                    if (data.lessonChat && data.lessonChat.length > 0) {
                        lessonChat.clear();
                        for (let i = 0; i < data.lessonChat.length; i++)
                            lessonChat.append(data.lessonChat[i]);
                    }
                }
                // Chain: load kavita next
                window.loadCache("kavita_last");
            }
            else if (t === "kavita_last") {
                if (data.seriesId && data.libraryId) {
                    window.kavitaLastSeriesId = data.seriesId;
                    window.kavitaLastLibraryId = data.libraryId;
                    window.kavitaLastName = data.name || "";
                }
                // Chain: load chess next
                window.loadCache("chess");
            }
            else if (t === "chess") {
                if (data.gameId && data.status === "playing") {
                    window.chessGameId = data.gameId;
                    window.chessIsWhite = data.isWhite !== false;
                    window.chessOpponent = data.opponent || "Opponent";
                    window.chessStatus = "playing";
                    // Reconnect stream
                    window.chessReconnectStream();
                }
            }
        } catch(e) {}
    }

    // ── Save triggers ──
    function saveChatState() {
        // Temporary chats (started via the "New Chat" button) are never
        // persisted — close + reopen the popup to verify the previous saved
        // chat is untouched.
        if (window.temporaryChat) return;
        let msgs = [];
        for (let i = 0; i < chatMessages.count; i++) {
            let m = chatMessages.get(i);
            msgs.push({ role: m.role, content: m.content });
        }
        if (msgs.length > 0)
            saveCache("chat", { messages: msgs, timestamp: Math.floor(Date.now() / 1000) });
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
            bookTitle: window.bookTitle,
            bookSeriesId: window.bookSeriesId,
            bookLoaded: window.bookLoaded,
            learnSubMode: window.learnSubMode,
            currentChapter: window.currentChapter,
            chapters: chapters,
            vocab: vocab,
            lessonChat: chat
        });
    }

    function saveKavitaLast(seriesId, libraryId, name) {
        saveCache("kavita_last", { seriesId: seriesId, libraryId: libraryId, name: name });
    }

    function saveChessState() {
        saveCache("chess", {
            gameId: window.chessGameId,
            isWhite: window.chessIsWhite,
            opponent: window.chessOpponent,
            status: window.chessStatus
        });
    }

    // Kavita last-read tracking
    property int kavitaLastSeriesId: 0
    property int kavitaLastLibraryId: 0
    property string kavitaLastName: ""

    // ── Hermes / approval system ──
    // Hermes runs locally as a subprocess. We call it with --no-execute so
    // tool calls come back to us as structured events; we then prompt the
    // user for approval before running anything ourselves.
    //
    // The bridge script (~/.config/hypr/scripts/hermes_bridge.sh) wraps
    // Hermes and emits a single JSON object per turn:
    //   { "type": "message", "content": "..." }
    //   { "type": "tool_call", "command": "...", "description": "..." }

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
                        // Hermes wants to run something — show approval UI
                        window.requestApproval(
                            resp.command || "",
                            resp.description || "Hermes wants to run a command"
                        );
                        return;
                    }

                    // Plain message response
                    let msg = resp.content || resp.message || "(no output)";
                    chatMessages.append({ role: "assistant", content: msg });
                    window.lastResponse = msg;
                    window.typeLen = 0;
                    window.saveChatState();
                } catch(e) {
                    // Not JSON — treat as plain text
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
        let b64 = Qt.btoa(query);
        // Bridge script handles the hermes invocation + JSON wrapping
        hermesRunner.command = ["bash", "-c",
            "echo " + b64 + " | base64 -d | ~/.config/hypr/scripts/hermes_bridge.sh 2>/dev/null"
        ];
        hermesRunner.running = false;
        hermesRunner.running = true;
        return true;
    }

    // After approval/denial, send the result back to Hermes so the
    // conversation continues with that context.
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

    // Approval flow
    function requestApproval(cmd, desc) {
        if (window.approvalPolicy === "deny") {
            chatMessages.append({ role: "assistant", content: "Action denied by policy: " + cmd });
            return;
        }
        if (window.approvalPolicy === "auto") {
            window.runApprovedCommand(cmd);
            return;
        }
        // ask
        window.pendingCommand = cmd;
        window.pendingDescription = desc;
        window.approvalPending = true;
    }
    Process {
        id: cmdRunner
        command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = this.text.trim();
                let label = window.lastApprovedCmd;
                chatMessages.append({
                    role: "assistant",
                    content: "[ran] $ " + label + (out ? "\n\n" + out.substring(0, 1500) : "")
                });
                window.lastResponse = "Ran: " + label;
                window.typeLen = window.lastResponse.length;
                window.saveChatState();
                // Feed result back to Hermes so it can continue
                if (window.hermesEnabled) window.reportToolResult(true, out.substring(0, 500));
            }
        }
    }
    property string lastApprovedCmd: ""

    function runApprovedCommand(cmd) {
        window.lastApprovedCmd = cmd;
        // Run via Process (not execDetached) so we can capture the output
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
        // Tell Hermes the user said no so it doesn't keep retrying
        if (window.hermesEnabled) window.reportToolResult(false, "User denied: " + cmd);
    }

    // ── Chess state ──
    property string lichessToken: ""

    // ── Hermes integration ──
    property bool hermesEnabled: false
    property string hermesEndpoint: "http://localhost:5400/api/agent"
    property string hermesToken: ""
    property string approvalPolicy: "ask"  // ask | auto | deny
    property bool approvalPending: false
    property string pendingCommand: ""
    property string pendingDescription: ""
    property string chessGameId: ""
    property string chessStatus: "menu" // menu, seeking, playing, ended
    property bool chessIsWhite: true
    property bool chessMyTurn: false
    property var chessBoard: []
    property int chessSelected: -1
    property string chessResult: ""
    property string chessOpponent: ""
    property int chessFromIdx: -1
    property int chessToIdx: -1

    // ── Kavita state ──
    property string kavitaUrl: "http://localhost:5000"  // overridden by ai_config.json
    property string kavitaApiKey: ""
    property string kavitaToken: ""
    property bool kavitaConnected: false
    property bool kavitaLoading: false
    ListModel { id: kavitaSeries }
    ListModel { id: kavitaOnDeck }
    ListModel { id: kavitaAllSeries }
    property string kavitaLibFilter: "all"
    property string kavitaSubMode: "ondeck"

    Timer {
        id: learnTypewriter; interval: 8; repeat: true
        running: learnTypeLen < learnLastResponse.length
        onTriggered: learnTypeLen = Math.min(learnTypeLen + 4, learnLastResponse.length)
    }

    // ── Chat state ──
    ListModel { id: chatMessages }
    property bool greetingFetched: false
    property string greetingText: "Hey! What can I help you with?"

    // ── Typewriter ──
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
                    if (cfg.lichess_token) window.lichessToken = cfg.lichess_token;
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
        id: noteSaver
        command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() !== "idle") {
                    window.noteAutoSaved = true;
                    autoSavedResetTimer.restart();
                }
            }
        }
    }

    // Auto-save debounce timer
    Timer {
        id: autoSaveTimer; interval: 1200; repeat: false
        onTriggered: {
            if (window.currentNoteFilepath === "" || noteArea.text.trim() === "") return;
            // Refuse paths outside the configured Obsidian vault to prevent
            // a stray UI bug from overwriting arbitrary files.
            if (window.obsidianVault !== "" && window.currentNoteFilepath.indexOf(window.obsidianVault) !== 0) {
                console.warn("Refusing to save note outside vault:", window.currentNoteFilepath);
                return;
            }
            let b64 = Qt.btoa(noteArea.text);
            noteSaver.command = ["bash", "-c",
                "echo " + b64 + " | base64 -d > '" + window.currentNoteFilepath.replace(/'/g, "'\\''") + "'"
            ];
            noteSaver.running = false;
            noteSaver.running = true;
        }
    }

    // Reset auto-saved indicator
    Timer {
        id: autoSavedResetTimer; interval: 2000; repeat: false
        onTriggered: window.noteAutoSaved = false
    }

    // ── Create new note ──
    function createNewNote() {
        // Generate filepath, create on disk, then open in editor
        newNoteCreator.command = ["bash", "-c",
            "VAULT=$(find ~/Documents ~/Notes ~/Obsidian -name .obsidian -maxdepth 2 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo $HOME/Notes) && " +
            "mkdir -p $VAULT/QuickNotes && " +
            "FP=$VAULT/QuickNotes/$(date +%Y-%m-%d_%H%M%S).md && " +
            "touch $FP && echo $FP"
        ];
        newNoteCreator.running = false;
        newNoteCreator.running = true;
    }

    Process {
        id: newNoteCreator
        command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "idle") return;
                let fp = this.text.trim();
                window.currentNoteFilepath = fp;
                window.selectedNoteTitle = fp.split("/").pop().replace(".md", "");
                noteArea.text = "";
                window.notesSubMode = "edit";
                noteArea.forceActiveFocus();
            }
        }
    }

    // ── Vault notes fetcher ──
    function fetchVaultNotes() {
        window.notesLoading = true;
        vaultNotesFetcher.command = ["bash", "-c",
            "VAULT=$(find ~/Documents ~/Notes ~/Obsidian -name .obsidian -maxdepth 2 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo $HOME/Notes) && " +
            "find $VAULT -name '*.md' -type f -printf '%T@ %p\\n' 2>/dev/null | sort -rn | head -50 | while read ts path; do " +
            "name=$(basename \"$path\" .md); " +
            "dir=$(dirname \"$path\" | sed \"s|$VAULT/||;s|$VAULT||\"); " +
            "preview=$(head -c 120 \"$path\" 2>/dev/null | tr '\\n' ' '); " +
            "echo \"$name|||$dir|||$path|||$preview\"; done"
        ];
        vaultNotesFetcher.running = false;
        vaultNotesFetcher.running = true;
    }

    Process {
        id: vaultNotesFetcher
        command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                window.notesLoading = false;
                if (this.text.trim() === "idle") return;
                vaultNotes.clear();
                let lines = this.text.trim().split("\n");
                for (let i = 0; i < lines.length; i++) {
                    let parts = lines[i].split("|||");
                    if (parts.length >= 4) {
                        vaultNotes.append({
                            name: parts[0].trim(),
                            folder: parts[1].trim(),
                            filepath: parts[2].trim(),
                            preview: parts[3].trim()
                        });
                    }
                }
            }
        }
    }

    // ── Individual note reader (opens in editor) ──
    function readNote(filepath, title) {
        window.selectedNoteTitle = title;
        window.currentNoteFilepath = filepath;
        noteReader.command = ["bash", "-c", "cat '" + filepath.replace(/'/g, "'\\''") + "' 2>/dev/null || echo ''"];
        noteReader.running = false;
        noteReader.running = true;
    }

    Process {
        id: noteReader
        command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() !== "idle") {
                    noteArea.text = this.text;
                    window.notesSubMode = "edit";
                    noteArea.forceActiveFocus();
                }
            }
        }
    }

    // ══════════════════════════════════════════
    // LEARN ENGINE
    // ══════════════════════════════════════════

    // ── Chess: board helpers ──
    readonly property var chessPieceMap: ({
        'K': '\u2654', 'Q': '\u2655', 'R': '\u2656', 'B': '\u2657', 'N': '\u2658', 'P': '\u2659',
        'k': '\u265a', 'q': '\u265b', 'r': '\u265c', 'b': '\u265d', 'n': '\u265e', 'p': '\u265f'
    })

    function chessPieceChar(p) { return chessPieceMap[p] || ""; }

    function chessInitBoard() {
        let b = [];
        let start = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR";
        let ranks = start.split("/");
        for (let r = 0; r < 8; r++) {
            for (let c = 0; c < ranks[r].length; c++) {
                let ch = ranks[r][c];
                if (ch >= '1' && ch <= '8') { for (let e = 0; e < parseInt(ch); e++) b.push(""); }
                else b.push(ch);
            }
        }
        window.chessBoard = b;
        window.chessBoardChanged();
    }

    function chessParseFen(fen) {
        let b = [];
        let ranks = fen.split(" ")[0].split("/");
        for (let r = 0; r < 8; r++) {
            for (let c = 0; c < ranks[r].length; c++) {
                let ch = ranks[r][c];
                if (ch >= '1' && ch <= '8') { for (let e = 0; e < parseInt(ch); e++) b.push(""); }
                else b.push(ch);
            }
        }
        return b;
    }

    function chessApplyMoves(movesStr) {
        let b = chessParseFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR");
        if (movesStr.trim() === "") { window.chessBoard = b; window.chessBoardChanged(); return; }
        let moves = movesStr.trim().split(" ");
        for (let m = 0; m < moves.length; m++) {
            let uci = moves[m];
            let ff = uci.charCodeAt(0) - 97;
            let fr = 8 - parseInt(uci[1]);
            let tf = uci.charCodeAt(2) - 97;
            let tr = 8 - parseInt(uci[3]);
            let fi = fr * 8 + ff;
            let ti = tr * 8 + tf;
            let piece = b[fi];
            let promo = uci.length > 4 ? uci[4] : "";

            // En passant
            if ((piece === "P" || piece === "p") && ff !== tf && b[ti] === "")
                b[fr * 8 + tf] = "";

            // Castling
            if (piece === "K" || piece === "k") {
                if (tf - ff === 2) { b[fr * 8 + 5] = b[fr * 8 + 7]; b[fr * 8 + 7] = ""; }
                if (ff - tf === 2) { b[fr * 8 + 3] = b[fr * 8 + 0]; b[fr * 8 + 0] = ""; }
            }

            b[fi] = "";
            if (promo) {
                let isW = piece === "P";
                let pm = {"q": isW?"Q":"q", "r": isW?"R":"r", "b": isW?"B":"b", "n": isW?"N":"n"};
                b[ti] = pm[promo] || piece;
            } else {
                b[ti] = piece;
            }
        }
        window.chessBoard = b;
        window.chessBoardChanged();
        // Determine whose turn
        let moveCount = movesStr.trim().split(" ").length;
        window.chessMyTurn = (moveCount % 2 === 0) === window.chessIsWhite;
        // Track last move for highlighting
        let last = moves[moves.length - 1];
        window.chessFromIdx = (8 - parseInt(last[1])) * 8 + (last.charCodeAt(0) - 97);
        window.chessToIdx = (8 - parseInt(last[3])) * 8 + (last.charCodeAt(2) - 97);
    }

    function chessIdxToUci(idx) {
        let f = idx % 8;
        let r = Math.floor(idx / 8);
        return String.fromCharCode(97 + f) + (8 - r).toString();
    }

    function chessSquareClicked(idx) {
        // Flip index if playing black
        let realIdx = window.chessIsWhite ? idx : (63 - idx);
        let piece = window.chessBoard[realIdx];

        if (window.chessSelected >= 0) {
            // Already selected - try to move
            let fromUci = chessIdxToUci(window.chessSelected);
            let toUci = chessIdxToUci(realIdx);
            let move = fromUci + toUci;

            // Auto-queen promotion
            let movingPiece = window.chessBoard[window.chessSelected];
            let toRank = Math.floor(realIdx / 8);
            if ((movingPiece === "P" && toRank === 0) || (movingPiece === "p" && toRank === 7))
                move += "q";

            window.chessSelected = -1;
            window.chessBoardChanged();
            chessMakeMove(move);
        } else {
            // Select a piece
            let isMyPiece = window.chessIsWhite ? (piece >= "A" && piece <= "Z") : (piece >= "a" && piece <= "z");
            if (isMyPiece && window.chessMyTurn) {
                window.chessSelected = realIdx;
                window.chessBoardChanged();
            }
        }
    }

    function chessStartAi(level, minutes) {
        window.chessStatus = "seeking";
        window.chessInitBoard();
        window.chessSelected = -1;
        window.chessResult = "";
        chessCreateProc.command = ["bash", "-c",
            "LT=\"" + window.lichessToken.replace(/[\"\\$`]/g,"") + "\" curl -s -X POST 'https://lichess.org/api/challenge/ai' " +
            "-H \"Authorization: Bearer $LT\" " +
            "-d 'level=" + level + "&clock.limit=" + (minutes * 60) + "&clock.increment=2' 2>/dev/null"
        ];
        chessCreateProc.running = false;
        chessCreateProc.running = true;
    }

    function chessSeekGame(minutes) {
        window.chessStatus = "seeking";
        window.chessInitBoard();
        window.chessSelected = -1;
        window.chessResult = "";
        chessCreateProc.command = ["bash", "-c",
            "LT=\"" + window.lichessToken.replace(/[\"\\$`]/g,"") + "\" curl -s -X POST 'https://lichess.org/api/board/seek' " +
            "-H \"Authorization: Bearer $LT\" " +
            "-d 'time=" + minutes + "&increment=2&rated=false' 2>/dev/null"
        ];
        chessCreateProc.running = false;
        chessCreateProc.running = true;
    }

    function chessMakeMove(move) {
        chessMoveProc.command = ["bash", "-c",
            "LT=\"" + window.lichessToken.replace(/[\"\\$`]/g,"") + "\" curl -s -X POST 'https://lichess.org/api/board/game/" + window.chessGameId.replace(/[^a-zA-Z0-9]/g,"") + "/move/" + move.replace(/[^a-h0-9qrbn]/g,"") + "' " +
            "-H \"Authorization: Bearer $LT\" 2>/dev/null"
        ];
        chessMoveProc.running = false;
        chessMoveProc.running = true;
    }

    function chessResign() {
        Quickshell.execDetached(["bash", "-c",
            "LT=\"" + window.lichessToken.replace(/[\"\\$`]/g,"") + "\" curl -s -X POST 'https://lichess.org/api/board/game/" + window.chessGameId.replace(/[^a-zA-Z0-9]/g,"") + "/resign' " +
            "-H \"Authorization: Bearer $LT\" 2>/dev/null"
        ]);
    }

    function chessProcessEvent(eventText) {
        try {
            let ev = JSON.parse(eventText);
            if (ev.type === "gameFull") {
                window.chessGameId = ev.id || window.chessGameId;
                window.chessIsWhite = (ev.white && ev.white.id && ev.white.name) ?
                    ev.white.name !== "" : true;
                // Check if our token user is white
                let whiteId = ev.white ? (ev.white.id || "") : "";
                let blackId = ev.black ? (ev.black.id || "") : "";
                // We figure out color from the game
                if (ev.white && ev.white.aiLevel) window.chessIsWhite = false;
                else if (ev.black && ev.black.aiLevel) window.chessIsWhite = true;

                window.chessOpponent = window.chessIsWhite ?
                    (ev.black ? (ev.black.name || ev.black.aiLevel ? "Stockfish L" + ev.black.aiLevel : "Opponent") : "Opponent") :
                    (ev.white ? (ev.white.name || "Opponent") : "Opponent");

                window.chessStatus = "playing";
                if (ev.state && ev.state.moves !== undefined) {
                    if (ev.state.moves === "") {
                        window.chessInitBoard();
                        window.chessMyTurn = window.chessIsWhite;
                    } else {
                        window.chessApplyMoves(ev.state.moves);
                    }
                } else {
                    window.chessInitBoard();
                    window.chessMyTurn = window.chessIsWhite;
                }
                if (ev.state && ev.state.status && ev.state.status !== "started" && ev.state.status !== "created") {
                    window.chessStatus = "ended";
                    window.chessResult = ev.state.status;
                    window.saveChessState();
                }
            } else if (ev.type === "gameState") {
                if (ev.moves !== undefined) {
                    if (ev.moves === "") {
                        window.chessInitBoard();
                        window.chessMyTurn = window.chessIsWhite;
                    } else {
                        window.chessApplyMoves(ev.moves);
                    }
                }
                if (ev.status && ev.status !== "started") {
                    window.chessStatus = "ended";
                    window.chessResult = ev.status;
                    window.saveChessState();
                }
            }
        } catch(e) {}
    }

    function chessReconnectStream() {
        // Use execDetached so stream survives popup close
        Quickshell.execDetached(["bash", "-c",
            "pkill -f 'chess_stream.sh.*" + window.chessGameId + "' 2>/dev/null; " +
            "LICHESS_TOKEN=\"" + window.lichessToken.replace(/[\"\\]/g,"") + "\" ~/.config/hypr/scripts/quickshell/chess_stream.sh " + window.chessGameId.replace(/[^a-zA-Z0-9]/g,"") + " &"
        ]);
        // Start watching events
        chessEventWatcher.running = false;
        chessEventWatcher.running = true;
    }

    // ── Chess: API processes ──
    Process {
        id: chessCreateProc; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "idle") return;
                try {
                    let data = JSON.parse(this.text.trim());
                    if (data.id) {
                        window.chessGameId = data.id;
                        window.chessStatus = "playing";
                        // Start streaming (detached so it survives popup close)
                        Quickshell.execDetached(["bash", "-c",
                            "pkill -f 'chess_stream.sh.*' 2>/dev/null; " +
                            "LICHESS_TOKEN=\"" + window.lichessToken.replace(/[\"\\]/g,"") + "\" ~/.config/hypr/scripts/quickshell/chess_stream.sh " + window.chessGameId.replace(/[^a-zA-Z0-9]/g,"") + " &"
                        ]);
                        window.saveChessState();
                        // Start watching events
                        chessEventWatcher.running = false;
                        chessEventWatcher.running = true;
                    }
                } catch(e) {
                    window.chessStatus = "menu";
                }
            }
        }
    }
    Process { id: chessMoveProc; command: ["bash", "-c", "echo idle"]; stdout: StdioCollector { onStreamFinished: {} } }
    Process { id: chessStreamProc; command: ["bash", "-c", "echo idle"] }

    // Watch /tmp/qs_chess_event for game updates
    Process {
        id: chessEventWatcher
        command: ["bash", "-c", "inotifywait -qq -e modify,close_write /tmp/qs_chess_event 2>/dev/null || sleep 60"]
        onExited: {
            chessEventReader.running = false;
            chessEventReader.running = true;
            running = false;
            running = true;
        }
    }
    Process {
        id: chessEventReader; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "idle" || this.text.trim() === "") return;
                window.chessProcessEvent(this.text.trim());
            }
        }
    }

    // Trigger event reader
    Connections {
        target: chessEventWatcher
        function onExited() {
            chessEventReader.command = ["bash", "-c", "cat /tmp/qs_chess_event 2>/dev/null || echo idle"];
            chessEventReader.running = false;
            chessEventReader.running = true;
        }
    }

    Component.onCompleted: {
        window.chessInitBoard();
        window.loadCache("chat");
        // Static greeting — no cloud call needed
        window.greetingFetched = true;
    }

    // ── Kavita authentication ──
    function kavitaAuth() {
        if (!window.kavitaUrl || !window.kavitaApiKey) return;
        kavitaAuthProc.command = ["bash", "-c",
            "curl -s -X POST '" + window.kavitaUrl + "/api/Plugin/authenticate?apiKey=" + window.kavitaApiKey + "&pluginName=quickshell-learn' " +
            "-H 'Content-Type: application/json' 2>/dev/null"
        ];
        kavitaAuthProc.running = false;
        kavitaAuthProc.running = true;
    }

    Process {
        id: kavitaAuthProc
        command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "idle") return;
                try {
                    let data = JSON.parse(this.text.trim());
                    if (data.token) {
                        window.kavitaToken = data.token;
                        window.kavitaConnected = true;
                        window.kavitaFetchSeries();
                    }
                } catch(e) {
                    window.kavitaConnected = false;
                }
            }
        }
    }

    // ── Fetch series from Kavita ──
    function kavitaFetchSeries() {
        if (!window.kavitaToken) return;
        window.kavitaLoading = true;
        kavitaSeriesProc.command = ["bash", "-c",
            "curl -s -X POST '" + window.kavitaUrl + "/api/Series/all-v2' " +
            "-H 'Authorization: Bearer " + window.kavitaToken + "' " +
            "-H 'Content-Type: application/json' " +
            "-d '{\"statements\":[],\"combination\":1,\"sortOptions\":{\"sortField\":1,\"isAscending\":true},\"limitTo\":0}' 2>/dev/null"
        ];
        kavitaSeriesProc.running = false;
        kavitaSeriesProc.running = true;
    }

    Process {
        id: kavitaSeriesProc
        command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                window.kavitaLoading = false;
                if (this.text.trim() === "idle") return;
                try {
                    let data = JSON.parse(this.text.trim());
                    kavitaSeries.clear();
                    kavitaAllSeries.clear();
                    let arr = data || [];
                    for (let i = 0; i < arr.length; i++) {
                        let entry = {
                            seriesId: arr[i].id || 0,
                            name: arr[i].name || "Unknown",
                            libraryName: arr[i].libraryName || "",
                            libraryId: arr[i].libraryId || 0,
                            pages: arr[i].pages || 0,
                            pagesRead: arr[i].pagesRead || 0,
                            format: arr[i].format || 0
                        };
                        kavitaAllSeries.append(entry);
                        if ((arr[i].libraryName || "").toLowerCase() === "textbooks")
                            kavitaSeries.append(entry);
                    }
                    window.kavitaFetchOnDeck();
                } catch(e) {}
            }
        }
    }

    function kavitaFetchOnDeck() {
        if (!window.kavitaToken) return;
        kavitaOnDeckProc.command = ["bash", "-c",
            "curl -s '" + window.kavitaUrl + "/api/Series/on-deck?pageNumber=0&pageSize=20' " +
            "-H 'Authorization: Bearer " + window.kavitaToken + "' 2>/dev/null"
        ];
        kavitaOnDeckProc.running = false;
        kavitaOnDeckProc.running = true;
    }
    Process {
        id: kavitaOnDeckProc; command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "idle") return;
                try {
                    let data = JSON.parse(this.text.trim());
                    kavitaOnDeck.clear();
                    let arr = data || [];
                    for (let i = 0; i < arr.length; i++) {
                        kavitaOnDeck.append({
                            seriesId: arr[i].id || 0, name: arr[i].name || "Unknown",
                            libraryName: arr[i].libraryName || "", libraryId: arr[i].libraryId || 0,
                            pages: arr[i].pages || 0, pagesRead: arr[i].pagesRead || 0
                        });
                    }
                } catch(e) {}
            }
        }
    }
    function kavitaOpenSeries(sid, lid, name) {
        window.kavitaLastSeriesId = sid;
        window.kavitaLastLibraryId = lid;
        window.kavitaLastName = name || "";
        window.saveKavitaLast(sid, lid, name || "");
        Quickshell.execDetached(["xdg-open", window.kavitaUrl + "/library/" + lid + "/series/" + sid]);
    }

    // ── Download book from Kavita ──
    function kavitaDownloadBook(seriesId, name) {
        window.learnLoading = true;
        window.bookTitle = name;
        kavitaDownloadProc.command = ["bash", "-c",
            "LDIR=$HOME/.local/share/quickshell-learn && mkdir -p $LDIR && " +
            "curl -s '" + window.kavitaUrl + "/api/Series/series-detail?seriesId=" + seriesId + "' " +
            "-H 'Authorization: Bearer " + window.kavitaToken + "' 2>/dev/null"
        ];
        kavitaDownloadProc.running = false;
        kavitaDownloadProc.running = true;
    }

    Process {
        id: kavitaDownloadProc
        command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "idle") return;
                try {
                    let detail = JSON.parse(this.text.trim());
                    // Get first volume's ID for download
                    let volumes = detail.volumes || [];
                    let volId = -1;
                    for (let i = 0; i < volumes.length; i++) {
                        if (volumes[i].id) { volId = volumes[i].id; break; }
                    }
                    if (volId >= 0) {
                        // Download the volume file
                        kavitaFileDownloader.command = ["bash", "-c",
                            "LDIR=$HOME/.local/share/quickshell-learn && mkdir -p $LDIR && " +
                            "curl -s '" + window.kavitaUrl + "/api/Download/volume?volumeId=" + volId + "' " +
                            "-H 'Authorization: Bearer " + window.kavitaToken + "' " +
                            "-o $LDIR/kavita_book.download 2>/dev/null && " +
                            "MIME=$(file -b --mime-type $LDIR/kavita_book.download) && " +
                            "case $MIME in " +
                            "  application/pdf) mv $LDIR/kavita_book.download $LDIR/kavita_book.pdf && echo $LDIR/kavita_book.pdf;; " +
                            "  application/epub*) mv $LDIR/kavita_book.download $LDIR/kavita_book.epub && echo $LDIR/kavita_book.epub;; " +
                            "  application/zip|application/x-cbz) " +
                            "    mv $LDIR/kavita_book.download $LDIR/kavita_book.zip && " +
                            "    mkdir -p $LDIR/extracted && cd $LDIR/extracted && unzip -o $LDIR/kavita_book.zip '*.txt' '*.html' '*.xhtml' 2>/dev/null && " +
                            "    find $LDIR/extracted -type f \\( -name '*.txt' -o -name '*.html' -o -name '*.xhtml' \\) -exec cat {} + > $LDIR/kavita_book.txt && " +
                            "    echo $LDIR/kavita_book.txt;; " +
                            "  text/*) mv $LDIR/kavita_book.download $LDIR/kavita_book.txt && echo $LDIR/kavita_book.txt;; " +
                            "  *) mv $LDIR/kavita_book.download $LDIR/kavita_book.pdf && echo $LDIR/kavita_book.pdf;; " +
                            "esac"
                        ];
                        kavitaFileDownloader.running = false;
                        kavitaFileDownloader.running = true;
                    } else {
                        window.learnLoading = false;
                    }
                } catch(e) {
                    window.learnLoading = false;
                }
            }
        }
    }

    Process {
        id: kavitaFileDownloader
        command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "idle") return;
                let fp = this.text.trim();
                if (fp && fp.length > 0) {
                    window.processBook(fp);
                } else {
                    window.learnLoading = false;
                }
            }
        }
    }

    // ── Load saved learn config on startup ──
    function loadLearnConfig() {
        learnConfigLoader.command = ["bash", "-c",
            "LDIR=$HOME/.local/share/quickshell-learn && " +
            "cat $LDIR/book_meta.json 2>/dev/null && echo '|||SPLIT|||' && " +
            "cat $LDIR/progress.json 2>/dev/null"
        ];
        learnConfigLoader.running = false;
        learnConfigLoader.running = true;
    }

    Process {
        id: learnConfigLoader
        command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "idle") return;
                let parts = this.text.split("|||SPLIT|||");
                try {
                    let meta = JSON.parse(parts[0].trim());
                    window.bookTitle = meta.title || "";
                    window.totalChapters = meta.total || 0;
                    window.bookLoaded = meta.total > 0;
                    bookChapters.clear();
                    for (let i = 0; i < meta.chapters.length; i++) {
                        bookChapters.append({
                            title: meta.chapters[i].title,
                            chIndex: meta.chapters[i].index,
                            filepath: meta.chapters[i].filepath
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
                            learnedTerms.append(vocab[i]);
                                    window.saveLearnState();
                        }
                    } catch(e) {}
                }
            }
        }
    }

    Timer {
        id: learnBootTimer; interval: 1200; repeat: false; running: true
        onTriggered: window.loadLearnConfig()
    }

    // ── Process a book file ──
    function processBook(filepath) {
        window.learnLoading = true;
        // Write processor script then run it
        bookProcessor.command = ["bash", "-c",
            "LDIR=$HOME/.local/share/quickshell-learn && mkdir -p $LDIR/chapters && " +
            "python3 -c '" +
            "import re,json,os,sys\n" +
            "fp=sys.argv[1]\n" +
            "ld=os.path.expanduser(\"~/.local/share/quickshell-learn\")\n" +
            "cd=os.path.join(ld,\"chapters\")\n" +
            "os.makedirs(cd,exist_ok=True)\n" +
            "ext=fp.rsplit(\".\",1)[-1].lower()\n" +
            "if ext==\"pdf\":\n" +
            " import subprocess;r=subprocess.run([\"pdftotext\",fp,\"-\"],capture_output=True,text=True);text=r.stdout\n" +
            "else:\n" +
            " text=open(fp,encoding=\"utf-8\",errors=\"replace\").read()\n" +
            "pats=[r\"(?m)^(?:Chapter|CHAPTER|Lesson|LESSON|Unit|UNIT|第)\\\\s*[\\\\d一二三四五六七八九十]+\",r\"(?m)^#{1,3}\\\\s+.+\",r\"(?m)^\\\\d+[\\\\.)\\\\s]+[A-Z].{5,}\"]\n" +
            "sp=None\n" +
            "for p in pats:\n" +
            " m=list(re.finditer(p,text))\n" +
            " if len(m)>=2:sp=m;break\n" +
            "chs=[]\n" +
            "if sp and len(sp)>=2:\n" +
            " for i,m in enumerate(sp):\n" +
            "  s=m.start();e=sp[i+1].start() if i+1<len(sp) else len(text)\n" +
            "  ch=text[s:e].strip()\n" +
            "  if not ch:continue\n" +
            "  t=ch.split(chr(10))[0].strip()[:80]\n" +
            "  fn=f\"ch_{i:03d}.txt\"\n" +
            "  open(os.path.join(cd,fn),\"w\").write(ch)\n" +
            "  chs.append({\"title\":t,\"index\":i,\"filepath\":os.path.join(cd,fn)})\n" +
            "else:\n" +
            " cs=3000\n" +
            " for i in range(0,len(text),cs):\n" +
            "  ch=text[i:i+cs].strip()\n" +
            "  if not ch:continue\n" +
            "  ix=i//cs;t=ch.split(chr(10))[0].strip()[:60] or f\"Section {ix+1}\"\n" +
            "  fn=f\"ch_{ix:03d}.txt\"\n" +
            "  open(os.path.join(cd,fn),\"w\").write(ch)\n" +
            "  chs.append({\"title\":t,\"index\":ix,\"filepath\":os.path.join(cd,fn)})\n" +
            "bt=os.path.basename(fp).rsplit(\".\",1)[0]\n" +
            "meta={\"title\":bt,\"source\":fp,\"chapters\":chs,\"total\":len(chs)}\n" +
            "json.dump(meta,open(os.path.join(ld,\"book_meta.json\"),\"w\"))\n" +
            "pp=os.path.join(ld,\"progress.json\")\n" +
            "if not os.path.exists(pp):json.dump({\"current_chapter\":0,\"vocab\":[]},open(pp,\"w\"))\n" +
            "print(json.dumps(meta))\n" +
            "' '" + filepath.replace(/'/g, "'\\''") + "'"
        ];
        bookProcessor.running = false;
        bookProcessor.running = true;
    }

    Process {
        id: bookProcessor
        command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                window.learnLoading = false;
                if (this.text.trim() === "idle") return;
                try {
                    let meta = JSON.parse(this.text.trim().split("\n").pop());
                    window.bookTitle = meta.title || "";
                    window.totalChapters = meta.total || 0;
                    window.bookLoaded = meta.total > 0;
                    window.currentChapter = 0;
                    bookChapters.clear();
                    for (let i = 0; i < meta.chapters.length; i++) {
                        bookChapters.append({
                            title: meta.chapters[i].title,
                            chIndex: meta.chapters[i].index,
                            filepath: meta.chapters[i].filepath
                        });
                    }
                } catch(e) {
                    window.bookTitle = "Error loading book";
                }
            }
        }
    }

    // ── Load a chapter's content ──
    function loadChapter(index) {
        if (index < 0 || index >= bookChapters.count) return;
        let ch = bookChapters.get(index);
        window.currentChapter = index;
        window.currentChapterTitle = ch.title;
        chapterLoader.command = ["bash", "-c", "cat '" + ch.filepath.replace(/'/g, "'\\''") + "' 2>/dev/null"];
        chapterLoader.running = false;
        chapterLoader.running = true;
    }

    Process {
        id: chapterLoader
        command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() !== "idle")
                    window.currentChapterContent = this.text;
            }
        }
    }

    // ── Start a lesson ──
    function startLesson() {
        if (!window.bookLoaded) return;
        // Export current vocab to Obsidian before starting new chapter
        if (learnedTerms.count > 0) window.exportVocabToObsidian();
        window.learnSubMode = "lesson";
        window.learnLoading = true;
        lessonChat.clear();
        window.loadChapter(window.currentChapter);

        // Wait for chapter to load, then generate
        lessonStartTimer.restart();
    }

    Timer {
        id: lessonStartTimer; interval: 800; repeat: false
        onTriggered: {
            let vocabList = [];
            for (let i = 0; i < learnedTerms.count; i++) {
                let t = learnedTerms.get(i);
                vocabList.push(t.term + " (" + t.meaning + ")");
            }

            let sysPrompt = "You are a language tutor. The student is studying from a textbook. " +
                "Here is the current chapter content:\\n\\n" + window.currentChapterContent.substring(0, 4000) +
                "\\n\\nThe student has already learned these terms: " + vocabList.join(", ") +
                "\\n\\nYour job: 1) Briefly introduce what this chapter covers. " +
                "2) Teach the key vocabulary and grammar points from this chapter. " +
                "3) Give practice exercises. 4) When the student speaks or types, evaluate their response. " +
                "5) Use the target language mixed with English explanations. " +
                "6) At the end of each response, list NEW vocabulary in this exact format on separate lines: " +
                "VOCAB:term|reading|meaning (e.g. VOCAB:食べる|たべる|to eat). " +
                "Be encouraging and conversational like Duolingo. Keep responses focused and not too long.";

            let payload = JSON.stringify({
                model: window.selectedModel,
                stream: false,
                messages: [
                    { role: "system", content: sysPrompt },
                    { role: "user", content: "I'm ready to start this chapter. Please begin the lesson!" }
                ]
            });

            let escaped = payload.replace(/'/g, "'\\''");
            learnApiCaller.command = ["bash", "-c",
                "echo '" + escaped + "' | curl -s -X POST '" + window.apiBaseUrl + "/api/chat/completions' " +
                "-H 'Authorization: Bearer " + window.apiKey + "' " +
                "-H 'Content-Type: application/json' " +
                "-d @- 2>/dev/null"
            ];
            learnApiCaller.running = false;
            learnApiCaller.running = true;
        }
    }

    // ── Send message to AI tutor ──
    function sendLearnMessage(text) {
        if (text.trim() === "" || window.learnLoading) return;
        lessonChat.append({ role: "user", content: text });
        window.learnLoading = true;
        window.learnTypeLen = 0;
        window.learnLastResponse = "";

        let msgs = [{ role: "system", content:
            "You are a language tutor continuing a lesson. Chapter content (abbreviated):\\n" +
            window.currentChapterContent.substring(0, 3000) +
            "\\nEvaluate student responses for correctness. Teach vocabulary and grammar from the chapter. " +
            "End each response with any NEW vocab as VOCAB:term|reading|meaning lines. Be encouraging."
        }];
        for (let i = 0; i < lessonChat.count; i++) {
            let m = lessonChat.get(i);
            msgs.push({ role: m.role, content: m.content });
        }

        let payload = JSON.stringify({ model: window.selectedModel, stream: false, messages: msgs });
        let escaped = payload.replace(/'/g, "'\\''");
        learnApiCaller.command = ["bash", "-c",
            "echo '" + escaped + "' | curl -s -X POST '" + window.apiBaseUrl + "/api/chat/completions' " +
            "-H 'Authorization: Bearer " + window.apiKey + "' " +
            "-H 'Content-Type: application/json' " +
            "-d @- 2>/dev/null"
        ];
        learnApiCaller.running = false;
        learnApiCaller.running = true;
    }

    Process {
        id: learnApiCaller
        command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "idle") return;
                window.learnLoading = false;
                try {
                    let data = JSON.parse(this.text.trim());
                    let resp = data.choices[0].message.content;

                    // Extract VOCAB lines
                    let lines = resp.split("\n");
                    let cleanLines = [];
                    for (let i = 0; i < lines.length; i++) {
                        if (lines[i].trim().startsWith("VOCAB:")) {
                            let parts = lines[i].trim().substring(6).split("|");
                            if (parts.length >= 3) {
                                // Check if already known
                                let exists = false;
                                for (let j = 0; j < learnedTerms.count; j++) {
                                    if (learnedTerms.get(j).term === parts[0].trim()) { exists = true; break; }
                                }
                                if (!exists) {
                                    learnedTerms.append({
                                        term: parts[0].trim(),
                                        reading: parts[1].trim(),
                                        meaning: parts[2].trim(),
                                        mastery: 1
                                    });
                                    window.saveLearnState();
                                }
                            }
                        } else {
                            cleanLines.push(lines[i]);
                        }
                    }

                    let cleanResp = cleanLines.join("\n").trim();
                    lessonChat.append({ role: "assistant", content: cleanResp });
                    window.learnLastResponse = cleanResp;
                    window.learnTypeLen = 0;
                    window.saveLearnProgress();
                } catch(e) {
                    lessonChat.append({ role: "assistant", content: "Error: Could not get response." });
                    window.learnLastResponse = "Error: Could not get response.";
                    window.learnTypeLen = 0;
                }
            }
        }
    }

    // ── Voice recording ──
    function startRecording() {
        window.isRecording = true;
        window.voiceTranscript = "";
        voiceRecorderProc.command = ["bash", "-c",
            "arecord -f S16_LE -r 16000 -c 1 -t wav /tmp/qs_learn_voice.wav 2>/dev/null || " +
            "pw-record --format=s16 --rate=16000 --channels=1 /tmp/qs_learn_voice.wav 2>/dev/null || " +
            "parecord --format=s16le --rate=16000 --channels=1 /tmp/qs_learn_voice.wav 2>/dev/null"
        ];
        voiceRecorderProc.running = false;
        voiceRecorderProc.running = true;
    }

    function stopRecording() {
        window.isRecording = false;
        voiceRecorderProc.signal(15); // SIGTERM
        // Wait a bit then transcribe
        voiceTranscribeDelay.restart();
    }

    Process {
        id: voiceRecorderProc
        command: ["bash", "-c", "echo idle"]
    }

    Timer {
        id: voiceTranscribeDelay; interval: 500; repeat: false
        onTriggered: {
            voiceTranscriberProc.command = ["bash", "-c",
                "if command -v whisper >/dev/null 2>&1; then " +
                "  whisper /tmp/qs_learn_voice.wav --model tiny --language auto --output_format txt --output_dir /tmp 2>/dev/null && " +
                "  cat /tmp/qs_learn_voice.txt 2>/dev/null; " +
                "elif command -v whisper-cpp >/dev/null 2>&1; then " +
                "  whisper-cpp -f /tmp/qs_learn_voice.wav 2>/dev/null; " +
                "else " +
                "  echo '[Voice requires whisper. Install: pip install openai-whisper]'; " +
                "fi"
            ];
            voiceTranscriberProc.running = false;
            voiceTranscriberProc.running = true;
        }
    }

    Process {
        id: voiceTranscriberProc
        command: ["bash", "-c", "echo idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() !== "idle" && this.text.trim() !== "") {
                    window.voiceTranscript = this.text.trim();
                    // Auto-send to AI tutor
                    if (!window.voiceTranscript.startsWith("[")) {
                        window.sendLearnMessage(window.voiceTranscript);
                        window.voiceTranscript = "";
                    }
                }
            }
        }
    }

    // ── Save / load progress ──
    function saveLearnProgress() {
        let vocab = [];
        for (let i = 0; i < learnedTerms.count; i++) {
            let t = learnedTerms.get(i);
            vocab.push({ term: t.term, reading: t.reading, meaning: t.meaning, mastery: t.mastery });
        }
        let prog = JSON.stringify({ current_chapter: window.currentChapter, vocab: vocab });
        let escaped = prog.replace(/'/g, "'\\''");
        learnProgressSaver.command = ["bash", "-c",
            "echo '" + escaped + "' > $HOME/.local/share/quickshell-learn/progress.json"
        ];
        learnProgressSaver.running = false;
        learnProgressSaver.running = true;
    }

    Process {
        id: learnProgressSaver
        command: ["bash", "-c", "echo idle"]
    }

    // ── Export vocab to Obsidian note ──
    function exportVocabToObsidian() {
        if (learnedTerms.count === 0) return;

        let lines = ["# " + window.bookTitle + " — Vocabulary", ""];
        lines.push("**Chapter " + (window.currentChapter + 1) + "**: " + window.currentChapterTitle);
        lines.push("**Exported**: " + new Date().toISOString().split("T")[0]);
        lines.push("**Total terms**: " + learnedTerms.count);
        lines.push("");
        lines.push("---");
        lines.push("");
        lines.push("| Term | Reading | Meaning | Mastery |");
        lines.push("|------|---------|---------|---------|");

        for (let i = 0; i < learnedTerms.count; i++) {
            let t = learnedTerms.get(i);
            let stars = "●".repeat(Math.min(t.mastery, 5)) + "○".repeat(Math.max(5 - t.mastery, 0));
            lines.push("| " + t.term + " | " + t.reading + " | " + t.meaning + " | " + stars + " |");
        }

        lines.push("");
        lines.push("---");
        lines.push("");
        lines.push("## Key Ideas");
        lines.push("");
        lines.push("_Auto-generated from learning session. Review and expand as needed._");

        let content = lines.join("\n");
        let b64 = Qt.btoa(content);
        let safeName = window.bookTitle.replace(/[^a-zA-Z0-9_\- ]/g, "").replace(/ /g, "_");

        vocabExporter.command = ["bash", "-c",
            "VAULT=$(find ~/Documents ~/Notes ~/Obsidian -name .obsidian -maxdepth 2 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo $HOME/Notes) && " +
            "mkdir -p $VAULT/Learning && " +
            "echo " + b64 + " | base64 -d > \"$VAULT/Learning/" + safeName + "_vocab.md\" && " +
            "echo exported"
        ];
        vocabExporter.running = false;
        vocabExporter.running = true;
    }

    Process {
        id: vocabExporter
        command: ["bash", "-c", "echo idle"]
    }

    // ── Advance chapter ──
    function advanceChapter() {
        if (window.currentChapter < window.totalChapters - 1) {
            window.exportVocabToObsidian();
            window.currentChapter++;
            window.saveLearnProgress();
            window.startLesson();
        }
    }

    // ── Auto-focus input ──
    Timer {
        id: focusTimer; interval: 600; repeat: false; running: true
        onTriggered: inputField.forceActiveFocus()
    }

    // ── Send message — Hermes-only ──
    function sendMessage(query) {
        if (query.trim() === "" || isLoading) return;
        chatMessages.append({ role: "user", content: query });
        window.saveChatState();

        if (window.hermesEnabled) {
            if (window.callHermes(query)) return;
        }

        // Hermes disabled or unreachable
        chatMessages.append({
            role: "assistant",
            content: "Hermes is not enabled. Set hermes_enabled=true in ~/.config/hypr/ai_config.json."
        });
        window.lastResponse = "Hermes is not enabled.";
        window.typeLen = 0;
        window.saveChatState();
    }

    // ── Orbit ──
    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: 12.5663706; duration: 180000; loops: Animation.Infinite; running: true
    }

    // ── Intro ──
    property real introMain: 0
    property real introTop: 0
    property real introChat: 0
    property real introInput: 0

    ParallelAnimation {
        running: true
        NumberAnimation { target: window; property: "introMain"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutQuart }
        SequentialAnimation {
            PauseAnimation { duration: 100 }
            NumberAnimation { target: window; property: "introTop"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutBack; easing.overshoot: 1.0 }
        }
        SequentialAnimation {
            PauseAnimation { duration: 200 }
            NumberAnimation { target: window; property: "introChat"; from: 0; to: 1.0; duration: 850; easing.type: Easing.OutQuart }
        }
        SequentialAnimation {
            PauseAnimation { duration: 350 }
            NumberAnimation { target: window; property: "introInput"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutExpo }
        }
    }

    // ═══════════════════════════════════════════
    // UI
    // ═══════════════════════════════════════════
    Item {
        anchors.fill: parent
        scale: 0.92 + (0.08 * introMain)
        opacity: introMain
        transform: Translate { y: window.s(15) * (1 - introMain) }

        Rectangle {
            anchors.fill: parent
            radius: window.s(20)
            color: window.base
            border.color: Qt.rgba(window.modeColor1.r, window.modeColor1.g, window.modeColor1.b, 0.15)
            border.width: 1
            Behavior on border.color { ColorAnimation { duration: 500 } }
            clip: true

            // ── Floating tools popup (above + button) ──
            Rectangle {
                id: toolsFloat
                visible: window.toolsPopupOpen && window.activeMode === "chat"
                width: window.s(160)
                height: visible ? toolsFloatCol.implicitHeight + window.s(12) : 0
                anchors.left: parent.left
                anchors.leftMargin: window.s(26)
                anchors.bottom: parent.bottom
                anchors.bottomMargin: window.s(100)
                radius: window.s(10)
                color: window.mantle
                border.color: window.surface1; border.width: 1
                z: 100
                clip: true

                Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutQuint } }

                // Shadow
                Rectangle {
                    anchors.fill: parent; anchors.margins: -1
                    radius: parent.radius + 1; color: "transparent"
                    border.color: Qt.rgba(0,0,0,0.3); border.width: 2; z: -1
                }

                Column {
                    id: toolsFloatCol
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.margins: window.s(6); spacing: window.s(2)

                    Repeater {
                        model: ListModel {
                            ListElement { icon: "󰍉"; label: "Web Search" }
                            ListElement { icon: "󰈙"; label: "Read File" }
                            ListElement { icon: "󰗀"; label: "Image Gen" }
                            ListElement { icon: "󰘦"; label: "Code" }
                            ListElement { icon: "󰗊"; label: "Translate" }
                        }
                        delegate: Rectangle {
                            width: parent.width; height: window.s(28)
                            radius: window.s(6)
                            color: tItemMa.containsMouse ? window.surface1 : "transparent"
                            Behavior on color { ColorAnimation { duration: 80 } }

                            Row {
                                anchors.left: parent.left; anchors.leftMargin: window.s(8)
                                anchors.verticalCenter: parent.verticalCenter; spacing: window.s(8)
                                Text {
                                    text: icon; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(13)
                                    color: window.activeTools[label] ? window.green : (tItemMa.containsMouse ? window.mauve : window.overlay1)
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: label; font.family: "JetBrains Mono"; font.pixelSize: window.s(10)
                                    color: window.activeTools[label] ? window.text : window.subtext0
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            // Checkmark
                            Text {
                                anchors.right: parent.right; anchors.rightMargin: window.s(8)
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰄬"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(13)
                                color: window.green
                                visible: window.activeTools[label] === true
                            }
                            // Checkmark
                            Text {
                                anchors.right: parent.right; anchors.rightMargin: window.s(8)
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰄬"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(12)
                                color: window.green
                                visible: window.activeTools[label] === true
                            }

                            MouseArea {
                                id: tItemMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    let tools = window.activeTools;
                                    tools[label] = !tools[label];
                                    window.activeTools = tools;
                                    inputField.forceActiveFocus();
                                }
                            }
                        }
                    }
                }
            }

            // Blobs
            Rectangle {
                width: parent.width * 0.8; height: width; radius: width / 2
                x: parent.width / 2 - width / 2 + Math.cos(window.globalOrbitAngle * 2) * window.s(150)
                y: parent.height / 2 - height / 2 + Math.sin(window.globalOrbitAngle * 2) * window.s(100)
                opacity: 0.08; color: window.modeColor1; Behavior on color { ColorAnimation { duration: 500 } }
            }
            Rectangle {
                width: parent.width * 0.9; height: width; radius: width / 2
                x: parent.width / 2 - width / 2 + Math.sin(window.globalOrbitAngle * 1.5) * window.s(-150)
                y: parent.height / 2 - height / 2 + Math.cos(window.globalOrbitAngle * 1.5) * window.s(-100)
                opacity: 0.06; color: window.modeColor2; Behavior on color { ColorAnimation { duration: 500 } }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: window.s(20)
                spacing: window.s(10)

                // ── Header: Title | Slider | App Button ──
                RowLayout {
                    Layout.fillWidth: true
                    Layout.minimumHeight: window.s(36)
                    Layout.maximumHeight: window.s(36)
                    spacing: window.s(10)
                    opacity: introTop
                    transform: Translate { y: window.s(-10) * (1.0 - introTop) }

                    // Title (left, clickable - opens the app)
                    Item {
                        Layout.preferredWidth: window.s(80)
                        Layout.fillHeight: true
                        Text {
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            text: window.activeMode === "chess" ? "Lichess"
                                : window.activeMode === "kavita" ? "Kavita"
                                : window.activeMode === "chat" ? "AI"
                                : window.activeMode === "notes" ? "Notes"
                                : "Learn"
                            font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(16)
                            color: titleMa.containsMouse ? Qt.lighter(window.modeColor1, 1.2) : window.modeColor1
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        MouseArea {
                            id: titleMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (window.activeMode === "chess") Quickshell.execDetached(["xdg-open", "https://lichess.org"]);
                                else if (window.activeMode === "kavita") Quickshell.execDetached(["xdg-open", window.kavitaUrl]);
                                else if (window.activeMode === "chat") Quickshell.execDetached(["xdg-open", window.apiBaseUrl]);
                                else if (window.activeMode === "notes") Quickshell.execDetached(["bash", "-c", "obsidian"]);
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: window.s(200)
                        Layout.fillHeight: true
                        radius: window.s(10); color: window.surface0
                        border.color: window.surface1; border.width: 1

                        property var modes: ["chess", "kavita", "chat", "notes", "learn"]
                        property int modeIdx: Math.max(0, modes.indexOf(window.activeMode))

                        Rectangle {
                            width: (parent.width - window.s(2)) / 5
                            height: parent.height - window.s(2)
                            y: window.s(1); radius: window.s(8)
                            x: parent.modeIdx * width + window.s(1)
                            Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }

                            property color c1: window.activeMode === "chess" ? window.yellow
                                : window.activeMode === "kavita" ? window.pink
                                : window.activeMode === "chat" ? window.mauve
                                : window.activeMode === "notes" ? window.peach
                                : window.green
                            property color c2: window.activeMode === "chess" ? window.peach
                                : window.activeMode === "kavita" ? window.mauve
                                : window.activeMode === "chat" ? window.blue
                                : window.activeMode === "notes" ? window.yellow
                                : window.teal
                            Behavior on c1 { ColorAnimation { duration: 300 } }
                            Behavior on c2 { ColorAnimation { duration: 300 } }

                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: parent.c1 }
                                GradientStop { position: 1.0; color: parent.c2 }
                            }
                        }
                        RowLayout {
                            anchors.fill: parent; spacing: 0
                            // Chess
                            Item {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                Text { anchors.centerIn: parent; text: "󰐹"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(14); color: window.activeMode === "chess" ? "#ffffff" : window.overlay0; Behavior on color { ColorAnimation { duration: 200 } } }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: window.activeMode = "chess" }
                            }
                            // Kavita
                            Item {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                Text { anchors.centerIn: parent; text: "󰀭"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(14); color: window.activeMode === "kavita" ? "#ffffff" : window.overlay0; Behavior on color { ColorAnimation { duration: 200 } } }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { window.activeMode = "kavita"; if (window.kavitaConnected) window.kavitaFetchOnDeck(); else window.kavitaAuth(); } }
                            }
                            // AI (chat)
                            Item {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                Text { anchors.centerIn: parent; text: "󰭻"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(14); color: window.activeMode === "chat" ? "#ffffff" : window.overlay0; Behavior on color { ColorAnimation { duration: 200 } } }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: window.activeMode = "chat" }
                            }
                            // Notes
                            Item {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                Text { anchors.centerIn: parent; text: "󰠮"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(14); color: window.activeMode === "notes" ? "#ffffff" : window.overlay0; Behavior on color { ColorAnimation { duration: 200 } } }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { window.activeMode = "notes"; window.notesSubMode = "menu"; window.fetchVaultNotes(); } }
                            }
                            // Learn
                            Item {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                Text { anchors.centerIn: parent; text: "󰗊"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(14); color: window.activeMode === "learn" ? "#ffffff" : window.overlay0; Behavior on color { ColorAnimation { duration: 200 } } }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { window.activeMode = "learn"; if (window.bookLoaded && window.learnSubMode === "home") { window.learnSubMode = "lesson"; window.startLesson(); } } }
                            }
                        }
                    }

                    // Right spacer (matches title width for centering)
                    Item {
                        Layout.preferredWidth: window.s(80)
                        Layout.fillHeight: true
                    }
                }

                // ══════════════════════════════════════
                // CHAT MODE
                // ══════════════════════════════════════
                Item {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    visible: window.activeMode === "chat"

                    ColumnLayout {
                        anchors.fill: parent; spacing: window.s(8)

                        // ── Top bar: temp indicator + New Chat button ──
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: window.s(28)
                            spacing: window.s(8)

                            Item { Layout.fillWidth: true }

                            Text {
                                visible: window.temporaryChat
                                text: "Temporary — not saved"
                                font.family: "JetBrains Mono"; font.pixelSize: window.s(9)
                                color: window.peach
                                Layout.alignment: Qt.AlignVCenter
                            }

                            Rectangle {
                                Layout.preferredWidth: newChatRow.implicitWidth + window.s(16)
                                Layout.preferredHeight: window.s(26)
                                radius: window.s(8)
                                color: newChatMa.containsMouse
                                    ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8)
                                    : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.5)
                                border.color: newChatMa.containsMouse
                                    ? window.mauve
                                    : Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.5)
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }

                                Row {
                                    id: newChatRow
                                    anchors.centerIn: parent; spacing: window.s(6)
                                    Text {
                                        text: "󰝒"
                                        font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(13)
                                        color: window.mauve
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: "New Chat"
                                        font.family: "JetBrains Mono"; font.weight: Font.Bold
                                        font.pixelSize: window.s(10)
                                        color: newChatMa.containsMouse ? window.text : window.subtext0
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                MouseArea {
                                    id: newChatMa
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        chatMessages.clear();
                                        window.lastResponse = "";
                                        window.typeLen = 0;
                                        window.temporaryChat = true;
                                        inputField.forceActiveFocus();
                                    }
                                }
                            }
                        }

                        // Greeting (empty state)
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            visible: chatMessages.count === 0
                            opacity: introChat

                            ColumnLayout {
                                anchors.centerIn: parent; spacing: window.s(12); width: parent.width * 0.8

                                Text {
                                    text: window.greetingFetched ? window.greetingText : "..."
                                    font.family: "JetBrains Mono"; font.weight: Font.Medium; font.pixelSize: window.s(14)
                                    color: window.text; Layout.alignment: Qt.AlignHCenter
                                    Layout.fillWidth: true; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                                    opacity: window.greetingFetched ? 1.0 : 0.3
                                    Behavior on opacity { NumberAnimation { duration: 600 } }
                                }
                            }
                        }

                        // Messages
                        ListView {
                            id: chatView
                            Layout.fillWidth: true; Layout.fillHeight: true
                            visible: chatMessages.count > 0
                            model: chatMessages; clip: true; spacing: window.s(8)
                            onCountChanged: positionViewAtEnd()
                            opacity: introChat

                            ScrollBar.vertical: ScrollBar {
                                width: window.s(3); policy: ScrollBar.AsNeeded
                                contentItem: Rectangle { implicitWidth: window.s(3); radius: window.s(1); color: window.surface2 }
                            }

                            delegate: Item {
                                width: ListView.view ? ListView.view.width : 0
                                height: msgOuter.implicitHeight + window.s(8)

                                // User: right-aligned bubble
                                // Assistant: left-aligned, no bubble
                                ColumnLayout {
                                    id: msgOuter
                                    anchors.left: model.role === "assistant" ? parent.left : undefined
                                    anchors.right: model.role === "user" ? parent.right : undefined
                                    anchors.top: parent.top
                                    width: Math.min(parent.width * 0.85, msgContent.implicitWidth + window.s(28))
                                    spacing: window.s(4)

                                    // Role label
                                    Text {
                                        text: model.role === "user" ? "You" : "Hermes"
                                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(10)
                                        color: model.role === "user" ? window.modeColor1 : window.overlay1
                                        Layout.alignment: model.role === "user" ? Qt.AlignRight : Qt.AlignLeft
                                    }

                                    // Message content
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: msgContent.implicitHeight + window.s(16)
                                        radius: window.s(12)
                                        color: model.role === "user"
                                            ? Qt.rgba(window.modeColor1.r, window.modeColor1.g, window.modeColor1.b, 0.12)
                                            : "transparent"
                                        border.color: model.role === "user"
                                            ? Qt.rgba(window.modeColor1.r, window.modeColor1.g, window.modeColor1.b, 0.2)
                                            : "transparent"
                                        border.width: model.role === "user" ? 1 : 0

                                        Text {
                                            id: msgContent
                                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                            anchors.margins: model.role === "user" ? window.s(10) : window.s(4)
                                            anchors.topMargin: model.role === "user" ? window.s(8) : window.s(4)
                                            text: {
                                                if (model.role === "assistant" && index === chatMessages.count - 1)
                                                    return window.displayedResponse;
                                                return model.content;
                                            }
                                            font.family: "JetBrains Mono"; font.pixelSize: window.s(12)
                                            color: window.text
                                            wrapMode: Text.Wrap; textFormat: Text.PlainText
                                            lineHeight: 1.4
                                        }
                                    }
                                }
                            }
                        }

                        // Loading
                        RowLayout {
                            Layout.fillWidth: true; Layout.preferredHeight: window.s(28)
                            visible: window.isLoading; spacing: window.s(8)
                            Layout.leftMargin: window.s(12)

                            Text { text: "󰣇"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(14); color: window.mauve }
                            Text {
                                text: "Thinking"
                                font.family: "JetBrains Mono"; font.pixelSize: window.s(11); color: window.overlay1
                                property int dots: 0
                                Timer { interval: 400; repeat: true; running: window.isLoading; onTriggered: parent.dots = (parent.dots + 1) % 4 }
                                Component.onCompleted: text = Qt.binding(function() { return "Thinking" + ".".repeat(dots); })
                            }
                        }

                        // ── Input box ──
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: window.s(90)
                            radius: window.s(16)
                            color: window.surface0
                            border.color: inputField.activeFocus ? window.modeColor1 : window.surface1
                            border.width: inputField.activeFocus ? 2 : 1
                            Behavior on border.color { ColorAnimation { duration: 200 } }
                            opacity: introInput
                            transform: Translate { y: window.s(15) * (1.0 - introInput) }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: window.s(8)
                                spacing: window.s(4)

                                // Top: text input
                                TextInput {
                                    id: inputField
                                    Layout.fillWidth: true
                                    Layout.minimumHeight: window.s(30)
                                    Layout.maximumHeight: window.s(30)
                                    verticalAlignment: TextInput.AlignVCenter
                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(13); color: window.text
                                    clip: true; selectByMouse: true; leftPadding: window.s(6)
                                    selectionColor: Qt.rgba(window.mauve.r, window.mauve.g, window.mauve.b, 0.3)

                                    Text {
                                        anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                        leftPadding: window.s(6)
                                        visible: !inputField.text && !inputField.activeFocus
                                        text: "Ask anything..."
                                        font: inputField.font; color: window.overlay0
                                    }
                                    Keys.onReturnPressed: { if (text.trim() !== "" && !window.isLoading) { window.sendMessage(text.trim()); text = ""; } }
                                }

                                // Controls: [tools] ............ [send]
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumHeight: window.s(30)
                                    Layout.maximumHeight: window.s(30)
                                    spacing: window.s(6)

                                    // Tools button
                                    Rectangle {
                                        Layout.preferredWidth: window.s(30); Layout.fillHeight: true
                                        radius: window.s(8)
                                        color: toolMa.containsMouse ? window.surface1 : "transparent"
                                        border.color: window.toolsPopupOpen ? window.mauve : "transparent"; border.width: 1
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: "+"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(16)
                                            color: window.toolsPopupOpen ? window.mauve : window.overlay0
                                            rotation: window.toolsPopupOpen ? 45 : 0
                                            Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                        }
                                        MouseArea { id: toolMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.toolsPopupOpen = !window.toolsPopupOpen }
                                    }

                                    // Spacer
                                    Item { Layout.fillWidth: true }

                                    // Send button
                                    Rectangle {
                                        Layout.preferredWidth: window.s(30); Layout.preferredHeight: window.s(30)
                                        radius: window.s(8)
                                        color: sendMa.containsMouse ? window.modeColor1 : window.surface1
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        Text { anchors.centerIn: parent; text: "󰒊"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(15); color: sendMa.containsMouse ? window.crust : window.text }
                                        MouseArea { id: sendMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (inputField.text.trim() !== "" && !window.isLoading) { window.sendMessage(inputField.text.trim()); inputField.text = ""; } } }
                                    }
                                }
                            }
                        }
                    }
                }


                // ══════════════════════════════════════
                // NOTES MODE (Obsidian)
                // ══════════════════════════════════════
                Item {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    visible: window.activeMode === "notes"

                    ColumnLayout {
                        anchors.fill: parent; spacing: window.s(8)
                        opacity: introChat

                        // ══════════════════════════════
                        // NOTES MENU (vault list)
                        // ══════════════════════════════
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            visible: window.notesSubMode === "menu"

                            ColumnLayout {
                                anchors.fill: parent; spacing: window.s(8)

                                // Notes toolbar
                                RowLayout {
                                    Layout.fillWidth: true; spacing: window.s(8)

                                    Item { Layout.fillWidth: true }

                                    // New note button (+)
                                    Rectangle {
                                        Layout.preferredWidth: window.s(30); Layout.preferredHeight: window.s(28)
                                        radius: window.s(8)
                                        color: newNoteMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"
                                        border.color: newNoteMa.containsMouse ? window.green : Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.5); border.width: 1
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        Text {
                                            anchors.centerIn: parent; text: "󰐕"
                                            font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(16); color: window.green
                                        }
                                        MouseArea { id: newNoteMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.createNewNote() }
                                    }


                                }

                                // Loading indicator
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    visible: window.notesLoading
                                    text: "Loading vault..."
                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(12); color: window.overlay0
                                }

                                // Empty state
                                Item {
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    visible: !window.notesLoading && vaultNotes.count === 0

                                    ColumnLayout {
                                        anchors.centerIn: parent; spacing: window.s(12)

                                        Text {
                                            text: "󰠮"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(40)
                                            color: window.overlay0; Layout.alignment: Qt.AlignHCenter
                                        }
                                        Text {
                                            text: "No notes yet"
                                            font.family: "JetBrains Mono"; font.pixelSize: window.s(13)
                                            color: window.overlay0; Layout.alignment: Qt.AlignHCenter
                                        }
                                        Text {
                                            text: "Tap + to create your first note"
                                            font.family: "JetBrains Mono"; font.pixelSize: window.s(10)
                                            color: window.overlay0; Layout.alignment: Qt.AlignHCenter
                                        }
                                    }
                                }

                                // Notes list
                                ListView {
                                    id: vaultListView
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    visible: !window.notesLoading && vaultNotes.count > 0
                                    model: vaultNotes; clip: true; spacing: window.s(4)
                                    boundsBehavior: Flickable.StopAtBounds

                                    ScrollBar.vertical: ScrollBar {
                                        width: window.s(3); policy: ScrollBar.AsNeeded
                                        contentItem: Rectangle { implicitWidth: window.s(3); radius: window.s(1); color: window.surface2 }
                                    }

                                    delegate: Rectangle {
                                        width: ListView.view.width
                                        height: noteItemCol.implicitHeight + window.s(16)
                                        radius: window.s(8)
                                        color: noteItemMa.containsMouse
                                            ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.6)
                                            : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.35)
                                        border.color: noteItemMa.containsMouse ? Qt.rgba(window.peach.r, window.peach.g, window.peach.b, 0.5) : "transparent"
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                        Behavior on border.color { ColorAnimation { duration: 100 } }

                                        ColumnLayout {
                                            id: noteItemCol
                                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                            anchors.margins: window.s(8); spacing: window.s(3)

                                            RowLayout {
                                                Layout.fillWidth: true; spacing: window.s(6)
                                                Text {
                                                    text: "󰈙"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(12)
                                                    color: window.peach
                                                }
                                                Text {
                                                    text: model.name
                                                    font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(11)
                                                    color: noteItemMa.containsMouse ? window.text : window.subtext0
                                                    elide: Text.ElideRight; Layout.fillWidth: true
                                                    Behavior on color { ColorAnimation { duration: 100 } }
                                                }
                                                Text {
                                                    visible: model.folder !== ""
                                                    text: model.folder
                                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(8)
                                                    color: window.overlay0
                                                }
                                            }

                                            Text {
                                                visible: model.preview !== ""
                                                text: model.preview
                                                font.family: "JetBrains Mono"; font.pixelSize: window.s(9)
                                                color: window.overlay0; Layout.fillWidth: true
                                                elide: Text.ElideRight; maximumLineCount: 1
                                            }
                                        }

                                        MouseArea {
                                            id: noteItemMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: window.readNote(model.filepath, model.name)
                                        }
                                    }
                                }

                                // Refresh footer
                                RowLayout {
                                    Layout.fillWidth: true; spacing: window.s(6)
                                    visible: !window.notesLoading && vaultNotes.count > 0

                                    Text {
                                        text: vaultNotes.count + " notes"
                                        font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.overlay0
                                        Layout.fillWidth: true
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: refreshRow.implicitWidth + window.s(14); Layout.preferredHeight: window.s(24)
                                        radius: window.s(6)
                                        color: refreshMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                        Row {
                                            id: refreshRow; anchors.centerIn: parent; spacing: window.s(4)
                                            Text { text: "󰑐"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(12); color: window.sapphire; anchors.verticalCenter: parent.verticalCenter }
                                            Text { text: "Refresh"; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.subtext0; anchors.verticalCenter: parent.verticalCenter }
                                        }
                                        MouseArea { id: refreshMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.fetchVaultNotes() }
                                    }
                                }
                            }
                        }

                        // ══════════════════════════════
                        // NOTE EDITOR
                        // ══════════════════════════════
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            visible: window.notesSubMode === "edit"

                            ColumnLayout {
                                anchors.fill: parent; spacing: window.s(8)

                                // Header: back + title + auto-save indicator + expand AI
                                RowLayout {
                                    Layout.fillWidth: true; spacing: window.s(8)

                                    // Back to menu
                                    Rectangle {
                                        Layout.preferredWidth: window.s(30); Layout.preferredHeight: window.s(28)
                                        radius: window.s(8)
                                        color: backMenuMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"
                                        Behavior on color { ColorAnimation { duration: 80 } }
                                        Text { anchors.centerIn: parent; text: "󰁍"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(16); color: window.peach }
                                        MouseArea {
                                            id: backMenuMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: { window.notesSubMode = "menu"; window.fetchVaultNotes(); }
                                        }
                                    }

                                    Text {
                                        text: window.selectedNoteTitle
                                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(13)
                                        color: window.text; elide: Text.ElideRight; Layout.fillWidth: true
                                    }

                                    // Auto-save indicator
                                    Text {
                                        visible: window.noteAutoSaved
                                        text: "Saved"
                                        font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.green
                                        opacity: window.noteAutoSaved ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 300 } }
                                    }

                                    // Expand with AI
                                    Rectangle {
                                        Layout.preferredWidth: aiExpandRow.implicitWidth + window.s(16)
                                        Layout.preferredHeight: window.s(28)
                                        radius: window.s(8)
                                        color: aiExpandMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"
                                        border.color: aiExpandMa.containsMouse ? window.mauve : Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.5); border.width: 1
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        Row {
                                            id: aiExpandRow; anchors.centerIn: parent; spacing: window.s(6)
                                            Text { text: "󰚩"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(13); color: window.mauve; anchors.verticalCenter: parent.verticalCenter }
                                            Text { text: "Expand with AI"; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: aiExpandMa.containsMouse ? window.text : window.subtext0; anchors.verticalCenter: parent.verticalCenter }
                                        }
                                        MouseArea {
                                            id: aiExpandMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (noteArea.text.trim() === "") return;
                                                window.activeMode = "chat";
                                                window.sendMessage("Expand and improve these notes into a well-structured document. Keep the original ideas but add detail, fix grammar, and organize with headers:\n\n" + noteArea.text);
                                            }
                                        }
                                    }
                                }

                                // Editor area
                                Rectangle {
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    radius: window.s(10); color: Qt.rgba(window.base.r, window.base.g, window.base.b, 0.65)
                                    border.color: noteArea.activeFocus ? window.peach : Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.6)
                                    border.width: noteArea.activeFocus ? 2 : 1
                                    Behavior on border.color { ColorAnimation { duration: 200 } }

                                    TextEdit {
                                        id: noteArea
                                        anchors.fill: parent; anchors.margins: window.s(10)
                                        font.family: "JetBrains Mono"; font.pixelSize: window.s(12)
                                        color: window.text; wrapMode: TextEdit.Wrap
                                        selectByMouse: true
                                        selectionColor: Qt.rgba(window.peach.r, window.peach.g, window.peach.b, 0.3)

                                        Text {
                                            anchors.left: parent.left; anchors.top: parent.top
                                            visible: !noteArea.text && !noteArea.activeFocus
                                            text: "Start typing..."
                                            font: noteArea.font; color: window.overlay0
                                        }

                                        onTextChanged: {
                                            if (window.notesSubMode === "edit" && window.currentNoteFilepath !== "")
                                                autoSaveTimer.restart();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ══════════════════════════════════════
                // LEARN MODE
                // ══════════════════════════════════════
                Item {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    visible: window.activeMode === "learn"

                    ColumnLayout {
                        anchors.fill: parent; spacing: window.s(8)
                        opacity: introChat

                        // ══════════════════════════════
                        // HOME (no book / book overview)
                        // ══════════════════════════════
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            visible: window.learnSubMode === "home"

                            ColumnLayout {
                                anchors.fill: parent; spacing: window.s(10)

                                // Toolbar
                                RowLayout {
                                    Layout.fillWidth: true; spacing: window.s(8)
                                    Item { Layout.fillWidth: true }

                                    // Vocab button
                                    Rectangle {
                                        visible: learnedTerms.count > 0
                                        Layout.preferredWidth: vocabBtnRow.implicitWidth + window.s(16); Layout.preferredHeight: window.s(28)
                                        radius: window.s(8)
                                        color: vocabBtnMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"
                                        border.color: vocabBtnMa.containsMouse ? window.yellow : Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.5); border.width: 1
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        Row {
                                            id: vocabBtnRow; anchors.centerIn: parent; spacing: window.s(5)
                                            Text { text: "󰗊"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(13); color: window.yellow; anchors.verticalCenter: parent.verticalCenter }
                                            Text { text: learnedTerms.count + " words"; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: vocabBtnMa.containsMouse ? window.text : window.subtext0; anchors.verticalCenter: parent.verticalCenter }
                                        }
                                        MouseArea { id: vocabBtnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.learnSubMode = "vocab" }
                                    }
                                }

                                // ── No book loaded (Kavita browser) ──
                                Item {
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    visible: !window.bookLoaded

                                    ColumnLayout {
                                        anchors.fill: parent; spacing: window.s(10)

                                        // Not connected state
                                        Item {
                                            Layout.fillWidth: true; Layout.fillHeight: true
                                            visible: !window.kavitaConnected && !window.kavitaLoading

                                            ColumnLayout {
                                                anchors.centerIn: parent; spacing: window.s(16); width: parent.width * 0.85

                                                Text {
                                                    text: "󰂺"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(48)
                                                    color: window.green; Layout.alignment: Qt.AlignHCenter; opacity: 0.6
                                                }
                                                Text {
                                                    text: "Connect to Kavita"
                                                    font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(14)
                                                    color: window.text; Layout.alignment: Qt.AlignHCenter
                                                }
                                                Text {
                                                    text: "Add your Kavita API key to ai_config.json to browse textbooks from your library."
                                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(10)
                                                    color: window.subtext0; Layout.fillWidth: true; wrapMode: Text.Wrap
                                                    horizontalAlignment: Text.AlignHCenter
                                                }

                                                // Config hint
                                                Rectangle {
                                                    Layout.fillWidth: true; Layout.preferredHeight: kavitaHintCol.implicitHeight + window.s(20)
                                                    radius: window.s(10)
                                                    color: Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.45)
                                                    border.color: Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.5); border.width: 1

                                                    ColumnLayout {
                                                        id: kavitaHintCol
                                                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                                        anchors.margins: window.s(10); spacing: window.s(6)

                                                        Text {
                                                            text: "~/.config/hypr/ai_config.json"
                                                            font.family: "JetBrains Mono"; font.pixelSize: window.s(9); font.weight: Font.Bold
                                                            color: window.overlay1
                                                        }
                                                        Text {
                                                            text: '  "kavita_url": "http://localhost:5000"\n  "kavita_api_key": "your-api-key"'
                                                            font.family: "JetBrains Mono"; font.pixelSize: window.s(9)
                                                            color: window.green; Layout.fillWidth: true; wrapMode: Text.Wrap
                                                        }
                                                    }
                                                }

                                                // Retry button
                                                Rectangle {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    Layout.preferredWidth: retryRow.implicitWidth + window.s(20); Layout.preferredHeight: window.s(32)
                                                    radius: window.s(8)
                                                    color: retryMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.5)
                                                    border.color: retryMa.containsMouse ? window.green : Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.5); border.width: 1
                                                    Behavior on color { ColorAnimation { duration: 120 } }
                                                    Row {
                                                        id: retryRow; anchors.centerIn: parent; spacing: window.s(6)
                                                        Text { text: "󰑐"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(13); color: window.green; anchors.verticalCenter: parent.verticalCenter }
                                                        Text { text: "Reconnect"; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: retryMa.containsMouse ? window.text : window.subtext0; anchors.verticalCenter: parent.verticalCenter }
                                                    }
                                                    MouseArea {
                                                        id: retryMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            // Re-read config and try auth
                                                            configReader.running = false;
                                                            configReader.running = true;
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Connected: Kavita library browser
                                        Item {
                                            Layout.fillWidth: true; Layout.fillHeight: true
                                            visible: window.kavitaConnected

                                            ColumnLayout {
                                                anchors.fill: parent; spacing: window.s(8)

                                                // Library header
                                                RowLayout {
                                                    Layout.fillWidth: true; spacing: window.s(8)
                                                    Text { text: "󰂺"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(16); color: window.green }
                                                    Text { text: "Textbooks"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(13); color: window.text }

                                                    // Connected indicator
                                                    Rectangle {
                                                        Layout.preferredWidth: window.s(8); Layout.preferredHeight: window.s(8)
                                                        radius: window.s(4); color: window.green
                                                    }

                                                    Item { Layout.fillWidth: true }

                                                    // Refresh
                                                    Rectangle {
                                                        Layout.preferredWidth: window.s(28); Layout.preferredHeight: window.s(28)
                                                        radius: window.s(8)
                                                        color: kavRefreshMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"
                                                        Behavior on color { ColorAnimation { duration: 80 } }
                                                        Text { anchors.centerIn: parent; text: "󰑐"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(14); color: window.sapphire }
                                                        MouseArea { id: kavRefreshMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.kavitaFetchSeries() }
                                                    }
                                                }

                                                // Loading
                                                Text {
                                                    visible: window.kavitaLoading || window.learnLoading
                                                    text: window.learnLoading ? "Downloading & processing..." : "Loading library..."
                                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(11); color: window.overlay0
                                                    Layout.alignment: Qt.AlignHCenter
                                                }

                                                // Empty state
                                                Text {
                                                    visible: !window.kavitaLoading && !window.learnLoading && kavitaSeries.count === 0
                                                    text: "No books found in your Textbooks library."
                                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(11); color: window.overlay0
                                                    Layout.alignment: Qt.AlignHCenter; Layout.topMargin: window.s(20)
                                                }

                                                // Series list
                                                ListView {
                                                    Layout.fillWidth: true; Layout.fillHeight: true
                                                    visible: !window.kavitaLoading && !window.learnLoading && kavitaSeries.count > 0
                                                    model: kavitaSeries; clip: true; spacing: window.s(4)
                                                    boundsBehavior: Flickable.StopAtBounds

                                                    ScrollBar.vertical: ScrollBar {
                                                        width: window.s(3); policy: ScrollBar.AsNeeded
                                                        contentItem: Rectangle { implicitWidth: window.s(3); radius: window.s(1); color: window.surface2 }
                                                    }

                                                    delegate: Rectangle {
                                                        width: ListView.view.width
                                                        height: kavSeriesCol.implicitHeight + window.s(16)
                                                        radius: window.s(8)
                                                        color: kavSeriesMa.containsMouse
                                                            ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.6)
                                                            : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.35)
                                                        border.color: kavSeriesMa.containsMouse ? Qt.rgba(window.green.r, window.green.g, window.green.b, 0.5) : "transparent"
                                                        border.width: 1
                                                        Behavior on color { ColorAnimation { duration: 100 } }
                                                        Behavior on border.color { ColorAnimation { duration: 100 } }

                                                        ColumnLayout {
                                                            id: kavSeriesCol
                                                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                                            anchors.margins: window.s(10); spacing: window.s(3)

                                                            RowLayout {
                                                                Layout.fillWidth: true; spacing: window.s(8)
                                                                Text {
                                                                    text: "󰂺"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(14)
                                                                    color: window.green
                                                                }
                                                                Text {
                                                                    text: model.name
                                                                    font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(11)
                                                                    color: kavSeriesMa.containsMouse ? window.text : window.subtext0
                                                                    elide: Text.ElideRight; Layout.fillWidth: true
                                                                    Behavior on color { ColorAnimation { duration: 100 } }
                                                                }
                                                            }

                                                            RowLayout {
                                                                Layout.fillWidth: true; spacing: window.s(8)
                                                                Text {
                                                                    visible: model.libraryName !== ""
                                                                    text: model.libraryName
                                                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(8)
                                                                    color: window.overlay0
                                                                }
                                                                Text {
                                                                    visible: model.pages > 0
                                                                    text: model.pages + " pages"
                                                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(8)
                                                                    color: window.overlay0
                                                                }
                                                            }
                                                        }

                                                        MouseArea {
                                                            id: kavSeriesMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                            onClicked: window.kavitaDownloadBook(model.seriesId, model.name)
                                                        }
                                                    }
                                                }

                                                // Footer: book count
                                                Text {
                                                    visible: kavitaSeries.count > 0
                                                    text: kavitaSeries.count + " books"
                                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.overlay0
                                                }
                                            }
                                        }
                                    }
                                }

                                // ── Book loaded overview ──
                                Item {
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    visible: window.bookLoaded

                                    ColumnLayout {
                                        anchors.fill: parent; spacing: window.s(10)

                                        // Book title card
                                        Rectangle {
                                            Layout.fillWidth: true; Layout.preferredHeight: window.s(70)
                                            radius: window.s(12)
                                            color: Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.45)
                                            border.color: Qt.rgba(window.green.r, window.green.g, window.green.b, 0.3); border.width: 1

                                            RowLayout {
                                                anchors.fill: parent; anchors.margins: window.s(12); spacing: window.s(12)

                                                // Book icon
                                                Rectangle {
                                                    Layout.preferredWidth: window.s(46); Layout.preferredHeight: window.s(46)
                                                    radius: window.s(10)
                                                    gradient: Gradient {
                                                        GradientStop { position: 0.0; color: window.green }
                                                        GradientStop { position: 1.0; color: window.teal }
                                                    }
                                                    Text { anchors.centerIn: parent; text: "󰂺"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(22); color: window.crust }
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true; spacing: window.s(4)
                                                    Text {
                                                        text: window.bookTitle
                                                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(13)
                                                        color: window.text; elide: Text.ElideRight; Layout.fillWidth: true
                                                    }
                                                    Text {
                                                        text: "Chapter " + (window.currentChapter + 1) + " of " + window.totalChapters
                                                        font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.subtext0
                                                    }
                                                    // Progress bar
                                                    Rectangle {
                                                        Layout.fillWidth: true; Layout.preferredHeight: window.s(4)
                                                        radius: window.s(2); color: Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.5)
                                                        Rectangle {
                                                            width: parent.width * ((window.currentChapter + 1) / Math.max(window.totalChapters, 1))
                                                            height: parent.height; radius: parent.radius
                                                            gradient: Gradient {
                                                                orientation: Gradient.Horizontal
                                                                GradientStop { position: 0.0; color: window.green }
                                                                GradientStop { position: 1.0; color: window.teal }
                                                            }
                                                            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutQuart } }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Continue lesson button
                                        Rectangle {
                                            Layout.fillWidth: true; Layout.preferredHeight: window.s(44)
                                            radius: window.s(10)
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                GradientStop { position: 0.0; color: continueMa.containsMouse ? Qt.lighter(window.green, 1.1) : window.green }
                                                GradientStop { position: 1.0; color: continueMa.containsMouse ? Qt.lighter(window.teal, 1.1) : window.teal }
                                            }
                                            Behavior on opacity { NumberAnimation { duration: 100 } }

                                            Row {
                                                anchors.centerIn: parent; spacing: window.s(8)
                                                Text { text: "󰐊"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(18); color: window.crust; anchors.verticalCenter: parent.verticalCenter }
                                                Text { text: "Continue Lesson"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(13); color: window.crust; anchors.verticalCenter: parent.verticalCenter }
                                            }
                                            MouseArea { id: continueMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.startLesson() }
                                        }

                                        // Chapter list
                                        ListView {
                                            Layout.fillWidth: true; Layout.fillHeight: true
                                            model: bookChapters; clip: true; spacing: window.s(3)
                                            boundsBehavior: Flickable.StopAtBounds

                                            ScrollBar.vertical: ScrollBar {
                                                width: window.s(3); policy: ScrollBar.AsNeeded
                                                contentItem: Rectangle { implicitWidth: window.s(3); radius: window.s(1); color: window.surface2 }
                                            }

                                            delegate: Rectangle {
                                                width: ListView.view.width; height: window.s(36)
                                                radius: window.s(8)
                                                color: chItemMa.containsMouse
                                                    ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.6)
                                                    : (model.chIndex === window.currentChapter
                                                        ? Qt.rgba(window.green.r, window.green.g, window.green.b, 0.12)
                                                        : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.25))
                                                border.color: model.chIndex === window.currentChapter ? Qt.rgba(window.green.r, window.green.g, window.green.b, 0.4) : "transparent"
                                                border.width: 1
                                                Behavior on color { ColorAnimation { duration: 100 } }

                                                RowLayout {
                                                    anchors.fill: parent; anchors.margins: window.s(8); spacing: window.s(8)
                                                    Text {
                                                        text: model.chIndex <= window.currentChapter ? "󰄬" : "󰝦"
                                                        font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(12)
                                                        color: model.chIndex < window.currentChapter ? window.green
                                                             : model.chIndex === window.currentChapter ? window.teal : window.overlay0
                                                    }
                                                    Text {
                                                        text: model.title
                                                        font.family: "JetBrains Mono"; font.pixelSize: window.s(10)
                                                        font.weight: model.chIndex === window.currentChapter ? Font.Bold : Font.Medium
                                                        color: model.chIndex <= window.currentChapter ? window.text : window.subtext0
                                                        elide: Text.ElideRight; Layout.fillWidth: true
                                                    }
                                                }
                                                MouseArea {
                                                    id: chItemMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: { window.currentChapter = model.chIndex; window.saveLearnState(); window.startLesson(); }
                                                }
                                            }
                                        }

                                        // Load different book
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: learnedTerms.count + " terms learned"
                                                font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.overlay0
                                                Layout.fillWidth: true
                                            }
                                            Rectangle {
                                                Layout.preferredWidth: newBookRow.implicitWidth + window.s(14); Layout.preferredHeight: window.s(24)
                                                radius: window.s(6)
                                                color: newBookMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                                Row {
                                                    id: newBookRow; anchors.centerIn: parent; spacing: window.s(4)
                                                    Text { text: "󰐕"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(11); color: window.sapphire; anchors.verticalCenter: parent.verticalCenter }
                                                    Text { text: "New book"; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.subtext0; anchors.verticalCenter: parent.verticalCenter }
                                                }
                                                MouseArea { id: newBookMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (learnedTerms.count > 0) window.exportVocabToObsidian(); window.bookLoaded = false; } }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ══════════════════════════════
                        // LESSON (AI tutor conversation)
                        // ══════════════════════════════
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            visible: window.learnSubMode === "lesson"

                            ColumnLayout {
                                anchors.fill: parent; spacing: window.s(8)

                                // Lesson header
                                RowLayout {
                                    Layout.fillWidth: true; spacing: window.s(8)

                                    // Back to home
                                    Rectangle {
                                        Layout.preferredWidth: window.s(30); Layout.preferredHeight: window.s(28)
                                        radius: window.s(8)
                                        color: learnBackMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"
                                        Behavior on color { ColorAnimation { duration: 80 } }
                                        Text { anchors.centerIn: parent; text: "󰁍"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(16); color: window.green }
                                        MouseArea { id: learnBackMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.learnSubMode = "home" }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: window.s(2)
                                        Text {
                                            text: window.currentChapterTitle
                                            font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(12)
                                            color: window.text; elide: Text.ElideRight; Layout.fillWidth: true
                                        }
                                        Text {
                                            text: "Ch " + (window.currentChapter + 1) + "/" + window.totalChapters
                                            font.family: "JetBrains Mono"; font.pixelSize: window.s(8); color: window.overlay0
                                        }
                                    }

                                    // Vocab count
                                    Rectangle {
                                        visible: learnedTerms.count > 0
                                        Layout.preferredWidth: lessonVocRow.implicitWidth + window.s(12); Layout.preferredHeight: window.s(24)
                                        radius: window.s(6)
                                        color: lessonVocMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                        Row {
                                            id: lessonVocRow; anchors.centerIn: parent; spacing: window.s(4)
                                            Text { text: "󰗊"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(11); color: window.yellow; anchors.verticalCenter: parent.verticalCenter }
                                            Text { text: learnedTerms.count.toString(); font.family: "JetBrains Mono"; font.pixelSize: window.s(9); font.weight: Font.Bold; color: window.yellow; anchors.verticalCenter: parent.verticalCenter }
                                        }
                                        MouseArea { id: lessonVocMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.learnSubMode = "vocab" }
                                    }

                                    // Next chapter
                                    Rectangle {
                                        visible: window.currentChapter < window.totalChapters - 1
                                        Layout.preferredWidth: window.s(30); Layout.preferredHeight: window.s(28)
                                        radius: window.s(8)
                                        color: nextChMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"
                                        border.color: nextChMa.containsMouse ? window.teal : Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.5); border.width: 1
                                        Behavior on color { ColorAnimation { duration: 80 } }
                                        Text { anchors.centerIn: parent; text: "󰒭"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(16); color: window.teal }
                                        MouseArea { id: nextChMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.advanceChapter() }
                                    }
                                }

                                // Chat messages
                                ListView {
                                    id: lessonView
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    model: lessonChat; clip: true; spacing: window.s(8)
                                    onCountChanged: positionViewAtEnd()

                                    ScrollBar.vertical: ScrollBar {
                                        width: window.s(3); policy: ScrollBar.AsNeeded
                                        contentItem: Rectangle { implicitWidth: window.s(3); radius: window.s(1); color: window.surface2 }
                                    }

                                    delegate: Rectangle {
                                        width: ListView.view.width
                                        height: lessonMsgCol.implicitHeight + window.s(20)
                                        color: model.role === "assistant" ? Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.3) : "transparent"
                                        radius: window.s(8)

                                        ColumnLayout {
                                            id: lessonMsgCol
                                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                            anchors.margins: window.s(10); spacing: window.s(4)

                                            RowLayout {
                                                spacing: window.s(6)
                                                Text {
                                                    text: model.role === "user" ? "󰀄" : "󰗊"
                                                    font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(13)
                                                    color: model.role === "user" ? window.blue : window.green
                                                }
                                                Text {
                                                    text: model.role === "user" ? "You" : "Tutor"
                                                    font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(10)
                                                    color: model.role === "user" ? window.blue : window.green
                                                }
                                            }

                                            Text {
                                                text: {
                                                    if (model.role === "assistant" && index === lessonChat.count - 1)
                                                        return window.learnDisplayedResponse;
                                                    return model.content;
                                                }
                                                font.family: "JetBrains Mono"; font.pixelSize: window.s(11)
                                                color: window.text; Layout.fillWidth: true
                                                wrapMode: Text.Wrap; textFormat: Text.PlainText; lineHeight: 1.4
                                            }
                                        }
                                    }
                                }

                                // Loading indicator
                                RowLayout {
                                    Layout.fillWidth: true; Layout.preferredHeight: window.s(24)
                                    visible: window.learnLoading; spacing: window.s(8); Layout.leftMargin: window.s(10)

                                    Text { text: "󰗊"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(14); color: window.green }
                                    Text {
                                        text: "Teaching"
                                        font.family: "JetBrains Mono"; font.pixelSize: window.s(11); color: window.overlay1
                                        property int dots: 0
                                        Timer { interval: 400; repeat: true; running: window.learnLoading; onTriggered: parent.dots = (parent.dots + 1) % 4 }
                                        Component.onCompleted: text = Qt.binding(function() { return "Teaching" + ".".repeat(dots); })
                                    }
                                }

                                // Voice transcript display
                                Text {
                                    visible: window.voiceTranscript !== "" && window.voiceTranscript.startsWith("[")
                                    text: window.voiceTranscript
                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.peach
                                    Layout.fillWidth: true; wrapMode: Text.Wrap
                                }

                                // Input row: [mic] [text input] [send]
                                Rectangle {
                                    Layout.fillWidth: true; Layout.preferredHeight: window.s(44)
                                    radius: window.s(12)
                                    color: Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.6)
                                    border.color: learnInput.activeFocus ? window.green : Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.6)
                                    border.width: learnInput.activeFocus ? 2 : 1
                                    Behavior on border.color { ColorAnimation { duration: 200 } }

                                    RowLayout {
                                        anchors.fill: parent; anchors.margins: window.s(6); spacing: window.s(6)

                                        // Mic button
                                        Rectangle {
                                            Layout.preferredWidth: window.s(32); Layout.preferredHeight: window.s(32)
                                            radius: window.s(10)
                                            color: window.isRecording
                                                ? window.red
                                                : (micMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent")
                                            Behavior on color { ColorAnimation { duration: 120 } }

                                            // Recording pulse
                                            Rectangle {
                                                anchors.fill: parent; radius: parent.radius
                                                color: window.red; visible: window.isRecording
                                                opacity: micPulse.running ? 0.3 : 0
                                                Behavior on opacity { NumberAnimation { duration: 600 } }
                                                SequentialAnimation on opacity {
                                                    id: micPulse; running: window.isRecording; loops: Animation.Infinite
                                                    NumberAnimation { to: 0.5; duration: 600 }
                                                    NumberAnimation { to: 0.1; duration: 600 }
                                                }
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                text: window.isRecording ? "󰍬" : "󰍮"
                                                font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(16)
                                                color: window.isRecording ? window.crust : (micMa.containsMouse ? window.green : window.overlay1)
                                                Behavior on color { ColorAnimation { duration: 120 } }
                                            }

                                            MouseArea {
                                                id: micMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (window.isRecording) window.stopRecording();
                                                    else window.startRecording();
                                                }
                                            }
                                        }

                                        // Text input
                                        TextInput {
                                            id: learnInput
                                            Layout.fillWidth: true; Layout.fillHeight: true
                                            verticalAlignment: TextInput.AlignVCenter
                                            font.family: "JetBrains Mono"; font.pixelSize: window.s(12); color: window.text
                                            clip: true; selectByMouse: true; leftPadding: window.s(4)
                                            selectionColor: Qt.rgba(window.green.r, window.green.g, window.green.b, 0.3)

                                            Text {
                                                anchors.fill: parent; verticalAlignment: Text.AlignVCenter; leftPadding: window.s(4)
                                                visible: !learnInput.text && !learnInput.activeFocus
                                                text: "Type or speak..."
                                                font: learnInput.font; color: window.overlay0
                                            }

                                            Keys.onReturnPressed: {
                                                if (text.trim() !== "" && !window.learnLoading) {
                                                    window.sendLearnMessage(text.trim());
                                                    text = "";
                                                }
                                            }
                                        }

                                        // Send button
                                        Rectangle {
                                            Layout.preferredWidth: window.s(32); Layout.preferredHeight: window.s(32)
                                            radius: window.s(10)
                                            color: learnSendMa.containsMouse ? window.green : Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8)
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                            Text { anchors.centerIn: parent; text: "󰒊"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(15); color: learnSendMa.containsMouse ? window.crust : window.text }
                                            MouseArea {
                                                id: learnSendMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (learnInput.text.trim() !== "" && !window.learnLoading) {
                                                        window.sendLearnMessage(learnInput.text.trim());
                                                        learnInput.text = "";
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ══════════════════════════════
                        // VOCAB REVIEW
                        // ══════════════════════════════
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            visible: window.learnSubMode === "vocab"

                            ColumnLayout {
                                anchors.fill: parent; spacing: window.s(8)

                                // Vocab header
                                RowLayout {
                                    Layout.fillWidth: true; spacing: window.s(8)

                                    Rectangle {
                                        Layout.preferredWidth: window.s(30); Layout.preferredHeight: window.s(28)
                                        radius: window.s(8)
                                        color: vocBackMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.8) : "transparent"
                                        Behavior on color { ColorAnimation { duration: 80 } }
                                        Text { anchors.centerIn: parent; text: "󰁍"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(16); color: window.green }
                                        MouseArea { id: vocBackMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.learnSubMode = "home" }
                                    }

                                    Text { text: "󰗊"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(18); color: window.yellow }
                                    Text { text: "Vocabulary"; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(14); color: window.text }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: learnedTerms.count + " terms"
                                        font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.overlay0
                                    }
                                }

                                // Empty state
                                Text {
                                    visible: learnedTerms.count === 0
                                    text: "No vocabulary learned yet. Start a lesson to build your word list!"
                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(11); color: window.overlay0
                                    Layout.fillWidth: true; wrapMode: Text.Wrap
                                    Layout.alignment: Qt.AlignHCenter; horizontalAlignment: Text.AlignHCenter
                                    Layout.topMargin: window.s(40)
                                }

                                // Vocab list
                                ListView {
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    visible: learnedTerms.count > 0
                                    model: learnedTerms; clip: true; spacing: window.s(4)
                                    boundsBehavior: Flickable.StopAtBounds

                                    ScrollBar.vertical: ScrollBar {
                                        width: window.s(3); policy: ScrollBar.AsNeeded
                                        contentItem: Rectangle { implicitWidth: window.s(3); radius: window.s(1); color: window.surface2 }
                                    }

                                    delegate: Rectangle {
                                        width: ListView.view.width; height: window.s(52)
                                        radius: window.s(8)
                                        color: Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.35)

                                        RowLayout {
                                            anchors.fill: parent; anchors.margins: window.s(10); spacing: window.s(10)

                                            // Mastery indicator
                                            Rectangle {
                                                Layout.preferredWidth: window.s(6); Layout.preferredHeight: window.s(30)
                                                radius: window.s(3)
                                                color: model.mastery >= 4 ? window.green
                                                     : model.mastery >= 2 ? window.yellow : window.peach
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: window.s(2)
                                                RowLayout {
                                                    spacing: window.s(8)
                                                    Text {
                                                        text: model.term
                                                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(13)
                                                        color: window.text
                                                    }
                                                    Text {
                                                        visible: model.reading !== "" && model.reading !== model.term
                                                        text: model.reading
                                                        font.family: "JetBrains Mono"; font.pixelSize: window.s(10)
                                                        color: window.subtext0
                                                    }
                                                }
                                                Text {
                                                    text: model.meaning
                                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(10)
                                                    color: window.overlay1; elide: Text.ElideRight; Layout.fillWidth: true
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ══════════════════════════════════════
                // CHESS MODE (Lichess)
                // ══════════════════════════════════════
                Item {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    visible: window.activeMode === "chess"

                    ColumnLayout {
                        anchors.fill: parent; spacing: window.s(6)
                        opacity: introChat

                        // ── MENU STATE ──
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            visible: window.chessStatus === "menu"

                            ColumnLayout {
                                anchors.centerIn: parent; spacing: window.s(14); width: parent.width * 0.85

                                // No token warning
                                Text {
                                    visible: window.lichessToken === ""
                                    text: "Add lichess_token to ai_config.json\nGet one at lichess.org/account/oauth/token"
                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.subtext0
                                    Layout.fillWidth: true; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                                }

                                // vs AI
                                Text { visible: window.lichessToken !== ""; text: "vs Computer"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(12); color: window.overlay1 }
                                GridLayout {
                                    visible: window.lichessToken !== ""
                                    Layout.fillWidth: true; columns: 3; rowSpacing: window.s(6); columnSpacing: window.s(6)
                                    Repeater {
                                        model: ListModel {
                                            ListElement { label: "Easy"; lvl: 2; mins: 10 }
                                            ListElement { label: "Medium"; lvl: 4; mins: 10 }
                                            ListElement { label: "Hard"; lvl: 8; mins: 10 }
                                        }
                                        delegate: Rectangle {
                                            Layout.fillWidth: true; Layout.preferredHeight: window.s(40)
                                            radius: window.s(8); color: aiMa.containsMouse ? window.surface1 : window.surface0
                                            border.color: aiMa.containsMouse ? window.yellow : window.surface1; border.width: 1
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                            Text { anchors.centerIn: parent; text: label; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(11); color: aiMa.containsMouse ? window.text : window.subtext0 }
                                            MouseArea { id: aiMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.chessStartAi(lvl, mins) }
                                        }
                                    }
                                }

                                // vs Human
                                Text { visible: window.lichessToken !== ""; text: "vs Human"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(12); color: window.overlay1 }
                                GridLayout {
                                    visible: window.lichessToken !== ""
                                    Layout.fillWidth: true; columns: 3; rowSpacing: window.s(6); columnSpacing: window.s(6)
                                    Repeater {
                                        model: ListModel {
                                            ListElement { label: "Bullet 1+0"; mins: 1 }
                                            ListElement { label: "Blitz 3+2"; mins: 3 }
                                            ListElement { label: "Rapid 10+0"; mins: 10 }
                                        }
                                        delegate: Rectangle {
                                            Layout.fillWidth: true; Layout.preferredHeight: window.s(40)
                                            radius: window.s(8); color: hvMa.containsMouse ? window.surface1 : window.surface0
                                            border.color: hvMa.containsMouse ? window.yellow : window.surface1; border.width: 1
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                            Text { anchors.centerIn: parent; text: label; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(11); color: hvMa.containsMouse ? window.text : window.subtext0 }
                                            MouseArea { id: hvMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.chessSeekGame(mins) }
                                        }
                                    }
                                }

                                // Open in browser fallback

                            }
                        }

                        // ── SEEKING STATE ──
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            visible: window.chessStatus === "seeking"
                            ColumnLayout {
                                anchors.centerIn: parent; spacing: window.s(12)
                                Text { text: "\u265e"; font.pixelSize: window.s(40); color: window.yellow; Layout.alignment: Qt.AlignHCenter
                                    SequentialAnimation on opacity { loops: Animation.Infinite; running: window.chessStatus === "seeking"
                                        NumberAnimation { to: 0.3; duration: 600 }
                                        NumberAnimation { to: 1.0; duration: 600 }
                                    }
                                }
                                Text { text: "Finding opponent..."; font.family: "JetBrains Mono"; font.pixelSize: window.s(14); color: window.subtext0; Layout.alignment: Qt.AlignHCenter }
                            }
                        }

                        // ── PLAYING STATE ──
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            visible: window.chessStatus === "playing" || window.chessStatus === "ended"

                            ColumnLayout {
                                anchors.fill: parent; spacing: window.s(4)

                                // Opponent label
                                RowLayout {
                                    Layout.fillWidth: true; spacing: window.s(6)
                                    Text { text: window.chessOpponent; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(11); color: window.text }
                                    Item { Layout.fillWidth: true }
                                    Text { visible: window.chessMyTurn; text: "Your turn"; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.green }
                                    Text { visible: !window.chessMyTurn && window.chessStatus === "playing"; text: "Waiting..."; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.overlay0 }
                                }

                                // Chess board
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: width
                                    Layout.maximumHeight: parent.height - window.s(60)
                                    radius: window.s(8); color: window.crust; clip: true
                                    border.color: window.surface1; border.width: 1

                                    Grid {
                                        anchors.fill: parent; anchors.margins: window.s(3)
                                        columns: 8; rows: 8

                                        Repeater {
                                            model: 64
                                            delegate: Rectangle {
                                                width: parent.width / 8; height: parent.height / 8
                                                property int row: Math.floor(index / 8)
                                                property int col: index % 8
                                                property bool isLight: (row + col) % 2 === 0
                                                property int realIdx: window.chessIsWhite ? index : (63 - index)
                                                property string piece: window.chessBoard[realIdx] || ""
                                                property bool isSelected: window.chessSelected === realIdx
                                                property bool isLastFrom: window.chessFromIdx === realIdx
                                                property bool isLastTo: window.chessToIdx === realIdx

                                                color: isSelected ? Qt.rgba(window.yellow.r, window.yellow.g, window.yellow.b, 0.5)
                                                     : (isLastFrom || isLastTo) ? Qt.rgba(window.blue.r, window.blue.g, window.blue.b, 0.25)
                                                     : isLight ? Qt.rgba(window.text.r, window.text.g, window.text.b, 0.15)
                                                     : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.6)

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: window.chessPieceChar(piece)
                                                    font.pixelSize: parent.width * 0.7
                                                    color: piece >= "A" && piece <= "Z" ? "#ffffff" : "#1a1a2e"
                                                    style: Text.Outline; styleColor: piece >= "A" && piece <= "Z" ? "#333333" : "#aaaaaa"
                                                }

                                                MouseArea {
                                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                    enabled: window.chessStatus === "playing"
                                                    onClicked: window.chessSquareClicked(index)
                                                }
                                            }
                                        }
                                    }
                                }

                                // You label + controls
                                RowLayout {
                                    Layout.fillWidth: true; spacing: window.s(6)
                                    Text { text: "You (" + (window.chessIsWhite ? "White" : "Black") + ")"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(11); color: window.text }
                                    Item { Layout.fillWidth: true }

                                    // Game over result
                                    Text {
                                        visible: window.chessStatus === "ended"
                                        text: window.chessResult
                                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(12)
                                        color: window.chessResult === "mate" || window.chessResult === "resign" ? window.red : window.yellow
                                    }

                                    // Resign button
                                    Rectangle {
                                        visible: window.chessStatus === "playing"
                                        Layout.preferredWidth: resignRow.implicitWidth + window.s(14); Layout.preferredHeight: window.s(26)
                                        radius: window.s(6); color: resignMa.containsMouse ? window.surface1 : "transparent"
                                        border.color: resignMa.containsMouse ? window.red : "transparent"; border.width: 1
                                        Row {
                                            id: resignRow; anchors.centerIn: parent; spacing: window.s(4)
                                            Text { text: "Resign"; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: resignMa.containsMouse ? window.red : window.overlay0; anchors.verticalCenter: parent.verticalCenter }
                                        }
                                        MouseArea { id: resignMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.chessResign() }
                                    }

                                    // New game button (after game ends)
                                    Rectangle {
                                        visible: window.chessStatus === "ended"
                                        Layout.preferredWidth: newGameRow.implicitWidth + window.s(14); Layout.preferredHeight: window.s(26)
                                        radius: window.s(6); color: newGameMa.containsMouse ? window.surface1 : window.surface0
                                        border.color: newGameMa.containsMouse ? window.green : window.surface1; border.width: 1
                                        Row {
                                            id: newGameRow; anchors.centerIn: parent; spacing: window.s(4)
                                            Text { text: "New Game"; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: newGameMa.containsMouse ? window.green : window.subtext0; anchors.verticalCenter: parent.verticalCenter }
                                        }
                                        MouseArea {
                                            id: newGameMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                window.chessStatus = "menu";
                                                window.chessGameId = "";
                                                window.chessSelected = -1;
                                                window.chessFromIdx = -1;
                                                window.chessToIdx = -1;
                                                window.chessInitBoard();
                                                chessStreamProc.running = false;
                                                chessEventWatcher.running = false;
                                                Quickshell.execDetached(["bash", "-c", "pkill -f chess_stream.sh 2>/dev/null"]);
                                                window.saveChessState();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }


                // ══════════════════════════════════════
                // KAVITA MODE
                // ══════════════════════════════════════
                Item {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    visible: window.activeMode === "kavita"
                    ColumnLayout {
                        anchors.fill: parent; spacing: window.s(8); opacity: introChat

                        RowLayout {
                            Layout.fillWidth: true; spacing: window.s(8)
                            Rectangle { visible: window.kavitaConnected; Layout.preferredWidth: window.s(8); Layout.preferredHeight: window.s(8); radius: window.s(4); color: window.green }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                visible: window.kavitaConnected; Layout.preferredWidth: window.s(130); Layout.preferredHeight: window.s(28)
                                radius: window.s(8); color: window.surface0; border.color: window.surface1; border.width: 1
                                Rectangle {
                                    width: parent.width / 2 - window.s(1); height: parent.height - window.s(2); y: window.s(1); radius: window.s(6)
                                    x: window.kavitaSubMode === "ondeck" ? window.s(1) : parent.width / 2
                                    Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: window.pink }
                                        GradientStop { position: 1.0; color: window.mauve }
                                    }
                                }
                                RowLayout {
                                    anchors.fill: parent; spacing: 0
                                    Item {
                                        Layout.fillWidth: true; Layout.fillHeight: true
                                        Text { anchors.centerIn: parent; text: "On Deck"; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); font.weight: Font.Bold; color: window.kavitaSubMode === "ondeck" ? window.crust : window.subtext0 }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { window.kavitaSubMode = "ondeck"; window.kavitaFetchOnDeck(); } }
                                    }
                                    Item {
                                        Layout.fillWidth: true; Layout.fillHeight: true
                                        Text { anchors.centerIn: parent; text: "Library"; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); font.weight: Font.Bold; color: window.kavitaSubMode === "library" ? window.crust : window.subtext0 }
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: window.kavitaSubMode = "library" }
                                    }
                                }
                            }
                        }

                        // Not connected
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true; visible: !window.kavitaConnected
                            ColumnLayout {
                                anchors.centerIn: parent; spacing: window.s(12); width: parent.width * 0.85
                                Text { text: "Add kavita_url and kavita_api_key to ai_config.json"; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.subtext0; Layout.fillWidth: true; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter }
                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: window.s(100); Layout.preferredHeight: window.s(30)
                                    radius: window.s(8); color: kavRMa.containsMouse ? window.surface1 : window.surface0; border.color: window.surface1; border.width: 1
                                    Text { anchors.centerIn: parent; text: "Reconnect"; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: kavRMa.containsMouse ? window.text : window.subtext0 }
                                    MouseArea { id: kavRMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { configReader.running = false; configReader.running = true; } }
                                }
                            }
                        }

                        // Continue Reading (last opened book)
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: window.kavitaLastName !== "" ? window.s(44) : 0
                            visible: window.kavitaConnected && window.kavitaSubMode === "ondeck" && window.kavitaLastName !== ""
                            radius: window.s(10)
                            color: contMa.containsMouse ? Qt.rgba(window.pink.r, window.pink.g, window.pink.b, 0.15) : Qt.rgba(window.pink.r, window.pink.g, window.pink.b, 0.08)
                            border.color: Qt.rgba(window.pink.r, window.pink.g, window.pink.b, 0.3); border.width: 1
                            Behavior on color { ColorAnimation { duration: 100 } }

                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: window.s(12); anchors.rightMargin: window.s(12); spacing: window.s(8)
                                Text { text: "Continue"; font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.pink }
                                Text { text: window.kavitaLastName; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(11); color: window.text; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                            MouseArea { id: contMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.kavitaOpenSeries(window.kavitaLastSeriesId, window.kavitaLastLibraryId, window.kavitaLastName) }
                        }

                        // On Deck
                        ListView {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            visible: window.kavitaConnected && window.kavitaSubMode === "ondeck"
                            model: kavitaOnDeck; clip: true; spacing: window.s(6); boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar { width: window.s(3); policy: ScrollBar.AsNeeded; contentItem: Rectangle { implicitWidth: window.s(3); radius: window.s(1); color: window.surface2 } }
                            delegate: Rectangle {
                                width: ListView.view ? ListView.view.width : 0; height: dkCol.implicitHeight + window.s(14)
                                radius: window.s(10); color: dkMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.6) : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.35)
                                border.color: dkMa.containsMouse ? Qt.rgba(window.pink.r, window.pink.g, window.pink.b, 0.5) : "transparent"; border.width: 1
                                Behavior on color { ColorAnimation { duration: 100 } }
                                ColumnLayout {
                                    id: dkCol; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: window.s(8); spacing: window.s(4)
                                    Text { text: model.name; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(12); color: dkMa.containsMouse ? window.text : window.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: window.s(8)
                                        Text { text: model.libraryName; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.pink }
                                        Rectangle { Layout.fillWidth: true; height: window.s(4); radius: window.s(2); color: window.surface1; Rectangle { width: model.pages > 0 ? parent.width                                        Text { text: model.libraryName; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.pink }
                                        Rectangle { Layout.fillWidth: true; height: window.s(4); radius: window.s(2); color: window.surface1; Rectangle { width: model.pages > 0 ? parent.width * (model.pagesRead / model.pages) : 0; height: parent.height; radius: parent.radius; color: window.pink } }
                                        Text { text: model.pages > 0 ? Math.round(model.pagesRead / model.pages * 100) + "%" : ""; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.overlay1 }
                                    }
                                }
                                MouseArea { id: dkMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.kavitaOpenSeries(model.seriesId, model.libraryId, model.name) }
                            }
                        }

                        // Library browser
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            visible: window.kavitaConnected && window.kavitaSubMode === "library"
                            ColumnLayout {
                                anchors.fill: parent; spacing: window.s(6)
                                RowLayout {
                                    Layout.fillWidth: true; spacing: window.s(4)
                                    Repeater {
                                        model: ["All", "Textbooks", "Novels", "Manga"]
                                        delegate: Rectangle {
                                            Layout.fillWidth: true; Layout.preferredHeight: window.s(26); radius: window.s(6)
                                            property string fv: modelData.toLowerCase()
                                            color: window.kavitaLibFilter === fv ? window.pink : (ltMa.containsMouse ? window.surface1 : window.surface0)
                                            border.color: window.kavitaLibFilter === fv ? window.pink : window.surface1; border.width: 1
                                            Text { anchors.centerIn: parent; text: modelData; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); font.weight: Font.Bold; color: window.kavitaLibFilter === fv ? window.crust : window.subtext0 }
                                            MouseArea { id: ltMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.kavitaLibFilter = fv }
                                        }
                                    }
                                }
                                ListView {
                                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: window.s(4); boundsBehavior: Flickable.StopAtBounds
                                    model: kavitaAllSeries
                                    ScrollBar.vertical: ScrollBar { width: window.s(3); policy: ScrollBar.AsNeeded; contentItem: Rectangle { implicitWidth: window.s(3); radius: window.s(1); color: window.surface2 } }
                                    delegate: Rectangle {
                                        width: ListView.view ? ListView.view.width : 0
                                        height: window.kavitaLibFilter === "all" || (model.libraryName || "").toLowerCase() === window.kavitaLibFilter ? lsCol.implicitHeight + window.s(12) : 0
                                        visible: height > 0; clip: true; radius: window.s(8)
                                        color: lsMa.containsMouse ? Qt.rgba(window.surface1.r, window.surface1.g, window.surface1.b, 0.6) : Qt.rgba(window.surface0.r, window.surface0.g, window.surface0.b, 0.35)
                                        border.color: lsMa.containsMouse ? Qt.rgba(window.pink.r, window.pink.g, window.pink.b, 0.5) : "transparent"; border.width: 1
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                        ColumnLayout {
                                            id: lsCol; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: window.s(8); spacing: window.s(3)
                                            Text { text: model.name; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(11); color: lsMa.containsMouse ? window.text : window.subtext0; elide: Text.ElideRight; Layout.fillWidth: true }
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: window.s(8)
                                                Text { text: model.libraryName; font.family: "JetBrains Mono"; font.pixelSize: window.s(8); color: window.pink }
                                                Text { visible: model.pages > 0; text: model.pages + " pg"; font.family: "JetBrains Mono"; font.pixelSize: window.s(8); color: window.overlay0 }
                                                Rectangle { visible: model.pagesRead > 0; Layout.fillWidth: true; height: window.s(3); radius: window.s(1); color: window.surface1; Rectangle { width: model.pages > 0 ? parent.width * (model.pagesRead / model.pages) : 0; height: parent.height; radius: parent.radius; color: window.pink } }
                                                Text { visible: model.pagesRead > 0; text: Math.round(model.pagesRead / model.pages * 100) + "%"; font.family: "JetBrains Mono"; font.pixelSize: window.s(8); color: window.overlay1 }
                                            }
                                        }
                                        MouseArea { id: lsMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.kavitaOpenSeries(model.seriesId, model.libraryId, model.name) }
                                    }
                                }
                                Text { text: kavitaAllSeries.count + " series"; font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.overlay0 }
                            }
                        }


                    }
                }





            }
        }
    }
}
