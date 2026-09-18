const { describe, it } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "manifest.json"), "utf8"))

describe("plugin manifest", () => {
  it("declares one shared service and the existing bar widget", () => {
    assert.equal(manifest.schemaVersion, 1)
    assert.equal(manifest.id, "io.github.BVisagie.protonvpn")
    assert.equal(manifest.version, "1.1.0")
    assert.deepEqual(manifest.kinds, ["service", "bar-widget"])
    assert.equal(manifest.entryPoints.service, "Service.qml")
    assert.equal(manifest.entryPoints.barWidget, "Panel.qml")
    assert.equal(manifest.barWidget.allowMultiple, false)
  })

  it("publishes bounded polling settings", () => {
    assert.equal(manifest.barWidget.defaults.refreshIntervalSec, 30)
    assert.equal(manifest.barWidget.defaults.linkWatchIntervalSec, 4)
    const watch = manifest.barWidget.schema.find((entry) => entry.key === "linkWatchIntervalSec")
    assert.deepEqual(
      { min: watch.min, max: watch.max, step: watch.step, defaultValue: watch.defaultValue },
      { min: 2, max: 60, step: 1, defaultValue: 4 }
    )
  })

  it("publishes a notification setting that defaults to drops", () => {
    assert.equal(manifest.barWidget.defaults.notifications, "drops")
    const entry = manifest.barWidget.schema.find((item) => item.key === "notifications")
    assert.equal(entry.type, "enum")
    assert.deepEqual(entry.options.map((o) => o.value), ["off", "drops", "all"])
    assert.equal(entry.defaultValue, "drops")
  })
})
