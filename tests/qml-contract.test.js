const { describe, it } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

function read(name) {
  return fs.readFileSync(path.join(__dirname, "..", name), "utf8")
}

describe("QML scheduler contract", () => {
  const service = read("Service.qml")
  const panel = read("Panel.qml")

  it("uses one Omarchy service instead of constructing a service per monitor", () => {
    assert.match(panel, /root\.bar\.shell\.serviceFor\(root\.moduleName\)/)
    assert.match(panel, /onVpnChanged: \{[\s\S]{0,200}if \(vpn\) vpn\.setSettings\(root\.settings\)/)
    assert.doesNotMatch(panel, /Service\s*\{\s*id:\s*vpn/)
    assert.match(service, /running: root\.active && root\.installed/)
  })

  it("polls protonvpn status on a timer only while a panel is open", () => {
    assert.match(service, /id: refreshTimer[\s\S]{0,120}running: root\.active && \(root\.openPanels > 0 \|\| !root\.linkAvailable\)\n/)
    assert.doesNotMatch(service, /id: refreshTimer[\s\S]{0,200}triggeredOnStart/)
    assert.match(service, /Component\.onCompleted: \{[\s\S]{0,320}if \(active\) refresh\(\)\n  \}/)
    assert.match(service, /openPanels = Math\.max\(0, openPanels - 1\)/)
    assert.match(panel, /onOpenedChanged: \{\n\s*trackOpen\(opened\)/)
    assert.match(panel, /Component\.onDestruction: trackOpen\(false\)/)
  })

  it("samples traffic and notifies only through fixed, bounded commands", () => {
    assert.match(service, /id: trafficTimer\n\s*interval: root\.openPanels > 0 \? 2000 : 5000\n\s*repeat: true\n\s*running: root\.active && root\.linkActive/)
    assert.match(service, /if \(openPanels > 0\) traffic = Model\.trafficSample\(traffic, counters, now\)/)
    assert.match(panel, /visible: root\.view\.stalled === true[\s\S]{0,80}text: Model\.stalledText\(root\.loc\)/)
    assert.match(service, /readonly property string _statsDir: Model\.isTunnelDevice\(linkDevice\) \? "\/sys\/class\/net\/" \+ linkDevice \+ "\/statistics\/" : ""/)
    assert.doesNotMatch(service, /\/usr\/bin\/cat/)
    assert.match(service, /var command = Model\.notificationCommand\(note\)\n\s*if \(command\.length > 0\) Quickshell\.execDetached\(command\)/)
    assert.doesNotMatch(service, /notify-send/)
  })

  it("launches install and sign-in only through fixed Omarchy terminals", () => {
    assert.match(service, /Quickshell\.execDetached\(Model\.INSTALL_LAUNCHER\)/)
    assert.match(service, /Quickshell\.execDetached\(Model\.SIGNIN_LAUNCHER\)/)
    assert.doesNotMatch(service, /omarchy-launch-terminal"/)
    assert.match(service, /id: setupTimer[\s\S]{0,80}interval: 5000/)
    assert.match(panel, /if \(view\.state === Model\.STATES\.cliMissing\) rows\.push\(\["install"\]\)/)
    assert.match(panel, /focusSection === "signin"\) vpn\.signIn\(\)/)
  })

  it("locks only Proton CLI runs", () => {
    assert.match(service, /if \(command && command\[0\] === "protonvpn"\) runner\.push\("--lock"\)/)
  })

  it("shows the Kill Switch block and colors the icon for it", () => {
    assert.match(service, /blocking: root\.killSwitchBlocking/)
    assert.match(service, /linkKillSwitch = link\.killSwitch === true/)
    assert.match(panel, /visible: root\.view\.blocking === true[\s\S]{0,80}text: Model\.killSwitchBlockingText\(root\.loc\)/)
    assert.doesNotMatch(panel, /Model\.icon(?:Urgent|Warning)\((?:root\.)?view\.state\)/)
  })

  it("reconnects only after an unowned drop and stops when the user acts", () => {
    assert.match(service, /var dropped = previous === true && !now && selfInitiated !== true && ksStep === "idle"/)
    assert.match(service, /else if \(dropped && reconnectOnDrop\) armReconnect\(\)/)
    assert.match(service, /if \(job\.auto !== true\) cancelReconnect\(\)/)
    assert.match(service, /if \(job\.auto === true\) scheduleNextReconnect\(\)/)
    assert.match(service, /onReconnectOnDropChanged: if \(!reconnectOnDrop\) cancelReconnect\(\)/)
  })

  it("never starts an automatic connect after the reconnect is cancelled", () => {
    assert.match(service, /_reconnectFallback = false\n\s*dropQueuedReconnect\(\)\n\s*\}/)
    assert.match(service, /Scheduler\.removeQueued\(_queueState, function\(job\) \{ return job\.auto === true \}\)/)
    const pump = service.indexOf("function pump()")
    const recheck = service.indexOf("if (_reconnectTarget === null || !reconnectOnDrop) dropQueuedReconnect()", pump)
    const begin = service.indexOf("Scheduler.beginJob(_queueState)", pump)
    assert.ok(pump !== -1 && recheck !== -1 && recheck < begin)
  })

  it("treats a disconnect request during reconnect backoff as cancellation", () => {
    const disconnect = service.indexOf("function disconnect()")
    const cancel = service.indexOf("cancelReconnect()", disconnect)
    const notConnected = service.indexOf('reportError(tr("action.notConnected", "Proton VPN is not connected."))', disconnect)
    assert.ok(disconnect !== -1 && cancel !== -1 && cancel < notConnected)
    assert.match(service, /if \(stoppedReconnect\) return noteReconnectStopped\(\)\n\s*reportError\(tr\("action\.notConnected", "Proton VPN is not connected\."\)\)/)
    assert.match(service, /if \(disconnectAfter\) Qt\.callLater\(disconnect\)/)
  })

  it("forgets account settings and the inferred plan on sign-out", () => {
    assert.match(service, /if \(state === Model\.STATES\.signedOut\) forgetAccountSettings\(\)/)
    assert.match(service, /function forgetAccountSettings\(\) \{\n\s*configValues = \(\{\}\)\n\s*configUpgrade = \(\{\}\)\n\s*configLoaded = false/)
    assert.match(service, /reportError\(blocked\)\n(?:\s*\/\/[^\n]*\n)*\s*refreshConfig\(\)/)
  })

  it("gates paid-only modes on the free plan before running the CLI", () => {
    const connect = service.indexOf("function connectWith(options)")
    const blocked = service.indexOf("Model.planBlockedReason(", connect)
    const run = service.indexOf("return runAction(plan.command", connect)
    assert.ok(connect !== -1 && blocked !== -1 && run !== -1 && blocked < run)
    assert.match(service, /_ksTarget = Model\.returnTarget\(activeTarget, status, freePlan\)/)
    assert.match(panel, /readonly property var modeOptions: Model\.modeOptions\(vpn\.freePlan, root\.loc\)/)
  })

  it("asks before a Kill Switch change drops a live tunnel", () => {
    assert.match(panel, /onChanged: function\(value\) \{ root\.chooseKillSwitch\(value\) \}/)
    assert.match(panel, /ksConfirmValue = value\n\s*cursorActive = true\n\s*focusSection = "ks-cancel"/)
    assert.match(service, /ksStep === "idle" \|\| _ksInternal/)
  })

  it("keeps the Kill Switch cycle's unprotected gap short and owned", () => {
    const reconnect = service.indexOf('if (ksStep === "setting" && job.setting === "kill-switch") advanceKillSwitch(')
    const listAfter = service.indexOf("refreshConfig()", reconnect)
    assert.ok(reconnect !== -1 && listAfter !== -1 && listAfter - reconnect < 200)
    assert.match(service, /var owned = actionRunning \|\| ksStep !== "idle"\n\s*noteLink\(link\.active, owned\)/)
    assert.match(service, /if \(owned\) return\n\s*if \(!Model\.linkMayClaimConnected\(state\)\)/)
    assert.match(service, /disconnected && linkConfirmed\(\) && ksStep === "idle"/)
    assert.match(service, /readonly property bool actionBusy: actionRunning \|\| ksStep !== "idle"/)
    assert.match(service, /if \(event === "connectFailed"\) reportError\(/)
  })

  it("falls back to an idle-until-needed local service when the shared one is missing", () => {
    assert.match(panel, /readonly property var vpn: root\.sharedVpn \|\| localVpn/)
    assert.match(panel, /Service \{\s*id: localVpn\s*active: !root\.sharedVpn\b/)
    assert.match(service, /property bool active: true/)
    assert.match(service, /function watchLink\(\) \{\n\s*if \(!active \|\| !installed\) return/)
  })

  it("keeps CLI verdicts the live tunnel cannot explain", () => {
    const actionGuard = service.indexOf("if (owned) return", service.indexOf("linkDevice = link.device"))
    const claimGuard = service.indexOf("if (!Model.linkMayClaimConnected(state))", actionGuard)
    const updateView = service.indexOf("if (link.active) {", actionGuard)
    assert.ok(actionGuard !== -1 && claimGuard !== -1 && updateView !== -1)
    assert.ok(actionGuard < claimGuard && claimGuard < updateView)
    assert.match(service, /next\.state === Model\.STATES\.disconnected && linkConfirmed\(\)/)
    assert.doesNotMatch(service, /disconnected && linkActive\b/)
  })

  it("discards nmcli polls that straddle an action result", () => {
    assert.match(service, /function handleAction\(result, job\) \{\n[^\n]*\n    _linkEpoch\+\+/)
    assert.match(service, /_linkStartedEpoch = _linkEpoch/)
    assert.match(service, /if \(_linkStartedEpoch !== _linkEpoch\) \{/)
  })

  it("resumes the queue when a watchdog-killed process finally exits", () => {
    assert.match(service, /runId: root\._commandRunId\n\s*\}\)\n[\s\S]{0,300}if \(!root\._currentJob\) Qt\.callLater\(root\.pump\)/)
    assert.match(service, /property var recentTargets: \[\]/)
    assert.match(service, /id: commandProcess/)
    assert.doesNotMatch(service, /id: statusProcess/)
    assert.doesNotMatch(service, /id: actionProcess/)
  })

  it("widens the bar slot to fit the label", () => {
    assert.match(panel, /labelText: root\.barLabel\n\s*slotSize: Style\.bar\.iconSlot \+ \(root\.barLabel !== "" \? Math\.ceil\(barLabelMetrics\.advanceWidth\) \+ Style\.space\(8\) : 0\)/)
  })

  it("drops a waiting automatic connect whose trigger no longer holds", () => {
    assert.match(service, /onWifiTrustedChanged: if \(wifiTrusted\) cancelAutoConnect\("wifi"\)/)
    assert.match(service, /onAutoConnectWifiChanged: if \(!autoConnectWifi\) cancelAutoConnect\("wifi"\)/)
    assert.match(service, /onConnectOnLoginChanged: if \(!connectOnLogin\) cancelAutoConnect\("login"\)/)
    assert.match(service, /onWifiNameChanged: \{\n\s*cancelAutoConnect\("wifi"\)/)
    assert.match(service, /if \(automaticRunning\) _disconnectAfterReconnect = true/)
  })

  it("keeps the first activation time for the same tunnel", () => {
    assert.match(service, /var sameTunnel = previousActive && link\.active && previousServer === link\.server && linkSinceMs > 0/)
    assert.match(service, /Math\.min\(linkSinceMs, link\.sinceMs\)/)
  })

  it("follows NetworkManager events and keeps a slow safety poll", () => {
    assert.match(service, /id: linkMonitor\n\s*running: false\n\s*command: \["\/usr\/bin\/nmcli", "monitor"\]/)
    assert.match(service, /onRead: function\(line\) \{ linkSettle\.restart\(\) \}/)
    assert.match(service, /interval: root\.linkEvents \? 60000 : root\.linkWatchIntervalSec \* 1000/)
    assert.match(service, /monitorRestart\.interval = Model\.monitorRestartDelayMs\(_monitorFailures\)/)
    assert.match(service, /if \(linkProcess\.running\) \{\n\s*_linkRecheck = true/)
  })

  it("bounds every collected command and keeps NetworkManager read-only", () => {
    assert.match(service, /scripts\/run_bounded\.py/)
    assert.match(service, /\/usr\/bin\/python3/)
    assert.match(service, /--max-bytes", "262144"/)
    assert.match(service, /\/usr\/bin\/nmcli/)
    assert.match(service, /connection", "show", "--active"/)
    assert.doesNotMatch(service, /nmcli[\s\S]{0,100}(connection", "down"|connection", "up")/)
  })

  it("words text through the plugin's own catalog", () => {
    for (const file of [service, panel]) {
      assert.match(file, /Translations \{ directory: Qt\.resolvedUrl\("i18n"\) \}/)
      assert.match(file, /num: function\(value, places\) \{ return I18n\.formatNumber\(value, places\) \}/)
    }
  })

  it("keeps the declared trust boundary in the runtime service", () => {
    assert.doesNotMatch(service, /\b(?:curl|wget)\b|settings\.json|keyring|pkill|sudo|pkexec/)
    // FileView reads only the tunnel's two byte counters, and checks that the
    // runner's lock file exists.
    const views = [...service.matchAll(/FileView \{[\s\S]*?\n  \}/g)].map((m) => m[0])
    assert.equal(views.length, 3)
    assert.match(views[0], /path: root\._runtimeDir !== "" \? root\._runtimeDir \+ "\/omarchy-protonvpn\.lock" : ""/)
    assert.doesNotMatch(views[0], /watchChanges|setText|atomicWrites/)
    for (const view of views.slice(1)) {
      assert.match(view, /path: root\._statsDir !== "" \? root\._statsDir \+ "(?:rx|tx)_bytes" : ""/)
      assert.doesNotMatch(view, /watchChanges|setText|atomicWrites/)
    }
    assert.doesNotMatch(service, /"connection", "(?:up|down|delete|modify)"/)
  })

  it("does not let an old NetworkManager signal replace an action in flight", () => {
    const updateFacts = service.indexOf("linkDevice = link.device")
    const actionGuard = service.indexOf("if (owned) return", updateFacts)
    const updateView = service.indexOf("if (link.active)", updateFacts)
    assert.ok(updateFacts !== -1 && actionGuard !== -1 && updateView !== -1)
    assert.ok(updateFacts < actionGuard && actionGuard < updateView)
  })

  it("shows compatibility warnings, CLI exit IP, and session recents", () => {
    assert.match(panel, /status\.exitIp/)
    assert.match(panel, /vpn\.compatibilityWarning/)
    assert.match(panel, /readonly property var quickRows: Model\.quickConnectRows\(vpn\.favorites, vpn\.recentTargets, currentTarget\)/)
    assert.match(panel, /model: root\.quickRows/)
    assert.match(panel, /if \(row && !row\.active\) vpn\.connectWith\(row\.target\)/)
    assert.match(service, /readonly property var favorites: Model\.normalizeTargets\(setting\("favorites", \[\]\), Model\.MAX_FAVORITES\)/)
    // Recents reach shell.json only when the user opts in, and leave it when they opt out.
    assert.match(service, /if \(recentTargets\.length === 0\) recentTargets = Model\.normalizeTargets\(setting\("recent", \[\]\), Model\.MAX_RECENTS\)\n\s*else saveSettings/)
    assert.match(service, /if \(rememberRecent\) saveSettings\(\{ recent: Model\.normalizeTargets\(recentTargets, Model\.MAX_RECENTS\) \}\)\n/)
    assert.match(service, /\} else if \(setting\("recent", undefined\) !== undefined\) \{\n\s*saveSettings\(\{ recent: undefined \}\)/)
    assert.match(service, /for \(var key in settings\) if \(key !== "id"\) entry\[key\] = settings\[key\]/)
    assert.match(service, /shell\.updateEntryInline\(Model\.PLUGIN_ID, entry\)/)
    assert.match(panel, /function onActiveTargetChanged\(\) \{ root\.connectDraftDirty = false \}/)
  })

  it("accepts an action before changing visual connecting state", () => {
    const enqueue = service.indexOf("if (!enqueue(job)) return false")
    const visual = service.indexOf("if (action === \"connect\") state = Model.STATES.connecting")
    assert.ok(enqueue !== -1, "runAction must enqueue before returning")
    assert.ok(visual !== -1, "runAction must set connecting/disconnecting")
    assert.ok(enqueue < visual, "visual connecting state must be set only after enqueue accepts")
  })

  it("does not treat visual connecting as process busy for enqueue", () => {
    assert.match(service, /readonly property bool actionBusy: actionRunning/)
    assert.match(service, /import "Scheduler\.js" as Scheduler/)
    assert.doesNotMatch(service, /actionBusy:\s*busy/)
  })

  it("keeps IPC connect and disconnect semantic", () => {
    assert.match(panel, /function connectVpn\(\): string \{ root\.connectNow\(\); return "ok" \}/)
    assert.match(panel, /function disconnectVpn\(\): string \{ root\.disconnectNow\(\); return "ok" \}/)
    assert.doesNotMatch(panel, /function connectVpn\(\): string \{ root\.tryToggle\(\)/)
    assert.match(panel, /function connectTo\(target: string\): string \{\n\s*var parsed = Model\.parseTargetSpec\(target\)/)
    assert.match(panel, /function statusJson\(\): string \{ return Model\.statusJson\(/)
  })

  it("includes stale in degraded UX and gates writes", () => {
    assert.match(panel, /view\.state === Model\.STATES\.stale/)
    assert.match(panel, /readonly property bool showWrites: showHealthy && vpn\.canChangeSettings/)
    assert.match(panel, /emptyText: root\.countryEmptyText\(\)/)
    assert.match(panel, /onClicked: root\.toggleCustomDns\(\)/)
  })

  it("shows Proton setting help as hover and keyboard-focus tooltips", () => {
    assert.match(panel, /component SettingTip: PanelToolTip/)
    assert.match(panel, /property bool keyboardNavigation: false/)
    assert.match(panel, /tipCursor: root\.keyboardNavigation && modeDropdown\.hasCursor/)
    assert.match(panel, /Model\.modeTooltip\(root\.selectedMode, root\.loc\)/)
    assert.match(panel, /Model\.connectFieldTooltip\("country", root\.loc\)/)
    assert.match(panel, /Model\.connectFieldTooltip\("city", root\.loc\)/)
    assert.match(panel, /Model\.connectFieldTooltip\("server", root\.loc\)/)
    assert.match(panel, /Model\.settingTooltip\("netshield", root\.loc\)/)
    assert.match(panel, /Model\.settingTooltip\("kill-switch", root\.loc\)/)
    assert.match(panel, /Model\.settingTooltip\("custom-dns", root\.loc\)/)
    assert.match(panel, /Model\.settingTooltip\(toggleSettingRow\.key, root\.loc\)/)
    assert.doesNotMatch(panel, /Model\.modeSummary\(/)
    assert.doesNotMatch(panel, /Model\.settingSummary\(/)
    assert.doesNotMatch(panel, /Model\.connectFieldSummary\(/)
    assert.doesNotMatch(panel, /Model\.CONNECT_SECTION_HELP/)
    assert.doesNotMatch(panel, /Model\.modeHelp\(/)
    assert.doesNotMatch(panel, /Model\.settingCaption\(/)
    assert.doesNotMatch(panel, /Model\.connectFieldHelp\(/)
    const connectGrid = panel.match(/id: connectRow[\s\S]*?id: modeDropdown/)
    assert.ok(connectGrid, "CONNECT grid must contain the mode dropdown")
    assert.doesNotMatch(connectGrid[0], /SettingHelp/)
    const settingsChoice = panel.match(/FieldLabel \{ text: Model\.settingLabel\("netshield", root\.loc\) \}[\s\S]*?id: netshieldDropdown/)
    assert.ok(settingsChoice, "SETTINGS grid must place NetShield label before its dropdown")
    assert.doesNotMatch(settingsChoice[0], /SettingHelp/)
    assert.match(panel, /FieldLabel \{ text: Model\.settingLabel\("kill-switch", root\.loc\) \}/)
    assert.equal(require("../Model.js").settingLabel("kill-switch"), "Kill Switch")
  })

  it("uses the same title type for choice labels as Toggle titles", () => {
    const fieldLabel = panel.match(/component FieldLabel: Text \{[\s\S]*?\n  \}/)
    assert.ok(fieldLabel, "FieldLabel component must exist")
    assert.match(fieldLabel[0], /color: root\.foreground/)
    assert.match(fieldLabel[0], /font\.pixelSize: Style\.font\.subtitle/)
    assert.match(fieldLabel[0], /font\.bold: true/)
    assert.doesNotMatch(fieldLabel[0], /Style\.font\.caption/)
    assert.doesNotMatch(fieldLabel[0], /color: root\.dim/)
  })

  it("offers an in-place switch for changed CONNECT choices while connected", () => {
    assert.match(panel, /readonly property bool offerSwitch: Model\.shouldOfferSwitch\(/)
    assert.match(panel, /id: switchButton\s*visible: root\.offerSwitch/)
    assert.match(panel, /text: Model\.switchLabel\(root\.connectOptions\(\), root\.loc\)/)
    assert.match(panel, /onClicked: root\.switchNow\(\)/)
    assert.match(panel, /if \(offerSwitch\) rows\.push\(\["switch"\]\)/)
    assert.match(panel, /focusSection === "switch"\) switchNow\(\)/)
    assert.match(panel, /onAccepted: root\.offerSwitch \? root\.switchNow\(\) : root\.tryToggle\(\)/)
    assert.doesNotMatch(panel, /function applyConnectDraft\(draft\) \{[^}]*connectDraftDirty/)
    assert.match(service, /activeTarget = target/)
    assert.match(service, /if \(state === Model\.STATES\.disconnected\) \{[\s\S]{0,300}activeTarget = null/)
  })

  it("centers the protocol pill with the power toggle and keeps status on one line", () => {
    assert.match(panel, /detail: ""/)
    assert.match(panel, /id: detailPill\s*visible: root\.heroDetailText !== ""\s*anchors\.verticalCenter: parent\.verticalCenter/)
    // A parent bound to a child's `visible` can hide itself permanently.
    assert.match(panel, /visible: root\.heroDetailText !== "" \|\| root\.powerSwitchShown/)
    assert.match(panel, /id: powerSwitch\s*anchors\.verticalCenter: parent\.verticalCenter\s*visible: root\.powerSwitchShown/)
    assert.doesNotMatch(panel, /visible:[^\n]*\b(?:detailPill|powerSwitch)\.visible/)
    assert.match(panel, /id: powerSwitch\s*anchors\.verticalCenter: parent\.verticalCenter/)
    assert.match(panel, /Flow \{\s*id: statusGrid/)
  })

  it("gets city lists to the user ahead of background refreshes", () => {
    assert.match(service, /"cities", "list", code\], timeout: 30000, priority: true/)
    assert.match(service, /timeout: 60000,\s*priority: true,\s*snapshot: snapshot\(\)/)
    assert.match(service, /kind: "set"[^\n]*priority: true/)
    assert.doesNotMatch(service, /"status"\][^\n]*priority: true/)
    assert.match(service, /force !== true && _citiesCache\[code\]/)
    assert.match(panel, /panelFlick\.contentY = 0\s*refreshOnOpen\(\)/)
    assert.match(panel, /loading: vpn\.citiesLoading && vpn\.citiesCountry === root\.selectedCountry/)
  })

  it("scrolls the Custom DNS row itself into view with bottom breathing room", () => {
    assert.match(panel, /focusSection === "config:custom-dns"\) scrollItemIntoView\(customDnsToggle\)/)
    assert.doesNotMatch(panel, /focusSection === "config:custom-dns"\) scrollItemIntoView\(dnsField\.visible \? dnsField : configColumn\)/)
    assert.match(panel, /id: customDnsToggle/)
    assert.match(panel, /height: Style\.space\(6\)/)
  })

  it("uses a compact card with stacked CONNECT fields and split SETTINGS grids", () => {
    assert.match(panel, /contentWidth: panel\.fittedContentWidth\(Style\.space\(520\)\)/)
    assert.doesNotMatch(panel, /fittedContentWidth\(Style\.space\(560\)\)/)
    assert.doesNotMatch(panel, /Style\.space\(420\)/)
    assert.doesNotMatch(panel, /Style\.space\(760\)/)
    assert.match(panel, /id: statusGrid/)
    assert.match(panel, /id: connectRow/)
    assert.match(panel, /id: choiceGrid/)
    assert.match(panel, /id: toggleGrid/)
    assert.doesNotMatch(panel, /id: configGrid/)
    assert.match(panel, /component FieldColumn: ColumnLayout/)
    assert.match(panel, /columns: 2/)
    assert.match(panel, /id: refreshRow/)
    assert.match(panel, /Button \{/)
    assert.doesNotMatch(panel, /Layout\.fillHeight: true/)
    assert.match(panel, /implicitHeight: Style\.spacing\.controlHeight/)
    assert.match(panel, /titleSize: Style\.font\.body/)
    assert.doesNotMatch(panel, /implicitHeight: Style\.space\(40\)/)
  })

  it("connects at login once, and never against the user", () => {
    const completed = service.indexOf("loginMarker.reload()")
    const refresh = service.indexOf("if (active) refresh()", completed)
    assert.ok(completed !== -1 && refresh > completed, "the marker is read before the first CLI run creates it")
    assert.match(service, /_shellReloaded = _runtimeDir === "" \|\| loginMarker\.loaded\n\s*_loginConnectPending = !_shellReloaded/)
    assert.match(service, /readonly property bool autoConnectArmed: \(connectOnLogin && _loginConnectPending\) \|\| \(autoConnectWifi && _wifiConnectPending\)/)
    assert.match(service, /running: root\.active && root\.autoConnectArmed/)
    assert.match(service, /if \(job\.autoConnect === ""\) cancelAutoConnect\(""\)/)
    // Disconnect wins even when there is nothing to disconnect yet.
    const disconnect = service.indexOf("function disconnect()")
    const cancel = service.indexOf('cancelAutoConnect("")', disconnect)
    const gate = service.indexOf("if (!canToggle) {", disconnect)
    assert.ok(disconnect !== -1 && cancel !== -1 && cancel < gate)
    assert.match(service, /_autoTicks > 18 \|\| _autoAttempts >= 3/)
  })

  it("connects on untrusted Wi-Fi only when a network is really joined", () => {
    assert.match(service, /import Quickshell\.Networking/)
    assert.match(service, /if \(!_started \|\| wifiName === "" \|\| !autoConnectWifi \|\| wifiTrusted\) return\n\s*if \(_shellReloaded && Date\.now\(\) - _startedMs < 10000\) return/)
    assert.match(service, /readonly property var trustedNetworks: Model\.normalizeNetworks\(setting\("trustedNetworks", \[\]\)\)/)
    assert.match(panel, /focusSection === "trust"\) vpn\.toggleTrustedNetwork\(vpn\.wifiName\)/)
  })

  it("signs out only from Disconnected, after asking", () => {
    assert.match(service, /if \(state !== Model\.STATES\.disconnected\) \{\n\s*reportError\(tr\("signout\.disconnectFirst"/)
    assert.match(service, /runAction\(\["protonvpn", "signout"\], "signout"/)
    assert.match(service, /if \(job\.action === "signout"\) \{\n\s*applyView\(Model\.signedOutView\(loc\)\)/)
    assert.match(panel, /focusSection === "signout"\) askSignOut\(\)/)
    assert.match(panel, /signOutConfirm = true\n\s*cursorActive = true\n\s*focusSection = "so-cancel"/)
  })

  it("folds SETTINGS away until asked for", () => {
    assert.match(panel, /property bool settingsOpen: false/)
    assert.match(panel, /rows\.push\(\["settings"\]\)\n\s*if \(settingsOpen && vpn\.configLoaded\) \{/)
    assert.match(panel, /id: settingsBody\n\s*visible: root\.settingsOpen/)
    assert.match(panel, /focusSection === "settings"\) toggleSettings\(\)/)
    assert.match(panel, /\(t === "s" \|\| t === "S"\) && root\.showWrites && vpn\.installed\) root\.toggleSettings\(\)/)
  })

  it("moves the cursor by row and column instead of a flat list", () => {
    assert.match(panel, /function visibleFocusRows\(\)/)
    assert.match(panel, /rows\.push\(\["config:netshield", "config:kill-switch"\]\)/)
    assert.match(panel, /if \(dx === 0 && dy === 0\) return/)
    assert.doesNotMatch(panel, /if \(dy === 0\) return/)
    assert.match(panel, /var nextCol = Math\.max\(0, Math\.min\(rows\[row\]\.length - 1, col \+ dx\)\)/)
  })

  it("cascade-resets CONNECT fields without touching SETTINGS", () => {
    assert.match(panel, /Model\.connectDraftForModeChange/)
    assert.match(panel, /Model\.connectDraftForCountryChange/)
    assert.match(panel, /Model\.connectFieldTriggerLabel\("country"/)
    assert.match(panel, /Model\.connectFieldTriggerLabel\("city"/)
    assert.match(panel, /cityDropdown\.value = selectedCity/)
    assert.match(panel, /countryDropdown\.value = selectedCountry/)
    assert.match(panel, /enabled: root\.selectedCountry !== ""/)
    assert.match(panel, /focusSection === "city" && selectedCountry !== ""/)
    assert.match(panel, /vpn\.clearCities\(\)/)
    assert.match(service, /function clearCities\(\)/)
    const modeHandler = panel.match(/onSelectedModeChanged: \{[\s\S]*?\n  \}/)
    assert.ok(modeHandler, "mode-change handler must exist")
    assert.doesNotMatch(modeHandler[0], /setConfig|dnsText|dnsEditorOpen|configDisplayValue/)
  })

  it("does not reveal the DNS field merely by hovering Custom DNS", () => {
    assert.match(panel, /property bool dnsEditorOpen: false/)
    assert.match(panel, /function showDnsField\(\)/)
    assert.match(panel, /height: root\.showDnsField\(\) \? dnsField\.implicitHeight \+ Style\.space\(6\) : 0/)
    assert.match(panel, /visible: root\.showDnsField\(\)/)
    assert.doesNotMatch(panel, /dnsEnabled\(\) \|\| root\.focusSection === "dns"/)
  })
})
