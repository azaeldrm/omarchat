import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// Omarchat as a standalone overlay: a menu-styled card holding one ephemeral
// chat. Not keepLoaded on purpose — hiding the plugin destroys this instance,
// and with it the ChatView's session process, so every summon starts fresh.
//
//   omarchy-shell shell toggle azaeldrm.omarchat '{}'
//   omarchy-shell shell summon azaeldrm.omarchat '{"prompt":"What is Hyprland?"}'
//   omarchy-shell shell summon azaeldrm.omarchat '{"settings":true}'
Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  // Plugins install with no hooks, so the session scripts run straight from
  // this plugin's folder rather than from anything put on PATH.
  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")).replace(/\/$/, "")

  property bool opened: false
  property string prompt: ""
  // Settings replace the conversation in the card without ending it; the chat
  // stays loaded underneath. Picking a model before the first question
  // restarts the warm session on it (chatAlive cycles the chat's Loader).
  property bool settingsOpen: false
  property bool chatAlive: true
  property string currentAgent: ""
  property string currentModel: ""
  // Resolved on open, before a session starts: with no usable agent the card
  // shows SetupView instead of a chat that could only fail.
  property bool agentKnown: false
  property bool needsSetup: false

  // Shares the [menu] surface tokens, so themes that style the menu style
  // this card too and the two read as one surface.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color selectedBorder: Color.menu.selectedBorder
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", selectedBorder, 0)
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md

  readonly property bool started: chatLoader.item ? chatLoader.item.started : root.prompt.length > 0
  property int cardWidth: Math.min(Style.space(640), panel.width - Style.gapsOut * 2)
  readonly property int fullCardHeight: Math.min(Style.space(620), Math.round(panel.height * 0.8))
  readonly property int compactCardHeight: root.contentMargin * 2 + root.headerHeight + root.contentSpacing
    + (chatLoader.item ? chatLoader.item.composerBlockHeight : Style.space(70))
  readonly property int setupCardHeight: Math.min(root.fullCardHeight, root.contentMargin * 2 + root.headerHeight
    + root.contentSpacing + (setupLoader.item ? setupLoader.item.preferredHeight : Style.space(260)))
  property int cardHeight: root.settingsOpen || root.started ? root.fullCardHeight
    : root.needsSetup ? root.setupCardHeight : root.compactCardHeight

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    root.prompt = String(payload.prompt || "").trim()
    root.agentKnown = false
    root.opened = true
    agentProbe.running = true
    if (payload.settings) root.openSettings()
    // Keep the model cache current even for people who never open settings:
    // a newly installed or logged-in agent shows up on its own.
    if (!modelsRefresh.running) modelsRefresh.running = true
  }

  function openSettings() {
    // Read the selection first so the picker opens with the current model checked.
    selectionRead.running = true
  }

  function closeSettings() {
    root.settingsOpen = false
    Qt.callLater(function() { if (chatLoader.item) chatLoader.item.focusInput() })
  }

  function restartChat() {
    root.chatAlive = false
    Qt.callLater(function() { root.chatAlive = true })
  }

  Process {
    id: agentProbe
    command: ["bash", root.pluginDir + "/bin/omarchat-model"]
    stdout: SplitParser {
      onRead: function(line) { root.needsSetup = line.split("\t")[0] === "none" }
    }
    onExited: root.agentKnown = true
  }

  Process {
    id: modelsRefresh
    command: ["bash", root.pluginDir + "/bin/omarchat-models"]
  }

  Process {
    id: selectionRead
    command: ["bash", root.pluginDir + "/bin/omarchat-model"]
    stdout: SplitParser {
      onRead: function(line) {
        var fields = line.split("\t")
        root.currentAgent = fields[0] || ""
        root.currentModel = fields[1] || ""
      }
    }
    onExited: root.settingsOpen = true
  }

  Process {
    id: selectionWrite
    property string name: ""
    onExited: function(exitCode) {
      root.settingsOpen = false
      if (exitCode !== 0) return
      if (!root.started) {
        root.restartChat()
      } else if (chatLoader.item) {
        chatLoader.item.flash("Next chat uses " + selectionWrite.name)
        Qt.callLater(function() { chatLoader.item.focusInput() })
      }
    }
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "azaeldrm.omarchat")
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchat"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.horizontalCenter: parent.horizontalCenter
      // Pin the top where the full card will sit, so the compact card grows
      // downward into the conversation instead of re-centering.
      y: Math.max(Style.gapsOut, Math.round((panel.height - root.fullCardHeight) / 2))
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Item {
          width: parent.width
          height: root.headerHeight

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            // In settings the header is the model search, like the menu's.
            text: root.settingsOpen
              ? (settingsLoader.item ? settingsLoader.item.headerText : "Choose a model…")
              : "󰚩  " + (root.needsSetup ? "Set up an agent…" : (chatLoader.item ? chatLoader.item.title : "Omarchat"))
            color: root.foreground
            opacity: root.settingsOpen && settingsLoader.item && settingsLoader.item.hasQuery ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.settingsOpen ? root.closeSettings() : root.openSettings()
          }
        }

        Loader {
          id: chatLoader
          width: parent.width
          height: parent.height - root.headerHeight - root.contentSpacing
          visible: !root.settingsOpen && !root.needsSetup
          active: root.opened && root.chatAlive && root.agentKnown && !root.needsSetup
          sourceComponent: ChatView {
            initialPrompt: root.prompt
            selectedBorderSpec: root.selectedBorderSpec
            sessionScript: root.pluginDir + "/bin/omarchat-session"
            modelScript: root.pluginDir + "/bin/omarchat-model"
            foreground: root.foreground
            background: root.background
            selectedBackground: root.selectedBackground
            selectedText: root.selectedText
            fontFamily: root.fontFamily
            cornerRadius: root.cornerRadius
            onCloseRequested: root.dismiss()
            onSettingsRequested: root.openSettings()
          }
        }

        Loader {
          id: setupLoader
          width: parent.width
          height: parent.height - root.headerHeight - root.contentSpacing
          visible: root.needsSetup && !root.settingsOpen
          active: root.opened && root.agentKnown && root.needsSetup
          sourceComponent: SetupView {
            modelsScript: root.pluginDir + "/bin/omarchat-models"
            foreground: root.foreground
            background: root.background
            selectedBackground: root.selectedBackground
            selectedText: root.selectedText
            selectedBorderSpec: root.selectedBorderSpec
            fontFamily: root.fontFamily
            cornerRadius: root.cornerRadius
            onCloseRequested: root.dismiss()
          }
        }

        Loader {
          id: settingsLoader
          width: parent.width
          height: parent.height - root.headerHeight - root.contentSpacing
          visible: root.settingsOpen
          active: root.opened && root.settingsOpen
          sourceComponent: ModelPicker {
            modelsScript: root.pluginDir + "/bin/omarchat-models"
            currentAgent: root.currentAgent
            currentModel: root.currentModel
            foreground: root.foreground
            background: root.background
            selectedBackground: root.selectedBackground
            selectedText: root.selectedText
            selectedBorderSpec: root.selectedBorderSpec
            fontFamily: root.fontFamily
            cornerRadius: root.cornerRadius
            onClosed: root.closeSettings()
            onPicked: function(agent, model, name) {
              selectionWrite.name = name
              selectionWrite.command = ["bash", root.pluginDir + "/bin/omarchat-model", "set", agent, model, name]
              selectionWrite.running = true
            }
          }
        }
      }
    }
  }
}
