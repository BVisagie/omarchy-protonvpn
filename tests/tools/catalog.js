"use strict"

// Every string the plugin shows is looked up as tr("key", "English") in QML,
// say(loc, "key", "English") in Model.js, or derived from Model.js's tables.
// collect() gathers them all; build_catalog.js writes them to i18n/en.json and
// tests/i18n.test.js fails when the two disagree.

const fs = require("node:fs")
const path = require("node:path")

const ROOT = path.join(__dirname, "..", "..")
const CALL = /\b(?:tr|say\(loc,)\s*\(?\s*"([a-zA-Z0-9.-]+)",\s*"((?:[^"\\]|\\.)*)"/g
// sayN(loc, "key", count, "one", "other") and trn("key", count, "one", "other").
const PLURAL = /\b(?:sayN\(loc,|trn\()\s*"([a-zA-Z0-9.-]+)",\s*[^,]+,\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"\)/g
const text = (raw) => JSON.parse(`"${raw}"`)

function sources() {
  return fs.readdirSync(ROOT).filter((name) => name.endsWith(".qml") || name === "Model.js")
}

function tableStrings(Model) {
  const out = []
  for (const def of Model.CONNECTION_MODES) {
    for (const field of ["label", "tooltip", "description"]) out.push([`mode.${def.value}.${field}`, def[field]])
  }
  for (const def of Model.CONNECT_FIELDS) out.push([`field.${def.key}.tooltip`, def.tooltip])
  for (const def of Model.CONFIG_SETTINGS) {
    out.push([`setting.${def.key}.label`, def.label], [`setting.${def.key}.tooltip`, def.tooltip])
    for (const value of Object.keys(def.valueLabels || {})) out.push([`setting.${def.key}.value.${value}`, def.valueLabels[value]])
    for (const value of Object.keys(def.valueDescriptions || {})) out.push([`setting.${def.key}.valueDescription.${value}`, def.valueDescriptions[value]])
  }
  return out
}

function collect() {
  const used = new Map()
  const add = (key, english, where) => {
    if (used.has(key) && JSON.stringify(used.get(key)) !== JSON.stringify(english)) {
      throw new Error(`${key} has two English texts (${where})`)
    }
    used.set(key, english)
  }
  for (const name of sources()) {
    const code = fs.readFileSync(path.join(ROOT, name), "utf8")
    for (const m of code.matchAll(CALL)) add(m[1], text(m[2]), name)
    for (const m of code.matchAll(PLURAL)) add(m[1], { one: text(m[2]), other: text(m[3]) }, name)
  }
  for (const [key, english] of tableStrings(require(path.join(ROOT, "Model.js")))) add(key, english, "Model.js tables")
  return used
}

module.exports = { ROOT, collect }
