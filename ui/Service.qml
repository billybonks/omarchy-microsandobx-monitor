import QtQuick
import Quickshell.Io

// Only process/JSON glue lives here. All management and display models are Rust.
Item {
  id: root
  property bool expanded: false
  property var sandboxes: []
  property int runningCount: 0
  property bool ready: false
  property bool healthy: false
  property bool truncated: false
  property string error: ""
  property string pendingId: ""
  property string pendingVerb: ""
  readonly property bool busy: worker.running
  readonly property string executable: Qt.resolvedUrl("../bin/microsandbox-panel").toString().replace(/^file:\/\//, "")

  function refresh() {
    if (busy) return
    launch(["status"], "", "status")
  }
  function action(verb, sandbox) {
    if (busy || !healthy || !sandbox) return
    launch([verb, sandbox.name, sandbox.id], sandbox.id, verb)
  }
  function launch(args, id, verb) {
    pendingId = id
    pendingVerb = verb
    worker.command = [decodeURIComponent(executable)].concat(args)
    worker.running = true
    watchdog.restart()
  }

  Timer {
    interval: root.expanded ? 3000 : 15000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
  Timer {
    id: watchdog
    interval: root.pendingVerb === "status" ? 25000 : 185000
    onTriggered: {
      worker.running = false
      root.error = "Backend timed out. Refresh to check the final state."
      root.healthy = false
      root.ready = true
    }
  }
  Process {
    id: worker
    command: []
    stdout: StdioCollector { id: output; waitForEnd: true }
    onExited: function(code) {
      watchdog.stop()
      root.pendingId = ""
      root.pendingVerb = ""
      root.ready = true
      try {
        if (output.text.length > 1048576) throw new Error("Oversized backend response")
        var result = JSON.parse(output.text)
        if (code !== 0 || result.ok !== true) {
          root.error = result.error || "Backend failed. Refresh to retry."
          root.healthy = false
          return
        }
        root.sandboxes = result.sandboxes
        root.runningCount = result.runningCount
        root.truncated = result.truncated
        root.error = ""
        root.healthy = true
      } catch (e) {
        root.error = "Could not read the Rust backend. Check that bin/microsandbox-panel is built and executable."
        root.healthy = false
      }
    }
  }
}
