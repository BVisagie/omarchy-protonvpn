import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs.Commons
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

  // The plugin's own strings, following Setup > Language live. Messages kept
  // in properties are worded once, when they happen.
  readonly property QtObject strings: Translations { directory: Qt.resolvedUrl("i18n") }
  function tr(key, english) { return root.strings.t(key, english) }
  readonly property var loc: ({
    tr: function(key, english) { return root.strings.t(key, english) },
    tn: function(key, count, english) { return root.strings.tn(key, count, english) },
    num: function(value, places) { return I18n.formatNumber(value, places) }
  })

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
  property bool linkKillSwitch: false
  // When NetworkManager activated the tunnel; 0 when unknown.
  property double linkSinceMs: 0
  readonly property bool killSwitchBlocking: Model.killSwitchBlocking({ known: linkKnown, available: linkAvailable, active: linkActive, killSwitch: linkKillSwitch }, state)
  property var recentTargets: []
  // Starred targets live in the widget's shell.json entry. Recents stay in
  // memory unless rememberRecent is on, which also keeps the last target.
  readonly property var favorites: Model.normalizeTargets(setting("favorites", []), Model.MAX_FAVORITES)
  readonly property bool rememberRecent: Model.normalizeBooleanSetting(setting("rememberRecent", false))
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

  // Reconnect on drop: the target, the attempt in the backoff schedule, and
  // the last connection the tunnel had before a status check cleared it.
  readonly property bool reconnectOnDrop: Model.normalizeBooleanSetting(setting("reconnectOnDrop", false))
  property var _reconnectTarget: null
  property int _reconnectAttempt: 0
  property bool _reconnectFallback: false
  property bool _disconnectAfterReconnect: false
  property bool _autoInternal: false
  property var _lastSession: null
  readonly property bool reconnectPending: _reconnectTarget !== null

  // Connect at login: once, at the first shell start after logging in. The
  // runner's lock file in XDG_RUNTIME_DIR (cleared at logout) already
  // exists when the shell merely reloaded, as it does for a theme change.
  readonly property bool connectOnLogin: Model.normalizeBooleanSetting(setting("connectOnLogin", false))
  readonly property string _runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  property bool _loginConnectPending: false
  // True when the lock file already existed: the shell reloaded mid-login.
  property bool _shellReloaded: false

  // Connect on untrusted Wi-Fi: joining a network that is not in
  // trustedNetworks connects, once per join. The name comes from
  // NetworkManager over D-Bus, through Quickshell; no process starts.
  readonly property bool autoConnectWifi: Model.normalizeBooleanSetting(setting("autoConnectWifi", false))
  readonly property var trustedNetworks: Model.normalizeNetworks(setting("trustedNetworks", []))
  readonly property string wifiName: currentWifiName()
  readonly property bool wifiTrusted: Model.isTrustedNetwork(trustedNetworks, wifiName)
  property bool _wifiConnectPending: false
  property bool _started: false
  property double _startedMs: 0
  readonly property bool autoConnectArmed: (connectOnLogin && _loginConnectPending) || (autoConnectWifi && _wifiConnectPending)

  // Shared by both: ticks and attempts of the current automatic connect.
  property int _autoTicks: 0
  property int _autoAttempts: 0
  // "login" or "wifi" while tryAutoConnect starts a connect; jobs keep it.
  property string _autoConnectKind: ""

  property int _setupChecks: 0
  property string portForwardingNotice: ""

  property var traffic: Model.emptyTraffic()
  property string _trafficDevice: ""
  property string _trafficServer: ""
  // Data going out with nothing coming back; read even with every panel closed.
  property var health: Model.emptyHealth()
  readonly property bool tunnelStalled: linkActive && state === Model.STATES.connected && health.stalled === true
  // Only a validated proton0-style device ever reaches a sysfs path.
  readonly property string _statsDir: Model.isTunnelDevice(linkDevice) ? "/sys/class/net/" + linkDevice + "/statistics/" : ""
  readonly property string trafficText: Model.trafficText(traffic, loc)
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
  readonly property bool freePlan: Model.isFreePlan(configUpgrade)
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
  readonly property bool actionBusy: actionRunning || ksStep !== "idle"
  readonly property var view: ({
    state: root.state,
    kind: root.kind,
    message: root.message,
    detail: root.detail,
    stale: root.stale,
    status: root.status,
    signedIn: root.signedIn,
    lastUpdatedMs: root.lastUpdatedMs,
    connectedSnapshot: root.connectedSnapshot,
    blocking: root.killSwitchBlocking,
    stalled: root.tunnelStalled
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
  // A change seen while a poll runs is read again once that poll ends.
  property bool _linkRecheck: false
  // `nmcli monitor` restarts with backoff; a run that lasted resets it.
  property int _monitorFailures: 0
  property double _monitorStartedMs: 0
  readonly property bool linkEvents: linkMonitor.running

  function panelOpened() {
    openPanels = openPanels + 1
  }

  function panelClosed() {
    openPanels = Math.max(0, openPanels - 1)
  }

  function setSettings(next) {
    settings = next || ({})
  }

  // The whole entry is replaced, so start from the live settings. Applied
  // locally first; the shell.json write comes back as the same value.
  function saveSettings(patch) {
    var entry = ({})
    for (var key in settings) if (key !== "id") entry[key] = settings[key]
    for (var name in patch) {
      if (patch[name] === undefined) delete entry[name]
      else entry[name] = patch[name]
    }
    settings = entry
    if (shell && typeof shell.updateEntryInline === "function") shell.updateEntryInline(Model.PLUGIN_ID, entry)
  }

  function toggleFavorite(target) {
    saveSettings({ favorites: Model.toggleFavorite(favorites, target) })
  }

  // Turned on, including when settings first arrive: a session with no
  // recents yet reads the saved ones; one that has some saves them.
  onRememberRecentChanged: {
    if (rememberRecent) {
      if (recentTargets.length === 0) recentTargets = Model.normalizeTargets(setting("recent", []), Model.MAX_RECENTS)
      else saveSettings({ recent: Model.normalizeTargets(recentTargets, Model.MAX_RECENTS) })
    } else if (setting("recent", undefined) !== undefined) {
      saveSettings({ recent: undefined })
    }
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
    var previousTarget = activeTarget
    var previousServer = String(status.server || "")
    state = String(next.state || Model.STATES.error)
    kind = String(next.kind || "")
    message = String(next.message || "")
    detail = String(next.detail || "")
    stale = next.stale === true
    status = statusCopy(next.status || Model.emptyStatus())
    signedIn = next.signedIn === true
    connectedSnapshot = next.connectedSnapshot === true
    if (state === Model.STATES.disconnected) {
      // A status check can notice a drop before nmcli does; keep where the
      // tunnel was so a reconnect can return there.
      if (previousConnected) _lastSession = { target: previousTarget, status: { server: previousServer } }
      activeTarget = null
      portForwardingNotice = ""
    }
    // Settings, and the plan inferred from them, belong to the signed-out
    // account; the next healthy status reloads them.
    if (state === Model.STATES.signedOut) forgetAccountSettings()
    if (state === Model.STATES.connected || state === Model.STATES.disconnected) {
      lastUpdatedMs = Date.now()
      lastError = ""
      if (state === Model.STATES.connected && previousConnected === false) restartNotice = ""
    } else if (message !== "") {
      lastError = message
    }
  }

  function forgetAccountSettings() {
    configValues = ({})
    configUpgrade = ({})
    configLoaded = false
    _lastSession = null
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

  // The queue serializes one service; the lock also covers a second shell,
  // such as a reload whose old CLI run has not finished yet.
  function boundedCommand(command, timeoutMs) {
    var seconds = Math.max(1, Math.ceil(Number(timeoutMs || 20000) / 1000))
    var runner = ["/usr/bin/python3", runnerPath, "--max-bytes", "262144", "--max-seconds", String(seconds)]
    if (command && command[0] === "protonvpn") runner.push("--lock")
    return runner.concat(["--"]).concat(prepareCommand(command))
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
    if (_reconnectTarget === null || !reconnectOnDrop) dropQueuedReconnect()
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
      applyView(Model.classifyProbe({ cliMissing: true, exitCode: result.exitCode, stdout: "", stderr: "", timedOut: result.timedOut === true }, null, loc))
      return
    }
    enqueue({ type: "help", command: ["protonvpn", "--help"], timeout: 5000 })
    requestStatusRefresh()
    watchLink()
    startLinkMonitor()
  }

  function handleHelp(result) {
    var info = result.exitCode === 0 && result.timedOut !== true
      ? Model.parseCliHelp(result.stdout) : Model.parseCliHelp("")
    cliVersion = info.version
    cliCommands = info.commands
    compatibilityWarning = Model.compatibilityWarning(info, loc)
  }

  function handleStatus(result) {
    if (!installed) {
      applyView(Model.classifyProbe({ cliMissing: true }, null, loc))
      return
    }
    var previous = snapshot()
    var next = Model.classifyProbe({
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
      timedOut: result.timedOut === true
    }, previous, loc)
    if (next.state === Model.STATES.connected) {
      if (previous.status && previous.status.server === next.status.server) next.status.exitIp = String(previous.status.exitIp || "")
      if (linkConfirmed() && linkServer !== "" && next.status.server === "") next.status.server = linkServer
      applyView(next)
    } else if (next.state === Model.STATES.disconnected && linkConfirmed() && ksStep === "idle") {
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
    var automatic = job.auto === true || job.autoConnect !== ""
    var disconnectAfter = automatic && _disconnectAfterReconnect
    if (automatic) _disconnectAfterReconnect = false
    var classified = Model.classifyCommandResult(result, job.snapshot || snapshot(), loc)
    if (classified.stateHint === Model.STATES.guiConflict || classified.stateHint === Model.STATES.signedOut) {
      applyView(Model.classifyProbe(result, job.snapshot || snapshot(), loc))
      actionStatus = ""
      delayedRefresh.restart()
      abortKillSwitch(classified.message)
      if (job.auto === true) cancelReconnect()
      return
    }
    if (classified.ok) {
      lastError = ""
      actionStatus = classified.message || (job.action === "disconnect" ? tr("action.disconnected", "Disconnected.") : tr("action.connected", "Connected."))
      if (job.action === "signout") {
        applyView(Model.signedOutView(loc))
      } else if (job.action === "disconnect") {
        linkActive = false
        linkServer = ""
        linkDevice = ""
        linkSinceMs = 0
        applyView(disconnectedView())
        _lastSession = null
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
        var target = Model.recentTarget(job.options || {}, outcome, loc)
        activeTarget = target
        recentTargets = Model.recordRecentTarget(recentTargets, target, Model.MAX_RECENTS)
        if (rememberRecent) saveSettings({ recent: Model.normalizeTargets(recentTargets, Model.MAX_RECENTS) })
        portForwardingNotice = Model.portForwardingNotice(outcome.portForwarding, loc)
        noteLink(true, true)
        if (job.auto === true) {
          cancelReconnect()
          actionStatus = tr("action.reconnected", "Reconnected after the drop.")
          if (disconnectAfter) Qt.callLater(disconnect)
        } else if (disconnectAfter) {
          Qt.callLater(disconnect)
        }
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
      if (job.auto === true) scheduleNextReconnect()
    }
    actionStatusTimer.restart()
    watchLink()
    // Mid-cycle, the next write matters more than a status refresh.
    if (!(ksStep === "disconnecting" && job.action === "disconnect" && classified.ok)) delayedRefresh.restart()
    if (ksStep !== "idle") advanceKillSwitch(job.action === "disconnect"
      ? (classified.ok ? "disconnected" : "disconnectFailed")
      : (classified.ok ? "connected" : "connectFailed"), classified.message)
  }

  function handleDiscovery(result, job) {
    var classified = Model.classifyCommandResult(result, snapshot(), loc)
    if (classified.stateHint === Model.STATES.signedOut || classified.stateHint === Model.STATES.guiConflict) {
      applyView(Model.classifyProbe(result, snapshot(), loc))
      countriesLoading = false
      citiesLoading = false
      return
    }
    if (job.kind === "countries") {
      countriesLoading = false
      if (!Model.readSucceeded(result)) {
        countriesError = classified.message || tr("discovery.countriesFailed", "Could not list countries.")
        if (countries.length > 0) discoveryStale = true
        return
      }
      var countriesCrashed = Model.crashedAfterOutput(result)
      var parsedCountries = Model.parseCountries(result.stdout, loc)
      if (!parsedCountries.ok || (countriesCrashed && parsedCountries.countries.length === 0)) {
        countriesError = countriesCrashed ? (classified.message || tr("discovery.countriesFailed", "Could not list countries.")) : parsedCountries.message
        if (countriesCrashed && countries.length > 0) discoveryStale = true
        return
      }
      countries = parsedCountries.countries
      // A table has no end marker, so crashed output is shown but fetched again.
      countriesLoaded = !countriesCrashed
      countriesError = parsedCountries.countries.length === 0 ? tr("discovery.noCountries", "No countries returned.") : ""
      discoveryStale = false
      return
    }
    if (job.kind === "cities") {
      if (String(job.country || "") !== citiesCountry) return
      citiesLoading = false
      if (!Model.readSucceeded(result)) {
        citiesError = classified.message || tr("discovery.citiesFailed", "Could not list cities.")
        if (cities.length > 0) discoveryStale = true
        return
      }
      var citiesCrashed = Model.crashedAfterOutput(result)
      var parsedCities = Model.parseCities(result.stdout, loc)
      if (!parsedCities.ok || (citiesCrashed && parsedCities.cities.length === 0)) {
        if (citiesCrashed) {
          citiesError = classified.message || tr("discovery.citiesFailed", "Could not list cities.")
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
      citiesError = parsedCities.cities.length === 0 ? tr("discovery.noCities", "No cities returned for that country.") : ""
      discoveryStale = false
    }
  }

  function handleConfig(result, job) {
    var classified = Model.classifyCommandResult(result, snapshot(), loc)
    if (classified.stateHint === Model.STATES.signedOut || classified.stateHint === Model.STATES.guiConflict) {
      pendingSetting = ""
      pendingValue = ""
      applyView(Model.classifyProbe(result, snapshot(), loc))
      if (job.kind === "set") abortKillSwitch(classified.message)
      return
    }
    if (job.kind === "list") {
      if (!Model.readSucceeded(result)) {
        configError = classified.message || tr("config.readFailed", "Could not read Proton VPN settings.")
        return
      }
      var configCrashed = Model.crashedAfterOutput(result)
      var parsed = Model.parseConfigList(result.stdout, loc)
      if (!parsed.ok || (configCrashed && !Model.configListComplete(parsed))) {
        configError = configCrashed ? (classified.message || tr("config.readFailed", "Could not read Proton VPN settings.")) : parsed.message
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
        actionStatus = classified.message || tr("config.updated", "Setting updated.")
        restartNotice = job.restart === true ? Model.restartNotice(job.setting, loc) : ""
        if (/please establish a new VPN connection/i.test(classified.detail)) restartNotice = classified.detail
      } else {
        lastError = classified.message
        actionStatus = classified.message
      }
      pendingSetting = ""
      pendingValue = ""
      actionStatusTimer.restart()
      // Reconnect first: the tunnel is down until it runs.
      if (ksStep === "setting" && job.setting === "kill-switch") advanceKillSwitch(classified.ok ? "set" : "setFailed", classified.message)
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
    if (!active || !installed) return
    if (linkProcess.running) {
      _linkRecheck = true
      return
    }
    _linkRecheck = false
    _linkStartedEpoch = _linkEpoch
    _linkOutput = ""
    _linkError = ""
    linkProcess.command = boundedCommand(["/usr/bin/nmcli", "-t", "-e", "no", "-f", "NAME,TYPE,DEVICE,STATE,TIMESTAMP", "connection", "show", "--active"], 5000)
    linkProcess.running = true
  }

  // NetworkManager prints a line for every device, connection, or
  // connectivity change. The text is localized, so any line only means
  // "look again"; the snapshot below is what gets parsed.
  function startLinkMonitor() {
    if (!active || !installed || linkMonitor.running) return
    _monitorStartedMs = Date.now()
    linkMonitor.running = true
  }

  function linkMonitorExited() {
    if (!active || !installed) return
    if (Date.now() - _monitorStartedMs > 60000) _monitorFailures = 0
    monitorRestart.interval = Model.monitorRestartDelayMs(_monitorFailures)
    _monitorFailures++
    monitorRestart.restart()
    watchLink()
  }

  function applyLinkResult(result) {
    if (_linkRecheck) Qt.callLater(watchLink)
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
    linkKillSwitch = link.killSwitch === true
    // NetworkManager may refresh TIMESTAMP while a connection stays up;
    // the same tunnel keeps its first one.
    var sameTunnel = previousActive && link.active && previousServer === link.server && linkSinceMs > 0
    linkSinceMs = !link.active ? 0 : (sameTunnel && link.sinceMs > 0 ? Math.min(linkSinceMs, link.sinceMs) : link.sinceMs)
    // The Kill Switch cycle owns the tunnel between its actions too.
    var owned = actionRunning || ksStep !== "idle"
    noteLink(link.active, owned)
    // NetworkManager can briefly continue reporting the old tunnel while a
    // connect, server change, or disconnect is in flight. Keep the live facts,
    // but let the action result own the transitional UI state.
    if (owned) return
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
      reportError(Model.writeBlockedReason(state, loc) || tr("blocked.connect", "Proton VPN is not ready to connect."))
      return false
    }
    var blocked = Model.planBlockedReason((options || {}).mode, freePlan, loc)
    if (blocked !== "") {
      reportError(blocked)
      // The plan is inferred from cached settings; re-read them in case the
      // account changed where this service could not see it.
      refreshConfig()
      return false
    }
    var plan = Model.buildConnectCommand(options, loc)
    if (!plan.ok) {
      reportError(plan.message)
      return false
    }
    return runAction(plan.command, "connect", tr("action.connecting", "Connecting…"), options)
  }

  function disconnect() {
    // Asking to disconnect while a reconnect waits means staying disconnected,
    // even though there is no tunnel to take down yet.
    var stoppedReconnect = false
    var automaticRunning = !!_currentJob && (_currentJob.auto === true || !!_currentJob.autoConnect)
    if (!_ksInternal && (reconnectPending || autoConnectArmed || automaticRunning || autoConnectQueued())) {
      if (automaticRunning) _disconnectAfterReconnect = true
      cancelReconnect()
      cancelAutoConnect("")
      stoppedReconnect = true
    }
    if (!canToggle) {
      if (stoppedReconnect) return noteReconnectStopped()
      reportError(Model.writeBlockedReason(state, loc) || tr("blocked.disconnect", "Proton VPN is not ready to disconnect."))
      return false
    }
    if (state !== Model.STATES.connected) {
      if (stoppedReconnect) return noteReconnectStopped()
      reportError(tr("action.notConnected", "Proton VPN is not connected."))
      return false
    }
    return runAction(["protonvpn", "disconnect"], "disconnect", tr("action.disconnecting", "Disconnecting…"), null)
  }

  // Only from Disconnected: the CLI would drop a live tunnel itself, but
  // asking first keeps Kill Switch and reconnects out of it.
  function signOut() {
    if (state !== Model.STATES.disconnected) {
      reportError(tr("signout.disconnectFirst", "Disconnect before signing out."))
      return false
    }
    return runAction(["protonvpn", "signout"], "signout", tr("signout.running", "Signing out…"), null)
  }

  function noteReconnectStopped() {
    actionStatus = _disconnectAfterReconnect
      ? tr("reconnect.disconnectAfter", "Disconnecting once the current reconnect attempt finishes…")
      : tr("reconnect.cancelled", "Automatic connection cancelled.")
    actionStatusTimer.restart()
    return true
  }

  function toggleConnection(options) {
    if (!canToggle) return false
    if (state === Model.STATES.connected) return disconnect()
    return connectWith(options)
  }

  function runAction(command, action, label, options) {
    if (!installed || actionRunning) return false
    if (!Model.canWrite(state)) {
      reportError(Model.writeBlockedReason(state, loc))
      return false
    }
    var job = {
      type: "action",
      action: action,
      command: command,
      timeout: 60000,
      priority: true,
      snapshot: snapshot(),
      options: options || ({}),
      auto: _autoInternal === true,
      autoConnect: _autoConnectKind
    }
    if (!enqueue(job)) return false
    if (job.auto !== true) cancelReconnect()
    // Anything the user does wins over the login connect.
    if (job.autoConnect === "") cancelAutoConnect("")
    lastError = ""
    actionStatus = label || ""
    if (action === "connect") state = Model.STATES.connecting
    else if (action === "disconnect") state = Model.STATES.disconnecting
    return true
  }

  function setConfig(settingName, value, extra) {
    if (!canChangeSettings) {
      reportError(Model.writeBlockedReason(state, loc) || tr("blocked.settings", "Proton VPN is not ready for settings changes."))
      return false
    }
    var ctx = extra || ({})
    ctx.connected = Model.isVpnActive(snapshot())
    var plan = Model.buildConfigSetCommand(settingName, value, ctx, loc)
    if (!plan.ok) {
      reportError(plan.message)
      return false
    }
    pendingSetting = settingName
    pendingValue = value
    lastError = ""
    actionStatus = tr("config.updating", "Updating %1…").arg(Model.settingLabel(settingName, loc))
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
      reportError(Model.writeBlockedReason(state, loc) || tr("blocked.settings", "Proton VPN is not ready for settings changes."))
      return false
    }
    var check = Model.buildConfigSetCommand("kill-switch", value, { connected: false }, loc)
    if (!check.ok) {
      reportError(check.message)
      return false
    }
    _ksValue = String(value)
    _ksTarget = Model.returnTarget(activeTarget, status, freePlan)
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
    actionStatus = tr("killSwitch.changing", "Changing Kill Switch…")
    return true
  }

  function advanceKillSwitch(event, message) {
    var step = ksStep
    var next = Model.nextKillSwitchCycleStep(step, event)
    ksStep = next
    if (step === "disconnecting" && next === "idle") {
      pendingSetting = ""
      pendingValue = ""
      reportError(tr("killSwitch.unchanged", "Kill Switch unchanged: %1").arg(String(message || tr("killSwitch.noDisconnect", "the VPN did not disconnect."))))
      return
    }
    if (next === "setting") {
      _ksInternal = true
      var started = setConfig("kill-switch", _ksValue)
      _ksInternal = false
      if (!started) advanceKillSwitch("setFailed", lastError)
      else actionStatus = tr("killSwitch.changing", "Changing Kill Switch…")
      return
    }
    if (next === "reconnecting") {
      if (event === "setFailed") _ksError = tr("killSwitch.unchanged", "Kill Switch unchanged: %1").arg(String(message || tr("killSwitch.rejected", "Proton VPN rejected the change.")))
      _ksInternal = true
      var reconnecting = connectWith(_ksTarget)
      _ksInternal = false
      if (!reconnecting) {
        ksStep = "idle"
        reportError(_ksError !== "" ? _ksError : tr("killSwitch.reconnectFailed", "Kill Switch changed, but reconnecting failed. Connect again."))
      } else {
        actionStatus = tr("reconnect.to", "Reconnecting to %1…").arg(Model.returnTargetLabel(_ksTarget, loc))
      }
      return
    }
    if (step === "reconnecting" && next === "idle") {
      var carried = _ksError
      _ksError = ""
      _ksTarget = null
      if (event === "connectFailed") reportError(carried !== "" ? carried + " " + tr("killSwitch.alsoFailed", "Reconnecting also failed. Connect again.") : tr("killSwitch.reconnectFailed", "Kill Switch changed, but reconnecting failed. Connect again."))
      else if (carried !== "") reportError(carried)
      else {
        actionStatus = tr("killSwitch.done", "Kill Switch changed and reconnected.")
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
    var why = String(message || tr("killSwitch.stopped", "Proton VPN stopped responding."))
    reportError(step === "disconnecting"
      ? tr("killSwitch.unchanged", "Kill Switch unchanged: %1").arg(why)
      : tr("killSwitch.interrupted", "Kill Switch change interrupted and the VPN is disconnected: %1").arg(why))
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
    var dropped = previous === true && !now && selfInitiated !== true && ksStep === "idle"
    if (now) cancelReconnect()
    else if (dropped && reconnectOnDrop) armReconnect()
    sendNotification(Model.linkNotification(previous, now, {
      setting: notificationSetting,
      openPanels: openPanels,
      selfInitiated: selfInitiated === true,
      cycleActive: ksStep !== "idle",
      killSwitch: linkKillSwitch,
      reconnecting: reconnectPending,
      server: status.server || linkServer,
      location: status.location
    }, loc))
  }

  function sendNotification(note) {
    var command = Model.notificationCommand(note)
    if (command.length > 0) Quickshell.execDetached(command)
  }

  // A drop with reconnect enabled returns to the same target. The server-ID
  // fallback only exists when the tunnel was started elsewhere, so later
  // attempts use the fastest server in case that server is gone.
  function armReconnect() {
    var session = (activeTarget || status.server) ? { target: activeTarget, status: status } : (_lastSession || ({}))
    var target = Model.returnTarget(session.target, session.status, freePlan)
    _reconnectFallback = !session.target && target.mode === "server"
    _reconnectTarget = target
    _reconnectAttempt = 0
    reconnectTimer.interval = Model.reconnectDelayMs(0)
    reconnectTimer.restart()
  }

  function cancelReconnect() {
    reconnectTimer.stop()
    _reconnectTarget = null
    _reconnectAttempt = 0
    _reconnectFallback = false
    dropQueuedReconnect()
  }

  // An automatic connect can wait behind a status or settings read. Once the
  // reconnect is cancelled it must not run, and the view it replaced returns.
  function dropQueuedReconnect() {
    var dropped = Scheduler.removeQueued(_queueState, function(job) { return job.auto === true })
    if (dropped.removed.length === 0) return
    _queueState = dropped.queue
    var snapshotView = dropped.removed[0].snapshot
    if (snapshotView && state === Model.STATES.connecting) applyView(snapshotView)
    actionStatus = ""
    // The tunnel may have changed while the connect waited; a timer keeps
    // this out of pump(), which can be the caller.
    delayedRefresh.restart()
  }

  function scheduleNextReconnect() {
    if (_reconnectTarget === null) return
    _reconnectAttempt++
    var delay = Model.reconnectDelayMs(_reconnectAttempt)
    if (delay < 0) {
      giveUpReconnect()
      return
    }
    if (_reconnectFallback) {
      _reconnectTarget = { mode: "fastest" }
      _reconnectFallback = false
    }
    reconnectTimer.interval = delay
    reconnectTimer.restart()
  }

  function giveUpReconnect() {
    cancelReconnect()
    reportError(tr("reconnect.gaveUp", "Could not reconnect after the VPN dropped. Connect again."))
    sendNotification(Model.reconnectFailedNotification({ setting: notificationSetting, openPanels: openPanels, killSwitch: linkKillSwitch }, loc))
  }

  function tryReconnect() {
    if (_reconnectTarget === null) return
    if (linkActive || state === Model.STATES.connected || !reconnectOnDrop || Model.reconnectAbandoned(state)) {
      cancelReconnect()
      return
    }
    if (actionRunning || ksStep !== "idle" || !canToggle) {
      // Not ready yet, for example while a status check runs; a wait uses up
      // an attempt so the schedule still ends.
      requestStatusRefresh()
      scheduleNextReconnect()
      return
    }
    _autoInternal = true
    var started = connectWith(_reconnectTarget)
    _autoInternal = false
    if (started) actionStatus = tr("reconnect.to", "Reconnecting to %1…").arg(Model.returnTargetLabel(_reconnectTarget, loc))
    else scheduleNextReconnect()
  }

  onReconnectOnDropChanged: if (!reconnectOnDrop) cancelReconnect()

  function currentWifiName() {
    var devices = Networking.devices ? Networking.devices.values : []
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i]
      if (!device || device.type !== DeviceType.Wifi || !device.connected) continue
      var networks = device.networks ? device.networks.values : []
      for (var j = 0; j < networks.length; j++) {
        if (networks[j] && networks[j].connected) return String(networks[j].name || "")
      }
    }
    return ""
  }

  // A reload discovers the current network a moment after start; that is
  // not a join, so a VPN you turned off stays off. A join later still counts.
  onWifiNameChanged: {
    cancelAutoConnect("wifi")
    if (!_started || wifiName === "" || !autoConnectWifi || wifiTrusted) return
    if (_shellReloaded && Date.now() - _startedMs < 10000) return
    _autoTicks = 0
    _autoAttempts = 0
    _wifiConnectPending = true
  }

  // A trigger that no longer holds takes its waiting connect with it.
  onWifiTrustedChanged: if (wifiTrusted) cancelAutoConnect("wifi")
  onAutoConnectWifiChanged: if (!autoConnectWifi) cancelAutoConnect("wifi")
  onConnectOnLoginChanged: if (!connectOnLogin) cancelAutoConnect("login")

  function autoConnectQueued() {
    var queued = _queueState.jobs || []
    for (var i = 0; i < queued.length; i++) if (queued[i].autoConnect) return true
    return false
  }

  // Like dropQueuedReconnect, for the login and Wi-Fi connects; kind ""
  // cancels both.
  function cancelAutoConnect(kind) {
    if (kind !== "wifi") _loginConnectPending = false
    if (kind !== "login") _wifiConnectPending = false
    var dropped = Scheduler.removeQueued(_queueState, function(job) {
      return !!job.autoConnect && (kind === "" || job.autoConnect === kind)
    })
    if (dropped.removed.length === 0) return
    _queueState = dropped.queue
    var snapshotView = dropped.removed[0].snapshot
    if (snapshotView && state === Model.STATES.connecting) applyView(snapshotView)
    actionStatus = ""
  }

  function toggleTrustedNetwork(name) {
    saveSettings({ trustedNetworks: Model.toggleNetwork(trustedNetworks, name) })
  }

  // Every 10 seconds for up to 3 minutes, while the network and Proton's
  // services come up: connect once Proton says Disconnected, at most 3 times.
  // Signed out, not installed, or already connected ends it.
  function tryAutoConnect() {
    _autoTicks++
    var done = state === Model.STATES.connected || linkActive || state === Model.STATES.signedOut || state === Model.STATES.cliMissing
    if (done || _autoTicks > 18 || _autoAttempts >= 3) {
      _loginConnectPending = false
      _wifiConnectPending = false
      return
    }
    if (state !== Model.STATES.disconnected || !canToggle) {
      if (!processBusy) requestStatusRefresh()
      return
    }
    _autoAttempts++
    var last = rememberRecent && recentTargets.length > 0 ? recentTargets[0] : null
    _autoConnectKind = autoConnectWifi && _wifiConnectPending ? "wifi" : "login"
    var started = connectWith(Model.returnTarget(last, null, freePlan))
    var kind = _autoConnectKind
    _autoConnectKind = ""
    if (started) actionStatus = kind === "wifi"
      ? tr("wifi.connecting", "Connecting on untrusted Wi-Fi…")
      : tr("login.connecting", "Connecting at login…")
  }

  // Two small kernel files, read in place: no process starts for a sample.
  // Rates are shown only in an open panel; the stall check runs regardless.
  function sampleTraffic() {
    if (!active || !linkActive || _statsDir === "") return
    if (linkDevice !== _trafficDevice || linkServer !== _trafficServer) {
      traffic = Model.emptyTraffic()
      health = Model.emptyHealth()
      _trafficDevice = linkDevice
      _trafficServer = linkServer
    }
    rxFile.reload()
    txFile.reload()
    // text() performs the blocking read; loaded is only true after it.
    var raw = rxFile.text() + " " + txFile.text()
    if (!rxFile.loaded || !txFile.loaded) return
    var counters = Model.parseInterfaceCounters(raw)
    var now = Date.now()
    health = Model.tunnelHealth(health, counters, now)
    if (openPanels > 0) traffic = Model.trafficSample(traffic, counters, now)
  }

  function reportError(errorMessage) {
    lastError = String(errorMessage || tr("failure.generic", "Proton VPN command failed."))
    actionStatus = lastError
    actionStatusTimer.restart()
  }

  function copyText(value) {
    var text = String(value || "")
    if (text === "") return
    Quickshell.execDetached(["wl-copy", "--", text])
    actionStatus = tr("action.copied", "Copied")
    actionStatusTimer.restart()
  }

  // Both open a terminal the panel cannot see into; poll until the CLI is
  // installed and signed in, or give up after six minutes.
  function installCli() {
    Quickshell.execDetached(Model.INSTALL_LAUNCHER)
    watchSetup(tr("setup.installing", "Installing in a terminal…"))
  }

  function signIn() {
    Quickshell.execDetached(Model.SIGNIN_LAUNCHER)
    watchSetup(tr("setup.signingIn", "Signing in from a terminal…"))
  }

  function watchSetup(label) {
    actionStatus = label
    actionStatusTimer.restart()
    _setupChecks = 0
    setupTimer.restart()
  }

  function checkSetup() {
    if (Model.setupComplete(state, installed) || ++_setupChecks >= 72) {
      setupTimer.stop()
      return
    }
    if (!processBusy) refresh()
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
    interval: root.openPanels > 0 ? 2000 : 5000
    repeat: true
    running: root.active && root.linkActive
    triggeredOnStart: true
    onTriggered: root.sampleTraffic()
    onRunningChanged: if (!running) {
      root.traffic = Model.emptyTraffic()
      root.health = Model.emptyHealth()
    }
  }

  // Opening a panel starts its rates at once instead of at the next tick.
  onOpenPanelsChanged: {
    if (openPanels === 0) traffic = Model.emptyTraffic()
    else if (openPanels === 1) sampleTraffic()
  }

  onActiveChanged: {
    if (active) refresh()
    else linkMonitor.running = false
  }
  Component.onCompleted: {
    loginMarker.reload()
    loginMarker.text()
    _shellReloaded = _runtimeDir === "" || loginMarker.loaded
    _loginConnectPending = !_shellReloaded
    _startedMs = Date.now()
    _started = true
    if (active) refresh()
  }

  // With NetworkManager events this is only a safety net for a missed one;
  // without them it is the live link check.
  Timer {
    id: linkTimer
    interval: root.linkEvents ? 60000 : root.linkWatchIntervalSec * 1000
    repeat: true
    running: root.active && root.installed
    triggeredOnStart: true
    onTriggered: root.watchLink()
  }

  Timer {
    id: linkSettle
    interval: 300
    repeat: false
    onTriggered: root.watchLink()
  }

  Timer {
    id: monitorRestart
    repeat: false
    onTriggered: root.startLinkMonitor()
  }

  Timer {
    id: autoConnectTimer
    interval: 10000
    repeat: true
    running: root.active && root.autoConnectArmed
    onTriggered: root.tryAutoConnect()
  }

  Timer {
    id: reconnectTimer
    repeat: false
    onTriggered: root.tryReconnect()
  }

  Timer {
    id: setupTimer
    interval: 5000
    repeat: true
    onTriggered: root.checkSetup()
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
    onTriggered: if (root.ksStep === "idle") root.actionStatus = ""
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

  // Only asks whether the runner's lock file exists; never reads or writes it.
  FileView {
    id: loginMarker
    path: root._runtimeDir !== "" ? root._runtimeDir + "/omarchy-protonvpn.lock" : ""
    blockLoading: true
    printErrors: false
  }

  FileView {
    id: rxFile
    path: root._statsDir !== "" ? root._statsDir + "rx_bytes" : ""
    blockLoading: true
    printErrors: false
  }

  FileView {
    id: txFile
    path: root._statsDir !== "" ? root._statsDir + "tx_bytes" : ""
    blockLoading: true
    printErrors: false
  }

  // Read-only: `nmcli monitor` only prints what NetworkManager reports.
  Process {
    id: linkMonitor
    running: false
    command: ["/usr/bin/nmcli", "monitor"]
    stdout: SplitParser {
      onRead: function(line) { linkSettle.restart() }
    }
    onExited: function(exitCode) { root.linkMonitorExited() }
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
