//@ pragma UseQApplication
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray

// hyprland.conf additions:
//   windowrule { match:title = ^(qs-ai-response)$; float = on; center = on; size = 900 600 }

Variants {
    model: Quickshell.screens

    delegate: Component {
        PanelWindow {
            id: barWindow

            required property var modelData
            screen: modelData
            anchors { top: true; left: true; right: true }

            Scaler { id: scaler; currentWidth: barWindow.width }
            property real baseScale: scaler.baseScale
            function s(val) { return scaler.s(val); }

            property int barHeight: s(48)
            implicitHeight: barHeight
            margins { top: s(8); bottom: 0; left: s(4); right: s(4) }
            exclusiveZone: barHeight + s(4)
            color: "transparent"

            MatugenColors { id: mocha }

            // ── State ──
            property bool isRecording: false
            property bool updateAvailable: false
            property int workspaceCount: 8
            property string activeWidget: ""
            property bool isDesktop: false
            property string focusMode: "default"
            property bool hasNotifications: false
            property int focusEndEpoch: 0
            property int focusRemainSec: 0
            property bool focusWarned: false
            property string focusCountdown: {
                if (focusRemainSec <= 0) return "";
                let m = Math.floor(focusRemainSec / 60);
                let s = focusRemainSec % 60;
                return m + ":" + (s < 10 ? "0" : "") + s;
            }
            property string ethStatus: "Ethernet"
            property bool isStartupReady: false

            // ── AI popup state ──
            property bool aiVisible: false
            property string aiQuery: ""
            property string aiResponse: ""
            property string aiState: "loading"
            property int aiTypeLen: 0
            property string aiDisplayed: aiResponse.substring(0, aiTypeLen)
            property bool startupCascadeFinished: false
            property bool fastPollerLoaded: false
            property bool isDataReady: fastPollerLoaded

            // ── Float state ──
            property bool currentWindowIsFloating: false
            property bool floatPollBlocked: false

            // ── Workspace windows ──
            ListModel { id: wsWindows }
            property string activeWindowAddr: ""

            // ── Time / weather ──
            property string timeStr: ""
            property string fullDateStr: ""
            property int typeInIndex: 0
            property string dateStr: fullDateStr.substring(0, typeInIndex)
            property string weatherIcon: ""
            property string weatherTemp: "--°"
            property string weatherHex: mocha.yellow

            // ── System status ──
            property string wifiStatus: "Off"
            property string wifiIcon: "󰤮"
            property string wifiSsid: ""
            property string btStatus: "Off"
            property string btIcon: "󰂲"
            property string btDevice: ""
            property string volPercent: "0%"
            property string volIcon: "󰕾"
            property bool isMuted: false
            property string batPercent: "100%"
            property string batIcon: "󰁹"
            property string batStatus: "Unknown"
            property string kbLayout: "us"

            // ── Music ──
            property var musicData: ({ "status": "Stopped", "title": "", "artUrl": "", "timeStr": "" })

            // ── Derived ──
            property bool isMediaActive: musicData.status !== "Stopped" && musicData.title !== ""
            property bool isWifiOn: wifiStatus.toLowerCase() === "enabled" || wifiStatus.toLowerCase() === "on"
            property bool isBtOn: btStatus.toLowerCase() === "enabled" || btStatus.toLowerCase() === "on"
            property bool showEthernet: isDesktop && !isWifiOn
            property bool isSoundActive: !isMuted && parseInt(volPercent) > 0
            property int batCap: parseInt(batPercent) || 0
            property bool isCharging: batStatus === "Charging" || batStatus === "Full"
            property color batDynamicColor: isCharging ? mocha.green : (batCap <= 20 ? mocha.red : mocha.text)

            // ── Dock icon paths ──
            property string iconKitty: ""
            property string iconDolphin: ""
            property string iconBrave: ""
            property string iconTutanota: ""
            property string iconMaterialious: ""
            property string iconJellyfin: ""
            property string iconNavidrome: ""
            property string iconSteam: ""
            property string iconHeroic: ""
            property string iconLutris: ""
            property string iconBottles: ""
            property string iconPrism: ""
            property string iconRetroarch: ""
            property string iconMinigalaxy: ""
            property string iconElement: ""

            // ── Dock clients / preview ──
            property var hyprClients: []
            property int previewDockIndex: -1
            property string previewTitle: ""
            property bool previewImageReady: false
            property string previewTmpPath: "/tmp/qs_dock_preview.png"

            ListModel { id: workspacesModel }

            // ─────────────────────────────────────────────
            // HELPER FUNCTIONS
            // ─────────────────────────────────────────────
            // Convert workspace number (1-10) to standard Japanese kanji
            function toKanji(n) {
                let kanji = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"];
                let num = parseInt(n);
                if (num >= 1 && num <= 10) return kanji[num];
                return n; // fallback for >10
            }

            // Translates a "resolved" icon hint into a QML Image source.
            //
            // The crash we fixed: previously this returned "file://" + path
            // unconditionally, even when the file didn't exist. The Image
            // element would fail and onStatusChanged would re-set source to
            // image://icon/<fallback> — and that fallback chain has a known
            // bug in current Quickshell-git that crashes the entire process.
            //
            // Fix: prefer image://icon/ paths upfront. Only use file:// if we
            // got an absolute path that looks like a real desktop icon file
            // and ends in a known image extension. The Image element's
            // onStatusChanged handler is kept simple — single fallback, no
            // re-firing.
            function iconSource(resolved, fallbackName) {
                // No resolved icon → freedesktop icon name lookup
                if (!resolved || resolved === "") {
                    return "image://icon/" + fallbackName;
                }
                // Image provider URLs pass through
                if (resolved.startsWith("image://") || resolved.startsWith("qrc:")) {
                    return resolved;
                }
                // Bare name (no path, no extension) → freedesktop lookup
                if (resolved.indexOf("/") === -1) {
                    return "image://icon/" + resolved;
                }
                // Absolute path with image extension → file:// URL
                // (caller should pre-validate, but we accept it here)
                let lc = resolved.toLowerCase();
                if (resolved.startsWith("/") &&
                    (lc.endsWith(".png") || lc.endsWith(".svg") ||
                     lc.endsWith(".jpg") || lc.endsWith(".jpeg") ||
                     lc.endsWith(".xpm") || lc.endsWith(".ico"))) {
                    return "file://" + resolved;
                }
                // Anything else (weird paths, relative paths, etc.) — bail
                // to fallback rather than handing Image a broken URL.
                return "image://icon/" + fallbackName;
            }

            function clientsForApp(classNames) {
                let result = [];
                for (let i = 0; i < hyprClients.length; i++) {
                    let c = hyprClients[i];
                    let cls = (c.class || "").toLowerCase();
                    for (let j = 0; j < classNames.length; j++) {
                        if (cls.indexOf(classNames[j].toLowerCase()) !== -1) {
                            result.push(c);
                            break;
                        }
                    }
                }
                return result;
            }

            function capturePreview(client) {
                if (!client || !client.at || !client.size) return;
                let x = client.at[0];
                let y = client.at[1];
                let w = client.size[0];
                let h = client.size[1];
                if (w <= 0 || h <= 0) return;
                let mon = (client.monitor !== undefined && client.monitor !== "") ? client.monitor : "";
                let ws  = (client.workspace && client.workspace.id !== undefined)
                          ? String(client.workspace.id) : "";
                let addr = client.address || "";
                // Switch to the window's workspace, wait for compositor to settle,
                // then capture the window geometry, then switch back.
                let switchBack = "";
                let switchTo   = "";
                if (ws !== "") {
                    switchTo   = "hyprctl dispatch workspace " + ws + " ; sleep 0.25 ; ";
                    switchBack = " ; hyprctl dispatch workspace previous_per_monitor";
                }
                let captureCmd = "";
                if (mon !== "") {
                    captureCmd = "grim -o " + mon + " /tmp/qs_mon_preview.png && " +
                                 "convert /tmp/qs_mon_preview.png -crop " + w + "x" + h + "+" + x + "+" + y +
                                 " +repage " + previewTmpPath + " 2>/dev/null || " +
                                 "grim -g \"" + x + "," + y + " " + w + "x" + h + "\" " + previewTmpPath;
                } else {
                    captureCmd = "grim -g \"" + x + "," + y + " " + w + "x" + h + "\" " + previewTmpPath;
                }
                let cmd = switchTo + captureCmd + switchBack;
                previewCapture.command = ["bash", "-c", cmd];
                previewImageReady = false;
                previewCapture.running = false;
                previewCapture.running = true;
            }

            // ─────────────────────────────────────────────
            // STARTUP TIMERS
            // ─────────────────────────────────────────────
            Timer { interval: 10;   running: true; onTriggered: barWindow.isStartupReady = true }
            Timer { interval: 1000; running: true; onTriggered: barWindow.startupCascadeFinished = true }
            Timer { interval: 600;  running: true; onTriggered: barWindow.isDataReady = true }

            // ─────────────────────────────────────────────
            // MASK (no sidebar hole needed)
            // ─────────────────────────────────────────────

            // ─────────────────────────────────────────────
            // DOCK ICON RESOLVERS
            // ─────────────────────────────────────────────
            Process {
                id: iconResolverKitty; running: true
                command: ["bash", "-c", "xdg-icon-lookup --size 48 kitty 2>/dev/null || echo ''"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let p = this.text.trim();
                        barWindow.iconKitty = (p !== "") ? p : "";
                    }
                }
            }
            Process {
                id: iconResolverDolphin; running: true
                command: ["bash", "-c", "xdg-icon-lookup --size 48 org.kde.dolphin 2>/dev/null || echo ''"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let p = this.text.trim();
                        barWindow.iconDolphin = (p !== "") ? p : "";
                    }
                }
            }
            Process {
                id: iconResolverBrave; running: true
                command: ["bash", "-c", "xdg-icon-lookup --size 48 brave-desktop 2>/dev/null || echo ''"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let p = this.text.trim();
                        barWindow.iconBrave = (p !== "") ? p : "";
                    }
                }
            }
            Process {
                id: iconResolverTutanota; running: true
                command: ["bash", "-c", "xdg-icon-lookup --size 48 tutanota-desktop 2>/dev/null || xdg-icon-lookup --size 48 com.tutanota.Tutanota 2>/dev/null || echo ''"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let p = this.text.trim();
                        barWindow.iconTutanota = (p !== "") ? p : "";
                    }
                }
            }
            Process {
                id: iconResolverMaterialious; running: true
                command: ["bash", "-c", "xdg-icon-lookup --size 48 us.materialio.Materialious 2>/dev/null || echo '/usr/share/icons/hicolor/512x512/apps/us.materialio.Materialious.png'"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let p = this.text.trim();
                        barWindow.iconMaterialious = (p !== "") ? p : "";
                    }
                }
            }
            Process {
                id: iconResolverJellyfin; running: true
                command: ["bash", "-c", "xdg-icon-lookup --size 48 org.jellyfin.JellyfinDesktop 2>/dev/null || echo '/usr/share/icons/hicolor/scalable/apps/org.jellyfin.JellyfinDesktop.svg'"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let p = this.text.trim();
                        barWindow.iconJellyfin = (p !== "") ? p : "";
                    }
                }
            }
            Process {
                id: iconResolverNavidrome; running: true
                command: ["bash", "-c", "xdg-icon-lookup --size 48 org.jeffvli.feishin 2>/dev/null || xdg-icon-lookup --size 48 feishin 2>/dev/null || echo ''"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let p = this.text.trim();
                        barWindow.iconNavidrome = (p !== "") ? p : "";
                    }
                }
            }
            Process {
                id: iconResolverHeroic; running: true
                command: ["bash", "-c", "xdg-icon-lookup --size 48 com.heroicgameslauncher.hgl 2>/dev/null || xdg-icon-lookup --size 48 heroic 2>/dev/null || echo ''"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let p = this.text.trim();
                        barWindow.iconHeroic = (p !== "") ? p : "";
                    }
                }
            }
            Process {
                id: iconResolverSteam; running: true
                command: ["bash", "-c", "xdg-icon-lookup --size 48 steam 2>/dev/null || echo ''"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let p = this.text.trim();
                        barWindow.iconSteam = (p !== "") ? p : "";
                    }
                }
            }
            Process {
                id: iconResolverLutris; running: true
                command: ["bash", "-c", "xdg-icon-lookup --size 48 lutris 2>/dev/null || echo ''"]
                stdout: StdioCollector {
                    onStreamFinished: { let p = this.text.trim(); barWindow.iconLutris = (p !== "") ? p : ""; }
                }
            }
            Process {
                id: iconResolverBottles; running: true
                command: ["bash", "-c", "xdg-icon-lookup --size 48 com.usebottles.bottles 2>/dev/null || xdg-icon-lookup --size 48 bottles 2>/dev/null || echo ''"]
                stdout: StdioCollector {
                    onStreamFinished: { let p = this.text.trim(); barWindow.iconBottles = (p !== "") ? p : ""; }
                }
            }
            Process {
                id: iconResolverPrism; running: true
                command: ["bash", "-c", "xdg-icon-lookup --size 48 org.prismlauncher.PrismLauncher 2>/dev/null || xdg-icon-lookup --size 48 prismlauncher 2>/dev/null || echo ''"]
                stdout: StdioCollector {
                    onStreamFinished: { let p = this.text.trim(); barWindow.iconPrism = (p !== "") ? p : ""; }
                }
            }
            Process {
                id: iconResolverRetroarch; running: true
                command: ["bash", "-c", "xdg-icon-lookup --size 48 retroarch 2>/dev/null || xdg-icon-lookup --size 48 org.libretro.RetroArch 2>/dev/null || echo ''"]
                stdout: StdioCollector {
                    onStreamFinished: { let p = this.text.trim(); barWindow.iconRetroarch = (p !== "") ? p : ""; }
                }
            }
            Process {
                id: iconResolverMinigalaxy; running: true
                command: ["bash", "-c", "xdg-icon-lookup --size 48 io.github.sharkwouter.Minigalaxy 2>/dev/null || xdg-icon-lookup --size 48 minigalaxy 2>/dev/null || echo ''"]
                stdout: StdioCollector {
                    onStreamFinished: { let p = this.text.trim(); barWindow.iconMinigalaxy = (p !== "") ? p : ""; }
                }
            }
            Process {
                id: iconResolverElement; running: true
                command: ["bash", "-c", "xdg-icon-lookup --size 48 io.element.Element 2>/dev/null || echo '/usr/share/icons/hicolor/512x512/apps/io.element.Element.png'"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let p = this.text.trim();
                        barWindow.iconElement = (p !== "") ? p : "";
                    }
                }
            }

            // ─────────────────────────────────────────────
            // HYPRLAND CLIENTS POLLER (for dock)
            // ─────────────────────────────────────────────
            Process {
                id: clientsPoller
                command: ["bash", "-c", "hyprctl clients -j 2>/dev/null || echo '[]'"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            let parsed = JSON.parse(this.text.trim());
                            barWindow.hyprClients = parsed;
                        } catch(e) {}
                    }
                }
            }
            Process {
                id: clientsWatcher; running: true
                command: ["bash", "-c", "socat -u UNIX-CONNECT:/tmp/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock - | grep -m1 -E 'openwindow|closewindow|activewindow'"]
                onExited: {
                    clientsPoller.running = false;
                    clientsPoller.running = true;
                    running = false;
                    running = true;
                }
            }
            Timer {
                interval: 2000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: { clientsPoller.running = false; clientsPoller.running = true; }
            }

            // ─────────────────────────────────────────────
            // PREVIEW CAPTURE
            // ─────────────────────────────────────────────
            Process {
                id: previewCapture
                command: ["bash", "-c", "echo idle"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        barWindow.previewImageReady = false;
                        previewImage.source = "";
                        previewImage.source = "file://" + barWindow.previewTmpPath + "?" + Date.now();
                        barWindow.previewImageReady = true;
                    }
                }
            }

            // ─────────────────────────────────────────────
            // FLOAT STATE
            // ─────────────────────────────────────────────
            Timer {
                id: floatCooldownTimer; interval: 1500; repeat: false
                onTriggered: {
                    // Cooldown over — do one definitive read to sync state
                    barWindow.floatPollBlocked = false;
                    floatPoller.running = false;
                    floatPoller.running = true;
                }
            }
            Process {
                id: floatPoller
                command: ["bash", "-c", "hyprctl activewindow -j 2>/dev/null | jq -r '[.floating, .address] | @tsv' 2>/dev/null || echo 'false\t'"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        if (!barWindow.floatPollBlocked) {
                            let parts = this.text.trim().split("\t");
                            barWindow.currentWindowIsFloating = (parts[0] === "true");
                            if (parts.length > 1 && parts[1]) barWindow.activeWindowAddr = parts[1];
                        }
                    }
                }
            }
            // ── Fetch all windows on active workspace ──
            Process {
                id: wsWindowsFetcher
                command: ["bash", "-c",
                    "ACTIVE=$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty'); " +
                    "WS=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id'); " +
                    "echo $ACTIVE; " +
                    "hyprctl clients -j 2>/dev/null | jq -c --argjson ws ${WS:-1} " +
                    "'[.[] | select(.workspace.id == $ws) | {addr: .address, class: .class, title: .title, floating: .floating}]' 2>/dev/null || echo '[]'"
                ]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let lines = this.text.trim().split("\n");
                        if (lines.length < 2) return;
                        // First line = active window address
                        let activeAddr = lines[0].trim();
                        if (activeAddr) barWindow.activeWindowAddr = activeAddr;
                        // Second line = window list JSON
                        try {
                            let wins = JSON.parse(lines[1]);
                            while (wsWindows.count > wins.length) wsWindows.remove(wsWindows.count - 1);
                            while (wsWindows.count < wins.length) wsWindows.append({ wAddr: "", wClass: "", wTitle: "", wFloating: false });
                            for (let i = 0; i < wins.length; i++) {
                                wsWindows.setProperty(i, "wAddr", wins[i].addr || "");
                                wsWindows.setProperty(i, "wClass", wins[i].class || "");
                                wsWindows.setProperty(i, "wTitle", wins[i].title || "");
                                wsWindows.setProperty(i, "wFloating", wins[i].floating || false);
                            }
                        } catch(e) {}
                    }
                }
            }
            Timer { running: true; interval: 800; repeat: false; onTriggered: wsWindowsFetcher.running = true }

            // Only poll on focus change — debounced to avoid stutter
            Timer {
                id: floatDebounce; interval: 150; repeat: false
                onTriggered: {
                    if (!barWindow.floatPollBlocked) {
                        floatPoller.running = false;
                        floatPoller.running = true;
                    }
                    wsWindowsFetcher.running = false;
                    wsWindowsFetcher.running = true;
                }
            }
            Process {
                id: windowListWatcher; running: true
                command: ["bash", "-c", "socat -u UNIX-CONNECT:/tmp/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock - | grep -m1 -E 'openwindow|closewindow|movewindow'"]
                onExited: {
                    wsWindowsFetcher.running = false;
                    wsWindowsFetcher.running = true;
                    running = false;
                    running = true;
                }
            }
            Process {
                id: floatWatcher; running: true
                command: ["bash", "-c", "socat -u UNIX-CONNECT:/tmp/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock - | grep -m1 -E 'activewindow|changefloatingmode'"]
                onExited: {
                    floatDebounce.restart();
                    running = false;
                    running = true;
                }
            }

            // ─────────────────────────────────────────────
            // AI POPUP WATCHERS
            // ─────────────────────────────────────────────
            Timer {
                id: aiTypewriter; interval: 12; repeat: true
                running: barWindow.aiState === "ready" && barWindow.aiTypeLen < barWindow.aiResponse.length
                onTriggered: barWindow.aiTypeLen = Math.min(barWindow.aiTypeLen + 3, barWindow.aiResponse.length)
            }
            onAiResponseChanged: { aiTypeLen = 0; }

            Process {
                id: aiVisiblePoller
                command: ["bash", "-c", "cat /tmp/qs_ai_visible 2>/dev/null || echo '0'"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        barWindow.aiVisible = (this.text.trim() === "1");
                    }
                }
            }
            Process {
                id: aiVisibleWatcher; running: true
                command: ["bash", "-c", "inotifywait -qq -e modify,close_write /tmp/qs_ai_visible 2>/dev/null || sleep 60"]
                onExited: {
                    aiVisiblePoller.running = false; aiVisiblePoller.running = true;
                    running = false; running = true;
                }
            }
            Process {
                id: aiStatePoller
                command: ["bash", "-c", "cat /tmp/qs_ai_state 2>/dev/null || echo 'loading'"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let s = this.text.trim();
                        if (s !== barWindow.aiState) barWindow.aiState = s;
                        if (s === "ready") {
                            aiQueryReader.running = false; aiQueryReader.running = true;
                            aiResponseReader.running = false; aiResponseReader.running = true;
                        }
                    }
                }
            }
            Process {
                id: aiStateWatcher; running: true
                command: ["bash", "-c", "inotifywait -qq -e modify,close_write /tmp/qs_ai_state 2>/dev/null || sleep 60"]
                onExited: {
                    aiStatePoller.running = false; aiStatePoller.running = true;
                    running = false; running = true;
                }
            }
            Timer { interval: 500; running: true; repeat: true; onTriggered: { aiStatePoller.running = false; aiStatePoller.running = true; } }
            Process {
                id: aiQueryReader
                command: ["bash", "-c", "cat /tmp/qs_ai_query 2>/dev/null || echo ''"]
                stdout: StdioCollector { onStreamFinished: { barWindow.aiQuery = this.text.trim(); } }
            }
            Process {
                id: aiResponseReader
                command: ["bash", "-c", "cat /tmp/qs_ai_response 2>/dev/null || echo ''"]
                stdout: StdioCollector { onStreamFinished: { barWindow.aiResponse = this.text.trim(); } }
            }

            // ─────────────────────────────────────────────
            // FOCUS MODE WATCHER
            // ─────────────────────────────────────────────
            Process {
                id: focusModeReader; running: true
                command: ["bash", "-c", "cat ~/.cache/qs_focus_mode 2>/dev/null || echo 'default'"]
                stdout: StdioCollector {
                    onStreamFinished: { barWindow.focusMode = this.text.trim() || "default"; }
                }
            }
            Process {
                id: focusModeWatcher; running: true
                command: ["bash", "-c", "inotifywait -qq -e modify,close_write ~/.cache/qs_focus_mode 2>/dev/null || sleep 60"]
                onExited: {
                    focusModeReader.running = false; focusModeReader.running = true;
                    running = false; running = true;
                }
            }

            // ── Dock assignment state (shared with the app launcher) ──
            // The launcher writes ~/.cache/qs_dock_state.json when you right-click an app
            // and assign it. We read gaming[] / studyRemoved[] here and match by `cmd` so
            // those assignments drive which dock icons show per focus mode — same rules:
            //   gaming-assigned → hidden in default & study (gaming only)
            //   study-removed   → hidden in study
            property var dockGaming: []
            property var dockStudyRemoved: []
            Process {
                id: dockStateReader; running: true
                command: ["bash", "-c", "cat ~/.cache/qs_dock_state.json 2>/dev/null || echo '{}'"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            let d = JSON.parse(this.text);
                            barWindow.dockGaming = d.gaming || [];
                            barWindow.dockStudyRemoved = d.studyRemoved || [];
                        } catch(e) {}
                    }
                }
            }
            Process {
                id: dockStateWatcher; running: true
                command: ["bash", "-c", "inotifywait -qq -e modify,close_write ~/.cache/qs_dock_state.json 2>/dev/null || sleep 60"]
                onExited: {
                    dockStateReader.running = false; dockStateReader.running = true;
                    running = false; running = true;
                }
            }
            // True if this dock app (matched by cmd) is hidden in the current focus mode,
            // combining its static hideIn with the launcher's saved assignments.
            function dockAppHidden(modelData) {
                let cmd = modelData.cmd;
                // Static hideIn still applies.
                if (modelData.hideIn && modelData.hideIn.indexOf(barWindow.focusMode) >= 0) return true;
                // Gaming-assigned (from launcher): show only in gaming.
                for (let i = 0; i < barWindow.dockGaming.length; i++)
                    if (barWindow.dockGaming[i] === cmd && barWindow.focusMode !== "gaming") return true;
                // Study-removed (from launcher): hide in study.
                if (barWindow.focusMode === "study")
                    for (let j = 0; j < barWindow.dockStudyRemoved.length; j++)
                        if (barWindow.dockStudyRemoved[j] === cmd) return true;
                return false;
            }

            // ── Focus end epoch reader ──
            Process {
                id: focusEndReader; running: true
                command: ["bash", "-c", "cat ~/.cache/qs_focus_end 2>/dev/null || echo '0'"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let val = parseInt(this.text.trim()) || 0;
                        if (val !== barWindow.focusEndEpoch) {
                            barWindow.focusEndEpoch = val;
                            barWindow.focusWarned = false;
                        }
                    }
                }
            }
            Process {
                id: focusEndWatcher; running: true
                command: ["bash", "-c", "inotifywait -qq -e modify,close_write ~/.cache/qs_focus_end 2>/dev/null || sleep 60"]
                onExited: {
                    focusEndReader.running = false; focusEndReader.running = true;
                    running = false; running = true;
                }
            }

            // ── Notification dot tracker ──
            Process {
                id: notifDotWatcher; running: true
                command: ["bash", "-c",
                    "dbus-monitor --session \"member='Notify',interface='org.freedesktop.Notifications'\" 2>/dev/null | " +
                    "while read -r line; do " +
                    "  if echo \"$line\" | grep -q 'member=Notify'; then " +
                    "    echo 1 > /tmp/qs_bell_dot; " +
                    "  fi; " +
                    "done"
                ]
            }
            Process {
                id: bellDotReader; running: true
                command: ["bash", "-c", "cat /tmp/qs_bell_dot 2>/dev/null || echo 0"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        barWindow.hasNotifications = this.text.trim() === "1";
                    }
                }
            }
            Process {
                id: bellDotWatcher; running: true
                command: ["bash", "-c", "touch /tmp/qs_bell_dot; inotifywait -qq -e modify,close_write /tmp/qs_bell_dot 2>/dev/null || sleep 60"]
                onExited: {
                    bellDotReader.running = false; bellDotReader.running = true;
                    running = false; running = true;
                }
            }

            // ── Universal focus countdown (always running) ──
            Timer {
                id: focusCountdownTimer
                interval: 1000; repeat: true
                running: barWindow.focusMode !== "default" && barWindow.focusEndEpoch > 0
                onTriggered: {
                    let now = Math.floor(Date.now() / 1000);
                    barWindow.focusRemainSec = Math.max(0, barWindow.focusEndEpoch - now);

                    // 5-minute warning for study mode (only once)
                    if (barWindow.focusMode === "study" && !barWindow.focusWarned
                        && barWindow.focusRemainSec <= 300 && barWindow.focusRemainSec > 0) {
                        barWindow.focusWarned = true;
                        Quickshell.execDetached(["bash", "-c",
                            "~/.config/hypr/scripts/qs_manager.sh toggle focuswarn"
                        ]);
                    }

                    // Timer expired — switch back to default
                    if (barWindow.focusRemainSec <= 0) {
                        barWindow.focusMode = "default";
                        barWindow.focusEndEpoch = 0;
                        barWindow.focusWarned = false;
                        Quickshell.execDetached(["bash", "-c",
                            "echo default > ~/.cache/qs_focus_mode; echo 0 > ~/.cache/qs_focus_end; " +
                            "notify-send -u critical 'Focus Mode' 'Time is up! Switched back to Default.'"
                        ]);
                        // Re-read to sync
                        focusModeReader.running = false; focusModeReader.running = true;
                    }
                }
            }

            // ─────────────────────────────────────────────
            // RECORDING / UPDATE POLLERS
            // ─────────────────────────────────────────────
            Process {
                id: recPoller
                command: ["bash", "-c", "pgrep -x wl-screenrec >/dev/null && echo '1' || echo '0'"]
                stdout: StdioCollector {
                    onStreamFinished: { barWindow.isRecording = (this.text.trim() === "1"); }
                }
            }
            Timer {
                interval: 500; running: true; repeat: true
                onTriggered: { recPoller.running = false; recPoller.running = true; }
            }
            Process {
                id: updatePoller
                command: ["bash", "-c", "if [ -f ~/.cache/qs_update_pending ]; then echo '1'; else echo '0'; fi"]
                stdout: StdioCollector {
                    onStreamFinished: { barWindow.updateAvailable = (this.text.trim() === "1"); }
                }
            }
            Timer {
                interval: 2000; running: true; repeat: true
                onTriggered: { updatePoller.running = false; updatePoller.running = true; }
            }

            // ─────────────────────────────────────────────
            // SETTINGS WATCHER
            // ─────────────────────────────────────────────
            Process {
                id: settingsReader; running: true
                command: ["bash", "-c", "cat ~/.config/hypr/settings.json 2>/dev/null || echo '{}'"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            if (this.text && this.text.trim().length > 0 && this.text.trim() !== "{}") {
                                let parsed = JSON.parse(this.text);
                                if (parsed.workspaceCount !== undefined && barWindow.workspaceCount !== parsed.workspaceCount) {
                                    barWindow.workspaceCount = parsed.workspaceCount;
                                    wsDaemon.running = false;
                                    wsDaemon.running = true;
                                }
                            }
                        } catch(e) {}
                    }
                }
            }
            Process {
                id: settingsWatcher; running: true
                command: ["bash", "-c", "while [ ! -f ~/.config/hypr/settings.json ]; do sleep 1; done; inotifywait -qq -e modify,close_write ~/.config/hypr/settings.json"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        settingsReader.running = false; settingsReader.running = true;
                        settingsWatcher.running = false; settingsWatcher.running = true;
                    }
                }
            }

            // ─────────────────────────────────────────────
            // CHASSIS DETECTION
            // ─────────────────────────────────────────────
            Process {
                id: chassisDetector; running: true
                command: ["bash", "-c", "if ls /sys/class/power_supply/BAT* 1>/dev/null 2>&1; then echo 'laptop'; else echo 'desktop'; fi"]
                stdout: StdioCollector {
                    onStreamFinished: { barWindow.isDesktop = (this.text.trim() === "desktop"); }
                }
            }

            // ─────────────────────────────────────────────
            // WORKSPACES
            // ─────────────────────────────────────────────
            Process { id: wsDaemon; command: ["bash", "-c", "~/.config/hypr/scripts/workspaces.sh"]; running: true }
            Process {
                id: wsReader
                command: ["cat", "/tmp/qs_workspaces.json"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt === "") return;
                        try {
                            let d = JSON.parse(txt);
                            while (workspacesModel.count < d.length) workspacesModel.append({ "wsId": "", "wsState": "" });
                            while (workspacesModel.count > d.length) workspacesModel.remove(workspacesModel.count - 1);
                            for (let i = 0; i < d.length; i++) {
                                if (workspacesModel.get(i).wsState !== d[i].state) workspacesModel.setProperty(i, "wsState", d[i].state);
                                if (workspacesModel.get(i).wsId !== d[i].id.toString()) workspacesModel.setProperty(i, "wsId", d[i].id.toString());
                            }
                        } catch(e) {}
                    }
                }
            }
            Process {
                id: wsWatcher; running: true
                command: ["bash", "-c", "inotifywait -qq -e close_write,modify /tmp/qs_workspaces.json"]
                onExited: { wsReader.running = false; wsReader.running = true; wsWindowsFetcher.running = false; wsWindowsFetcher.running = true; running = false; running = true; }
            }

            // ─────────────────────────────────────────────
            // MUSIC
            // ─────────────────────────────────────────────
            Process {
                id: musicForceRefresh; running: true
                command: ["bash", "-c", "bash ~/.config/hypr/scripts/quickshell/music/music_info.sh | tee /tmp/music_info.json"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let txt = this.text.trim();
                        if (txt !== "") { try { barWindow.musicData = JSON.parse(txt); } catch(e) {} }
                    }
                }
            }
            Timer {
                interval: 1000; running: true; repeat: true
                onTriggered: {
                    if (!barWindow.musicData || barWindow.musicData.status !== "Playing") return;
                    if (!barWindow.musicData.timeStr || barWindow.musicData.timeStr === "") return;
                    let parts = barWindow.musicData.timeStr.split(" / ");
                    if (parts.length !== 2) return;
                    let pp = parts[0].split(":").map(Number);
                    let lp = parts[1].split(":").map(Number);
                    let pos = (pp.length === 3) ? (pp[0]*3600+pp[1]*60+pp[2]) : (pp[0]*60+pp[1]);
                    let len = (lp.length === 3) ? (lp[0]*3600+lp[1]*60+lp[2]) : (lp[0]*60+lp[1]);
                    if (isNaN(pos) || isNaN(len)) return;
                    pos++; if (pos > len) pos = len;
                    let ps = "";
                    if (pp.length === 3) {
                        let h=Math.floor(pos/3600),m=Math.floor((pos%3600)/60),s=pos%60;
                        ps=h+":"+(m<10?"0":"")+m+":"+(s<10?"0":"")+s;
                    } else {
                        let m=Math.floor(pos/60),s=pos%60;
                        ps=(m<10?"0":"")+m+":"+(s<10?"0":"")+s;
                    }
                    let nd = Object.assign({}, barWindow.musicData);
                    nd.timeStr = ps + " / " + parts[1];
                    nd.positionStr = ps;
                    if (len > 0) nd.percent = (pos/len)*100;
                    barWindow.musicData = nd;
                }
            }
            Process {
                id: mprisWatcher; running: true
                command: ["bash", "-c", "dbus-monitor --session \"type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.mpris.MediaPlayer2.Player'\" \"type='signal',interface='org.mpris.MediaPlayer2.Player',member='Seeked'\" 2>/dev/null | grep -m1 'member=' >/dev/null || sleep 2"]
                onExited: { musicForceRefresh.running = false; musicForceRefresh.running = true; running = false; running = true; }
            }

            // ─────────────────────────────────────────────
            // SYSTEM WATCHERS
            // ─────────────────────────────────────────────
            Process {
                id: kbPoller; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/kb_fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let t = this.text.trim();
                        if (t !== "" && barWindow.kbLayout !== t) barWindow.kbLayout = t;
                        kbWaiter.running = false; kbWaiter.running = true;
                        barWindow.fastPollerLoaded = true;
                    }
                }
            }
            Process { id: kbWaiter; command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/kb_wait.sh"]; onExited: { kbPoller.running = false; kbPoller.running = true; } }

            Process {
                id: audioPoller; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/audio_fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let t = this.text.trim();
                        if (t !== "") {
                            try {
                                let d = JSON.parse(t);
                                let nv = d.volume.toString() + "%";
                                if (barWindow.volPercent !== nv) barWindow.volPercent = nv;
                                if (barWindow.volIcon !== d.icon) barWindow.volIcon = d.icon;
                                let nm = (d.is_muted === "true");
                                if (barWindow.isMuted !== nm) barWindow.isMuted = nm;
                            } catch(e) {}
                        }
                        audioWaiter.running = false; audioWaiter.running = true;
                    }
                }
            }
            Process { id: audioWaiter; command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/audio_wait.sh"]; onExited: { audioPoller.running = false; audioPoller.running = true; } }

            Process {
                id: networkPoller; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/network_fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let t = this.text.trim();
                        if (t !== "") {
                            try {
                                let d = JSON.parse(t);
                                if (barWindow.wifiStatus !== d.status) barWindow.wifiStatus = d.status;
                                if (barWindow.wifiIcon !== d.icon) barWindow.wifiIcon = d.icon;
                                if (barWindow.wifiSsid !== d.ssid) barWindow.wifiSsid = d.ssid;
                                if (barWindow.ethStatus !== d.eth_status) barWindow.ethStatus = d.eth_status;
                            } catch(e) {}
                        }
                        networkWaiter.running = false; networkWaiter.running = true;
                    }
                }
            }
            Process { id: networkWaiter; command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/network_wait.sh"]; onExited: { networkPoller.running = false; networkPoller.running = true; } }

            Process {
                id: btPoller; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/bt_fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let t = this.text.trim();
                        if (t !== "") {
                            try {
                                let d = JSON.parse(t);
                                if (barWindow.btStatus !== d.status) barWindow.btStatus = d.status;
                                if (barWindow.btIcon !== d.icon) barWindow.btIcon = d.icon;
                                if (barWindow.btDevice !== d.connected) barWindow.btDevice = d.connected;
                            } catch(e) {}
                        }
                        btWaiter.running = false; btWaiter.running = true;
                    }
                }
            }
            Process { id: btWaiter; command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/bt_wait.sh"]; onExited: { btPoller.running = false; btPoller.running = true; } }

            Process {
                id: batteryPoller; running: true
                command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/battery_fetch.sh"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let t = this.text.trim();
                        if (t !== "") {
                            try {
                                let d = JSON.parse(t);
                                let nb = d.percent.toString() + "%";
                                if (barWindow.batPercent !== nb) barWindow.batPercent = nb;
                                if (barWindow.batIcon !== d.icon) barWindow.batIcon = d.icon;
                                if (barWindow.batStatus !== d.status) barWindow.batStatus = d.status;
                            } catch(e) {}
                        }
                        batteryWaiter.running = false; batteryWaiter.running = true;
                    }
                }
            }
            Process { id: batteryWaiter; command: ["bash", "-c", "~/.config/hypr/scripts/quickshell/watchers/battery_wait.sh"]; onExited: { batteryPoller.running = false; batteryPoller.running = true; } }

            Process {
                id: weatherPoller
                command: ["bash", "-c", `
                    echo "$(~/.config/hypr/scripts/quickshell/calendar/weather.sh --current-icon)"
                    echo "$(~/.config/hypr/scripts/quickshell/calendar/weather.sh --current-temp)"
                    echo "$(~/.config/hypr/scripts/quickshell/calendar/weather.sh --current-hex)"
                `]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let lines = this.text.trim().split("\n");
                        if (lines.length >= 3) {
                            barWindow.weatherIcon = lines[0];
                            barWindow.weatherTemp = lines[1];
                            barWindow.weatherHex = lines[2] || mocha.yellow;
                        }
                    }
                }
            }
            Timer { interval: 150000; running: true; repeat: true; triggeredOnStart: true; onTriggered: { weatherPoller.running = false; weatherPoller.running = true; } }

            Timer {
                interval: 1000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: {
                    let d = new Date();
                    barWindow.timeStr = Qt.formatDateTime(d, "HH:mm:ss");
                    barWindow.fullDateStr = Qt.formatDateTime(d, "dddd, MMMM dd");
                    if (barWindow.typeInIndex >= barWindow.fullDateStr.length)
                        barWindow.typeInIndex = barWindow.fullDateStr.length;
                }
            }
            Timer {
                id: typewriterTimer; interval: 40
                running: barWindow.isStartupReady && barWindow.typeInIndex < barWindow.fullDateStr.length
                repeat: true
                onTriggered: barWindow.typeInIndex += 1
            }

            // =====================================================
            // UI LAYOUT
            // =====================================================
            Item {
                anchors.fill: parent

                // ── LEFT: AI button + Dock ──
                Row {
                    id: leftBar
                    y: (parent.height - barWindow.barHeight) / 2
                    spacing: barWindow.s(4)
                    property bool showLayout: false
                    opacity: showLayout ? 1 : 0
                    x: showLayout ? 0 : barWindow.s(-300)
                    Behavior on x { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                    Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    Timer { running: barWindow.isStartupReady; interval: 10; onTriggered: leftBar.showLayout = true }

                    // AI Button
                    Rectangle {
                        id: aiBtn
                        property bool isHovered: aiMouse.containsMouse
                        color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.95) : Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)
                        radius: barWindow.s(14); border.width: 1
                        border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, isHovered ? 0.15 : 0.05)
                        height: barWindow.barHeight; width: barWindow.barHeight
                        Behavior on color { ColorAnimation { duration: 200 } }
                        scale: isHovered ? 1.05 : 1.0
                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }

                        property real glowOpacity: 0.0
                        SequentialAnimation on glowOpacity {
                            running: !aiBtn.isHovered; loops: Animation.Infinite
                            NumberAnimation { to: 0.55; duration: 2200; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 0.0;  duration: 2200; easing.type: Easing.InOutSine }
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width + barWindow.s(4); height: parent.height + barWindow.s(4)
                            radius: parent.radius + barWindow.s(2); color: "transparent"; border.width: 1
                            border.color: Qt.rgba(mocha.mauve.r, mocha.mauve.g, mocha.mauve.b, aiBtn.glowOpacity)
                        }
                        Text {
                            anchors.centerIn: parent; text: "󰣇"
                            font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(26)
                            color: aiBtn.isHovered ? mocha.mauve : mocha.subtext0
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        MouseArea {
                            id: aiMouse; anchors.fill: parent; hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                            onClicked: function(mouse) {
                                mouse.accepted = true;
                                if (mouse.button === Qt.MiddleButton) {
                                    Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle clipboard"]);
                                } else if (mouse.button === Qt.RightButton) {
                                    Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle tools"]);
                                } else {
                                    Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle applauncher"]);
                                }
                            }
                        }
                    }

                    // Dock
                    Rectangle {
                        id: dockBox
                        color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)
                        radius: barWindow.s(14); border.width: 1
                        border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                        // Height accounts for icon + dot indicator below
                        height: barWindow.barHeight
                        width: dockRow.implicitWidth + barWindow.s(20)
                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
                        clip: false

                        // hideIn: comma-separated modes where the app is hidden
                        // "" = always visible, "default,study" = only visible in gaming
                        readonly property var dockApps: [
                            { srcProp: "iconKitty",        fallback: "kitty",                          cmd: "kitty",            classes: ["kitty"],                                              hideIn: "" },
                            { srcProp: "iconDolphin",      fallback: "org.kde.dolphin",                cmd: "dolphin",          classes: ["dolphin", "org.kde.dolphin"],                          hideIn: "" },
                            { srcProp: "iconTutanota",     fallback: "tutanota-desktop",               cmd: "tutanota-desktop", classes: ["tutanota", "tutanota-desktop", "com.tutanota.tutanota"], hideIn: "" },
                            { srcProp: "iconBrave",        fallback: "brave-desktop",                  cmd: "brave",            classes: ["brave-browser", "brave"],                              hideIn: "" },
                            { srcProp: "iconMaterialious", fallback: "us.materialio.Materialious",     cmd: "materiious",       classes: ["materiious", "com.github.materiious"],                 hideIn: "" },
                            { srcProp: "iconJellyfin",     fallback: "org.jellyfin.JellyfinDesktop",   cmd: "jellyfin-desktop", classes: ["jellyfin-desktop", "jellyfin", "jellyfin-media-player"], hideIn: "study" },
                            { srcProp: "iconNavidrome",    fallback: "org.jeffvli.feishin",            cmd: "feishin",          classes: ["feishin", "navidrome"],                                hideIn: "" },
                            { srcProp: "iconSteam",        fallback: "steam",                          cmd: "steam",            classes: ["steam"],                                              hideIn: "default,study" },
                            { srcProp: "iconHeroic",       fallback: "com.heroicgameslauncher.hgl",  cmd: "heroic",           classes: ["heroic", "com.heroicgameslauncher.hgl"],              hideIn: "default,study" },
                            { srcProp: "iconLutris",       fallback: "lutris",                         cmd: "lutris",           classes: ["lutris"],                                             hideIn: "default,study" },
                            { srcProp: "iconBottles",      fallback: "com.usebottles.bottles",         cmd: "bottles",          classes: ["bottles", "com.usebottles.bottles"],                   hideIn: "default,study" },
                            { srcProp: "iconPrism",        fallback: "org.prismlauncher.PrismLauncher", cmd: "prismlauncher",   classes: ["prismlauncher", "org.prismlauncher.PrismLauncher"],     hideIn: "default,study" },
                            { srcProp: "iconRetroarch",    fallback: "retroarch",                      cmd: "retroarch",        classes: ["retroarch", "org.libretro.RetroArch"],                 hideIn: "default,study" },
                            { srcProp: "iconMinigalaxy",   fallback: "io.github.sharkwouter.Minigalaxy", cmd: "minigalaxy",    classes: ["minigalaxy"],                                          hideIn: "default,study" },
                            { srcProp: "iconElement",      fallback: "element-desktop",                cmd: "element-desktop",  classes: ["element", "element-desktop", "im.riot.riot"],          hideIn: "" }
                        ]

                        Row {
                            id: dockRow
                            anchors.centerIn: parent
                            spacing: barWindow.s(6)

                            Repeater {
                                model: dockBox.dockApps
                                delegate: Item {
                                    id: dockItemWrapper
                                    // Hidden if its static hideIn OR a launcher assignment
                                    // (gaming-only / study-removed) hides it in this mode.
                                    property bool isHidden: barWindow.dockAppHidden(modelData)
                                    visible: !isHidden
                                    width: visible ? barWindow.s(36) : 0
                                    height: visible ? barWindow.s(40) : 0
                                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

                                    property var appClients: barWindow.clientsForApp(modelData.classes)
                                    property int windowCount: appClients.length
                                    property bool hasWindows: windowCount > 0
                                    property bool isHovered: dockMouse.containsMouse

                                    property bool initAnimTrigger: false
                                    opacity: initAnimTrigger ? 1 : 0
                                    transform: Translate {
                                        y: dockItemWrapper.initAnimTrigger ? 0 : barWindow.s(15)
                                        Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }
                                    }
                                    Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

                                    Timer {
                                        running: leftBar.showLayout && !dockItemWrapper.initAnimTrigger
                                        interval: 60 + index * 60
                                        onTriggered: dockItemWrapper.initAnimTrigger = true
                                    }

                                    // Icon background pill
                                    Rectangle {
                                        id: dockIconBg
                                        anchors.top: parent.top
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: barWindow.s(36); height: barWindow.s(32)
                                        radius: barWindow.s(10)
                                        color: dockItemWrapper.isHovered
                                            ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.9)
                                            : (dockItemWrapper.hasWindows
                                                ? Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.45)
                                                : "transparent")
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                        scale: dockItemWrapper.isHovered ? 1.12 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                                        Image {
                                            id: dockIconImage
                                            anchors.centerIn: parent
                                            width: barWindow.s(22); height: barWindow.s(22)
                                            source: barWindow.iconSource(barWindow[modelData.srcProp], modelData.fallback)
                                            fillMode: Image.PreserveAspectFit; smooth: true
                                            // Guard against infinite fallback loops. If the freedesktop
                                            // icon provider also fails, we just leave the Image empty
                                            // rather than re-firing onStatusChanged which can crash
                                            // Quickshell-git on some Qt 6.11 builds.
                                            property bool fallbackTried: false
                                            onStatusChanged: {
                                                if (status === Image.Error && !fallbackTried) {
                                                    fallbackTried = true;
                                                    source = "image://icon/" + modelData.fallback;
                                                } else if (status === Image.Error && fallbackTried) {
                                                    // Already tried fallback; give up silently.
                                                    source = "";
                                                }
                                            }
                                        }
                                    }

                                    // Open window dots (1 per window, max 4)
                                    Row {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        spacing: barWindow.s(3)
                                        visible: dockItemWrapper.hasWindows
                                        Repeater {
                                            model: Math.min(dockItemWrapper.windowCount, 4)
                                            delegate: Rectangle {
                                                width: barWindow.s(4); height: barWindow.s(4)
                                                radius: width / 2
                                                color: mocha.mauve; opacity: 0.85
                                            }
                                        }
                                    }

                                    // Hover → show preview after 400ms
                                    Timer {
                                        id: previewHoverTimer; interval: 400; repeat: false
                                        running: dockItemWrapper.isHovered && dockItemWrapper.hasWindows
                                        onTriggered: {
                                            if (!dockItemWrapper.isHovered || !dockItemWrapper.hasWindows) return;
                                            barWindow.previewDockIndex = index;
                                            let clients = dockItemWrapper.appClients;
                                            let last = clients[clients.length - 1];
                                            barWindow.previewTitle = last.title || modelData.fallback;
                                            barWindow.capturePreview(last);
                                        }
                                    }

                                    onIsHoveredChanged: {
                                        if (!isHovered && barWindow.previewDockIndex === index)
                                            barWindow.previewDockIndex = -1;
                                    }

                                    MouseArea {
                                        id: dockMouse; anchors.fill: parent; hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        onClicked: function(mouse) {
                                            let clients = dockItemWrapper.appClients;
                                            if (mouse.button === Qt.RightButton) {
                                                // Right click: close most recent window
                                                if (clients.length > 0) {
                                                    let addr = clients[clients.length - 1].address;
                                                    Quickshell.execDetached(["bash", "-c",
                                                        "hyprctl dispatch closewindow address:" + addr
                                                    ]);
                                                }
                                            } else {
                                                // Left click: always launch a new instance
                                                Quickshell.execDetached(["bash", "-c", modelData.cmd]);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── MEDIA PLAYER ──
                Rectangle {
                    id: mediaBox
                    color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)
                    radius: barWindow.s(14); border.width: 1; border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                    y: (parent.height - barWindow.barHeight) / 2
                    height: barWindow.barHeight; clip: true
                    property real targetWidth: barWindow.isMediaActive ? mediaLayoutContainer.width + barWindow.s(24) : 0
                    x: leftBar.x + leftBar.width + barWindow.s(8)
                    Behavior on x { enabled: barWindow.startupCascadeFinished; NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                    width: targetWidth
                    visible: targetWidth > 0 || opacity > 0
                    opacity: barWindow.isMediaActive ? 1.0 : 0.0
                    Behavior on width { NumberAnimation { duration: 700; easing.type: Easing.OutQuint } }
                    Behavior on opacity { NumberAnimation { duration: 400 } }

                    Item {
                        id: mediaLayoutContainer
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left; anchors.leftMargin: barWindow.s(12)
                        height: parent.height; width: innerMediaLayout.width
                        opacity: barWindow.isMediaActive ? 1.0 : 0.0
                        transform: Translate { x: barWindow.isMediaActive ? 0 : barWindow.s(-20); Behavior on x { NumberAnimation { duration: 700; easing.type: Easing.OutQuint } } }
                        Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

                        Row {
                            id: innerMediaLayout
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: barWindow.width < 1920 ? barWindow.s(8) : barWindow.s(16)

                            MouseArea {
                                id: mediaInfoMouse; width: infoLayout.width; height: innerMediaLayout.height; hoverEnabled: true
                                onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle music"])
                                Row {
                                    id: infoLayout; anchors.verticalCenter: parent.verticalCenter; spacing: barWindow.s(10)
                                    scale: mediaInfoMouse.containsMouse ? 1.02 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                    Rectangle {
                                        width: barWindow.s(32); height: barWindow.s(32); radius: barWindow.s(8); color: mocha.surface1
                                        border.width: barWindow.musicData.status === "Playing" ? 1 : 0; border.color: mocha.mauve; clip: true
                                        Image { anchors.fill: parent; source: barWindow.musicData.artUrl || ""; fillMode: Image.PreserveAspectCrop }
                                        Rectangle { anchors.fill: parent; color: Qt.rgba(mocha.mauve.r, mocha.mauve.g, mocha.mauve.b, 0.2) }
                                    }
                                    Column {
                                        spacing: -2; anchors.verticalCenter: parent.verticalCenter
                                        width: barWindow.width < 1920 ? barWindow.s(120) : barWindow.s(180)
                                        Text { text: barWindow.musicData.title; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: barWindow.s(13); color: mocha.text; width: parent.width; elide: Text.ElideRight }
                                        Text { text: barWindow.musicData.timeStr; font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: barWindow.s(10); color: mocha.subtext0; width: parent.width; elide: Text.ElideRight }
                                    }
                                }
                            }

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: barWindow.width < 1920 ? barWindow.s(4) : barWindow.s(8)
                                Item { width: barWindow.s(24); height: barWindow.s(24); anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        anchors.centerIn: parent; text: "󰒮"
                                        font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(26)
                                        color: prevMouse.containsMouse ? mocha.text : mocha.overlay2
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        scale: prevMouse.containsMouse ? 1.1 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { id: prevMouse; hoverEnabled: true; anchors.fill: parent; onClicked: { Quickshell.execDetached(["playerctl", "previous"]); musicForceRefresh.running = true; } }
                                }
                                Item { width: barWindow.s(28); height: barWindow.s(28); anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        anchors.centerIn: parent
                                        text: barWindow.musicData.status === "Playing" ? "󰏤" : "󰐊"
                                        font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(30)
                                        color: playMouse.containsMouse ? mocha.green : mocha.text
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        scale: playMouse.containsMouse ? 1.15 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { id: playMouse; hoverEnabled: true; anchors.fill: parent; onClicked: { Quickshell.execDetached(["playerctl", "play-pause"]); musicForceRefresh.running = true; } }
                                }
                                Item { width: barWindow.s(24); height: barWindow.s(24); anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        anchors.centerIn: parent; text: "󰒭"
                                        font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(26)
                                        color: nextMouse.containsMouse ? mocha.text : mocha.overlay2
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        scale: nextMouse.containsMouse ? 1.1 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea { id: nextMouse; hoverEnabled: true; anchors.fill: parent; onClicked: { Quickshell.execDetached(["playerctl", "next"]); musicForceRefresh.running = true; } }
                                }
                            }
                        }
                    }
                }

                // ── CENTER BOX: [Search] [Clock] [Weather] [Clipboard] ──
                Rectangle {
                    id: centerBox
                    property bool isHovered: centerMouse.containsMouse
                    color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.95) : Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)
                    radius: barWindow.s(14); border.width: 1; border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, isHovered ? 0.15 : 0.05)
                    y: (parent.height - barWindow.barHeight) / 2; height: barWindow.barHeight

                    property real targetWidth: centerLayout.implicitWidth + barWindow.s(36)
                    width: targetWidth
                    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }

                    property real pureCenter: (parent.width - targetWidth) / 2
                    property real minDefaultX: mediaBox.x + mediaBox.targetWidth + (mediaBox.targetWidth > 0 ? barWindow.s(8) : 0)
                    x: Math.max(minDefaultX, pureCenter)
                    Behavior on x { enabled: barWindow.startupCascadeFinished; NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }

                    property bool showLayout: false
                    opacity: showLayout ? 1 : 0
                    transform: Translate {
                        y: centerBox.showLayout ? 0 : barWindow.s(-30)
                        Behavior on y { NumberAnimation { duration: 800; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
                    }
                    Timer { running: barWindow.isStartupReady; interval: 150; onTriggered: centerBox.showLayout = true }
                    Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                    scale: isHovered ? 1.03 : 1.0
                    Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }
                    Behavior on color { ColorAnimation { duration: 250 } }

                    MouseArea {
                        id: centerMouse; anchors.fill: parent; hoverEnabled: true
                        onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle calendar"])
                    }

                    RowLayout {
                        id: centerLayout; anchors.centerIn: parent; spacing: barWindow.s(16)

                        // Matrix chat (moved to the left side of the center section)
                        Rectangle {
                            id: matrixBtn; property bool isHovered: matrixMouse.containsMouse
                            color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : "transparent"
                            radius: barWindow.s(10)
                            Layout.preferredWidth: barWindow.s(32); Layout.preferredHeight: barWindow.s(32)
                            Behavior on color { ColorAnimation { duration: 200 } }
                            scale: isHovered ? 1.1 : 1.0; Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                            Text { anchors.centerIn: parent; text: "󰸿"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(20); color: matrixBtn.isHovered ? mocha.mauve : mocha.subtext0; Behavior on color { ColorAnimation { duration: 200 } } }
                            MouseArea { id: matrixMouse; anchors.fill: parent; hoverEnabled: true; onClicked: function(m) { m.accepted = true; Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle matrix"]); } }
                        }

                        // Clock
                        Item {
                            Layout.preferredWidth: clockCol.implicitWidth
                            Layout.preferredHeight: clockCol.implicitHeight
                            ColumnLayout {
                                id: clockCol; anchors.fill: parent
                                spacing: -2
                                Text { text: barWindow.timeStr; Layout.alignment: Qt.AlignHCenter; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(16); font.weight: Font.Black; color: mocha.blue }
                                Text { text: barWindow.dateStr; Layout.alignment: Qt.AlignHCenter; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(11); font.weight: Font.Bold; color: mocha.subtext0 }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle calendar"]) }
                        }

                        // Weather
                        Item {
                            Layout.preferredWidth: weatherRow.implicitWidth
                            Layout.preferredHeight: weatherRow.implicitHeight
                            RowLayout {
                                id: weatherRow; anchors.fill: parent
                                spacing: barWindow.s(8)
                                Text { text: barWindow.weatherIcon; Layout.alignment: Qt.AlignVCenter; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(24); color: Qt.tint(barWindow.weatherHex, Qt.rgba(mocha.mauve.r, mocha.mauve.g, mocha.mauve.b, 0.4)) }
                                Text { text: barWindow.weatherTemp; Layout.alignment: Qt.AlignVCenter; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(17); font.weight: Font.Black; color: mocha.peach }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle calendar"]) }
                        }

                        // Clipboard
                        Rectangle {
                            id: clipBtn; property bool isHovered: clipMouse.containsMouse
                            color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : "transparent"
                            radius: barWindow.s(10)
                            Layout.preferredWidth: barWindow.s(32); Layout.preferredHeight: barWindow.s(32)
                            Behavior on color { ColorAnimation { duration: 200 } }
                            scale: isHovered ? 1.1 : 1.0; Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                            Text { anchors.centerIn: parent; text: "󱌾"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(20); color: clipBtn.isHovered ? mocha.green : mocha.subtext0; Behavior on color { ColorAnimation { duration: 200 } } }
                            MouseArea { id: clipMouse; anchors.fill: parent; hoverEnabled: true; onClicked: function(m) { m.accepted = true; Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle library"]); } }
                        }
                    }
                }

                // ── RIGHT CONTENT ──
                Row {
                    id: rightContent
                    anchors.right: parent.right
                    y: (parent.height - barWindow.barHeight) / 2
                    spacing: barWindow.s(4)
                    property bool showLayout: false
                    opacity: showLayout ? 1 : 0
                    transform: Translate {
                        x: rightContent.showLayout ? 0 : barWindow.s(30)
                        Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
                    }
                    Timer { running: barWindow.isStartupReady && barWindow.isDataReady; interval: 250; onTriggered: rightContent.showLayout = true }
                    Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }


                    // System tray
                    Rectangle {
                        height: barWindow.barHeight; radius: barWindow.s(14)
                        border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.08); border.width: 1
                        color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75); anchors.verticalCenter: parent.verticalCenter
                        property real targetWidth: trayRepeater.count > 0 ? trayRow.width + barWindow.s(24) : 0
                        width: targetWidth; Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
                        visible: targetWidth > 0; opacity: targetWidth > 0 ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 300 } }

                        Row {
                            id: trayRow; anchors.centerIn: parent; spacing: barWindow.s(10)
                            Repeater {
                                id: trayRepeater; model: SystemTray.items
                                delegate: Image {
                                    id: trayIcon; source: modelData.icon || ""; fillMode: Image.PreserveAspectFit
                                    sourceSize: Qt.size(barWindow.s(18), barWindow.s(18)); width: barWindow.s(18); height: barWindow.s(18); anchors.verticalCenter: parent.verticalCenter
                                    property bool isHovered: trayMouse.containsMouse
                                    property bool initAnimTrigger: false
                                    opacity: initAnimTrigger ? (isHovered ? 1.0 : 0.8) : 0.0
                                    scale: initAnimTrigger ? (isHovered ? 1.15 : 1.0) : 0.0
                                    Component.onCompleted: { if (!barWindow.startupCascadeFinished) { trayTimer.interval = index * 50; trayTimer.start(); } else { initAnimTrigger = true; } }
                                    Timer { id: trayTimer; running: false; repeat: false; onTriggered: trayIcon.initAnimTrigger = true }
                                    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                                    QsMenuAnchor { id: trayMenu; anchor.window: barWindow; anchor.item: trayIcon; menu: modelData.menu }
                                    MouseArea {
                                        id: trayMouse; anchors.fill: parent; hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                        onClicked: function(m) {
                                            if (m.button === Qt.LeftButton) {
                                                if (modelData.isMenuOnly || modelData.onlyMenu) trayMenu.open();
                                                else if (typeof modelData.activate === "function") modelData.activate();
                                            } else if (m.button === Qt.MiddleButton) {
                                                if (typeof modelData.secondaryActivate === "function") modelData.secondaryActivate();
                                            } else {
                                                if (modelData.menu) trayMenu.open();
                                                else if (typeof modelData.contextMenu === "function") modelData.contextMenu(m.x, m.y);
                                                else modelData.activate();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // System pills
                    Rectangle {
                        height: barWindow.barHeight; radius: barWindow.s(14)
                        border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.08); border.width: 1
                        color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75); anchors.verticalCenter: parent.verticalCenter; clip: true
                        property real targetWidth: sysRow.width + barWindow.s(20)
                        width: targetWidth; Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }

                        Row {
                            id: sysRow; anchors.centerIn: parent; spacing: barWindow.s(8)
                            property int pillH: barWindow.s(34)

                            // ── Workspace pills (compact, merged into sys row) ──
                            Repeater {
                                model: workspacesModel
                                delegate: Rectangle {
                                    id: wsPill
                                    property bool isHovered: wsMouse.containsMouse
                                    property string stateLabel: model.wsState
                                    property string wsName: model.wsId
                                    width: barWindow.s(28); height: sysRow.pillH
                                    radius: barWindow.s(8)
                                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                                    color: stateLabel === "active" ? mocha.mauve
                                         : (isHovered ? Qt.rgba(mocha.overlay0.r, mocha.overlay0.g, mocha.overlay0.b, 0.7)
                                         : (stateLabel === "occupied" ? Qt.rgba(mocha.surface2.r, mocha.surface2.g, mocha.surface2.b, 0.7)
                                         : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)))
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    scale: isHovered && stateLabel !== "active" ? 1.08 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: barWindow.toKanji(wsName)
                                        font.family: "Noto Sans CJK JP"; font.pixelSize: barWindow.s(13)
                                        font.weight: stateLabel === "active" ? Font.Black : Font.Medium
                                        color: stateLabel === "active" ? mocha.crust
                                             : (isHovered ? mocha.text : (stateLabel === "occupied" ? mocha.text : mocha.overlay0))
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                    }
                                    MouseArea {
                                        id: wsMouse; hoverEnabled: true; anchors.fill: parent
                                        onClicked: {
                                            // Validate — Hyprland workspace names *should* be alphanumeric,
                                            // but a malicious config could include shell metacharacters
                                            if (/^[A-Za-z0-9_\-]+$/.test(wsName)) {
                                                Quickshell.execDetached(["sh", "-c",
                                                    "$HOME/.config/hypr/scripts/qs_manager.sh \"$1\"",
                                                    "_", wsName]);
                                            } else {
                                                console.warn("Refused unsafe workspace name:", wsName);
                                            }
                                        }
                                    }
                                }
                            }

                            // Thin divider between workspaces and system pills
                            Rectangle {
                                width: 1; height: sysRow.pillH - barWindow.s(8)
                                anchors.verticalCenter: parent.verticalCenter
                                color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.12)
                            }

                            // Float toggle
                            Rectangle {
                                id: floatPill
                                property bool isHovered: floatMouse.containsMouse
                                property bool isFloating: barWindow.currentWindowIsFloating
                                height: sysRow.pillH; width: barWindow.s(38); radius: barWindow.s(10); clip: true
                                color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)
                                Behavior on color { ColorAnimation { duration: 200 } }
                                scale: isHovered ? 1.05 : 1.0; Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }

                                property bool floatInitAnim: false
                                Timer { running: rightContent.showLayout && !floatPill.floatInitAnim; interval: 0; onTriggered: floatPill.floatInitAnim = true }
                                opacity: floatInitAnim ? 1 : 0
                                transform: Translate { y: floatPill.floatInitAnim ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } } }
                                Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

                                Rectangle {
                                    anchors.fill: parent; radius: parent.radius
                                    opacity: floatPill.isFloating ? 1.0 : 0.0
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: mocha.mauve }
                                        GradientStop { position: 1.0; color: Qt.lighter(mocha.mauve, 1.3) }
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: floatPill.isFloating ? "󰒱" : "󰕰"
                                    font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(17)
                                    color: floatPill.isFloating ? mocha.base : (floatPill.isHovered ? mocha.mauve : mocha.overlay2)
                                }
                                MouseArea {
                                    id: floatMouse; anchors.fill: parent; hoverEnabled: true
                                    onClicked: {
                                        barWindow.floatPollBlocked = true;
                                        floatCooldownTimer.restart();
                                        barWindow.currentWindowIsFloating = !barWindow.currentWindowIsFloating;
                                        Quickshell.execDetached(["bash", "-c",
                                            "addr=$(hyprctl activewindow -j | jq -r '.address'); hyprctl dispatch togglefloating address:$addr"
                                        ]);
                                    }
                                }
                            }

                            // KB layout
                            Rectangle {
                                id: kbPill; property bool isHovered: kbMouse.containsMouse
                                color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)
                                radius: barWindow.s(10); height: sysRow.pillH; clip: true
                                Behavior on color { ColorAnimation { duration: 200 } }
                                property real targetWidth: kbRow.width + barWindow.s(24); width: targetWidth
                                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
                                scale: isHovered ? 1.05 : 1.0; Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                property bool kbInitAnim: false
                                Timer { running: rightContent.showLayout && !kbPill.kbInitAnim; interval: 50; onTriggered: kbPill.kbInitAnim = true }
                                opacity: kbInitAnim ? 1 : 0
                                transform: Translate { y: kbPill.kbInitAnim ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } } }
                                Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                Row {
                                    id: kbRow; anchors.centerIn: parent; spacing: barWindow.s(8)
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: "󰌌"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16); color: kbPill.isHovered ? mocha.text : mocha.overlay2 }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: barWindow.kbLayout; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(13); font.weight: Font.Black; color: mocha.text }
                                }
                                MouseArea {
                                    id: kbMouse; anchors.fill: parent; hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: function(mouse) {
                                        if (mouse.button === Qt.RightButton) {
                                            // Right-click: set the SYSTEM keyboard layout/locale to the
                                            // current typing layout (persists via localectl). Needs polkit/sudo
                                            // rights for localectl; runs through pkexec so the user is prompted.
                                            Quickshell.execDetached(["bash", "-c",
                                                "L=$(hyprctl devices -j | jq -r '.keyboards[] | select(.main==true) | .active_keymap' 2>/dev/null); " +
                                                "CODE=$(echo \"$L\" | grep -qi english && echo us || (hyprctl getoption input:kb_layout -j | jq -r '.str' | cut -d, -f1)); " +
                                                "pkexec localectl set-x11-keymap \"$CODE\" 2>/dev/null || localectl set-x11-keymap \"$CODE\" 2>/dev/null"]);
                                        } else {
                                            // Left-click: cycle the typing layout only (no system change).
                                            Quickshell.execDetached(["hyprctl", "switchxkblayout", "main", "next"]);
                                        }
                                    }
                                }
                            }

                            // WiFi / Ethernet
                            Rectangle {
                                id: wifiPill; property bool isHovered: wifiMouse.containsMouse
                                radius: barWindow.s(10); height: sysRow.pillH
                                color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4); clip: true
                                Rectangle {
                                    anchors.fill: parent; radius: barWindow.s(10)
                                    opacity: barWindow.showEthernet ? (barWindow.ethStatus === "Connected" ? 1.0 : 0.0) : (barWindow.isWifiOn ? 1.0 : 0.0)
                                    Behavior on opacity { NumberAnimation { duration: 300 } }
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: mocha.blue }
                                        GradientStop { position: 1.0; color: Qt.lighter(mocha.blue, 1.3) }
                                    }
                                }
                                property real targetWidth: wifiRow.width + barWindow.s(24); width: targetWidth
                                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
                                scale: isHovered ? 1.05 : 1.0; Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                Behavior on color { ColorAnimation { duration: 200 } }
                                property bool wifiInitAnim: false
                                Timer { running: rightContent.showLayout && !wifiPill.wifiInitAnim; interval: 100; onTriggered: wifiPill.wifiInitAnim = true }
                                opacity: wifiInitAnim ? 1 : 0
                                transform: Translate { y: wifiPill.wifiInitAnim ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } } }
                                Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                Row {
                                    id: wifiRow; anchors.centerIn: parent; spacing: barWindow.s(8)
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: barWindow.showEthernet ? "󰈀" : barWindow.wifiIcon; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16); color: barWindow.showEthernet ? (barWindow.ethStatus === "Connected" ? mocha.base : mocha.subtext0) : (barWindow.isWifiOn ? mocha.base : mocha.subtext0) }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: barWindow.showEthernet ? barWindow.ethStatus : (barWindow.isWifiOn ? (barWindow.wifiSsid !== "" ? barWindow.wifiSsid : "On") : "Off"); visible: text !== ""; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(13); font.weight: Font.Black; color: barWindow.showEthernet ? (barWindow.ethStatus === "Connected" ? mocha.base : mocha.text) : (barWindow.isWifiOn ? mocha.base : mocha.text); width: Math.min(implicitWidth, barWindow.s(100)); elide: Text.ElideRight }
                                }
                                MouseArea { id: wifiMouse; hoverEnabled: true; anchors.fill: parent; onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle network wifi"]) }
                            }

                            // Bluetooth
                            Rectangle {
                                id: btPill; property bool isHovered: btMouse.containsMouse
                                radius: barWindow.s(10); height: sysRow.pillH; clip: true
                                color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)
                                Rectangle {
                                    anchors.fill: parent; radius: barWindow.s(10)
                                    opacity: barWindow.isBtOn ? 1.0 : 0.0; Behavior on opacity { NumberAnimation { duration: 300 } }
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: mocha.mauve }
                                        GradientStop { position: 1.0; color: Qt.lighter(mocha.mauve, 1.3) }
                                    }
                                }
                                property real targetWidth: barWindow.isDesktop ? 0 : btRow.width + barWindow.s(24)
                                width: targetWidth; visible: targetWidth > 0; Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutQuint } }
                                scale: isHovered ? 1.05 : 1.0; Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                                Behavior on color { ColorAnimation { duration: 200 } }
                                property bool btInitAnim: false
                                Timer { running: rightContent.showLayout && !btPill.btInitAnim; interval: 150; onTriggered: btPill.btInitAnim = true }
                                opacity: btInitAnim ? 1 : 0
                                transform: Translate { y: btPill.btInitAnim ? 0 : barWindow.s(15); Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } } }
                                Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                Row {
                                    id: btRow; anchors.centerIn: parent; spacing: barWindow.s(8)
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: barWindow.btIcon; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(16); color: barWindow.isBtOn ? mocha.base : mocha.subtext0 }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: barWindow.btDevice; visible: text !== ""; font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(13); font.weight: Font.Black; color: barWindow.isBtOn ? mocha.base : mocha.text; width: Math.min(implicitWidth, barWindow.s(100)); elide: Text.ElideRight }
                                }
                                MouseArea { id: btMouse; hoverEnabled: true; anchors.fill: parent; onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle network bt"]) }
                            }

                        }
                    }

                    // Notification bell — same style as AI button, green icon
                    Rectangle {
                        id: bellPill
                        property bool isHovered: bellMouse.containsMouse
                        color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.95) : Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)
                        radius: barWindow.s(14); border.width: 1
                        border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, isHovered ? 0.15 : 0.05)
                        height: barWindow.barHeight; width: barWindow.barHeight
                        anchors.verticalCenter: parent.verticalCenter
                        Behavior on color { ColorAnimation { duration: 200 } }
                        scale: isHovered ? 1.05 : 1.0
                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }

                        property bool bellInitAnim: false
                        Timer { running: rightContent.showLayout && !bellPill.bellInitAnim; interval: 280; onTriggered: bellPill.bellInitAnim = true }
                        opacity: bellInitAnim ? 1 : 0
                        transform: Translate {
                            x: bellPill.bellInitAnim ? 0 : barWindow.s(30)
                            Behavior on x { NumberAnimation { duration: 800; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
                        }
                        Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

                        Text {
                            anchors.centerIn: parent
                            text: "󰂚"
                            font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(26)
                            color: bellPill.isHovered ? mocha.green : mocha.subtext0
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        // Notification dot
                        Rectangle {
                            visible: barWindow.hasNotifications
                            width: barWindow.s(8); height: barWindow.s(8)
                            radius: barWindow.s(4)
                            color: mocha.red
                            anchors.right: parent.right; anchors.top: parent.top
                            anchors.rightMargin: barWindow.s(6); anchors.topMargin: barWindow.s(4)

                            SequentialAnimation on scale {
                                running: barWindow.hasNotifications
                                loops: 3
                                NumberAnimation { to: 1.4; duration: 300; easing.type: Easing.OutBack }
                                NumberAnimation { to: 1.0; duration: 300; easing.type: Easing.InOutSine }
                            }
                        }
                        MouseArea {
                            id: bellMouse; anchors.fill: parent; hoverEnabled: true
                            onClicked: {
                                barWindow.hasNotifications = false;
                                Quickshell.execDetached(["bash", "-c", "echo 0 > /tmp/qs_bell_dot; ~/.config/hypr/scripts/qs_manager.sh toggle battery"]);
                            }
                        }
                    }

                    // Recording indicator
                    Rectangle {
                        id: recButton; property bool isHovered: recMouse.containsMouse
                        color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.95) : Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)
                        radius: barWindow.s(14); border.width: 1; border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, isHovered ? 0.15 : 0.05)
                        property real targetWidth: barWindow.isRecording ? barWindow.barHeight : 0
                        width: targetWidth; height: barWindow.barHeight; anchors.verticalCenter: parent.verticalCenter
                        visible: targetWidth > 0 || opacity > 0; opacity: barWindow.isRecording ? 1.0 : 0.0; clip: true
                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
                        Behavior on opacity { NumberAnimation { duration: 300 } }
                        scale: isHovered ? 1.05 : 1.0; Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                        Behavior on color { ColorAnimation { duration: 200 } }
                        Text {
                            anchors.centerIn: parent; text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(20); color: mocha.red
                            SequentialAnimation on opacity {
                                running: barWindow.isRecording && !recButton.isHovered; loops: Animation.Infinite
                                NumberAnimation { to: 0.3; duration: 600; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                            }
                            SequentialAnimation on scale {
                                running: barWindow.isRecording && !recButton.isHovered; loops: Animation.Infinite
                                NumberAnimation { to: 1.15; duration: 600; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0;  duration: 600; easing.type: Easing.InOutSine }
                            }
                        }
                        MouseArea { id: recMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { barWindow.isRecording = false; Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/screenshot.sh"]); } }
                    }
                }
            }
        // ── Preview PopupWindow — separate surface, never blocks input ──
        PopupWindow {
            id: previewPopup
            visible: barWindow.previewDockIndex >= 0
            // Anchor to the PanelWindow
            anchor.window: barWindow

            implicitWidth:  barWindow.s(260)
            implicitHeight: barWindow.s(180)

            color: "transparent"

            // Compute X: left edge of dock + per-icon offset centred on hovered icon
            property real dockStartX: barWindow.barHeight + barWindow.s(4) + barWindow.s(10)
            property real iconStride: barWindow.s(36) + barWindow.s(6)
            property real iconCentreX: barWindow.previewDockIndex < 0 ? 0
                : dockStartX + barWindow.previewDockIndex * iconStride + barWindow.s(18)

            anchor.rect.x: Math.max(barWindow.s(4),
                Math.min(iconCentreX - implicitWidth / 2,
                         barWindow.width - implicitWidth - barWindow.s(4)))
            // Below the bar: bar starts at top margin s(8), barHeight tall, then s(4) gap
            anchor.rect.y: barWindow.s(8) + barWindow.barHeight + barWindow.s(4)
            anchor.rect.width: 1
            anchor.rect.height: 1

            Rectangle {
                anchors.fill: parent
                radius: barWindow.s(10)
                color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.95)
                border.width: 1
                border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.12)

                Behavior on opacity { NumberAnimation { duration: 150 } }
                opacity: barWindow.previewDockIndex >= 0 ? 1 : 0

                Column {
                    anchors.fill: parent
                    anchors.margins: barWindow.s(8)
                    spacing: barWindow.s(6)

                    Text {
                        width: parent.width
                        text: barWindow.previewTitle
                        font.family: "JetBrains Mono"
                        font.pixelSize: barWindow.s(11)
                        font.weight: Font.Bold
                        color: mocha.text
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        width: parent.width
                        height: barWindow.s(140)
                        radius: barWindow.s(6)
                        color: Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.8)
                        clip: true

                        Image {
                            id: previewImage
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            visible: barWindow.previewImageReady
                            cache: false
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !barWindow.previewImageReady
                            text: "󰄰"
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: barWindow.s(24)
                            color: mocha.overlay0
                        }
                    }
                }
            }
        }

        // ── AI PopupWindow — integrated in TopBar, no separate process needed ──
        PopupWindow {
            id: aiPopup
            visible: barWindow.aiVisible
            anchor.window: barWindow

            implicitWidth:  barWindow.s(420)
            implicitHeight: barWindow.s(520)

            color: "transparent"

            // Top-left corner, below the bar
            anchor.rect.x: barWindow.s(4)
            anchor.rect.y: barWindow.s(8) + barWindow.barHeight + barWindow.s(8)
            anchor.rect.width: 1
            anchor.rect.height: 1

            // Startup scale/fade
            property real introMain: 0
            property real introHeader: 0
            property real introBody: 0

            onVisibleChanged: {
                if (visible) {
                    introMain = 0; introHeader = 0; introBody = 0;
                    aiPopupAnim.restart();
                    barWindow.aiTypeLen = 0;
                    aiQueryReader.running = false; aiQueryReader.running = true;
                }
            }

            ParallelAnimation {
                id: aiPopupAnim
                NumberAnimation { target: aiPopup; property: "introMain";   from: 0; to: 1.0; duration: 700; easing.type: Easing.OutQuart }
                SequentialAnimation {
                    PauseAnimation { duration: 80 }
                    NumberAnimation { target: aiPopup; property: "introHeader"; from: 0; to: 1.0; duration: 600; easing.type: Easing.OutBack; easing.overshoot: 1.0 }
                }
                SequentialAnimation {
                    PauseAnimation { duration: 200 }
                    NumberAnimation { target: aiPopup; property: "introBody";   from: 0; to: 1.0; duration: 700; easing.type: Easing.OutQuart }
                }
            }

            // Blob orbit
            property real orbitAngle: 0
            NumberAnimation on orbitAngle {
                from: 0; to: Math.PI * 2; duration: 90000; loops: Animation.Infinite; running: true
            }

            Item {
                anchors.fill: parent
                scale: 0.92 + (0.08 * aiPopup.introMain)
                opacity: aiPopup.introMain
                transform: Translate { y: barWindow.s(12) * (1 - aiPopup.introMain) }

                Rectangle {
                    anchors.fill: parent
                    radius: barWindow.s(20)
                    color: mocha.base
                    border.color: mocha.surface0
                    border.width: 1
                    clip: true

                    // Ambient blobs — same as BatteryPopup
                    Rectangle {
                        width: parent.width * 0.8; height: width; radius: width / 2
                        x: parent.width / 2 - width / 2 + Math.cos(aiPopup.orbitAngle * 2) * barWindow.s(120)
                        y: parent.height / 2 - height / 2 + Math.sin(aiPopup.orbitAngle * 2) * barWindow.s(80)
                        color: mocha.mauve; opacity: 0.08
                    }
                    Rectangle {
                        width: parent.width * 0.9; height: width; radius: width / 2
                        x: parent.width / 2 - width / 2 + Math.sin(aiPopup.orbitAngle * 1.5) * barWindow.s(-120)
                        y: parent.height / 2 - height / 2 + Math.cos(aiPopup.orbitAngle * 1.5) * barWindow.s(-80)
                        color: mocha.blue; opacity: 0.06
                    }

                    // Dismiss on click
                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { barWindow.aiVisible = false; Quickshell.execDetached(["bash", "-c", "echo 0 > /tmp/qs_ai_visible"]); }
                        Rectangle {
                            anchors.fill: parent; radius: parent.parent.radius
                            color: mocha.surface0
                            opacity: parent.containsMouse ? 0.12 : 0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: barWindow.s(20)
                        spacing: barWindow.s(16)

                        // Header
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: barWindow.s(12)
                            opacity: aiPopup.introHeader
                            transform: Translate { y: barWindow.s(-20) * (1.0 - aiPopup.introHeader) }

                            Text {
                                text: "󰂽"
                                font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(22)
                                color: mocha.mauve
                            }
                            Text {
                                text: "Agentic Intelligence"
                                font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: barWindow.s(18)
                                color: mocha.text; Layout.fillWidth: true
                            }
                            Rectangle {
                                Layout.preferredWidth: statusInnerRow.implicitWidth + barWindow.s(16)
                                Layout.preferredHeight: barWindow.s(28)
                                radius: barWindow.s(8)
                                color: barWindow.aiState === "loading"
                                    ? Qt.rgba(mocha.peach.r, mocha.peach.g, mocha.peach.b, 0.15)
                                    : Qt.rgba(mocha.green.r, mocha.green.g, mocha.green.b, 0.15)
                                Behavior on color { ColorAnimation { duration: 300 } }
                                Row {
                                    id: statusInnerRow; anchors.centerIn: parent; spacing: barWindow.s(6)
                                    Text {
                                        font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(13)
                                        color: barWindow.aiState === "loading" ? mocha.peach : mocha.green
                                        text: barWindow.aiState === "loading" ? "󰔟" : "󰄳"
                                        Behavior on color { ColorAnimation { duration: 300 } }
                                    }
                                    Text {
                                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: barWindow.s(11)
                                        color: barWindow.aiState === "loading" ? mocha.peach : mocha.green
                                        text: barWindow.aiState === "loading" ? "Thinking" : "Done"
                                        Behavior on color { ColorAnimation { duration: 300 } }
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: mocha.surface1; opacity: aiPopup.introHeader }

                        // Question
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: barWindow.s(6)
                            opacity: aiPopup.introBody
                            transform: Translate { y: barWindow.s(20) * (1.0 - aiPopup.introBody) }

                            Text {
                                text: "QUESTION"
                                font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: barWindow.s(10)
                                color: mocha.overlay1
                            }
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: qHidden.implicitHeight
                                Text {
                                    id: qHidden; text: barWindow.aiQuery || "…"; width: parent.width
                                    font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: barWindow.s(15)
                                    wrapMode: Text.Wrap; visible: false
                                }
                                Text {
                                    anchors.fill: parent; text: barWindow.aiQuery || "…"
                                    font: qHidden.font; color: mocha.text; wrapMode: Text.Wrap
                                }
                            }
                        }

                        // Loading bar
                        Rectangle {
                            Layout.fillWidth: true; height: barWindow.s(2); radius: barWindow.s(1)
                            visible: barWindow.aiState === "loading"; color: mocha.surface1
                            opacity: aiPopup.introBody
                            Rectangle {
                                height: parent.height; radius: parent.radius; color: mocha.mauve
                                width: parent.width * 0.35
                                property real pos: 0
                                SequentialAnimation on pos {
                                    loops: Animation.Infinite; running: barWindow.aiState === "loading"
                                    NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 0; duration: 900; easing.type: Easing.InOutSine }
                                }
                                x: pos * (parent.width - width)
                            }
                        }

                        // Response
                        ColumnLayout {
                            Layout.fillWidth: true; Layout.fillHeight: true; spacing: barWindow.s(6)
                            visible: barWindow.aiDisplayed !== ""
                            opacity: aiPopup.introBody
                            transform: Translate { y: barWindow.s(20) * (1.0 - aiPopup.introBody) }

                            Text {
                                text: "RESPONSE"
                                font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: barWindow.s(10)
                                color: mocha.overlay1
                            }
                            Rectangle {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                color: Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.5)
                                radius: barWindow.s(12); clip: true
                                Flickable {
                                    anchors.fill: parent; anchors.margins: barWindow.s(12)
                                    contentHeight: aiResponseText.implicitHeight; clip: true
                                    ScrollBar.vertical: ScrollBar {
                                        width: barWindow.s(3); policy: ScrollBar.AsNeeded
                                        contentItem: Rectangle { implicitWidth: barWindow.s(3); radius: barWindow.s(1); color: mocha.surface2 }
                                    }
                                    Text {
                                        id: aiResponseText; width: parent.width
                                        text: barWindow.aiDisplayed
                                        font.family: "JetBrains Mono"; font.weight: Font.Medium; font.pixelSize: barWindow.s(13)
                                        color: mocha.subtext0; wrapMode: Text.Wrap; textFormat: Text.PlainText
                                    }
                                }
                            }
                        }

                        // Footer
                        Text {
                            visible: barWindow.aiState === "ready" && barWindow.aiTypeLen >= barWindow.aiResponse.length
                            text: "click anywhere to dismiss"
                            font.family: "JetBrains Mono"; font.pixelSize: barWindow.s(11)
                            color: mocha.overlay1; Layout.alignment: Qt.AlignRight
                            opacity: aiPopup.introBody
                        }
                    }
                }
            }
        }

        }
    }
}
