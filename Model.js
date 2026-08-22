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

var SETTINGS_SECTION_HELP = "Most CLI settings apply without reconnecting. IPv6 and custom DNS need a new VPN connection."
var TOOLTIP_MAX_LENGTH = 90
var OPTION_DESCRIPTION_MAX_LENGTH = 60

var CONNECTION_MODES = [
  {
    value: "fastest",
    label: "Fastest server",
    help: "Connects to the fastest VPN server available on your plan.",
    tooltip: "Connects to the fastest VPN server on your plan.",
    description: "Fastest server on your plan"
  },
  {
    value: "country",
    label: "Country",
    help: "Connects to a server in the selected country, using a country code such as US or the full name.",
    tooltip: "Connects to a server in the selected country.",
    description: "A country code or full name"
  },
  {
    value: "city",
    label: "City",
    help: "Connects to a server in the selected city after you choose the country.",
    tooltip: "Connects to a server in the selected city.",
    description: "A city in the selected country"
  },
  {
    value: "server",
    label: "Server ID",
    help: "Connects to a specific server such as CH#242. Proton lists IDs in the account WireGuard server list.",
    tooltip: "Connects to a specific server such as CH#242.",
    description: "A specific server such as CH#242"
  },
  {
    value: "securecore",
    label: "Secure Core",
    help: "Routes traffic through extra Proton-owned Secure Core servers before the exit country, which makes it harder to trace the connection back to you. Available on paid plans.",
    tooltip: "Extra Proton-owned hop before the exit. Paid plans.",
    description: "Extra Proton-owned hop before the exit"
  },
  {
    value: "p2p",
    label: "P2P",
    help: "Connects to a peer-to-peer server. Proton uses these servers for file sharing, and port forwarding requires a P2P server.",
    tooltip: "Peer-to-peer servers. Required for port forwarding.",
    description: "Peer-to-peer servers"
  },
  {
    value: "tor",
    label: "Tor",
    help: "Connects to a Tor-over-VPN server so traffic enters the Tor network, including .onion sites. Proton recommends this only when you need that extra anonymity. NetShield does not work on Tor servers.",
    tooltip: "Tor over VPN, including .onion sites. NetShield will not work.",
    description: "Tor over VPN, including .onion sites"
  },
  {
    value: "random",
    label: "Random",
    help: "Asks the CLI to connect to a random Proton VPN server.",
    tooltip: "Connects to a random Proton VPN server.",
    description: "A random Proton VPN server"
  }
]

