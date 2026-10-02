import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Cava as a desktop backdrop.
//
// The service does the three things that only make sense from inside the shell:
// it puts the Hyprland rule and the visualizer in place once, it restarts the
// visualizer when the theme changes (cava reads its colors when it starts, and
// the window it draws in cannot be focused to send it a reload key), and it
// cleans up when the plugin is disabled.
Item {
  id: root

  // The shell hands a service its manifest as a public copy with the source
  // directory stripped out, so this file's own location is the only honest
  // answer to where the scripts are.
  readonly property string pluginDir: Qt.resolvedUrl(".")
    .toString()
    .replace(/^file:\/\//, "")
    .replace(/\/+$/, "")
  readonly property string scripts: pluginDir + "/scripts"

  // How often to check that the visualizer is still there. The terminal can die
  // on its own, and the shell service that started it can be replaced by a shell
  // restart, which also runs the cleanup below; one cheap status check keeps the
  // backdrop from staying missing until the next login.
  readonly property int watchdogIntervalMs: 30000

  function script(name, args) {
    return [root.scripts + "/" + name].concat(args || [])
  }

  Component.onCompleted: {
    console.log("omarchy-cava: starting")
    installer.running = true
    watchdog.restart()
  }

  // Nothing is torn down here on a shell restart, only on a real disable: the
  // window rule lives in the state directory and install-hyprd owns that file,
  // so scripts/uninstall is the one place that removes it.
  Component.onDestruction: stopper.running = true

  // ---------------------------------------------------------------- processes

  // Copy the window rule into place, render the current theme's colors, start
  // the visualizer. All three steps are safe to repeat.
  Process {
    id: installer
    command: root.script("install")
    stdout: StdioCollector {
      onStreamFinished: console.log("omarchy-cava: install\n" + text)
    }
    stderr: StdioCollector {
      onStreamFinished: console.warn("omarchy-cava: install\n" + text)
    }
  }

  // write-colors exits 0 when it changed the theme file and 1 when the colors
  // were already current, which is what keeps a theme signal from restarting the
  // visualizer for nothing.
  Process {
    id: colors
    command: root.script("write-colors")
  }

  Process {
    id: restarter
    command: root.script("backdrop", ["restart"])
    stdout: StdioCollector {
      onStreamFinished: if (text.trim().length > 0) console.log("omarchy-cava: " + text)
    }
    stderr: StdioCollector {
      onStreamFinished: console.warn("omarchy-cava: " + text)
    }
  }

  Process {
    id: stopper
    command: root.script("backdrop", ["stop"])
  }

  // Cheap liveness check: install is a no-op when the window is already there.
  Process {
    id: watchdogRun
    command: root.script("install")
  }

  // ------------------------------------------------------------------ triggers

  // Every theme switch rewrites the palette the shell itself uses, and any of
  // these changing means the visualizer is drawing last theme's colors. The
  // timer collapses a switch, which touches several of them at once, into one
  // check.
  Timer {
    id: themeChanged
    interval: 750
    onTriggered: colors.running = true
  }

  Connections {
    target: Color

    function onAccentChanged() {
      themeChanged.restart()
    }

    function onBackgroundChanged() {
      themeChanged.restart()
    }

    function onForegroundChanged() {
      themeChanged.restart()
    }

    function onMutedChanged() {
      themeChanged.restart()
    }
  }

  Timer {
    id: watchdog
    interval: root.watchdogIntervalMs
    repeat: true
    onTriggered: if (!watchdogRun.running) watchdogRun.running = true
  }

  // ---------------------------------------------------------------- reactions

  Connections {
    target: colors

    function onExited(code) {
      if (code === 0 && !restarter.running) restarter.running = true
    }
  }
}