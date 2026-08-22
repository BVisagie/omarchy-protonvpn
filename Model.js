var CLI_PACKAGE = "proton-vpn-cli 1.0.1-1"
var OUTPUT_CAP = 400
var MESSAGE_CAP = 160
var SIGNIN_COMMAND = "protonvpn signin USERNAME"
var INSTALL_COMMAND = "sudo pacman -S proton-vpn-cli"
var SERVER_LIST_URL = "https://account.proton.me/vpn/WireGuard"

var STATES = {
  checking: "checking",
  cliMissing: "cliMissing",
  guiConflict: "guiConflict",
  signedOut: "signedOut",
  disconnected: "disconnected",
  connecting: "connecting",
  disconnecting: "disconnecting",
  connected: "connected",
  error: "error",
  stale: "stale"
}

var HEALTHY_TOGGLE_STATES = [STATES.connected, STATES.disconnected]

var CONNECTION_MODES = [
  { value: "fastest", label: "Fastest server" },
  { value: "country", label: "Country" },
  { value: "city", label: "City" },
  { value: "server", label: "Server ID" },
  { value: "securecore", label: "Secure Core" },
  { value: "p2p", label: "P2P" },
  { value: "tor", label: "Tor" },
  { value: "random", label: "Random" }
]

var CONFIG_SETTINGS = [
  {
    key: "netshield",
    label: "NetShield",
    type: "choice",
    values: ["off", "malware-only", "malware-ads-trackers"],
    valueLabels: {
      off: "Off",
      "malware-only": "Malware only",
      "malware-ads-trackers": "Malware, ads, and trackers"
    },
    free: false,
    restart: false
  },
  {
    key: "kill-switch",
    label: "Kill switch",
    type: "choice",
    values: ["off", "standard"],
    valueLabels: { off: "Off", standard: "Standard" },
    free: true,
    restart: false,
    disconnectFirst: true
  },
  {
    key: "port-forwarding",
    label: "Port forwarding",
    type: "toggle",
    values: ["off", "on"],
    free: false,
    restart: false
  },
  {
    key: "custom-dns",
    label: "Custom DNS",
    type: "dns",
    values: ["off", "on"],
    free: false,
    restart: true
  },
  {
    key: "vpn-accelerator",
    label: "VPN Accelerator",
    type: "toggle",
    values: ["off", "on"],
    free: false,
    restart: false
  },
  {
    key: "moderate-nat",
    label: "Moderate NAT",
    type: "toggle",
    values: ["off", "on"],
    free: false,
    restart: false
  },
  {
    key: "ipv6",
    label: "IPv6",
    type: "toggle",
    values: ["off", "on"],
    free: true,
    restart: true
  },
  {
    key: "anonymous-crash-reports",
    label: "Anonymous crash reports",
    type: "toggle",
    values: ["off", "on"],
    free: true,
    restart: false
  }
]

function emptyStatus() {
  return { server: "", location: "", load: null, protocol: "" }
}

function defaultView() {
  return {
    state: STATES.checking,
    kind: "",
    message: "",
    detail: "",
    stale: false,
    status: emptyStatus(),
    signedIn: false
  }
}

function normalizeOutput(text) {
  return String(text || "").replace(/\r\n/g, "\n").replace(/\r/g, "\n")
}

function capOutput(text, max) {
  var limit = typeof max === "number" && max > 0 ? max : OUTPUT_CAP
  var value = String(text || "").replace(/\s+/g, " ").trim()
  if (value.length > limit) return value.substring(0, limit - 1) + "…"
  return value
}

function combineOutput(stdout, stderr) {
  var out = String(stdout || "").trim()
  var err = String(stderr || "").trim()
  if (out && err) return out + "\n" + err
  return out || err
}

function hasGuiConflict(text) {
  var value = String(text || "")
  return /Proton VPN desktop app is currently running/i.test(value)
    || /The CLI and GUI cannot run simultaneously/i.test(value)
}

