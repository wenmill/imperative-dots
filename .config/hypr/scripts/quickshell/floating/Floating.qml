import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../"

Variants {
    model: Quickshell.screens

    delegate: Component {
        PanelWindow {
            id: floatingWidget
            required property var modelData
            screen: modelData

            WlrLayershell.namespace: "qs-floating-overlay"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore 
            color: "transparent"
            
            focusable: isSidebarVisible && (!isPinned || (typeof mainHoverTracker !== "undefined" && mainHoverTracker.hovered))

            // =========================================================
            // --- FULL SCREEN LAYOUT & TOPBAR CLEARANCE
            // =========================================================
            anchors {
                top: false; bottom: true; left: true; right: true
            }
            implicitHeight: floatingWidget.screen.height - 60

            // =========================================================
            // --- FOCUS TRACKING (FALLBACK CLOSER)
            // =========================================================
            Item {
                id: focusTracker
                focus: true
                onActiveFocusChanged: {
                    if (!activeFocus && !floatingWidget.isPinned) {
                        floatingWidget.isExpanded = false;
                        hideTimer.restart(); 
                    }
                }
            }

            // =========================================================
            // --- STATE LOGIC
            // =========================================================
            property bool isPinned: false 
            property bool useGraceTimer: false // Tracks if the 3s drag grace period is active
            
            onIsPinnedChanged: {
                if (!isPinned) kickTimer();
            }

            property int hoveredBars: 0

            // =========================================================
            // --- MODULE CONFIGURATION
            // ---------------------------------------------------------
            // One shared content module (the AI popup), driven across three
            // MODES by the active tab: chat, notes, learn. The selector shows
            // three pills; switching a pill sets the module's activeMode rather
            // than swapping the module out.
            // =========================================================
            property var tabModules: [ "FloatingContent.qml" ]
            property var tabModes: [ "chat", "notes", "learn" ]
            property int tabCount: tabModes.length

            // Push the selected mode into the loaded module.
            function _syncFloatingMode() {
                if (typeof moduleRepeater === "undefined") return;
                let loader = moduleRepeater.itemAt(0);
                if (loader && loader.status === Loader.Ready && loader.item) {
                    let m = tabModes[Math.max(0, Math.min(tabModes.length - 1, activeIndex))];
                    loader.item.activeMode = m;
                }
            }
            onActiveIndexChanged: _syncFloatingMode()

            // =========================================================
            // --- IPC CONTROLS
            // =========================================================
            IpcHandler {
                target: "floating"

                function setIndex(idx: string) {
                    let newIdx = parseInt(idx);
                    if (!isNaN(newIdx) && newIdx >= 0 && newIdx < floatingWidget.tabCount) {
                        floatingWidget.activeIndex = newIdx;
                    }
                }

                function forceReload() {
                    Quickshell.reload(true) 
                }
            }

            // =========================================================
            // --- UNIVERSAL SHORTCUT ROUTER
            // =========================================================
            function childIntercepts(sequenceStr) {
                // If not expanded, parent always keeps control
                if (!isExpanded) return false; 

                if (typeof moduleRepeater !== "undefined" && activeIndex >= 0 && activeIndex < moduleRepeater.count) {
                    let loader = moduleRepeater.itemAt(activeIndex);
                    
                    if (loader && loader.status === Loader.Ready && loader.item) {
                        // Check if the child has exposed a list of shortcuts it wants to steal
                        if (loader.item.interceptedShortcuts !== undefined) {
                            return loader.item.interceptedShortcuts.includes(sequenceStr);
                        }
                    }
                }
                return false; // Safe default: parent retains the shortcut
            }

            // =========================================================
            // --- KEYBOARD SHORTCUTS & ACTIVITY TRACKER
            // =========================================================
            function kickTimer() {
                if (!isPinned) {
                    if ((typeof mainHoverTracker !== "undefined" && mainHoverTracker.hovered) ||
                        (typeof sidebarDragArea !== "undefined" && (sidebarDragArea.containsMouse || sidebarDragArea.pressed)) ||
                        (typeof gridMouseArea !== "undefined" && (gridMouseArea.containsMouse || gridMouseArea.pressed)) ||
                        (typeof peekMouse !== "undefined" && (peekMouse.containsMouse || peekMouse.pressed)) ||
                        (typeof pinMouse !== "undefined" && pinMouse.containsMouse) ||
                        (typeof expandMouse !== "undefined" && expandMouse.containsMouse) ||
                        floatingWidget.hoveredBars > 0) {
                        return;
                    }
                    hideTimer.restart();
                }
            }

            Shortcut { enabled: floatingWidget.isSidebarVisible && !floatingWidget.childIntercepts("Tab"); sequence: "Tab"; onActivated: { floatingWidget.activeIndex = (floatingWidget.activeIndex + 1) % floatingWidget.tabCount; floatingWidget.kickTimer(); } }
            Shortcut { enabled: floatingWidget.isSidebarVisible && !floatingWidget.childIntercepts("Shift+Tab"); sequence: "Shift+Tab"; onActivated: { floatingWidget.activeIndex = (floatingWidget.activeIndex + (floatingWidget.tabCount - 1)) % floatingWidget.tabCount; floatingWidget.kickTimer(); } }
            Shortcut { enabled: floatingWidget.isSidebarVisible && !floatingWidget.childIntercepts("Return"); sequence: "Return"; onActivated: { floatingWidget.isExpanded = !floatingWidget.isExpanded; floatingWidget.kickTimer(); } }
            Shortcut { enabled: floatingWidget.isSidebarVisible && !floatingWidget.childIntercepts("Enter"); sequence: "Enter"; onActivated: { floatingWidget.isExpanded = !floatingWidget.isExpanded; floatingWidget.kickTimer(); } }
            
            Shortcut { 
                enabled: floatingWidget.isSidebarVisible && floatingWidget.activeEdge === "bottom" && !floatingWidget.childIntercepts("Left")
                sequence: "Left"
                onActivated: { floatingWidget.activeIndex = Math.max(0, floatingWidget.activeIndex - 1); floatingWidget.kickTimer(); } 
            }
            Shortcut { 
                enabled: floatingWidget.isSidebarVisible && floatingWidget.activeEdge === "bottom" && !floatingWidget.childIntercepts("Right")
                sequence: "Right"
                onActivated: { floatingWidget.activeIndex = Math.min(floatingWidget.tabCount - 1, floatingWidget.activeIndex + 1); floatingWidget.kickTimer(); } 
            }
            Shortcut { 
                enabled: floatingWidget.isSidebarVisible && (floatingWidget.activeEdge === "left" || floatingWidget.activeEdge === "right") && !floatingWidget.childIntercepts("Up")
                sequence: "Up"
                onActivated: { 
                    let step = floatingWidget.activeEdge === "right" ? 1 : -1;
                    floatingWidget.activeIndex = Math.max(0, Math.min(floatingWidget.tabCount - 1, floatingWidget.activeIndex + step)); 
                    floatingWidget.kickTimer(); 
                } 
            }
            Shortcut { 
                enabled: floatingWidget.isSidebarVisible && (floatingWidget.activeEdge === "left" || floatingWidget.activeEdge === "right") && !floatingWidget.childIntercepts("Down")
                sequence: "Down"
                onActivated: { 
                    let step = floatingWidget.activeEdge === "right" ? -1 : 1;
                    floatingWidget.activeIndex = Math.max(0, Math.min(floatingWidget.tabCount - 1, floatingWidget.activeIndex + step)); 
                    floatingWidget.kickTimer(); 
                } 
            }

            Shortcut { 
                enabled: floatingWidget.isSidebarVisible && !floatingWidget.childIntercepts("Escape")
                sequence: "Escape"
                onActivated: {
                    if (floatingWidget.isExpanded) {
                        floatingWidget.isExpanded = false;
                        floatingWidget.kickTimer();
                    } else if (!floatingWidget.isPinned) {
                        floatingWidget.isSidebarVisible = false;
                        floatingWidget.isPeekVisible = true;
                        peekHideTimer.restart();
                    }
                }
            }

            // =========================================================
            // --- SCALER & THEMING
            // =========================================================
            Scaler {
                id: scaler
                currentWidth: floatingWidget.screen.width
                currentHeight: floatingWidget.screen.height
            }

            property real baseScale: scaler.baseScale
            function s(val) { 
                let res = scaler.s(val); 
                return isNaN(res) ? val : res; 
            }

            MatugenColors { id: mocha }

            // =========================================================
            // --- DYNAMIC LAYOUT LOGIC
            // =========================================================
            property int activeIndex: 0 
            property bool isExpanded: false 
            // Latched true once the module has been expanded; stays true through the
            // close-collapse so the panel keeps its CENTERED position and slides straight
            // out to the edge (instead of travelling back to the grab point). Cleared only
            // when fully hidden.
            property bool keepCentered: false
            onIsExpandedChanged: if (isExpanded) keepCentered = true;
            onIsSidebarVisibleChanged: if (!isSidebarVisible) keepCentered = false;

            property var currentLayoutTemplate: [{x: 0, y: 0, w: 1, h: 1}]

            function evaluateDrag(gpStartX, gpStartY, gpMouseX, gpMouseY) {
                let delta = 0;
                if (activeEdge === "left") delta = gpMouseX - gpStartX;
                else if (activeEdge === "right") delta = gpStartX - gpMouseX;
                else if (activeEdge === "bottom") delta = gpStartY - gpMouseY;

                if (delta > s(30) && !isExpanded) {
                    isExpanded = true;
                } else if (delta < -s(30) && (isExpanded || isSidebarVisible)) {
                    isExpanded = false;
                    if (!isPinned) {
                        isSidebarVisible = false;
                        isPeekVisible = true;
                        peekHideTimer.restart(); 
                    }
                }
            }
            
            property real h_in: s(32) 
            property real h_ac: s(112)
            property real itemSpacing: s(10)

            property real buttonSize: s(19)
            property real controlAreaHeight: buttonSize * 2 + s(14)

            property real barOffsetY: (activeEdge === "left" || activeEdge === "bottom") ? (controlAreaHeight + itemSpacing) : 0

            function getTargetY(idx, activeIdx) {
                let y = 0;
                for (let i = 0; i < idx; i++) {
                    y += (i === activeIdx ? h_ac : h_in) + itemSpacing;
                }
                return y;
            }

            // =========================================================
            // --- SYNCHRONIZED MORPH PROGRESS
            // =========================================================
            property real baseExpandedWidth: s(378)
            property real baseExpandedExtraLength: s(224)
            // Local, always-notifiable source of truth for the bottom dock's dragged
            // height (Config is a shared singleton whose change signal we can't rely on
            // from here). The drag writes this live; updateSizes reads it; a change here
            // re-runs the sizing. Seeded from Config on load, persisted back on release.
            property real userBottomHeight: 0
            // The currently-loaded module item, published from inside the Repeater
            // delegate (whose `contentLoader` id isn't visible to siblings like the
            // relocated bottom header). Anything outside the delegate reads this.
            property var currentModuleItem: null
            property real expandedPadding: s(15)
            
            property real targetExpandedExtraLength: baseExpandedExtraLength

            property real expandedWidth: baseExpandedWidth
            property real expandedExtraLength: baseExpandedExtraLength

            Behavior on expandedWidth { enabled: !floatingWidget.disableAnim; NumberAnimation { duration: 450; easing.type: Easing.OutQuart } }
            Behavior on expandedExtraLength { enabled: !floatingWidget.disableAnim; NumberAnimation { duration: 450; easing.type: Easing.OutQuart } }

            property real expandProgress: isExpanded ? 1.0 : 0.0
            Behavior on expandProgress { 
                enabled: !floatingWidget.disableAnim
                NumberAnimation { duration: 450; easing.type: Easing.OutQuart } 
            }

            property real visibleProgress: isSidebarVisible ? 1.0 : 0.0
            Behavior on visibleProgress { 
                enabled: !floatingWidget.disableAnim
                NumberAnimation { duration: 300; easing.type: Easing.OutExpo } 
            }

            property real currentExtraWidth: (expandedWidth + expandedPadding) * expandProgress
            property real currentExtraLength: expandedExtraLength * expandProgress
            
            property real totalSidebarWidth: s(35) + currentExtraWidth

            // =========================================================
            // --- PRECISE MATHEMATICAL WAYLAND INPUT MASK
            // =========================================================
	    property var activeMaskAABB: {
		if (!floatingWidget.isSidebarVisible) return Qt.rect(0, 0, 0, 0);
                // New model: the container IS the panel (panelW × panelH), positioned at
                // sidebarContainer.x/y, never rotated. So the interactive region is simply
                // that rectangle plus a small buffer — no per-rotation math needed.
                let buffer = floatingWidget.s(15);
                return Qt.rect(
                    sidebarContainer.x - buffer,
                    sidebarContainer.y - buffer,
                    sidebarContainer.width + buffer * 2,
                    sidebarContainer.height + buffer * 2
                );
            }

            mask: Region {
                Region { x: 0; y: 0; width: 1; height: floatingWidget.height }
                Region { x: floatingWidget.width - 1; y: 0; width: 1; height: floatingWidget.height }
                Region { x: 0; y: floatingWidget.height - 1; width: floatingWidget.width; height: 1 }

                Region {
                    x: floatingWidget.isPeekVisible ? peekBar.x - floatingWidget.s(15) : 0
                    y: floatingWidget.isPeekVisible ? peekBar.y - floatingWidget.s(15) : 0
                    width: floatingWidget.isPeekVisible ? peekBar.width + floatingWidget.s(30) : 0
                    height: floatingWidget.isPeekVisible ? peekBar.height + floatingWidget.s(30) : 0
                }

                Region {
                    x: floatingWidget.isSidebarVisible ? floatingWidget.activeMaskAABB.x : 0
                    y: floatingWidget.isSidebarVisible ? floatingWidget.activeMaskAABB.y : 0
                    width: floatingWidget.isSidebarVisible ? floatingWidget.activeMaskAABB.width : 0
                    height: floatingWidget.isSidebarVisible ? floatingWidget.activeMaskAABB.height : 0
                }
            }

            // =========================================================
            // --- CLAMPED CENTERING LOGIC
            // =========================================================
            function safeClamp(pos, size, margin) {
                let minCenter = margin;
                let maxCenter = size - margin;
                if (minCenter <= maxCenter) {
                    return Math.max(minCenter, Math.min(maxCenter, pos));
                } else {
                    let ratio = Math.max(0, Math.min(1, pos / size));
                    return minCenter + ratio * (maxCenter - minCenter); 
                }
            }

            property real targetEdgeMargin: {
                let length = baseSidebarH;
                if (isExpanded) {
                    length += targetExpandedExtraLength;
                }
                return (length / 2) + s(5);
            }

            // Horizontal clamp margin for the BOTTOM edge: the panel's horizontal extent is
            // its width, so use panelW/2 (not the vertical length) to keep it on-screen while
            // staying as close to the grab point as possible.
            property real targetEdgeMarginX: (panelW / 2) + s(5)

            property real clampedCenterX: safeClamp(currentPos, floatingWidget.width,
                activeEdge === "bottom" ? targetEdgeMarginX : targetEdgeMargin)
            property real clampedCenterY: safeClamp(currentPos, floatingWidget.height, targetEdgeMargin)

            // =========================================================
            // --- EDGE TRANSITION STATE MACHINE
            // =========================================================
            property string pendingEdge: ""
            property real pendingPos: 0
            property bool pendingWasExpanded: false
            property string pendingMode: "" 

            Timer {
                id: edgeTransitionTimer
                interval: 350
                onTriggered: {
                    floatingWidget.disableAnim = true;
                    floatingWidget.activeEdge = floatingWidget.pendingEdge;
                    floatingWidget.currentPos = floatingWidget.pendingPos;
                    teleportTimer.restart();
                }
            }

            Timer {
                id: teleportTimer
                interval: 32 
                onTriggered: {
                    floatingWidget.disableAnim = false;
                    if (floatingWidget.pendingMode === "sidebar") {
                        floatingWidget.isSidebarVisible = true;
                        floatingWidget.isExpanded = floatingWidget.pendingWasExpanded;
                        floatingWidget.isPeekVisible = false;
                        hideTimer.restart();
                    } else if (floatingWidget.pendingMode === "peek") {
                        floatingWidget.isPeekVisible = true;
                        floatingWidget.isSidebarVisible = false;
                        floatingWidget.isExpanded = false;
                    }
                    floatingWidget.pendingMode = "";
                }
            }

            // =========================================================
            // --- SLIDE-IN POPUP LOGIC & DYNAMIC HEIGHT SCALING
            // =========================================================
            property bool isSidebarVisible: false
            property bool isPeekVisible: false
            property bool disableAnim: false
            
            property string activeEdge: "left"
            property real currentPos: 0

            property real baseSidebarH: {
                let count = floatingWidget.tabCount;
                let activeTabH = count > 0 ? floatingWidget.h_ac : 0;
                let inactiveTabsH = Math.max(0, count - 1) * floatingWidget.h_in;
                let tabsSpacing = Math.max(0, count - 1) * floatingWidget.itemSpacing;
                
                let controlSpacing = count > 0 ? floatingWidget.itemSpacing : 0;
                let margins = floatingWidget.s(16); 
                
                return floatingWidget.controlAreaHeight + controlSpacing + activeTabH + inactiveTabsH + tabsSpacing + margins;
            }

            property real sidebarW: s(35)
            
            // ── UNIFIED PANEL GEOMETRY (container-upright model) ──────────────
            // The container never rotates. The panel (morphOrigin) holds the module
            // flush against the screen edge and the selector strip flush on the inner
            // side. These two dims describe the panel's full on-screen footprint.
            //   left/right : panelW = strip + module width ; panelH = module height
            //   bottom     : panelW = module width         ; panelH = strip + module height
            property real panelW: activeEdge === "bottom"
                ? Math.max(currentExtraWidth, baseSidebarH)
                : (sidebarW + currentExtraWidth)
            property real panelH: activeEdge === "bottom"
                ? (sidebarW + currentExtraLength)
                : (baseSidebarH + currentExtraLength)

            // Collapsed (peek): the selector sits where you grabbed the edge.
            // Expanded (or closing from expanded): the panel is centered on the screen edge
            // and slides STRAIGHT out to the edge on close — no travel back to the grab point.
            property real sidebarTargetX: {
                if (activeEdge === "left")   return 0;                                  // module on left edge
                if (activeEdge === "right")  return floatingWidget.width - panelW;       // module on right edge
                if (activeEdge === "bottom")
                    return clampedCenterX - panelW / 2;                                  // stay where grabbed (no centering)
                return 0;
            }

            property real sidebarTargetY: {
                if (activeEdge === "left" || activeEdge === "right")
                    return (floatingWidget.isExpanded || floatingWidget.keepCentered)
                        ? (floatingWidget.height - panelH) / 2                            // centered when open/closing
                        : (clampedCenterY - panelH / 2);                                 // grab point when collapsed
                if (activeEdge === "bottom")
                    return floatingWidget.height - floatingWidget.s(6) - panelH;          // bottom edge, 6px gap
                return 0;
            }

            property real targetRotation: 0   // container never rotates (upright model)

            function showPeek(edge, pos) {
                if (isPinned || isSidebarVisible || pendingMode === "sidebar") return;

                if (activeEdge !== edge) {
                    if (isPeekVisible || edgeTransitionTimer.running) {
                        pendingEdge = edge;
                        pendingPos = pos;
                        pendingMode = "peek";
                        
                        if (!edgeTransitionTimer.running) {
                            isPeekVisible = false;
                            edgeTransitionTimer.restart();
                        }
                    } else {
                        disableAnim = true;
                        activeEdge = edge;
                        currentPos = pos;
                        pendingMode = "peek";
                        teleportTimer.restart();
                    }
                    return;
                } else {
                    if (edgeTransitionTimer.running) {
                        edgeTransitionTimer.stop();
                        pendingMode = "";
                    }
                }

                currentPos = pos;
                isPeekVisible = true;
                peekHideTimer.stop();
            }

            function showSidebar(edge, pos) {
                if (isPinned) return;

                if (activeEdge !== edge) {
                    if (isSidebarVisible || isExpanded || edgeTransitionTimer.running) {
                        pendingEdge = edge;
                        pendingPos = pos;
                        pendingMode = "sidebar";
                        
                        if (!edgeTransitionTimer.running) {
                            pendingWasExpanded = isExpanded;
                            isExpanded = false;
                            isSidebarVisible = false;
                            isPeekVisible = false;
                            edgeTransitionTimer.restart();
                        }
                    } else {
                        disableAnim = true;
                        activeEdge = edge;
                        currentPos = pos;
                        pendingMode = "sidebar";
                        pendingWasExpanded = false;
                        teleportTimer.restart(); 
                    }
                    return; 
                } else {
                    if (edgeTransitionTimer.running) {
                        edgeTransitionTimer.stop();
                        if (pendingMode === "sidebar") {
                            isExpanded = pendingWasExpanded;
                        }
                        pendingMode = "";
                    }
                }

                currentPos = pos;
                isSidebarVisible = true;
                isPeekVisible = false;
                hideTimer.restart();
            }

            Timer {
                id: peekHideTimer
                interval: 50
                onTriggered: {
                    if (typeof peekMouse !== "undefined" && peekMouse.pressed) {
                        peekHideTimer.restart();
                        return;
                    }
                    if (!peekMouse.containsMouse && 
                        !leftEdge.containsMouse && !rightEdge.containsMouse && !bottomEdge.containsMouse) {
                        floatingWidget.isPeekVisible = false;
                    }
                }
            }

            Timer {
                id: hideTimer
                interval: floatingWidget.useGraceTimer ? 3000 : 800 // 3 seconds if drag was just happening, else 800ms
                onTriggered: {
                    if (floatingWidget.isPinned) return;

                    if ((typeof sidebarDragArea !== "undefined" && sidebarDragArea.pressed) || 
                        (typeof peekMouse !== "undefined" && peekMouse.pressed) ||
                        (typeof gridMouseArea !== "undefined" && gridMouseArea.pressed)) {
                        hideTimer.restart();
                        return;
                    }

                    // Sequenced close: collapse the module FIRST, then close the tab
                    // (selector) once the collapse animation has played.
                    if (floatingWidget.isExpanded) {
                        floatingWidget.isExpanded = false;
                        closeTabTimer.restart();
                    } else {
                        floatingWidget.isSidebarVisible = false;
                    }
                    floatingWidget.useGraceTimer = false; // Reset grace state when finally hidden
                }
            }

            // Fires after the module collapse animation so the tab/selector closes
            // SECOND (module first, then tab). If the user re-opens or hovers back in
            // the meantime, it aborts.
            Timer {
                id: closeTabTimer
                interval: 470   // slightly longer than the 450ms expand/collapse animation
                onTriggered: {
                    if (floatingWidget.isPinned || floatingWidget.isExpanded) return;
                    // Don't close if the pointer came back over the panel.
                    if ((typeof mainHoverTracker !== "undefined" && mainHoverTracker.hovered) ||
                        floatingWidget.hoveredBars > 0) {
                        return;
                    }
                    floatingWidget.isSidebarVisible = false;
                }
            }

            Timer {
                id: peekShowTimer
                interval: 300
                property string pendingShowEdge: ""
                property real pendingShowPos: 0
                onTriggered: {
                    // Approaching the edge now reveals the SELECTOR strip directly (no thin
                    // peek bar / no first click). Same appear-on-approach mechanics as the
                    // peek bar had, just showing the selector instead.
                    floatingWidget.showSidebar(pendingShowEdge, pendingShowPos);
                }
            }

            // =========================================================
            // --- EDGE TRIGGERS
            // =========================================================
            Item {
                id: mainHitArea 
                anchors.fill: parent

                MouseArea {
                    id: leftEdge
                    x: 0; y: 0; width: floatingWidget.s(12); height: floatingWidget.height   // proximity zone (was 1px)
                    hoverEnabled: true
                    onEntered: { 
                        peekHideTimer.stop(); 
                        if (floatingWidget.isSidebarVisible || floatingWidget.pendingMode === "sidebar") { 
                            floatingWidget.showSidebar("left", mouseY + y); 
                        } else if (floatingWidget.isPeekVisible) {
                            floatingWidget.showPeek("left", mouseY + y);
                        } else {
                            peekShowTimer.pendingShowEdge = "left";
                            peekShowTimer.pendingShowPos = mouseY + y;
                            peekShowTimer.restart();
                        }
                    }
                    onPositionChanged: mouse => { 
                        if (floatingWidget.isSidebarVisible || floatingWidget.pendingMode === "sidebar") { 
                            floatingWidget.showSidebar("left", mouse.y + y); 
                        } else if (floatingWidget.isPeekVisible) {
                            floatingWidget.showPeek("left", mouse.y + y);
                        } else {
                            peekShowTimer.pendingShowPos = mouse.y + y;
                        }
                    }
                    onExited: {
                        peekShowTimer.stop();
                        peekHideTimer.restart();
                    }
                }

                MouseArea {
                    id: rightEdge
                    x: floatingWidget.width - floatingWidget.s(12); y: 0; width: floatingWidget.s(12); height: floatingWidget.height
                    hoverEnabled: true
                    onEntered: { 
                        peekHideTimer.stop(); 
                        if (floatingWidget.isSidebarVisible || floatingWidget.pendingMode === "sidebar") { 
                            floatingWidget.showSidebar("right", mouseY + y); 
                        } else if (floatingWidget.isPeekVisible) {
                            floatingWidget.showPeek("right", mouseY + y);
                        } else {
                            peekShowTimer.pendingShowEdge = "right";
                            peekShowTimer.pendingShowPos = mouseY + y;
                            peekShowTimer.restart();
                        }
                    }
                    onPositionChanged: mouse => { 
                        if (floatingWidget.isSidebarVisible || floatingWidget.pendingMode === "sidebar") { 
                            floatingWidget.showSidebar("right", mouse.y + y); 
                        } else if (floatingWidget.isPeekVisible) {
                            floatingWidget.showPeek("right", mouse.y + y);
                        } else {
                            peekShowTimer.pendingShowPos = mouse.y + y;
                        }
                    }
                    onExited: {
                        peekShowTimer.stop();
                        peekHideTimer.restart();
                    }
                }

                MouseArea {
                    id: bottomEdge
                    x: 0; y: floatingWidget.height - floatingWidget.s(12); width: floatingWidget.width; height: floatingWidget.s(12)
                    hoverEnabled: true
                    onEntered: { 
                        peekHideTimer.stop(); 
                        if (floatingWidget.isSidebarVisible || floatingWidget.pendingMode === "sidebar") { 
                            floatingWidget.showSidebar("bottom", mouseX + x); 
                        } else if (floatingWidget.isPeekVisible) {
                            floatingWidget.showPeek("bottom", mouseX + x);
                        } else {
                            peekShowTimer.pendingShowEdge = "bottom";
                            peekShowTimer.pendingShowPos = mouseX + x;
                            peekShowTimer.restart();
                        }
                    }
                    onPositionChanged: mouse => { 
                        if (floatingWidget.isSidebarVisible || floatingWidget.pendingMode === "sidebar") { 
                            floatingWidget.showSidebar("bottom", mouse.x + x); 
                        } else if (floatingWidget.isPeekVisible) {
                            floatingWidget.showPeek("bottom", mouse.x + x);
                        } else {
                            peekShowTimer.pendingShowPos = mouse.x + x;
                        }
                    }
                    onExited: {
                        peekShowTimer.stop();
                        peekHideTimer.restart();
                    }
                }
            }

            // =========================================================
            // --- FLOATING PEEK BAR (DRAG HANDLE)
            // =========================================================
            Rectangle {
                id: peekBar
                // 10px smaller on each side = 20px total subtraction
                width: floatingWidget.activeEdge === "bottom" ? Math.max(floatingWidget.s(20), floatingWidget.baseSidebarH - floatingWidget.s(20)) : floatingWidget.s(12)
                height: floatingWidget.activeEdge === "bottom" ? floatingWidget.s(12) : Math.max(floatingWidget.s(20), floatingWidget.baseSidebarH - floatingWidget.s(20))
                radius: floatingWidget.s(6)
                
                color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 1.0)
                border.width: 0
                
                opacity: (floatingWidget.isPeekVisible && !floatingWidget.isSidebarVisible) ? (peekMouse.containsMouse || peekMouse.pressed ? 1.0 : 0.6) : 0.0
                scale: floatingWidget.isPeekVisible ? 1.0 : 0.6
                
                Behavior on opacity { NumberAnimation { duration: 250 } }
                Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }

                property real visualDragOffset: {
                    if (!peekMouse.pressed) return 0;
                    return Math.max(-floatingWidget.s(15), Math.min(peekMouse.currentDragDelta, floatingWidget.s(15))); 
                }

                x: {
                    let offscreen = 0, visibleX = 0;
                    if (floatingWidget.activeEdge === "left") {
                        offscreen = -width - floatingWidget.s(10);
                        visibleX = floatingWidget.s(3);   // small margin from edge 
                        return (floatingWidget.isPeekVisible ? visibleX : offscreen) + visualDragOffset;
                    }
                    if (floatingWidget.activeEdge === "right") {
                        offscreen = floatingWidget.width + floatingWidget.s(10);
                        visibleX = floatingWidget.width - width - floatingWidget.s(3);   // small margin 
                        return (floatingWidget.isPeekVisible ? visibleX : offscreen) - visualDragOffset;
                    }
                    if (floatingWidget.activeEdge === "bottom") return clampedCenterX - width / 2;
                    return 0;
                }

                y: {
                    let offscreen = 0, visibleY = 0;
                    if (floatingWidget.activeEdge === "bottom") {
                        offscreen = floatingWidget.height + floatingWidget.s(10);
                        visibleY = floatingWidget.height - height - floatingWidget.s(3);   // small margin 
                        return (floatingWidget.isPeekVisible ? visibleY : offscreen) - visualDragOffset;
                    }
                    if (floatingWidget.activeEdge === "left" || floatingWidget.activeEdge === "right") return clampedCenterY - height / 2;
                    return 0;
                }

                Behavior on x { enabled: !floatingWidget.disableAnim && !peekMouse.pressed; NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
                Behavior on y { enabled: !floatingWidget.disableAnim && !peekMouse.pressed; NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }

                Rectangle {
                    anchors.centerIn: parent
                    width: floatingWidget.activeEdge === "bottom" ? floatingWidget.s(30) : floatingWidget.s(4)
                    height: floatingWidget.activeEdge === "bottom" ? floatingWidget.s(4) : floatingWidget.s(30)
                    radius: floatingWidget.s(2)
                    color: Qt.darker(mocha.mauve, 1.8)
                }

                MouseArea {
                    id: peekMouse
                    anchors.fill: parent
                    anchors.margins: -floatingWidget.s(15) 
                    hoverEnabled: true
                    enabled: floatingWidget.isPeekVisible || pressed
                    
                    property real startGlobalX: 0
                    property real startGlobalY: 0
                    property real currentDragDelta: 0

                    onEntered: { floatingWidget.isPeekVisible = true; peekHideTimer.stop(); }
                    onExited: { if (!pressed) peekHideTimer.restart(); }
                    
                    onPressed: mouse => { 
                        let gp = mapToItem(mainHitArea, mouse.x, mouse.y);
                        startGlobalX = gp.x; 
                        startGlobalY = gp.y;
                        currentDragDelta = 0;
                        floatingWidget.useGraceTimer = true; // Give grace time after drag interaction
                    }
                    
                    onPositionChanged: mouse => {
                        if (!pressed) return;
                        
                        let gp = mapToItem(mainHitArea, mouse.x, mouse.y);
                        let delta = 0;
                        
                        if (floatingWidget.activeEdge === "left") delta = gp.x - startGlobalX;
                        else if (floatingWidget.activeEdge === "right") delta = startGlobalX - gp.x;
                        else if (floatingWidget.activeEdge === "bottom") delta = startGlobalY - gp.y;

                        currentDragDelta = delta;

                        if (delta > floatingWidget.s(15) && !floatingWidget.isExpanded) {
                            floatingWidget.showSidebar(floatingWidget.activeEdge, floatingWidget.currentPos);
                            floatingWidget.isExpanded = true;
                        } else if (delta < -floatingWidget.s(10) && floatingWidget.isPeekVisible) {
                            floatingWidget.isPeekVisible = false;
                        }
                    }
                    
                    onReleased: { 
                        currentDragDelta = 0;
                        peekHideTimer.restart(); 
                    }
                    
                    onClicked: floatingWidget.showSidebar(floatingWidget.activeEdge, floatingWidget.currentPos)
                }
            }

            // =========================================================
            // --- SIDEBAR CONTAINER
            // =========================================================
            Item {
                id: sidebarContainer
                
                // Container is the full panel footprint, positioned by target X/Y.
                width: floatingWidget.panelW
                height: floatingWidget.panelH

                x: {
                    if (floatingWidget.isSidebarVisible) return floatingWidget.sidebarTargetX;
                    if (floatingWidget.activeEdge === "left") return -width - floatingWidget.s(20);
                    if (floatingWidget.activeEdge === "right") return floatingWidget.width + floatingWidget.s(20);
                    return floatingWidget.sidebarTargetX;
                }

                y: {
                    if (floatingWidget.isSidebarVisible) return floatingWidget.sidebarTargetY;
                    if (floatingWidget.activeEdge === "bottom") return floatingWidget.height + floatingWidget.s(20);
                    return floatingWidget.sidebarTargetY; 
                }

                // On the LEFT dock the panel grows rightward from a fixed x=0, so only
                // width animates — clean. On the RIGHT dock x = width - panelW must change
                // as the panel widens to keep the right edge pinned; if x animates on its
                // own curve (350 OutExpo) while width animates on another (450 OutQuart),
                // the two desync and the right edge wobbles. So, exactly like the Y-wobble
                // fix below, disable the x Behavior while expanding/centered — x then tracks
                // the width change instantly, holding the right edge fixed and mirroring the
                // left dock's polish. Keep the Behavior for the full slide-in/out.
                Behavior on x {
                    enabled: !floatingWidget.disableAnim && !floatingWidget.keepCentered
                    NumberAnimation { duration: 350; easing.type: Easing.OutExpo }
                }
                // While the panel is centered (expanding/collapsing), the centered Y is
                // derived from the animating panelH. If Y also animates on its own curve it
                // lags behind panelH and the panel visibly wobbles up/down. So disable the Y
                // Behavior while centered — Y then tracks the height change exactly, holding
                // the center fixed. Keep the Behavior for the grab→center slide and slide-out.
                Behavior on y {
                    enabled: !floatingWidget.disableAnim && !floatingWidget.keepCentered
                    NumberAnimation { duration: 350; easing.type: Easing.OutExpo }
                }

                Item {
                    id: morphOrigin
                    anchors.fill: parent   // fills the panel-sized container

                    HoverHandler {
                        id: mainHoverTracker
                        onHoveredChanged: {
                            if (hovered) {
                                floatingWidget.useGraceTimer = false; // Reset grace period safely if they returned
                                hideTimer.stop();
                            } else {
                                floatingWidget.kickTimer();
                            }
                        }
                    }

                    // ── ONE unified panel background ──
                    // Backs the WHOLE expanded window (selector strip + module) so there is
                    // no inner panel, no margin seam, no double border. Carries the ambient
                    // launcher-style orbs. Fades with expandProgress so the collapsed peek
                    // strip still uses morphingBackground's small nub.
                    Rectangle {
                        id: unifiedBg
                        anchors.fill: parent
                        radius: floatingWidget.s(15)
                        color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.95)
                        border.width: 1
                        border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.08)
                        opacity: floatingWidget.expandProgress
                        visible: floatingWidget.expandProgress > 0.01
                        clip: true

                        // Two ambient bubbles — verbatim launcher background logic
                        // (mauve + blue, cos/sin orbit, ×2 and ×1.5 angle multipliers).
                        // Loop over 4π (not 2π): the blobs use angle×2 and angle×1.5, and
                        // only at 4π do BOTH complete whole turns (8π and 6π) and return to
                        // their start positions — so the loop has no visible jump/seam.
                        // Duration doubled to keep the same drift speed.
                        property real orbitAngle: 0
                        NumberAnimation on orbitAngle {
                            from: 0; to: (4 * Math.PI); duration: 76000
                            loops: Animation.Infinite
                            running: floatingWidget.expandProgress > 0.05
                        }
                        Rectangle {
                            width: parent.width * 0.8; height: width; radius: width / 2
                            x: (parent.width / 2 - width / 2) + Math.cos(unifiedBg.orbitAngle * 2) * floatingWidget.s(150)
                            y: (parent.height / 2 - height / 2) + Math.sin(unifiedBg.orbitAngle * 2) * floatingWidget.s(100)
                            opacity: 0.08
                            color: mocha.mauve
                            Behavior on color { ColorAnimation { duration: 1000 } }
                        }
                        Rectangle {
                            width: parent.width * 0.9; height: width; radius: width / 2
                            x: (parent.width / 2 - width / 2) + Math.sin(unifiedBg.orbitAngle * 1.5) * floatingWidget.s(-150)
                            y: (parent.height / 2 - height / 2) + Math.cos(unifiedBg.orbitAngle * 1.5) * floatingWidget.s(-100)
                            opacity: 0.06
                            color: mocha.blue
                            Behavior on color { ColorAnimation { duration: 1000 } }
                        }
                    }

                    Rectangle {
                        id: morphingBackground
                        // Backs the selector strip wherever it is (inner side, any edge).
                        // anchors.fill copies the strip's bounding box but NOT its rotation,
                        // so apply the same −90° on bottom to keep the backing horizontal
                        // (otherwise it shows as a vertical nub poking above the module).
                        anchors.fill: staticContentWrapper
                        anchors.margins: -floatingWidget.s(4)
                        rotation: floatingWidget.activeEdge === "bottom" ? -90 : 0
                        transformOrigin: Item.Center
                        radius: floatingWidget.s(15) 
                        // Fades out as the panel expands — unifiedBg backs everything when
                        // open, so the strip's own nub only shows while collapsed/peeking.
                        color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.95 * (1.0 - floatingWidget.expandProgress))
                        border.width: 1
                        border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.08 * (1.0 - floatingWidget.expandProgress))

                        MouseArea {
                            id: sidebarDragArea
                            anchors.fill: parent
                            anchors.margins: floatingWidget.isExpanded ? -floatingWidget.s(60) : -floatingWidget.s(15) 
                            hoverEnabled: true
                            enabled: floatingWidget.isSidebarVisible 
                            
                            property real startGlobalX: 0
                            property real startGlobalY: 0

                            onEntered: hideTimer.stop()
                            onExited: { if (!pressed && !gridMouseArea.containsMouse) floatingWidget.kickTimer(); }
                            onPressed: mouse => { 
                                let gp = mapToItem(mainHitArea, mouse.x, mouse.y);
                                startGlobalX = gp.x; 
                                startGlobalY = gp.y; 
                                floatingWidget.useGraceTimer = true; // Initiated a drag, enable 3s grace
                            }
                            onPositionChanged: mouse => {
                                if (!pressed) return;
                                let gp = mapToItem(mainHitArea, mouse.x, mouse.y);
                                floatingWidget.evaluateDrag(startGlobalX, startGlobalY, gp.x, gp.y);
                            }
                            onReleased: { if (!containsMouse) floatingWidget.kickTimer(); }
                        }
                    }

                    Item {
                        id: expandedContainer
                        // Module flush against the screen edge; selector flush on inner side.
                        //   left  : module fills left part,  x=0
                        //   right : module fills right part, x=sidebarW (selector on its left)
                        //   bottom: module fills lower part, y=sidebarW (selector above it)
                        x: floatingWidget.activeEdge === "right" ? floatingWidget.sidebarW : 0
                        y: floatingWidget.activeEdge === "bottom" ? floatingWidget.sidebarW : 0
                        width: floatingWidget.activeEdge === "bottom"
                            ? parent.width
                            : floatingWidget.currentExtraWidth
                        height: floatingWidget.activeEdge === "bottom"
                            ? (parent.height - floatingWidget.sidebarW)
                            : parent.height
                        opacity: floatingWidget.expandProgress
                        clip: true 

                        // (Module-local background removed — unifiedBg backs the whole
                        //  panel now, edge to edge, so there's no inner panel or seam.)

                        // ── Relocated chat header (BOTTOM dock only) ──
                        // Lives in the panel's top band — ABOVE the module content — so the
                        // title and New Chat/Kanban sit on the selector's line, level with
                        // the resize grip (which is centered, leaving these corners free).
                        // Bound to the loaded module via floatingWidget.currentModuleItem; the module's own
                        // in-module header is hidden on the bottom edge to avoid duplication.
                        Item {
                            id: bottomChatHeader
                            // Reparent OUT of expandedContainer (which clips and starts BELOW
                            // the selector band at y=sidebarW) into morphOrigin, which spans
                            // the whole panel and doesn't clip — so the header can sit up in
                            // the selector strip's top band without being cut off.
                            parent: morphOrigin
                            property var mod: floatingWidget.currentModuleItem
                            visible: floatingWidget.activeEdge === "bottom"
                                     && floatingWidget.expandProgress > 0.5
                                     && mod && mod.activeMode === "chat"
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            // Center within the selector strip's top band (height ≈ sidebarW).
                            anchors.topMargin: Math.max(0, (floatingWidget.sidebarW - floatingWidget.s(28)) / 2)
                            anchors.leftMargin: floatingWidget.s(12)
                            anchors.rightMargin: floatingWidget.s(12)
                            height: floatingWidget.s(28)
                            z: 60

                            // Title / previous-chats dropdown — far left.
                            Rectangle {
                                id: bchTitle
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(bchTitleRow.implicitWidth + floatingWidget.s(16), floatingWidget.s(220))
                                height: floatingWidget.s(28); radius: floatingWidget.s(8)
                                color: (bchTitleMa.containsMouse || (bottomChatHeader.mod && bottomChatHeader.mod.chatHistoryOpen))
                                       ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.7) : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Row { id: bchTitleRow; anchors.left: parent.left; anchors.leftMargin: floatingWidget.s(8)
                                    anchors.verticalCenter: parent.verticalCenter; spacing: floatingWidget.s(6)
                                    Text { text: "󰍝"; font.family: "Iosevka Nerd Font"; font.pixelSize: floatingWidget.s(11)
                                        color: (bottomChatHeader.mod && bottomChatHeader.mod.chatHistoryOpen) ? mocha.mauve : (bchTitleMa.containsMouse ? mocha.mauve : mocha.overlay1)
                                        anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: (bottomChatHeader.mod && bottomChatHeader.mod.chatTitle !== "") ? bottomChatHeader.mod.chatTitle : "New conversation"
                                        font.family: "JetBrains Mono"; font.weight: Font.Medium; font.pixelSize: floatingWidget.s(10)
                                        color: (bottomChatHeader.mod && bottomChatHeader.mod.chatTitle !== "") ? (bchTitleMa.containsMouse ? mocha.text : mocha.subtext0) : mocha.overlay0
                                        elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
                                }
                                MouseArea { id: bchTitleMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { if (!bottomChatHeader.mod) return;
                                        bottomChatHeader.mod.chatHistoryOpen = !bottomChatHeader.mod.chatHistoryOpen;
                                        if (bottomChatHeader.mod.chatHistoryOpen) bottomChatHeader.mod.loadChatHistory(); } }
                            }

                            // New Chat — far right.
                            Rectangle {
                                id: bchNew
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: bchNewRow.implicitWidth + floatingWidget.s(16); height: floatingWidget.s(28); radius: floatingWidget.s(8)
                                color: bchNewMa.containsMouse ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.8) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.5)
                                border.color: bchNewMa.containsMouse ? mocha.mauve : Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.5); border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Row { id: bchNewRow; anchors.centerIn: parent; spacing: floatingWidget.s(6)
                                    Text { text: "󰝒"; font.family: "Iosevka Nerd Font"; font.pixelSize: floatingWidget.s(13); color: mocha.mauve; anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: "New Chat"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: floatingWidget.s(10); color: bchNewMa.containsMouse ? mocha.text : mocha.subtext0; anchors.verticalCenter: parent.verticalCenter } }
                                MouseArea { id: bchNewMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: (mouse) => { if (!bottomChatHeader.mod) return;
                                        if (mouse.button === Qt.RightButton) bottomChatHeader.mod.startNewChat(true);
                                        else bottomChatHeader.mod.startNewChat(false); } }
                            }
                        }

                        // ── Chat scrollbar ──
                        // Implemented inside FloatingContent as a ScrollBar ATTACHED to the
                        // chat ListView (so Qt manages position/size/drag/stop-at-end
                        // automatically and correctly), then reparented to the module root to
                        // escape the content clip and sit at the panel edge. See chatView.

                        // ── Bottom-module height resize handle (the "pull tab") ──
                        // A grab strip along the TOP edge of the bottom dock. Dragging it up
                        // grows the panel, down shrinks it; the chosen height persists via
                        // Config.floatingBottomHeight. Sits JUST inside the unified background.
                        Item {
                            id: bottomResizeHandle
                            visible: floatingWidget.activeEdge === "bottom" && floatingWidget.expandProgress > 0.5
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter   // centered grip only
                            anchors.topMargin: floatingWidget.s(6)
                            width: floatingWidget.s(120)   // narrow: leaves the corners free for title / buttons
                            height: floatingWidget.s(16)
                            z: 50

                            // Soft capsule backdrop — appears on hover/drag so the tab reads
                            // as a real control without cluttering the idle panel.
                            Rectangle {
                                anchors.centerIn: parent
                                width: floatingWidget.s(76); height: floatingWidget.s(14)
                                radius: height / 2
                                color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.07)
                                opacity: (resizeHandleMouse.containsMouse || resizeHandleMouse.drag.active) ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                            }
                            // The grip itself — a wide rounded pill, mauve when active.
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.verticalCenter
                                width: floatingWidget.s(52); height: floatingWidget.s(5)
                                radius: height / 2
                                color: (resizeHandleMouse.containsMouse || resizeHandleMouse.drag.active)
                                       ? Qt.rgba(mocha.mauve.r, mocha.mauve.g, mocha.mauve.b, 0.9)
                                       : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.25)
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            MouseArea {
                                id: resizeHandleMouse
                                anchors.fill: parent
                                anchors.margins: -floatingWidget.s(6)   // a little extra grab room
                                hoverEnabled: true
                                cursorShape: Qt.SizeVerCursor
                                preventStealing: true
                                property real startY: 0
                                property real startHeight: 0
                                onPressed: mouse => {
                                    floatingWidget.useGraceTimer = true;
                                    floatingWidget.disableAnim = true;
                                    hideTimer.stop();
                                    // Track the cursor in ABSOLUTE SCREEN coordinates. The handle
                                    // sits at the panel's top and the panel grows upward, so the
                                    // handle (and this MouseArea) move during the drag — any
                                    // panel-relative measure feeds back on itself. Global screen Y
                                    // is fixed, giving a clean reference.
                                    startY = mapToGlobal(mouse.x, mouse.y).y;
                                    startHeight = floatingWidget.sidebarW + floatingWidget.expandedExtraLength;
                                }
                                onPositionChanged: mouse => {
                                    if (!pressed) return;
                                    let curY = mapToGlobal(mouse.x, mouse.y).y;
                                    let dy = curY - startY;                 // cursor moved down = positive
                                    let newH = startHeight - dy;            // up grows the panel
                                    let w = floatingWidget.panelW;
                                    let minH = 0.25 * w;
                                    let maxH = 2.0 * w;
                                    maxH = Math.min(maxH, floatingWidget.height - floatingWidget.s(50));
                                    newH = Math.max(minH, Math.min(newH, maxH));
                                    floatingWidget.userBottomHeight = newH;
                                }
                                onReleased: {
                                    // Persist the chosen height between sessions (both the
                                    // shared Config value and the local source of truth).
                                    Config.floatingBottomHeight = floatingWidget.userBottomHeight;
                                    Config.setSetting("floatingBottomHeight", floatingWidget.userBottomHeight);
                                    floatingWidget.disableAnim = false;
                                    hideTimer.restart();
                                }
                            }
                        }

                        component EmptyBlock : Rectangle {
                            radius: floatingWidget.s(12) 
                            // Transparent content frame: unifiedBg is the ONLY visible
                            // background now — this just rounds/clips its content, so
                            // there's no inner panel, border, or margin seam.
                            color: "transparent"
                            border.width: 0
                            clip: true
                        }

                        // =========================================================
                        // --- ADAPTIVE INNER COUNTER-ROTATION FIX 
                        // =========================================================
                        Item {
                            anchors.fill: parent
                            anchors.topMargin: 0
                            anchors.bottomMargin: 0
                            anchors.leftMargin: 0
                            anchors.rightMargin: 0
                            visible: floatingWidget.expandProgress > 0.01

                            Item {
                                anchors.centerIn: parent
                                width: parent.width
                                height: parent.height
                                rotation: floatingWidget.activeEdge === "right" ? 180 : 0

                                property real sp: floatingWidget.s(10) 
                                property real cw: Math.max(0, width) 
                                property real ch: Math.max(0, height)
                                
                                Repeater {
                                    model: floatingWidget.currentLayoutTemplate
                                    delegate: EmptyBlock {
                                        x: (modelData.x * parent.cw) + (modelData.x > 0 ? parent.sp / 2 : 0)
                                        y: (modelData.y * parent.ch) + (modelData.y > 0 ? parent.sp / 2 : 0)
                                        width: (modelData.w * parent.cw) - ((modelData.x > 0 ? parent.sp / 2 : 0) + ((modelData.x + modelData.w) < 0.99 ? parent.sp / 2 : 0))
                                        height: (modelData.h * parent.ch) - ((modelData.y > 0 ? parent.sp / 2 : 0) + ((modelData.y + modelData.h) < 0.99 ? parent.sp / 2 : 0))
                                    }
                                }
                            }
                        }

                        Repeater {
                            id: moduleRepeater
                            model: floatingWidget.tabModules

                            delegate: Loader {
                                id: contentLoader
                                z: 10
                                // Counter-rotate the module against the container's edge
                                // rotation (same idea as Timer's orientedRoot): the container
                                // rotates the whole sidebar per edge, so the module rotates
                                // back to stay right-side-up. 180° (right) doesn't swap axes;
                                // 90° (bottom) does, so swap width/height there.
                                // Right edge flips 180°; left and bottom render the module
                                // plain and upright. No axis swap — the module's natural
                                // portrait shape (preferred 801×1000) just fills the frame.
                                anchors.fill: parent
                                // Uniform inset, EXCEPT the side facing the selector strip:
                                // drop that margin to 0 so the module content (text box,
                                // bubbles) sits flush against the selector.
                                //   left  edge → selector on the module's RIGHT → no right margin
                                //   right edge → selector on the module's LEFT  → no left margin
                                anchors.topMargin: floatingWidget.s(14)
                                anchors.bottomMargin: floatingWidget.s(14)
                                anchors.leftMargin: floatingWidget.activeEdge === "right" ? 0 : floatingWidget.s(14)
                                anchors.rightMargin: floatingWidget.activeEdge === "left" ? 0 : floatingWidget.s(14)

                                visible: floatingWidget.expandProgress > 0.01
                                source: modelData
                                asynchronous: false

                                property var scaleFunc: floatingWidget.s
                                property var mochaColors: mocha 
                                property string activeEdge: floatingWidget.activeEdge 

                                property bool isCurrentTarget: true
                                property real modWidth: (status === Loader.Ready && item && item.preferredWidth !== undefined) ? item.preferredWidth : floatingWidget.baseExpandedWidth
                                property real modExt: (status === Loader.Ready && item && item.preferredExtraLength !== undefined) ? item.preferredExtraLength : floatingWidget.baseExpandedExtraLength
                                
                                property var modLayout: {
                                    if (status === Loader.Ready && item && item.requestedLayoutTemplate !== undefined) {
                                        let req = item.requestedLayoutTemplate;
                                        if (typeof req === "number") {
                                            if (req === 0) return [ {x:0, y:0, w:0.5, h:0.5}, {x:0.5, y:0, w:0.5, h:0.5}, {x:0, y:0.5, w:0.5, h:0.5}, {x:0.5, y:0.5, w:0.5, h:0.5} ];
                                            else return [ {x:0, y:0, w:1, h:1} ]; 
                                        }
                                        return req; 
                                    }
                                    return [ {x:0, y:0, w:1, h:1} ];
                                }

                                function updateSizes() {
                                    if (isCurrentTarget) {
                                        if (floatingWidget.activeEdge === "bottom") {
                                            // Bottom dock panel's real height is
                                            // (sidebarW + extraLength). Size extraLength so the
                                            // whole panel spans from a small top margin down to
                                            // a few px above the screen bottom — UNLESS the user
                                            // has dragged a custom height (Config.floatingBottomHeight),
                                            // in which case honor that (clamped to sane bounds).
                                            let topMargin = floatingWidget.s(50);
                                            let bottomGap = floatingWidget.s(6);
                                            let fillLen = floatingWidget.height - topMargin - bottomGap - floatingWidget.sidebarW;
                                            let len;
                                            // Prefer the live local drag value; fall back to the
                                            // persisted Config value for the initial seed.
                                            let desired = floatingWidget.userBottomHeight > 0
                                                ? floatingWidget.userBottomHeight
                                                : ((Config.floatingBottomHeight && Config.floatingBottomHeight > 0) ? Config.floatingBottomHeight : 0);
                                            if (desired > 0) {
                                                let w = floatingWidget.panelW;
                                                let minPanel = 0.25 * w;
                                                let maxPanel = Math.min(2.0 * w, floatingWidget.height - topMargin);
                                                let panelH = Math.max(minPanel, Math.min(desired, maxPanel));
                                                len = panelH - floatingWidget.sidebarW;
                                                if (len < 0) len = 0;
                                            } else {
                                                len = Math.max(modExt, fillLen);
                                            }
                                            floatingWidget.targetExpandedExtraLength = len;
                                            floatingWidget.expandedWidth = modWidth;
                                            floatingWidget.expandedExtraLength = len;
                                        } else {
                                            // Side docks: match the bottom panel's overall width
                                            // but a touch smaller. Bottom panel ≈ modWidth wide;
                                            // a side panel's total = sidebarW + module width, so
                                            // subtract the strip plus a small trim to land just
                                            // under the bottom's footprint.
                                            floatingWidget.targetExpandedExtraLength = modExt;
                                            floatingWidget.expandedWidth = Math.max(floatingWidget.s(200),
                                                modWidth - floatingWidget.sidebarW - floatingWidget.s(60));
                                            floatingWidget.expandedExtraLength = modExt;
                                        }
                                        floatingWidget.currentLayoutTemplate = modLayout;
                                    }
                                }

                                onLoaded: { updateSizes(); floatingWidget._syncFloatingMode();
                                    if (isCurrentTarget) floatingWidget.currentModuleItem = item; }
                                onIsCurrentTargetChanged: { updateSizes(); if (isCurrentTarget && item) floatingWidget.currentModuleItem = item; }
                                onModWidthChanged: updateSizes()
                                onModExtChanged: updateSizes()
                                onModLayoutChanged: updateSizes()
                                onActiveEdgeChanged: updateSizes()
                                Component.onCompleted: updateSizes()
                                // Re-apply sizing when the user-set bottom height changes
                                // (live during drag, and once when loaded from settings).
                                Connections {
                                    target: Config
                                    function onFloatingBottomHeightChanged() {
                                        if (contentLoader.isCurrentTarget && floatingWidget.activeEdge === "bottom")
                                            contentLoader.updateSizes();
                                    }
                                }
                                Connections {
                                    target: floatingWidget
                                    // Live drag: the local height is always notifiable, so this
                                    // fires on every drag step and resizes the panel 1:1.
                                    function onUserBottomHeightChanged() {
                                        if (contentLoader.isCurrentTarget && floatingWidget.activeEdge === "bottom")
                                            contentLoader.updateSizes();
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: gridMouseArea
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton 
                            hoverEnabled: true
                            
                            onEntered: hideTimer.stop()
                            onExited: { if (!sidebarDragArea.containsMouse) floatingWidget.kickTimer(); }
                            // Scroll no longer switches between modules — it's passed through
                            // to the module content so you can scroll within chat/notes/etc.
                            // Module switching is done via the selector pills / Tab only.
                            onWheel: wheel => { wheel.accepted = false; }
                        }
                    }

                    // =========================================================
                    // --- STATIC INNER LAYOUT WRAPPER (TABS)
                    // =========================================================
                    Item {
                        id: staticContentWrapper
                        width: floatingWidget.sidebarW
                        height: floatingWidget.baseSidebarH
                        rotation: floatingWidget.activeEdge === "bottom" ? -90 : 0
                        transformOrigin: Item.Center

                        // Selector sits centered on the module's INNER edge (flush against
                        // the module, centered along that edge). The panel itself slides to
                        // screen-center as it opens, so the selector ends up centered on the
                        // screen edge when kept open.
                        //   left  : inner edge = right side of module (x = currentExtraWidth)
                        //   right : inner edge = left side of module  (x = 0)
                        //   bottom: inner edge = top of module, centered horizontally
                        x: {
                            if (floatingWidget.activeEdge === "left")  return floatingWidget.currentExtraWidth;
                            if (floatingWidget.activeEdge === "right") return 0;
                            return (floatingWidget.panelW / 2) - (floatingWidget.sidebarW / 2);
                        }
                        y: {
                            if (floatingWidget.activeEdge === "bottom")
                                return (floatingWidget.sidebarW / 2) - (floatingWidget.baseSidebarH / 2);
                            // left/right: centered along the inner edge (module vertical center)
                            return (floatingWidget.panelH / 2) - (floatingWidget.baseSidebarH / 2);
                        }

                        Item {
                            anchors.fill: parent
                            anchors.margins: floatingWidget.s(8)

                            // ---------------------------------------------------------
                            // CONTROL AREA (expand + pin buttons)
                            // ---------------------------------------------------------
                            Item {
                                id: controlArea
                                width: parent.width
                                height: floatingWidget.controlAreaHeight
                                x: 0
                                y: (floatingWidget.activeEdge === "left" || floatingWidget.activeEdge === "bottom")
                                    ? 0
                                    : floatingWidget.getTargetY(floatingWidget.tabCount, floatingWidget.activeIndex)

                                Behavior on y {
                                    enabled: !floatingWidget.disableAnim
                                    NumberAnimation { duration: 350; easing.type: Easing.OutExpo }
                                }

                                // EXPAND BUTTON
                                Item {
                                    id: expandButton
                                    width: floatingWidget.buttonSize
                                    height: floatingWidget.buttonSize
                                    x: (parent.width - width) / 2
                                    y: (floatingWidget.activeEdge === "left" || floatingWidget.activeEdge === "bottom")
                                        ? floatingWidget.s(6)
                                        : parent.height - height - floatingWidget.s(6)

                                    rotation: floatingWidget.isExpanded ? 180 : 0
                                    Behavior on rotation { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }

                                    Item {
                                        anchors.fill: parent
                                        
                                        property color iconColor: floatingWidget.isExpanded ? mocha.mauve : 
                                                                  (expandMouse.pressed ? Qt.darker(mocha.mauve, 1.2) : 
                                                                  (expandMouse.containsMouse ? mocha.mauve : 
                                                                  Qt.tint(mocha.base, Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.3))))
                                                                  
                                        property real pivotX: parent.width / 2 - floatingWidget.s(4)

                                        Rectangle {
                                            width: floatingWidget.s(5)
                                            height: floatingWidget.s(5)
                                            radius: width / 2
                                            color: parent.iconColor
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: parent.pivotX - (width / 2)
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                        }

                                        Rectangle {
                                            x: parent.pivotX
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: floatingWidget.s(13)
                                            height: floatingWidget.s(4.5)
                                            radius: height / 2
                                            transformOrigin: Item.Left
                                            rotation: 42
                                            color: parent.iconColor
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                        }

                                        Rectangle {
                                            x: parent.pivotX
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: floatingWidget.s(13)
                                            height: floatingWidget.s(4.5)
                                            radius: height / 2
                                            transformOrigin: Item.Left
                                            rotation: -42
                                            color: parent.iconColor
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                        }
                                    }

                                    MouseArea {
                                        id: expandMouse
                                        anchors.fill: parent
                                        hoverEnabled: true

                                        property real startGlobalX: 0
                                        property real startGlobalY: 0
                                        property bool isDragging: false

                                        onEntered: hideTimer.stop()
                                        onExited: floatingWidget.kickTimer()

                                        onPressed: mouse => {
                                            let gp = mapToItem(mainHitArea, mouse.x, mouse.y);
                                            startGlobalX = gp.x;
                                            startGlobalY = gp.y;
                                            isDragging = false;
                                        }
                                        onPositionChanged: mouse => {
                                            if (!pressed) return;
                                            let gp = mapToItem(mainHitArea, mouse.x, mouse.y);
                                            let deltaX = Math.abs(gp.x - startGlobalX);
                                            let deltaY = Math.abs(gp.y - startGlobalY);
                                            // Only treat as a drag past a clear threshold, and
                                            // only actually move the panel once dragging — this
                                            // keeps taps on the rotated bottom strip as clicks.
                                            if (deltaX > 12 || deltaY > 12) {
                                                isDragging = true;
                                                floatingWidget.evaluateDrag(startGlobalX, startGlobalY, gp.x, gp.y);
                                            }
                                        }
                                        onClicked: {
                                            if (!isDragging) {
                                                floatingWidget.isExpanded = !floatingWidget.isExpanded;
                                                floatingWidget.kickTimer();
                                            }
                                        }
                                    }
                                }

                                // PIN BUTTON
                                Rectangle {
                                    id: pinButton
                                    width: floatingWidget.buttonSize
                                    height: floatingWidget.buttonSize
                                    radius: width / 2
                                    x: (parent.width - width) / 2
                                    y: (floatingWidget.activeEdge === "left" || floatingWidget.activeEdge === "bottom")
                                        ? expandButton.y + expandButton.height + floatingWidget.s(8)
                                        : expandButton.y - height - floatingWidget.s(8)

                                    color: floatingWidget.isPinned
                                        ? mocha.mauve
                                        : (pinMouse.pressed
                                            ? Qt.rgba(mocha.mauve.r, mocha.mauve.g, mocha.mauve.b, 0.4)
                                            : (pinMouse.containsMouse
                                                ? Qt.rgba(mocha.mauve.r, mocha.mauve.g, mocha.mauve.b, 0.25)
                                                : "transparent"))
                                    border.width: floatingWidget.s(2)
                                    border.color: floatingWidget.isPinned
                                        ? mocha.mauve
                                        : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.2)
                                    
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Behavior on border.color { ColorAnimation { duration: 200 } }

                                    MouseArea {
                                        id: pinMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        
                                        property real startGlobalX: 0
                                        property real startGlobalY: 0
                                        property bool isDragging: false

                                        onEntered: hideTimer.stop()
                                        onExited: floatingWidget.kickTimer()
                                        
                                        onPressed: mouse => { 
                                            let gp = mapToItem(mainHitArea, mouse.x, mouse.y);
                                            startGlobalX = gp.x; 
                                            startGlobalY = gp.y; 
                                            isDragging = false;
                                        }
                                        onPositionChanged: mouse => {
                                            if (!pressed) return;
                                            let gp = mapToItem(mainHitArea, mouse.x, mouse.y);
                                            let deltaX = Math.abs(gp.x - startGlobalX);
                                            let deltaY = Math.abs(gp.y - startGlobalY);
                                            if (deltaX > 5 || deltaY > 5) isDragging = true;
                                            floatingWidget.evaluateDrag(startGlobalX, startGlobalY, gp.x, gp.y);
                                        }
                                        onClicked: {
                                            if (!isDragging) {
                                                floatingWidget.isPinned = !floatingWidget.isPinned;
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                id: activeHighlight
                                x: 0
                                width: parent.width
                                z: 0
                                radius: floatingWidget.s(7) 
                                color: mocha.mauve

                                property int prevIdx: 0
                                property int curIdx: floatingWidget.activeIndex

                                onCurIdxChanged: {
                                    if (curIdx > prevIdx) { bottomAnim.duration = 200; topAnim.duration = 350; } 
                                    else if (curIdx < prevIdx) { topAnim.duration = 200; bottomAnim.duration = 350; }
                                    prevIdx = curIdx;
                                }

                                property real targetTop: floatingWidget.barOffsetY + floatingWidget.getTargetY(curIdx, curIdx)
                                property real targetBottom: targetTop + floatingWidget.h_ac

                                property real actualTop: targetTop
                                property real actualBottom: targetBottom

                                Behavior on actualTop { NumberAnimation { id: topAnim; duration: 250; easing.type: Easing.OutExpo } }
                                Behavior on actualBottom { NumberAnimation { id: bottomAnim; duration: 250; easing.type: Easing.OutExpo } }

                                y: actualTop
                                height: actualBottom - actualTop
                            }

                            Repeater {
                                model: floatingWidget.tabCount
                                delegate: Rectangle {
                                    id: barPill
                                    property bool isActive: floatingWidget.activeIndex === index
                                    property bool isHovered: barMouse.containsMouse
                                    property bool isPressed: barMouse.pressed
                                    
                                    x: 0
                                    width: parent.width
                                    radius: floatingWidget.s(7) 
                                    z: 1 

                                    y: floatingWidget.barOffsetY + floatingWidget.getTargetY(index, floatingWidget.activeIndex)
                                    Behavior on y { enabled: !floatingWidget.disableAnim; NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }

                                    height: isActive ? floatingWidget.h_ac : floatingWidget.h_in
                                    Behavior on height { enabled: !floatingWidget.disableAnim; NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }

                                    color: isActive ? "transparent" : (isPressed ? Qt.rgba(mocha.mauve.r, mocha.mauve.g, mocha.mauve.b, 0.4) : (isHovered ? Qt.rgba(mocha.mauve.r, mocha.mauve.g, mocha.mauve.b, 0.25) : Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.15)))
                                    Behavior on color { ColorAnimation { duration: 250 } }

                                    scale: isActive ? 1.0 : (isPressed ? 0.95 : (isHovered ? 1.05 : 1.0))
                                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                                    MouseArea {
                                        id: barMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        
                                        property real startGlobalX: 0
                                        property real startGlobalY: 0
                                        property bool isDragging: false
                                        
                                        onEntered: { floatingWidget.hoveredBars++; hideTimer.stop(); }
                                        onExited: { floatingWidget.hoveredBars = Math.max(0, floatingWidget.hoveredBars - 1); floatingWidget.kickTimer(); }
                                        
                                        onPressed: mouse => { 
                                            let gp = mapToItem(mainHitArea, mouse.x, mouse.y);
                                            startGlobalX = gp.x; 
                                            startGlobalY = gp.y; 
                                            isDragging = false;
                                        }
                                        onPositionChanged: mouse => {
                                            if (!pressed) return;
                                            let gp = mapToItem(mainHitArea, mouse.x, mouse.y);
                                            let deltaX = Math.abs(gp.x - startGlobalX);
                                            let deltaY = Math.abs(gp.y - startGlobalY);
                                            if (deltaX > 12 || deltaY > 12) {
                                                isDragging = true;
                                                floatingWidget.evaluateDrag(startGlobalX, startGlobalY, gp.x, gp.y);
                                            }
                                        }
                                        onClicked: {
                                            if (!isDragging) {
                                                if (!barPill.isActive) floatingWidget.activeIndex = index; 
                                                else floatingWidget.isExpanded = !floatingWidget.isExpanded;
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
    }
}
