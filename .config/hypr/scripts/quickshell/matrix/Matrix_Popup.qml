import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtCore
import Quickshell
import Quickshell.Io
import "../"

// =============================================================================
// Matrix_Popup.qml — a Matrix chat client
// -----------------------------------------------------------------------------
// Emulates Element's three-pane layout (room list • timeline • composer) and
// talks to a homeserver directly over the Matrix Client-Server API (v3) using
// XMLHttpRequest:
//   • POST /login                                 — password auth -> access_token
//   • GET  /sync (long-poll)                      — initial snapshot + live deltas
//   • PUT  /rooms/{id}/send/m.room.message/{txn}  — send a message
// Credentials (homeserver + access_token + user_id) are persisted, base64'd,
// to ~/.cache/qs_matrix/session.json so login survives restarts.
//
// Limitation: unencrypted client (no E2EE — needs libolm, unavailable in QML).
// =============================================================================
Item {
    id: window
    focus: true

    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val); }

    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color mantle: _theme.mantle
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color mauve: _theme.mauve
    readonly property color green: _theme.green
    readonly property color red: _theme.red

    Shortcut { sequence: "Escape"; onActivated: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh close matrix"]) }

    // ── Session state ──────────────────────────────────────────────────────────
    property string homeserver: ""
    property string accessToken: ""
    property string userId: ""
    property string nextBatch: ""
    property bool loggedIn: false
    property bool mcInstalled: true
    property bool syncing: false
    property string statusMsg: ""
    property bool busy: false

    property string fHomeserver: "https://matrix.org"
    property string fUser: ""
    property string fPass: ""

    property var rooms: ({})
    property var roomOrder: []
    property string activeRoom: ""
    property var timeline: []

    // ── matrix-commander backend (E2EE, single device) ──────────────────────
    // This client is a thin frontend over matrix-commander. All Matrix traffic —
    // login state, room list, history, live messages, sending — goes through the
    // verified matrix-commander device, so there's no separate REST device and
    // encrypted rooms work. Backend script normalizes everything to JSON.
    // ── matrixd backend (matrix-rust-sdk, modern vodozemac E2EE) ────────────────
    // A headless Rust daemon does all Matrix protocol + encryption work; this QML
    // is a thin frontend. Commands go to its Unix socket (JSON in / JSON out via
    // socat); incoming decrypted messages are tailed from events.jsonl.
    readonly property string mxSock: "${XDG_RUNTIME_DIR:-/tmp}/qs_matrixd.sock"
    readonly property string mxCtl: "~/.config/hypr/scripts/quickshell/matrix/matrixd.sh"
    // Helper to build a 'send one JSON command to the socket, print the reply' shell line.
    function mxCmd(jsonObj) {
        // Base64-encode the JSON so ANY characters in it (passwords with $, ", \,
        // spaces, quotes, etc.) survive the trip through bash -c intact. The shell
        // just decodes and pipes to the socket — nothing in the payload is parsed
        // by the shell, so there's nothing to break.
        var b64 = Qt.btoa(JSON.stringify(jsonObj) + "\n");
        return "echo " + b64 + " | base64 -d | socat - UNIX-CONNECT:" + mxSock + " 2>/dev/null";
    }

    // ── Status / login ──────────────────────────────────────────────────────────
    Process {
        id: mxStatusProc
        // Ensure the daemon is built+running, then query status over the socket.
        command: ["bash", "-c",
            "bash " + mxCtl + " start >/dev/null 2>&1; sleep 0.3; " + mxCmd({op:"status"})]
        stdout: StdioCollector { onStreamFinished: {
            try {
                var s = JSON.parse((this.text || "{}").trim());
                window.loggedIn = s.loggedin === true;
                window.userId = s.user || "";
                if (window.loggedIn) {
                    window.statusMsg = "";
                    window.loadRooms();
                    window.startListen();   // begin tailing events.jsonl (daemon already syncs)
                } else {
                    window.statusMsg = "";  // show login form
                }
            } catch(e) { window.statusMsg = "Daemon not running — build it: matrixd.sh build"; window.loggedIn = false; }
        }}
    }
    function refreshStatus() { mxStatusProc.running = false; mxStatusProc.running = true; }

    // ── Device verification (real SAS emoji, via the matrix-rust-sdk daemon) ────
    // You tap Verify on Element (your phone) for this session; the daemon auto-
    // accepts and computes the emojis, which we poll from verify.json and show
    // below. You compare and confirm. No "Start" button is needed — Element
    // initiates, the daemon handles the rest.
    property bool   verifyOpen: false
    property bool   settingsOpen: false
    property bool   newRoomOpen: false
    property string verifyStatus: ""    // ""|requested|emojis|done|failed
    property string verifyEmojis: ""
    property string verifyAvail: "loggedin"   // daemon path is always available once logged in
    function verifyCheck() {
        window.verifyStatus = ""; window.verifyEmojis = "";
        // Clear any stale verify file, then ask the daemon to INITIATE verification
        // (sends the request to Element so it shows the prompt), then poll.
        Quickshell.execDetached(["bash", "-c",
            "rm -f ~/.cache/qs_matrix/verify.json; " + mxCmd({op:"verify_start"})]);
        verifyPoll.running = true;
    }
    function verifyConfirm() { Quickshell.execDetached(["bash", "-c", mxCmd({op:"verify_confirm"})]); }
    function verifyCancel() {
        Quickshell.execDetached(["bash", "-c", mxCmd({op:"verify_cancel"})]);
        window.verifyOpen = false; verifyPoll.running = false; window.verifyStatus = "";
    }
    // Poll verify.json (written by the daemon as the SAS flow progresses).
    Timer {
        id: verifyPoll; interval: 800; repeat: true; running: false
        onTriggered: { verifyReadProc.running = false; verifyReadProc.running = true; }
    }
    Process {
        id: verifyReadProc
        command: ["bash", "-c", "cat ~/.cache/qs_matrix/verify.json 2>/dev/null || echo '{}'"]
        stdout: StdioCollector { onStreamFinished: {
            try {
                var v = JSON.parse((this.text || "{}").trim());
                if (v.status) window.verifyStatus = v.status;
                if (v.emojis !== undefined) window.verifyEmojis = v.emojis;
                if (window.verifyStatus === "done" || window.verifyStatus === "failed")
                    verifyPoll.running = false;
            } catch(e) {}
        }}
    }

    // Login through the daemon (it persists the session + crypto store).
    Process { id: mxLoginProc; command: ["bash", "-c", "true"]
        stdout: StdioCollector { onStreamFinished: {
            try {
                var r = JSON.parse((this.text || "{}").trim());
                // Only act on an EXPLICIT failure with a real reason (e.g. wrong
                // password). Success and slow/empty replies are handled by the
                // status poll, so we don't show a false "failed" here.
                if (r.ok === false && r.error) {
                    // Ignore a "timed out" race — the poll may still confirm success.
                    if (r.error.indexOf("timed out") < 0) {
                        loginConfirmPoll.running = false;
                        window.busy = false; window.statusMsg = r.error;
                    }
                }
            } catch(e) { /* slow/partial reply — let the poll decide */ }
        }}
    }
    function doLogin() {
        window.busy = true;
        window.statusMsg = "Signing in… if Element asks to approve this device, you can ignore it — new messages work without it.";
        var hs = fHomeserver.trim();
        if (hs.indexOf("http") !== 0) hs = "https://" + hs;
        mxLoginProc.command = ["bash", "-c", mxCmd({op:"login", homeserver:hs, user:fUser, password:fPass})];
        mxLoginProc.running = false; mxLoginProc.running = true;
        // Login (device creation + crypto setup) can take 10–30s, and the reply may
        // be slow. So we ALSO poll the daemon's live status — whichever confirms
        // login first wins. Only declare failure after the poll gives up.
        window.loginTries = 0;
        loginConfirmPoll.running = true;
    }
    property int loginTries: 0
    Timer {
        id: loginConfirmPoll; interval: 1500; repeat: true; running: false
        onTriggered: {
            window.loginTries += 1;
            loginConfirmProc.running = false; loginConfirmProc.running = true;
        }
    }
    Process {
        id: loginConfirmProc
        command: ["bash", "-c", mxCmd({op:"status"})]
        stdout: StdioCollector { onStreamFinished: {
            try {
                var s = JSON.parse((this.text || "{}").trim());
                if (s.loggedin === true) {
                    // Success confirmed by the live daemon state.
                    loginConfirmPoll.running = false;
                    window.busy = false; window.statusMsg = "";
                    window.loggedIn = true; window.userId = s.user || "";
                    window.loadRooms(); window.startListen();
                    return;
                }
            } catch(e) {}
            // Not logged in yet — keep waiting up to ~20s (13 tries).
            if (window.loginTries >= 13) {
                loginConfirmPoll.running = false;
                window.busy = false;
                if (window.statusMsg.indexOf("Signing in") === 0)
                    window.statusMsg = "Couldn't sign in. Check your homeserver, username (@you:server), and password.";
            }
        }}
    }

    function logout() {
        Quickshell.execDetached(["bash", "-c", mxCmd({op:"logout"})]);
        window.loggedIn = false; window.rooms = ({}); window.roomOrder = [];
        window.activeRoom = ""; window.timeline = []; window.statusMsg = "";
        stopListen();
    }

    // ── Room list ──────────────────────────────────────────────────────────────
    Process {
        id: mxRoomsProc
        command: ["bash", "-c", mxCmd({op:"rooms"})]
        stdout: StdioCollector { onStreamFinished: {
            try {
                var resp = JSON.parse((this.text || "{}").trim());
                var arr = resp.rooms || [];
                for (var i = 0; i < arr.length; i++) {
                    var r = arr[i];
                    var room = window.rooms[r.id] || { id: r.id, name: r.id, topic: "", lastTs: 0, unread: 0, msgs: [] };
                    room.name = r.name || r.id; room.topic = r.topic || "";
                    if (r.unread !== undefined) room.unread = r.unread;
                    window.rooms[r.id] = room;
                }
                window.rebuildRoomOrder();
                window.syncing = true; window.statusMsg = "";
            } catch(e) {}
        }}
    }
    function loadRooms() { mxRoomsProc.running = false; mxRoomsProc.running = true; }

    // ── Room management (maps to the daemon's new ops) ──────────────────────────
    // Each fires the op then refreshes the room list shortly after.
    function afterAction() { roomRefreshTimer.restart(); }
    Timer { id: roomRefreshTimer; interval: 700; onTriggered: window.loadRooms() }

    function createRoom(name, topic) {
        var obj = {op:"create_room"};
        if (name && name.length) obj.name = name;
        if (topic && topic.length) obj.topic = topic;
        Quickshell.execDetached(["bash", "-c", mxCmd(obj)]); afterAction();
    }
    function createDm(userId) {
        if (!userId || userId.length === 0) return;
        Quickshell.execDetached(["bash", "-c", mxCmd({op:"create_dm", user:userId})]); afterAction();
    }
    function joinRoom(target) {
        if (!target || target.length === 0) return;
        Quickshell.execDetached(["bash", "-c", mxCmd({op:"join", room:target})]); afterAction();
    }
    function leaveRoom(rid) {
        Quickshell.execDetached(["bash", "-c", mxCmd({op:"leave", room:rid})]);
        if (window.activeRoom === rid) { window.activeRoom = ""; window.timeline = []; }
        afterAction();
    }
    function inviteUser(rid, userId) {
        if (!userId || userId.length === 0) return;
        Quickshell.execDetached(["bash", "-c", mxCmd({op:"invite", room:rid, user:userId})]);
    }
    function setRoomName(rid, name) {
        Quickshell.execDetached(["bash", "-c", mxCmd({op:"set_name", room:rid, name:name})]); afterAction();
    }
    function setRoomTopic(rid, topic) {
        Quickshell.execDetached(["bash", "-c", mxCmd({op:"set_topic", room:rid, topic:topic})]);
    }
    function markRead(rid) { Quickshell.execDetached(["bash", "-c", mxCmd({op:"mark_read", room:rid})]); }
    function sendTyping(rid, on) { Quickshell.execDetached(["bash", "-c", mxCmd({op:"typing", room:rid, on:on})]); }

    // Member list — result handled by mxMembersProc.
    property var roomMembers: []
    function loadMembers(rid) {
        mxMembersProc.command = ["bash", "-c", mxCmd({op:"members", room:rid})];
        mxMembersProc.running = false; mxMembersProc.running = true;
    }
    Process {
        id: mxMembersProc; command: ["bash", "-c", "true"]
        stdout: StdioCollector { onStreamFinished: {
            try {
                var r = JSON.parse((this.text || "{}").trim());
                window.roomMembers = (r.ok && r.members) ? r.members : [];
            } catch(e) { window.roomMembers = []; }
        }}
    }

    // Real history backfill — merges fetched messages into the active room.
    function loadHistoryReal(rid, n) {
        mxHist2Proc.command = ["bash", "-c", mxCmd({op:"history", room:rid, limit:(n||40)})];
        mxHist2Proc.running = false; mxHist2Proc.running = true;
    }
    Process {
        id: mxHist2Proc; command: ["bash", "-c", "true"]
        stdout: StdioCollector { onStreamFinished: {
            try {
                var r = JSON.parse((this.text || "{}").trim());
                if (r.ok && r.messages && window.activeRoom !== "") {
                    var room = window.rooms[window.activeRoom];
                    if (room) {
                        // Prepend history that isn't already present (by id).
                        var have = {};
                        for (var i = 0; i < room.msgs.length; i++) have[room.msgs[i].id] = true;
                        var merged = [];
                        for (var j = 0; j < r.messages.length; j++) {
                            var m = r.messages[j];
                            if (!have[m.id]) merged.push({ id:m.id, sender:m.sender, body:m.body,
                                msgtype:m.msgtype, ts:m.ts, mine:(m.sender===window.userId) });
                        }
                        room.msgs = merged.concat(room.msgs);
                        window.rooms[window.activeRoom] = room;
                        window.timeline = room.msgs.slice();
                    }
                }
            } catch(e) {}
        }}
    }


    // ── History for a room (loaded when you open it) ────────────────────────────
    property string histLoadingRoom: ""
    Process {
        id: mxHistProc
        command: ["bash", "-c", "true"]
        stdout: StdioCollector { onStreamFinished: {
            try {
                var arr = JSON.parse((this.text || "[]").trim());
                var rid = window.histLoadingRoom;
                var room = window.rooms[rid]; if (!room) return;
                // matrix-commander tail prints newest..oldest; reverse to chronological.
                arr.reverse();
                room.msgs = [];
                for (var i = 0; i < arr.length; i++) {
                    var m = arr[i];
                    room.msgs.push({ id: m.id, sender: m.sender, body: m.body,
                                     msgtype: m.msgtype, ts: m.ts, mine: (m.sender === window.userId) });
                    if (m.ts > room.lastTs) room.lastTs = m.ts;
                }
                window.rooms[rid] = room;
                if (window.activeRoom === rid) window.timeline = room.msgs.slice();
                window.rebuildRoomOrder();
            } catch(e) {}
        }}
    }
    function loadHistory(rid, n) {
        // The daemon writes live messages to events.jsonl which we tail; explicit
        // backfill of older history is a future enhancement (the daemon's sync
        // already surfaces recent messages on connect).
        window.histLoadingRoom = rid;
    }

    // ── Live messages: the daemon syncs continuously and writes events.jsonl. ──
    // We just tail that file; there's no separate listener process to start/stop.
    function startListen() { mxEventsTail.running = true; }
    function stopListen() { mxEventsTail.running = false; }
    // Track how many event lines we've consumed so we only ingest new ones.
    property int mxEventOffset: 0
    Timer {
        id: mxEventsTail; interval: 1500; repeat: true; running: false
        onTriggered: { mxEventsProc.running = false; mxEventsProc.running = true; }
    }
    Process {
        id: mxEventsProc
        command: ["bash", "-c",
            "F=\"$HOME/.cache/qs_matrix/events.jsonl\"; [ -f \"$F\" ] || exit 0; " +
            "tail -n +" + (mxEventOffset + 1) + " \"$F\""]
        stdout: StdioCollector { onStreamFinished: {
            var txt = (this.text || "").trim();
            if (txt === "") return;
            var lines = txt.split("\n");
            window.mxEventOffset += lines.length;
            var touched = false;
            for (var i = 0; i < lines.length; i++) {
                if (lines[i].trim() === "") continue;
                try {
                    var m = JSON.parse(lines[i]);
                    var rid = m.room; if (!rid) continue;
                    var room = window.rooms[rid] || { id: rid, name: rid, topic: "", lastTs: 0, unread: 0, msgs: [] };
                    // de-dup by event id
                    var dup = false;
                    for (var k = room.msgs.length - 1; k >= 0 && k > room.msgs.length - 30; k--)
                        if (room.msgs[k].id === m.id) { dup = true; break; }
                    if (dup) continue;
                    room.msgs.push({ id: m.id, sender: m.sender, body: m.body, msgtype: m.msgtype,
                                     ts: m.ts, mine: (m.sender === window.userId) });
                    room.lastTs = m.ts || room.lastTs;
                    if (rid !== window.activeRoom && m.sender !== window.userId) room.unread++;
                    if (room.msgs.length > 200) room.msgs = room.msgs.slice(room.msgs.length - 200);
                    window.rooms[rid] = room; touched = true;
                } catch(e) {}
            }
            if (touched) {
                window.rebuildRoomOrder();
                if (window.activeRoom !== "" && window.rooms[window.activeRoom])
                    window.timeline = window.rooms[window.activeRoom].msgs.slice();
            }
        }}
    }

    Component.onCompleted: { window.refreshStatus(); }

    function rebuildRoomOrder() {
        var ids = Object.keys(rooms);
        ids.sort(function(a, b) { return (rooms[b].lastTs || 0) - (rooms[a].lastTs || 0); });
        roomOrder = ids;
    }

    function openRoom(rid) {
        activeRoom = rid;
        if (rooms[rid]) { rooms[rid].unread = 0; timeline = rooms[rid].msgs.slice(); rebuildRoomOrder(); }
        loadHistoryReal(rid, 40);   // real backfill from the daemon
        loadMembers(rid);           // populate member list
        markRead(rid);              // clear unread on the server
    }

    // ── Send (encrypted, via matrix-commander) ─────────────────────────────────
    Process { id: mxSendProc; command: ["bash", "-c", "true"] }
    function sendMessage(textBody) {
        if (activeRoom === "" || textBody.trim() === "") return;
        var room = rooms[activeRoom];
        if (room) {
            room.msgs.push({ id: "pending" + Date.now(), sender: userId, body: textBody,
                             msgtype: "m.text", ts: Date.now(), mine: true, pending: true });
            timeline = room.msgs.slice();
        }
        mxSendProc.command = ["bash", "-c", mxCmd({op:"send", room:activeRoom, body:textBody})];
        mxSendProc.running = false; mxSendProc.running = true;
    }

    function shortName(mxid) {
        if (!mxid) return "?";
        var n = mxid.replace(/^@/, "");
        var c = n.indexOf(":");
        return c > 0 ? n.substring(0, c) : n;
    }
    function fmtTime(ts) {
        if (!ts) return "";
        var d = new Date(ts);
        var h = d.getHours(), m = d.getMinutes();
        return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
    }

    // =========================================================================
    // UI
    // =========================================================================
    Rectangle {
        anchors.fill: parent
        radius: window.s(18)
        color: window.base
        border.color: window.surface1
        border.width: 1
        clip: true

        // ── LOGIN VIEW ────────────────────────────────────────────────────────
        Item {
            anchors.fill: parent
            visible: !window.loggedIn

            ColumnLayout {
                anchors.centerIn: parent
                width: window.s(320)
                spacing: window.s(12)

                Text { Layout.alignment: Qt.AlignHCenter; text: "󰸿"
                    font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(48); color: window.green }
                Text { Layout.alignment: Qt.AlignHCenter; text: "Sign in to Matrix"
                    font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(18); color: window.text }
                Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                    text: "End-to-end encrypted via the matrixd daemon (matrix-rust-sdk)."
                    font.family: "JetBrains Mono"; font.pixelSize: window.s(9); color: window.subtext0 }

                Rectangle {
                    Layout.fillWidth: true; height: window.s(38); radius: window.s(10); color: window.surface0
                    border.color: hsIn.activeFocus ? window.mauve : window.surface1; border.width: 1
                    TextInput { id: hsIn; anchors.fill: parent; anchors.margins: window.s(10)
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: "JetBrains Mono"; font.pixelSize: window.s(12); color: window.text
                        clip: true; text: window.fHomeserver; onTextChanged: window.fHomeserver = text
                        Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                            visible: hsIn.text === ""; text: "Homeserver (https://matrix.org)"
                            font: hsIn.font; color: window.subtext0 } }
                }
                Rectangle {
                    Layout.fillWidth: true; height: window.s(38); radius: window.s(10); color: window.surface0
                    border.color: userIn.activeFocus ? window.mauve : window.surface1; border.width: 1
                    TextInput { id: userIn; anchors.fill: parent; anchors.margins: window.s(10)
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: "JetBrains Mono"; font.pixelSize: window.s(12); color: window.text
                        clip: true; text: window.fUser; onTextChanged: window.fUser = text
                        Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                            visible: userIn.text === ""; text: "@user:matrix.org"
                            font: userIn.font; color: window.subtext0 } }
                }
                Rectangle {
                    Layout.fillWidth: true; height: window.s(38); radius: window.s(10); color: window.surface0
                    border.color: passIn.activeFocus ? window.mauve : window.surface1; border.width: 1
                    TextInput { id: passIn; anchors.fill: parent; anchors.margins: window.s(10)
                        verticalAlignment: TextInput.AlignVCenter; echoMode: TextInput.Password
                        font.family: "JetBrains Mono"; font.pixelSize: window.s(12); color: window.text
                        clip: true; text: window.fPass; onTextChanged: window.fPass = text; onAccepted: window.doLogin()
                        Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                            visible: passIn.text === ""; text: "Password"
                            font: passIn.font; color: window.subtext0 } }
                }
                Rectangle {
                    Layout.fillWidth: true; height: window.s(40); radius: window.s(10)
                    color: loginMa.containsMouse ? window.mauve : window.surface2
                    Text { anchors.centerIn: parent; text: window.busy ? "…" : "Sign in"
                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(13)
                        color: loginMa.containsMouse ? window.crust : window.text }
                    MouseArea { id: loginMa; anchors.fill: parent; hoverEnabled: true
                        enabled: !window.busy; cursorShape: Qt.PointingHandCursor; onClicked: window.doLogin() }
                }
                Text { Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                    visible: window.statusMsg !== ""; text: window.statusMsg; wrapMode: Text.WordWrap
                    font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.subtext0 }
            }
        }

        // ── CLIENT VIEW (Element-style three panes) ────────────────────────────
        RowLayout {
            anchors.fill: parent
            anchors.margins: window.s(1)
            spacing: 0
            visible: window.loggedIn

            // ROOM LIST
            Rectangle {
                Layout.preferredWidth: window.s(230); Layout.fillHeight: true
                color: window.mantle; radius: window.s(18)

                ColumnLayout {
                    anchors.fill: parent; anchors.margins: window.s(12); spacing: window.s(8)

                    RowLayout {
                        Layout.fillWidth: true
                        // Username opens a settings dropdown.
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: window.s(28); radius: window.s(8)
                            color: userMa.containsMouse || window.settingsOpen ? window.surface0 : "transparent"
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: window.s(6); anchors.rightMargin: window.s(6); spacing: window.s(4)
                                Text { Layout.fillWidth: true; text: window.shortName(window.userId); elide: Text.ElideRight
                                    font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(15); color: window.text }
                                Text { text: window.settingsOpen ? "󰅃" : "󰅀"
                                    font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(12); color: window.subtext0 }
                            }
                            MouseArea { id: userMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: window.settingsOpen = !window.settingsOpen }
                        }
                        // New room / DM / join (toggles the panel below).
                        Rectangle {
                            width: window.s(26); height: window.s(26); radius: window.s(8)
                            color: addMa.containsMouse || window.newRoomOpen ? window.mauve : window.surface0
                            Text { anchors.centerIn: parent; text: "󰐕"
                                font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(15)
                                color: (addMa.containsMouse || window.newRoomOpen) ? window.crust : window.subtext0 }
                            MouseArea { id: addMa; anchors.fill: parent; hoverEnabled: true
                                onClicked: window.newRoomOpen = !window.newRoomOpen }
                        }
                    }
                    // Settings dropdown (toggled by the username).
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: window.settingsOpen ? window.s(76) : 0
                        clip: true; radius: window.s(10); color: window.surface0
                        visible: Layout.preferredHeight > 0
                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: window.s(6); spacing: window.s(4)
                            // Verify device
                            Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: window.s(30); radius: window.s(8)
                                color: setVerMa.containsMouse ? window.green : window.surface1
                                RowLayout { anchors.fill: parent; anchors.leftMargin: window.s(8); spacing: window.s(8)
                                    Text { text: "󰒃"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(14)
                                        color: setVerMa.containsMouse ? window.crust : window.subtext0 }
                                    Text { Layout.fillWidth: true; text: "Verify this device"
                                        font.family: "JetBrains Mono"; font.pixelSize: window.s(11)
                                        color: setVerMa.containsMouse ? window.crust : window.text } }
                                MouseArea { id: setVerMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { window.settingsOpen = false; window.verifyCheck(); window.verifyOpen = true; } }
                            }
                            // Logout
                            Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: window.s(30); radius: window.s(8)
                                color: setOutMa.containsMouse ? window.red : window.surface1
                                RowLayout { anchors.fill: parent; anchors.leftMargin: window.s(8); spacing: window.s(8)
                                    Text { text: "󰍃"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(14)
                                        color: setOutMa.containsMouse ? window.crust : window.subtext0 }
                                    Text { Layout.fillWidth: true; text: "Sign out"
                                        font.family: "JetBrains Mono"; font.pixelSize: window.s(11)
                                        color: setOutMa.containsMouse ? window.crust : window.text } }
                                MouseArea { id: setOutMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { window.settingsOpen = false; window.logout(); } }
                            }
                        }
                    }
                    Text { text: window.syncing ? "● connected" : (window.statusMsg !== "" ? window.statusMsg : "○ offline")
                        font.family: "JetBrains Mono"; font.pixelSize: window.s(10)
                        color: window.syncing ? window.green : window.subtext0 }
                    Rectangle { Layout.fillWidth: true; height: 1; color: window.surface1 }

                    // Collapsible new-room / DM / join panel.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: window.newRoomOpen ? window.s(150) : 0
                        clip: true; radius: window.s(10)
                        color: window.surface0
                        visible: Layout.preferredHeight > 0
                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: window.s(8); spacing: window.s(6)
                            RowLayout {
                                Layout.fillWidth: true; spacing: window.s(6)
                                Rectangle {
                                    Layout.fillWidth: true; height: window.s(30); radius: window.s(8); color: window.surface1
                                    TextInput { id: newRoomName; anchors.fill: parent; anchors.margins: window.s(8)
                                        verticalAlignment: TextInput.AlignVCenter; clip: true
                                        font.family: "JetBrains Mono"; font.pixelSize: window.s(11); color: window.text
                                        Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                            visible: newRoomName.text === ""; text: "New room name…"
                                            font: newRoomName.font; color: window.subtext0 } }
                                }
                                Rectangle {
                                    width: window.s(54); height: window.s(30); radius: window.s(8)
                                    color: crMa.containsMouse ? window.green : window.surface2
                                    Text { anchors.centerIn: parent; text: "Create"; font.family: "JetBrains Mono"
                                        font.pixelSize: window.s(9); color: crMa.containsMouse ? window.crust : window.text }
                                    MouseArea { id: crMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { window.createRoom(newRoomName.text, ""); newRoomName.text = ""; window.newRoomOpen = false; } }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: window.s(6)
                                Rectangle {
                                    Layout.fillWidth: true; height: window.s(30); radius: window.s(8); color: window.surface1
                                    TextInput { id: newDmUser; anchors.fill: parent; anchors.margins: window.s(8)
                                        verticalAlignment: TextInput.AlignVCenter; clip: true
                                        font.family: "JetBrains Mono"; font.pixelSize: window.s(11); color: window.text
                                        Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                            visible: newDmUser.text === ""; text: "DM @user:server"
                                            font: newDmUser.font; color: window.subtext0 } }
                                }
                                Rectangle {
                                    width: window.s(54); height: window.s(30); radius: window.s(8)
                                    color: dmMa.containsMouse ? window.blue : window.surface2
                                    Text { anchors.centerIn: parent; text: "DM"; font.family: "JetBrains Mono"
                                        font.pixelSize: window.s(9); color: dmMa.containsMouse ? window.crust : window.text }
                                    MouseArea { id: dmMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { window.createDm(newDmUser.text); newDmUser.text = ""; window.newRoomOpen = false; } }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: window.s(6)
                                Rectangle {
                                    Layout.fillWidth: true; height: window.s(30); radius: window.s(8); color: window.surface1
                                    TextInput { id: joinTarget; anchors.fill: parent; anchors.margins: window.s(8)
                                        verticalAlignment: TextInput.AlignVCenter; clip: true
                                        font.family: "JetBrains Mono"; font.pixelSize: window.s(11); color: window.text
                                        Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                            visible: joinTarget.text === ""; text: "Join #room:server or !id"
                                            font: joinTarget.font; color: window.subtext0 } }
                                }
                                Rectangle {
                                    width: window.s(54); height: window.s(30); radius: window.s(8)
                                    color: jnMa.containsMouse ? window.mauve : window.surface2
                                    Text { anchors.centerIn: parent; text: "Join"; font.family: "JetBrains Mono"
                                        font.pixelSize: window.s(9); color: jnMa.containsMouse ? window.crust : window.text }
                                    MouseArea { id: jnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { window.joinRoom(joinTarget.text); joinTarget.text = ""; window.newRoomOpen = false; } }
                                }
                            }
                        }
                    }

                    ListView {
                        Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: window.s(3)
                        model: window.roomOrder
                        delegate: Rectangle {
                            width: ListView.view.width; height: window.s(50); radius: window.s(10)
                            property var room: window.rooms[modelData]
                            property bool active: (modelData !== undefined && modelData === window.activeRoom)
                            color: active ? window.surface1 : (rMa.containsMouse ? window.surface0 : "transparent")
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: window.s(10); anchors.rightMargin: window.s(10)
                                spacing: window.s(10)
                                Rectangle {
                                    width: window.s(34); height: window.s(34); radius: window.s(10); color: window.surface2
                                    Text { anchors.centerIn: parent
                                        text: (room && room.name) ? room.name.charAt(0).toUpperCase() : "#"
                                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(15); color: window.mauve }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 0
                                    Text { Layout.fillWidth: true; elide: Text.ElideRight; text: room ? room.name : modelData
                                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(13); color: window.text }
                                    Text { Layout.fillWidth: true; elide: Text.ElideRight
                                        visible: !!(room && room.msgs && room.msgs.length > 0)
                                        text: (room && room.msgs.length > 0)
                                            ? (window.shortName(room.msgs[room.msgs.length-1].sender) + ": " + room.msgs[room.msgs.length-1].body) : ""
                                        font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.subtext0 }
                                }
                                Rectangle {
                                    visible: !!(room && room.unread > 0)
                                    width: window.s(20); height: window.s(20); radius: window.s(10); color: window.mauve
                                    Text { anchors.centerIn: parent; text: room ? room.unread : ""
                                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(10); color: window.crust }
                                }
                            }
                            MouseArea { id: rMa; anchors.fill: parent; hoverEnabled: true; onClicked: window.openRoom(modelData) }
                        }
                    }
                }
            }

            // TIMELINE + COMPOSER
            Item {
                Layout.fillWidth: true; Layout.fillHeight: true

                ColumnLayout {
                    anchors.centerIn: parent; visible: window.activeRoom === ""; spacing: window.s(8)
                    Text { Layout.alignment: Qt.AlignHCenter; text: "󰭹"
                        font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(48); color: window.surface2 }
                    Text { Layout.alignment: Qt.AlignHCenter; text: "Select a room"
                        font.family: "JetBrains Mono"; font.pixelSize: window.s(14); color: window.subtext0 }
                }

                ColumnLayout {
                    anchors.fill: parent; anchors.margins: window.s(12); spacing: window.s(8)
                    visible: window.activeRoom !== ""

                    RowLayout {
                        Layout.fillWidth: true
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 0
                            Text { text: (window.rooms[window.activeRoom] ? window.rooms[window.activeRoom].name : "")
                                font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(16); color: window.text }
                            Text { Layout.fillWidth: true; elide: Text.ElideRight
                                visible: !!(window.rooms[window.activeRoom] && window.rooms[window.activeRoom].topic !== "")
                                text: window.rooms[window.activeRoom] ? window.rooms[window.activeRoom].topic : ""
                                font.family: "JetBrains Mono"; font.pixelSize: window.s(10); color: window.subtext0 }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: window.surface1 }

                    ListView {
                        id: tlView
                        Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: window.s(8)
                        model: window.timeline
                        onCountChanged: positionViewAtEnd()
                        delegate: Row {
                            width: tlView.width
                            layoutDirection: modelData.mine ? Qt.RightToLeft : Qt.LeftToRight
                            spacing: window.s(8)
                            Column {
                                width: Math.min(tlView.width * 0.72, bubbleText.implicitWidth + window.s(24))
                                spacing: window.s(2)
                                Text { visible: !modelData.mine; text: window.shortName(modelData.sender)
                                    font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(10); color: window.mauve }
                                Rectangle {
                                    width: parent.width; height: bubbleText.implicitHeight + window.s(14); radius: window.s(12)
                                    color: modelData.mine ? window.mauve : window.surface0
                                    opacity: modelData.pending ? 0.6 : 1.0
                                    Text { id: bubbleText; anchors.fill: parent; anchors.margins: window.s(7)
                                        text: modelData.body; wrapMode: Text.Wrap
                                        font.family: "JetBrains Mono"; font.pixelSize: window.s(12)
                                        color: modelData.mine ? window.crust : window.text }
                                }
                                Text { anchors.right: modelData.mine ? parent.right : undefined
                                    text: window.fmtTime(modelData.ts)
                                    font.family: "JetBrains Mono"; font.pixelSize: window.s(8); color: window.subtext0 }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; height: window.s(44); radius: window.s(12); color: window.surface0
                        border.color: composer.activeFocus ? window.mauve : window.surface1; border.width: 1
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: window.s(12); anchors.rightMargin: window.s(6); spacing: window.s(6)
                            TextInput {
                                id: composer; Layout.fillWidth: true; verticalAlignment: TextInput.AlignVCenter
                                font.family: "JetBrains Mono"; font.pixelSize: window.s(13); color: window.text; clip: true
                                onAccepted: { if (text.trim() !== "") { window.sendMessage(text); text = ""; } }
                                Text { anchors.verticalCenter: parent.verticalCenter
                                    visible: composer.text === ""; text: "Message…"; font: composer.font; color: window.subtext0 }
                            }
                            Rectangle {
                                width: window.s(32); height: window.s(32); radius: window.s(9)
                                color: sendMa.containsMouse ? window.mauve : window.surface2
                                Text { anchors.centerIn: parent; text: "󰒊"
                                    font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(15)
                                    color: sendMa.containsMouse ? window.crust : window.text }
                                MouseArea { id: sendMa; anchors.fill: parent; hoverEnabled: true
                                    onClicked: { if (composer.text.trim() !== "") { window.sendMessage(composer.text); composer.text = ""; } } }
                            }
                        }
                    }
                }
            }

            // ── Device verification overlay ──
            Rectangle {
                anchors.fill: parent
                z: 500
                visible: window.verifyOpen
                color: Qt.rgba(window.crust.r, window.crust.g, window.crust.b, 0.94)
                MouseArea { anchors.fill: parent }   // swallow background clicks

                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - window.s(40), window.s(360))
                    spacing: window.s(12)

                    Text {
                        text: "Verify Device"
                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(16); color: window.text
                        Layout.alignment: Qt.AlignHCenter
                    }

                    // Not installed / needs login guidance.
                    // Instructions + live status.
                    Text {
                        Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                        text: {
                            if (window.verifyStatus === "done") return "✓ Verified! This device now shows a green shield in Element.";
                            if (window.verifyStatus === "failed") return "Verification failed or was cancelled. Close and try again.";
                            if (window.verifyStatus === "emojis") return "Compare these emojis with the ones on Element, then confirm:";
                            if (window.verifyStatus === "requested") return "Request sent — on Element, tap to accept the verification. Emojis will appear here.";
                            return "Starting verification… Element should prompt you shortly. If not, on Element open Settings → this session → Verify.";
                        }
                        font.family: "JetBrains Mono"; font.pixelSize: window.s(10)
                        color: window.verifyStatus === "done" ? window.green : (window.verifyStatus === "failed" ? window.red : window.subtext1)
                    }

                    // Captured emoji line.
                    Rectangle {
                        visible: window.verifyEmojis !== ""
                        Layout.fillWidth: true; Layout.preferredHeight: window.s(80); radius: window.s(10)
                        color: window.surface0; border.color: window.surface2; border.width: 1
                        Text {
                            anchors.fill: parent; anchors.margins: window.s(8)
                            text: window.verifyEmojis
                            font.family: "JetBrains Mono"; font.pixelSize: window.s(13)
                            color: window.text; wrapMode: Text.Wrap
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                    }

                    // Action buttons.
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter; spacing: window.s(10)

                        // They match (confirm) — only once emojis are shown.
                        Rectangle {
                            visible: window.verifyStatus === "emojis"
                            Layout.preferredWidth: window.s(110); Layout.preferredHeight: window.s(34); radius: window.s(10)
                            color: vYesMa.containsMouse ? window.green : window.surface1
                            Text { anchors.centerIn: parent; text: "They match"
                                font.family: "JetBrains Mono"; font.pixelSize: window.s(11); color: vYesMa.containsMouse ? window.crust : window.text }
                            MouseArea { id: vYesMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: window.verifyConfirm() }
                        }
                        // No match
                        Rectangle {
                            visible: window.verifyStatus === "emojis"
                            Layout.preferredWidth: window.s(90); Layout.preferredHeight: window.s(34); radius: window.s(10)
                            color: vNoMa.containsMouse ? window.red : window.surface1
                            Text { anchors.centerIn: parent; text: "No match"
                                font.family: "JetBrains Mono"; font.pixelSize: window.s(11); color: vNoMa.containsMouse ? window.crust : window.text }
                            MouseArea { id: vNoMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: window.verifyCancel() }
                        }
                        // Close / cancel
                        Rectangle {
                            Layout.preferredWidth: window.s(90); Layout.preferredHeight: window.s(34); radius: window.s(10)
                            color: vCloseMa.containsMouse ? window.surface2 : "transparent"
                            border.color: window.surface2; border.width: 1
                            Text { anchors.centerIn: parent; text: window.verifyStatus === "done" ? "Done" : "Close"
                                font.family: "JetBrains Mono"; font.pixelSize: window.s(11); color: window.subtext0 }
                            MouseArea { id: vCloseMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: window.verifyCancel() }
                        }
                    }
                }
            }
        }
    }
}