function hasAuthRequired(text) {
  var value = String(text || "")
  if (/Authentication required/i.test(value)) return true
  if (/Please sign in with/i.test(value)) return true
  if (/sign in to Proton VPN/i.test(value)) return true
  return false
}

function isTransientFailure(kind) {
  return kind === "timeout" || kind === "network"
}

function classifyFailureKind(text, timedOut) {
  if (timedOut === true) return "timeout"
  var value = String(text || "")
  if (hasGuiConflict(value)) return "gui"
  if (hasAuthRequired(value)) return "auth"
  if (/not available on the free plan/i.test(value) || /Upgrade to enable/i.test(value) || /Please upgrade to access/i.test(value)) {
    return "plan"
  }
  if (/Disconnect before changing Kill Switch/i.test(value)) return "prerequisite"
  if (/No servers found matching criteria/i.test(value)) return "empty"
  if (/not found or no servers available/i.test(value) || /Country '.*' not found/i.test(value)) return "empty"
  if (/Invalid (country|server|DNS|value)/i.test(value)) return "invalid"
  if (/network|timed out|timeout|connection refused|temporary failure|could not resolve|name or service not known|no route to host|network is unreachable/i.test(value)) {
    return "network"
  }
  if (/Connection failed/i.test(value)) return "action"
  return "error"
}

function sanitizeMessage(text, fallback) {
  var value = capOutput(text, MESSAGE_CAP)
  if (value === "") return String(fallback || "Command failed")
  value = value.replace(/^Error:\s*/i, "")
  return value
}

function parseLoad(line) {
  var match = String(line || "").match(/Load:\s*([0-9]+(?:\.[0-9]+)?)\s*%/i)
  if (!match) return null
  var n = Number(match[1])
  if (!isFinite(n) || n < 0) return null
  return n
}

function parseServerLine(line) {
  var text = String(line || "")
  var match = text.match(/^Server:\s+(.+?)\s+in\s+(.+)\s*$/)
  if (!match) return null
  return { server: String(match[1] || "").trim(), location: String(match[2] || "").trim() }
}

function parseStatus(raw) {
  var text = normalizeOutput(raw)
  var lines = text.split("\n")
  var statusLine = ""
  var serverLine = ""
  var loadLine = ""
  var protocolLine = ""
  for (var i = 0; i < lines.length; i++) {
    var line = String(lines[i] || "").trim()
    if (line === "") continue
    if (/^Status:\s+/i.test(line) && statusLine === "") statusLine = line
    else if (/^Server:\s+/i.test(line) && serverLine === "") serverLine = line
    else if (/^Load:\s+/i.test(line) && loadLine === "") loadLine = line
    else if (/^Protocol:\s+/i.test(line) && protocolLine === "") protocolLine = line
  }

  if (statusLine === "") {
    return { ok: false, kind: "parse", message: "Proton VPN status output is incompatible with this plugin." }
  }

  if (/^Status:\s*Disconnected\s*$/i.test(statusLine)) {
    return { ok: true, state: STATES.disconnected, status: emptyStatus() }
  }

  if (!/^Status:\s*Connected\s*$/i.test(statusLine)) {
    return { ok: false, kind: "parse", message: "Proton VPN reported an unknown status line." }
  }

  var server = parseServerLine(serverLine)
  if (!server || server.server === "" || server.location === "") {
    return { ok: false, kind: "parse", message: "Connected status is missing a server or location line." }
  }

  var protocol = ""
  var protocolMatch = String(protocolLine || "").match(/^Protocol:\s*(.+)\s*$/i)
  if (protocolMatch) protocol = String(protocolMatch[1] || "").trim()

  return {
    ok: true,
    state: STATES.connected,
    status: {
      server: server.server,
      location: server.location,
      load: parseLoad(loadLine),
      protocol: protocol
    }
  }
}

