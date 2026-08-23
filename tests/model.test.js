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

  it("marks a parse failure stale when a valid status exists", () => {
    const view = Model.classifyProbe(probe({ exitCode: 0, stdout: fixture("status-partial.txt") }), connected)
    assert.equal(view.state, "stale")
    assert.equal(view.status.server, "CH#42")
    assert.notEqual(view.state, "disconnected")
  })

  it("uses empty successful output as a compatibility error", () => {
    const view = Model.classifyProbe(probe({ exitCode: 0, stdout: "" }))
    assert.equal(view.state, "error")
    assert.notEqual(view.state, "disconnected")
  })

  it("keeps a generic probe failure as stale when a prior status exists", () => {
    const view = Model.classifyProbe(probe({ stderr: "Error: boom", exitCode: 1 }), connected)
    assert.equal(view.state, "stale")
    assert.equal(view.status.server, "CH#42")
    assert.equal(view.connectedSnapshot, true)
    assert.equal(Model.canWrite(view.state), false)
  })

  it("classifies keyring failures without treating them as signed out", () => {
    const view = Model.classifyProbe(probe({ stderr: fixture("keyring-error.txt") }))
    assert.equal(view.state, "error")
    assert.equal(view.kind, "keyring")
    assert.notEqual(view.state, "signedOut")
    assert.match(view.message, /keyring/i)
  })

  it("classifies Proton connection timeouts separately from plugin watchdog timeouts", () => {
    const result = Model.classifyCommandResult(probe({ stderr: fixture("connect-timeout.txt") }))
    assert.equal(result.ok, false)
    assert.equal(result.kind, "connectionTimeout")
    assert.notEqual(result.stateHint, "signedOut")
    assert.match(result.message, /handshake/i)
  })

  it("classifies daemon failures separately from authentication", () => {
    const view = Model.classifyProbe(probe({ stderr: fixture("daemon-error.txt") }))
    assert.equal(view.kind, "daemon")
    assert.notEqual(view.state, "signedOut")
  })
})

