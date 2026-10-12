import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui

// Shown instead of a chat when no supported agent can be used yet. Lists the
// agents Omarchat works with and why each isn't ready; choosing one hands off
// to Omarchy's own setup (omarchy-default-agent), which installs the agent if
// needed, makes it the default, and opens it so the user can sign in.
Item {
  id: setup

  property string modelsScript: "omarchat-models"
  property color foreground: "white"
  property color background: "black"
  property color selectedBackground: "gray"
  property color selectedText: "white"
  property var selectedBorderSpec: Border.none()
  property string fontFamily: Style.font.menuFamily
  property int cornerRadius: Style.cornerRadius

  signal closeRequested()

  property var agents: []
  property int selectedIndex: 0

  // Same row anatomy as the Omarchy menu's: label over a detail line.
  readonly property int rowHeight: Math.max(Style.space(58), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  readonly property real rowReservedBorderLeft: Border.left(setup.selectedBorderSpec)
  // Hosts size the card from this, so it fits the message and the agent rows.
  readonly property int preferredHeight: intro.height + Style.spacing.md
    + Math.max(1, setup.agents.length) * (setup.rowHeight + Style.spacing.xs)

  // Only real pointer movement moves the cursor (see ModelPicker.qml).
  PointerMoveGate {
    id: pointerGate
    referenceItem: setup
  }

  function selectFromPointer(index, item, mouse) {
    if (pointerGate.moved(item, mouse)) setup.selectedIndex = index
  }

  function load(cached) {
    listProc.collected = ""
    listProc.cached = cached
    listProc.command = cached ? ["bash", setup.modelsScript, "--cached"] : ["bash", setup.modelsScript]
    listProc.running = true
  }

  function setUp(index) {
    if (index < 0 || index >= setup.agents.length) return
    Quickshell.execDetached(["omarchy-default-agent", setup.agents[index].id])
    setup.closeRequested()
  }

  Process {
    id: listProc
    property string collected: ""
    property bool cached: false
    stdout: SplitParser {
      onRead: function(line) { listProc.collected += line + "\n" }
    }
    onExited: {
      try { setup.agents = JSON.parse(listProc.collected).agents || [] } catch (e) { }
      // The cache is a first paint; the fresh check says what changed.
      if (listProc.cached) setup.load(false)
    }
  }

  Component.onCompleted: {
    setup.load(true)
    keys.forceActiveFocus()
  }

  Item {
    id: keys
    anchors.fill: parent
    focus: true

    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        setup.closeRequested()
        event.accepted = true
      } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
        pointerGate.reset()
        if (setup.agents.length) setup.selectedIndex = (setup.selectedIndex + 1) % setup.agents.length
        event.accepted = true
      } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
        pointerGate.reset()
        if (setup.agents.length) setup.selectedIndex = (setup.selectedIndex - 1 + setup.agents.length) % setup.agents.length
        event.accepted = true
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        setup.setUp(setup.selectedIndex)
        event.accepted = true
      }
    }
  }

  Column {
    id: intro
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: Style.spacing.sm
    anchors.rightMargin: Style.space(4)
    spacing: Style.space(6)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      text: "No agent is set up yet. Omarchat answers through an AI agent you already use. Choose one to set it up: "
        + "Omarchy installs it if needed, makes it your default agent, and opens it so you can sign in. "
        + "Then open Omarchat again."
      color: setup.foreground
      opacity: 0.7
      font.family: setup.fontFamily
      font.pixelSize: Style.font.body
      lineHeight: 1.15
    }
  }

  ListView {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: intro.bottom
    anchors.topMargin: Style.spacing.md
    anchors.bottom: parent.bottom
    model: setup.agents
    clip: true
    spacing: Style.spacing.xs
    boundsBehavior: Flickable.StopAtBounds

    delegate: BorderSurface {
      id: row
      required property int index
      required property var modelData

      readonly property bool hasCursor: row.index === setup.selectedIndex

      width: ListView.view.width
      height: setup.rowHeight
      radius: setup.cornerRadius
      color: row.hasCursor ? setup.selectedBackground : "transparent"
      borderSpec: row.hasCursor ? setup.selectedBorderSpec : Border.none()

      Column {
        anchors.left: parent.left
        anchors.leftMargin: setup.rowReservedBorderLeft + Style.space(18)
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.rowPaddingX
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(3)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: row.modelData.name
          elide: Text.ElideRight
          color: row.hasCursor ? setup.selectedText : setup.foreground
          font.family: setup.fontFamily
          font.pixelSize: Style.font.heading
          font.weight: Font.Medium
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: row.modelData.available ? "Ready: open Omarchat again" : (row.modelData.reason || "Not set up")
          elide: Text.ElideRight
          color: setup.foreground
          opacity: 0.52
          font.family: setup.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: setup.selectFromPointer(row.index, row, { x: rowMouse.mouseX, y: rowMouse.mouseY })
        onPositionChanged: function(mouse) { setup.selectFromPointer(row.index, row, mouse) }
        onClicked: setup.setUp(row.index)
      }
    }
  }
}
