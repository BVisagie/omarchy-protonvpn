var PLUGIN_ID = "io.github.BVisagie.protonvpn"
var CLI_PACKAGE = "proton-vpn-cli"
var MIN_TESTED_CLI_VERSION = "1.0.1"
var MAX_TESTED_CLI_VERSION = "1.0.5"
var OUTPUT_CAP = 400
var MESSAGE_CAP = 160
var SIGNIN_COMMAND = "protonvpn signin USERNAME"
// Omarchy's installer opens its own terminal, where pacman asks for the password.
var INSTALL_LAUNCHER = ["omarchy-install-app", "Proton VPN CLI", CLI_PACKAGE]
// A fixed script: the username is read inside the terminal and never reaches
// the shell process. `--` keeps a name that starts with a dash from parsing
// as an option.
var SIGNIN_SCRIPT = "read -rp 'Proton username: ' u && protonvpn signin -- \"$u\""
var SIGNIN_LAUNCHER = ["omarchy-launch-floating-terminal-with-presentation", SIGNIN_SCRIPT]
var SERVER_LIST_URL = "https://account.proton.me/vpn/WireGuard"
// Omarchy's system update, as its menu and bar widget launch it. A partial
// upgrade of one package is unsupported on Arch, so the CLI updates with
// everything else.
var UPDATE_LAUNCHER = ["omarchy-launch-floating-terminal-with-presentation", "omarchy-update"]

// Text for people goes through `loc`, which the QML passes in:
//   loc.tr(key, english)         -> the plugin's catalog (Commons.Translations)
//   loc.tn(key, count, english)  -> the plural form for count
//   loc.num(value, places)       -> Commons.I18n.formatNumber
// Without it every function answers in English, which the tests check.
// Tables below stay in English; tableText() derives their keys, and
// tests/tools/build_catalog.js writes both kinds into i18n/en.json.
function say(loc, key, english) {
  return loc && typeof loc.tr === "function" ? loc.tr(key, english) : english
}

function sayN(loc, key, count, one, other) {
  var english = Number(count) === 1 ? one : other
  return loc && typeof loc.tn === "function" ? loc.tn(key, count, english) : english
}

function num(loc, value, places) {
  if (loc && typeof loc.num === "function") return loc.num(value, places)
  var n = Number(value)
  if (!isFinite(n)) return String(value)
  return places === undefined ? String(n) : n.toFixed(places)
}

// "%1 of %2" with its arguments filled in; QML's arg() is not in Node.
function fill(template) {
  var args = arguments
  return String(template).replace(/%(\d)/g, function(m, i) {
    var k = Number(i)
    return k < args.length ? String(args[k]) : m
  })
}

// prefix is "mode", "field", or "setting"; id is the entry's value or key.
function tableText(loc, prefix, id, field, english) {
  return say(loc, prefix + "." + id + "." + field, String(english || ""))
}

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
    label: "Kill Switch",
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
    label: "Port Forwarding",
    type: "toggle",
    values: ["off", "on"],
    help: "Opens a path for incoming connections through Proton's firewall. You must be connected to a P2P server. It cannot be used with Moderate NAT. Proton notes that opening a port carries a small risk. The CLI does not show the forwarded port; Proton's Linux guide reads it with natpmpc.",
    tooltip: "Opens incoming connections. Use natpmpc to get the port.",
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
    label: "Anonymous Crash Reports",
    // A switch cell is half the panel; the tooltip says "anonymous".
    shortLabel: "Crash Reports",
    type: "toggle",
    values: ["off", "on"],
    help: "Sends anonymous crash reports to Proton VPN to help them fix bugs and improve the software.",
    tooltip: "Sends anonymous crash reports to help Proton fix bugs.",
    free: true,
    restart: false
  }
]

function emptyStatus() {
  return { server: "", location: "", load: null, protocol: "", exitIp: "" }
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
  return String(text || "")
    .replace(/\u001b\[[0-?]*[ -\/]*[@-~]/g, "")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
}

function compareVersions(left, right) {
  var a = String(left || "").split(".")
  var b = String(right || "").split(".")
  for (var i = 0; i < 3; i++) {
    var av = parseInt(a[i] || "0", 10)
    var bv = parseInt(b[i] || "0", 10)
    if (av < bv) return -1
    if (av > bv) return 1
  }
  return 0
}

function parseCliHelp(raw) {
  var text = normalizeOutput(raw)
  var match = text.match(/\b(\d+\.\d+\.\d+)(?:[-+][^\s]+)?\s*$/m)
  var version = match ? match[1] : ""
  var commands = []
  var known = ["signin", "signout", "info", "connect", "disconnect", "status", "servers", "countries", "cities", "config"]
  for (var i = 0; i < known.length; i++) {
    if (new RegExp("^[ \\t]*" + known[i] + "[ \\t]+", "m").test(text)) commands.push(known[i])
  }
  var support = "unknown"
  if (version !== "") {
    support = compareVersions(version, MIN_TESTED_CLI_VERSION) >= 0
      && compareVersions(version, MAX_TESTED_CLI_VERSION) <= 0 ? "tested" : "untested"
  }
  return { version: version, commands: commands, support: support }
}

function compatibilityWarning(cli, loc) {
  var info = cli || {}
  if (info.support === "tested") return ""
  if (String(info.version || "") === "") return say(loc, "compat.unknown", "Could not identify the Proton VPN CLI version. Core controls remain available.")
  return fill(say(loc, "compat.untested", "Proton VPN CLI %1 is outside the tested %2–%3 range."), info.version, MIN_TESTED_CLI_VERSION, MAX_TESTED_CLI_VERSION)
}

var TUNNEL_DEVICE = /^proton\d*$/i
var TUNNEL_TYPES = { wireguard: true, vpn: true, tun: true }

function isTunnelDevice(name) {
  return /^[A-Za-z0-9_.-]{1,15}$/.test(String(name || "")) && TUNNEL_DEVICE.test(String(name || ""))
}

// Proton's standard Kill Switch is a NetworkManager dummy connection. It stays
// up after an unexpected drop and blocks traffic until the VPN reconnects.
var KILL_SWITCH_CONNECTION = /^pvpn-killswitch(?:-perm)?$/
var KILL_SWITCH_BLOCKING_STATES = [STATES.disconnected, STATES.checking, STATES.stale]

function parseActiveVpn(raw) {
  var lines = normalizeOutput(raw).split("\n")
  var tunnel = null
  var killSwitch = false
  for (var i = 0; i < lines.length; i++) {
    var line = String(lines[i] || "").trim()
    if (line === "") continue
    var parts = line.split(":")
    // NAME may hold colons (-e no), so fields are read from the end; the
    // probe asks for TIMESTAMP last, older captures end at STATE.
    var since = 0
    if (/^\d+$/.test(parts[parts.length - 1])) since = Number(parts.pop())
    if (parts.length < 4) continue
    var state = parts[parts.length - 1]
    var device = parts[parts.length - 2]
    var type = parts[parts.length - 3]
    var name = parts.slice(0, parts.length - 3).join(":").replace(/\\:/g, ":")
    if (!/^activated$/i.test(state)) continue
    if (KILL_SWITCH_CONNECTION.test(name)) {
      killSwitch = true
      continue
    }
    if (tunnel) continue
    if (!TUNNEL_DEVICE.test(device)) continue
    if (!TUNNEL_TYPES[String(type).toLowerCase()]) continue
    tunnel = {
      active: true,
      name: name,
      server: name.replace(/^ProtonVPN[\s:]+/i, "").trim(),
      device: device,
      type: type,
      sinceMs: since > 0 ? since * 1000 : 0
    }
  }
  var result = tunnel || { active: false, name: "", server: "", device: "", type: "", sinceMs: 0 }
  result.killSwitch = killSwitch
  return result
}

function killSwitchBlocking(link, state) {
  if (!link || link.known !== true || link.available !== true) return false
  if (link.active === true || link.killSwitch !== true) return false
  return KILL_SWITCH_BLOCKING_STATES.indexOf(String(state || "")) !== -1
}

function killSwitchBlockingText(loc) {
  return say(loc, "killSwitch.blocking", "The VPN dropped and Kill Switch is blocking internet traffic, so nothing leaks. Connect again to restore access, or set Kill Switch to Off.")
}

function parseConnectOutcome(raw) {
  var lines = normalizeOutput(raw).split("\n")
  var result = { server: "", location: "", exitIp: "", portForwarding: "" }
  for (var i = 0; i < lines.length; i++) {
    var line = String(lines[i] || "").trim()
    var connected = line.match(/^Connected to\s+(.+?)\s+in\s+(.+?)\.?\s*$/i)
    if (connected) {
      result.server = String(connected[1] || "").trim()
      result.location = String(connected[2] || "").trim().replace(/\.$/, "")
    }
    var ip = line.match(/^Your new IP address is\s+(.+?)\.?\s*$/i)
    if (ip) {
      var candidate = String(ip[1] || "").trim().replace(/\.$/, "")
      if (isIPv4(candidate) || isIPv6(candidate)) result.exitIp = candidate
    }
    if (/^Port forwarding is active on this server/i.test(line)) result.portForwarding = "active"
    else if (/Port forwarding is enabled but this server does not support it/i.test(line)) result.portForwarding = "unsupported"
  }
  return result
}

function portForwardingNotice(kind, loc) {
  if (kind === "active") return say(loc, "portForwarding.active", "Port forwarding is active on this server. The Proton CLI does not show the forwarded port; Proton's Linux guide reads it with natpmpc.")
  if (kind === "unsupported") return say(loc, "portForwarding.unsupported", "Port forwarding is on, but this server does not support it. Connect in P2P mode to use it.")
  return ""
}

function recentTarget(options, outcome, loc) {
  var source = options || {}
  var connected = outcome || {}
  var mode = String(source.mode || "fastest")
  var target = {
    mode: mode,
    country: String(source.country || ""),
    city: String(source.city || ""),
    serverId: String(source.serverId || ""),
    label: "",
    detail: connected.server ? String(connected.server) + (connected.location ? " · " + connected.location : "") : ""
  }
  if (mode === "city") target.label = target.city
  else if (mode === "country") target.label = target.country
  else if (mode === "server") target.label = target.serverId
  else {
    target.label = modeLabel(mode, loc)
    if (target.country !== "") target.label += " · " + target.country
  }
  return target
}

function recordRecentTarget(list, target, max) {
  if (!target || String(target.label || "") === "") return (list || []).slice()
  var key = [target.mode, target.country, target.city, target.serverId].join("\n")
  var result = [target]
  var source = list || []
  for (var i = 0; i < source.length; i++) {
    var item = source[i]
    var itemKey = [item.mode, item.country, item.city, item.serverId].join("\n")
    if (itemKey !== key) result.push(item)
  }
  return result.slice(0, typeof max === "number" && max > 0 ? max : 3)
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
  if (value === "") return String(fallback || "")
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

function incompatibleStatusText(loc) {
  return say(loc, "status.incompatible", "Proton VPN status output is incompatible with this plugin.")
}

function parseStatus(raw, loc) {
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
    return { ok: false, kind: "parse", message: incompatibleStatusText(loc) }
  }

  if (/^Status:\s*Disconnected\s*$/i.test(statusLine)) {
    return { ok: true, state: STATES.disconnected, status: emptyStatus() }
  }

  if (!/^Status:\s*Connected\s*$/i.test(statusLine)) {
    return { ok: false, kind: "parse", message: say(loc, "status.unknownLine", "Proton VPN reported an unknown status line.") }
  }

  var server = parseServerLine(serverLine)
  if (!server || server.server === "" || server.location === "") {
    return { ok: false, kind: "parse", message: say(loc, "status.partial", "Connected status is missing a server or location line.") }
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
    protocol: String(prior.status.protocol || ""),
    exitIp: String(prior.status.exitIp || "")
  }
}

function hasValidStatus(prior) {
  if (!prior) return false
  return prior.state === STATES.connected
    || prior.state === STATES.disconnected
    || prior.state === STATES.stale
}

var CRASH_AFTER_OUTPUT_EXIT = 139
var RUNNER_MARKER = /omarchy-protonvpn: command (timed out|output exceeded)/

// SIGSEGV after the CLI prints; trust only if the caller can parse.
function crashedAfterOutput(result) {
  if (!result || result.timedOut === true || result.exitCode !== CRASH_AFTER_OUTPUT_EXIT) return false
  return !RUNNER_MARKER.test(String(result.stderr || ""))
}

function readSucceeded(result) {
  if (!result || result.timedOut === true) return false
  return result.exitCode === 0 || crashedAfterOutput(result)
}

function classifyProbe(result, prior, loc) {
  var previous = prior || defaultView()
  var stdout = result && result.stdout !== undefined ? result.stdout : ""
  var stderr = result && result.stderr !== undefined ? result.stderr : ""
  var combined = combineOutput(stdout, stderr)
  var timedOut = result && result.timedOut === true
  var exitCode = result && typeof result.exitCode === "number" ? result.exitCode : 1

  if (result && result.cliMissing === true) {
    return viewFor(STATES.cliMissing, "cli", cliMissingText(loc), combined, previous, false)
  }

  if (hasGuiConflict(combined)) {
    return viewFor(STATES.guiConflict, "gui", guiConflictText(loc), combined, previous, false)
  }

  if (hasAuthRequired(combined)) {
    return viewFor(STATES.signedOut, "auth", signInText(loc), combined, previous, false)
  }

  var parsed = parseStatus(stdout, loc)
  if (crashedAfterOutput(result) && parsed.ok) exitCode = 0
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
      return staleView(previous, "parse", parsed.message || incompatibleStatusText(loc), combined)
    }
    return viewFor(STATES.error, "parse", parsed.message || incompatibleStatusText(loc), combined, previous, false)
  }

  var failureKind = classifyFailureKind(combined, timedOut)
  var message = failureMessage(failureKind, combined, loc)
  if (hasValidStatus(previous)) {
    return staleView(previous, failureKind, message, combined)
  }

  return viewFor(STATES.error, failureKind, message, combined, previous, false)
}