function retainStatus(prior) {
  if (!prior || !prior.status) return emptyStatus()
  return {
    server: String(prior.status.server || ""),
    location: String(prior.status.location || ""),
    load: prior.status.load === null || prior.status.load === undefined ? null : Number(prior.status.load),
    protocol: String(prior.status.protocol || "")
  }
}

function hasValidStatus(prior) {
  if (!prior) return false
  return prior.state === STATES.connected
    || prior.state === STATES.disconnected
    || prior.state === STATES.stale
}

function classifyProbe(result, prior) {
  var previous = prior || defaultView()
  var stdout = result && result.stdout !== undefined ? result.stdout : ""
  var stderr = result && result.stderr !== undefined ? result.stderr : ""
  var combined = combineOutput(stdout, stderr)
  var timedOut = result && result.timedOut === true
  var exitCode = result && typeof result.exitCode === "number" ? result.exitCode : 1

  if (result && result.cliMissing === true) {
    return viewFor(STATES.cliMissing, "cli", "Proton VPN CLI not installed.", combined, previous, false)
  }

  if (hasGuiConflict(combined)) {
    return viewFor(STATES.guiConflict, "gui", "Close the Proton VPN desktop app to use the CLI.", combined, previous, false)
  }

  if (hasAuthRequired(combined)) {
    return viewFor(STATES.signedOut, "auth", "Sign in to Proton VPN from a terminal.", combined, previous, false)
  }

  var parsed = parseStatus(stdout)
  if (!timedOut && exitCode === 0) {
    if (parsed.ok) {
      return {
        state: parsed.state,
        kind: "status",
        message: "",
        detail: "",
        stale: false,
        status: parsed.status,
        signedIn: previous.signedIn === true
      }
    }
    return viewFor(STATES.error, "parse", parsed.message || "Proton VPN status output is incompatible with this plugin.", combined, previous, false)
  }

  var failureKind = classifyFailureKind(combined, timedOut)
  var message = failureMessage(failureKind, combined)
  if (isTransientFailure(failureKind) && hasValidStatus(previous)) {
    return {
      state: STATES.stale,
      kind: failureKind,
      message: message,
      detail: capOutput(combined),
      stale: true,
      status: retainStatus(previous),
      signedIn: previous.signedIn === true
    }
  }

  return viewFor(STATES.error, failureKind, message, combined, previous, false)
}

function failureMessage(kind, combined) {
  if (kind === "timeout") return "Proton VPN did not respond in time."
  if (kind === "network") return "Proton VPN could not reach the network."
  if (kind === "parse") return "Proton VPN status output is incompatible with this plugin."
  if (kind === "plan") return sanitizeMessage(combined, "This option is not available on the current plan.")
  if (kind === "prerequisite") return sanitizeMessage(combined, "Disconnect before changing this setting.")
  if (kind === "empty") return sanitizeMessage(combined, "No matching Proton VPN servers were found.")
  if (kind === "invalid") return sanitizeMessage(combined, "Proton VPN rejected that value.")
  if (kind === "action") return sanitizeMessage(combined, "The Proton VPN command failed.")
  return sanitizeMessage(combined, "Proton VPN command failed.")
}

function viewFor(state, kind, message, combined, previous, stale) {
  var keepStatus = state === STATES.stale || (stale === true && hasValidStatus(previous))
  return {
    state: state,
    kind: kind,
    message: message,
    detail: capOutput(combined),
    stale: state === STATES.stale,
    status: keepStatus ? retainStatus(previous) : emptyStatus(),
    signedIn: previous && previous.signedIn === true && state !== STATES.signedOut && state !== STATES.cliMissing
  }
}

