import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Panel {
    id: root
    moduleName: "billybonks.microsandbox-monitor"
    property var anchorItem: null
    property var hostWidget: null
    property var backend: null
    property string selectedId: ""
    readonly property int selectedIndex: selectionIndex(backend ? backend.sandboxes : [], selectedId)

    function selectionIndex(sandboxes, id) {
        for (var i = 0; i < sandboxes.length; ++i) {
            if (sandboxes[i].id === id)
                return i;
        }
        return sandboxes.length ? 0 : -1;
    }

    Connections {
        target: root.backend
        function onSandboxesChanged() {
            var sandboxes = root.backend.sandboxes;
            var index = root.selectionIndex(sandboxes, root.selectedId);
            root.selectedId = index >= 0 ? sandboxes[index].id : "";
        }
    }
    property var removeTarget: null
    // Stable IDs preserve disclosure state across polling and reordered rows.
    property var expandedIds: []

    function toggleDetails(sb) {
        if (!sb)
            return;
        var ids = expandedIds.slice();
        var index = ids.indexOf(sb.id);
        if (index === -1)
            ids.push(sb.id);
        else
            ids.splice(index, 1);
        expandedIds = ids;
    }
    readonly property color foreground: bar ? bar.foreground : Color.foreground
    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

    function open() {
        backend.refresh();
        controller.show();
        Qt.callLater(function () {
            keys.forceActiveFocus();
        });
    }
    function close() {
        removeTarget = null;
        controller.hide();
    }
    function switchPanel(direction) {
        return bar && bar.switchPanelFrom ? bar.switchPanelFrom(hostWidget || root, direction) : false;
    }
    function selected() {
        return selectedIndex >= 0 ? backend.sandboxes[selectedIndex] : null;
    }
    function toggleSandbox(sb) {
        if (sb && sb.actionable)
            backend.action(sb.running ? "stop" : "start", sb);
    }
    function askRemove(sb) {
        if (!sb || sb.running || !sb.actionable || backend.busy || !backend.healthy)
            return;
        removeTarget = sb;
        confirm.selectedIndex = 0;
        Qt.callLater(function () {
            confirmKeys.forceActiveFocus();
        });
    }
    function cancelRemove() {
        removeTarget = null;
        Qt.callLater(function () {
            keys.forceActiveFocus();
        });
    }
    onOpenedChanged: if (!opened)
        removeTarget = null

    component UsageMeter: Column {
        id: meter
        property string label: ""
        property var fraction: null
        spacing: Style.space(4)
        Text {
            width: parent.width
            text: meter.label
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
        }
        Rectangle {
            width: parent.width
            height: Style.space(4)
            radius: height / 2
            visible: meter.fraction !== null
            color: Util.alpha(root.foreground, 0.1)
            Rectangle {
                width: parent.width * (meter.fraction === null ? 0 : meter.fraction)
                height: parent.height
                radius: height / 2
                color: meter.fraction > 0.9 ? Color.urgent : Color.accent
                Behavior on width {
                    NumberAnimation {
                        duration: 200
                    }
                }
            }
        }
    }

    KeyboardPanel {
        id: popup
        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        focusTarget: keys
        contentWidth: popup.fittedContentWidth(Style.space(500))
        contentHeight: popup.fittedContentHeight(content.implicitHeight, Style.space(620))

        PanelKeyCatcher {
            id: keys
            anchors.fill: parent
            blocked: root.removeTarget !== null
            onCloseRequested: root.close()
            onTabRequested: function (direction) {
                root.switchPanel(direction);
            }
            onMoveRequested: function (dx, dy) {
                var sandboxes = root.backend.sandboxes;
                if (!sandboxes.length)
                    return;
                var index = Math.max(0, Math.min(sandboxes.length - 1, root.selectedIndex + dy));
                root.selectedId = sandboxes[index].id;
                Qt.callLater(function () {
                    var row = rows.itemAt(root.selectedIndex);
                    if (!row)
                        return;
                    var y = row.mapToItem(flick.contentItem, 0, 0).y;
                    if (y < flick.contentY)
                        flick.contentY = y;
                    else if (y + row.height > flick.contentY + flick.height)
                        flick.contentY = Math.min(flick.contentHeight - flick.height, y + row.height - flick.height);
                });
            }
            onActivateRequested: root.toggleDetails(root.selected())
            onDeleteRequested: root.askRemove(root.selected())
            onTextKey: function (t) {
                var sb = root.selected();
                if (t.toLowerCase() === "r")
                    backend.refresh();
                else if (t.toLowerCase() === "s" && sb && sb.running)
                    backend.action("shell", sb);
                else if (t.toLowerCase() === "g" && sb)
                    backend.action("logs", sb);
            }

            Flickable {
                id: flick
                anchors.fill: parent
                contentWidth: width
                contentHeight: content.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                Column {
                    id: content
                    width: flick.width
                    spacing: Style.space(14)
                    RowLayout {
                        width: parent.width
                        spacing: Style.space(12)
                        Text {
                            text: String.fromCodePoint(0xF01A6)
                            color: Color.accent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.display
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(3)
                            Text {
                                text: "Microsandbox"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.title
                                font.bold: true
                            }
                            Text {
                                text: !backend.ready ? "Connecting to your local runtime…" : backend.healthy ? backend.runningCount + " running · " + backend.sandboxes.length + " total · LOCAL" : "Status unavailable · LOCAL"
                                textFormat: Text.PlainText
                                color: Qt.darker(root.foreground, 1.5)
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                            }
                        }
                        PanelActionButton {
                            iconText: String.fromCodePoint(0xF0450)
                            tooltipText: "Refresh"
                            foreground: root.foreground
                            enabled: !backend.busy
                            onClicked: backend.refresh()
                        }
                    }
                    PanelSeparator {
                        width: parent.width
                        foreground: root.foreground
                    }
                    Text {
                        width: parent.width
                        visible: backend.error !== ""
                        text: backend.error + (backend.sandboxes.length ? "\nShowing previous results. Actions disabled until refresh succeeds." : "")
                        textFormat: Text.PlainText
                        color: Color.urgent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        width: parent.width
                        visible: backend.ready && backend.healthy && backend.sandboxes.length === 0
                        text: "No local sandboxes yet.\nCreate one with msb; it will appear here automatically."
                        textFormat: Text.PlainText
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        wrapMode: Text.WordWrap
                    }
                    Column {
                        width: parent.width
                        spacing: Style.space(8)
                        Repeater {
                            id: rows
                            model: backend.sandboxes
                            delegate: Rectangle {
                                id: card
                                required property var modelData
                                required property int index
                                readonly property bool pending: backend.busy && backend.pendingId === modelData.id
                                readonly property bool controlsEnabled: backend.healthy && !backend.busy
                                readonly property bool expanded: root.expandedIds.indexOf(modelData.id) !== -1
                                width: parent.width
                                height: rowContent.implicitHeight + Style.space(22)
                                radius: Style.cornerRadius
                                color: Util.alpha(root.foreground, root.selectedIndex === index ? 0.07 : 0.025)
                                border.width: 1
                                border.color: root.selectedIndex === index ? Util.alpha(Color.accent, 0.65) : Util.alpha(root.foreground, 0.08)
                                opacity: backend.healthy ? 1 : 0.55
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: root.selectedId = card.modelData.id
                                    onClicked: root.selectedId = card.modelData.id
                                }
                                ColumnLayout {
                                    id: rowContent
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: Style.space(11)
                                    spacing: Style.space(5)
                                    Item {
                                        Layout.fillWidth: true
                                        implicitHeight: heading.implicitHeight
                                        RowLayout {
                                            id: heading
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            spacing: Style.space(8)
                                            Rectangle {
                                                implicitWidth: Style.space(7)
                                                implicitHeight: implicitWidth
                                                radius: width / 2
                                                color: card.modelData.running ? Color.accent : card.modelData.status === "Crashed" ? Color.urgent : Qt.darker(root.foreground, 2)
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: card.modelData.name
                                                textFormat: Text.PlainText
                                                color: root.foreground
                                                font.family: root.fontFamily
                                                font.pixelSize: Style.font.body
                                                font.bold: true
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                visible: !card.expanded && !!card.modelData.usage
                                                text: card.modelData.usage ? card.modelData.usage.cpuSummary : ""
                                                textFormat: Text.PlainText
                                                color: root.foreground
                                                font.family: root.fontFamily
                                                font.pixelSize: Style.font.caption
                                            }
                                            Text {
                                                visible: !card.expanded && !!card.modelData.usage
                                                text: card.modelData.usage ? card.modelData.usage.memorySummary : ""
                                                textFormat: Text.PlainText
                                                color: root.foreground
                                                font.family: root.fontFamily
                                                font.pixelSize: Style.font.caption
                                            }
                                            Text {
                                                text: card.pending ? backend.pendingVerb + "…" : card.modelData.status
                                                textFormat: Text.PlainText
                                                color: card.modelData.status === "Crashed" ? Color.urgent : Color.accent
                                                font.family: root.fontFamily
                                                font.pixelSize: Style.font.caption
                                            }
                                            Text {
                                                text: card.expanded ? "⌄" : "›"
                                                color: root.foreground
                                                font.family: root.fontFamily
                                                font.pixelSize: Style.font.body
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.selectedId = card.modelData.id;
                                                root.toggleDetails(card.modelData);
                                            }
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        visible: card.expanded
                                        text: card.modelData.image
                                        textFormat: Text.PlainText
                                        color: Qt.darker(root.foreground, 1.4)
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        elide: Text.ElideMiddle
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        visible: card.expanded
                                        Text {
                                            Layout.fillWidth: true
                                            text: card.modelData.resources
                                            textFormat: Text.PlainText
                                            color: Qt.darker(root.foreground, 1.4)
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.caption
                                            elide: Text.ElideRight
                                        }
                                        PanelActionButton {
                                            iconText: String.fromCodePoint(0xF018D)
                                            tooltipText: "Open shell in a terminal"
                                            foreground: root.foreground
                                            enabled: card.controlsEnabled && card.modelData.running
                                            onClicked: backend.action("shell", card.modelData)
                                        }
                                        PanelActionButton {
                                            iconText: String.fromCodePoint(0xF0219)
                                            tooltipText: "Follow logs in a terminal"
                                            foreground: root.foreground
                                            enabled: card.controlsEnabled
                                            onClicked: backend.action("logs", card.modelData)
                                        }
                                        PanelActionButton {
                                            iconText: String.fromCodePoint(card.modelData.running ? 0xF04DB : 0xF040A)
                                            tooltipText: card.modelData.running ? "Stop sandbox" : "Start sandbox"
                                            foreground: root.foreground
                                            enabled: card.controlsEnabled && card.modelData.actionable
                                            onClicked: root.toggleSandbox(card.modelData)
                                        }
                                        PanelActionButton {
                                            iconText: String.fromCodePoint(0xF0A7A)
                                            tooltipText: card.modelData.running ? "Stop before removing" : "Remove sandbox…"
                                            foreground: root.foreground
                                            hoverColor: Color.urgent
                                            enabled: card.controlsEnabled && card.modelData.actionable && !card.modelData.running
                                            onClicked: root.askRemove(card.modelData)
                                        }
                                    }
                                    UsageMeter {
                                        Layout.fillWidth: true
                                        visible: card.expanded && !!card.modelData.usage
                                        label: card.modelData.usage ? card.modelData.usage.cpuText : ""
                                        fraction: card.modelData.usage ? card.modelData.usage.cpuFraction : null
                                    }
                                    UsageMeter {
                                        Layout.fillWidth: true
                                        visible: card.expanded && !!card.modelData.usage
                                        label: card.modelData.usage ? card.modelData.usage.memoryText : ""
                                        fraction: card.modelData.usage ? card.modelData.usage.memoryFraction : null
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        visible: card.expanded && card.modelData.running
                                        text: (card.modelData.metricsNote || "") + (card.modelData.usage ? " · updates every 3s" : "")
                                        textFormat: Text.PlainText
                                        color: Qt.darker(root.foreground, 1.6)
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        wrapMode: Text.WordWrap
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        visible: card.expanded && card.modelData.ports.length > 0
                                        text: card.modelData.ports.join(" · ")
                                        textFormat: Text.PlainText
                                        color: Qt.darker(root.foreground, 1.4)
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.caption
                                        wrapMode: Text.WrapAnywhere
                                    }
                                }
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        text: backend.truncated ? "Showing the first 500 sandboxes." : "↑↓ select · enter expand/collapse · s shell · g logs · x remove · r refresh"
                        textFormat: Text.PlainText
                        color: Qt.darker(root.foreground, 1.6)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WordWrap
                    }
                }
            }
            Item {
                id: confirmKeys
                Keys.onPressed: function (event) {
                    if (confirm.handleKey(event))
                        event.accepted = true;
                }
            }
            ConfirmDialog {
                id: confirm
                anchors.fill: parent
                z: 10
                opened: root.removeTarget !== null
                message: root.removeTarget ? "Remove “" + root.removeTarget.name + "”?\nIts managed sandbox data will be deleted. This cannot be undone." : ""
                confirmText: "Remove"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onCanceled: root.cancelRemove()
                onConfirmed: {
                    backend.action("remove", root.removeTarget);
                    root.cancelRemove();
                }
            }
        }
    }
}
