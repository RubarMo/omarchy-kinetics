import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "PostureMath.js" as PostureMath

Item {
  id: root
  visible: false

  property var bar: null
  property var settings: ({})
  property var anchorItem: null
  property var hostWidget: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property bool opened: false
  property bool settingsOpen: false
  property bool stateReady: false
  property bool stateDirectoryReady: false
  property bool saveQueued: false
  property bool reminderVisible: false
  property string reminderSummary: ""
  property string reminderBody: ""

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDirectory: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/kinetics"
  readonly property string statePath: stateDirectory + "/day.json"
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: bar ? bar.urgent : Color.accent

  property bool dayActive: false
  property bool dayEnded: false
  property bool sessionActive: false
  property string phase: "idle"
  property int round: 0
  property double phaseStartedAt: 0
  property double clockNow: Date.now()
  property var sessionPlan: PostureMath.plan(20, 8, 2, 3)
  property var totals: PostureMath.emptyTotals()

  property int draftSitting: 20
  property int draftStanding: 8
  property int draftMoving: 2
  property int draftRounds: 3

  readonly property int configuredSitting: PostureMath.minutes(setting("sittingMinutes", 20), 20)
  readonly property int configuredStanding: PostureMath.minutes(setting("standingMinutes", 8), 8)
  readonly property int configuredMoving: PostureMath.minutes(setting("movingMinutes", 2), 2)
  readonly property int configuredRounds: PostureMath.rounds(setting("rounds", 3), 3)
  readonly property int currentPhaseDuration: sessionActive
    ? PostureMath.phaseDurationSeconds(sessionPlan, phase) : 0
  readonly property int elapsedInPhase: sessionActive
    ? Math.max(0, Math.min(currentPhaseDuration, Math.floor((clockNow - phaseStartedAt) / 1000))) : 0
  readonly property int remainingInPhase: Math.max(0, currentPhaseDuration - elapsedInPhase)
  readonly property real phaseProgress: currentPhaseDuration > 0
    ? Math.min(1, elapsedInPhase / currentPhaseDuration) : 0

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function open() { opened = true }
  function close() { opened = false }
  function toggle() { opened ? close() : open() }

  function formatDuration(seconds) {
    var total = Math.max(0, Math.floor(Number(seconds) || 0))
    var hours = Math.floor(total / 3600)
    var minutes = Math.floor((total % 3600) / 60)
    var remainder = total % 60
    if (hours > 0) return hours + "h " + (minutes < 10 ? "0" : "") + minutes + "m"
    if (minutes > 0) return minutes + "m"
    return remainder + "s"
  }

  function planDescription(value) {
    var plan = value || sessionPlan
    var eachRound = plan.sittingMinutes + plan.standingMinutes + plan.movingMinutes
    return plan.sittingMinutes + "m sit · " + plan.standingMinutes + "m stand · "
      + plan.movingMinutes + "m move × " + plan.rounds + " rounds = " + (eachRound * plan.rounds) + " minutes"
  }

  function shortStatus() {
    if (sessionActive) return PostureMath.phaseLabel(phase) + " — " + formatDuration(remainingInPhase) + " remaining"
    if (dayEnded) return "Kinetics day finished — open for totals"
    if (dayActive) return "Day started — ready for a session"
    return "Kinetics — start your day"
  }

  function stateSnapshot() {
    return {
      schemaVersion: 1,
      dayActive: dayActive,
      dayEnded: dayEnded,
      sessionActive: sessionActive,
      phase: phase,
      round: round,
      phaseStartedAt: phaseStartedAt,
      sessionPlan: sessionPlan,
      totals: totals
    }
  }

  function restoreState(raw) {
    var saved = null
    try {
      saved = JSON.parse(String(raw || ""))
    } catch (error) {
      console.warn("kinetics: ignoring unreadable daily state", error)
    }

    if (saved && saved.schemaVersion === 1) {
      dayActive = saved.dayActive === true
      dayEnded = saved.dayEnded === true
      sessionActive = saved.sessionActive === true && dayActive && !dayEnded
      phase = ["sitting", "standing", "moving"].indexOf(saved.phase) >= 0 ? saved.phase : "idle"
      round = Math.max(0, Math.floor(Number(saved.round) || 0))
      phaseStartedAt = Number(saved.phaseStartedAt) || 0
      sessionPlan = PostureMath.plan(
        saved.sessionPlan ? saved.sessionPlan.sittingMinutes : 20,
        saved.sessionPlan ? saved.sessionPlan.standingMinutes : 8,
        saved.sessionPlan ? saved.sessionPlan.movingMinutes : 2,
        saved.sessionPlan ? saved.sessionPlan.rounds : 3)
      totals = PostureMath.totalsFrom(saved.totals)
      if (!sessionActive) {
        phase = "idle"
        round = 0
        phaseStartedAt = 0
      }
    }
    stateReady = true
    clockNow = Date.now()
    if (sessionActive) Qt.callLater(tick)
  }

  function requestSave() {
    if (!stateReady) return
    saveQueued = true
    if (stateDirectoryReady) writeState()
    else if (!stateDirectoryProcess.running) stateDirectoryProcess.running = true
  }

  function writeState() {
    if (!stateReady || !stateDirectoryReady || !saveQueued) return
    saveQueued = false
    stateFile.setText(JSON.stringify(stateSnapshot(), null, 2) + "\n")
  }

  function addToTotal(position, seconds) {
    var next = PostureMath.totalsFrom(totals)
    if (position === "sitting" || position === "standing" || position === "moving")
      next[position] += Math.max(0, Number(seconds) || 0)
    totals = next
  }

  function showReminder(summary, body) {
    reminderSummary = summary
    reminderBody = body
    reminderVisible = true
    reminderTimer.restart()
  }

  function sendNotification(summary, body) {
    var command = [
      root.omarchyPath + "/bin/omarchy-notification-send",
      // Keep each reminder transient so successive posture changes do not
      // stack below the visible notification area.
      "--app-name", "Kinetics", "-g", "󰔛", "-u", "normal", "-t", "8000", summary, body
    ]
    console.log("kinetics: sending notification", summary)
    showReminder(summary, body)
    Quickshell.execDetached(command)
    Quickshell.execDetached([
      "omarchy-shell", "osd", "show",
      JSON.stringify({
        icon: "󰔛",
        message: summary + "\n" + body,
        duration: 8000
      })
    ])
  }

  // Every change of position receives its own visible desktop notification,
  // including the first sitting block of a session.
  function promptForPosture(position, minutes, roundNumber) {
    var action = position === "standing" ? "STAND" : (position === "moving" ? "MOVE" : "SIT")
    var roundText = "Round " + roundNumber + " of " + sessionPlan.rounds + ". "
    sendNotification("Kinetics: " + action,
      "Change posture now. " + roundText + action.charAt(0) + action.slice(1).toLowerCase()
        + " for " + minutes + " minutes.")
  }

  function startDay() {
    if (dayActive || dayEnded) return
    dayActive = true
    dayEnded = false
    totals = PostureMath.emptyTotals()
    phase = "idle"
    round = 0
    phaseStartedAt = 0
    requestSave()
  }

  function startSession() {
    if (!dayActive || dayEnded || sessionActive) return
    sessionPlan = PostureMath.plan(configuredSitting, configuredStanding, configuredMoving, configuredRounds)
    phase = "sitting"
    round = 1
    phaseStartedAt = Date.now()
    clockNow = phaseStartedAt
    sessionActive = true
    promptForPosture("sitting", sessionPlan.sittingMinutes, round)
    requestSave()
  }

  function completeCurrentPhase(boundary) {
    var completed = phase
    addToTotal(completed, PostureMath.phaseDurationSeconds(sessionPlan, completed))

    if (completed === "sitting") {
      phase = "standing"
      phaseStartedAt = boundary
      promptForPosture("standing", sessionPlan.standingMinutes, round)
      return
    }
    if (completed === "standing") {
      phase = "moving"
      phaseStartedAt = boundary
      promptForPosture("moving", sessionPlan.movingMinutes, round)
      return
    }

    if (round >= sessionPlan.rounds) {
      sessionActive = false
      phase = "idle"
      round = 0
      phaseStartedAt = 0
      sendNotification("Session complete", "Great work. Start another session whenever you are ready.")
      return
    }

    round += 1
    phase = "sitting"
    phaseStartedAt = boundary
    promptForPosture("sitting", sessionPlan.sittingMinutes, round)
  }

  function tick() {
    if (!sessionActive) return
    clockNow = Date.now()
    var safety = 0
    while (sessionActive && safety < 64) {
      var boundary = phaseStartedAt + PostureMath.phaseDurationSeconds(sessionPlan, phase) * 1000
      if (clockNow < boundary) break
      completeCurrentPhase(boundary)
      safety += 1
    }
    if (safety > 0) requestSave()
  }

  function commitPartialPhase() {
    if (!sessionActive) return
    var seconds = Math.max(0, Math.min(
      PostureMath.phaseDurationSeconds(sessionPlan, phase),
      Math.floor((Date.now() - phaseStartedAt) / 1000)))
    addToTotal(phase, seconds)
  }

  function endSession() {
    if (!sessionActive) return
    tick()
    if (!sessionActive) return
    commitPartialPhase()
    sessionActive = false
    phase = "idle"
    round = 0
    phaseStartedAt = 0
    clockNow = Date.now()
    sendNotification("Session ended", "Your completed time has been added to today’s totals.")
    requestSave()
  }

  function endDay() {
    if (!dayActive || dayEnded) return
    tick()
    if (sessionActive) commitPartialPhase()
    sessionActive = false
    dayActive = false
    dayEnded = true
    phase = "idle"
    round = 0
    phaseStartedAt = 0
    clockNow = Date.now()
    sendNotification("Kinetics day finished", "Sat " + formatDuration(totals.sitting)
      + ", stood " + formatDuration(totals.standing) + ", moved " + formatDuration(totals.moving) + ".")
    requestSave()
  }

  function resetForTomorrow() {
    dayActive = false
    dayEnded = false
    sessionActive = false
    phase = "idle"
    round = 0
    phaseStartedAt = 0
    totals = PostureMath.emptyTotals()
    clockNow = Date.now()
    requestSave()
  }

  function openSettings() {
    draftSitting = configuredSitting
    draftStanding = configuredStanding
    draftMoving = configuredMoving
    draftRounds = configuredRounds
    settingsOpen = true
  }

  function saveSettings() {
    var entry = { id: hostWidget ? hostWidget.moduleName : "rubar.kinetics" }
    for (var key in settings) {
      if (key !== "id") entry[key] = settings[key]
    }
    entry.sittingMinutes = PostureMath.minutes(draftSitting, 20)
    entry.standingMinutes = PostureMath.minutes(draftStanding, 8)
    entry.movingMinutes = PostureMath.minutes(draftMoving, 2)
    entry.rounds = PostureMath.rounds(draftRounds, 3)
    settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(entry.id, entry)
    settingsOpen = false
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.stateReady && root.sessionActive
    triggeredOnStart: true
    onTriggered: root.tick()
  }

  Timer {
    id: reminderTimer
    interval: 8000
    repeat: false
    onTriggered: root.reminderVisible = false
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.restoreState(text())
    onLoadFailed: root.restoreState("")
    onFileChanged: reload()
  }

  Process {
    id: stateDirectoryProcess
    command: ["mkdir", "-p", root.stateDirectory]
    onExited: function(exitCode) {
      root.stateDirectoryReady = exitCode === 0
      if (root.stateDirectoryReady) root.writeState()
      else console.warn("kinetics: cannot create state directory", root.stateDirectory)
    }
  }

  Component.onCompleted: stateDirectoryProcess.running = true

  PopupCard {
    id: popup
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    contentWidth: popup.fittedContentWidth(Style.space(420), Style.space(460))
    contentHeight: popup.fittedContentHeight(content.implicitHeight, Style.space(600))

    Column {
      id: content
      width: parent.width
      spacing: Style.space(14)

      PanelHero {
        width: parent.width
        title: root.dayEnded ? "Posture totals" : (root.sessionActive ? PostureMath.phaseLabel(root.phase) : "Kinetics")
        meta: root.dayEnded ? "Day complete" : root.shortStatus()
        detail: root.sessionActive ? ("Round " + root.round + " / " + root.sessionPlan.rounds) : ""
        foreground: root.foreground
        iconComponent: Component {
          Text {
            text: root.sessionActive && root.phase === "standing" ? "󰚀"
              : (root.sessionActive && root.phase === "moving" ? "󰖴" : "󰔛")
            color: root.sessionActive ? root.accent : root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.display
          }
        }
      }

      Column {
        visible: root.sessionActive
        width: parent.width
        spacing: Style.space(7)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.remainingInPhase > 0
            ? root.formatDuration(root.remainingInPhase) + " remaining in this " + root.phase + " block"
            : "Changing position…"
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Rectangle {
          width: parent.width
          height: Math.max(4, Style.space(5))
          radius: height / 2
          color: Qt.darker(root.foreground, 1.8)

          Rectangle {
            width: parent.width * root.phaseProgress
            height: parent.height
            radius: parent.radius
            color: root.accent

            Behavior on width { NumberAnimation { duration: 180 } }
          }
        }
      }

      Column {
        visible: !root.settingsOpen && !root.dayEnded
        width: parent.width
        spacing: Style.space(8)

        PanelSectionHeader {
          text: root.sessionActive ? "THIS SESSION" : "NEXT SESSION"
          foreground: root.foreground
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.planDescription(root.sessionActive ? root.sessionPlan
            : PostureMath.plan(root.configuredSitting, root.configuredStanding, root.configuredMoving, root.configuredRounds))
          color: Qt.darker(root.foreground, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
        }
      }

      Column {
        visible: root.settingsOpen
        width: parent.width
        spacing: Style.space(10)

        PanelSectionHeader {
          text: "SESSION SETTINGS"
          foreground: root.foreground
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Changes apply to the next session."
          color: Qt.darker(root.foreground, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Row {
          spacing: Style.space(8)

          NumberField {
            label: "Sit min"
            value: root.draftSitting
            from: 1; to: 120; stepSize: 1
            fieldWidth: Style.space(76)
            foreground: root.foreground
            accent: root.accent
            onModified: function(value) { root.draftSitting = value }
          }
          NumberField {
            label: "Stand min"
            value: root.draftStanding
            from: 1; to: 120; stepSize: 1
            fieldWidth: Style.space(76)
            foreground: root.foreground
            accent: root.accent
            onModified: function(value) { root.draftStanding = value }
          }
          NumberField {
            label: "Move min"
            value: root.draftMoving
            from: 1; to: 120; stepSize: 1
            fieldWidth: Style.space(76)
            foreground: root.foreground
            accent: root.accent
            onModified: function(value) { root.draftMoving = value }
          }
          NumberField {
            label: "Rounds"
            value: root.draftRounds
            from: 1; to: 12; stepSize: 1
            fieldWidth: Style.space(76)
            foreground: root.foreground
            accent: root.accent
            onModified: function(value) { root.draftRounds = value }
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.planDescription(PostureMath.plan(root.draftSitting, root.draftStanding, root.draftMoving, root.draftRounds))
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
        }
      }

      Column {
        visible: root.dayEnded
        width: parent.width
        spacing: Style.space(10)

        PanelSectionHeader {
          text: "TODAY"
          foreground: root.foreground
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Repeater {
            model: [
              { label: "SIT", value: root.totals.sitting },
              { label: "STAND", value: root.totals.standing },
              { label: "MOVE", value: root.totals.moving }
            ]

            delegate: BorderSurface {
              required property var modelData
              width: (parent.width - parent.spacing * 2) / 3
              height: Style.space(68)
              color: "transparent"
              borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
              radius: Style.cornerRadius

              Column {
                anchors.centerIn: parent
                spacing: Style.space(4)

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  textFormat: Text.PlainText
                  text: modelData.label
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  textFormat: Text.PlainText
                  text: root.formatDuration(modelData.value)
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
              }
            }
          }
        }
      }

      Row {
        visible: root.settingsOpen
        width: parent.width
        spacing: Style.space(8)

        Button {
          width: (parent.width - parent.spacing) / 2
          text: "Cancel"
          bordered: true
          foreground: root.foreground
          accent: root.accent
          onClicked: root.settingsOpen = false
        }
        Button {
          width: (parent.width - parent.spacing) / 2
          text: "Save settings"
          bordered: true
          selected: true
          foreground: root.foreground
          accent: root.accent
          onClicked: root.saveSettings()
        }
      }

      Row {
        visible: !root.settingsOpen && !root.dayActive && !root.dayEnded
        width: parent.width
        spacing: Style.space(8)

        Button {
          width: (parent.width - parent.spacing) / 2
          text: "Start day"
          bordered: true
          selected: true
          foreground: root.foreground
          accent: root.accent
          onClicked: root.startDay()
        }
        Button {
          width: (parent.width - parent.spacing) / 2
          text: "Settings"
          bordered: true
          foreground: root.foreground
          accent: root.accent
          onClicked: root.openSettings()
        }
      }

      Column {
        visible: !root.settingsOpen && root.dayActive && !root.dayEnded
        width: parent.width
        spacing: Style.space(8)

        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            width: (parent.width - parent.spacing) / 2
            text: root.sessionActive ? "End session" : "Start session"
            bordered: true
            selected: !root.sessionActive
            foreground: root.foreground
            accent: root.accent
            onClicked: {
              if (root.sessionActive) root.endSession()
              else root.startSession()
            }
          }
          Button {
            width: (parent.width - parent.spacing) / 2
            text: root.sessionActive ? "End day" : "Settings"
            bordered: true
            foreground: root.foreground
            accent: root.accent
            onClicked: {
              if (root.sessionActive) root.endDay()
              else root.openSettings()
            }
          }
        }

        Button {
          visible: !root.sessionActive
          width: parent.width
          text: "End day"
          bordered: true
          foreground: root.foreground
          accent: root.accent
          onClicked: root.endDay()
        }
      }

      Button {
        visible: !root.settingsOpen && root.dayEnded
        width: parent.width
        text: "Reset for tomorrow"
        bordered: true
        selected: true
        foreground: root.foreground
        accent: root.accent
        onClicked: root.resetForTomorrow()
      }
    }
  }
}
