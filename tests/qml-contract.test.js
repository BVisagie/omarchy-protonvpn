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
    assert.match(service, /Component\.onCompleted: if \(active\) refresh\(\)/)
    assert.match(service, /openPanels = Math\.max\(0, openPanels - 1\)/)
    assert.match(panel, /onOpenedChanged: \{\n\s*trackOpen\(opened\)/)
    assert.match(panel, /Component\.onDestruction: trackOpen\(false\)/)
  })

  it("samples traffic and notifies only through fixed, bounded commands", () => {
    assert.match(service, /id: trafficTimer[\s\S]{0,120}running: root\.active && root\.openPanels > 0 && root\.linkActive/)
    assert.match(service, /if \(!Model\.isTunnelDevice\(linkDevice\)\) return/)
    assert.match(service, /boundedCommand\(\["\/usr\/bin\/cat", base \+ "rx_bytes", base \+ "tx_bytes"\], 2000\)/)
    assert.match(service, /execDetached\(\["notify-send", "--app-name=Proton VPN", "--urgency=" \+ note\.urgency, "--icon=network-vpn-symbolic", "--", note\.summary, note\.body\]\)/)
  })

  it("asks before a Kill Switch change drops a live tunnel", () => {
    assert.match(panel, /onChanged: function\(value\) \{ root\.chooseKillSwitch\(value\) \}/)
    assert.match(panel, /ksConfirmValue = value\n\s*cursorActive = true\n\s*focusSection = "ks-cancel"/)
    assert.match(service, /ksStep === "idle" \|\| _ksInternal/)
  })

  it("falls back to an idle-until-needed local service when the shared one is missing", () => {
    assert.match(panel, /readonly property var vpn: root\.sharedVpn \|\| localVpn/)
    assert.match(panel, /Service \{\s*id: localVpn\s*active: !root\.sharedVpn\s*\}/)
    assert.match(service, /property bool active: true/)
    assert.match(service, /if \(!active \|\| !installed \|\| linkProcess\.running\) return/)
  })

  it("keeps CLI verdicts the live tunnel cannot explain", () => {
    const actionGuard = service.indexOf("if (actionRunning) return", service.indexOf("linkDevice = link.device"))
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

  it("bounds every collected command and keeps NetworkManager read-only", () => {
    assert.match(service, /scripts\/run_bounded\.py/)
    assert.match(service, /\/usr\/bin\/python3/)
    assert.match(service, /--max-bytes", "262144"/)
    assert.match(service, /\/usr\/bin\/nmcli/)
    assert.match(service, /connection", "show", "--active"/)
    assert.doesNotMatch(service, /nmcli[\s\S]{0,100}(connection", "down"|connection", "up")/)
  })

  it("keeps the declared trust boundary in the runtime service", () => {
    assert.doesNotMatch(service, /\b(?:curl|wget)\b|FileView|settings\.json|keyring|pkill|sudo|pkexec/)
    assert.doesNotMatch(service, /"connection", "(?:up|down|delete|modify)"/)
  })

  it("does not let an old NetworkManager signal replace an action in flight", () => {
    const updateFacts = service.indexOf("linkDevice = link.device")
    const actionGuard = service.indexOf("if (actionRunning) return", updateFacts)
    const updateView = service.indexOf("if (link.active)", updateFacts)
    assert.ok(updateFacts !== -1 && actionGuard !== -1 && updateView !== -1)
    assert.ok(updateFacts < actionGuard && actionGuard < updateView)
  })

  it("shows compatibility warnings, CLI exit IP, and session recents", () => {
    assert.match(panel, /status\.exitIp/)
    assert.match(panel, /vpn\.compatibilityWarning/)
    assert.match(panel, /id: recentGrid/)
    assert.match(panel, /onClicked: root\.connectRecent\(index\)/)
    assert.match(panel, /readonly property var recentChoices: Model\.recentChoices\(vpn\.recentTargets, vpn\.activeTarget\)/)
    assert.match(panel, /model: root\.recentChoices/)
    assert.match(panel, /function onActiveTargetChanged\(\) \{ root\.connectDraftDirty = false \}/)
  })

  it("accepts an action before changing visual connecting state", () => {
    const enqueue = service.indexOf("if (!enqueue(job)) return false")
    const visual = service.indexOf("state = action === \"disconnect\" ? Model.STATES.disconnecting : Model.STATES.connecting")
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
    assert.match(panel, /Model\.modeTooltip\(root\.selectedMode\)/)
    assert.match(panel, /Model\.connectFieldTooltip\("country"\)/)
    assert.match(panel, /Model\.connectFieldTooltip\("city"\)/)
    assert.match(panel, /Model\.connectFieldTooltip\("server"\)/)
    assert.match(panel, /Model\.settingTooltip\("netshield"\)/)
    assert.match(panel, /Model\.settingTooltip\("kill-switch"\)/)
    assert.match(panel, /Model\.settingTooltip\("custom-dns"\)/)
    assert.match(panel, /Model\.settingTooltip\(toggleSettingRow\.key\)/)
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
    const settingsChoice = panel.match(/FieldLabel \{ text: "NetShield" \}[\s\S]*?id: netshieldDropdown/)
    assert.ok(settingsChoice, "SETTINGS grid must place NetShield label before its dropdown")
    assert.doesNotMatch(settingsChoice[0], /SettingHelp/)
    assert.match(panel, /FieldLabel \{ text: "Kill Switch" \}/)
    assert.doesNotMatch(panel, /FieldLabel \{ text: "Kill switch" \}/)
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
    assert.match(panel, /text: Model\.switchLabel\(root\.connectOptions\(\)\)/)
    assert.match(panel, /onClicked: root\.switchNow\(\)/)
    assert.match(panel, /if \(offerSwitch\) rows\.push\(\["switch"\]\)/)
    assert.match(panel, /focusSection === "switch"\) switchNow\(\)/)
    assert.match(panel, /onAccepted: root\.offerSwitch \? root\.switchNow\(\) : root\.tryToggle\(\)/)
    assert.doesNotMatch(panel, /function applyConnectDraft\(draft\) \{[^}]*connectDraftDirty/)
    assert.match(service, /activeTarget = target/)
    assert.match(service, /if \(state === Model\.STATES\.disconnected\) activeTarget = null/)
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
