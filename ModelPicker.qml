import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui

// Omarchat settings: pick the agent and model the next chat uses.
//
// Lists every agent Omarchat supports (bin/omarchat-models), each model by its
// name, styled and driven like the Omarchy menu: typing filters (the host
// shows the query as its header), rows carry their agent as the detail line,
// a hairline divides agents, and the current choice ends in ✓. Agents that
// can't be used say why, and models a chat found refused are dimmed with the
// reason. Opens from the cache and refreshes in the background.
Item {
  id: picker

  property string modelsScript: "omarchat-models"
  property string currentAgent: ""
  property string currentModel: ""
  property color foreground: "white"
  property color background: "black"
  property color selectedBackground: "gray"
  property color selectedText: "white"
  property var selectedBorderSpec: Border.none()
  property string fontFamily: Style.font.menuFamily
  property int cornerRadius: Style.cornerRadius

  signal picked(string agent, string model, string name)
  signal closed()

  property var agents: []
  property bool refreshing: false
  property string filterText: ""
  property int selectedIndex: -1
  property string firstSection: ""

  // The host's header shows the query, the way the menu and emojis do.
  readonly property string headerText: picker.filterText || "Choose a model…"
  readonly property bool hasQuery: picker.filterText.length > 0

  readonly property real rowReservedBorderLeft: Border.left(picker.selectedBorderSpec)
  readonly property int rowHeight: Math.max(Style.space(58), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  readonly property int dividerHeight: Style.space(17)

  ListModel { id: rows }

  // Scrolling moves rows under a pointer that hasn't moved, and plain hover
  // would then drag the cursor back to whatever row sits under it. Only real
  // pointer movement selects, as in the Omarchy menu.
  PointerMoveGate {
    id: pointerGate
    referenceItem: picker
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse) || !picker.selectable(index)) return
    picker.selectedIndex = index
  }

  function load(cached) {
    listProc.collected = ""
    listProc.command = cached ? ["bash", picker.modelsScript, "--cached"] : ["bash", picker.modelsScript]
    picker.refreshing = !cached
    listProc.running = true
  }

  function providerName(provider) {
    var names = { anthropic: "Anthropic", openai: "OpenAI", google: "Google", openrouter: "OpenRouter" }
    return names[provider] || String(provider || "")
  }

  function matches(model, agentName, terms) {
    var haystack = [model.name, model.id, model.provider || "", agentName].join(" ").toLowerCase()
    for (var i = 0; i < terms.length; i++)
      if (terms[i] && haystack.indexOf(terms[i]) < 0) return false
    return true
  }

  function rebuild() {
    var keep = picker.selectedIndex >= 0 && picker.selectedIndex < rows.count
      ? rows.get(picker.selectedIndex).agent + "/" + rows.get(picker.selectedIndex).model : ""
    var terms = picker.filterText.toLowerCase().trim().split(/\s+/)
    pointerGate.reset()
    rows.clear()
    picker.firstSection = ""

    for (var a = 0; a < picker.agents.length; a++) {
      var agent = picker.agents[a]
      if (!agent.available) {
        if (!picker.hasQuery)
          picker.append({ kind: "notice", agent: agent.id, model: "", label: agent.name, detail: agent.reason || "Unavailable", unavailable: true })
        continue
      }
      var models = agent.models || []
      for (var m = 0; m < models.length; m++) {
        var model = models[m]
        if (!picker.matches(model, agent.name, terms)) continue
        var current = agent.id === picker.currentAgent && model.id === picker.currentModel
        // Same model names can come from several agents and providers; the
        // detail line says whose, like the menu's parent path.
        var whose = model.provider ? agent.name + " · " + picker.providerName(model.provider) : agent.name
        picker.append({
          kind: "model",
          agent: agent.id,
          model: model.id,
          label: model.name + (current ? " ✓" : ""),
          detail: model.unavailable ? whose + " · " + model.unavailable : whose,
          unavailable: !!model.unavailable,
          current: current
        })
      }
    }

    // Keep the cursor on the same model across a refresh; otherwise start on
    // the current choice, or the first one that can be picked.
    var index = -1
    for (var i = 0; i < rows.count && index < 0; i++) {
      var row = rows.get(i)
      if (keep && row.agent + "/" + row.model === keep) index = i
    }
    for (var j = 0; j < rows.count && index < 0 && !picker.hasQuery; j++)
      if (rows.get(j).current) index = j
    if (index < 0) index = picker.nextSelectable(-1, 1)
    picker.selectedIndex = index
    if (index >= 0) Qt.callLater(function() { list.positionViewAtIndex(picker.selectedIndex, ListView.Contain) })
  }

  function append(row) {
    if (!picker.firstSection) picker.firstSection = row.agent
    rows.append({
      kind: row.kind,
      agent: row.agent,
      model: row.model,
      label: row.label,
      detail: row.detail,
      unavailable: row.unavailable,
      current: !!row.current
    })
  }

  function selectable(index) {
    if (index < 0 || index >= rows.count) return false
    var row = rows.get(index)
    return row.kind === "model" && !row.unavailable
  }

  function nextSelectable(from, step) {
    for (var i = from + step; i >= 0 && i < rows.count; i += step)
      if (picker.selectable(i)) return i
    return from >= 0 && picker.selectable(from) ? from : -1
  }

  function move(step) {
    pointerGate.reset()
    var next = picker.nextSelectable(picker.selectedIndex, step)
    if (next >= 0) {
      picker.selectedIndex = next
      list.positionViewAtIndex(next, ListView.Contain)
    }
  }

  function choose(index) {
    if (!picker.selectable(index)) return
    var row = rows.get(index)
    picker.picked(row.agent, row.model, row.label.replace(/ ✓$/, ""))
  }

  function setFilter(text) {
    picker.filterText = text
    picker.selectedIndex = -1
    picker.rebuild()
  }

  Process {
    id: listProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(line) { listProc.collected += line + "\n" }
    }
    onExited: function(exitCode) {
      var wasRefresh = picker.refreshing
      picker.refreshing = false
      try {
        var parsed = JSON.parse(listProc.collected)
        picker.agents = parsed.agents || []
        picker.rebuild()
      } catch (e) { }
      // The cached list is a first paint; always follow it with a refresh.
      if (!wasRefresh) picker.load(false)
    }
  }

  Component.onCompleted: {
    picker.load(true)
    keyCatcher.forceActiveFocus()
  }

  // Keys work like the menu's: type to filter, Backspace / Ctrl+Backspace /
  // Ctrl+U edit the query, arrows move, Enter picks, Esc clears then leaves.
  Item {
    id: keyCatcher
    anchors.fill: parent
    focus: true

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        if (picker.filterText) picker.setFilter("")
        else picker.closed()
        event.accepted = true
      } else if (Util.editsFilter(event, picker.filterText)) {
        picker.setFilter(Util.editedFilter(event, picker.filterText))
        event.accepted = true
      } else if (event.key === Qt.Key_Backspace && !picker.filterText) {
        picker.closed()
        event.accepted = true
      } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier))) {
        picker.move(1)
        event.accepted = true
      } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
        picker.move(-1)
        event.accepted = true
      } else if (event.key === Qt.Key_PageDown) {
        for (var i = 0; i < 6; i++) picker.move(1)
        event.accepted = true
      } else if (event.key === Qt.Key_PageUp) {
        for (var j = 0; j < 6; j++) picker.move(-1)
        event.accepted = true
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        picker.choose(picker.selectedIndex)
        event.accepted = true
      } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
                 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
        picker.setFilter(picker.filterText + event.text)
        event.accepted = true
      }
    }
  }

  ListView {
    id: list
    anchors.fill: parent
    model: rows
    clip: true
    spacing: Style.spacing.xs
    boundsBehavior: Flickable.StopAtBounds

    section.property: "agent"
    section.criteria: ViewSection.FullString
    section.delegate: Item {
      required property string section

      width: ListView.view.width
      height: section === picker.firstSection ? 0 : picker.dividerHeight
      visible: section !== picker.firstSection

      Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.sm
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
        height: Style.spacing.hairline
        color: Util.alpha(picker.foreground, 0.2)
      }
    }

    delegate: BorderSurface {
      id: row
      required property int index
      required property string kind
      required property string label
      required property string detail
      required property bool unavailable

      readonly property bool hasCursor: row.index === picker.selectedIndex

      width: ListView.view.width
      height: picker.rowHeight
      radius: picker.cornerRadius
      color: row.hasCursor ? picker.selectedBackground : "transparent"
      borderSpec: row.hasCursor ? picker.selectedBorderSpec : Border.none()

      Column {
        anchors.left: parent.left
        anchors.leftMargin: picker.rowReservedBorderLeft + Style.space(18)
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.rowPaddingX
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(3)
        opacity: row.unavailable ? 0.45 : 1

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: row.label
          elide: Text.ElideRight
          color: row.hasCursor ? picker.selectedText : picker.foreground
          font.family: picker.fontFamily
          font.pixelSize: Style.font.heading
          font.weight: Font.Medium
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: row.detail
          elide: Text.ElideRight
          color: picker.foreground
          opacity: 0.52
          font.family: picker.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      MouseArea {
        id: rowMouse
        anchors.fill: parent
        enabled: picker.selectable(row.index)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: picker.selectFromPointer(row.index, row, { x: rowMouse.mouseX, y: rowMouse.mouseY })
        onPositionChanged: function(mouse) { picker.selectFromPointer(row.index, row, mouse) }
        onClicked: picker.choose(row.index)
      }
    }
  }

  // Scroll scrims, matching the menu's list.
  Rectangle {
    anchors.left: list.left
    anchors.right: list.right
    anchors.top: list.top
    height: Math.min(Style.space(28), list.height / 2)
    visible: opacity > 0
    opacity: list.contentHeight > list.height
      ? Math.max(0, Math.min(1, (list.contentY - list.originY) / height)) : 0
    gradient: Gradient {
      GradientStop { position: 0; color: picker.background }
      GradientStop { position: 1; color: Util.alpha(picker.background, 0) }
    }
  }

  Rectangle {
    anchors.left: list.left
    anchors.right: list.right
    anchors.bottom: list.bottom
    height: Math.min(Style.space(28), list.height / 2)
    visible: opacity > 0
    opacity: list.contentHeight > list.height
      ? Math.max(0, Math.min(1, (list.originY + list.contentHeight - list.height - list.contentY) / height)) : 0
    gradient: Gradient {
      GradientStop { position: 0; color: Util.alpha(picker.background, 0) }
      GradientStop { position: 1; color: picker.background }
    }
  }

  // Empty state, matching the menu's and emojis'.
  Column {
    anchors.centerIn: parent
    spacing: Style.space(8)
    visible: rows.count === 0

    Text {
      text: "󰈉"
      color: picker.selectedText
      opacity: 0.8
      font.family: picker.fontFamily
      font.pixelSize: Style.font.displayLarge
      horizontalAlignment: Text.AlignHCenter
      width: Style.space(320)
    }

    Text {
      textFormat: Text.PlainText
      text: picker.hasQuery ? "No matches for “" + picker.filterText + "”"
        : (picker.refreshing ? "Looking for models…" : "No agents found")
      color: picker.foreground
      opacity: 0.7
      font.family: picker.fontFamily
      font.pixelSize: Style.font.title
      horizontalAlignment: Text.AlignHCenter
      width: Style.space(320)
    }
  }
}
