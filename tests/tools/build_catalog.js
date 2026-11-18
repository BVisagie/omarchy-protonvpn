"use strict"

// Rewrites i18n/en.json from the strings the code uses:
//   node tests/tools/build_catalog.js
// tests/i18n.test.js fails until the catalog matches.

const fs = require("node:fs")
const path = require("node:path")
const { ROOT, collect } = require("./catalog.js")

const used = collect()
const sorted = Object.fromEntries([...used.keys()].sort().map((key) => [key, used.get(key)]))
fs.mkdirSync(path.join(ROOT, "i18n"), { recursive: true })
fs.writeFileSync(path.join(ROOT, "i18n", "en.json"), JSON.stringify(sorted, null, 2) + "\n")
