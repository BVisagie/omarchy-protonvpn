import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model
import "Scheduler.js" as Scheduler

Item {
  id: root

  property var settings: ({})

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
  readonly property bool processBusy: whichProcess.running || statusProcess.running || actionProcess.running || discoveryProcess.running || configProcess.running
  readonly property bool actionRunning: actionProcess.running || (_currentJob && _currentJob.type === "action") || Scheduler.hasAction(_queueState)
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
  readonly property bool canToggle: Model.canWrite(state) && !actionRunning
  readonly property bool canChangeSettings: canToggle

  property var _queueState: Scheduler.emptyQueue()
  property var _currentJob: null
  property int _whichRunId: 0
  property int _statusRunId: 0
  property int _actionRunId: 0
  property int _discoveryRunId: 0
  property int _configRunId: 0
  property bool _timedOut: false
  property bool _pendingStatusRefresh: false
  property string _statusOutput: ""
  property string _statusError: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property string _discoveryOutput: ""
  property string _discoveryError: ""
  property string _configOutput: ""
  property string _configError: ""
  property bool _whichChecked: false

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

  function applyView(next) {
    if (!next) return
    var previousConnected = connectedSnapshot === true
    state = String(next.state || Model.STATES.error)
    kind = String(next.kind || "")
    message = String(next.message || "")
    detail = String(next.detail || "")
    stale = next.stale === true
    status = next.status || Model.emptyStatus()
    signedIn = next.signedIn === true
    connectedSnapshot = next.connectedSnapshot === true
    if (state === Model.STATES.connected || state === Model.STATES.disconnected) {
      lastUpdatedMs = Date.now()
      lastError = ""
      if (state === Model.STATES.connected && previousConnected === false) restartNotice = ""
    } else if (message !== "") {
      lastError = message
    }
  }

  function enqueue(job) {
    var result = Scheduler.enqueueJob(_queueState, job)
    _queueState = result.queue
    if (!result.accepted) return false
    pump()
    return true
  }

  function pump() {
    if (processBusy) return
    if (_queueState.current) return
    var started = Scheduler.beginJob(_queueState)
    _queueState = started.queue
    if (!started.started) {
      _currentJob = null
      watchdog.stop()
      if (_pendingStatusRefresh) {
        _pendingStatusRefresh = false
        enqueue({ type: "status", command: ["protonvpn", "status"] })
      }
      return
    }
    startJob(started.job)
  }

  function startJob(job) {
    _timedOut = false
    _currentJob = job
    watchdog.interval = Scheduler.timeoutFor(job)
    watchdog.restart()
    if (job.type === "which") {
      _whichRunId = job.runId
      whichProcess.command = job.command
      whichProcess.running = true
      return
    }
    if (job.type === "status") {
      _statusRunId = job.runId
      _statusOutput = ""
      _statusError = ""
      refreshing = true
      statusProcess.command = job.command
      statusProcess.running = true
      return
    }
    if (job.type === "action") {
      _actionRunId = job.runId
      _actionOutput = ""
      _actionError = ""
      actionProcess.command = job.command
      actionProcess.running = true
      return
    }
    if (job.type === "discovery") {
      _discoveryRunId = job.runId
      _discoveryOutput = ""
      _discoveryError = ""
      discoveryProcess.command = job.command
      discoveryProcess.running = true
      return
    }
    if (job.type === "config") {
      _configRunId = job.runId
      _configOutput = ""
      _configError = ""
      configProcess.command = job.command
      configProcess.running = true
      return
    }
    finishJob({ exitCode: 1, stdout: "", stderr: "Unknown job type", timedOut: false, runId: job.runId })
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
    else if (job.type === "status") handleStatus(result)
    else if (job.type === "action") handleAction(result, job)
    else if (job.type === "discovery") handleDiscovery(result, job)
    else if (job.type === "config") handleConfig(result, job)
    Qt.callLater(pump)
  }

  function handleWhich(result) {
    _whichChecked = true
    installed = result.exitCode === 0 && result.timedOut !== true
    if (!installed) {
      applyView(Model.classifyProbe({ cliMissing: true, exitCode: result.exitCode, stdout: "", stderr: "", timedOut: result.timedOut === true }))
      return
    }
    requestStatusRefresh()
  }

  function handleStatus(result) {
    if (!installed) {
      applyView(Model.classifyProbe({ cliMissing: true }))
      return
    }
    var view = Model.classifyProbe({
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
      timedOut: result.timedOut === true
    }, snapshot())
    applyView(view)
    if (view.state === Model.STATES.connected || view.state === Model.STATES.disconnected) {
      if (!configLoaded) refreshConfig()
    }
  }

  function handleAction(result, job) {
    var classified = Model.classifyCommandResult({
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
      timedOut: result.timedOut === true
    }, snapshot())
    if (classified.stateHint === Model.STATES.guiConflict || classified.stateHint === Model.STATES.signedOut) {
      applyView(Model.classifyProbe({
        exitCode: result.exitCode,
        stdout: result.stdout,
        stderr: result.stderr,
        timedOut: result.timedOut === true
      }, job.snapshot || snapshot()))
      actionStatus = ""
      delayedRefresh.restart()
      return
    }
    if (classified.ok) {
      lastError = ""
      actionStatus = classified.message || (job.action === "disconnect" ? "Disconnected." : "Connected.")
    } else {
      lastError = classified.message
      actionStatus = classified.message
      if (job.snapshot) applyView(job.snapshot)
      lastError = classified.message
    }
    actionStatusTimer.restart()
    delayedRefresh.restart()
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
      if (result.timedOut === true || result.exitCode !== 0) {
        countriesError = classified.message || "Could not list countries."
        if (countries.length > 0) discoveryStale = true
        return
      }
      var parsedCountries = Model.parseCountries(result.stdout)
      if (!parsedCountries.ok) {
        countriesError = parsedCountries.message
        if (countries.length === 0) countriesError = parsedCountries.message
        return
      }
      countries = parsedCountries.countries
      countriesLoaded = true
      countriesError = parsedCountries.countries.length === 0 ? "No countries returned." : ""
      discoveryStale = false
      return
    }
    if (job.kind === "cities") {
      if (String(job.country || "") !== citiesCountry) return
      citiesLoading = false
      if (result.timedOut === true || result.exitCode !== 0) {
        citiesError = classified.message || "Could not list cities."
        if (cities.length > 0) discoveryStale = true
        return
      }
      var parsedCities = Model.parseCities(result.stdout)
      if (!parsedCities.ok) {
        citiesError = parsedCities.message
        cities = []
        return
      }
      cities = parsedCities.cities
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
      return
    }
    if (job.kind === "list") {
      if (result.exitCode !== 0 || result.timedOut === true) {
        configError = classified.message || "Could not read Proton VPN settings."
        return
      }
      var parsed = Model.parseConfigList(result.stdout)
      if (!parsed.ok) {
        configError = parsed.message
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
      enqueue({ type: "which", command: ["which", "protonvpn"], timeout: 5000 })
      return
    }
    requestStatusRefresh()
  }

  function refreshCountries(force) {
    if (!installed) return
    if (countriesLoaded && force !== true && countriesError === "" && !countriesLoading) return
    countriesLoading = true
    countriesError = ""
    enqueue({ type: "discovery", kind: "countries", command: ["protonvpn", "countries", "list"], timeout: 30000 })
  }

  function refreshCities(country, force) {
    var code = String(country || "").trim()
    if (!installed || code === "") return
    if (force !== true && citiesCountry === code && cities.length > 0 && citiesError === "" && !citiesLoading) return
    citiesCountry = code
    cities = []
    citiesError = ""
    citiesLoading = true
    enqueue({ type: "discovery", kind: "cities", country: code, command: ["protonvpn", "cities", "list", code], timeout: 30000 })
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
    return runAction(plan.command, "connect", "Connecting…")
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
    return runAction(["protonvpn", "disconnect"], "disconnect", "Disconnecting…")
  }

  function toggleConnection(options) {
    if (!canToggle) return false
    if (state === Model.STATES.connected) return disconnect()
    return connectWith(options)
  }

  function runAction(command, action, label) {
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
      snapshot: snapshot()
    }
    if (!enqueue(job)) return false
    lastError = ""
    actionStatus = label || ""
    state = action === "disconnect" ? Model.STATES.disconnecting : Model.STATES.connecting
    return true
  }

  function setConfig(setting, value, extra) {
    if (!canChangeSettings) {
      reportError(Model.writeBlockedReason(state) || "Proton VPN is not ready for settings changes.")
      return false
    }
    var ctx = extra || {}
    ctx.connected = Model.isVpnActive(snapshot())
    var plan = Model.buildConfigSetCommand(setting, value, ctx)
    if (!plan.ok) {
      reportError(plan.message)
      return false
    }
    pendingSetting = setting
    pendingValue = value
    lastError = ""
    actionStatus = "Updating " + setting + "…"
    if (!enqueue({ type: "config", kind: "set", setting: setting, restart: plan.restart === true, command: plan.command, timeout: 20000 })) {
      pendingSetting = ""
      pendingValue = ""
      return false
    }
    return true
  }

  function reportError(message) {
    lastError = String(message || "Proton VPN command failed")
    actionStatus = lastError
    actionStatusTimer.restart()
  }

  function copyText(value) {
    var text = String(value || "")
    if (text === "") return
    Quickshell.execDetached(["wl-copy", text])
    actionStatus = "Copied command"
    actionStatusTimer.restart()
  }

  function openTerminal() {
    Quickshell.execDetached(["omarchy-launch-terminal"])
  }

  function configDisplayValue(key) {
    if (pendingSetting === key) return pendingValue
    return String((configValues && configValues[key]) || "")
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: delayedRefresh
    interval: 800
    repeat: false
    onTriggered: root.requestStatusRefresh()
  }

  Timer {
    id: watchdog
    interval: 25000
    repeat: false
    onTriggered: {
      var job = root._currentJob
      if (!job) return
      root._timedOut = true
      if (whichProcess.running) whichProcess.running = false
      if (statusProcess.running) statusProcess.running = false
      if (actionProcess.running) actionProcess.running = false
      if (discoveryProcess.running) discoveryProcess.running = false
      if (configProcess.running) configProcess.running = false
      root.finishJob({ exitCode: 1, stdout: "", stderr: "Timed out waiting for Proton VPN.", timedOut: true, runId: job.runId })
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 3200
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: whichProcess
    running: false
    command: []
    onExited: function(exitCode) {
      root.finishJob({ exitCode: exitCode, stdout: "", stderr: "", timedOut: false, runId: root._whichRunId })
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      root.finishJob({
        exitCode: exitCode,
        stdout: String(statusStdout.text || root._statusOutput || ""),
        stderr: String(statusStderr.text || root._statusError || ""),
        timedOut: false,
        runId: root._statusRunId
      })
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true; onStreamFinished: root._actionOutput = text }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true; onStreamFinished: root._actionError = text }
    onExited: function(exitCode) {
      root.finishJob({
        exitCode: exitCode,
        stdout: String(actionStdout.text || root._actionOutput || ""),
        stderr: String(actionStderr.text || root._actionError || ""),
        timedOut: false,
        runId: root._actionRunId
      })
    }
  }

  Process {
    id: discoveryProcess
    running: false
    command: []
    stdout: StdioCollector { id: discoveryStdout; waitForEnd: true; onStreamFinished: root._discoveryOutput = text }
    stderr: StdioCollector { id: discoveryStderr; waitForEnd: true; onStreamFinished: root._discoveryError = text }
    onExited: function(exitCode) {
      root.finishJob({
        exitCode: exitCode,
        stdout: String(discoveryStdout.text || root._discoveryOutput || ""),
        stderr: String(discoveryStderr.text || root._discoveryError || ""),
        timedOut: false,
        runId: root._discoveryRunId
      })
    }
  }

  Process {
    id: configProcess
    running: false
    command: []
    stdout: StdioCollector { id: configStdout; waitForEnd: true; onStreamFinished: root._configOutput = text }
    stderr: StdioCollector { id: configStderr; waitForEnd: true; onStreamFinished: root._configError = text }
    onExited: function(exitCode) {
      root.finishJob({
        exitCode: exitCode,
        stdout: String(configStdout.text || root._configOutput || ""),
        stderr: String(configStderr.text || root._configError || ""),
        timedOut: false,
        runId: root._configRunId
      })
    }
  }
}
