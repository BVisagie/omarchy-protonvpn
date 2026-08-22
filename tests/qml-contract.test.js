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
    assert.match(panel, /Model\.modeSummary\(root\.selectedMode\)/)
    assert.match(panel, /Model\.settingSummary\("netshield"\)/)
    assert.doesNotMatch(panel, /Model\.CONNECT_SECTION_HELP/)
    assert.doesNotMatch(panel, /Model\.modeHelp\(/)
    assert.doesNotMatch(panel, /Model\.settingCaption\(/)
    assert.doesNotMatch(panel, /Model\.connectFieldHelp\(/)
  })

  it("scrolls the Custom DNS row itself into view with bottom breathing room", () => {
    assert.match(panel, /focusSection === "config:custom-dns"\) scrollItemIntoView\(customDnsToggle\)/)
    assert.doesNotMatch(panel, /focusSection === "config:custom-dns"\) scrollItemIntoView\(dnsField\.visible \? dnsField : configColumn\)/)
    assert.match(panel, /id: customDnsToggle/)
    assert.match(panel, /height: Style\.space\(6\)/)
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