function classifyCommandResult(result, prior) {
  var previous = prior || defaultView()
  var combined = combineOutput(result && result.stdout, result && result.stderr)
  if (result && result.cliMissing === true) {
    return viewFor(STATES.cliMissing, "cli", "Proton VPN CLI not installed.", combined, previous, false)
  }
  if (hasGuiConflict(combined)) {
    return viewFor(STATES.guiConflict, "gui", "Close the Proton VPN desktop app to use the CLI.", combined, previous, false)
  }
  if (hasAuthRequired(combined)) {
    return viewFor(STATES.signedOut, "auth", "Sign in to Proton VPN from a terminal.", combined, previous, false)
  }
  var timedOut = result && result.timedOut === true
  var exitCode = result && typeof result.exitCode === "number" ? result.exitCode : 1
  if (exitCode === 0 && !timedOut) {
    return {
      ok: true,
      kind: "ok",
      message: sanitizeMessage(combined, ""),
      detail: capOutput(combined)
    }
  }
  var kind = classifyFailureKind(combined, timedOut)
  return {
    ok: false,
    kind: kind,
    message: failureMessage(kind, combined),
    detail: capOutput(combined),
    stateHint: kind === "gui" ? STATES.guiConflict : (kind === "auth" ? STATES.signedOut : "")
  }
}

function canToggleConnection(state) {
  return HEALTHY_TOGGLE_STATES.indexOf(String(state || "")) !== -1
}

function sliceTableColumn(line, start, end) {
  var text = String(line || "")
  if (start < 0 || start >= text.length) return ""
  if (end < 0) return text.substring(start).trim()
  return text.substring(start, Math.min(end, text.length)).trim()
}

function findTableHeader(lines, leftHeader, rightHeader) {
  for (var i = 0; i < lines.length; i++) {
    var line = String(lines[i] || "")
    var left = line.indexOf(leftHeader)
    var right = line.indexOf(rightHeader)
    if (left !== -1 && right !== -1 && right > left) {
      return { index: i, left: left, right: right, line: line }
    }
  }
  return null
}

function isSeparatorLine(line) {
  return /^\s*-{2,}(?:\s+-{2,})+\s*$/.test(String(line || ""))
}

