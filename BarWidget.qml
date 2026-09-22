import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "rubar.kinetics"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened : false
  readonly property bool sessionActive: panelLoader.item ? panelLoader.item.sessionActive : false
  readonly property string currentPhase: panelLoader.item ? panelLoader.item.phase : "idle"

  function injectPanel() {
    var panel = panelLoader.item
    if (!panel) return
    panel.bar = root.bar
    panel.settings = root.settings
    panel.anchorItem = button
    panel.hostWidget = root
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  // A textual state is deliberately used instead of a Nerd Font glyph: it
  // makes the next posture obvious at a glance, even if a font lacks a
  // particular pictogram.
  function actionLabel() {
    if (currentPhase === "standing") return "STAND"
    if (currentPhase === "moving") return "MOVE"
    if (currentPhase === "sitting") return "SIT"
    return "KINETICS"
  }

  function tooltip() {
    if (!panelLoader.item) return "Kinetics"
    return panelLoader.item.shortStatus()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }

  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.actionLabel()
    active: root.sessionActive
    horizontalMargin: 7
    fontSize: Style.font.bodySmall
    tooltipText: root.tooltip()

    onPressed: function(button) {
      if (button === Qt.LeftButton) root.togglePanel()
    }
  }
}
