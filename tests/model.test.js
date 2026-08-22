const { describe, it } = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const Model = require("../Model.js")

function fixture(name) {
  return fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8")
}

function probe(overrides) {
  return Object.assign({ exitCode: 1, stdout: "", stderr: "", timedOut: false, cliMissing: false }, overrides)
}

describe("status parsing", () => {
  it("parses disconnected status", () => {
    const parsed = Model.parseStatus(fixture("status-disconnected.txt"))
    assert.equal(parsed.ok, true)
    assert.equal(parsed.state, "disconnected")
    assert.equal(parsed.status.server, "")
  })

  it("parses connected status fields", () => {
    const parsed = Model.parseStatus(fixture("status-connected.txt"))
    assert.equal(parsed.ok, true)
    assert.equal(parsed.state, "connected")
    assert.equal(parsed.status.server, "CH#42")
    assert.equal(parsed.status.location, "Zurich, Switzerland")
    assert.equal(parsed.status.load, 23)
    assert.equal(parsed.status.protocol, "WireGuard")
  })

  it("ignores server-list update prefixes", () => {
    const parsed = Model.parseStatus(fixture("status-connected-prefix.txt"))
    assert.equal(parsed.ok, true)
    assert.equal(parsed.status.server, "NL#14")
    assert.equal(parsed.status.location, "Amsterdam, Netherlands")
  })

  it("keeps commas and spaces inside locations", () => {
    const parsed = Model.parseStatus(fixture("status-connected-comma-location.txt"))
    assert.equal(parsed.status.server, "US#88")
    assert.equal(parsed.status.location, "Washington, D.C., United States")
  })

  it("parses Secure Core via-locations", () => {
    const parsed = Model.parseStatus(fixture("status-connected-securecore.txt"))
    assert.equal(parsed.status.server, "IS-CH#1")
    assert.equal(parsed.status.location, "Reykjavik, via Switzerland")
  })

  it("rejects partial connected output", () => {
    const parsed = Model.parseStatus(fixture("status-partial.txt"))
    assert.equal(parsed.ok, false)
    assert.equal(parsed.kind, "parse")
  })

  it("rejects malformed output instead of assuming disconnected", () => {
    const parsed = Model.parseStatus(fixture("status-malformed.txt"))
    assert.equal(parsed.ok, false)
    const view = Model.classifyProbe(probe({ exitCode: 0, stdout: fixture("status-malformed.txt") }))
    assert.equal(view.state, "error")
    assert.notEqual(view.state, "disconnected")
  })
})

describe("probe classification", () => {
  const connected = Model.classifyProbe(probe({ exitCode: 0, stdout: fixture("status-connected.txt") }))

  it("reports CLI missing first", () => {
    const view = Model.classifyProbe(probe({ cliMissing: true, stdout: fixture("status-disconnected.txt"), exitCode: 0 }))
    assert.equal(view.state, "cliMissing")
  })

  it("detects GUI conflict from official wording", () => {
    const view = Model.classifyProbe(probe({ stderr: fixture("gui-conflict.txt") }))
    assert.equal(view.state, "guiConflict")
    assert.match(Model.tooltipText(view), /desktop app/i)
  })

  it("detects signed-out only from authentication diagnostics", () => {
    const view = Model.classifyProbe(probe({ stderr: fixture("signed-out-connect.txt") }))
    assert.equal(view.state, "signedOut")
    const generic = Model.classifyProbe(probe({ stderr: "Error: boom", exitCode: 1 }))
    assert.notEqual(generic.state, "signedOut")
    assert.notEqual(generic.state, "disconnected")
    assert.equal(generic.state, "error")
  })

  it("does not treat a generic failure as disconnected", () => {
    const view = Model.classifyProbe(probe({ stderr: "Error: something went wrong", exitCode: 1 }))
    assert.equal(view.state, "error")
    assert.notEqual(view.state, "disconnected")
    assert.notEqual(view.state, "signedOut")
  })

  it("marks a transient failure stale and keeps the last status", () => {
    const view = Model.classifyProbe(probe({ stderr: fixture("network-error.txt"), timedOut: false }), connected)
    assert.equal(view.state, "stale")
    assert.equal(view.status.server, "CH#42")
    assert.equal(view.status.location, "Zurich, Switzerland")
    assert.match(view.message, /network/i)
  })

  it("marks a poll timeout stale when a valid status exists", () => {
    const view = Model.classifyProbe(probe({ timedOut: true, stderr: "" }), connected)
    assert.equal(view.state, "stale")
    assert.equal(view.status.server, "CH#42")
  })

  it("does not invent a disconnected state after a parse failure", () => {
    const view = Model.classifyProbe(probe({ exitCode: 0, stdout: fixture("status-partial.txt") }), connected)
    assert.equal(view.state, "error")
    assert.notEqual(view.state, "disconnected")
  })

  it("uses empty successful output as a compatibility error", () => {
    const view = Model.classifyProbe(probe({ exitCode: 0, stdout: "" }))
    assert.equal(view.state, "error")
    assert.notEqual(view.state, "disconnected")
  })
})