function parseTwoColumnTable(raw, leftHeader, rightHeader) {
  var lines = normalizeOutput(raw).split("\n")
  var header = findTableHeader(lines, leftHeader, rightHeader)
  if (!header) return { ok: false, rows: [], message: "Proton VPN table output is incompatible with this plugin." }
  var rows = []
  var start = header.index + 1
  if (start < lines.length && isSeparatorLine(lines[start])) start += 1
  for (var i = start; i < lines.length; i++) {
    var line = String(lines[i] || "")
    if (/^\s*$/.test(line)) continue
    if (isSeparatorLine(line)) continue
    if (/^Use '/.test(line.trim()) || /^To upgrade/.test(line.trim()) || /^After upgrading/.test(line.trim())) break
    var left = sliceTableColumn(line, header.left, header.right)
    var right = sliceTableColumn(line, header.right, -1)
    if (left === "" && right === "") continue
    rows.push({ left: left, right: right })
  }
  return { ok: true, rows: rows, message: "" }
}

function parseCountries(raw) {
  var parsed = parseTwoColumnTable(raw, "Country", "Code")
  if (!parsed.ok) return parsed
  var countries = []
  for (var i = 0; i < parsed.rows.length; i++) {
    var name = String(parsed.rows[i].left || "").trim()
    var code = String(parsed.rows[i].right || "").trim().toUpperCase()
    if (name === "" || !/^[A-Z]{2}$/.test(code)) continue
    countries.push({ name: name, code: code, label: name + " (" + code + ")" })
  }
  return { ok: true, countries: countries, message: "" }
}

function parseCities(raw) {
  var parsed = parseTwoColumnTable(raw, "City", "Features")
  if (!parsed.ok) return parsed
  var cities = []
  for (var i = 0; i < parsed.rows.length; i++) {
    var name = String(parsed.rows[i].left || "").trim()
    var features = String(parsed.rows[i].right || "").trim()
    if (name === "") continue
    cities.push({ name: name, features: features, label: features !== "" ? name + " · " + features : name })
  }
  return { ok: true, cities: cities, message: "" }
}

function parseCustomDnsValue(value) {
  var text = String(value || "").trim()
  var match = text.match(/^(on|off)(?:\s+\[(.*)\])?$/i)
  if (!match) return { enabled: text !== "off" && text !== "", ips: [], raw: text }
  var ipsText = String(match[2] || "").trim()
  var ips = []
  if (ipsText !== "" && ipsText !== "...") {
    var parts = ipsText.split(",")
    for (var i = 0; i < parts.length; i++) {
      var ip = String(parts[i] || "").trim()
      if (ip !== "" && ip !== "...") ips.push(ip)
    }
  }
  return { enabled: match[1].toLowerCase() === "on", ips: ips, raw: text }
}

function parseConfigList(raw) {
  var parsed = parseTwoColumnTable(raw, "Setting", "Value")
  if (!parsed.ok) return parsed
  var settings = {}
  var upgrade = {}
  for (var i = 0; i < parsed.rows.length; i++) {
    var key = String(parsed.rows[i].left || "").trim()
    var value = String(parsed.rows[i].right || "").trim()
    if (key === "") continue
    if (/^Upgrade to enable$/i.test(value)) {
      settings[key] = ""
      upgrade[key] = true
    } else {
      settings[key] = value
      upgrade[key] = false
    }
  }
  var known = 0
  for (var j = 0; j < CONFIG_SETTINGS.length; j++) {
    if (settings[CONFIG_SETTINGS[j].key] !== undefined) known += 1
  }
  if (known === 0) {
    return { ok: false, settings: {}, upgrade: {}, message: "Proton VPN configuration output is incompatible with this plugin." }
  }
  return { ok: true, settings: settings, upgrade: upgrade, message: "" }
}

function settingDef(key) {
  for (var i = 0; i < CONFIG_SETTINGS.length; i++) {
    if (CONFIG_SETTINGS[i].key === key) return CONFIG_SETTINGS[i]
  }
  return null
}

function isIPv4(value) {
  var parts = String(value || "").split(".")
  if (parts.length !== 4) return false
  for (var i = 0; i < 4; i++) {
    if (!/^[0-9]{1,3}$/.test(parts[i])) return false
    var n = parseInt(parts[i], 10)
    if (n < 0 || n > 255) return false
  }
  return true
}

function isIPv6(value) {
  var text = String(value || "")
  if (text.indexOf(":") === -1) return false
  if (/[^0-9a-fA-F:]/.test(text)) return false
  if (text.split("::").length > 2) return false
  var groups = text.split(":")
  if (groups.length < 3 || groups.length > 8) return false
  for (var i = 0; i < groups.length; i++) {
    if (groups[i] === "") continue
    if (!/^[0-9a-fA-F]{1,4}$/.test(groups[i])) return false
  }
  return true
}

function parseDnsList(text) {
  var parts = String(text || "").split(",")
  var ips = []
  for (var i = 0; i < parts.length; i++) {
    var ip = String(parts[i] || "").trim()
    if (ip === "") continue
    ips.push(ip)
  }
  return ips
}

function validateDnsList(text) {
  var ips = parseDnsList(text)
  if (ips.length === 0) return { ok: false, message: "Enter at least one DNS server IP.", ips: [] }
  for (var i = 0; i < ips.length; i++) {
    if (!isIPv4(ips[i]) && !isIPv6(ips[i])) {
      return { ok: false, message: "Invalid DNS address '" + ips[i] + "'. Use IPv4 or IPv6.", ips: [] }
    }
  }
  return { ok: true, message: "", ips: ips }
}

function validateServerId(value) {
  var text = String(value || "").trim()
  if (text === "") return { ok: false, message: "Enter a Proton VPN server ID such as IT#23." }
  if (!/^[A-Za-z]{2,3}(?:-[A-Za-z]{2,3})?#\d+$/.test(text)) {
    return { ok: false, message: "Server IDs look like IT#23 or CH-IS#1. Proton lists them in the account server list." }
  }
  return { ok: true, message: "", value: text }
}

function modeNeedsCountry(mode) {
  return mode === "country" || mode === "city" || mode === "p2p" || mode === "securecore" || mode === "tor"
}

function modeRequiresCountry(mode) {
  return mode === "country" || mode === "city"
}

function modeNeedsCity(mode) {
  return mode === "city"
}

function modeNeedsServer(mode) {
  return mode === "server"
}

function buildConnectCommand(options) {
  var opts = options || {}
  var mode = String(opts.mode || "fastest")
  var command = ["protonvpn", "connect"]
  var country = String(opts.country || "").trim()
  var city = String(opts.city || "").trim()
  var serverId = String(opts.serverId || "").trim()

  if (mode === "fastest") return { ok: true, command: command }
  if (mode === "random") return { ok: true, command: command.concat(["--random"]) }

  if (mode === "server") {
    if (country !== "" || city !== "" || opts.p2p || opts.securecore || opts.tor || opts.random) {
      return { ok: false, message: "A specific server ID cannot be combined with other connection filters." }
    }
    var server = validateServerId(serverId)
    if (!server.ok) return server
    return { ok: true, command: command.concat([server.value]) }
  }

  if (mode === "country") {
    if (country === "") return { ok: false, message: "Choose a country before connecting." }
    return { ok: true, command: command.concat(["--country", country]) }
  }

  if (mode === "city") {
    if (country === "") return { ok: false, message: "Choose a country before listing cities." }
    if (city === "") return { ok: false, message: "Choose a city before connecting." }
    return { ok: true, command: command.concat(["--country", country, "--city", city]) }
  }

  if (mode === "p2p" || mode === "securecore" || mode === "tor") {
    if (country !== "") command = command.concat(["--country", country])
    if (mode === "p2p") command = command.concat(["--p2p"])
    else if (mode === "securecore") command = command.concat(["--securecore"])
    else command = command.concat(["--tor"])
    return { ok: true, command: command }
  }

  return { ok: false, message: "Unknown connection mode." }
}

function buildConfigSetCommand(setting, value, context) {
  var def = settingDef(setting)
  if (!def) return { ok: false, message: "Unknown Proton VPN setting." }
  var ctx = context || {}
  var next = String(value || "").trim()
  if (def.disconnectFirst && ctx.connected === true) {
    return { ok: false, message: "Disconnect before changing Kill Switch.", kind: "prerequisite" }
  }
  if (def.values && def.values.indexOf(next) === -1) {
    return { ok: false, message: "Invalid value '" + next + "' for " + def.label + "." }
  }
  if (def.type === "dns") {
    if (next === "off") return { ok: true, command: ["protonvpn", "config", "set", "custom-dns", "off"], restart: def.restart === true }
    var dns = validateDnsList(ctx.dns || "")
    if (!dns.ok) return dns
    return {
      ok: true,
      command: ["protonvpn", "config", "set", "custom-dns", "on", "--dns", dns.ips.join(",")],
      restart: def.restart === true
    }
  }
  return {
    ok: true,
    command: ["protonvpn", "config", "set", setting, next],
    restart: def.restart === true
  }
}

function displayLoad(load) {
  if (load === null || load === undefined || !isFinite(Number(load))) return "Unknown"
  return Math.round(Number(load)) + "%"
}

function connectedSummary(status) {
  var item = status || emptyStatus()
  var parts = []
  if (item.server) parts.push(item.server)
  if (item.location) parts.push(item.location)
  if (item.load !== null && item.load !== undefined && isFinite(Number(item.load))) parts.push("Load " + displayLoad(item.load))
  if (item.protocol) parts.push(item.protocol)
  return parts.join(" · ")
}

function tooltipText(view) {
  var state = view && view.state ? view.state : STATES.checking
  if (state === STATES.connected) {
    var summary = connectedSummary(view.status)
    return summary !== "" ? "Proton VPN · " + summary : "Proton VPN connected."
  }
  if (state === STATES.disconnected) return "Proton VPN disconnected."
  if (state === STATES.connecting) return "Connecting to Proton VPN…"
  if (state === STATES.disconnecting) return "Disconnecting Proton VPN…"
  if (state === STATES.checking) return "Checking Proton VPN status…"
  if (state === STATES.cliMissing) return "Proton VPN CLI not installed."
  if (state === STATES.signedOut) return "Sign in to Proton VPN from a terminal."
  if (state === STATES.guiConflict) return "Close the Proton VPN desktop app to use the CLI."
  if (state === STATES.stale) {
    var staleSummary = connectedSummary(view.status)
    var prefix = staleSummary !== "" ? staleSummary + " · " : ""
    return prefix + (view.message || "Proton VPN status may be outdated.")
  }
  return view && view.message ? view.message : "Proton VPN error."
}

function heroTitle(view) {
  var state = view && view.state ? view.state : STATES.checking
  if (state === STATES.connected && view.status && view.status.server) return view.status.server
  return "Proton VPN"
}

function heroMeta(view) {
  var state = view && view.state ? view.state : STATES.checking
  if (state === STATES.connected) return view.status && view.status.location ? view.status.location : "Connected"
  if (state === STATES.disconnected) return "Disconnected"
  if (state === STATES.connecting) return "Connecting"
  if (state === STATES.disconnecting) return "Disconnecting"
  if (state === STATES.checking) return "Checking status"
  if (state === STATES.cliMissing) return "CLI not installed"
  if (state === STATES.signedOut) return "Sign-in required"
  if (state === STATES.guiConflict) return "Desktop app is running"
  if (state === STATES.stale) return "Status may be outdated"
  return "Needs attention"
}

function heroDetail(view) {
  var state = view && view.state ? view.state : ""
  if (state === STATES.connected && view.status && view.status.protocol) return view.status.protocol
  if (state === STATES.stale) return "Stale"
  return ""
}

function relativeTime(fromMs, nowMs) {
  var then = Number(fromMs || 0)
  var now = nowMs === undefined ? Date.now() : Number(nowMs)
  if (!isFinite(then) || then <= 0) return ""
  var diff = Math.max(0, Math.floor((now - then) / 1000))
  if (diff < 5) return "just now"
  if (diff < 60) return diff + "s ago"
  var minutes = Math.floor(diff / 60)
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  return Math.floor(hours / 24) + "d ago"
}

function lastUpdatedText(view, nowMs) {
  var when = relativeTime(view && view.lastUpdatedMs, nowMs)
  if (when === "") return ""
  if (view && view.state === STATES.stale) return "Last successful update " + when
  return "Updated " + when
}

function degradedExplanation(state) {
  if (state === STATES.cliMissing) {
    return "The official Proton VPN CLI is not installed or is not on PATH."
  }
  if (state === STATES.signedOut) {
    return "The CLI is installed but this session is signed out. Sign in from a terminal; this plugin never asks for a password or 2FA code."
  }
  if (state === STATES.guiConflict) {
    return "Proton VPN's desktop app is running. The official CLI refuses to operate until that app is closed."
  }
  if (state === STATES.error) {
    return "Proton VPN could not complete the last command."
  }
  if (state === STATES.stale) {
    return "The last status probe failed. The previous result is still shown and may be outdated."
  }
  return ""
}

function degradedRemediation(state) {
  if (state === STATES.cliMissing) {
    return "Install with `" + INSTALL_COMMAND + "`. The package is in Arch extra; Proton's upstream Linux support list does not currently include Arch, so updates and support may be limited."
  }
  if (state === STATES.signedOut) {
    return "Run `" + SIGNIN_COMMAND + "` in a terminal, then refresh. Replace USERNAME with your Proton account."
  }
  if (state === STATES.guiConflict) {
    return "Quit the Proton VPN desktop application, then refresh this panel."
  }
  if (state === STATES.stale || state === STATES.error) {
    return "Use Refresh after the network, daemon, or CLI is available again."
  }
  return ""
}

function copyCommandFor(state) {
  if (state === STATES.cliMissing) return INSTALL_COMMAND
  if (state === STATES.signedOut) return SIGNIN_COMMAND
  return ""
}

function iconCrossed(state) {
  return state === STATES.disconnected || state === STATES.signedOut
}

function iconWarning(state) {
  return state === STATES.cliMissing || state === STATES.guiConflict || state === STATES.error || state === STATES.stale
}

function iconUrgent(state) {
  return state === STATES.cliMissing || state === STATES.guiConflict || state === STATES.error || state === STATES.stale
}

function iconDim(state) {
  return state !== STATES.connected && state !== STATES.connecting
}

function clampRefreshIntervalSec(value) {
  var n = parseInt(String(value), 10)
  if (!isFinite(n)) n = 30
  if (n < 10) n = 10
  if (n > 3600) n = 3600
  return n
}

function configValueLabel(key, value) {
  var def = settingDef(key)
  var raw = String(value || "")
  if (!def) return raw
  if (def.type === "dns") {
    var dns = parseCustomDnsValue(raw)
    if (!dns.enabled) return "Off"
    return dns.ips.length > 0 ? "On · " + dns.ips.join(", ") : "On"
  }
  if (def.valueLabels && def.valueLabels[raw]) return def.valueLabels[raw]
  if (raw === "on") return "On"
  if (raw === "off") return "Off"
  return raw
}

function restartNotice(setting) {
  var def = settingDef(setting)
  if (def && def.restart) return "Establish a new VPN connection for this change to take effect."
  return ""
}

if (typeof module !== "undefined") {
  module.exports = {
    CLI_PACKAGE: CLI_PACKAGE,
    OUTPUT_CAP: OUTPUT_CAP,
    SIGNIN_COMMAND: SIGNIN_COMMAND,
    INSTALL_COMMAND: INSTALL_COMMAND,
    SERVER_LIST_URL: SERVER_LIST_URL,
    STATES: STATES,
    CONNECTION_MODES: CONNECTION_MODES,
    CONFIG_SETTINGS: CONFIG_SETTINGS,
    emptyStatus: emptyStatus,
    defaultView: defaultView,
    normalizeOutput: normalizeOutput,
    capOutput: capOutput,
    combineOutput: combineOutput,
    hasGuiConflict: hasGuiConflict,
    hasAuthRequired: hasAuthRequired,
    classifyFailureKind: classifyFailureKind,
    parseStatus: parseStatus,
    classifyProbe: classifyProbe,
    classifyCommandResult: classifyCommandResult,
    canToggleConnection: canToggleConnection,
    parseCountries: parseCountries,
    parseCities: parseCities,
    parseConfigList: parseConfigList,
    parseCustomDnsValue: parseCustomDnsValue,
    settingDef: settingDef,
    isIPv4: isIPv4,
    isIPv6: isIPv6,
    validateDnsList: validateDnsList,
    validateServerId: validateServerId,
    modeNeedsCountry: modeNeedsCountry,
    modeRequiresCountry: modeRequiresCountry,
    modeNeedsCity: modeNeedsCity,
    modeNeedsServer: modeNeedsServer,
    buildConnectCommand: buildConnectCommand,
    buildConfigSetCommand: buildConfigSetCommand,
    displayLoad: displayLoad,
    connectedSummary: connectedSummary,
    tooltipText: tooltipText,
    heroTitle: heroTitle,
    heroMeta: heroMeta,
    heroDetail: heroDetail,
    relativeTime: relativeTime,
    lastUpdatedText: lastUpdatedText,
    degradedExplanation: degradedExplanation,
    degradedRemediation: degradedRemediation,
    copyCommandFor: copyCommandFor,
    iconCrossed: iconCrossed,
    iconWarning: iconWarning,
    iconUrgent: iconUrgent,
    iconDim: iconDim,
    clampRefreshIntervalSec: clampRefreshIntervalSec,
    configValueLabel: configValueLabel,
    restartNotice: restartNotice
  }
}