var CONNECT_FIELDS = [
  {
    key: "country",
    label: "Country",
    help: "Use a country code such as US, or the full country name.",
    tooltip: "Use a country code such as US, or the full country name.",
    summary: "Country code or full name."
  },
  {
    key: "city",
    label: "City",
    help: "Choose a city in that country. Multi-word names such as New York are supported.",
    tooltip: "Choose a city in that country. Multi-word names work.",
    summary: "Multi-word names are supported."
  },
  {
    key: "server",
    label: "Server ID",
    help: "Enter a server ID such as CH#242. Proton publishes IDs in the account WireGuard server list.",
    tooltip: "Enter a server ID such as CH#242.",
    summary: "IDs are listed in the account WireGuard list."
  }
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
    valueDescriptions: {
      off: "No DNS filtering.",
      "malware-only": "Blocks malware, spyware, and malicious domains.",
      "malware-ads-trackers": "Blocks ads, trackers, and malware."
    },
    help: "Proton's DNS filtering while you are connected. It does not work with Tor over VPN or custom DNS, because those send DNS queries somewhere Proton cannot filter.",
    tooltip: "Proton's DNS filtering while you are connected.",
    summary: "Does not work with Tor over VPN or custom DNS.",
    free: false,
    restart: false
  },
  {
    key: "kill-switch",
    label: "Kill switch",
    type: "choice",
    values: ["off", "standard"],
    valueLabels: { off: "Off", standard: "Standard" },
    valueDescriptions: {
      off: "Internet stays available if the VPN drops.",
      standard: "Blocks all internet if the VPN drops accidentally."
    },
    help: "Standard kill switch blocks internet traffic if the VPN connection drops accidentally, so your IP address and DNS queries are not exposed. The Linux CLI does not offer Advanced kill switch.",
    tooltip: "Blocks internet if the VPN drops accidentally. CLI has Standard only.",
    free: true,
    restart: false,
    disconnectFirst: true
  },
  {
    key: "port-forwarding",
    label: "Port forwarding",
    type: "toggle",
    values: ["off", "on"],
    help: "Opens a path for incoming connections through Proton's firewall. You must be connected to a P2P server. It cannot be used with Moderate NAT. Proton notes that opening a port carries a small risk.",
    tooltip: "Opens incoming connections. Proton notes a small risk.",
    summary: "Requires a P2P server. Cannot be used with Moderate NAT.",
    free: false,
    restart: false
  },
  {
    key: "custom-dns",
    label: "Custom DNS",
    type: "dns",
    values: ["off", "on"],
    help: "Sends DNS queries to third-party resolvers you choose instead of Proton's DNS. Cannot be used with NetShield, because NetShield filters DNS at Proton.",
    tooltip: "Third-party DNS instead of Proton's. Needs a new connection.",
    summary: "Cannot be used with NetShield.",
    free: false,
    restart: true
  },
  {
    key: "vpn-accelerator",
    label: "VPN Accelerator",
    type: "toggle",
    values: ["off", "on"],
    help: "Uses Proton's VPN Accelerator technologies to improve connection stability and, in some cases, speed.",
    tooltip: "Improves connection stability and, in some cases, speed.",
    free: false,
    restart: false
  },
  {
    key: "moderate-nat",
    label: "Moderate NAT",
    type: "toggle",
    values: ["off", "on"],
    help: "Allows direct peer-to-peer connections for gaming and WebRTC. Proton says this slightly reduces privacy compared with strict NAT, and it cannot be used with port forwarding.",
    tooltip: "Allows direct P2P for gaming and WebRTC. Slightly less private.",
    summary: "Proton recommends leaving this off (strict NAT).",
    defaultHint: "Proton recommends leaving this off (strict NAT) unless you need those connections.",
    free: false,
    restart: false
  },
  {
    key: "ipv6",
    label: "IPv6",
    type: "toggle",
    values: ["off", "on"],
    help: "Routes traffic inside the VPN tunnel over IPv6 when the server supports it.",
    tooltip: "IPv6 inside the tunnel when supported. Needs a new connection.",
    summary: "Proton's Linux apps turn IPv6 on by default.",
    defaultHint: "Proton's Linux apps turn IPv6 on by default.",
    free: true,
    restart: true
  },
  {
    key: "anonymous-crash-reports",
    label: "Anonymous crash reports",
    type: "toggle",
    values: ["off", "on"],
    help: "Sends anonymous crash reports to Proton VPN to help them fix bugs and improve the software.",
    tooltip: "Sends anonymous crash reports to help Proton fix bugs.",
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
    signedIn: false,
    connectedSnapshot: false
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

function classifyFailureKind(text, timedOut) {
  if (timedOut === true) return "timeout"
  var value = String(text || "")
  if (hasGuiConflict(value)) return "gui"
  if (/Keyring error|SecretService|Failed to create the collection|Secret Service not available|Remote peer disconnected/i.test(value)) {
    return "keyring"
  }
  if (hasAuthRequired(value)) return "auth"
  if (/Timed out after \d+s waiting for event/i.test(value) || /Connect timeout/i.test(value)) {
    return "connectionTimeout"
  }
  if (/proton-vpn-daemon|VPN daemon|daemon did not|org\.proton\.vpn/i.test(value)) return "daemon"
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
        signedIn: true,
        connectedSnapshot: parsed.state === STATES.connected
      }
    }
    if (hasValidStatus(previous)) {
      return staleView(previous, "parse", parsed.message || "Proton VPN status output is incompatible with this plugin.", combined)
    }
    return viewFor(STATES.error, "parse", parsed.message || "Proton VPN status output is incompatible with this plugin.", combined, previous, false)
  }

  var failureKind = classifyFailureKind(combined, timedOut)
  var message = failureMessage(failureKind, combined)
  if (hasValidStatus(previous)) {
    return staleView(previous, failureKind, message, combined)
  }

  return viewFor(STATES.error, failureKind, message, combined, previous, false)
}

