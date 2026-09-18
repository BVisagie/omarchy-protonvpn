import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model
import "Scheduler.js" as Scheduler

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var settings: ({})
  // False keeps a panel-local fallback instance idle while the shared Omarchy
  // service is available.
  property bool active: true

  property string state: Model.STATES.checking
  property var status: Model.emptyStatus()
  property string kind: ""
  property string message: ""
  property string detail: ""
  property bool stale: false
  property bool signedIn: false
  property bool connectedSnapshot: false
  property bool installed: false
  property bool refreshing: false
  property string actionStatus: ""
  property string lastError: ""
  property double lastUpdatedMs: 0

  property string cliPath: ""
  property string cliVersion: ""
  property var cliCommands: []
  property string compatibilityWarning: ""

  property bool linkKnown: false
  property bool linkAvailable: true
  property bool linkActive: false
  property string linkServer: ""
  property string linkDevice: ""
  property var recentTargets: []
  // Panels on every monitor share this service; count the open ones.
  property int openPanels: 0
  readonly property string notificationSetting: Model.normalizeNotificationSetting(setting("notifications", "drops"))
  // Last tunnel state a notification decision was made for; null until the
  // first link observation, so start-up never announces an existing tunnel.
  property var _notifiedActive: null

  // Kill Switch while connected: idle → disconnecting → setting → reconnecting.
  property string ksStep: "idle"
  property string _ksValue: ""
  property var _ksTarget: null
  property string _ksError: ""
  property bool _ksInternal: false

  property var traffic: Model.emptyTraffic()
  property string _trafficDevice: ""
  property string _trafficServer: ""
  readonly property string trafficText: Model.trafficText(traffic)
  // Options behind the current connection, when this session made it.
  property var activeTarget: null

  property var countries: []
  property var cities: []
  property string citiesCountry: ""
  property string countriesError: ""
  property string citiesError: ""
  property bool countriesLoaded: false
  property bool countriesLoading: false
  property bool citiesLoading: false
  property bool discoveryStale: false

  property var configValues: ({})
  property var configUpgrade: ({})
  property bool configLoaded: false
  property string configError: ""
  property string pendingSetting: ""
  property string pendingValue: ""
  property string restartNotice: ""

  readonly property int refreshIntervalSec: Model.clampRefreshIntervalSec(setting("refreshIntervalSec", 30))
  readonly property int linkWatchIntervalSec: Model.clampLinkWatchIntervalSec(setting("linkWatchIntervalSec", 4))
  readonly property bool processBusy: commandProcess.running
  readonly property bool actionRunning: (_currentJob && _currentJob.type === "action") || Scheduler.hasAction(_queueState)
  readonly property bool busy: processBusy || state === Model.STATES.connecting || state === Model.STATES.disconnecting
  readonly property bool actionBusy: actionRunning
  readonly property var view: ({
    state: root.state,
    kind: root.kind,
    message: root.message,
    detail: root.detail,
    stale: root.stale,
    status: root.status,
    signedIn: root.signedIn,
    lastUpdatedMs: root.lastUpdatedMs,
    connectedSnapshot: root.connectedSnapshot
  })
  // A Kill Switch cycle owns the connection until it finishes; only its own
  // steps may write while it runs.
  readonly property bool canToggle: Model.canWrite(state) && !actionRunning && (ksStep === "idle" || _ksInternal)
  readonly property bool canChangeSettings: canToggle
  readonly property string runnerPath: decodeURIComponent(Qt.resolvedUrl("scripts/run_bounded.py").toString().replace(/^file:\/\//, ""))

  property var _queueState: Scheduler.emptyQueue()
  property var _currentJob: null
  property int _commandRunId: 0
  property bool _timedOut: false
  property bool _pendingStatusRefresh: false
  property string _commandOutput: ""
  property string _commandError: ""
  property string _linkOutput: ""
  property string _linkError: ""
  property var _citiesCache: ({})
  property int _linkEpoch: 0
  property int _linkStartedEpoch: 0

  function panelOpened() {
    openPanels = openPanels + 1
  }

  function panelClosed() {
    openPanels = Math.max(0, openPanels - 1)
  }

  function setSettings(next) {
    settings = next || ({})
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function snapshot() {
    return {
      state: state,
      kind: kind,
      message: message,
      detail: detail,
      stale: stale,
      status: status,
      signedIn: signedIn,
      lastUpdatedMs: lastUpdatedMs,
      connectedSnapshot: connectedSnapshot
    }
  }

  function statusCopy(source) {
    var value = source || ({})
    return {
      server: String(value.server || ""),
      location: String(value.location || ""),
      load: value.load === null || value.load === undefined ? null : Number(value.load),
      protocol: String(value.protocol || ""),
      exitIp: String(value.exitIp || "")
    }
  }

  function applyView(next) {
    if (!next) return
    var previousConnected = connectedSnapshot === true
    state = String(next.state || Model.STATES.error)
    kind = String(next.kind || "")
    message = String(next.message || "")
    detail = String(next.detail || "")
    stale = next.stale === true
    status = statusCopy(next.status || Model.emptyStatus())
    signedIn = next.signedIn === true
    connectedSnapshot = next.connectedSnapshot === true
    if (state === Model.STATES.disconnected) activeTarget = null
    if (state === Model.STATES.connected || state === Model.STATES.disconnected) {
      lastUpdatedMs = Date.now()
      lastError = ""
      if (state === Model.STATES.connected && previousConnected === false) restartNotice = ""
    } else if (message !== "") {
      lastError = message
    }
  }

  function connectedView(nextStatus) {
    return {
      state: Model.STATES.connected,
      kind: "status",
      message: "",
      detail: "",
      stale: false,
      status: statusCopy(nextStatus),
      signedIn: true,
      connectedSnapshot: true
    }
  }

  function disconnectedView() {
    return {
      state: Model.STATES.disconnected,
      kind: "status",
      message: "",
      detail: "",
      stale: false,
      status: Model.emptyStatus(),
      signedIn: true,
      connectedSnapshot: false
    }
  }

  function prepareCommand(command) {
    var prepared = (command || []).slice()
    if (prepared.length > 0 && prepared[0] === "protonvpn" && cliPath !== "") prepared[0] = cliPath
    return prepared
  }

  function boundedCommand(command, timeoutMs) {
    var seconds = Math.max(1, Math.ceil(Number(timeoutMs || 20000) / 1000))
    return ["/usr/bin/python3", runnerPath, "--max-bytes", "262144", "--max-seconds", String(seconds), "--"].concat(prepareCommand(command))
  }

  function enqueue(job) {
    var result = Scheduler.enqueueJob(_queueState, job)
    _queueState = result.queue
    if (!result.accepted) return false
    pump()
    return true
  }

  function pump() {
    if (processBusy || _queueState.current) return
    var started = Scheduler.beginJob(_queueState)
    _queueState = started.queue
    if (!started.started) {
      _currentJob = null
      watchdog.stop()
      if (_pendingStatusRefresh) {
        _pendingStatusRefresh = false
        requestStatusRefresh()
      }
      return
    }
    startJob(started.job)
  }

  function startJob(job) {
    var timeout = Scheduler.timeoutFor(job)
    _timedOut = false
    _currentJob = job
    _commandRunId = job.runId
    _commandOutput = ""
    _commandError = ""
    refreshing = job.type === "status"
    watchdog.interval = timeout + 2000
    watchdog.restart()
    commandProcess.command = boundedCommand(job.command, timeout)
    commandProcess.running = true
  }

  function finishJob(result) {
    var job = _currentJob
    if (!job) return
    var runId = result && result.runId !== undefined ? result.runId : job.runId
    if (!Scheduler.shouldApplyResult(_queueState, runId)) return
    var finished = Scheduler.finishJob(_queueState, runId)
    if (!finished.finished) return
    watchdog.stop()
    _queueState = finished.queue
    _currentJob = null
    refreshing = false
    if (result) result.timedOut = result.timedOut === true || _timedOut === true
    _timedOut = false
    if (job.type === "which") handleWhich(result)
    else if (job.type === "help") handleHelp(result)
    else if (job.type === "status") handleStatus(result)
    else if (job.type === "action") handleAction(result, job)
    else if (job.type === "discovery") handleDiscovery(result, job)
    else if (job.type === "config") handleConfig(result, job)
    Qt.callLater(pump)
  }

  function handleWhich(result) {
    var found = result.exitCode === 0 && result.timedOut !== true
      ? String(result.stdout || "").trim().split("\n")[0] : ""
    installed = found.charAt(0) === "/"
    cliPath = installed ? found : ""
    if (!installed) {
      cliVersion = ""
      cliCommands = []
      compatibilityWarning = ""
      applyView(Model.classifyProbe({ cliMissing: true, exitCode: result.exitCode, stdout: "", stderr: "", timedOut: result.timedOut === true }))
      return
    }
    enqueue({ type: "help", command: ["protonvpn", "--help"], timeout: 5000 })
    requestStatusRefresh()
    watchLink()
  }

  function handleHelp(result) {
    var info = result.exitCode === 0 && result.timedOut !== true
      ? Model.parseCliHelp(result.stdout) : Model.parseCliHelp("")
    cliVersion = info.version
    cliCommands = info.commands
    compatibilityWarning = Model.compatibilityWarning(info)
  }

  function handleStatus(result) {
    if (!installed) {
      applyView(Model.classifyProbe({ cliMissing: true }))
      return
    }
    var previous = snapshot()
    var next = Model.classifyProbe({
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
      timedOut: result.timedOut === true
    }, previous)
    if (next.state === Model.STATES.connected) {
      if (previous.status && previous.status.server === next.status.server) next.status.exitIp = String(previous.status.exitIp || "")
      if (linkConfirmed() && linkServer !== "" && next.status.server === "") next.status.server = linkServer
      applyView(next)
    } else if (next.state === Model.STATES.disconnected && linkConfirmed()) {
      var observed = statusCopy(previous.status)
      if (linkServer !== "") observed.server = linkServer
      applyView(connectedView(observed))
    } else {
      applyView(next)
    }
    if (next.state === Model.STATES.connected || next.state === Model.STATES.disconnected) {
      if (!configLoaded) refreshConfig()
    }
  }

  function handleAction(result, job) {
    // Any nmcli poll that started before this result may describe the old tunnel.
    _linkEpoch++
    var classified = Model.classifyCommandResult(result, job.snapshot || snapshot())
    if (classified.stateHint === Model.STATES.guiConflict || classified.stateHint === Model.STATES.signedOut) {
      applyView(Model.classifyProbe(result, job.snapshot || snapshot()))
      actionStatus = ""
      delayedRefresh.restart()
      abortKillSwitch(classified.message)
      return
    }
    if (classified.ok) {
      lastError = ""
      actionStatus = classified.message || (job.action === "disconnect" ? "Disconnected." : "Connected.")
      if (job.action === "disconnect") {
        linkActive = false
        linkServer = ""
        linkDevice = ""
        applyView(disconnectedView())
        noteLink(false, true)
      } else {
        var outcome = Model.parseConnectOutcome(result.stdout)
        var nextStatus = statusCopy((job.snapshot || snapshot()).status)
        if (outcome.server !== "" && outcome.server !== nextStatus.server) {
          // Load, protocol, and location belonged to the previous server.
          nextStatus.location = ""
          nextStatus.load = null
          nextStatus.protocol = ""
        }
        if (outcome.server !== "") nextStatus.server = outcome.server
        if (outcome.location !== "") nextStatus.location = outcome.location
        nextStatus.exitIp = outcome.exitIp
        applyView(connectedView(nextStatus))
        var target = Model.recentTarget(job.options || {}, outcome)
        activeTarget = target
        recentTargets = Model.recordRecentTarget(recentTargets, target, 3)
        noteLink(true, true)
      }
    } else {
      lastError = classified.message
      actionStatus = classified.message
      if (job.action === "connect" && job.snapshot && job.snapshot.state === Model.STATES.connected) {
        // A failed switch can leave the old tunnel down; the CLI disconnects on
        // connection errors. Re-check instead of restoring "connected".
        applyView({
          state: Model.STATES.checking,
          kind: classified.kind,
          message: classified.message,
          detail: classified.detail,
          stale: false,
          status: job.snapshot.status,
          signedIn: true,
          connectedSnapshot: true
        })
      } else if (job.snapshot) {
        applyView(job.snapshot)
      }
      lastError = classified.message
    }
    actionStatusTimer.restart()
    watchLink()
    delayedRefresh.restart()
    if (ksStep !== "idle") advanceKillSwitch(job.action === "disconnect"
      ? (classified.ok ? "disconnected" : "disconnectFailed")
      : (classified.ok ? "connected" : "connectFailed"), classified.message)
  }

  function handleDiscovery(result, job) {
    var classified = Model.classifyCommandResult(result, snapshot())
    if (classified.stateHint === Model.STATES.signedOut || classified.stateHint === Model.STATES.guiConflict) {
      applyView(Model.classifyProbe(result, snapshot()))
      countriesLoading = false
      citiesLoading = false
      return
    }
    if (job.kind === "countries") {
      countriesLoading = false
      if (!Model.readSucceeded(result)) {
        countriesError = classified.message || "Could not list countries."
        if (countries.length > 0) discoveryStale = true
        return
      }
      var countriesCrashed = Model.crashedAfterOutput(result)
      var parsedCountries = Model.parseCountries(result.stdout)
      if (!parsedCountries.ok || (countriesCrashed && parsedCountries.countries.length === 0)) {
        countriesError = countriesCrashed ? (classified.message || "Could not list countries.") : parsedCountries.message
        if (countriesCrashed && countries.length > 0) discoveryStale = true
        return
      }
      countries = parsedCountries.countries
      // A table has no end marker, so crashed output is shown but fetched again.
      countriesLoaded = !countriesCrashed
      countriesError = parsedCountries.countries.length === 0 ? "No countries returned." : ""
      discoveryStale = false
      return
    }
    if (job.kind === "cities") {
      if (String(job.country || "") !== citiesCountry) return
      citiesLoading = false
      if (!Model.readSucceeded(result)) {
        citiesError = classified.message || "Could not list cities."
        if (cities.length > 0) discoveryStale = true
        return
      }
      var citiesCrashed = Model.crashedAfterOutput(result)
      var parsedCities = Model.parseCities(result.stdout)
      if (!parsedCities.ok || (citiesCrashed && parsedCities.cities.length === 0)) {
        if (citiesCrashed) {
          citiesError = classified.message || "Could not list cities."
          if (cities.length > 0) discoveryStale = true
          return
        }
        citiesError = parsedCities.message
        cities = []
        return
      }
      cities = parsedCities.cities
      if (parsedCities.cities.length > 0 && !citiesCrashed) {
        var cache = Object.assign({}, _citiesCache)
        cache[citiesCountry] = parsedCities.cities
        _citiesCache = cache
      }
      citiesError = parsedCities.cities.length === 0 ? "No cities returned for that country." : ""
      discoveryStale = false
    }
  }

  function handleConfig(result, job) {
    var classified = Model.classifyCommandResult(result, snapshot())
    if (classified.stateHint === Model.STATES.signedOut || classified.stateHint === Model.STATES.guiConflict) {
      pendingSetting = ""
      pendingValue = ""
      applyView(Model.classifyProbe(result, snapshot()))
      if (job.kind === "set") abortKillSwitch(classified.message)
      return
    }
    if (job.kind === "list") {
      if (!Model.readSucceeded(result)) {
        configError = classified.message || "Could not read Proton VPN settings."
        return
      }
      var configCrashed = Model.crashedAfterOutput(result)
      var parsed = Model.parseConfigList(result.stdout)
      if (!parsed.ok || (configCrashed && !Model.configListComplete(parsed))) {
        configError = configCrashed ? (classified.message || "Could not read Proton VPN settings.") : parsed.message
        return
      }
      configValues = parsed.settings
      configUpgrade = parsed.upgrade
      configLoaded = true
      configError = ""
      pendingSetting = ""
      pendingValue = ""
      return
    }
    if (job.kind === "set") {
      if (classified.ok) {
        lastError = ""
        actionStatus = classified.message || "Setting updated."
        restartNotice = job.restart === true ? Model.restartNotice(job.setting) : ""
        if (/please establish a new VPN connection/i.test(classified.detail)) restartNotice = classified.detail
      } else {
        lastError = classified.message
        actionStatus = classified.message
      }
      pendingSetting = ""
      pendingValue = ""
      actionStatusTimer.restart()
      refreshConfig()
      if (ksStep === "setting" && job.setting === "kill-switch") advanceKillSwitch(classified.ok ? "set" : "setFailed", classified.message)
    }
  }

  function requestStatusRefresh() {
    if (actionRunning) {
      _pendingStatusRefresh = true
      return
    }
    enqueue({ type: "status", command: ["protonvpn", "status"] })
  }

  function refresh() {
    if (!installed) {
      enqueue({ type: "which", command: ["/usr/bin/which", "protonvpn"], timeout: 5000 })
      return
    }
    requestStatusRefresh()
    watchLink()
  }

  function linkConfirmed() {
    return Model.linkConfirmsTunnel({ known: linkKnown, available: linkAvailable, active: linkActive })
  }

  function watchLink() {
    if (!active || !installed || linkProcess.running) return
    _linkStartedEpoch = _linkEpoch
    _linkOutput = ""
    _linkError = ""
    linkProcess.command = boundedCommand(["/usr/bin/nmcli", "-t", "-e", "no", "-f", "NAME,TYPE,DEVICE,STATE", "connection", "show", "--active"], 5000)
    linkProcess.running = true
  }

  function applyLinkResult(result) {
    if (_linkStartedEpoch !== _linkEpoch) {
      // An action finished while this poll was running; re-read the live link.
      Qt.callLater(watchLink)
      return
    }
    if (result.exitCode !== 0 || result.timedOut === true) {
      linkAvailable = false
      return
    }
    linkAvailable = true
    linkKnown = true
    var previousActive = linkActive
    var previousServer = linkServer
    var link = Model.parseActiveVpn(result.stdout)
    linkActive = link.active
    linkServer = link.server
    linkDevice = link.device
    noteLink(link.active, actionRunning)
    // NetworkManager can briefly continue reporting the old tunnel while a
    // connect, server change, or disconnect is in flight. Keep the live facts,
    // but let the action result own the transitional UI state.
    if (actionRunning) return
    if (!Model.linkMayClaimConnected(state)) {
      // Keep GUI-conflict, signed-out, and error verdicts in both directions;
      // only a status check may clear them.
      if (link.active !== previousActive) requestStatusRefresh()
      return
    }
    if (link.active) {
      var nextStatus = statusCopy(status)
      var changedServer = previousActive && previousServer !== "" && link.server !== "" && previousServer !== link.server
      if (changedServer) {
        nextStatus.location = ""
        nextStatus.load = null
        nextStatus.exitIp = ""
      }
      if (link.server !== "") nextStatus.server = link.server
      if ((!previousActive || changedServer || state !== Model.STATES.connected) && (state !== Model.STATES.stale || !connectedSnapshot)) {
        applyView(connectedView(nextStatus))
      } else if (state === Model.STATES.stale && connectedSnapshot) {
        status = nextStatus
        connectedSnapshot = true
      }
      if (!previousActive || changedServer) requestStatusRefresh()
    } else if (previousActive && !actionRunning) {
      applyView(disconnectedView())
      requestStatusRefresh()
    }
  }

  function refreshCountries(force) {
    if (!installed) return
    if (countriesLoaded && force !== true && countriesError === "" && !countriesLoading) return
    countriesLoading = true
    countriesError = ""
    enqueue({ type: "discovery", kind: "countries", command: ["protonvpn", "countries", "list"], timeout: 30000 })
  }

  function clearCities() {
    cities = []
    citiesCountry = ""
    citiesError = ""
    citiesLoading = false
  }

  function refreshCities(country, force) {
    var code = String(country || "").trim()
    if (code === "") {
      clearCities()
      return
    }
    if (!installed) return
    if (force !== true && citiesCountry === code && cities.length > 0 && citiesError === "" && !citiesLoading) return
    if (force !== true && _citiesCache[code]) {
      // City lists rarely change; Refresh and Retry still force a new read.
      citiesCountry = code
      cities = _citiesCache[code]
      citiesError = ""
      citiesLoading = false
      return
    }
    citiesCountry = code
    cities = []
    citiesError = ""
    citiesLoading = true
    enqueue({ type: "discovery", kind: "cities", country: code, command: ["protonvpn", "cities", "list", code], timeout: 30000, priority: true })
  }

  function refreshConfig() {
    if (!installed) return
    enqueue({ type: "config", kind: "list", command: ["protonvpn", "config", "list"], timeout: 20000 })
  }

  function connectWith(options) {
    if (!canToggle) {
      reportError(Model.writeBlockedReason(state) || "Proton VPN is not ready to connect.")
      return false
    }
    var plan = Model.buildConnectCommand(options)
    if (!plan.ok) {
      reportError(plan.message)
      return false
    }
    return runAction(plan.command, "connect", "Connecting…", options)
  }

  function disconnect() {
    if (!canToggle) {
      reportError(Model.writeBlockedReason(state) || "Proton VPN is not ready to disconnect.")
      return false
    }
    if (state !== Model.STATES.connected) {
      reportError("Proton VPN is not connected.")
      return false
    }
    return runAction(["protonvpn", "disconnect"], "disconnect", "Disconnecting…", null)
  }

  function toggleConnection(options) {
    if (!canToggle) return false
    if (state === Model.STATES.connected) return disconnect()
    return connectWith(options)
  }

  function runAction(command, action, label, options) {
    if (!installed || actionRunning) return false
    if (!Model.canWrite(state)) {
      reportError(Model.writeBlockedReason(state))
      return false
    }
    var job = {
      type: "action",
      action: action,
      command: command,
      timeout: 60000,
      priority: true,
      snapshot: snapshot(),
      options: options || ({})
    }
    if (!enqueue(job)) return false
    lastError = ""
    actionStatus = label || ""
    state = action === "disconnect" ? Model.STATES.disconnecting : Model.STATES.connecting
    return true
  }

  function setConfig(settingName, value, extra) {
    if (!canChangeSettings) {
      reportError(Model.writeBlockedReason(state) || "Proton VPN is not ready for settings changes.")
      return false
    }
    var ctx = extra || ({})
    ctx.connected = Model.isVpnActive(snapshot())
    var plan = Model.buildConfigSetCommand(settingName, value, ctx)
    if (!plan.ok) {
      reportError(plan.message)
      return false
    }
    pendingSetting = settingName
    pendingValue = value
    lastError = ""
    actionStatus = "Updating " + settingName + "…"
    if (!enqueue({ type: "config", kind: "set", setting: settingName, restart: plan.restart === true, command: plan.command, timeout: 20000, priority: true })) {
      pendingSetting = ""
      pendingValue = ""
      return false
    }
    return true
  }

  // Kill Switch changes need the tunnel down. When connected, drop it, change
  // the setting, and reconnect to the same target. A failed change still
  // reconnects, and its error is carried across the reconnect.
  function setKillSwitch(value) {
    if (!Model.isVpnActive(snapshot())) return setConfig("kill-switch", value)
    if (!canChangeSettings) {
      reportError(Model.writeBlockedReason(state) || "Proton VPN is not ready for settings changes.")
      return false
    }
    var check = Model.buildConfigSetCommand("kill-switch", value, { connected: false })
    if (!check.ok) {
      reportError(check.message)
      return false
    }
    _ksValue = String(value)
    _ksTarget = Model.killSwitchReturnTarget(activeTarget, status)
    _ksError = ""
    ksStep = "disconnecting"
    _ksInternal = true
    var started = disconnect()
    _ksInternal = false
    if (!started) {
      ksStep = "idle"
      return false
    }
    pendingSetting = "kill-switch"
    pendingValue = _ksValue
    actionStatus = "Changing Kill Switch…"
    return true
  }

  function advanceKillSwitch(event, message) {
    var step = ksStep
    var next = Model.nextKillSwitchCycleStep(step, event)
    ksStep = next
    if (step === "disconnecting" && next === "idle") {
      pendingSetting = ""
      pendingValue = ""
      reportError("Kill Switch unchanged: " + String(message || "the VPN did not disconnect."))
      return
    }
    if (next === "setting") {
      _ksInternal = true
      var started = setConfig("kill-switch", _ksValue)
      _ksInternal = false
      if (!started) advanceKillSwitch("setFailed", lastError)
      else actionStatus = "Changing Kill Switch…"
      return
    }
    if (next === "reconnecting") {
      if (event === "setFailed") _ksError = "Kill Switch unchanged: " + String(message || "Proton VPN rejected the change.")
      _ksInternal = true
      var reconnecting = connectWith(_ksTarget)
      _ksInternal = false
      if (!reconnecting) {
        ksStep = "idle"
        reportError(_ksError !== "" ? _ksError : "Kill Switch changed, but reconnecting failed. Connect again.")
      } else {
        actionStatus = "Reconnecting to " + Model.killSwitchTargetLabel(_ksTarget) + "…"
      }
      return
    }
    if (step === "reconnecting" && next === "idle") {
      var carried = _ksError
      _ksError = ""
      _ksTarget = null
      if (carried !== "") reportError(carried)
      else if (event === "connected") {
        actionStatus = "Kill Switch changed and reconnected."
        actionStatusTimer.restart()
      }
    }
  }

  // Proton stopped answering as a signed-in CLI (desktop app or sign-out);
  // the cycle cannot finish, so say what state it was left in.
  function abortKillSwitch(message) {
    if (ksStep === "idle") return
    var step = ksStep
    ksStep = "idle"
    _ksTarget = null
    _ksError = ""
    pendingSetting = ""
    pendingValue = ""
    var where = step === "disconnecting" ? "Kill Switch unchanged" : "Kill Switch change interrupted and the VPN is disconnected"
    reportError(where + ": " + String(message || "Proton VPN stopped responding."))
  }

  // Decide whether a tunnel change deserves a desktop notification. Our own
  // actions never report a drop; an open panel already shows every change.
  function noteLink(active, selfInitiated) {
    var now = active === true
    if (_notifiedActive === null) {
      _notifiedActive = now
      return
    }
    if (_notifiedActive === now) return
    var previous = _notifiedActive
    _notifiedActive = now
    var note = Model.linkNotification(previous, now, {
      setting: notificationSetting,
      openPanels: openPanels,
      selfInitiated: selfInitiated === true,
      cycleActive: ksStep !== "idle",
      server: status.server || linkServer,
      location: status.location
    })
    if (!note) return
    Quickshell.execDetached(["notify-send", "--app-name=Proton VPN", "--urgency=" + note.urgency, "--icon=network-vpn-symbolic", "--", note.summary, note.body])
  }

  function sampleTraffic() {
    if (!active || openPanels === 0 || !linkActive || trafficProcess.running) return
    if (!Model.isTunnelDevice(linkDevice)) return
    if (linkDevice !== _trafficDevice || linkServer !== _trafficServer) {
      traffic = Model.emptyTraffic()
      _trafficDevice = linkDevice
      _trafficServer = linkServer
    }
    var base = "/sys/class/net/" + linkDevice + "/statistics/"
    trafficProcess.command = boundedCommand(["/usr/bin/cat", base + "rx_bytes", base + "tx_bytes"], 2000)
    trafficProcess.running = true
  }

  function applyTraffic(result) {
    if (result.exitCode !== 0 || result.timedOut === true) return
    traffic = Model.trafficSample(traffic, Model.parseInterfaceCounters(result.stdout), Date.now())
  }

  function reportError(errorMessage) {
    lastError = String(errorMessage || "Proton VPN command failed")
    actionStatus = lastError
    actionStatusTimer.restart()
  }

  function copyText(value) {
    var text = String(value || "")
    if (text === "") return
    Quickshell.execDetached(["wl-copy", "--", text])
    actionStatus = "Copied"
    actionStatusTimer.restart()
  }

  function openTerminal() {
    Quickshell.execDetached(["omarchy-launch-terminal"])
  }

  function configDisplayValue(key) {
    if (pendingSetting === key) return pendingValue
    return String((configValues && configValues[key]) || "")
  }

  // Each `protonvpn status` opens a new Secret Service connection; poll only
  // when a panel shows the result or nmcli cannot follow the tunnel.
  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: root.active && (root.openPanels > 0 || !root.linkAvailable)
    onTriggered: root.refresh()
  }

  Timer {
    id: trafficTimer
    interval: 2000
    repeat: true
    running: root.active && root.openPanels > 0 && root.linkActive
    triggeredOnStart: true
    onTriggered: root.sampleTraffic()
    onRunningChanged: if (!running) root.traffic = Model.emptyTraffic()
  }

  onActiveChanged: if (active) refresh()
  Component.onCompleted: if (active) refresh()

  Timer {
    id: linkTimer
    interval: root.linkWatchIntervalSec * 1000
    repeat: true
    running: root.active && root.installed
    triggeredOnStart: true
    onTriggered: root.watchLink()
  }

  Timer {
    id: delayedRefresh
    interval: 800
    repeat: false
    onTriggered: root.requestStatusRefresh()
  }

  Timer {
    id: watchdog
    interval: 27000
    repeat: false
    onTriggered: {
      var job = root._currentJob
      if (!job) return
      root._timedOut = true
      if (commandProcess.running) commandProcess.running = false
      root.finishJob({ exitCode: 124, stdout: "", stderr: "Timed out waiting for Proton VPN.", timedOut: true, runId: job.runId })
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 3200
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: commandProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: commandStdout
      waitForEnd: true
      onStreamFinished: root._commandOutput = text
    }
    stderr: StdioCollector {
      id: commandStderr
      waitForEnd: true
      onStreamFinished: root._commandError = text
    }
    onExited: function(exitCode) {
      var errorText = String(commandStderr.text || root._commandError || "")
      root.finishJob({
        exitCode: exitCode,
        stdout: String(commandStdout.text || root._commandOutput || ""),
        stderr: errorText,
        timedOut: exitCode === 124 && /command timed out/i.test(errorText),
        runId: root._commandRunId
      })
      // A watchdog kill finishes its job early, but Quickshell keeps `running`
      // true (and defers any restart) until the process really exits. Nothing
      // else wakes the queue after that late exit, so resume it here.
      if (!root._currentJob) Qt.callLater(root.pump)
    }
  }

  Process {
    id: trafficProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: trafficStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.applyTraffic({ exitCode: exitCode, stdout: String(trafficStdout.text || ""), timedOut: exitCode === 124 })
    }
  }

  Process {
    id: linkProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: linkStdout
      waitForEnd: true
      onStreamFinished: root._linkOutput = text
    }
    stderr: StdioCollector {
      id: linkStderr
      waitForEnd: true
      onStreamFinished: root._linkError = text
    }
    onExited: function(exitCode) {
      var errorText = String(linkStderr.text || root._linkError || "")
      root.applyLinkResult({
        exitCode: exitCode,
        stdout: String(linkStdout.text || root._linkOutput || ""),
        stderr: errorText,
        timedOut: exitCode === 124 && /command timed out/i.test(errorText)
      })
    }
  }
}