describe("safety gate", () => {
  it("allows toggle only while connected or disconnected", () => {
    assert.equal(Model.canToggleConnection("connected"), true)
    assert.equal(Model.canToggleConnection("disconnected"), true)
    ;["checking", "cliMissing", "guiConflict", "signedOut", "connecting", "disconnecting", "error", "stale"].forEach((state) => {
      assert.equal(Model.canToggleConnection(state), false, state)
    })
  })
})

describe("location tables", () => {
  it("parses country names that contain spaces", () => {
    const parsed = Model.parseCountries(fixture("countries-list.txt"))
    assert.equal(parsed.ok, true)
    const bosnia = parsed.countries.find((c) => c.code === "BA")
    assert.equal(bosnia.name, "Bosnia and Herzegovina")
    assert.equal(parsed.countries.find((c) => c.code === "US").name, "United States")
  })

  it("parses city names and feature lists", () => {
    const parsed = Model.parseCities(fixture("cities-us.txt"))
    assert.equal(parsed.ok, true)
    const ny = parsed.cities.find((c) => c.name === "New York")
    const slc = parsed.cities.find((c) => c.name === "Salt Lake City")
    const atl = parsed.cities.find((c) => c.name === "Atlanta")
    assert.ok(ny)
    assert.ok(slc)
    assert.equal(atl.features, "P2P, Tor")
  })
})

describe("configuration parsing", () => {
  it("parses every 1.0.1 setting", () => {
    const parsed = Model.parseConfigList(fixture("config-list.txt"))
    assert.equal(parsed.ok, true)
    Model.CONFIG_SETTINGS.forEach((setting) => {
      assert.equal(parsed.settings[setting.key] !== undefined, true, setting.key)
    })
    assert.equal(parsed.settings.netshield, "malware-only")
    assert.equal(parsed.settings["kill-switch"], "off")
    assert.equal(parsed.settings["vpn-accelerator"], "on")
  })

  it("records paid-plan placeholders without hiding the setting", () => {
    const parsed = Model.parseConfigList(fixture("config-list-free.txt"))
    assert.equal(parsed.upgrade.netshield, true)
    assert.equal(parsed.upgrade["kill-switch"], false)
    assert.equal(parsed.settings.ipv6, "on")
  })

  it("parses custom DNS addresses from the value column", () => {
    const parsed = Model.parseConfigList(fixture("config-list-custom-dns.txt"))
    const dns = Model.parseCustomDnsValue(parsed.settings["custom-dns"])
    assert.equal(dns.enabled, true)
    assert.deepEqual(dns.ips, ["1.1.1.1", "8.8.8.8"])
  })
})

describe("connection commands", () => {
  it("builds argument arrays for every supported mode", () => {
    assert.deepEqual(Model.buildConnectCommand({ mode: "fastest" }).command, ["protonvpn", "connect"])
    assert.deepEqual(Model.buildConnectCommand({ mode: "country", country: "US" }).command, ["protonvpn", "connect", "--country", "US"])
    assert.deepEqual(Model.buildConnectCommand({ mode: "city", country: "US", city: "New York" }).command, ["protonvpn", "connect", "--country", "US", "--city", "New York"])
    assert.deepEqual(Model.buildConnectCommand({ mode: "server", serverId: "IT#23" }).command, ["protonvpn", "connect", "IT#23"])
    assert.deepEqual(Model.buildConnectCommand({ mode: "p2p", country: "IT" }).command, ["protonvpn", "connect", "--country", "IT", "--p2p"])
    assert.deepEqual(Model.buildConnectCommand({ mode: "securecore" }).command, ["protonvpn", "connect", "--securecore"])
    assert.deepEqual(Model.buildConnectCommand({ mode: "tor" }).command, ["protonvpn", "connect", "--tor"])
    assert.deepEqual(Model.buildConnectCommand({ mode: "random" }).command, ["protonvpn", "connect", "--random"])
  })

  it("rejects invalid combinations and server IDs", () => {
    assert.equal(Model.buildConnectCommand({ mode: "country" }).ok, false)
    assert.equal(Model.buildConnectCommand({ mode: "city", country: "US" }).ok, false)
    assert.equal(Model.buildConnectCommand({ mode: "server", serverId: "nope" }).ok, false)
    assert.equal(Model.buildConnectCommand({ mode: "server", serverId: "IT#23", country: "IT" }).ok, false)
  })
})