function failureMessage(kind, combined) {
  if (kind === "timeout") return "Proton VPN did not respond in time."
  if (kind === "connectionTimeout") return "Proton VPN timed out while connecting. The CLI reached a server but the handshake did not finish."
  if (kind === "keyring") return "Proton VPN could not read saved credentials from the system keyring."
  if (kind === "daemon") return "The Proton VPN daemon did not respond."
  if (kind === "network") return "Proton VPN could not reach the network."
  if (kind === "parse") return "Proton VPN status output is incompatible with this plugin."
  if (kind === "plan") return sanitizeMessage(combined, "This option is not available on the current plan.")
  if (kind === "prerequisite") return sanitizeMessage(combined, "Disconnect before changing this setting.")
  if (kind === "empty") return sanitizeMessage(combined, "No matching Proton VPN servers were found.")
  if (kind === "invalid") return sanitizeMessage(combined, "Proton VPN rejected that value.")
  if (kind === "action") return sanitizeMessage(combined, "The Proton VPN command failed.")
  return sanitizeMessage(combined, "Proton VPN command failed.")
}

function snapshotConnected(previous) {
  if (!previous) return false
  if (previous.connectedSnapshot === true) return true
  return previous.state === STATES.connected || previous.state === STATES.connecting
}

function staleView(previous, kind, message, combined) {
  return {
    state: STATES.stale,
    kind: kind,
    message: message,
    detail: capOutput(combined),
    stale: true,
    status: retainStatus(previous),
    signedIn: previous && previous.signedIn === true,
    connectedSnapshot: snapshotConnected(previous)
  }
}

function viewFor(state, kind, message, combined, previous, stale) {
  var keepStatus = state === STATES.stale || (stale === true && hasValidStatus(previous))
  var connected = state === STATES.connected
  if (state === STATES.stale) connected = snapshotConnected(previous)
  else if (state === STATES.disconnected || state === STATES.signedOut || state === STATES.cliMissing) connected = false
  return {
    state: state,
    kind: kind,
    message: message,
    detail: capOutput(combined),
    stale: state === STATES.stale,
    status: keepStatus ? retainStatus(previous) : emptyStatus(),
    signedIn: (previous && previous.signedIn === true && state !== STATES.signedOut && state !== STATES.cliMissing) || state === STATES.connected || state === STATES.disconnected,
    connectedSnapshot: connected
  }
}