function cliMissingText(loc) {
  return say(loc, "state.cliMissing", "Proton VPN CLI not installed.")
}

function guiConflictText(loc) {
  return say(loc, "state.guiConflict", "Close the Proton VPN desktop app to use the CLI.")
}

function signInText(loc) {
  return say(loc, "state.signedOut", "Sign in to Proton VPN from a terminal.")
}

// CLI output stays as Proton wrote it; only the plugin's own fallbacks change.
// After `protonvpn signout` the CLI answers as signed out.
function signedOutView(loc) {
  return viewFor(STATES.signedOut, "auth", signInText(loc), "", null, false)
}

function failureMessage(kind, combined, loc) {
  if (kind === "timeout") return say(loc, "failure.timeout", "Proton VPN did not respond in time.")
  if (kind === "connectionTimeout") return say(loc, "failure.connectionTimeout", "Proton VPN timed out while connecting. The CLI reached a server but the handshake did not finish.")
  if (kind === "keyring") return say(loc, "failure.keyring", "Proton VPN could not read saved credentials from the system keyring.")
  if (kind === "daemon") return say(loc, "failure.daemon", "The Proton VPN daemon did not respond.")
  if (kind === "network") return say(loc, "failure.network", "Proton VPN could not reach the network.")
  if (kind === "parse") return incompatibleStatusText(loc)
  if (kind === "plan") return sanitizeMessage(combined, say(loc, "failure.plan", "This option is not available on the current plan."))
  if (kind === "prerequisite") return sanitizeMessage(combined, say(loc, "failure.prerequisite", "Disconnect before changing this setting."))
  if (kind === "empty") return sanitizeMessage(combined, say(loc, "failure.empty", "No matching Proton VPN servers were found."))
  if (kind === "invalid") return sanitizeMessage(combined, say(loc, "failure.invalid", "Proton VPN rejected that value."))
  if (kind === "action") return sanitizeMessage(combined, say(loc, "failure.action", "The Proton VPN command failed."))
  return sanitizeMessage(combined, say(loc, "failure.generic", "Proton VPN command failed."))
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

function classifyCommandResult(result, prior, loc) {
  var previous = prior || defaultView()
  var combined = combineOutput(result && result.stdout, result && result.stderr)
  if (result && result.cliMissing === true) {
    return {
      ok: false,
      kind: "cli",
      message: cliMissingText(loc),
      detail: capOutput(combined),
      stateHint: STATES.cliMissing
    }
  }
  if (hasGuiConflict(combined)) {
    return {
      ok: false,
      kind: "gui",
      message: guiConflictText(loc),
      detail: capOutput(combined),
      stateHint: STATES.guiConflict
    }
  }
  if (hasAuthRequired(combined)) {
    return {
      ok: false,
      kind: "auth",
      message: signInText(loc),
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
    message: failureMessage(kind, combined, loc),
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

function writeBlockedReason(state, loc) {
  if (canWrite(state)) return ""
  if (state === STATES.checking) return say(loc, "blocked.checking", "Wait for Proton VPN status before making changes.")
  if (state === STATES.stale) return say(loc, "blocked.stale", "Refresh Proton VPN status before making changes. The last result may be outdated.")
  if (state === STATES.connecting || state === STATES.disconnecting) return say(loc, "blocked.busy", "Wait for the current Proton VPN action to finish.")
  if (state === STATES.cliMissing) return say(loc, "blocked.cliMissing", "Install the Proton VPN CLI before making changes.")
  if (state === STATES.signedOut) return say(loc, "blocked.signedOut", "Sign in to Proton VPN from a terminal before making changes.")
  if (state === STATES.guiConflict) return say(loc, "blocked.guiConflict", "Close the Proton VPN desktop app before making changes.")
  return say(loc, "blocked.other", "Proton VPN is not ready for changes.")
}

function isVpnActive(view) {
  if (!view) return false
  if (view.state === STATES.connected || view.state === STATES.connecting) return true
  if (view.connectedSnapshot === true && (view.state === STATES.stale || view.state === STATES.error)) return true
  return false
}

// A live NetworkManager tunnel only proves the tunnel exists. It must not hide
// a CLI verdict that the tunnel cannot explain: the desktop app uses the same
// proton0 device, and sign-in or CLI errors still block writes.
var LINK_CLAIMABLE_STATES = [STATES.checking, STATES.disconnected, STATES.connected, STATES.stale]

function linkMayClaimConnected(state) {
  return LINK_CLAIMABLE_STATES.indexOf(String(state || "")) !== -1
}

// Only a successful, current nmcli result may override a CLI "Disconnected".
function linkConfirmsTunnel(link) {
  return !!link && link.known === true && link.available === true && link.active === true
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

function parseTwoColumnTable(raw, leftHeader, rightHeader, loc) {
  var lines = normalizeOutput(raw).split("\n")
  var header = findTableHeader(lines, leftHeader, rightHeader)
  if (!header) return { ok: false, rows: [], message: say(loc, "table.incompatible", "Proton VPN table output is incompatible with this plugin.") }
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

function parseCountries(raw, loc) {
  var parsed = parseTwoColumnTable(raw, "Country", "Code", loc)
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

function parseCities(raw, loc) {
  var parsed = parseTwoColumnTable(raw, "City", "Features", loc)
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

function parseConfigList(raw, loc) {
  var parsed = parseTwoColumnTable(raw, "Setting", "Value", loc)
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
    return { ok: false, settings: {}, upgrade: {}, message: say(loc, "config.incompatible", "Proton VPN configuration output is incompatible with this plugin.") }
  }
  return { ok: true, settings: settings, upgrade: upgrade, message: "" }
}

// Every setting this plugin knows is listed; used when the CLI crashed on exit.
function configListComplete(parsed) {
  if (!parsed || parsed.ok !== true || !parsed.settings) return false
  for (var i = 0; i < CONFIG_SETTINGS.length; i++) {
    if (parsed.settings[CONFIG_SETTINGS[i].key] === undefined) return false
  }
  return true
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

// `protonvpn info` does not report the plan, but `config list` marks paid-only
// settings "Upgrade to enable" only on the free plan.
function isFreePlan(upgrade) {
  if (!upgrade) return false
  for (var key in upgrade) {
    if (upgrade[key] === true) return true
  }
  return false
}

// The free plan accepts only `protonvpn connect`: the CLI refuses locations,
// server IDs, feature servers, and random selection.
var FREE_PLAN_MODES = ["fastest"]

function modeAvailable(mode, freePlan) {
  return freePlan !== true || FREE_PLAN_MODES.indexOf(String(mode || "fastest")) !== -1
}

function modeLabel(value, loc) {
  var def = modeDef(value) || CONNECTION_MODES[0]
  return tableText(loc, "mode", def.value, "label", def.label)
}

function modeOptions(freePlan, loc) {
  var options = []
  for (var i = 0; i < CONNECTION_MODES.length; i++) {
    var def = CONNECTION_MODES[i]
    options.push({
      value: def.value,
      label: tableText(loc, "mode", def.value, "label", def.label),
      description: modeAvailable(def.value, freePlan)
        ? tableText(loc, "mode", def.value, "description", def.description)
        : say(loc, "mode.paidOnly", "Needs a paid plan")
    })
  }
  return options
}

function planBlockedReason(mode, freePlan, loc) {
  if (modeAvailable(mode, freePlan)) return ""
  return fill(say(loc, "mode.paidBlocked", "%1 needs a paid Proton VPN plan. Fastest server works on the free plan."), modeLabel(mode, loc))
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

function settingTooltip(key, loc) {
  return tableText(loc, "setting", key, "tooltip", tooltipFor(settingDef(key)))
}

function modeTooltip(value, loc) {
  return tableText(loc, "mode", value, "tooltip", tooltipFor(modeDef(value)))
}

function connectFieldTooltip(key, loc) {
  return tableText(loc, "field", key, "tooltip", tooltipFor(connectFieldDef(key)))
}

function settingLabel(key, loc) {
  var def = settingDef(key)
  return def ? tableText(loc, "setting", key, "label", def.label) : String(key || "")
}

// The name in a half-width switch cell.
function settingShortLabel(key, loc) {
  var def = settingDef(key)
  return def && def.shortLabel ? tableText(loc, "setting", key, "shortLabel", def.shortLabel) : settingLabel(key, loc)
}

// Dropdown options for a choice setting, in the order Proton lists them.
function settingChoiceOptions(key, loc) {
  var def = settingDef(key)
  var options = []
  if (!def || !def.values) return options
  for (var i = 0; i < def.values.length; i++) {
    var value = def.values[i]
    var option = { value: value, label: configValueLabel(key, value, loc) }
    if (def.valueDescriptions && def.valueDescriptions[value]) {
      option.description = tableText(loc, "setting", key, "valueDescription." + value, def.valueDescriptions[value])
    }
    options.push(option)
  }
  return options
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

function validateDnsList(text, loc) {
  var ips = parseDnsList(text)
  if (ips.length === 0) return { ok: false, message: say(loc, "dns.empty", "Enter at least one DNS server IP."), ips: [] }
  for (var i = 0; i < ips.length; i++) {
    if (!isIPv4(ips[i]) && !isIPv6(ips[i])) {
      return { ok: false, message: fill(say(loc, "dns.invalid", "Invalid DNS address '%1'. Use IPv4 or IPv6."), ips[i]), ips: [] }
    }
  }
  return { ok: true, message: "", ips: ips }
}

function validateServerId(value, loc) {
  var text = String(value || "").trim()
  if (text === "") return { ok: false, message: say(loc, "server.empty", "Enter a Proton VPN server ID such as IT#23.") }
  if (!/^[A-Za-z]{2,3}(?:-[A-Za-z]{2,3})?#\d+$/.test(text)) {
    return { ok: false, message: say(loc, "server.invalid", "Server IDs look like IT#23 or CH-IS#1. Proton lists them in the account server list.") }
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

function connectDraft(draft) {
  var current = draft || {}
  return {
    country: String(current.country || "").trim(),
    city: String(current.city || "").trim(),
    serverId: String(current.serverId || "").trim()
  }
}

function connectDraftForModeChange(prevMode, nextMode, draft) {
  var prev = String(prevMode || "")
  var next = String(nextMode || "fastest")
  var current = connectDraft(draft)
  if (!modeNeedsCountry(prev) || !modeNeedsCountry(next)) current.country = ""
  current.city = ""
  if (prev !== "server" || next !== "server") current.serverId = ""
  return current
}

function connectDraftForCountryChange(draft) {
  var current = connectDraft(draft)
  current.city = ""
  return current
}

function connectFieldTriggerLabel(field, context, loc) {
  var ctx = context || {}
  var country = String(ctx.country || "").trim()
  if (field === "country") return modeRequiresCountry(ctx.mode) ? say(loc, "field.chooseCountry", "Choose a country") : say(loc, "field.anyCountry", "Any country")
  if (field === "city") {
    if (country === "") return say(loc, "field.countryFirst", "Choose a country first")
    return ctx.loading === true ? say(loc, "field.loadingCities", "Loading cities…") : say(loc, "field.chooseCity", "Choose a city")
  }
  return ""
}

// Two connection choices are the same target exactly when they build the same
// CLI command, so fields a mode ignores never count as a change.
function connectTargetKey(options) {
  var plan = buildConnectCommand(options)
  return plan.ok ? plan.command.join("\n") : ""
}

function shouldOfferSwitch(ctx) {
  if (!ctx || ctx.state !== STATES.connected || ctx.busy === true) return false
  // Only after the user edits CONNECT: a recreated panel or a Quick connect reconnect
  // leaves an untouched draft that differs from the connection.
  if (ctx.draftDirty !== true) return false
  var draftKey = connectTargetKey(ctx.draft)
  if (draftKey === "") return false
  // Connected before the shell started: the current target is unknown.
  if (!ctx.activeTarget) return true
  return connectTargetKey(ctx.activeTarget) !== draftKey
}

// Favorites and remembered recents live in the widget's shell.json entry,
// which the user can edit, so read them back as untrusted: only the four
// connection fields, short strings, and targets the CLI would accept.
var MAX_FAVORITES = 8
var MAX_RECENTS = 3
var TARGET_FIELD_MAX = 64

function cleanTarget(raw) {
  if (!raw || typeof raw !== "object") return null
  var target = { mode: "fastest", country: "", city: "", serverId: "" }
  var fields = ["mode", "country", "city", "serverId"]
  for (var i = 0; i < fields.length; i++) {
    var value = raw[fields[i]]
    if (value === undefined || value === null) continue
    if (typeof value !== "string" || value.length > TARGET_FIELD_MAX) return null
    target[fields[i]] = value.trim()
  }
  if (!modeDef(target.mode) || !buildConnectCommand(target).ok) return null
  return target
}

function normalizeTargets(list, max) {
  var out = []
  var seen = {}
  var source = Array.isArray(list) ? list : []
  for (var i = 0; i < source.length && out.length < max; i++) {
    var target = cleanTarget(source[i])
    if (!target) continue
    var key = connectTargetKey(target)
    if (seen[key]) continue
    seen[key] = true
    out.push(target)
  }
  return out
}

function isFavorite(favorites, target) {
  var key = target ? connectTargetKey(target) : ""
  if (key === "") return false
  for (var i = 0; i < (favorites || []).length; i++) {
    if (connectTargetKey(favorites[i]) === key) return true
  }
  return false
}

// Starring adds to the end; starring again removes it.
function toggleFavorite(favorites, target) {
  var clean = cleanTarget(target)
  var list = normalizeTargets(favorites, MAX_FAVORITES)
  if (!clean) return list
  var key = connectTargetKey(clean)
  var kept = list.filter(function(item) { return connectTargetKey(item) !== key })
  if (kept.length !== list.length) return kept
  return list.length < MAX_FAVORITES ? list.concat([clean]) : list
}

function countryName(code, countries) {
  var value = String(code || "").trim()
  var list = countries || []
  for (var i = 0; i < list.length; i++) {
    if (String(list[i].code || "").toUpperCase() === value.toUpperCase()) return String(list[i].name || value)
  }
  return value
}

// "Netherlands", "Zurich · Switzerland", "P2P · Iceland", "CH#242".
function targetName(target, countries, loc) {
  var t = target || {}
  var mode = String(t.mode || "fastest")
  var country = countryName(t.country, countries)
  if (mode === "country") return country
  if (mode === "city") return String(t.city || "") === "" ? country : (country !== "" ? t.city + " · " + country : String(t.city))
  if (mode === "server") return String(t.serverId || "")
  return modeLabel(mode, loc) + (country !== "" ? " · " + country : "")
}

// Favorites first, the current connection marked; then recents that are
// neither. Each row says what it is so the panel can draw and act on it.
function quickConnectRows(favorites, recents, activeTarget) {
  var activeKey = activeTarget ? connectTargetKey(activeTarget) : ""
  var rows = []
  var seen = {}
  var favs = favorites || []
  for (var i = 0; i < favs.length; i++) {
    var key = connectTargetKey(favs[i])
    if (key === "" || seen[key]) continue
    seen[key] = true
    rows.push({ target: favs[i], favorite: true, active: key === activeKey })
  }
  if (activeKey !== "" && !seen[activeKey]) {
    seen[activeKey] = true
    rows.unshift({ target: activeTarget, favorite: false, active: true })
  }
  var recent = recents || []
  for (var j = 0; j < recent.length; j++) {
    var rkey = connectTargetKey(recent[j])
    if (rkey === "" || seen[rkey]) continue
    seen[rkey] = true
    rows.push({ target: recent[j], favorite: false, active: false })
  }
  return rows
}

// Trusted Wi-Fi names, from shell.json: SSIDs are 1 to 32 bytes.
var MAX_TRUSTED_NETWORKS = 32

function normalizeNetworks(list) {
  var out = []
  var source = Array.isArray(list) ? list : []
  for (var i = 0; i < source.length && out.length < MAX_TRUSTED_NETWORKS; i++) {
    var name = source[i]
    if (typeof name !== "string" || name.length === 0 || name.length > 32 || out.indexOf(name) !== -1) continue
    out.push(name)
  }
  return out
}

function isTrustedNetwork(list, name) {
  return String(name || "") !== "" && normalizeNetworks(list).indexOf(String(name)) !== -1
}

function toggleNetwork(list, name) {
  var clean = normalizeNetworks(list)
  var value = String(name || "")
  if (value === "" || value.length > 32) return clean
  if (clean.indexOf(value) !== -1) return clean.filter(function(item) { return item !== value })
  return clean.length < MAX_TRUSTED_NETWORKS ? clean.concat([value]) : clean
}

// `connectTo` over IPC: "NL", "CH#242", "US New York", "p2p", "p2p NL",
// "securecore IS", "tor", "random", or "fastest". Returns a target the CLI
// accepts, or null.
function parseTargetSpec(spec) {
  var text = String(spec || "").trim().replace(/\s+/g, " ")
  if (text === "" || text.length > 80) return null
  var words = text.split(" ")
  var head = words[0].toLowerCase()
  var target = null
  if (["fastest", "random", "p2p", "securecore", "tor"].indexOf(head) !== -1) {
    if (words.length > 2 || ((head === "fastest" || head === "random") && words.length > 1)) return null
    target = { mode: head, country: words.length === 2 ? words[1].toUpperCase() : "" }
    if (target.country !== "" && !/^[A-Z]{2}$/.test(target.country)) return null
  } else if (/#/.test(text)) {
    target = { mode: "server", serverId: text.toUpperCase() }
  } else if (/^[A-Za-z]{2}$/.test(words[0])) {
    target = words.length === 1
      ? { mode: "country", country: words[0].toUpperCase() }
      : { mode: "city", country: words[0].toUpperCase(), city: words.slice(1).join(" ") }
  }
  return cleanTarget(target)
}

// What `statusJson` prints over IPC. Only what the panel already shows.
function statusJson(view, extra) {
  var v = view || defaultView()
  var x = extra || {}
  var status = v.status || emptyStatus()
  var connected = v.state === STATES.connected
  return JSON.stringify({
    state: String(v.state || ""),
    connected: connected,
    server: connected ? String(status.server || "") : "",
    location: connected ? String(status.location || "") : "",
    load: connected && status.load !== null && status.load !== undefined ? Number(status.load) : null,
    protocol: connected ? protocolName(status.protocol) : "",
    exitIp: connected ? String(status.exitIp || "") : "",
    connectedSince: connected && Number(x.sinceMs) > 0 ? new Date(Number(x.sinceMs)).toISOString() : null,
    killSwitch: String((x.config || {})["kill-switch"] || ""),
    netshield: String((x.config || {}).netshield || ""),
    killSwitchBlocking: v.blocking === true,
    stalled: v.stalled === true,
    routing: connected && x.routing ? { ipv4: x.routing.ipv4, ipv6: x.routing.ipv6, dns: x.routing.dns } : null,
    leaks: connected ? routingLeakLines(x.routing, null) : [],
    message: String(v.message || "")
  })
}

function switchLabel(options, loc) {
  return fill(say(loc, "connect.switchTo", "Switch to %1"), recentTarget(options, null, loc).label)
}

function buildConnectCommand(options, loc) {
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
      return { ok: false, message: say(loc, "connect.serverFilters", "A specific server ID cannot be combined with other connection filters.") }
    }
    var server = validateServerId(serverId, loc)
    if (!server.ok) return server
    return { ok: true, command: command.concat([server.value]) }
  }

  if (mode === "country") {
    if (country === "") return { ok: false, message: say(loc, "connect.needCountry", "Choose a country before connecting.") }
    return { ok: true, command: command.concat(["--country", country]) }
  }

  if (mode === "city") {
    if (country === "") return { ok: false, message: say(loc, "connect.needCountryForCity", "Choose a country before listing cities.") }
    if (city === "") return { ok: false, message: say(loc, "connect.needCity", "Choose a city before connecting.") }
    return { ok: true, command: command.concat(["--country", country, "--city", city]) }
  }

  if (mode === "p2p" || mode === "securecore" || mode === "tor") {
    if (country !== "") command = command.concat(["--country", country])
    if (mode === "p2p") command = command.concat(["--p2p"])
    else if (mode === "securecore") command = command.concat(["--securecore"])
    else command = command.concat(["--tor"])
    return { ok: true, command: command }
  }

  return { ok: false, message: say(loc, "connect.unknownMode", "Unknown connection mode.") }
}

function buildConfigSetCommand(setting, value, context, loc) {
  var def = settingDef(setting)
  if (!def) return { ok: false, message: say(loc, "config.unknown", "Unknown Proton VPN setting.") }
  var ctx = context || {}
  var next = String(value || "").trim()
  if (def.disconnectFirst && ctx.connected === true) {
    return { ok: false, message: say(loc, "config.disconnectFirst", "Disconnect before changing Kill Switch."), kind: "prerequisite" }
  }
  if (def.values && def.values.indexOf(next) === -1) {
    return { ok: false, message: fill(say(loc, "config.invalidValue", "Invalid value '%1' for %2."), next, settingLabel(setting, loc)) }
  }
  if (def.type === "dns") {
    if (next === "off") return { ok: true, command: ["protonvpn", "config", "set", "custom-dns", "off"], restart: def.restart === true }
    var dns = validateDnsList(ctx.dns || "", loc)
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

// The CLI prints protocols in lowercase ("wireguard", "openvpn-udp").
var PROTOCOL_NAMES = { wireguard: "WireGuard", "openvpn-udp": "OpenVPN UDP", "openvpn-tcp": "OpenVPN TCP", openvpn: "OpenVPN", stealth: "Stealth" }

function protocolName(value) {
  var raw = String(value || "").trim()
  return PROTOCOL_NAMES[raw.toLowerCase()] || raw
}

function displayLoad(load, loc) {
  if (load === null || load === undefined || !isFinite(Number(load))) return say(loc, "status.loadUnknown", "Unknown")
  return num(loc, Math.round(Number(load))) + "%"
}

function connectedSummary(status, loc) {
  var item = status || emptyStatus()
  var parts = []
  if (item.server) parts.push(item.server)
  if (item.location) parts.push(item.location)
  if (item.load !== null && item.load !== undefined && isFinite(Number(item.load))) parts.push(fill(say(loc, "status.loadSummary", "Load %1"), displayLoad(item.load, loc)))
  if (item.protocol) parts.push(protocolName(item.protocol))
  return parts.join(" · ")
}

function tooltipText(view, loc) {
  var state = view && view.state ? view.state : STATES.checking
  if (view && view.blocking === true) return say(loc, "tooltip.blocking", "Proton VPN disconnected. Kill Switch is blocking internet traffic.")
  if (state === STATES.connected) {
    var summary = connectedSummary(view.status, loc)
    var line = summary !== "" ? "Proton VPN · " + summary : say(loc, "tooltip.connected", "Proton VPN connected.")
    if (view.stalled === true) line += "\n" + say(loc, "tooltip.stalled", "Nothing is coming back through the tunnel.")
    if (view.leaking === true) line += "\n" + say(loc, "tooltip.leaking", "Some traffic or DNS goes outside the tunnel.")
    return line
  }
  if (state === STATES.disconnected) return say(loc, "tooltip.disconnected", "Proton VPN disconnected.")
  if (state === STATES.connecting) return say(loc, "tooltip.connecting", "Connecting to Proton VPN…")
  if (state === STATES.disconnecting) return say(loc, "tooltip.disconnecting", "Disconnecting Proton VPN…")
  if (state === STATES.checking) return say(loc, "tooltip.checking", "Checking Proton VPN status…")
  if (state === STATES.cliMissing) return cliMissingText(loc)
  if (state === STATES.signedOut) return signInText(loc)
  if (state === STATES.guiConflict) return guiConflictText(loc)
  if (state === STATES.stale) {
    var staleSummary = connectedSummary(view.status, loc)
    var prefix = staleSummary !== "" ? staleSummary + " · " : ""
    return prefix + (view.message || say(loc, "tooltip.stale", "Proton VPN status may be outdated."))
  }
  return view && view.message ? view.message : say(loc, "tooltip.error", "Proton VPN error.")
}

// What protects the connection, from values the plugin already has: the
// CLI's settings and the server name. Facts only, never a score. Label and
// value pairs, in the same style as the status line above them.
function protectionPairs(configValues, view, loc) {
  var values = configValues || {}
  // Until the settings load, say nothing rather than half the story.
  if (values["kill-switch"] === undefined && values.netshield === undefined) return []
  var on = say(loc, "value.on", "On")
  var off = say(loc, "value.off", "Off")
  var pairs = []
  if (values["kill-switch"] !== undefined) {
    pairs.push({ label: settingLabel("kill-switch", loc), value: values["kill-switch"] === "off" ? off : on })
  }
  if (values.netshield !== undefined && values.netshield !== "") {
    // Custom DNS sends queries past Proton, so NetShield cannot filter them.
    var bypassed = values.netshield !== "off" && parseCustomDnsValue(values["custom-dns"]).enabled
    pairs.push({
      label: settingLabel("netshield", loc),
      value: bypassed ? say(loc, "protect.netShieldBypassed", "Off (custom DNS)") : configValueLabel("netshield", values.netshield, loc)
    })
  }
  var server = view && view.state === STATES.connected && view.status ? String(view.status.server || "") : ""
  if (/^[A-Za-z]{2,3}-[A-Za-z]{2,3}#\d+$/.test(server)) pairs.push({ label: modeLabel("securecore", loc), value: on })
  return pairs
}

// Live rates and the session total, once two samples exist.
function trafficPairs(traffic, loc) {
  if (!traffic || traffic.known !== true) return []
  return [
    { label: say(loc, "traffic.down", "Down"), value: formatRate(traffic.rxRate, loc) },
    { label: say(loc, "traffic.up", "Up"), value: formatRate(traffic.txRate, loc) },
    { label: say(loc, "traffic.session", "Session"), value: formatBytes(traffic.sessionRx + traffic.sessionTx, loc) }
  ]
}

// The button under CONNECT: "Connect to Netherlands" while disconnected,
// "Switch to Zurich · Switzerland" while connected.
function connectButtonLabel(state, options, countries, loc) {
  // Until the choices name a place the CLI accepts, say only what it does.
  if (!buildConnectCommand(options).ok) {
    return state === STATES.connected ? say(loc, "connect.switch", "Switch") : say(loc, "connect.connect", "Connect")
  }
  var name = targetName(options, countries, loc)
  return state === STATES.connected
    ? fill(say(loc, "connect.switchTo", "Switch to %1"), name)
    : fill(say(loc, "connect.connectTo", "Connect to %1"), name)
}

// Text beside the bar icon while connected: "NL", "NL#806", or "Amsterdam".
// Server IDs start with the exit country ("IS-CH#1" exits in Iceland).
var BAR_LABELS = ["none", "country", "server", "city"]

function normalizeBarLabel(value) {
  var v = String(value === undefined || value === null ? "" : value)
  return BAR_LABELS.indexOf(v) !== -1 ? v : "none"
}

function barLabelText(setting, view) {
  var mode = normalizeBarLabel(setting)
  if (mode === "none" || !view || view.state !== STATES.connected || !view.status) return ""
  var server = String(view.status.server || "")
  var text = ""
  if (mode === "server") text = server
  else if (mode === "country") text = (server.match(/^([A-Za-z]{2,3})[-#]/) || ["", ""])[1].toUpperCase()
  else text = String(view.status.location || "").split(",")[0].trim()
  return capOutput(text, 16)
}

function heroTitle(view) {
  var state = view && view.state ? view.state : STATES.checking
  if (state === STATES.connected && view.status && view.status.server) return view.status.server
  return "Proton VPN"
}

function heroMeta(view, loc) {
  var state = view && view.state ? view.state : STATES.checking
  if (view && view.blocking === true) return say(loc, "hero.blocking", "Kill Switch is blocking traffic")
  if (state === STATES.connected) return view.status && view.status.location ? view.status.location : say(loc, "hero.connected", "Connected")
  if (state === STATES.disconnected) return say(loc, "hero.disconnected", "Disconnected")
  if (state === STATES.connecting) return say(loc, "hero.connecting", "Connecting")
  if (state === STATES.disconnecting) return say(loc, "hero.disconnecting", "Disconnecting")
  if (state === STATES.checking) return say(loc, "hero.checking", "Checking status")
  if (state === STATES.cliMissing) return say(loc, "hero.cliMissing", "CLI not installed")
  if (state === STATES.signedOut) return say(loc, "hero.signedOut", "Sign-in required")
  if (state === STATES.guiConflict) return say(loc, "hero.guiConflict", "Desktop app is running")
  if (state === STATES.stale) return say(loc, "hero.stale", "Status may be outdated")
  return say(loc, "hero.error", "Needs attention")
}

function heroDetail(view, loc) {
  var state = view && view.state ? view.state : ""
  if (state === STATES.connected && view.status && view.status.protocol) return protocolName(view.status.protocol)
  if (state === STATES.stale) return say(loc, "hero.staleBadge", "Stale")
  return ""
}

function relativeTime(fromMs, nowMs, loc) {
  var then = Number(fromMs || 0)
  var now = nowMs === undefined ? Date.now() : Number(nowMs)
  if (!isFinite(then) || then <= 0) return ""
  var diff = Math.max(0, Math.floor((now - then) / 1000))
  if (diff < 5) return say(loc, "age.now", "just now")
  if (diff < 60) return fill(say(loc, "age.seconds", "%1s ago"), num(loc, diff))
  var minutes = Math.floor(diff / 60)
  if (minutes < 60) return fill(say(loc, "age.minutes", "%1m ago"), num(loc, minutes))
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return fill(say(loc, "age.hours", "%1h ago"), num(loc, hours))
  return fill(say(loc, "age.days", "%1d ago"), num(loc, Math.floor(hours / 24)))
}

// How long the tunnel has been up: "42s", "12m", "1h 12m", "3d 4h".
function durationText(sinceMs, nowMs, loc) {
  var since = Number(sinceMs || 0)
  if (!isFinite(since) || since <= 0) return ""
  var s = Math.max(0, Math.floor((Number(nowMs) - since) / 1000))
  if (s < 60) return fill(say(loc, "duration.seconds", "%1s"), num(loc, s))
  var m = Math.floor(s / 60)
  if (m < 60) return fill(say(loc, "duration.minutes", "%1m"), num(loc, m))
  var h = Math.floor(m / 60)
  if (h < 24) return fill(say(loc, "duration.hours", "%1h %2m"), num(loc, h), num(loc, m % 60))
  return fill(say(loc, "duration.days", "%1d %2h"), num(loc, Math.floor(h / 24)), num(loc, h % 24))
}

function lastUpdatedText(view, nowMs, loc) {
  var when = relativeTime(view && view.lastUpdatedMs, nowMs, loc)
  if (when === "") return ""
  if (view && view.state === STATES.stale) return fill(say(loc, "status.lastSuccess", "Last successful update %1"), when)
  return when
}

function degradedExplanation(state, loc) {
  if (state === STATES.cliMissing) {
    return say(loc, "degraded.cliMissing", "The official Proton VPN CLI is not installed or is not on PATH.")
  }
  if (state === STATES.signedOut) {
    return say(loc, "degraded.signedOut", "The CLI is installed but this session is signed out. Sign in from a terminal; this plugin never asks for a password or 2FA code.")
  }
  if (state === STATES.guiConflict) {
    return say(loc, "degraded.guiConflict", "Proton VPN's desktop app is running. The official CLI refuses to operate until that app is closed.")
  }
  if (state === STATES.error) {
    return say(loc, "degraded.error", "Proton VPN could not complete the last command. This can be a plugin, CLI, daemon, or keyring problem.")
  }
  if (state === STATES.stale) {
    return say(loc, "degraded.stale", "The last status probe failed. The previous result is still shown and may be outdated. Connection and settings changes stay disabled until a fresh probe succeeds.")
  }
  return ""
}

function kindRemediation(kind, loc) {
  if (kind === "keyring") {
    return say(loc, "fix.keyring", "Unlock or restart the system keyring (Secret Service), then refresh. This is a local session problem, not a widget parser bug.")
  }
  if (kind === "daemon") {
    return say(loc, "fix.daemon", "Check that proton-vpn-daemon is running, then refresh. This is a Proton CLI/service problem.")
  }
  if (kind === "connectionTimeout") {
    return say(loc, "fix.connectionTimeout", "The CLI reached Proton but the connection handshake timed out. Retry, or check the network. This is not a widget command-queue failure.")
  }
  if (kind === "timeout") {
    return say(loc, "fix.timeout", "The Proton VPN command did not finish in time. Refresh after the CLI or daemon responds again.")
  }
  if (kind === "network") {
    return say(loc, "fix.network", "Check local network connectivity, then refresh. A failed probe is not treated as disconnected.")
  }
  return ""
}

function degradedRemediation(viewOrState, loc) {
  var view = typeof viewOrState === "string" ? { state: viewOrState } : (viewOrState || {})
  var state = view.state
  var fromKind = kindRemediation(view.kind, loc)
  if (fromKind !== "") return fromKind
  if (state === STATES.cliMissing) {
    return fill(say(loc, "fix.cliMissing", "Choose Install Proton VPN CLI. Omarchy installs the %1 package from Arch extra in a terminal, which asks for your password there. Proton's upstream Linux support list does not currently include Arch, so updates and support may be limited."), CLI_PACKAGE)
  }
  if (state === STATES.signedOut) {
    return fill(say(loc, "fix.signedOut", "Choose Sign in to enter your username, password, and 2FA in a terminal, or run `%1` yourself. The panel refreshes once you are signed in."), SIGNIN_COMMAND)
  }
  if (state === STATES.guiConflict) {
    return say(loc, "fix.guiConflict", "Quit the Proton VPN desktop application, then refresh this panel.")
  }
  if (state === STATES.stale || state === STATES.error) {
    return say(loc, "fix.stale", "Use Refresh after the network, daemon, or CLI is available again. Confirm `protonvpn status` in a terminal if the widget still fails.")
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
  if (state === STATES.signedOut) return SIGNIN_COMMAND
  return ""
}

// Install and sign-in hand off to a terminal; poll until that finishes.
function setupComplete(state, installed) {
  if (installed !== true) return false
  return state !== STATES.cliMissing && state !== STATES.signedOut && state !== STATES.checking
}

function iconCrossed(state) {
  return state === STATES.disconnected || state === STATES.signedOut
}

function iconWarning(state, blocking, stalled, leaking) {
  return blocking === true || stalled === true || leaking === true || state === STATES.cliMissing || state === STATES.guiConflict || state === STATES.error || state === STATES.stale
}

function iconUrgent(state, blocking) {
  return blocking === true || state === STATES.cliMissing || state === STATES.guiConflict || state === STATES.error || state === STATES.stale
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

function clampLinkWatchIntervalSec(value) {
  var n = parseInt(String(value), 10)
  if (!isFinite(n)) n = 4
  if (n < 2) n = 2
  if (n > 60) n = 60
  return n
}

function configValueLabel(key, value, loc) {
  var def = settingDef(key)
  var raw = String(value || "")
  if (!def) return raw
  var on = say(loc, "value.on", "On")
  var off = say(loc, "value.off", "Off")
  if (def.type === "dns") {
    var dns = parseCustomDnsValue(raw)
    if (!dns.enabled) return off
    return dns.ips.length > 0 ? on + " · " + dns.ips.join(", ") : on
  }
  if (def.valueLabels && def.valueLabels[raw]) return tableText(loc, "setting", key, "value." + raw, def.valueLabels[raw])
  if (raw === "on") return on
  if (raw === "off") return off
  return raw
}

function restartNotice(setting, loc) {
  var def = settingDef(setting)
  if (def && def.restart) return say(loc, "config.restartNotice", "Establish a new VPN connection for this change to take effect.")
  return ""
}

// Desktop notifications. "drops" reports only a tunnel that goes down on its
// own; "all" also reports every tunnel that comes up. An open panel already
// shows the change, so nothing is sent while one is open.
var NOTIFICATION_MODES = ["off", "drops", "all"]

function normalizeNotificationSetting(value) {
  var v = String(value === undefined || value === null ? "" : value)
  return NOTIFICATION_MODES.indexOf(v) !== -1 ? v : "drops"
}

// Nerd Font glyphs for omarchy-notification-send: shield-lock, shield-off,
// and shield-alert.
var NOTIFICATION_GLYPHS = {
  connected: "\uDB82\uDD9D",
  dropped: "\uDB82\uDD9E",
  blocked: "\uDB83\uDECC"
}

// Every body starts with fixed text, so CLI-supplied server names can never
// sit where omarchy-notification-send looks for an option.
function linkNotification(previousActive, nextActive, ctx, loc) {
  var c = ctx || {}
  var mode = normalizeNotificationSetting(c.setting)
  if (mode === "off" || c.openPanels > 0 || c.cycleActive === true) return null
  if (previousActive === true && nextActive !== true) {
    if (c.selfInitiated === true) return null
    var body = c.killSwitch === true
      ? say(loc, "notify.dropBlocked", "Kill Switch is blocking internet traffic until the VPN reconnects.")
      : say(loc, "notify.dropOpen", "You're no longer protected.")
    if (c.reconnecting === true) body += " " + say(loc, "notify.reconnecting", "Reconnecting automatically.")
    return {
      summary: say(loc, "notify.dropTitle", "Proton VPN disconnected"),
      body: body,
      urgency: "critical",
      glyph: c.killSwitch === true ? NOTIFICATION_GLYPHS.blocked : NOTIFICATION_GLYPHS.dropped
    }
  }
  if (mode === "all" && previousActive !== true && nextActive === true) {
    var server = capOutput(String(c.server || ""), 64)
    var location = capOutput(String(c.location || ""), 64)
    var connected = server !== ""
      ? fill(say(loc, "notify.connectedTo", "Connected to %1."), server + (location !== "" ? " · " + location : ""))
      : say(loc, "notify.tunnelUp", "The tunnel is up.")
    return { summary: say(loc, "notify.connectedTitle", "Proton VPN connected"), body: connected, urgency: "normal", glyph: NOTIFICATION_GLYPHS.connected }
  }
  return null
}

function reconnectFailedNotification(ctx, loc) {
  var c = ctx || {}
  if (normalizeNotificationSetting(c.setting) === "off" || c.openPanels > 0) return null
  return {
    summary: say(loc, "notify.giveUpTitle", "Proton VPN could not reconnect"),
    body: c.killSwitch === true
      ? say(loc, "notify.giveUpBlocked", "Kill Switch is still blocking internet traffic. Open the panel to connect again.")
      : say(loc, "notify.giveUpOpen", "You're no longer protected. Open the panel to connect again."),
    urgency: "critical",
    glyph: c.killSwitch === true ? NOTIFICATION_GLYPHS.blocked : NOTIFICATION_GLYPHS.dropped
  }
}

// Clicking a notification opens the panel through the plugin's IPC target.
function notificationCommand(note) {
  if (!note) return []
  return ["omarchy-notification-send", "--app-name", "Proton VPN", "--urgency", note.urgency,
    "--glyph", note.glyph, note.summary, note.body, "--exec", "omarchy-shell", PLUGIN_ID, "open"]
}

// Where to go back to after a Kill Switch cycle or an automatic reconnect.
// The free plan only accepts the fastest server.
function returnTarget(activeTarget, status, freePlan) {
  if (freePlan === true) return { mode: "fastest" }
  if (activeTarget && buildConnectCommand(activeTarget).ok) return activeTarget
  var server = String((status && status.server) || "").trim()
  if (server !== "") {
    var byServer = { mode: "server", serverId: server }
    if (buildConnectCommand(byServer).ok) return byServer
  }
  return { mode: "fastest" }
}

// Reconnect on drop backs off between attempts and gives up after the last.
var RECONNECT_DELAYS_MS = [3000, 10000, 30000, 60000, 120000]

function reconnectDelayMs(attempt) {
  var n = Number(attempt)
  if (!isFinite(n) || n < 0 || n >= RECONNECT_DELAYS_MS.length) return -1
  return RECONNECT_DELAYS_MS[Math.floor(n)]
}

// The runner's lock file, one per Hyprland session (scripts/run_bounded.py
// names it the same way). Its absence means the first shell start since login.
function runnerLockName(signature) {
  var sig = String(signature || "")
  return /^[A-Za-z0-9_]{1,128}$/.test(sig) ? "omarchy-protonvpn-" + sig + ".lock" : "omarchy-protonvpn.lock"
}

// The CLI package: installed, in the local package database, and on the
// mirrors when the user asks. Formats are pacman's own, not localized:
//   pacman -Q proton-vpn-cli                      -> "proton-vpn-cli 1.0.5-1"
//   pacman -Sddp --print-format "%n %r %v" proton-vpn-cli -> "proton-vpn-cli extra 1.0.5-1"
//   checkupdates                                  -> "proton-vpn-cli 1.0.5-1 -> 1.0.6-1"
var PACKAGE_VERSION = /^(?:\d+:)?[0-9A-Za-z.+~_]+(?:-[0-9.]+)?$/

function parseInstalledPackage(raw) {
  var parts = String(raw || "").trim().split(/\s+/)
  return parts.length === 2 && parts[0] === CLI_PACKAGE && PACKAGE_VERSION.test(parts[1]) ? parts[1] : ""
}

// Only the CLI's own line: without -dd pacman also lists dependencies.
function parseSyncPackage(raw) {
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].trim().split(/\s+/)
    if (parts.length !== 3 || parts[0] !== CLI_PACKAGE) continue
    if (!/^[a-z0-9._-]{1,32}$/.test(parts[1]) || !PACKAGE_VERSION.test(parts[2])) return null
    return { repo: parts[1], version: parts[2] }
  }
  return null
}

// null when checkupdates lists nothing for the CLI.
function parseCheckUpdates(raw) {
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].trim().match(/^(\S+)\s+(\S+)\s+->\s+(\S+)$/)
    if (m && m[1] === CLI_PACKAGE && PACKAGE_VERSION.test(m[3])) return m[3]
  }
  return null
}

// pacman's own order (libalpm's alpm_pkg_vercmp): epoch, then version,
// then release, each compared with rpmvercmp's segment rules.
function rpmvercmp(a, b) {
  if (a === b) return 0
  var alnum = /[A-Za-z0-9]/
  var digit = /[0-9]/
  var alpha = /[A-Za-z]/
  var one = 0
  var two = 0
  var p1 = 0
  var p2 = 0
  while (one < a.length && two < b.length) {
    while (one < a.length && !alnum.test(a[one])) one++
    while (two < b.length && !alnum.test(b[two])) two++
    if (!(one < a.length && two < b.length)) break
    // Different separator lengths decide it.
    if (one - p1 !== two - p2) return one - p1 < two - p2 ? -1 : 1
    p1 = one
    p2 = two
    var isnum = digit.test(a[p1])
    var kind = isnum ? digit : alpha
    while (p1 < a.length && kind.test(a[p1])) p1++
    while (p2 < b.length && kind.test(b[p2])) p2++
    var segA = a.substring(one, p1)
    var segB = b.substring(two, p2)
    // A numeric segment is newer than an alpha one.
    if (segB === "") return isnum ? 1 : -1
    if (isnum) {
      segA = segA.replace(/^0+/, "")
      segB = segB.replace(/^0+/, "")
      if (segA.length !== segB.length) return segA.length > segB.length ? 1 : -1
    }
    if (segA !== segB) return segA < segB ? -1 : 1
    one = p1
    two = p2
  }
  if (one >= a.length && two >= b.length) return 0
  // A remaining alpha string never beats an empty one.
  if ((one >= a.length && !alpha.test(b[two] || "")) || alpha.test(a[one] || "")) return -1
  return 1
}

function parseEvr(value) {
  var text = String(value || "")
  var epoch = "0"
  var colon = text.indexOf(":")
  if (colon !== -1 && /^\d+$/.test(text.substring(0, colon))) { epoch = text.substring(0, colon) || "0"; text = text.substring(colon + 1) }
  var dash = text.lastIndexOf("-")
  return { epoch: epoch, version: dash === -1 ? text : text.substring(0, dash), release: dash === -1 ? "" : text.substring(dash + 1) }
}

function comparePackageVersions(left, right) {
  if (String(left) === String(right)) return 0
  var a = parseEvr(left)
  var b = parseEvr(right)
  var r = rpmvercmp(a.epoch, b.epoch)
  if (r === 0) r = rpmvercmp(a.version, b.version)
  if (r === 0 && a.release !== "" && b.release !== "") r = rpmvercmp(a.release, b.release)
  return r
}

// What the CLI row says. Latest comes from the mirrors when checked, else
// from the local package database.
function cliVersionInfo(pkg, nowMs, loc) {
  var p = pkg || {}
  var installed = String(p.installed || p.cliVersion || "")
  // The mirror answer holds only until the local database syncs after it.
  var mirror = p.mirrorCheckedMs > 0 && p.mirrorCheckedMs >= Number(p.repoSyncedMs || 0)
  var latest = mirror ? String(p.mirrorVersion || installed) : String(p.repoVersion || "")
  var newer = installed !== "" && latest !== "" && comparePackageVersions(installed, latest) < 0
  var source = ""
  if (mirror) source = fill(say(loc, "cli.fromMirrors", "mirrors, checked %1"), relativeTime(p.mirrorCheckedMs, nowMs, loc))
  else if (p.repoVersion) source = p.repoSyncedMs > 0
    ? fill(say(loc, "cli.fromRepo", "%1, database dated %2"), p.repo, relativeTime(p.repoSyncedMs, nowMs, loc))
    : String(p.repo || "")
  return {
    installed: installed,
    latest: latest,
    source: source,
    newer: newer,
    status: installed === "" ? "" : (latest === "" ? "" : (newer
      ? say(loc, "cli.updateAvailable", "Update available")
      : say(loc, "cli.upToDate", "Up to date")))
  }
}

// `nmcli monitor` restarts after 1, 2, 4 ... seconds, at most a minute apart.
function monitorRestartDelayMs(failures) {
  var n = Math.max(0, Math.floor(Number(failures) || 0))
  return Math.min(60000, 1000 * Math.pow(2, Math.min(n, 6)))
}

// `omarchy bar set` stores a string unless the caller passes --json.
function normalizeBooleanSetting(value) {
  return value === true || value === "true"
}

// States in which a pending reconnect can never succeed until the user acts.
function reconnectAbandoned(state) {
  return state === STATES.signedOut || state === STATES.guiConflict || state === STATES.cliMissing
}

function returnTargetLabel(target, loc) {
  var t = target || {}
  if (t.mode === "server") return String(t.serverId || say(loc, "target.sameServer", "the same server"))
  if (t.label) return String(t.label)
  if (t.mode === "city" && t.city) return String(t.city)
  if (t.mode === "country" && t.country) return String(t.country)
  return say(loc, "target.fastest", "the fastest server")
}

function killSwitchConfirmText(value, target, loc) {
  return fill(say(loc, "killSwitch.confirm", "This briefly drops the VPN, sets Kill Switch to %1, then reconnects to %2."),
    configValueLabel("kill-switch", value, loc), returnTargetLabel(target, loc))
}

// Step after `event` in the idle → disconnecting → setting → reconnecting
// cycle. A failed disconnect ends it untouched; a failed setting still
// reconnects, because leaving someone offline is the worse outcome.
function nextKillSwitchCycleStep(step, event) {
  if (step === "disconnecting") return event === "disconnected" ? "setting" : "idle"
  if (step === "setting") return event === "set" || event === "setFailed" ? "reconnecting" : step
  if (step === "reconnecting") return event === "connected" || event === "connectFailed" ? "idle" : step
  return "idle"
}

// Tunnel traffic from /sys/class/net/<dev>/statistics, sampled only while a
// panel is open. Counters are local and never stored.
function parseInterfaceCounters(raw) {
  var parts = String(raw || "").trim().split(/\s+/)
  if (parts.length !== 2) return null
  var rx = Number(parts[0])
  var tx = Number(parts[1])
  if (!/^\d+$/.test(parts[0]) || !/^\d+$/.test(parts[1]) || !isFinite(rx) || !isFinite(tx)) return null
  return { rx: rx, tx: tx }
}

function emptyTraffic() {
  return { known: false, rx: -1, tx: -1, atMs: 0, rxRate: 0, txRate: 0, sessionRx: 0, sessionTx: 0 }
}

function trafficSample(previous, counters, nowMs) {
  var prev = previous || emptyTraffic()
  if (!counters) return prev
  var next = {
    known: prev.known,
    rx: counters.rx,
    tx: counters.tx,
    atMs: nowMs,
    rxRate: prev.rxRate,
    txRate: prev.txRate,
    sessionRx: prev.sessionRx,
    sessionTx: prev.sessionTx
  }
  if (prev.rx < 0 || prev.atMs <= 0 || counters.rx < prev.rx || counters.tx < prev.tx) {
    // First sample, or the interface was recreated and its counters reset.
    next.rxRate = 0
    next.txRate = 0
    return next
  }
  var seconds = Math.max(0.25, (nowMs - prev.atMs) / 1000)
  var drx = counters.rx - prev.rx
  var dtx = counters.tx - prev.tx
  next.known = true
  next.rxRate = drx / seconds
  next.txRate = dtx / seconds
  next.sessionRx = prev.sessionRx + drx
  next.sessionTx = prev.sessionTx + dtx
  return next
}

// A tunnel can stay up while nothing comes back through it: the server is
// gone, or the network under it is. Data going out with nothing returning
// for STALL_AFTER_MS says so. Idle (nothing sent) is never a stall, and a
// gap between samples (suspend) starts the watch over.
var STALL_AFTER_MS = 30000
var STALL_MIN_SENT_BYTES = 2048
var STALL_MAX_GAP_MS = 20000

function emptyHealth() {
  return { rx: -1, tx: -1, atMs: 0, quietSinceMs: 0, txAtQuiet: 0, stalled: false }
}

function tunnelHealth(previous, counters, nowMs) {
  var prev = previous || emptyHealth()
  if (!counters) return prev
  var restart = prev.rx < 0 || counters.rx < prev.rx || counters.tx < prev.tx || nowMs - prev.atMs > STALL_MAX_GAP_MS
  if (restart || counters.rx > prev.rx) {
    return { rx: counters.rx, tx: counters.tx, atMs: nowMs, quietSinceMs: nowMs, txAtQuiet: counters.tx, stalled: false }
  }
  return {
    rx: counters.rx,
    tx: counters.tx,
    atMs: nowMs,
    quietSinceMs: prev.quietSinceMs,
    txAtQuiet: prev.txAtQuiet,
    stalled: nowMs - prev.quietSinceMs >= STALL_AFTER_MS && counters.tx - prev.txAtQuiet >= STALL_MIN_SENT_BYTES
  }
}

function stalledText(loc) {
  return say(loc, "health.stalled", "Connected, but nothing has come back through the tunnel for 30 seconds. The server or the network under it may be down; reconnect or switch servers if it lasts.")
}

// The tunnel check reads only local state: `ip route get` looks a route up
// without sending a packet, and resolvectl says where systemd-resolved sends
// lookups. Each part is "ok", "blocked", "none", "leak", or "unknown".
var ROUTE_PROBE_V4 = "1.1.1.1"
var ROUTE_PROBE_V6 = "2606:4700:4700::1111"
// Proton's Kill Switch and IPv6 leak protection devices blackhole traffic.
var PROTON_BLOCK_DEVICE = /^(?:pvpnksintrf|pvpnrouteintrf|ipv6leakintrf)\d+$/
// A leak warns once a check at least this much later still finds it, so the
// moments while NetworkManager applies a new connection never flash.
var ROUTING_CONFIRM_MS = 5000

function routingCommands() {
  return {
    ipv4: ["/usr/bin/ip", "-j", "route", "get", ROUTE_PROBE_V4],
    ipv6: ["/usr/bin/ip", "-j", "-6", "route", "get", ROUTE_PROBE_V6],
    dns: ["/usr/bin/resolvectl", "--json=short", "status"],
    firewall: ["/usr/bin/busctl", "--system", "--json=short", "list"]
  }
}

function parseJson(text) {
  try {
    return JSON.parse(String(text || ""))
  } catch (e) {
    return null
  }
}

// `ip route get` exits 2 with nothing on stdout when no route exists.
function routeVerdict(result, tunnelDevice) {
  var r = result || {}
  if (r.timedOut === true) return { status: "unknown", device: "" }
  if (r.exitCode === 2 && String(r.stdout || "").trim() === "") return { status: "none", device: "" }
  var routes = r.exitCode === 0 ? parseJson(r.stdout) : null
  var dev = routes && routes.length > 0 && routes[0] ? String(routes[0].dev || "") : ""
  if (dev === "") return { status: "unknown", device: "" }
  if (tunnelDevice && dev === tunnelDevice) return { status: "ok", device: dev }
  if (PROTON_BLOCK_DEVICE.test(dev)) return { status: "blocked", device: dev }
  return { status: "leak", device: dev }
}

// Proton's opt-in nftables Kill Switch blocks at the firewall, where a route
// lookup cannot see. Its D-Bus service has a pid only once it has started.
// "running", "stopped", or "unknown" when the bus listing failed.
function firewallKillSwitchState(result) {
  var names = result && result.exitCode === 0 && result.timedOut !== true ? parseJson(result.stdout) : null
  if (!names || typeof names.length !== "number" || names.length === 0) return "unknown"
  for (var i = 0; i < names.length; i++) {
    var n = names[i] || {}
    if (n.name === "me.proton.vpn.kill_switch" && Number(n.pid) > 0) return "running"
  }
  return "stopped"
}

function serverText(server) {
  return String((server && server.addressString) || "")
}

// systemd-resolved sends a lookup for an ordinary name to the scopes with a
// "." routing domain when any has one, otherwise to every link with
// DefaultRoute plus the global servers. Domain-only routes (a tailnet, the
// LAN's search domain) never take ordinary names. Proton's blocking devices
// list placeholder servers, so they never count.
function dnsVerdict(result, tunnelDevice) {
  var entries = result && result.exitCode === 0 && result.timedOut !== true ? parseJson(result.stdout) : null
  if (!entries || !entries.length) return { status: "unknown", device: "", server: "" }
  var global = null
  var scopes = []
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i] || {}
    if (e.ifname === undefined) {
      global = e
      continue
    }
    var name = String(e.ifname || "")
    if (PROTON_BLOCK_DEVICE.test(name) || !e.servers || e.servers.length === 0) continue
    scopes.push({ device: name, global: false, defaultRoute: e.defaultRoute === true, domains: e.searchDomains || [], server: serverText(e.servers[0]) })
  }
  // Only the stub mode sends every program's lookups through resolved.
  if (!global || global.resolvConfMode !== "stub") return { status: "unknown", device: "", server: "" }
  if (global.servers && global.servers.length > 0) {
    scopes.push({ device: "", global: true, defaultRoute: true, domains: global.searchDomains || [], server: serverText(global.servers[0]) })
  }
  var rooted = scopes.filter(function(s) {
    return s.domains.some(function(d) { return d && d.name === "." })
  })
  var takers = rooted.length > 0 ? rooted : scopes.filter(function(s) { return s.defaultRoute })
  if (takers.length === 0) return { status: "unknown", device: "", server: "" }
  for (var j = 0; j < takers.length; j++) {
    var t = takers[j]
    if (t.global || t.device !== tunnelDevice) return { status: "leak", device: t.device, server: t.server, global: t.global }
  }
  return { status: "ok", device: tunnelDevice, server: takers[0].server }
}

// results: { ipv4, ipv6, dns, firewall } runner results; firewall may be
// missing, since it is only read when IPv6 leaves outside the tunnel.
function routingVerdict(results, tunnelDevice) {
  var r = results || {}
  var v4 = routeVerdict(r.ipv4, tunnelDevice)
  var v6 = routeVerdict(r.ipv6, tunnelDevice)
  // IPv6 counts as leaking only when the firewall Kill Switch is known to be off.
  if (v6.status === "leak" && firewallKillSwitchState(r.firewall) !== "stopped") v6 = { status: "unknown", device: v6.device }
  var dns = dnsVerdict(r.dns, tunnelDevice)
  var leaks = []
  if (v4.status === "leak") leaks.push({ kind: "ipv4", device: v4.device })
  if (v6.status === "leak") leaks.push({ kind: "ipv6", device: v6.device })
  if (dns.status === "leak") leaks.push({ kind: dns.global ? "dnsGlobal" : "dns", device: dns.device, server: dns.server })
  return { ipv4: v4.status, ipv6: v6.status, dns: dns.status, leaks: leaks }
}

function emptyRouting() {
  return { ipv4: "unknown", ipv6: "unknown", dns: "unknown", leaks: [], shown: [], pending: false, since: {} }
}

// Shows each leak once checks started ROUTING_CONFIRM_MS apart both found it,
// and drops it at the first check that does not.
function routingHealth(previous, verdict, observedMs) {
  var prev = previous || emptyRouting()
  var prevSince = prev.since || {}
  var v = verdict || { ipv4: "unknown", ipv6: "unknown", dns: "unknown", leaks: [] }
  var next = { ipv4: v.ipv4, ipv6: v.ipv6, dns: v.dns, leaks: v.leaks, shown: [], pending: false, since: {} }
  for (var i = 0; i < v.leaks.length; i++) {
    var key = JSON.stringify(v.leaks[i])
    var since = prevSince[key] !== undefined ? prevSince[key] : observedMs
    next.since[key] = since
    if (observedMs - since >= ROUTING_CONFIRM_MS) next.shown.push(v.leaks[i])
    else next.pending = true
  }
  return next
}

// Each line starts with fixed text; device and server names come from the
// system and are capped.
function routingLeakText(leak, loc) {
  var device = capOutput(String((leak && leak.device) || ""), 32)
  var server = capOutput(String((leak && leak.server) || ""), 64)
  var kind = leak ? leak.kind : ""
  if (kind === "ipv4") return fill(say(loc, "routing.ipv4Leak", "IPv4 traffic leaves through %1, outside the tunnel."), device)
  if (kind === "ipv6") return fill(say(loc, "routing.ipv6Leak", "IPv6 traffic leaves through %1, outside the tunnel."), device)
  if (kind === "dnsGlobal") return fill(say(loc, "routing.dnsGlobalLeak", "DNS goes to %1, set system-wide, instead of the tunnel's resolver."), server)
  return fill(say(loc, "routing.dnsLeak", "DNS goes to %1 on %2, outside the tunnel."), server, device)
}

function routingLeakLines(routing, loc) {
  var shown = routing && routing.shown ? routing.shown : []
  return shown.map(function(leak) { return routingLeakText(leak, loc) })
}

function routingNotification(previousCount, routing, ctx, loc) {
  var c = ctx || {}
  var lines = routingLeakLines(routing, loc)
  if (previousCount > 0 || lines.length === 0) return null
  if (normalizeNotificationSetting(c.setting) === "off" || c.openPanels > 0) return null
  return {
    summary: say(loc, "notify.leakTitle", "Proton VPN is not covering everything"),
    body: say(loc, "notify.leakBody", "Open the panel for details.") + " " + lines.join(" "),
    urgency: "critical",
    glyph: NOTIFICATION_GLYPHS.dropped
  }
}

function formatBytes(value, loc) {
  var n = Number(value)
  if (!isFinite(n) || n < 0) n = 0
  var units = ["B", "KB", "MB", "GB", "TB"]
  var i = 0
  while (n >= 1000 && i < units.length - 1) {
    n /= 1000
    i++
  }
  var digits = i === 0 || n >= 100 ? 0 : (n >= 10 ? 1 : 2)
  var text = n.toFixed(digits).replace(/\.0+$|(\.\d*[1-9])0+$/, "$1")
  var places = text.indexOf(".") === -1 ? 0 : text.length - text.indexOf(".") - 1
  return num(loc, Number(text), places) + " " + units[i]
}

function formatRate(value, loc) {
  return formatBytes(value, loc) + "/s"
}

function trafficText(traffic, loc) {
  if (!traffic || traffic.known !== true) return ""
  return fill(say(loc, "traffic.line", "↓ %1  ↑ %2 · %3 this session"),
    formatRate(traffic.rxRate, loc), formatRate(traffic.txRate, loc), formatBytes(traffic.sessionRx + traffic.sessionTx, loc))
}

if (typeof module !== "undefined") {
  module.exports = {
    configListComplete: configListComplete,
    isTunnelDevice: isTunnelDevice,
    NOTIFICATION_MODES: NOTIFICATION_MODES,
    normalizeNotificationSetting: normalizeNotificationSetting,
    linkNotification: linkNotification,
    reconnectFailedNotification: reconnectFailedNotification,
    notificationCommand: notificationCommand,
    NOTIFICATION_GLYPHS: NOTIFICATION_GLYPHS,
    returnTarget: returnTarget,
    returnTargetLabel: returnTargetLabel,
    reconnectDelayMs: reconnectDelayMs,
    monitorRestartDelayMs: monitorRestartDelayMs,
    runnerLockName: runnerLockName,
    parseInstalledPackage: parseInstalledPackage,
    parseSyncPackage: parseSyncPackage,
    parseCheckUpdates: parseCheckUpdates,
    comparePackageVersions: comparePackageVersions,
    cliVersionInfo: cliVersionInfo,
    RECONNECT_DELAYS_MS: RECONNECT_DELAYS_MS,
    normalizeBooleanSetting: normalizeBooleanSetting,
    reconnectAbandoned: reconnectAbandoned,
    killSwitchBlocking: killSwitchBlocking,
    killSwitchBlockingText: killSwitchBlockingText,
    say: say,
    sayN: sayN,
    fill: fill,
    modeLabel: modeLabel,
    settingLabel: settingLabel,
    settingShortLabel: settingShortLabel,
    settingChoiceOptions: settingChoiceOptions,
    portForwardingNotice: portForwardingNotice,
    isFreePlan: isFreePlan,
    modeAvailable: modeAvailable,
    modeOptions: modeOptions,
    planBlockedReason: planBlockedReason,
    setupComplete: setupComplete,
    killSwitchConfirmText: killSwitchConfirmText,
    nextKillSwitchCycleStep: nextKillSwitchCycleStep,
    parseInterfaceCounters: parseInterfaceCounters,
    emptyTraffic: emptyTraffic,
    trafficSample: trafficSample,
    formatBytes: formatBytes,
    formatRate: formatRate,
    trafficText: trafficText,
    emptyHealth: emptyHealth,
    tunnelHealth: tunnelHealth,
    stalledText: stalledText,
    ROUTING_CONFIRM_MS: ROUTING_CONFIRM_MS,
    routingCommands: routingCommands,
    routeVerdict: routeVerdict,
    firewallKillSwitchState: firewallKillSwitchState,
    dnsVerdict: dnsVerdict,
    routingVerdict: routingVerdict,
    emptyRouting: emptyRouting,
    routingHealth: routingHealth,
    routingLeakText: routingLeakText,
    routingLeakLines: routingLeakLines,
    routingNotification: routingNotification,
    STALL_AFTER_MS: STALL_AFTER_MS,

    crashedAfterOutput: crashedAfterOutput,
    readSucceeded: readSucceeded,
    CLI_PACKAGE: CLI_PACKAGE,
    MIN_TESTED_CLI_VERSION: MIN_TESTED_CLI_VERSION,
    MAX_TESTED_CLI_VERSION: MAX_TESTED_CLI_VERSION,
    OUTPUT_CAP: OUTPUT_CAP,
    PLUGIN_ID: PLUGIN_ID,
    SIGNIN_COMMAND: SIGNIN_COMMAND,
    SIGNIN_SCRIPT: SIGNIN_SCRIPT,
    SIGNIN_LAUNCHER: SIGNIN_LAUNCHER,
    INSTALL_LAUNCHER: INSTALL_LAUNCHER,
    UPDATE_LAUNCHER: UPDATE_LAUNCHER,
    SERVER_LIST_URL: SERVER_LIST_URL,
    STATES: STATES,
    CONNECTION_MODES: CONNECTION_MODES,
    CONNECT_FIELDS: CONNECT_FIELDS,
    CONFIG_SETTINGS: CONFIG_SETTINGS,
    TOOLTIP_MAX_LENGTH: TOOLTIP_MAX_LENGTH,
    OPTION_DESCRIPTION_MAX_LENGTH: OPTION_DESCRIPTION_MAX_LENGTH,
    emptyStatus: emptyStatus,
    defaultView: defaultView,
    normalizeOutput: normalizeOutput,
    compareVersions: compareVersions,
    parseCliHelp: parseCliHelp,
    compatibilityWarning: compatibilityWarning,
    parseActiveVpn: parseActiveVpn,
    parseConnectOutcome: parseConnectOutcome,
    recentTarget: recentTarget,
    recordRecentTarget: recordRecentTarget,
    capOutput: capOutput,
    combineOutput: combineOutput,
    hasGuiConflict: hasGuiConflict,
    hasAuthRequired: hasAuthRequired,
    classifyFailureKind: classifyFailureKind,
    parseStatus: parseStatus,
    classifyProbe: classifyProbe,
    signedOutView: signedOutView,
    classifyCommandResult: classifyCommandResult,
    canToggleConnection: canToggleConnection,
    canWrite: canWrite,
    writeBlockedReason: writeBlockedReason,
    isVpnActive: isVpnActive,
    linkMayClaimConnected: linkMayClaimConnected,
    linkConfirmsTunnel: linkConfirmsTunnel,
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
    connectDraftForModeChange: connectDraftForModeChange,
    connectDraftForCountryChange: connectDraftForCountryChange,
    connectFieldTriggerLabel: connectFieldTriggerLabel,
    connectTargetKey: connectTargetKey,
    shouldOfferSwitch: shouldOfferSwitch,
    switchLabel: switchLabel,
    MAX_FAVORITES: MAX_FAVORITES,
    MAX_RECENTS: MAX_RECENTS,
    cleanTarget: cleanTarget,
    normalizeTargets: normalizeTargets,
    isFavorite: isFavorite,
    toggleFavorite: toggleFavorite,
    countryName: countryName,
    targetName: targetName,
    quickConnectRows: quickConnectRows,
    parseTargetSpec: parseTargetSpec,
    statusJson: statusJson,
    normalizeNetworks: normalizeNetworks,
    isTrustedNetwork: isTrustedNetwork,
    toggleNetwork: toggleNetwork,
    buildConnectCommand: buildConnectCommand,
    buildConfigSetCommand: buildConfigSetCommand,
    displayLoad: displayLoad,
    protocolName: protocolName,
    connectedSummary: connectedSummary,
    tooltipText: tooltipText,
    heroTitle: heroTitle,
    BAR_LABELS: BAR_LABELS,
    normalizeBarLabel: normalizeBarLabel,
    barLabelText: barLabelText,
    protectionPairs: protectionPairs,
    trafficPairs: trafficPairs,
    connectButtonLabel: connectButtonLabel,
    heroMeta: heroMeta,
    heroDetail: heroDetail,
    relativeTime: relativeTime,
    lastUpdatedText: lastUpdatedText,
    durationText: durationText,
    degradedExplanation: degradedExplanation,
    degradedRemediation: degradedRemediation,
    diagnosticDetail: diagnosticDetail,
    copyCommandFor: copyCommandFor,
    iconCrossed: iconCrossed,
    iconWarning: iconWarning,
    iconUrgent: iconUrgent,
    iconDim: iconDim,
    clampRefreshIntervalSec: clampRefreshIntervalSec,
    clampLinkWatchIntervalSec: clampLinkWatchIntervalSec,
    configValueLabel: configValueLabel,
    restartNotice: restartNotice
  }
}