describe("config writes", () => {
  it("builds argument arrays for every current setting", () => {
    assert.deepEqual(Model.buildConfigSetCommand("netshield", "malware-ads-trackers").command, ["protonvpn", "config", "set", "netshield", "malware-ads-trackers"])
    assert.deepEqual(Model.buildConfigSetCommand("kill-switch", "standard").command, ["protonvpn", "config", "set", "kill-switch", "standard"])
    assert.deepEqual(Model.buildConfigSetCommand("port-forwarding", "on").command, ["protonvpn", "config", "set", "port-forwarding", "on"])
    assert.deepEqual(Model.buildConfigSetCommand("vpn-accelerator", "off").command, ["protonvpn", "config", "set", "vpn-accelerator", "off"])
    assert.deepEqual(Model.buildConfigSetCommand("moderate-nat", "on").command, ["protonvpn", "config", "set", "moderate-nat", "on"])
    assert.deepEqual(Model.buildConfigSetCommand("ipv6", "off").command, ["protonvpn", "config", "set", "ipv6", "off"])
    assert.deepEqual(Model.buildConfigSetCommand("anonymous-crash-reports", "off").command, ["protonvpn", "config", "set", "anonymous-crash-reports", "off"])
  })

  it("passes custom DNS as one --dns argument after local validation", () => {
    const enabled = Model.buildConfigSetCommand("custom-dns", "on", { dns: "1.1.1.1, 8.8.8.8" })
    assert.deepEqual(enabled.command, ["protonvpn", "config", "set", "custom-dns", "on", "--dns", "1.1.1.1,8.8.8.8"])
    const disabled = Model.buildConfigSetCommand("custom-dns", "off")
    assert.deepEqual(disabled.command, ["protonvpn", "config", "set", "custom-dns", "off"])
    assert.equal(Model.buildConfigSetCommand("custom-dns", "on", { dns: "not-an-ip" }).ok, false)
  })

  it("encodes kill-switch disconnect prerequisite and restart notices", () => {
    const blocked = Model.buildConfigSetCommand("kill-switch", "standard", { connected: true })
    assert.equal(blocked.ok, false)
    assert.equal(blocked.kind, "prerequisite")
    assert.equal(Model.buildConfigSetCommand("ipv6", "on").restart, true)
    assert.equal(Model.restartNotice("custom-dns") !== "", true)
  })
})

describe("command result classification", () => {
  it("keeps paid-plan failures actionable", () => {
    const result = Model.classifyCommandResult(probe({ stderr: fixture("paid-plan-country.txt") }))
    assert.equal(result.ok, false)
    assert.equal(result.kind, "plan")
    assert.match(result.message, /free plan/i)
  })

  it("classifies invalid server and kill-switch errors", () => {
    assert.equal(Model.classifyCommandResult(probe({ stderr: fixture("invalid-server.txt") })).kind, "invalid")
    assert.equal(Model.classifyCommandResult(probe({ stderr: fixture("killswitch-connected.txt") })).kind, "prerequisite")
  })

  it("does not treat cities-list usage errors as signed out", () => {
    const result = Model.classifyCommandResult(probe({ stderr: fixture("cities-invalid-country.txt") }))
    assert.notEqual(result.stateHint, "signedOut")
    assert.equal(result.kind, "invalid")
  })
})

describe("display helpers", () => {
  it("caps diagnostics and keeps tooltips state-specific", () => {
    const long = Model.capOutput("x".repeat(800), 40)
    assert.equal(long.length, 40)
    assert.equal(Model.tooltipText({ state: "disconnected" }), "Proton VPN disconnected.")
    assert.match(Model.tooltipText({ state: "connected", status: { server: "CH#42", location: "Zurich, Switzerland", load: 23, protocol: "WireGuard" } }), /CH#42/)
    assert.equal(Model.copyCommandFor("signedOut"), Model.SIGNIN_COMMAND)
    assert.equal(Model.clampRefreshIntervalSec(3), 10)
    assert.equal(Model.clampRefreshIntervalSec(9000), 3600)
  })
})
