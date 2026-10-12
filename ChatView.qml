import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui

// Omarchat: one ephemeral LLM conversation.
//
// The view owns one `omarchat-session` process for its whole life. Messages go
// in as {"text": ...} lines on stdin and Omarchat events stream back on stdout
// (backends/lib.sh), whichever agent answers. Hosts load this view only while
// the chat is open, so tearing it down kills the process and the conversation.
Item {
  id: chat

  property string initialPrompt: ""
  // Hosts point these at the plugin's bin/; the defaults resolve on PATH.
  property string sessionScript: "omarchat-session"
  property string modelScript: "omarchat-model"
  property color foreground: "white"
  property color background: "black"
  property color selectedBackground: "gray"
  property color selectedText: "white"
  property string fontFamily: Style.font.menuFamily
  property int cornerRadius: Style.cornerRadius
  // The menu's selected-row border, so the question bubble reads like a
  // selected row under any theme that styles one.
  property var selectedBorderSpec: Border.none()
  // Text selection and the composer use the kit's input tokens (Ui/TextField).
  readonly property color selectionTint: Style.selectionFillFor(chat.foreground, Color.accent)

  readonly property string title: "Omarchat" + (chat.modelName ? " · " + chat.modelName : "")
  // Opened without a question (the standalone card), the view starts as just
  // the composer; hosts size the card from these until the first message.
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
    if (chat.answerIndex < 0 || chat.answerIndex >= messages.count) return
    messages.setProperty(chat.answerIndex, "text", text)
    messages.setProperty(chat.answerIndex, "html", chat.renderMarkdown(text))
    if (role) messages.setProperty(chat.answerIndex, "role", role)
    chat.followEnd(false)
  }

  function appendAnswer(text) {
    if (chat.answerIndex < 0 || chat.answerIndex >= messages.count) return
    var current = messages.get(chat.answerIndex).text
    // Text written before a tool call ("Let me look that up") and the answer
    // after it arrive as separate blocks; keep them from running together.
    if (chat.breakBeforeText && current) current += "\n\n"
    chat.breakBeforeText = false
    chat.setAnswer(current + text)
  }

  // Markdown links render in a fixed blue that ignores linkColor and the
  // palette, and inline HTML in Markdown breaks list items. So render the
  // Markdown once off-screen, export it as HTML, and recolor the links there.
  function renderMarkdown(text) {
    markdownRenderer.textFormat = TextEdit.MarkdownText
    markdownRenderer.text = String(text || "")
    markdownRenderer.textFormat = TextEdit.RichText
    // The export marks its fragment bounds with comments; when the answer
    // opens with a list, the start marker lands inside the first item and
    // the re-import drops the whole list's bullets and indent.
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
    flashTimer.text = text
    chat.status = text
    flashTimer.restart()
  }

  // Follow the stream only while the reader is already at the bottom, so
  // scrolling up to reread an earlier answer isn't yanked away mid-stream.
  function followEnd(force) {
    if (!force && !conversation.atYEnd) return
    Qt.callLater(function() { conversation.positionViewAtEnd() })
  }

  function toolStatus(name, query) {
    if (name === "WebSearch" || name === "web_search")
      return query ? "Searching “" + query + "”" : "Searching the web…"
    return "Working…"
  }

  // Refusals that won't change by retrying (the model isn't on this plan or
  // account). Recorded so settings can grey the model out with the reason.
  readonly property var accessErrors: /not supported|not available|does not have access|no access|model_not_found|does not exist/i

  function handleEvent(line) {
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
        // Died before the first question (missing dependency, no login):
        // say why instead of leaving a card that silently ignores Enter.
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

  // The header names the model and agent this session was started with.
  Process {
    id: modelRead
    command: ["bash", chat.modelScript, "--label"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        if (!chat.modelName && line.trim()) chat.modelName = line.trim()
      }
    }
  }

  // Shared by the composer, which sees keys first, and the view itself.
  function handleKey(event) {
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
            // The card is a fullscreen overlay, so a browser would open
            // underneath it. Following a source is moving on: close the chat.
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

  // Scroll scrims, matching the menu's list.
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

  // The composer is a multi-line input, which the kit's single-line TextField
  // can't be, so it takes the same fill and border states instead.
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

  // Chat-only: the menu needs no key hints, a conversation does. Detail-line
  // styling, so it sits with the rest of the card.
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

  // Take focus only when shown: a chat loaded under an open settings view
  // (opened from the menu's Settings row) must not steal its keys. The host
  // hands focus back with focusInput() when settings close.
  Component.onCompleted: if (chat.visible) input.forceActiveFocus()
}
