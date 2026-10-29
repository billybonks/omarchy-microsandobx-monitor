import QtQuick
import qs.Ui as Ui

Ui.BarWidget {
  id: root
  moduleName: "billybonks.microsandbox-monitor"
  readonly property bool opened: panel.opened
  readonly property bool popoutSwitchClosing: panel.popoutSwitchClosing

  function open() { panel.open() }
  function close() { panel.close() }
  function toggle() { panel.toggle() }
  function closeForPopoutSwitch() { panel.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Service { id: service; expanded: panel.opened }
  SandboxDisclosure {
    id: panel
    bar: root.bar
    hostWidget: root
    anchorItem: button
    backend: service
  }
  Ui.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: String.fromCodePoint(0xF01A6) + (root.vertical ? "" : " " + (service.healthy ? service.runningCount : "·"))
    tooltipText: service.healthy
      ? service.runningCount + " running · " + service.sandboxes.length + " sandboxes"
      : (service.error || "Checking microsandbox…")
    onPressed: function(b) {
      if (b === Qt.RightButton) service.refresh()
      else root.toggle()
    }
  }
}