describe("safety gate", () => {
  it("allows toggle only while connected or disconnected", () => {
    assert.equal(Model.canToggleConnection("connected"), true)
    assert.equal(Model.canToggleConnection("disconnected"), true)
    ;["checking", "cliMissing", "guiConflict", "signedOut", "connecting", "disconnecting", "error", "stale"].forEach((state) => {
      assert.equal(Model.canToggleConnection(state), false, state)
      assert.equal(Model.canWrite(state), false, state)
    })
  })

  it("blocks kill-switch changes when a stale snapshot is still connected", () => {
    const prior = Model.classifyProbe(probe({ exitCode: 0, stdout: fixture("status-connected.txt") }))
    const stale = Model.classifyProbe(probe({ stderr: fixture("network-error.txt") }), prior)
    assert.equal(stale.state, "stale")
    assert.equal(Model.isVpnActive(stale), true)
    const blocked = Model.buildConfigSetCommand("kill-switch", "standard", { connected: Model.isVpnActive(stale) })
    assert.equal(blocked.ok, false)
    assert.equal(blocked.kind, "prerequisite")
    assert.match(Model.writeBlockedReason("stale"), /outdated/i)
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

  it("treats country-list authentication as signed out, not empty", () => {
    const result = Model.classifyCommandResult(probe({ stderr: fixture("signed-out-countries.txt") }))
    assert.equal(result.stateHint, "signedOut")
    assert.notEqual(result.kind, "empty")
  })

  it("parses an empty country table without inventing rows", () => {
    const parsed = Model.parseCountries(fixture("countries-empty.txt"))
    assert.equal(parsed.ok, true)
    assert.equal(parsed.countries.length, 0)
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

  it("rejects incompatible configuration tables", () => {
    const parsed = Model.parseConfigList(fixture("config-incompatible.txt"))
    assert.equal(parsed.ok, false)
    assert.match(parsed.message, /incompatible/i)
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

  it("cascade-resets connect draft fields when the mode changes", () => {
    const filled = { country: "US", city: "New York", serverId: "IT#23" }
    assert.deepEqual(Model.connectDraftForModeChange("city", "fastest", filled), { country: "", city: "", serverId: "" })
    assert.deepEqual(Model.connectDraftForModeChange("fastest", "city", filled), { country: "", city: "", serverId: "" })
    assert.deepEqual(Model.connectDraftForModeChange("country", "city", filled), { country: "US", city: "", serverId: "" })
    assert.deepEqual(Model.connectDraftForModeChange("city", "country", filled), { country: "US", city: "", serverId: "" })
    assert.deepEqual(Model.connectDraftForModeChange("city", "p2p", filled), { country: "US", city: "", serverId: "" })
    assert.deepEqual(Model.connectDraftForModeChange("p2p", "securecore", filled), { country: "US", city: "", serverId: "" })
    assert.deepEqual(Model.connectDraftForModeChange("city", "server", filled), { country: "", city: "", serverId: "" })
    assert.deepEqual(Model.connectDraftForModeChange("server", "fastest", filled), { country: "", city: "", serverId: "" })
    assert.deepEqual(Model.connectDraftForModeChange("server", "server", filled), { country: "", city: "", serverId: "IT#23" })
  })

  it("clears city when the country draft changes", () => {
    assert.deepEqual(
      Model.connectDraftForCountryChange({ country: "DE", city: "Berlin", serverId: "IT#23" }),
      { country: "DE", city: "", serverId: "IT#23" }
    )
  })

  it("labels empty connect dropdowns by required versus optional country", () => {
    assert.equal(Model.connectFieldTriggerLabel("country", { mode: "city" }), "Choose a country")
    assert.equal(Model.connectFieldTriggerLabel("country", { mode: "country" }), "Choose a country")
    assert.equal(Model.connectFieldTriggerLabel("country", { mode: "p2p" }), "Any country")
    assert.equal(Model.connectFieldTriggerLabel("country", { mode: "securecore" }), "Any country")
    assert.equal(Model.connectFieldTriggerLabel("country", { mode: "tor" }), "Any country")
    assert.equal(Model.connectFieldTriggerLabel("city", { mode: "city", country: "" }), "Choose a country first")
    assert.equal(Model.connectFieldTriggerLabel("city", { mode: "city", country: "US" }), "Choose a city")
    assert.equal(Model.connectFieldTriggerLabel("server", { mode: "server" }), "")
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
    assert.equal(Model.validateDnsList("").ok, false)
    assert.equal(Model.validateDnsList("   ").ok, false)
    assert.equal(Model.validateDnsList("1.1.1.1, 999.1.1.1").ok, false)
    const ipv6 = Model.validateDnsList("2001:4860:4860::8888")
    assert.equal(ipv6.ok, true)
    assert.deepEqual(ipv6.ips, ["2001:4860:4860::8888"])
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
    assert.equal(Model.CLI_PACKAGE, fixture("cli-version.txt").trim())
    assert.match(Model.degradedRemediation({ state: "error", kind: "keyring" }), /keyring/i)
    assert.match(Model.diagnosticDetail({ detail: "Secret Service not available" }), /Secret Service/)
  })
})

describe("Proton-sourced help copy", () => {
  it("gives every connection mode a help caption, tooltip, and option description", () => {
    Model.CONNECTION_MODES.forEach((mode) => {
      assert.ok(String(mode.help || "").trim() !== "", mode.value)
      assert.ok(String(mode.tooltip || "").trim() !== "", mode.value)
      assert.ok(String(mode.tooltip).length <= Model.TOOLTIP_MAX_LENGTH, mode.value)
      assert.ok(String(mode.description || "").trim() !== "", mode.value)
      assert.equal(Model.modeHelp(mode.value), mode.help)
      assert.equal(Model.modeTooltip(mode.value), mode.tooltip)
      assert.equal(Model.modeSummary(mode.value), "")
    })
  })

  it("gives country, city, and server fields help captions, tooltips, and short hints", () => {
    Model.CONNECT_FIELDS.forEach((field) => {
      assert.ok(String(field.help || "").trim() !== "", field.key)
      assert.ok(String(field.tooltip || "").trim() !== "", field.key)
      assert.ok(String(field.tooltip).length <= Model.TOOLTIP_MAX_LENGTH, field.key)
      assert.ok(String(field.summary || "").trim() !== "", field.key)
      assert.equal(Model.connectFieldHelp(field.key), field.help)
      assert.equal(Model.connectFieldTooltip(field.key), field.tooltip)
      assert.equal(Model.connectFieldSummary(field.key), field.summary)
    })
  })

  it("gives every setting a help caption and a one-line tooltip", () => {
    Model.CONFIG_SETTINGS.forEach((setting) => {
      assert.ok(String(setting.help || "").trim() !== "", setting.key)
      assert.ok(String(setting.tooltip || "").trim() !== "", setting.key)
      assert.ok(String(setting.tooltip).length <= Model.TOOLTIP_MAX_LENGTH, setting.key)
      assert.match(Model.settingCaption(setting.key), /\S/)
      assert.equal(Model.settingTooltip(setting.key), setting.tooltip)
    })
  })

  it("keeps operational summaries off settings that have nothing extra to say", () => {
    assert.equal(Model.settingSummary("kill-switch"), "")
    assert.equal(Model.settingSummary("vpn-accelerator"), "")
    assert.equal(Model.settingSummary("anonymous-crash-reports"), "")
    assert.equal(Model.settingDescription("vpn-accelerator"), "")
    assert.match(Model.settingSummary("netshield"), /Tor/i)
    assert.match(Model.settingSummary("port-forwarding"), /P2P/i)
    assert.match(Model.settingSummary("custom-dns"), /NetShield/i)
    assert.match(Model.settingSummary("moderate-nat"), /strict NAT/i)
    assert.match(Model.settingSummary("ipv6"), /Linux apps turn IPv6 on by default/i)
  })

  it("describes NetShield and Kill Switch values in one unelided line", () => {
    const netshield = Model.settingDef("netshield")
    const killSwitch = Model.settingDef("kill-switch")
    netshield.values.forEach((value) => {
      const description = String(netshield.valueDescriptions[value] || "").trim()
      assert.ok(description !== "", value)
      assert.ok(description.length <= Model.OPTION_DESCRIPTION_MAX_LENGTH, value)
    })
    killSwitch.values.forEach((value) => {
      const description = String(killSwitch.valueDescriptions[value] || "").trim()
      assert.ok(description !== "", value)
      assert.ok(description.length <= Model.OPTION_DESCRIPTION_MAX_LENGTH, value)
    })
  })

  it("keeps Proton default hints only where Proton is explicit", () => {
    assert.match(Model.settingCaption("moderate-nat"), /strict NAT/i)
    assert.match(Model.settingCaption("ipv6"), /Linux apps turn IPv6 on by default/i)
    assert.equal(Model.settingDef("vpn-accelerator").defaultHint, undefined)
    assert.equal(Model.settingDef("netshield").defaultHint, undefined)
    assert.match(Model.settingTooltip("custom-dns"), /new connection/i)
    assert.match(Model.settingTooltip("ipv6"), /new connection/i)
    assert.doesNotMatch(Model.settingDescription("custom-dns"), /help them fix bugs|third-party resolvers/i)
    assert.match(Model.settingDescription("custom-dns"), /NetShield/i)
    assert.match(Model.settingDescription("port-forwarding", { upgrade: true }), /Upgrade to enable/)
    assert.match(Model.SETTINGS_SECTION_HELP, /IPv6 and custom DNS/i)
  })

  it("title-cases setting names that were sentence-cased", () => {
    assert.equal(Model.settingDef("kill-switch").label, "Kill Switch")
    assert.equal(Model.settingDef("port-forwarding").label, "Port Forwarding")
    assert.equal(Model.settingDef("anonymous-crash-reports").label, "Anonymous Crash Reports")
  })
})

describe("last-updated copy", () => {
  it("keeps the healthy last-updated value as a relative phrase only", () => {
    const now = 1_700_000_000_000
    const justNow = Model.lastUpdatedText({ state: "connected", lastUpdatedMs: now - 1000 }, now)
    assert.equal(justNow, "just now")
    assert.doesNotMatch(justNow, /^Updated /)
    const seconds = Model.lastUpdatedText({ state: "disconnected", lastUpdatedMs: now - 13_000 }, now)
    assert.equal(seconds, "13s ago")
    const stale = Model.lastUpdatedText({ state: "stale", lastUpdatedMs: now - 60_000 }, now)
    assert.equal(stale, "Last successful update 1m ago")
  })
})
