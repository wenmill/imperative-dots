import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import QtCore
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: window

    // --- RECEIVE THE DBUS LIST FROM MAIN.QML ---
    property var notifModel

    // State object for collapsible notification groups
    property var collapsedGroups: ({})

    function toggleGroup(groupName) {
        let temp = Object.assign({}, collapsedGroups);
        temp[groupName] = !temp[groupName];
        collapsedGroups = temp;
    }

    function isCollapsed(groupName) {
        return collapsedGroups[groupName] === true;
    }

    // Helper: Safely clear an entire group of notifications by AppName
    function clearGroup(appName) {
        if (!notifModel) return;
        for (let i = notifModel.count - 1; i >= 0; i--) {
            if (notifModel.get(i).appName === appName) {
                notifModel.remove(i);
            }
        }
    }

    // --- Responsive Scaling Logic ---
    Scaler {
        id: scaler
        // Uses the physical screen width so the popup scales synchronously with the TopBar
        currentWidth: Screen.width
    }
    
    // Helper function scoped to the root Item for easy access in deeply nested elements and Canvases
    function s(val) { 
        return scaler.s(val); 
    }

    // -------------------------------------------------------------------------
    // COLORS (Dynamic Matugen Palette)
    // -------------------------------------------------------------------------
    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color mantle: _theme.mantle
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color overlay1: _theme.overlay1
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    
    readonly property color mauve: _theme.mauve
    readonly property color pink: _theme.pink
    readonly property color red: _theme.red
    readonly property color maroon: _theme.maroon
    readonly property color peach: _theme.peach
    readonly property color yellow: _theme.yellow
    readonly property color green: _theme.green
    readonly property color teal: _theme.teal
    readonly property color sapphire: _theme.sapphire
    readonly property color blue: _theme.blue

    // -------------------------------------------------------------------------
    // CACHE (Eliminates startup delay visually)
    // -------------------------------------------------------------------------
    Settings {
        id: widgetCache
        category: "SystemMonitorCache"
        property int cpuUsage: 0
        property int ramUsage: 0
        property int diskUsage: 0
        property int gpuUsage: 0
        property int sysTemp: 0
        property string powerProfile: "balanced"
        property int upHours: 0
        property int upMins: 0
        property real sysVolume: 0
        property bool sysMuted: false
        property real sysBrightness: 0
        property string currentUserName: "User"
    }

    // -------------------------------------------------------------------------
    // STATE & POLLING
    // -------------------------------------------------------------------------
    property int cpuUsage: widgetCache.cpuUsage
    property int ramUsage: widgetCache.ramUsage
    property int diskUsage: widgetCache.diskUsage
    property int gpuUsage: widgetCache.gpuUsage
    property int sysTemp: widgetCache.sysTemp

    property string powerProfile: widgetCache.powerProfile
    
    property int upHours: widgetCache.upHours
    property int upMins: widgetCache.upMins

    property real sysVolume: widgetCache.sysVolume
    property bool sysMuted: widgetCache.sysMuted
    property real sysBrightness: widgetCache.sysBrightness
    
    property string currentUserName: widgetCache.currentUserName

    property bool dndEnabled: false
    property string focusMode: "default"
    property string pendingFocusMode: ""
    property int focusEndEpoch: 0
    property int focusSetMins: 60
    property int focusRemainSec: 0
    property string focusCountdown: {
        if (focusRemainSec <= 0) return "";
        let m = Math.floor(focusRemainSec / 60);
        let s = focusRemainSec % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    // ── Fastfetch-style system info ──
    property string sysOs: ""
    property string sysKernel: ""
    property string sysShell: ""
    property string sysCpuName: ""
    property string sysGpu: ""
    property string sysMemory: ""
    property string sysDiskStr: ""
    property string sysPackages: ""
    property string sysTerminal: ""
    property string sysWm: ""
    property string sysResolution: ""
    property string sysLocale: ""

    // Anti-Jitter Sync States
    property bool isDraggingVol: false
    property bool isDraggingBri: false

    Timer { id: volSyncDelay; interval: 800; onTriggered: window.isDraggingVol = false; triggeredOnStart: true; }
    Timer { id: briSyncDelay; interval: 800; onTriggered: window.isDraggingBri = false; triggeredOnStart: true; }

    // Unified hue for Performance Profile
    readonly property color profileStart: {
        if (powerProfile === "performance") return window.red;
        if (powerProfile === "power-saver") return window.green;
        return window.blue;
    }
    readonly property color profileEnd: Qt.lighter(profileStart, 1.15)

    // Ambient Blobs - Static for Desktop version
    readonly property color ambientPrimary: window.mauve
    readonly property color ambientSecondary: window.blue

    // --- INIT DND STATE FROM CACHE ---
    Process {
        id: dndInit
        running: true
        command: ["bash", "-c", "mkdir -p ~/.cache && cat ~/.cache/qs_dnd 2>/dev/null || echo '0'"]
        stdout: StdioCollector {
            onStreamFinished: {
                window.dndEnabled = (this.text.trim() === "1");
            }
        }
    }

    Process {
        id: userPoller
        command: ["bash", "-c", "echo $USER"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                window.currentUserName = this.text.trim();
                widgetCache.currentUserName = window.currentUserName;
            }
        }
    }

    Process {
        id: sysPoller
        // HIGHLY ROBUST BASH COMMANDS
        command: ["bash", "-c", 
            "vmstat 1 2 | tail -1 | awk '{print 100 - $15}' || echo '0'; " +
            "free -m | awk '/Mem:/ {print int($3/$2 * 100)}' || echo '0'; " +
            "df -h / | awk 'NR==2 {print $5}' | tr -d '%' || echo '0'; " +
            "temp=$(sensors 2>/dev/null | grep -m 1 -E 'Package id 0|Tctl|Tdie|edge|temp1' | grep -oE '\\+[0-9]+\\.[0-9]+' | head -n 1 | tr -d '+' | cut -d. -f1); [ -z \"$temp\" ] && temp=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -n 1 | awk '{print int($1/1000)}'); echo \"${temp:-0}\"; " +
            "powerprofilesctl get 2>/dev/null || echo 'balanced'; " +
            "awk '{print int($1/3600)\"h \"int(($1%3600)/60)\"m\"}' /proc/uptime 2>/dev/null || echo '0h 0m'; " +
            "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{print int($2*100), ($3==\"[MUTED]\"?\"off\":\"on\")}' || echo '0 on'; " +
            "brightnessctl -m 2>/dev/null | awk -F, '{print substr($4, 1, length($4)-1)}' || echo '0'; " +
            "cat /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -1 || { nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | grep -E '^[0-9]+$' || echo '0'; }"
        ]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n");
                if (lines.length >= 8) {
                    window.cpuUsage = parseInt(lines[0]) || 0;
                    widgetCache.cpuUsage = window.cpuUsage;

                    window.ramUsage = parseInt(lines[1]) || 0;
                    widgetCache.ramUsage = window.ramUsage;

                    window.diskUsage = parseInt(lines[2]) || 0;
                    widgetCache.diskUsage = window.diskUsage;

                    window.sysTemp = parseInt(lines[3]) || 0;
                    widgetCache.sysTemp = window.sysTemp;
                    
                    window.powerProfile = lines[4];
                    widgetCache.powerProfile = window.powerProfile;
                    
                    let upParts = lines[5].split("h ");
                    if (upParts.length === 2) {
                        window.upHours = parseInt(upParts[0]) || 0;
                        widgetCache.upHours = window.upHours;
                        window.upMins = parseInt(upParts[1].replace("m", "")) || 0;
                        widgetCache.upMins = window.upMins;
                    }

                    if (!window.isDraggingVol) {
                        let volParts = (lines[6] || "0 on").trim().split(" ");
                        window.sysVolume = parseInt(volParts[0]) || 0;
                        widgetCache.sysVolume = window.sysVolume;
                        window.sysMuted = (volParts[1] === "off");
                        widgetCache.sysMuted = window.sysMuted;
                    }
                    
                    if (!window.isDraggingBri) {
                        window.sysBrightness = parseInt(lines[7]) || 0;
                        widgetCache.sysBrightness = window.sysBrightness;
                    }

                    if (lines.length >= 9) {
                        window.gpuUsage = parseInt(lines[8]) || 0;
                        widgetCache.gpuUsage = window.gpuUsage;
                    }
                }
            }
        }
    }

    Timer {
        interval: 1500; running: true; repeat: true; triggeredOnStart: true;
        onTriggered: sysPoller.running = true
    }

    // ── Focus mode reader + countdown ──
    Process {
        id: focusReader; running: true
        command: ["bash", "-c", "cat ~/.cache/qs_focus_mode 2>/dev/null || echo 'default'"]
        stdout: StdioCollector {
            onStreamFinished: { window.focusMode = this.text.trim() || "default"; }
        }
    }
    Process {
        id: focusEndReader; running: true
        command: ["bash", "-c", "cat ~/.cache/qs_focus_end 2>/dev/null || echo '0'"]
        stdout: StdioCollector {
            onStreamFinished: { window.focusEndEpoch = parseInt(this.text.trim()) || 0; }
        }
    }
    // Countdown display only — TopBar handles the actual expiry and mode reset
    Timer {
        id: focusCountdownTimer
        interval: 1000; running: window.focusMode !== "default" && window.focusEndEpoch > 0; repeat: true
        onTriggered: {
            let now = Math.floor(Date.now() / 1000);
            window.focusRemainSec = Math.max(0, window.focusEndEpoch - now);
            // If expired, re-read state (TopBar will have already reset it)
            if (window.focusRemainSec <= 0) {
                focusReader.running = false; focusReader.running = true;
                focusEndReader.running = false; focusEndReader.running = true;
            }
        }
    }

    // ── System info poller (runs once) ──
    Process {
        id: infoPoller
        running: true
        command: ["bash", Qt.resolvedUrl("fetch_sysinfo.sh").toString().replace("file://", "")]
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n");
                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i];
                    let idx = line.indexOf(":");
                    if (idx < 0) continue;
                    let key = line.substring(0, idx).trim();
                    let val = line.substring(idx + 1).trim();
                    if      (key === "OS")         window.sysOs = val;
                    else if (key === "KERNEL")     window.sysKernel = val;
                    else if (key === "SHELL")      window.sysShell = val;
                    else if (key === "CPU_NAME")   window.sysCpuName = val;
                    else if (key === "GPU")        window.sysGpu = val;
                    else if (key === "MEMORY")     window.sysMemory = val;
                    else if (key === "DISK")       window.sysDiskStr = val;
                    else if (key === "PACKAGES")   window.sysPackages = val;
                    else if (key === "TERMINAL")   window.sysTerminal = val;
                    else if (key === "WM")         window.sysWm = val;
                    else if (key === "RESOLUTION") window.sysResolution = val;
                    else if (key === "LOCALE")     window.sysLocale = val;
                }
            }
        }
    }

    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2; duration: 90000; loops: Animation.Infinite; running: true
    }

    // --- ENHANCED STARTUP ANIMATION STATES ---
    property real introMain: 0
    property real introTop: 0
    property real introNotifs: 0
    property real introCore: 0
    property real introSliders: 0
    property real introActions: 0
    property real introProfiles: 0

    ParallelAnimation {
        running: true

        // Base window fades, scales, and lifts
        NumberAnimation { target: window; property: "introMain"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutQuart }

        // Top bar drops in
        SequentialAnimation {
            PauseAnimation { duration: 100 }
            NumberAnimation { target: window; property: "introTop"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutBack; easing.overshoot: 1.0 }
        }

        // Notification List cascades in smoothly
        SequentialAnimation {
            PauseAnimation { duration: 150 }
            NumberAnimation { target: window; property: "introNotifs"; from: 0; to: 1.0; duration: 850; easing.type: Easing.OutQuart }
        }

        // Central core pops out and breathes
        SequentialAnimation {
            PauseAnimation { duration: 250 }
            NumberAnimation { target: window; property: "introCore"; from: 0; to: 1.0; duration: 900; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        }

        // Hardware sliders slide up
        SequentialAnimation {
            PauseAnimation { duration: 350 }
            NumberAnimation { target: window; property: "introSliders"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutQuart }
        }

        // Actions waterfall
        SequentialAnimation {
            PauseAnimation { duration: 450 }
            NumberAnimation { target: window; property: "introActions"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutExpo }
        }

        // Power profiles finish the wave
        SequentialAnimation {
            PauseAnimation { duration: 550 }
            NumberAnimation { target: window; property: "introProfiles"; from: 0; to: 1.0; duration: 850; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
        }
    }

    ParallelAnimation {
        id: exitAnim
        NumberAnimation { target: window; property: "introMain"; to: 0; duration: 400; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introTop"; to: 0; duration: 300; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introNotifs"; to: 0; duration: 300; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introCore"; to: 0; duration: 350; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introSliders"; to: 0; duration: 250; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introActions"; to: 0; duration: 200; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introProfiles"; to: 0; duration: 150; easing.type: Easing.InQuart }
    }

    // -------------------------------------------------------------------------
    // UI LAYOUT
    // -------------------------------------------------------------------------
    Item {
        anchors.fill: parent
        scale: 0.92 + (0.08 * introMain)
        opacity: introMain
        transform: Translate { y: window.s(15) * (1 - introMain) }

        // Unified Outer Background
        Rectangle {
            anchors.fill: parent
            radius: window.s(20)
            color: window.base
            border.color: window.surface0 
            border.width: 1
            clip: true

            // Rotating Background Blobs - Spanning across the whole widget natively
            Rectangle {
                width: parent.width * 0.8; height: width; radius: width / 2
                x: (parent.width / 2 - width / 2) + Math.cos(window.globalOrbitAngle * 2) * window.s(150)
                y: (parent.height / 2 - height / 2) + Math.sin(window.globalOrbitAngle * 2) * window.s(100)
                opacity: 0.08
                color: window.ambientPrimary
                Behavior on color { ColorAnimation { duration: 1000 } }
            }
            
            Rectangle {
                width: parent.width * 0.9; height: width; radius: width / 2
                x: (parent.width / 2 - width / 2) + Math.sin(window.globalOrbitAngle * 1.5) * window.s(-150)
                y: (parent.height / 2 - height / 2) + Math.cos(window.globalOrbitAngle * 1.5) * window.s(-100)
                opacity: 0.06
                color: window.ambientSecondary
                Behavior on color { ColorAnimation { duration: 1000 } }
            }

            RowLayout {
                anchors.fill: parent
                spacing: window.s(15) // Seamless separation instead of a line

                // ==========================================
                // LEFT SIDE: NOTIFICATION CENTER
                // ==========================================
                Item {
                    Layout.preferredWidth: window.s(320)
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: window.s(20)
                        spacing: window.s(15)

                        // --- Notification Header & DND Toggle ---
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: window.s(38)
                            spacing: window.s(12)
                            
                            transform: Translate { y: window.s(-20) * (1.0 - introTop) }
                            opacity: introTop

                            Item { Layout.fillWidth: true }
                            Text {
                                text: "Notifications"
                                font.family: "JetBrains Mono"
                                font.weight: Font.Black
                                font.pixelSize: window.s(18)
                                color: window.text
                            }
                            Item { Layout.fillWidth: true }

                            // DND Toggle Button
                            Rectangle {
                                Layout.preferredWidth: dndMa.containsMouse ? window.s(38) + dndText.implicitWidth + window.s(8) : window.s(38)
                                Layout.preferredHeight: window.s(38)
                                radius: window.s(12)
                                color: window.dndEnabled ? Qt.alpha(window.red, 0.15) : (dndMa.containsMouse ? window.surface1 : "transparent")
                                border.color: window.dndEnabled ? window.red : (dndMa.containsMouse ? window.surface2 : "transparent")
                                border.width: 1
                                clip: true

                                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                Row {
                                    anchors.right: parent.right
                                    anchors.rightMargin: window.s(10)
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: window.s(8)

                                    Text {
                                        id: dndText
                                        text: window.dndEnabled ? "Silent" : "Mute"
                                        font.family: "JetBrains Mono"
                                        font.weight: Font.Bold
                                        font.pixelSize: window.s(13)
                                        color: window.dndEnabled ? window.red : window.text
                                        anchors.verticalCenter: parent.verticalCenter
                                        opacity: dndMa.containsMouse ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 250 } }
                                    }

                                    Text {
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: window.s(18)
                                        color: window.dndEnabled ? window.red : (dndMa.containsMouse ? window.text : window.overlay0)
                                        text: window.dndEnabled ? "󰂛" : "󰂚"
                                        anchors.verticalCenter: parent.verticalCenter
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }
                                }

                                MouseArea {
                                    id: dndMa
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        window.dndEnabled = !window.dndEnabled;
                                        Quickshell.execDetached(["sh", "-c", "mkdir -p ~/.cache && echo '" + (window.dndEnabled ? "1" : "0") + "' > ~/.cache/qs_dnd"]);
                                    }
                                }
                            }
                        }

                        // --- Zero State ---
                        Text {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.family: "JetBrains Mono"
                            font.weight: Font.Medium
                            font.pixelSize: window.s(14)
                            color: window.overlay0
                            text: "You're all caught up."
                            visible: !notifModel || notifModel.count === 0
                            opacity: introNotifs
                        }

                        // --- Notification List ---
                        ListView {
                            id: notifList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            model: window.notifModel
                            spacing: window.s(8)
                            clip: true
                            
                            opacity: introNotifs
                            transform: Translate { y: window.s(20) * (1 - introNotifs) }

                            ScrollBar.vertical: ScrollBar {
                                active: notifList.moving || notifList.movingVertically
                                width: window.s(4)
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle { implicitWidth: window.s(4); radius: window.s(2); color: window.surface2 }
                            }

                            // Fluid Animations
                            add: Transition {
                                ParallelAnimation {
                                    NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 400; easing.type: Easing.OutQuint }
                                    NumberAnimation { property: "x"; from: window.s(-40); to: 0; duration: 500; easing.type: Easing.OutExpo }
                                    NumberAnimation { property: "scale"; from: 0.95; to: 1.0; duration: 500; easing.type: Easing.OutBack }
                                }
                            }
                            remove: Transition {
                                ParallelAnimation {
                                    NumberAnimation { property: "opacity"; to: 0.0; duration: 300; easing.type: Easing.OutQuint }
                                    NumberAnimation { property: "scale"; to: 0.9; duration: 300; easing.type: Easing.OutQuint }
                                }
                            }
                            displaced: Transition {
                                NumberAnimation { properties: "y"; duration: 400; easing.type: Easing.OutExpo }
                            }

                            // --- Grouping Configuration ---
                            section.property: "appName"
                            section.criteria: ViewSection.FullString
                            section.delegate: Item {
                                width: ListView.view.width
                                height: window.s(46)
                                
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.topMargin: window.s(10)
                                    anchors.bottomMargin: window.s(4)
                                    color: headerMa.containsMouse ? window.surface1 : "transparent"
                                    radius: window.s(8)
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: window.s(6)
                                        anchors.rightMargin: window.s(6)
                                        spacing: window.s(8)

                                        // Clickable Area for Collapse Toggle
                                        MouseArea {
                                            id: headerMa
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: window.toggleGroup(section)

                                            RowLayout {
                                                anchors.fill: parent
                                                spacing: window.s(8)
                                                
                                                Text {
                                                    font.family: "Iosevka Nerd Font"
                                                    font.pixelSize: window.s(14)
                                                    color: window.mauve
                                                    text: window.isCollapsed(section) ? "󰅂" : "󰅀"
                                                    Behavior on rotation { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                                                }

                                                Text {
                                                    text: section.toUpperCase()
                                                    font.family: "JetBrains Mono"
                                                    font.weight: Font.Black
                                                    font.pixelSize: window.s(11)
                                                    color: window.text
                                                    Layout.fillWidth: true
                                                    verticalAlignment: Text.AlignVCenter
                                                }
                                            }
                                        }

                                        // Clear Group Button
                                        Rectangle {
                                            Layout.preferredWidth: window.s(26)
                                            Layout.preferredHeight: window.s(26)
                                            radius: window.s(13)
                                            color: groupClearMa.containsMouse ? window.surface2 : "transparent"
                                            Behavior on color { ColorAnimation { duration: 150 } }

                                            Text {
                                                anchors.centerIn: parent
                                                font.family: "Iosevka Nerd Font"
                                                font.pixelSize: window.s(14)
                                                color: groupClearMa.containsMouse ? window.red : window.overlay0
                                                text: "󰅖"
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                            }

                                            MouseArea {
                                                id: groupClearMa
                                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: window.clearGroup(section)
                                            }
                                        }
                                    }
                                }
                            }

                            // --- Individual Notification Card ---
                            delegate: Item {
                                id: delegateWrapper
                                width: ListView.view.width
                                property bool isHidden: window.isCollapsed(model.appName)
                                height: isHidden ? 0 : innerCard.height
                                visible: height > 0
                                opacity: isHidden ? 0 : 1
                                clip: true
                                
                                Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }
                                Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

                                Rectangle {
                                    id: innerCard
                                    width: parent.width
                                    height: cardContent.height + window.s(24)
                                    radius: window.s(14)
                                    color: cardHover.containsMouse ? window.surface1 : window.surface0
                                    border.color: cardHover.containsMouse ? window.surface2 : "transparent"
                                    border.width: 1
                                    clip: true
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Behavior on border.color { ColorAnimation { duration: 200 } }

                                    MouseArea {
                                        id: cardHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                    }

                                    // Left side accent stripe
                                    Rectangle {
                                        width: window.s(4)
                                        height: parent.height
                                        anchors.left: parent.left
                                        color: window.ambientPrimary
                                    }

                                    ColumnLayout {
                                        id: cardContent
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: window.s(14)
                                        anchors.leftMargin: window.s(18) // make room for the accent stripe
                                        spacing: window.s(6)

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: window.s(8)

                                            Text {
                                                text: model.summary || "Notification"
                                                font.family: "JetBrains Mono"
                                                font.weight: Font.Bold
                                                font.pixelSize: window.s(13)
                                                color: window.text
                                                Layout.fillWidth: true
                                                wrapMode: Text.Wrap
                                            }

                                            // Individual Dismiss Button
                                            Rectangle {
                                                Layout.preferredWidth: window.s(22)
                                                Layout.preferredHeight: window.s(22)
                                                radius: window.s(11)
                                                color: itemClearMa.containsMouse ? Qt.alpha(window.red, 0.15) : "transparent"
                                                Behavior on color { ColorAnimation { duration: 150 } }

                                                Text {
                                                    anchors.centerIn: parent
                                                    font.family: "Iosevka Nerd Font"
                                                    font.pixelSize: window.s(12)
                                                    color: itemClearMa.containsMouse ? window.red : window.overlay0
                                                    text: "󰅖"
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                }

                                                MouseArea {
                                                    id: itemClearMa
                                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if(window.notifModel) window.notifModel.remove(index);
                                                    }
                                                }
                                            }
                                        }

                                        Text {
                                            text: model.body || ""
                                            font.family: "JetBrains Mono"
                                            font.weight: Font.Medium
                                            font.pixelSize: window.s(11)
                                            color: window.subtext0
                                            Layout.fillWidth: true
                                            wrapMode: Text.Wrap
                                            visible: text !== ""
                                            textFormat: Text.PlainText 
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ==========================================
                // RIGHT SIDE: SYSTEM RESOURCES CORE
                // ==========================================
                Item {
                    Layout.preferredWidth: window.s(480)
                    Layout.fillHeight: true

                    // Radar Rings
                    Item {
                        id: radarItem
                        anchors.fill: parent
                        
                        Repeater {
                            model: 3
                            Rectangle {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: window.s(-70)
                                width: window.s(320) + (index * window.s(170))
                                height: width
                                radius: width / 2
                                color: "transparent"
                                border.color: window.ambientSecondary
                                border.width: 1
                                opacity: 0.06 - (index * 0.02)
                            }
                        }
                    }

                    // ==========================================
                    // TOP: UPTIME COMPONENT
                    // ==========================================
                    // Expanding top-left screenshot icon
                    Rectangle {
                        id: screenshotBtn
                        anchors.top: parent.top; anchors.left: parent.left
                        anchors.margins: window.s(20)
                        z: 10
                        width: screenshotMa.containsMouse ? window.s(38) + screenshotLabel.implicitWidth + window.s(12) : window.s(38)
                        height: window.s(38); radius: window.s(12)
                        color: screenshotMa.containsMouse ? window.surface1 : "transparent"
                        border.color: screenshotMa.containsMouse ? window.surface2 : "transparent"
                        clip: true

                        transform: Translate { y: window.s(-20) * (1.0 - introTop) }
                        opacity: introTop

                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: window.s(13)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: window.s(12)

                            Text {
                                font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(18)
                                color: screenshotMa.containsMouse ? window.blue : window.overlay0
                                text: "󰄀"
                                anchors.verticalCenter: parent.verticalCenter
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            Text {
                                id: screenshotLabel
                                text: "Screenshot"
                                font.family: "JetBrains Mono"
                                font.weight: Font.Bold
                                font.pixelSize: window.s(14)
                                color: window.text
                                anchors.verticalCenter: parent.verticalCenter
                                opacity: screenshotMa.containsMouse ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 250 } }
                            }
                        }

                        MouseArea {
                            id: screenshotMa
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                // Close popup immediately (no animation), then screenshot
                                Quickshell.execDetached(["sh", "-c", "echo 'close' > /tmp/qs_widget_state"]);
                                screenshotSelectDelay.start();
                            }
                        }

                        Timer {
                            id: screenshotSelectDelay; interval: 800; repeat: false
                            onTriggered: Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/screenshot.sh"])
                        }
                    }

                    // Expanding top-right logout icon
                    Rectangle {
                        id: logoutBtn
                        anchors.top: parent.top; anchors.right: parent.right
                        anchors.margins: window.s(20)
                        z: 10
                        width: logoutMa.containsMouse ? window.s(38) + usernameText.implicitWidth + window.s(12) : window.s(38)
                        height: window.s(38); radius: window.s(12)
                        color: logoutMa.containsMouse ? window.surface1 : "transparent"
                        border.color: logoutMa.containsMouse ? window.surface2 : "transparent"
                        clip: true
                        
                        transform: Translate { y: window.s(-20) * (1.0 - introTop) }
                        opacity: introTop

                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: window.s(13)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: window.s(12)

                            Text {
                                id: usernameText
                                text: window.currentUserName
                                font.family: "JetBrains Mono"
                                font.weight: Font.Bold
                                font.pixelSize: window.s(14)
                                color: window.text
                                anchors.verticalCenter: parent.verticalCenter
                                opacity: logoutMa.containsMouse ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 250 } }
                            }

                            Text {
                                font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(18)
                                color: logoutMa.containsMouse ? window.red : window.overlay0
                                text: "󰍃"
                                anchors.verticalCenter: parent.verticalCenter
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                        }

                        MouseArea {
                            id: logoutMa
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { 
                                exitAnim.start();
                                Quickshell.execDetached(["sh", "-c", "loginctl kill-session $XDG_SESSION_ID"]); 
                                Quickshell.execDetached(["sh", "-c", "echo 'close' > /tmp/qs_widget_state"]); 
                            }
                        }
                    }

                    // ==========================================
                    // BIG SYSTEM RESOURCES GRID (DESKTOP)
                    // ==========================================
                    Grid {
                        id: sysGrid
                        columns: 2
                        spacing: window.s(25)
                        anchors.horizontalCenter: parent.horizontalCenter
                        // Center vertically in the space between top and bottomDocks
                        anchors.bottom: bottomDocks.top; anchors.bottomMargin: window.s(15) 
                        z: 1

                        opacity: introCore
                        transform: Translate { y: window.s(25) * (1 - introCore) }
                        scale: 0.9 + (0.1 * introCore)

                        // 1. CPU Orb
                        Item {
                            id: cpuOrb; width: window.s(145); height: window.s(145)
                            property real animVal: window.cpuUsage
                            Behavior on animVal { NumberAnimation { duration: 1200; easing.type: Easing.OutQuint } }
                            onAnimValChanged: cpuCanvas.requestPaint()
                            
                            scale: cpuMa.containsMouse ? 1.05 : 1.0
                            Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }

                            // Individual Aura - Fixed Overlap
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width + (cpuMa.containsMouse ? window.s(16) : window.s(4)) 
                                height: width; radius: width / 2
                                color: window.blue
                                opacity: cpuMa.containsMouse ? 0.25 : 0.08
                                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
                                Behavior on opacity { NumberAnimation { duration: 300 } }
                            }

                            Canvas {
                                id: cpuCanvas; anchors.fill: parent; rotation: 180
                                onPaint: {
                                    var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height);
                                    var cX = width/2; var cY = height/2; var rad = (width/2)-window.s(8);
                                    var eA = (Math.min(100, Math.max(0, parent.animVal)) / 100) * 2 * Math.PI;
                                    ctx.lineCap = "round"; ctx.lineWidth = window.s(8); ctx.beginPath(); ctx.arc(cX, cY, rad, 0, 2*Math.PI); 
                                    ctx.strokeStyle = window.surface0.toString(); ctx.stroke();
                                    var grad = ctx.createLinearGradient(0, height, width, 0); grad.addColorStop(0, window.blue.toString()); grad.addColorStop(1, window.sapphire.toString());
                                    ctx.lineWidth = window.s(14); ctx.beginPath(); ctx.arc(cX, cY, rad, 0, eA); ctx.strokeStyle = grad; ctx.stroke();
                                }
                            }
                            ColumnLayout {
                                anchors.centerIn: parent; spacing: 0
                                RowLayout {
                                    Layout.alignment: Qt.AlignHCenter; spacing: window.s(4)
                                    Text { font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(18); color: window.blue; text: "" }
                                    Text { font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(28); color: window.text; text: Math.round(cpuOrb.animVal) + "%" }
                                }
                                Text { Layout.alignment: Qt.AlignHCenter; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(12); color: window.subtext0; text: "CPU LOAD" }
                            }
                            MouseArea { id: cpuMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor }
                        }

                        // 2. RAM Orb
                        Item {
                            id: ramOrb; width: window.s(145); height: window.s(145)
                            property real animVal: window.ramUsage
                            Behavior on animVal { NumberAnimation { duration: 1200; easing.type: Easing.OutQuint } }
                            onAnimValChanged: ramCanvas.requestPaint()

                            scale: ramMa.containsMouse ? 1.05 : 1.0
                            Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }

                            // Individual Aura - Fixed Overlap
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width + (ramMa.containsMouse ? window.s(16) : window.s(4))
                                height: width; radius: width / 2
                                color: window.mauve
                                opacity: ramMa.containsMouse ? 0.25 : 0.08
                                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
                                Behavior on opacity { NumberAnimation { duration: 300 } }
                            }

                            Canvas {
                                id: ramCanvas; anchors.fill: parent; rotation: 180
                                onPaint: {
                                    var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height);
                                    var cX = width/2; var cY = height/2; var rad = (width/2)-window.s(8);
                                    var eA = (Math.min(100, Math.max(0, parent.animVal)) / 100) * 2 * Math.PI;
                                    ctx.lineCap = "round"; ctx.lineWidth = window.s(8); ctx.beginPath(); ctx.arc(cX, cY, rad, 0, 2*Math.PI); 
                                    ctx.strokeStyle = window.surface0.toString(); ctx.stroke();
                                    var grad = ctx.createLinearGradient(0, height, width, 0); grad.addColorStop(0, window.mauve.toString()); grad.addColorStop(1, window.pink.toString());
                                    ctx.lineWidth = window.s(14); ctx.beginPath(); ctx.arc(cX, cY, rad, 0, eA); ctx.strokeStyle = grad; ctx.stroke();
                                }
                            }
                            ColumnLayout {
                                anchors.centerIn: parent; spacing: 0
                                RowLayout {
                                    Layout.alignment: Qt.AlignHCenter; spacing: window.s(4)
                                    Text { font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(18); color: window.mauve; text: "󰍛" }
                                    Text { font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(28); color: window.text; text: Math.round(ramOrb.animVal) + "%" }
                                }
                                Text { Layout.alignment: Qt.AlignHCenter; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(12); color: window.subtext0; text: "MEMORY" }
                            }
                            MouseArea { id: ramMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor }
                        }

                        // 3. GPU Orb
                        Item {
                            id: gpuOrb; width: window.s(145); height: window.s(145)
                            property real animVal: window.gpuUsage
                            Behavior on animVal { NumberAnimation { duration: 1200; easing.type: Easing.OutQuint } }
                            onAnimValChanged: gpuCanvas.requestPaint()

                            scale: gpuMa.containsMouse ? 1.05 : 1.0
                            Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }

                            // Individual Aura - Fixed Overlap
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width + (gpuMa.containsMouse ? window.s(16) : window.s(4))
                                height: width; radius: width / 2
                                color: window.peach
                                opacity: gpuMa.containsMouse ? 0.25 : 0.08
                                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
                                Behavior on opacity { NumberAnimation { duration: 300 } }
                            }

                            Canvas {
                                id: gpuCanvas; anchors.fill: parent; rotation: 180
                                onPaint: {
                                    var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height);
                                    var cX = width/2; var cY = height/2; var rad = (width/2)-window.s(8);
                                    var eA = (Math.min(100, Math.max(0, parent.animVal)) / 100) * 2 * Math.PI;
                                    ctx.lineCap = "round"; ctx.lineWidth = window.s(8); ctx.beginPath(); ctx.arc(cX, cY, rad, 0, 2*Math.PI); 
                                    ctx.strokeStyle = window.surface0.toString(); ctx.stroke();
                                    var grad = ctx.createLinearGradient(0, height, width, 0); grad.addColorStop(0, window.peach.toString()); grad.addColorStop(1, window.yellow.toString());
                                    ctx.lineWidth = window.s(14); ctx.beginPath(); ctx.arc(cX, cY, rad, 0, eA); ctx.strokeStyle = grad; ctx.stroke();
                                }
                            }
                            ColumnLayout {
                                anchors.centerIn: parent; spacing: 0
                                RowLayout {
                                    Layout.alignment: Qt.AlignHCenter; spacing: window.s(4)
                                    Text { font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(18); color: window.peach; text: "󰍹" }
                                    Text { font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(28); color: window.text; text: Math.round(gpuOrb.animVal) + "%" }
                                }
                                Text { Layout.alignment: Qt.AlignHCenter; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(12); color: window.subtext0; text: "GPU LOAD" }
                            }
                            MouseArea { id: gpuMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor }
                        }

                        // 4. TEMP Orb
                        Item {
                            id: tempOrb; width: window.s(145); height: window.s(145)
                            property real animVal: window.sysTemp
                            Behavior on animVal { NumberAnimation { duration: 1200; easing.type: Easing.OutQuint } }
                            onAnimValChanged: tempCanvas.requestPaint()

                            scale: tempMa.containsMouse ? 1.05 : 1.0
                            Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }

                            // Individual Aura - Fixed Overlap
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width + (tempMa.containsMouse ? window.s(16) : window.s(4))
                                height: width; radius: width / 2
                                color: window.red
                                opacity: tempMa.containsMouse ? 0.25 : 0.08
                                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
                                Behavior on opacity { NumberAnimation { duration: 300 } }
                            }

                            Canvas {
                                id: tempCanvas; anchors.fill: parent; rotation: 180
                                onPaint: {
                                    var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height);
                                    var cX = width/2; var cY = height/2; var rad = (width/2)-window.s(8);
                                    var eA = (Math.min(100, Math.max(0, parent.animVal)) / 100) * 2 * Math.PI;
                                    ctx.lineCap = "round"; ctx.lineWidth = window.s(8); ctx.beginPath(); ctx.arc(cX, cY, rad, 0, 2*Math.PI); 
                                    ctx.strokeStyle = window.surface0.toString(); ctx.stroke();
                                    var grad = ctx.createLinearGradient(0, height, width, 0); grad.addColorStop(0, window.red.toString()); grad.addColorStop(1, window.maroon.toString());
                                    ctx.lineWidth = window.s(14); ctx.beginPath(); ctx.arc(cX, cY, rad, 0, eA); ctx.strokeStyle = grad; ctx.stroke();
                                }
                            }
                            ColumnLayout {
                                anchors.centerIn: parent; spacing: 0
                                RowLayout {
                                    Layout.alignment: Qt.AlignHCenter; spacing: window.s(4)
                                    Text { font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(18); color: window.red; text: "" }
                                    Text { font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(28); color: window.text; text: Math.round(tempOrb.animVal) + "°" }
                                }
                                Text { Layout.alignment: Qt.AlignHCenter; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(12); color: window.subtext0; text: "SYSTEM TEMP" }
                            }
                            MouseArea { id: tempMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor }
                        }
                    }

                    // ==========================================
                    // BOTTOM DOCKS
                    // ── Uptime circle — centered on performance orbs ──
                    Rectangle {
                        id: uptimeCircle
                        width: window.s(52); height: window.s(52)
                        radius: width / 2
                        color: window.surface0
                        border.color: window.surface1
                        border.width: 1
                        z: 5

                        // Center on the sysGrid
                        anchors.centerIn: sysGrid

                        opacity: introCore
                        scale: 0.5 + (0.5 * introCore)
                        Behavior on scale { NumberAnimation { duration: 600; easing.type: Easing.OutBack } }

                        // Subtle ambient glow
                        Rectangle {
                            anchors.fill: parent; radius: parent.radius
                            color: window.ambientPrimary; opacity: 0.06
                            Behavior on color { ColorAnimation { duration: 1000 } }
                        }

                        property int totalSecs: window.upHours * 3600 + window.upMins * 60
                        property int totalMins: window.upHours * 60 + window.upMins
                        property string uptimeVal: {
                            let s = totalSecs;
                            let m = totalMins;
                            let h = window.upHours;
                            let d = Math.floor(h / 24);
                            let w = Math.floor(d / 7);
                            let mo = Math.floor(d / 30);

                            if (mo >= 1) return mo.toString();
                            if (w >= 1)  return w.toString();
                            if (d >= 1)  return d.toString();
                            if (h >= 1)  return h.toString();
                            if (m >= 1)  return m.toString();
                            return s.toString();
                        }
                        property string uptimeUnit: {
                            let s = totalSecs;
                            let m = totalMins;
                            let h = window.upHours;
                            let d = Math.floor(h / 24);
                            let w = Math.floor(d / 7);
                            let mo = Math.floor(d / 30);

                            if (mo >= 1) return "MO";
                            if (w >= 1)  return "WK";
                            if (d >= 1)  return "DAY";
                            if (h >= 1)  return "HR";
                            if (m >= 1)  return "MIN";
                            return "SEC";
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: window.s(-2)

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: uptimeCircle.uptimeVal
                                font.family: "JetBrains Mono"
                                font.weight: Font.Black
                                font.pixelSize: window.s(16)
                                color: window.ambientPrimary
                                Behavior on color { ColorAnimation { duration: 1000 } }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: uptimeCircle.uptimeUnit
                                font.family: "JetBrains Mono"
                                font.weight: Font.Bold
                                font.pixelSize: window.s(8)
                                color: window.subtext0
                            }
                        }
                    }

                    // ==========================================
                    ColumnLayout {
                        id: bottomDocks
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: window.s(20)
                        anchors.bottomMargin: window.s(20)
                        spacing: window.s(15)

                        // 1. SYSTEM INFO
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: metricsGrid.implicitHeight + window.s(24)
                            radius: window.s(14)
                            color: window.surface0
                            border.color: window.surface1
                            border.width: 1

                            opacity: introProfiles
                            transform: Translate { y: window.s(20) * (1.0 - introProfiles) }

                            GridLayout {
                                id: metricsGrid
                                anchors {
                                    left: parent.left; right: parent.right; top: parent.top
                                    margins: window.s(12)
                                }
                                columns: 2
                                columnSpacing: window.s(14)
                                rowSpacing: window.s(3)

                                Repeater {
                                    model: [
                                        { icon: "󰒋", label: "os",      val: window.sysOs },
                                        { icon: "󰌽",  label: "kernel",  val: window.sysKernel },
                                        { icon: "󰏖", label: "pkgs",    val: window.sysPackages },
                                        { icon: "󰆍",  label: "shell",   val: window.sysShell },
                                        { icon: "󰻠", label: "cpu",     val: window.sysCpuName },
                                        { icon: "󰍹", label: "gpu",     val: window.sysGpu },
                                        { icon: "󰋊", label: "disk",    val: window.sysDiskStr },
                                        { icon: "󰟜", label: "res",     val: window.sysResolution },
                                        { icon: "󰖳", label: "wm",      val: window.sysWm },
                                        { icon: "󰗡", label: "locale",  val: window.sysLocale }
                                    ]
                                    delegate: RowLayout {
                                        spacing: window.s(6)
                                        Layout.fillWidth: true
                                        Text {
                                            text: modelData.icon
                                            font.family: "Iosevka Nerd Font"
                                            font.pixelSize: window.s(12)
                                            color: window.mauve
                                        }
                                        Text {
                                            text: modelData.label
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: window.s(10)
                                            font.weight: Font.Bold
                                            color: window.overlay1
                                            Layout.minimumWidth: window.s(50)
                                        }
                                        Text {
                                            text: modelData.val !== "" ? modelData.val : "…"
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: window.s(10)
                                            color: window.subtext0
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }

                        // 2. FOCUS MODE
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: window.s(58)
                            radius: window.s(14)
                            color: window.surface0
                            border.color: window.surface1
                            border.width: 1

                            opacity: introSliders
                            transform: Translate { y: window.s(20) * (1.0 - introSliders) }

                            // State: show mode selector when default OR timer is running,
                            // show time setter when mode just changed to gaming/study but not locked
                            property bool showTimeSetter: window.pendingFocusMode !== "" && window.focusEndEpoch <= 0

                            // ── Mode selector (gaming / default / study) ──
                            Rectangle {
                                id: modeSelector
                                anchors.fill: parent
                                anchors.margins: window.s(10)
                                radius: window.s(8)
                                color: window.surface1
                                border.color: window.surface2
                                border.width: 1
                                visible: !parent.showTimeSetter
                                opacity: visible ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 250 } }

                                Rectangle {
                                    width: (parent.width - window.s(2)) / 3
                                    height: parent.height - window.s(2)
                                    y: window.s(1)
                                    radius: window.s(7)
                                    x: {
                                        let m = window.pendingFocusMode !== "" ? window.pendingFocusMode : window.focusMode;
                                        if (m === "gaming") return window.s(1);
                                        if (m === "default") return width + window.s(1);
                                        return (width * 2) + window.s(1);
                                    }
                                    Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop {
                                            position: 0.0
                                            property string cm: window.pendingFocusMode !== "" ? window.pendingFocusMode : window.focusMode
                                            color: cm === "gaming" ? window.red : (cm === "study" ? window.green : window.blue)
                                            Behavior on color { ColorAnimation { duration: 400 } }
                                        }
                                        GradientStop {
                                            position: 1.0
                                            property string cm: window.pendingFocusMode !== "" ? window.pendingFocusMode : window.focusMode
                                            color: cm === "gaming" ? window.peach : (cm === "study" ? window.teal : window.sapphire)
                                            Behavior on color { ColorAnimation { duration: 400 } }
                                        }
                                    }
                                }

                                // Countdown + add time button when timer is active
                                Row {
                                    anchors.right: parent.right
                                    anchors.rightMargin: window.s(6)
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: window.focusCountdown !== ""
                                    spacing: window.s(4)
                                    z: 5

                                    Text {
                                        text: window.focusCountdown
                                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(10)
                                        color: window.focusMode === "gaming" ? window.red
                                             : (window.focusMode === "study" ? window.green : window.overlay1)
                                        Behavior on color { ColorAnimation { duration: 300 } }
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    // Add time button (study only)
                                    Rectangle {
                                        visible: window.focusMode === "study"
                                        width: window.s(22); height: window.s(22)
                                        radius: window.s(6)
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: addTimeMa.containsMouse ? window.surface0 : "transparent"
                                        border.color: addTimeMa.containsMouse ? window.green : "transparent"
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Behavior on border.color { ColorAnimation { duration: 150 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "+"
                                            font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(12)
                                            color: addTimeMa.containsMouse ? window.green : window.subtext0
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                        }
                                        MouseArea {
                                            id: addTimeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                // Add 15 minutes to the study timer
                                                window.focusEndEpoch = window.focusEndEpoch + 900;
                                                window.focusRemainSec = window.focusRemainSec + 900;
                                                Quickshell.execDetached(["bash", "-c",
                                                    "echo " + window.focusEndEpoch + " > ~/.cache/qs_focus_end"
                                                ]);
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent; spacing: 0
                                    Repeater {
                                        model: ListModel {
                                            ListElement { name: "gaming";  icon: "󰊴" }
                                            ListElement { name: "default"; icon: "󰗑" }
                                            ListElement { name: "study";   icon: "󰑴" }
                                        }
                                        delegate: Item {
                                            Layout.fillWidth: true; Layout.fillHeight: true
                                            Text {
                                                anchors.centerIn: parent
                                                font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(14)
                                                color: (window.pendingFocusMode !== "" ? window.pendingFocusMode : window.focusMode) === name ? window.crust : (fMa.containsMouse ? window.text : window.subtext0)
                                                text: icon
                                                Behavior on color { ColorAnimation { duration: 200 } }
                                            }
                                            MouseArea {
                                                id: fMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    // Block switching away from study mode while timer is running
                                                    if (window.focusMode === "study" && window.focusEndEpoch > 0 && name !== "study") return;

                                                    if (name === "default") {
                                                        window.focusMode = "default";
                                                        window.pendingFocusMode = "";
                                                        window.focusEndEpoch = 0;
                                                        window.focusRemainSec = 0;
                                                        Quickshell.execDetached(["bash", "-c",
                                                            "echo default > ~/.cache/qs_focus_mode; echo 0 > ~/.cache/qs_focus_end"
                                                        ]);
                                                    } else {
                                                        // Don't change mode yet — just show time setter
                                                        window.pendingFocusMode = name;
                                                        window.focusSetMins = 60;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Time setter (replaces mode selector) ──
                            RowLayout {
                                id: timeSetter
                                anchors.fill: parent
                                anchors.margins: window.s(10)
                                spacing: window.s(8)
                                visible: parent.showTimeSetter
                                opacity: visible ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 250 } }

                                // Minus
                                Rectangle {
                                    Layout.preferredWidth: window.s(44)
                                    Layout.fillHeight: true
                                    radius: window.s(8)
                                    color: minusMa.containsMouse ? window.surface1 : window.surface0
                                    border.color: minusMa.containsMouse ? window.surface2 : window.surface1
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Text {
                                        anchors.centerIn: parent; text: "-"
                                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(20)
                                        color: minusMa.containsMouse ? window.text : window.subtext0
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }
                                    MouseArea {
                                        id: minusMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: window.focusSetMins = Math.max(0, window.focusSetMins - 15)
                                    }
                                }

                                // Time display — click to lock in
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: window.s(8)
                                    color: lockMa.containsMouse ? window.surface1 : window.surface0
                                    border.color: lockMa.containsMouse
                                        ? (window.pendingFocusMode === "gaming" ? window.red : window.green)
                                        : window.surface1
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on border.color { ColorAnimation { duration: 200 } }

                                    property string timeStr: {
                                        if (window.focusSetMins <= 0) return "Cancel";
                                        let h = Math.floor(window.focusSetMins / 60);
                                        let m = window.focusSetMins % 60;
                                        return h + ":" + (m < 10 ? "0" : "") + m;
                                    }

                                    Row {
                                        anchors.centerIn: parent; spacing: window.s(8)
                                        Text {
                                            text: "󰥔"
                                            font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(16)
                                            color: window.pendingFocusMode === "gaming" ? window.red : window.green
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: parent.parent.timeStr
                                            font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(18)
                                            color: window.pendingFocusMode === "gaming" ? window.red : window.green
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                    MouseArea {
                                        id: lockMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (window.focusSetMins <= 0) {
                                                // Cancel — go back to default
                                                window.focusMode = "default";
                                                window.pendingFocusMode = "";
                                                window.focusEndEpoch = 0;
                                                window.focusRemainSec = 0;
                                                Quickshell.execDetached(["bash", "-c",
                                                    "echo default > ~/.cache/qs_focus_mode; echo 0 > ~/.cache/qs_focus_end"
                                                ]);
                                                return;
                                            }
                                            // Apply the pending mode and start timer
                                            window.focusMode = window.pendingFocusMode;
                                            let secs = window.focusSetMins * 60;
                                            let end = Math.floor(Date.now() / 1000) + secs;
                                            window.focusEndEpoch = end;
                                            window.focusRemainSec = secs;
                                            window.pendingFocusMode = "";
                                            Quickshell.execDetached(["bash", "-c",
                                                "echo " + window.focusMode + " > ~/.cache/qs_focus_mode; echo " + end + " > ~/.cache/qs_focus_end"
                                            ]);
                                        }
                                    }
                                }

                                // Plus
                                Rectangle {
                                    Layout.preferredWidth: window.s(44)
                                    Layout.fillHeight: true
                                    radius: window.s(8)
                                    color: plusMa.containsMouse ? window.surface1 : window.surface0
                                    border.color: plusMa.containsMouse ? window.surface2 : window.surface1
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Text {
                                        anchors.centerIn: parent; text: "+"
                                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(20)
                                        color: plusMa.containsMouse ? window.text : window.subtext0
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }
                                    MouseArea {
                                        id: plusMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: window.focusSetMins = Math.min(480, window.focusSetMins + 15)
                                    }
                                }
                            }
                        }

                        // 3. VOLUME DOCK
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: window.s(58)
                            radius: window.s(14)
                            color: window.surface0
                            border.color: window.surface1
                            border.width: 1

                            opacity: introSliders
                            transform: Translate { y: window.s(20) * (1.0 - introSliders) }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: window.s(14)
                                spacing: window.s(12)

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: window.s(15)

                                    Rectangle {
                                        Layout.preferredWidth: window.s(32)
                                        Layout.preferredHeight: window.s(32)
                                        radius: window.s(16)
                                        color: volIconMa.containsMouse ? window.surface1 : "transparent"
                                        border.color: volIconMa.containsMouse ? window.blue : "transparent"
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Behavior on border.color { ColorAnimation { duration: 150 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: window.sysMuted || window.sysVolume === 0 ? "󰖁" : (window.sysVolume > 50 ? "󰕾" : "󰖀")
                                            font.family: "Iosevka Nerd Font"
                                            font.pixelSize: window.s(22)
                                            color: window.sysMuted ? window.overlay0 : window.blue
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                        }
                                        MouseArea {
                                            id: volIconMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                volSyncDelay.stop();
                                                window.isDraggingVol = true;
                                                window.sysMuted = !window.sysMuted;
                                                Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
                                                volSyncDelay.restart();
                                            }
                                        }
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                        height: window.s(18)

                                        Timer {
                                            id: volCmdThrottle
                                            interval: 50
                                            property int targetPct: -1
                                            onTriggered: {
                                                if (targetPct >= 0) {
                                                    Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", targetPct + "%"]);
                                                    targetPct = -1;
                                                }
                                            }
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: window.s(9)
                                            color: window.surface1
                                            border.color: window.surface2
                                            border.width: 1
                                            clip: true

                                            Rectangle {
                                                height: parent.height
                                                width: parent.width * (window.sysVolume / 100)
                                                radius: window.s(9)
                                                opacity: volMa.containsMouse ? 1.0 : 0.85
                                                Behavior on opacity { NumberAnimation { duration: 200 } }
                                                Behavior on width { enabled: !window.isDraggingVol; NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }

                                                gradient: Gradient {
                                                    orientation: Gradient.Horizontal
                                                    GradientStop { position: 0.0; color: window.sysMuted ? window.surface2 : window.blue }
                                                    GradientStop { position: 1.0; color: window.sysMuted ? Qt.lighter(window.surface2, 1.15) : window.sapphire }
                                                }
                                            }
                                        }
                                        MouseArea {
                                            id: volMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onPressed: function(mouse) { volSyncDelay.stop(); window.isDraggingVol = true; updateVol(mouse.x); }
                                            onPositionChanged: function(mouse) { if (pressed) updateVol(mouse.x); }
                                            onReleased: { volSyncDelay.restart(); }

                                            function updateVol(mx) {
                                                let pct = Math.max(0, Math.min(100, Math.round((mx / width) * 100)));
                                                window.sysVolume = pct;
                                                volCmdThrottle.targetPct = pct;
                                                if (!volCmdThrottle.running) volCmdThrottle.start();
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 4. SYSTEM ACTIONS DOCK
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: window.s(75)
                            spacing: window.s(12)
                            
                            Repeater {
                                model: ListModel {
                                    ListElement { cmd: "XDG_CURRENT_DESKTOP=KDE systemsettings"; clickCmd: ""; icon: ""; baseColor: "red"; weight: 1.0 }
                                    ListElement { cmd: "bash $HOME/.config/hypr/scripts/valorant.sh"; clickCmd: ""; icon: "󰍲"; baseColor: "blue"; weight: 1.0 }
                                    ListElement { cmd: "systemctl reboot"; clickCmd: ""; icon: "󰑓"; baseColor: "yellow"; weight: 2.5 }
                                    ListElement { cmd: "hyprctl dispatch dpms off"; clickCmd: "hyprctl dispatch dpms off"; icon: "󰶐"; baseColor: "mauve"; weight: 1.0 }
                                }
                                
                                delegate: Rectangle {
                                    id: actionCapsule
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: window.s(14)

                                    opacity: introActions
                                    transform: Translate { y: window.s(30) * (1.0 - introActions) + (index * window.s(12) * (1.0 - introActions)) }
                                    
                                    property color c1: window[baseColor] || window.surface1
                                    property color c2: Qt.lighter(c1, 1.2)

                                    color: actionMa.containsMouse ? window.surface1 : window.surface0
                                    border.color: actionMa.containsMouse ? c1 : window.surface2
                                    border.width: actionMa.containsMouse ? 2 : 1
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Behavior on border.color { ColorAnimation { duration: 200 } }
                                    
                                    scale: actionMa.pressed ? (0.98 - (0.01 * weight)) : (actionMa.containsMouse ? 1.08 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutQuart } }

                                    property real fillLevel: 0.0
                                    property bool triggered: false
                                    property real flashOpacity: 0.0
                                    
                                    Canvas {
                                        id: actionWaveCanvas
                                        anchors.fill: parent
                                        
                                        property real wavePhase: 0.0
                                        NumberAnimation on wavePhase {
                                            running: actionCapsule.fillLevel > 0.0 && actionCapsule.fillLevel < 1.0
                                            loops: Animation.Infinite
                                            from: 0; to: Math.PI * 2; duration: 800
                                        }
                                        onWavePhaseChanged: requestPaint()
                                        Connections { target: actionCapsule; function onFillLevelChanged() { actionWaveCanvas.requestPaint() } }
                                        
                                        onPaint: {
                                            var ctx = getContext("2d");
                                            ctx.clearRect(0, 0, width, height);
                                            if (actionCapsule.fillLevel <= 0.001) return;
                                            
                                            var r = window.s(14); 
                                            var fillY = height * (1.0 - actionCapsule.fillLevel);
                                            ctx.save();
                                            ctx.beginPath();
                                            ctx.moveTo(r, 0); ctx.lineTo(width - r, 0); ctx.arcTo(width, 0, width, r, r);
                                            ctx.lineTo(width, height - r); ctx.arcTo(width, height, width - r, height, r);
                                            ctx.lineTo(r, height); ctx.arcTo(0, height, 0, height - r, r);
                                            ctx.lineTo(0, r); ctx.arcTo(0, 0, r, 0, r); ctx.closePath(); ctx.clip(); 
                                            
                                            ctx.beginPath();
                                            ctx.moveTo(0, fillY);
                                            if (actionCapsule.fillLevel < 0.99) {
                                                var waveAmp = window.s(10) * Math.sin(actionCapsule.fillLevel * Math.PI); 
                                                var cp1y = fillY + Math.sin(wavePhase) * waveAmp;
                                                var cp2y = fillY + Math.cos(wavePhase + Math.PI) * waveAmp;
                                                ctx.bezierCurveTo(width * 0.33, cp2y, width * 0.66, cp1y, width, fillY);
                                                ctx.lineTo(width, height); ctx.lineTo(0, height);
                                            } else {
                                                ctx.lineTo(width, 0); ctx.lineTo(width, height); ctx.lineTo(0, height);
                                            }
                                            ctx.closePath();
                                            
                                            var grad = ctx.createLinearGradient(0, 0, 0, height);
                                            grad.addColorStop(0, actionCapsule.c1.toString()); grad.addColorStop(1, actionCapsule.c2.toString());
                                            ctx.fillStyle = grad; ctx.fill(); ctx.restore();
                                        }
                                    }

                                    Rectangle {
                                        anchors.fill: parent; radius: window.s(14); color: "#ffffff"
                                        opacity: actionCapsule.flashOpacity
                                        PropertyAnimation on opacity { id: cardFlashAnim; to: 0; duration: 500; easing.type: Easing.OutExpo }
                                    }

                                    Text { 
                                        anchors.centerIn: parent
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: window.s(24)
                                        color: actionMa.containsMouse ? window.text : window.subtext0
                                        text: icon
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }

                                    Item {
                                        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                        height: actionCapsule.height * actionCapsule.fillLevel
                                        clip: true
                                        
                                        Text { 
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            y: (actionCapsule.height / 2) - (height / 2) - (actionCapsule.height - parent.height)
                                            font.family: "Iosevka Nerd Font"
                                            font.pixelSize: window.s(24)
                                            color: window.crust
                                            text: icon 
                                        }
                                    }

                                    MouseArea {
                                        id: actionMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: actionCapsule.triggered ? Qt.ArrowCursor : Qt.PointingHandCursor
                                        
                                        onPressed: { 
                                            if (!actionCapsule.triggered) { 
                                                drainAnim.stop(); 
                                                fillAnim.start(); 
                                            }
                                        }
                                        onReleased: {
                                            if (!actionCapsule.triggered && actionCapsule.fillLevel < 1.0) { 
                                                fillAnim.stop();
                                                // Quick tap: if clickCmd exists and fill barely started, run it
                                                if (clickCmd !== "" && actionCapsule.fillLevel < 0.3) {
                                                    Quickshell.execDetached(["sh", "-c", clickCmd]);
                                                }
                                                drainAnim.start(); 
                                            }
                                        }
                                    }

                                    NumberAnimation {
                                        id: fillAnim; target: actionCapsule; property: "fillLevel"; to: 1.0
                                        duration: (550 * weight) * (1.0 - actionCapsule.fillLevel); easing.type: Easing.InSine
                                        onFinished: {
                                            actionCapsule.triggered = true; actionCapsule.flashOpacity = 0.6; cardFlashAnim.start();
                                            exitAnim.start(); exitTimer.start();
                                        }
                                    }
                                    
                                    NumberAnimation {
                                        id: drainAnim; target: actionCapsule; property: "fillLevel"; to: 0.0
                                        duration: 1500 * actionCapsule.fillLevel; easing.type: Easing.OutQuad
                                    }

                                    Timer {
                                        id: exitTimer; interval: 500 
                                        onTriggered: { Quickshell.execDetached(["sh", "-c", cmd]); Quickshell.execDetached(["sh", "-c", "echo 'close' > /tmp/qs_widget_state"]); }
                                    }
                                }
                            }
                        }


                    }
                }
            }
        }
    }
}
