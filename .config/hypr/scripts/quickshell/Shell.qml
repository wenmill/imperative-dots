//@ pragma UseQApplication
import QtQuick
import Quickshell
import "floating" as FloatingDir

ShellRoot {
    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup() }
        function onReloadFailed(errorString) { Quickshell.inhibitReloadPopup() }
    }

    Main {}
    TopBar {}
    FloatingDir.Floating {}
}

