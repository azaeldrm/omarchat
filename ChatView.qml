import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: chat

  property string initialPrompt: ""
  property string sessionScript: "omarchat-session"
  property string modelScript: "omarchat-model"
  property color foreground: "white"
  property color background: "black"
  property color selectedBackground: "gray"
  property color selectedText: "white"
  property string fontFamily: Style.font.menuFamily
  property int cornerRadius: Style.cornerRadius
  property var selectedBorderSpec: Border.none()
  readonly property color selectionTint: Style.selectionFillFor(chat.foreground, Color.accent)

  readonly property string title: "Omarchat" + (chat.modelName ? " · " + chat.modelName : "")
  readonly property bool started: messages.count > 0
  readonly property int composerBlockHeight: composer.height + Style.spacing.md + hints.height

  signal closeRequested()
  signal settingsRequested()

  property bool busy: false
  property bool ended: false
  property string status: ""
  property string modelName: ""
  property int answerIndex: -1
  property bool breakBeforeText: false
  property string stderrText: ""

  ListModel { id: messages }

  function send(text) {
    // Show a question with an empty answer under it, and send it to the session.
    var prompt = String(text || "").trim()
    if (!prompt || chat.busy || chat.ended) return false

    messages.append({ role: "user", text: prompt, html: "" })
    messages.append({ role: "assistant", text: "", html: "" })
    chat.answerIndex = messages.count - 1
    chat.breakBeforeText = false
    chat.busy = true
    chat.status = "Thinking…"
    session.write(JSON.stringify({ text: prompt }) + "\n")
    chat.followEnd(true)
    return true
  }

  function setAnswer(text, role) {
    // Replace the current answer's text, and its role if given.
    if (chat.answerIndex < 0 || chat.answerIndex >= messages.count) return
    messages.setProperty(chat.answerIndex, "text", text)
    messages.setProperty(chat.answerIndex, "html", chat.renderMarkdown(text))
    if (role) messages.setProperty(chat.answerIndex, "role", role)
    chat.followEnd(false)
  }

  function appendAnswer(text) {
    // Add streamed text to the current answer.
    if (chat.answerIndex < 0 || chat.answerIndex >= messages.count) return
    var current = messages.get(chat.answerIndex).text
    if (chat.breakBeforeText && current) current += "\n\n"
    chat.breakBeforeText = false
    chat.setAnswer(current + text)
  }

  function renderMarkdown(text) {
    // Markdown to HTML, with links in the theme's colors.
    markdownRenderer.textFormat = TextEdit.MarkdownText
    markdownRenderer.text = String(text || "")
    markdownRenderer.textFormat = TextEdit.RichText
    return markdownRenderer.getFormattedText(0, markdownRenderer.length)
      .replace(/<!--(Start|End)Fragment-->/g, "")
      .replace(/#0000ff/gi, String(chat.selectedText))
  }

  TextEdit {
    id: markdownRenderer
    visible: false
    font.family: chat.fontFamily
    font.pixelSize: Style.font.title
  }

  function lastAnswer() {
    // The text of the most recent non-empty answer.
    for (var i = messages.count - 1; i >= 0; i--) {
      var row = messages.get(i)
      if (row.role === "assistant" && row.text) return row.text
    }
    return ""
  }

  function copyLastAnswer() {
    var text = chat.lastAnswer()
    if (!text) return
    Quickshell.execDetached(["wl-copy", "--", text])
    chat.flash("Copied answer")
  }

  function focusInput() {
    input.forceActiveFocus()
  }

  function flash(text) {
    // Show a status message briefly.
    flashTimer.text = text
    chat.status = text
    flashTimer.restart()
  }

  function followEnd(force) {
    // Scroll to the end, unless the reader scrolled up (force scrolls anyway).
    if (!force && !conversation.atYEnd) return
    Qt.callLater(function() { conversation.positionViewAtEnd() })
  }

  function toolStatus(name, query) {
    // The status line for a tool the model is using.
    if (name === "WebSearch" || name === "web_search")
      return query ? "Searching “" + query + "”" : "Searching the web…"
    return "Working…"
  }

  readonly property var accessErrors: /not supported|not available|does not have access|no access|model_not_found|does not exist/i

  function handleEvent(line) {
    // Apply one session event (lib.sh's event format) to the conversation.
    var event
    try { event = JSON.parse(line) } catch (e) { return }

    if (event.type === "text") {
      chat.status = ""
      chat.appendAnswer(String(event.delta || ""))
    } else if (event.type === "tool") {
      chat.status = chat.toolStatus(event.name, event.query)
      chat.breakBeforeText = true
    } else if (event.type === "answer") {
      var finalText = String(event.text || "").trim()
      if (finalText) chat.setAnswer(finalText)
    } else if (event.type === "error") {
      var message = String(event.text || "").trim() || "Something went wrong."
      chat.setAnswer(message, "error")
      if (chat.accessErrors.test(message))
        Quickshell.execDetached(["bash", chat.modelScript, "unavailable", message])
    } else if (event.type === "done") {
      chat.busy = false
      chat.status = ""
    }
  }

  Process {
    id: session
    command: ["bash", chat.sessionScript]
    stdinEnabled: true
    running: true

    onStarted: chat.send(chat.initialPrompt)

    stdout: SplitParser {
      onRead: function(line) { chat.handleEvent(line) }
    }

    stderr: SplitParser {
      onRead: function(line) { chat.stderrText += line + "\n" }
    }

    onExited: function(exitCode) {
      chat.ended = true
      chat.status = ""
      if (!chat.busy) {
        if (!chat.started && chat.stderrText.trim()) {
          messages.append({ role: "error", text: "", html: "" })
          chat.answerIndex = messages.count - 1
          chat.setAnswer(chat.stderrText.trim(), "error")
        }
        return
      }
      chat.busy = false
      chat.setAnswer(chat.stderrText.trim() || ("The session ended unexpectedly (exit " + exitCode + ")."), "error")
    }
  }

  Component.onDestruction: session.running = false

  Timer {
    id: flashTimer
    property string text: ""
    interval: 1800
    onTriggered: if (chat.status === flashTimer.text) chat.status = ""
  }

  property string labelSource: ""
  onLabelSourceChanged: if (!chat.started) chat.modelName = chat.labelSource

  function handleKey(event) {
    // Handle Esc, Ctrl+, and Ctrl+Y, for both the composer and the view.
    if (event.key === Qt.Key_Escape) {
      chat.closeRequested()
      event.accepted = true
    } else if (event.key === Qt.Key_Comma && event.modifiers === Qt.ControlModifier) {
      chat.settingsRequested()
      event.accepted = true
    } else if (event.key === Qt.Key_Y && event.modifiers === Qt.ControlModifier) {
      chat.copyLastAnswer()
      event.accepted = true
    } else if (event.key === Qt.Key_PageUp) {
      conversation.flick(0, Style.space(2400))
      event.accepted = true
    } else if (event.key === Qt.Key_PageDown) {
      conversation.flick(0, -Style.space(2400))
      event.accepted = true
    }
  }

  Keys.onPressed: function(event) { chat.handleKey(event) }

  ListView {
    id: conversation
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: composer.top
    anchors.bottomMargin: chat.started ? Style.spacing.md : 0
    visible: chat.started
    model: messages
    clip: true
    spacing: Style.spacing.md
    boundsBehavior: Flickable.StopAtBounds

    delegate: Item {
      id: message
      required property int index
      required property string role
      required property string text
      required property string html

      readonly property bool isUser: message.role === "user"
      readonly property bool isLast: message.index === messages.count - 1

      width: ListView.view.width
      height: bubble.height + (statusLine.visible ? statusLine.height + Style.spacing.md : 0)

      BorderSurface {
        id: bubble
        width: parent.width
        height: body.height + (message.isUser ? Style.spacing.lg * 2 : 0)
        radius: chat.cornerRadius
        color: message.isUser ? chat.selectedBackground : "transparent"
        borderSpec: message.isUser ? chat.selectedBorderSpec : Border.none()

        TextEdit {
          id: body
          x: message.isUser ? Style.spacing.rowPaddingX : Style.spacing.sm
          y: message.isUser ? Style.spacing.lg : 0
          width: parent.width - x * 2
          readOnly: true
          selectByMouse: true
          activeFocusOnPress: false
          wrapMode: TextEdit.Wrap
          textFormat: message.isUser ? TextEdit.PlainText : TextEdit.RichText
          text: message.isUser ? message.text : message.html
          visible: message.text.length > 0
          color: message.isUser ? chat.selectedText : chat.foreground
          opacity: message.role === "error" ? 0.7 : 1
          selectionColor: chat.selectionTint
          selectedTextColor: message.isUser ? chat.selectedText : chat.foreground
          font.family: chat.fontFamily
          font.pixelSize: Style.font.title
          onLinkActivated: function(link) {
            Qt.openUrlExternally(link)
            chat.closeRequested()
          }

          HoverHandler {
            enabled: body.hoveredLink.length > 0
            cursorShape: Qt.PointingHandCursor
          }
        }
      }

      Text {
        id: statusLine
        anchors.top: bubble.bottom
        anchors.topMargin: Style.spacing.md
        x: Style.spacing.sm
        width: parent.width - x * 2
        visible: message.isLast && !message.isUser && chat.status.length > 0
        textFormat: Text.PlainText
        text: "󰇘 " + chat.status
        elide: Text.ElideRight
        color: chat.foreground
        font.family: chat.fontFamily
        font.pixelSize: Style.font.bodySmall

        SequentialAnimation on opacity {
          running: statusLine.visible && chat.busy
          loops: Animation.Infinite
          NumberAnimation { from: 0.7; to: 0.3; duration: 700; easing.type: Easing.InOutQuad }
          NumberAnimation { from: 0.3; to: 0.7; duration: 700; easing.type: Easing.InOutQuad }
          onStopped: statusLine.opacity = 0.52
        }
      }
    }
  }

  Rectangle {
    anchors.left: conversation.left
    anchors.right: conversation.right
    anchors.top: conversation.top
    height: Math.min(Style.space(28), conversation.height / 2)
    visible: conversation.visible && opacity > 0
    opacity: conversation.contentHeight > conversation.height
      ? Math.max(0, Math.min(1, (conversation.contentY - conversation.originY) / height)) : 0
    gradient: Gradient {
      GradientStop { position: 0; color: chat.background }
      GradientStop { position: 1; color: Util.alpha(chat.background, 0) }
    }
  }

  Rectangle {
    anchors.left: conversation.left
    anchors.right: conversation.right
    anchors.bottom: conversation.bottom
    height: Math.min(Style.space(28), conversation.height / 2)
    visible: conversation.visible && opacity > 0
    opacity: conversation.contentHeight > conversation.height
      ? Math.max(0, Math.min(1, (conversation.originY + conversation.contentHeight - conversation.height - conversation.contentY) / height)) : 0
    gradient: Gradient {
      GradientStop { position: 0; color: Util.alpha(chat.background, 0) }
      GradientStop { position: 1; color: chat.background }
    }
  }

  BorderSurface {
    id: composer
    readonly property bool hot: composerHover.hovered
    readonly property var stateSpec: Border.controlSpec(input.activeFocus ? "focus" : (composer.hot ? "hover-cursor" : "normal"), chat.foreground, Color.accent)

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: hints.top
    anchors.bottomMargin: Style.spacing.md
    height: Math.min(input.contentHeight, Style.font.title * 6) + Style.spacing.inputPaddingY * 2
      + Border.top(composer.stateSpec) + Border.bottom(composer.stateSpec)
    radius: chat.cornerRadius
    color: Style.controlFill(input.activeFocus, composer.hot, chat.foreground, Color.accent)
    borderSpec: composer.stateSpec

    HoverHandler { id: composerHover }

    Flickable {
      id: inputScroll
      anchors.fill: parent
      anchors.leftMargin: Style.spacing.controlPaddingX + Border.left(composer.stateSpec)
      anchors.rightMargin: Style.spacing.controlPaddingX + Border.right(composer.stateSpec)
      anchors.topMargin: Style.spacing.inputPaddingY + Border.top(composer.stateSpec)
      anchors.bottomMargin: Style.spacing.inputPaddingY + Border.bottom(composer.stateSpec)
      contentHeight: input.contentHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      TextEdit {
        id: input
        width: inputScroll.width
        focus: true
        wrapMode: TextEdit.Wrap
        textFormat: TextEdit.PlainText
        color: chat.foreground
        selectionColor: chat.selectionTint
        selectedTextColor: chat.foreground
        font.family: chat.fontFamily
        font.pixelSize: Style.font.title
        onCursorRectangleChanged: {
          if (cursorRectangle.y < inputScroll.contentY) inputScroll.contentY = cursorRectangle.y
          else if (cursorRectangle.y + cursorRectangle.height > inputScroll.contentY + inputScroll.height)
            inputScroll.contentY = cursorRectangle.y + cursorRectangle.height - inputScroll.height
        }

        Keys.onPressed: function(event) {
          var enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
          if (enter && !(event.modifiers & Qt.ShiftModifier)) {
            if (chat.send(input.text)) input.text = ""
            event.accepted = true
          } else {
            chat.handleKey(event)
          }
        }

        Text {
          anchors.fill: parent
          visible: !input.text
          textFormat: Text.PlainText
          text: chat.ended ? "Session ended — Esc to close"
            : chat.busy ? "Answering…"
            : chat.started ? "Ask a follow-up…" : "Ask anything…"
          color: chat.foreground
          opacity: 0.58
          font: input.font
          elide: Text.ElideRight
        }
      }
    }
  }

  Text {
    id: hints
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    textFormat: Text.PlainText
    text: "↵ send   ⇧↵ newline   ctrl+y copy   ctrl+, settings   esc close"
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideLeft
    color: chat.foreground
    opacity: 0.52
    font.family: chat.fontFamily
    font.pixelSize: Style.font.caption
  }

  Component.onCompleted: {
    chat.modelName = chat.labelSource
    if (chat.visible) input.forceActiveFocus()
  }
}
