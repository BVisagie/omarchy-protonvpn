const { describe, it } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { ROOT, collect } = require("./tools/catalog.js")

describe("translation catalog", () => {
  it("carries every key the code uses, with the same English", () => {
    const catalog = JSON.parse(fs.readFileSync(path.join(ROOT, "i18n", "en.json"), "utf8"))
    const used = collect()
    assert.ok(used.size > 150, "the scan found the strings")
    for (const [key, english] of used) assert.deepEqual(catalog[key], english, `${key}: run node tests/tools/build_catalog.js`)
    for (const key of Object.keys(catalog)) assert.ok(used.has(key), `${key} is not used`)
  })

  it("keeps placeholders whole so translations can reorder them", () => {
    const catalog = JSON.parse(fs.readFileSync(path.join(ROOT, "i18n", "en.json"), "utf8"))
    for (const [key, value] of Object.entries(catalog)) {
      for (const form of typeof value === "string" ? [value] : Object.values(value)) {
        assert.doesNotMatch(form, /%[^1-9]|%$/, key)
      }
    }
  })
})
