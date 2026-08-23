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
