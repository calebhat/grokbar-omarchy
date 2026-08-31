import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar widget: Grok weekly pool, plus optional Cursor monthly pools and
// optional Grok Bot weekly pool. Both extras are off by default; panel
// settings toggles (showCursorUsage / showGrokBotUsage) turn them on.
// Each provider is icon + % + reset (5d / 12h). Cursor also shows Other Models %.
// Self-hides a provider with no usable session or period-pool data.
// Left click toggles the panel; right click refreshes.
BarWidget {
  id: root
  moduleName: "rlimberger.grokbar-omarchy"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property double nowMs: Date.now()
  property real primaryPercent: -1
  property string resetAt: ""
  property string periodStart: ""
  property string tierLabel: ""
  property string grokLoginName: ""
  property string grokLoginEmail: ""
  property string subscriptionPeriodEnd: ""
  property bool subscriptionCancelsAtEnd: false
  property string usageStatusText: ""
  property string authHelpText: ""
  property var categories: []
  property bool hasData: false
  property bool refreshing: false
  // Signed in with usable credentials (auth.json present / refreshable).
  property bool grokAvailable: false

  // Cursor (X-login session only — Google Cursor accounts are ignored).
  property real cursorAutoPercent: -1
  property real cursorApiPercent: -1
  property string cursorResetAt: ""
  property string cursorPeriodStart: ""
  property string cursorTierLabel: ""
  property string cursorLoginName: ""
  property string cursorLoginEmail: ""
  property string cursorUsageStatusText: ""
  property string cursorAuthHelpText: ""
  property bool cursorHasData: false
  property bool cursorRefreshing: false
  property bool cursorAvailable: false

  // Grok Bot weekly pool (same Cursor session as the monthly pools).
  property real grokBotPercent: -1
  property string grokBotResetAt: ""
  property string grokBotPeriodStart: ""
  property string grokBotTierLabel: ""
  property string grokBotUsageStatusText: ""
  property string grokBotAuthHelpText: ""
  property bool grokBotHasData: false

  readonly property int refreshIntervalSec: Math.max(30, Number(setting("refreshIntervalSec", 300)) || 300)
  // Off unless the panel toggle (or shell.json) turns it on. Bind to
  // `settings` directly so persistSettings() redraws without a reload.
  readonly property bool showCursorUsage: !!(settings && settings.showCursorUsage === true)
  readonly property bool showGrokBotUsage: !!(settings && settings.showGrokBotUsage === true)
  readonly property bool needsCursorSession: showCursorUsage || showGrokBotUsage

  // TEMP QA hook: force over-pace styling (leave false in production).
  readonly property bool simulateOverPace: false

  // Expected usage by now = elapsed / period (0–1). -1 when unknown.
  readonly property real expectedPace: {
    var start = root.parseTimeMs(periodStart)
    var end = root.parseTimeMs(resetAt)
    if (!(start > 0) || !(end > start)) {
      // Weekly fallback: 7d before reset.
      if (!(end > 0)) return -1
      start = end - 7 * 24 * 3600 * 1000
    }
    var frac = (root.nowMs - start) / (end - start)
    if (!isFinite(frac)) return -1
    return Math.max(0, Math.min(1, frac))
  }

  // Displayed usage % (simulation can push past the pace marker).
  readonly property real displayPercent: {
    if (!root.simulateOverPace || !(primaryPercent >= 0) || !(expectedPace >= 0))
      return primaryPercent
    return Math.max(0, Math.min(1, Math.max(primaryPercent, expectedPace + 0.15)))
  }

  // Over budget if used more than the linear pace marker allows.
  readonly property bool overPace: expectedPace >= 0 && displayPercent >= 0
    && displayPercent > expectedPace + 0.0001
  readonly property bool grokAlarming: displayPercent >= 0.9 || overPace
  readonly property string primaryText: displayPercent >= 0 ? Math.round(displayPercent * 100) + "%" : ""
  readonly property string resetText: {
    if (resetAt === "") return ""
    var ms = new Date(resetAt).getTime() - root.nowMs
    return isFinite(ms) ? root.formatBarDuration(ms) : ""
  }

  // Monthly expected usage by now. Fallback: 1 month before reset (not Grok's 7d).
  readonly property real cursorExpectedPace: {
    var start = root.parseTimeMs(cursorPeriodStart)
    var end = root.parseTimeMs(cursorResetAt)
    if (!(start > 0) || !(end > start)) {
      if (!(end > 0)) return -1
      start = end - 30 * 24 * 3600 * 1000
    }
    var frac = (root.nowMs - start) / (end - start)
    if (!isFinite(frac)) return -1
    return Math.max(0, Math.min(1, frac))
  }

  readonly property real cursorAutoDisplay: {
    if (!root.simulateOverPace || !(cursorAutoPercent >= 0) || !(cursorExpectedPace >= 0))
      return cursorAutoPercent
    return Math.max(0, Math.min(1, Math.max(cursorAutoPercent, cursorExpectedPace + 0.15)))
  }
  readonly property real cursorApiDisplay: {
    if (!root.simulateOverPace || !(cursorApiPercent >= 0) || !(cursorExpectedPace >= 0))
      return cursorApiPercent
    return Math.max(0, Math.min(1, Math.max(cursorApiPercent, cursorExpectedPace + 0.15)))
  }
  readonly property bool cursorAutoOverPace: cursorExpectedPace >= 0 && cursorAutoDisplay >= 0
    && cursorAutoDisplay > cursorExpectedPace + 0.0001
  readonly property bool cursorApiOverPace: cursorExpectedPace >= 0 && cursorApiDisplay >= 0
    && cursorApiDisplay > cursorExpectedPace + 0.0001
  readonly property bool cursorAlarming: cursorAutoDisplay >= 0.9 || cursorApiDisplay >= 0.9
    || cursorAutoOverPace || cursorApiOverPace
  readonly property string cursorAutoText: cursorAutoDisplay >= 0 ? Math.round(cursorAutoDisplay * 100) + "%" : ""
  readonly property string cursorApiText: cursorApiDisplay >= 0 ? Math.round(cursorApiDisplay * 100) + "%" : ""
  readonly property string cursorResetText: {
    if (cursorResetAt === "") return ""
    var ms = new Date(cursorResetAt).getTime() - root.nowMs
    return isFinite(ms) ? root.formatBarDuration(ms) : ""
  }

  readonly property real grokBotExpectedPace: {
    var start = root.parseTimeMs(grokBotPeriodStart)
    var end = root.parseTimeMs(grokBotResetAt)
    if (!(start > 0) || !(end > start)) {
      if (!(end > 0)) return -1
      start = end - 7 * 24 * 3600 * 1000
    }
    var frac = (root.nowMs - start) / (end - start)
    if (!isFinite(frac)) return -1
    return Math.max(0, Math.min(1, frac))
  }
  readonly property real grokBotDisplay: {
    if (!root.simulateOverPace || !(grokBotPercent >= 0) || !(grokBotExpectedPace >= 0))
      return grokBotPercent
    return Math.max(0, Math.min(1, Math.max(grokBotPercent, grokBotExpectedPace + 0.15)))
  }
  readonly property bool grokBotOverPace: grokBotExpectedPace >= 0 && grokBotDisplay >= 0
    && grokBotDisplay > grokBotExpectedPace + 0.0001
  readonly property bool grokBotAlarming: grokBotDisplay >= 0.9 || grokBotOverPace
  readonly property string grokBotText: grokBotDisplay >= 0 ? Math.round(grokBotDisplay * 100) + "%" : ""
  readonly property string grokBotResetText: {
    if (grokBotResetAt === "") return ""
    var ms = new Date(grokBotResetAt).getTime() - root.nowMs
    return isFinite(ms) ? root.formatBarDuration(ms) : ""
  }

  readonly property bool grokVisible: grokAvailable && hasData
  readonly property bool cursorVisible: showCursorUsage && cursorAvailable && cursorHasData
  readonly property bool grokBotVisible: showGrokBotUsage && cursorAvailable && grokBotHasData
  readonly property bool alarming: grokAlarming
    || (grokBotVisible && grokBotAlarming)
    || (cursorVisible && cursorAlarming)
  readonly property string verticalIcon: {
    if (grokVisible && grokAlarming) return "grok"
    if (grokBotVisible && grokBotAlarming) return "bot"
    if (cursorVisible && cursorAlarming) return "cursor"
    if (grokVisible) return "grok"
    if (grokBotVisible) return "bot"
    if (cursorVisible) return "cursor"
    return ""
  }

  readonly property string scannerPath: String(Qt.resolvedUrl("scripts/grokbar_scanner.py")).replace("file://", "")
  readonly property string cursorScannerPath: String(Qt.resolvedUrl("scripts/cursor_usage_scanner.py")).replace("file://", "")
  // White icon only — MultiEffect recolors it to bar.foreground so it tracks
  // the theme the same way glyph widgets do (baked #fff/#111 never will).
  readonly property url iconSource: Qt.resolvedUrl("assets/grok.svg")
  readonly property url grokBotIconSource: Qt.resolvedUrl("assets/grok-bot.svg")
  readonly property url cursorIconSource: Qt.resolvedUrl("assets/cursor.svg")

  // Shape contract for shell.summon/hide/toggle routing.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function resolvePath(value) {
    var text = String(value || "").trim()
    if (text === "") return ""
    if (text.startsWith("~/"))
      return (Quickshell.env("HOME") || "") + text.slice(1)
    if (text === "~")
      return Quickshell.env("HOME") || ""
    return text
  }

  function scannerCommand(probe) {
    var command = ["python3", root.scannerPath]
    if (probe)
      command.push("--probe")
    var authPath = root.resolvePath(root.setting("authPath", ""))
    if (authPath !== "")
      command.push("--auth", authPath)
    return command
  }

  function cursorScannerCommand(probe) {
    var command = ["python3", root.cursorScannerPath]
    if (probe)
      command.push("--probe")
    var authPath = root.resolvePath(root.setting("cursorAuthPath", ""))
    if (authPath !== "")
      command.push("--auth", authPath)
    var stateDb = root.resolvePath(root.setting("stateDbPath", ""))
    if (stateDb !== "")
      command.push("--state-db", stateDb)
    var grokAuth = root.resolvePath(root.setting("authPath", ""))
    if (grokAuth !== "")
      command.push("--grok-auth", grokAuth)
    if (!probe && root.showGrokBotUsage)
      command.push("--include-sand")
    return command
  }

  // ≥1 day → "5d"; under a day → "12h" (no minutes on the bar).
  function formatBarDuration(ms) {
    if (!(ms > 0)) return "now"
    var hours = Math.floor(ms / 3600000)
    var days = Math.floor(hours / 24)
    if (days > 0) return days + "d"
    return Math.max(1, hours) + "h"
  }

  function parseTimeMs(value) {
    var text = String(value || "").trim()
    if (text === "") return NaN
    var t = new Date(text).getTime()
    return isFinite(t) ? t : NaN
  }

  function applyScan(data) {
    if (!data || typeof data !== "object") {
      root.hasData = false
      return
    }
    var primary = Number(data.rateLimitPercent)
    if (!isFinite(primary)) primary = -1
    root.primaryPercent = primary
    root.resetAt = String(data.rateLimitResetAt || "")
    root.periodStart = String(data.rateLimitPeriodStart || "")
    root.tierLabel = String(data.tierLabel || "")
    root.grokLoginName = String(data.accountName || "")
    root.grokLoginEmail = String(data.accountEmail || "")
    root.subscriptionPeriodEnd = String(data.subscriptionPeriodEnd || "")
    root.subscriptionCancelsAtEnd = data.subscriptionCancelsAtEnd === true
    root.usageStatusText = String(data.usageStatusText || "")
    root.authHelpText = String(data.authHelpText || "")
    root.categories = Array.isArray(data.categories) ? data.categories : []
    root.hasData = primary >= 0
    root.nowMs = Date.now()
    root.injectPanel()
  }

  function clearUsage() {
    root.primaryPercent = -1
    root.resetAt = ""
    root.periodStart = ""
    root.tierLabel = ""
    root.grokLoginName = ""
    root.grokLoginEmail = ""
    root.subscriptionPeriodEnd = ""
    root.subscriptionCancelsAtEnd = false
    root.usageStatusText = ""
    root.authHelpText = ""
    root.categories = []
    root.hasData = false
  }

  function applyCursorScan(data) {
    if (!data || typeof data !== "object") {
      root.cursorHasData = false
      return
    }
    var autoPct = Number(data.rateLimitPercent)
    var apiPct = Number(data.secondaryRateLimitPercent)
    if (!isFinite(autoPct)) autoPct = -1
    if (!isFinite(apiPct)) apiPct = -1
    root.cursorAutoPercent = autoPct
    root.cursorApiPercent = apiPct
    root.cursorResetAt = String(data.rateLimitResetAt || data.secondaryRateLimitResetAt || "")
    root.cursorPeriodStart = String(data.rateLimitPeriodStart || "")
    root.cursorTierLabel = String(data.tierLabel || "")
    root.cursorLoginName = String(data.accountName || "")
    root.cursorLoginEmail = String(data.accountEmail || "")
    root.cursorUsageStatusText = String(data.usageStatusText || "")
    root.cursorAuthHelpText = String(data.authHelpText || "")
    root.cursorHasData = autoPct >= 0 || apiPct >= 0
    var botPct = Number(data.grokBotPercent)
    if (!isFinite(botPct)) botPct = -1
    root.grokBotPercent = botPct
    root.grokBotResetAt = String(data.grokBotResetAt || "")
    root.grokBotPeriodStart = String(data.grokBotPeriodStart || "")
    root.grokBotTierLabel = String(data.grokBotTierLabel || "")
    root.grokBotUsageStatusText = String(data.grokBotUsageStatusText || "")
    root.grokBotAuthHelpText = String(data.grokBotAuthHelpText || "")
    root.grokBotHasData = botPct >= 0
    root.nowMs = Date.now()
    root.injectPanel()
  }

  function clearCursorUsage() {
    root.cursorAutoPercent = -1
    root.cursorApiPercent = -1
    root.cursorResetAt = ""
    root.cursorPeriodStart = ""
    root.cursorTierLabel = ""
    root.cursorLoginName = ""
    root.cursorLoginEmail = ""
    root.cursorUsageStatusText = ""
    root.cursorAuthHelpText = ""
    root.cursorHasData = false
    root.clearGrokBotUsage()
  }

  function clearGrokBotUsage() {
    root.grokBotPercent = -1
    root.grokBotResetAt = ""
    root.grokBotPeriodStart = ""
    root.grokBotTierLabel = ""
    root.grokBotUsageStatusText = ""
    root.grokBotAuthHelpText = ""
    root.grokBotHasData = false
  }

  function probeGrok() {
    if (!presenceProbe.running) presenceProbe.running = true
  }

  function probeCursor() {
    if (!cursorPresenceProbe.running) cursorPresenceProbe.running = true
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setShowCursorUsage(on) {
    var next = on === true
    if (root.showCursorUsage === next) return
    root.persistSettings({ showCursorUsage: next })
    if (next) root.probeCursor()
    else if (!root.showGrokBotUsage) root.clearCursorUsage()
  }

  function setShowGrokBotUsage(on) {
    var next = on === true
    if (root.showGrokBotUsage === next) return
    root.persistSettings({ showGrokBotUsage: next })
    if (next) root.probeCursor()
    else {
      root.clearGrokBotUsage()
      if (!root.showCursorUsage) root.clearCursorUsage()
    }
  }

  function refresh() {
    // Availability first: no auth → hide and skip the API.
    if (root.grokAvailable) root.refreshing = true
    if (root.needsCursorSession && root.cursorAvailable) root.cursorRefreshing = true
    root.probeGrok()
    if (root.needsCursorSession) root.probeCursor()
  }

  function refreshUsage() {
    if (!root.grokAvailable) {
      root.clearUsage()
      return
    }
    if (usageScanner.running) return
    root.refreshing = true
    usageScanner.command = root.scannerCommand()
    usageScanner.running = true
  }

  function refreshCursorUsage() {
    if (!root.cursorAvailable) {
      root.clearCursorUsage()
      return
    }
    if (cursorUsageScanner.running) return
    root.cursorRefreshing = true
    cursorUsageScanner.command = root.cursorScannerCommand(false)
    cursorUsageScanner.running = true
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("grokLoginName" in target) target.grokLoginName = root.grokLoginName
    if ("grokLoginEmail" in target) target.grokLoginEmail = root.grokLoginEmail
    if ("cursorLoginName" in target) target.cursorLoginName = root.cursorLoginName
    if ("cursorLoginEmail" in target) target.cursorLoginEmail = root.cursorLoginEmail
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  // Missing auth or nothing to report → collapse the slot.
  visible: grokVisible || grokBotVisible || cursorVisible
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  IpcHandler {
    target: "rlimberger.grokbar-omarchy"
    function refresh(): string { root.refresh(); return "ok" }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

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

  Process {
    id: presenceProbe
    // Signed-in credentials (default or override path). Grok CLI does not
    // need to be running — usage is fetched from grok.com with the OAuth token.
    // authPath is argv, never interpolated into a shell program.
    command: root.scannerCommand(true)
    running: false

    stdout: StdioCollector {
      onStreamFinished: {
        var status = text.trim()
        var available = status === "ready"
        if (root.grokAvailable !== available)
          root.grokAvailable = available
        if (available) root.refreshUsage()
        else root.clearUsage()
      }
    }
  }

  Process {
    id: usageScanner
    command: root.scannerCommand()
    running: false

    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.applyScan(JSON.parse(text))
        } catch (e) {
          root.hasData = false
          console.warn("rlimberger.grokbar-omarchy: bad scanner JSON", e)
        }
      }
    }

    onExited: root.refreshing = false

    stderr: StdioCollector {
      onStreamFinished: if (text.trim() !== "") console.warn("rlimberger.grokbar-omarchy", text.trim())
    }
  }

  Process {
    id: cursorPresenceProbe
    // X-login Cursor session only. --probe never calls the usage API.
    command: root.cursorScannerCommand(true)
    running: false

    stdout: StdioCollector {
      onStreamFinished: {
        var status = text.trim()
        var available = status === "ready"
        if (root.cursorAvailable !== available)
          root.cursorAvailable = available
        if (available) root.refreshCursorUsage()
        else root.clearCursorUsage()
      }
    }
  }

  Process {
    id: cursorUsageScanner
    command: root.cursorScannerCommand(false)
    running: false

    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.applyCursorScan(JSON.parse(text))
        } catch (e) {
          root.cursorHasData = false
          console.warn("rlimberger.grokbar-omarchy: bad cursor scanner JSON", e)
        }
      }
    }

    onExited: root.cursorRefreshing = false

    stderr: StdioCollector {
      onStreamFinished: if (text.trim() !== "") console.warn("rlimberger.grokbar-omarchy cursor", text.trim())
    }
  }

  Timer {
    // Auth file can appear after `grok login` / Cursor X sign-in; keep
    // presence snappier than the usage API poll.
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.probeGrok()
      if (root.needsCursorSession) root.probeCursor()
    }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: root.grokAvailable || (root.needsCursorSession && root.cursorAvailable)
    repeat: true
    onTriggered: {
      root.refreshUsage()
      if (root.needsCursorSession) root.refreshCursorUsage()
    }
  }

  Timer {
    interval: 30000
    running: root.visible || root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: root.grokVisible || root.grokBotVisible || root.cursorVisible
    active: root.alarming
    // Tooltip suppressed because the panel is the detail view.
    tooltipText: ""
    fixedWidth: {
      if (vertical) return Style.bar.iconSlot
      return Math.ceil(contentRow.implicitWidth + Style.spaceReal(8.75) * 2)
    }
    fixedHeight: vertical ? Style.bar.iconSlot : -1
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refresh()
      else root.togglePanel()
    }

    Row {
      id: contentRow
      visible: !button.vertical
      anchors.centerIn: parent
      spacing: Style.space(8)

      Row {
        id: grokCluster
        visible: root.grokVisible
        spacing: Style.space(5)

        ThemedGrokIcon {
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          visible: root.primaryText !== ""
          anchors.verticalCenter: parent.verticalCenter
          text: root.primaryText
          color: root.overPace || root.displayPercent >= 0.9
            ? button.activeColor
            : button.foreground
          font.family: button.fontFamily
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
        }

        Text {
          visible: root.resetText !== ""
          anchors.verticalCenter: parent.verticalCenter
          text: root.resetText
          color: root.dim
          font.family: button.fontFamily
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
        }
      }

      Row {
        id: grokBotCluster
        visible: root.grokBotVisible
        spacing: Style.space(5)

        ThemedGrokBotIcon {
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          visible: root.grokBotText !== ""
          anchors.verticalCenter: parent.verticalCenter
          text: root.grokBotText
          color: root.grokBotOverPace || root.grokBotDisplay >= 0.9
            ? button.activeColor
            : button.foreground
          font.family: button.fontFamily
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
        }

        Text {
          visible: root.grokBotResetText !== ""
          anchors.verticalCenter: parent.verticalCenter
          text: root.grokBotResetText
          color: root.dim
          font.family: button.fontFamily
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
        }
      }

      Row {
        id: cursorCluster
        visible: root.cursorVisible
        spacing: Style.space(5)

        ThemedCursorIcon {
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          visible: root.cursorAutoText !== ""
          anchors.verticalCenter: parent.verticalCenter
          text: root.cursorAutoText
          color: root.cursorAutoOverPace || root.cursorAutoDisplay >= 0.9
            ? button.activeColor
            : button.foreground
          font.family: button.fontFamily
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
        }

        Text {
          visible: root.cursorApiText !== ""
          anchors.verticalCenter: parent.verticalCenter
          text: root.cursorApiText
          color: root.cursorApiOverPace || root.cursorApiDisplay >= 0.9
            ? button.activeColor
            : button.foreground
          font.family: button.fontFamily
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
        }

        Text {
          visible: root.cursorResetText !== ""
          anchors.verticalCenter: parent.verticalCenter
          text: root.cursorResetText
          color: root.dim
          font.family: button.fontFamily
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
        }
      }
    }

    ThemedGrokIcon {
      visible: button.vertical && root.verticalIcon === "grok"
      anchors.centerIn: parent
    }

    ThemedGrokBotIcon {
      visible: button.vertical && root.verticalIcon === "bot"
      anchors.centerIn: parent
    }

    ThemedCursorIcon {
      visible: button.vertical && root.verticalIcon === "cursor"
      anchors.centerIn: parent
    }
  }

  // Same optical model as BarIconButton: iconCanvas slot, iconFont size.
  component ThemedGrokIcon: Item {
    width: Style.bar.iconCanvas
    height: Style.bar.iconCanvas
    implicitWidth: width
    implicitHeight: height

    readonly property int iconSize: Style.bar.iconFont

    Image {
      id: icon
      anchors.centerIn: parent
      width: parent.iconSize
      height: parent.iconSize
      source: root.iconSource
      sourceSize.width: parent.iconSize * 2
      sourceSize.height: parent.iconSize * 2
      fillMode: Image.PreserveAspectFit
      visible: false
      layer.enabled: true
    }

    MultiEffect {
      anchors.fill: icon
      source: icon
      colorization: 1.0
      colorizationColor: root.foreground
    }
  }

  component ThemedGrokBotIcon: Item {
    width: Style.bar.iconCanvas
    height: Style.bar.iconCanvas
    implicitWidth: width
    implicitHeight: height

    readonly property int iconSize: Style.bar.iconFont

    Image {
      id: grokBotIcon
      anchors.centerIn: parent
      width: parent.iconSize
      height: parent.iconSize
      source: root.grokBotIconSource
      sourceSize.width: parent.iconSize * 2
      sourceSize.height: parent.iconSize * 2
      fillMode: Image.PreserveAspectFit
      visible: false
      layer.enabled: true
    }

    MultiEffect {
      anchors.fill: grokBotIcon
      source: grokBotIcon
      colorization: 1.0
      colorizationColor: root.foreground
    }
  }

  component ThemedCursorIcon: Item {
    width: Style.bar.iconCanvas
    height: Style.bar.iconCanvas
    implicitWidth: width
    implicitHeight: height

    readonly property int iconSize: Style.bar.iconFont

    Image {
      id: cursorIcon
      anchors.centerIn: parent
      width: parent.iconSize
      height: parent.iconSize
      source: root.cursorIconSource
      sourceSize.width: parent.iconSize * 2
      sourceSize.height: parent.iconSize * 2
      fillMode: Image.PreserveAspectFit
      visible: false
      layer.enabled: true
    }

    MultiEffect {
      anchors.fill: cursorIcon
      source: cursorIcon
      colorization: 1.0
      colorizationColor: root.foreground
    }
  }
}