function classifyCommandResult(result, prior) {
  var previous = prior || defaultView()
  var combined = combineOutput(result && result.stdout, result && result.stderr)
  if (result && result.cliMissing === true) {
    return {
      ok: false,
      kind: "cli",
      message: "Proton VPN CLI not installed.",
      detail: capOutput(combined),
      stateHint: STATES.cliMissing
    }
  }
  if (hasGuiConflict(combined)) {
    return {
      ok: false,
      kind: "gui",
      message: "Close the Proton VPN desktop app to use the CLI.",
      detail: capOutput(combined),
      stateHint: STATES.guiConflict
    }
  }
  if (hasAuthRequired(combined)) {
    return {
      ok: false,
      kind: "auth",
      message: "Sign in to Proton VPN from a terminal.",
      detail: capOutput(combined),
      stateHint: STATES.signedOut
    }
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

function canWrite(state) {
  return canToggleConnection(state)
}

function writeBlockedReason(state) {
  if (canWrite(state)) return ""
  if (state === STATES.checking) return "Wait for Proton VPN status before making changes."
  if (state === STATES.stale) return "Refresh Proton VPN status before making changes. The last result may be outdated."
  if (state === STATES.connecting || state === STATES.disconnecting) return "Wait for the current Proton VPN action to finish."
  if (state === STATES.cliMissing) return "Install the Proton VPN CLI before making changes."
  if (state === STATES.signedOut) return "Sign in to Proton VPN from a terminal before making changes."
  if (state === STATES.guiConflict) return "Close the Proton VPN desktop app before making changes."
  return "Proton VPN is not ready for changes."
}

function isVpnActive(view) {
  if (!view) return false
  if (view.state === STATES.connected || view.state === STATES.connecting) return true
  if (view.connectedSnapshot === true && (view.state === STATES.stale || view.state === STATES.error)) return true
  return false
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

function modeDef(value) {
  var mode = String(value || "")
  for (var i = 0; i < CONNECTION_MODES.length; i++) {
    if (CONNECTION_MODES[i].value === mode) return CONNECTION_MODES[i]
  }
  return null
}

function connectFieldDef(key) {
  var name = String(key || "")
  for (var i = 0; i < CONNECT_FIELDS.length; i++) {
    if (CONNECT_FIELDS[i].key === name) return CONNECT_FIELDS[i]
  }
  return null
}

function captionFor(item) {
  if (!item) return ""
  var help = String(item.help || "").trim()
  var hint = String(item.defaultHint || "").trim()
  if (help && hint) return help + " " + hint
  return help || hint
}

function tooltipFor(item) {
  if (!item) return ""
  return String(item.tooltip || "").trim()
}

function summaryFor(item) {
  if (!item) return ""
  return String(item.summary || "").trim()
}

function settingCaption(key) {
  return captionFor(settingDef(key))
}

function modeHelp(value) {
  return captionFor(modeDef(value))
}

function connectFieldHelp(key) {
  return captionFor(connectFieldDef(key))
}

function settingTooltip(key) {
  return tooltipFor(settingDef(key))
}

function modeTooltip(value) {
  return tooltipFor(modeDef(value))
}

function connectFieldTooltip(key) {
  return tooltipFor(connectFieldDef(key))
}

function settingSummary(key) {
  return summaryFor(settingDef(key))
}

function modeSummary(value) {
  return summaryFor(modeDef(value))
}

function connectFieldSummary(key) {
  return summaryFor(connectFieldDef(key))
}

function settingDescription(key, options) {
  var opts = options || {}
  if (opts.upgrade === true) {
    return "Upgrade to enable. Changing it still sends the CLI command so Proton can report the restriction."
  }
  return settingSummary(key)
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
    return "Proton VPN could not complete the last command. This can be a plugin, CLI, daemon, or keyring problem."
  }
  if (state === STATES.stale) {
    return "The last status probe failed. The previous result is still shown and may be outdated. Connection and settings changes stay disabled until a fresh probe succeeds."
  }
  return ""
}

function kindRemediation(kind) {
  if (kind === "keyring") {
    return "Unlock or restart the system keyring (Secret Service), then refresh. This is a local session problem, not a widget parser bug."
  }
  if (kind === "daemon") {
    return "Check that proton-vpn-daemon is running, then refresh. This is a Proton CLI/service problem."
  }
  if (kind === "connectionTimeout") {
    return "The CLI reached Proton but the connection handshake timed out. Retry, or check the network. This is not a widget command-queue failure."
  }
  if (kind === "timeout") {
    return "The Proton VPN command did not finish in time. Refresh after the CLI or daemon responds again."
  }
  if (kind === "network") {
    return "Check local network connectivity, then refresh. A failed probe is not treated as disconnected."
  }
  return ""
}

function degradedRemediation(viewOrState) {
  var view = typeof viewOrState === "string" ? { state: viewOrState } : (viewOrState || {})
  var state = view.state
  var fromKind = kindRemediation(view.kind)
  if (fromKind !== "") return fromKind
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
    return "Use Refresh after the network, daemon, or CLI is available again. Confirm `protonvpn status` in a terminal if the widget still fails."
  }
  return ""
}

function diagnosticDetail(view) {
  if (!view) return ""
  var detail = String(view.detail || "").trim()
  if (detail === "") return ""
  return capOutput(detail, 220)
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
    CONNECT_FIELDS: CONNECT_FIELDS,
    CONFIG_SETTINGS: CONFIG_SETTINGS,
    SETTINGS_SECTION_HELP: SETTINGS_SECTION_HELP,
    TOOLTIP_MAX_LENGTH: TOOLTIP_MAX_LENGTH,
    OPTION_DESCRIPTION_MAX_LENGTH: OPTION_DESCRIPTION_MAX_LENGTH,
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
    canWrite: canWrite,
    writeBlockedReason: writeBlockedReason,
    isVpnActive: isVpnActive,
    parseCountries: parseCountries,
    parseCities: parseCities,
    parseConfigList: parseConfigList,
    parseCustomDnsValue: parseCustomDnsValue,
    settingDef: settingDef,
    modeDef: modeDef,
    connectFieldDef: connectFieldDef,
    settingCaption: settingCaption,
    modeHelp: modeHelp,
    connectFieldHelp: connectFieldHelp,
    settingTooltip: settingTooltip,
    modeTooltip: modeTooltip,
    connectFieldTooltip: connectFieldTooltip,
    settingSummary: settingSummary,
    modeSummary: modeSummary,
    connectFieldSummary: connectFieldSummary,
    settingDescription: settingDescription,
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
    diagnosticDetail: diagnosticDetail,
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
