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
})
