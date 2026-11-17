import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.BVisagie.protonvpn"
  ipcTarget: "io.github.BVisagie.protonvpn"
  manageIpc: false

  readonly property var sharedVpn: root.bar && root.bar.shell && typeof root.bar.shell.serviceFor === "function"
    ? root.bar.shell.serviceFor(root.moduleName) : null
  // Replacement bars get a service-less shell facade, and the shared service
  // may not exist yet, so never let the panel bind against null.
  readonly property var vpn: root.sharedVpn || localVpn

  // The plugin's own strings, following Setup > Language live.
  readonly property QtObject strings: Translations { directory: Qt.resolvedUrl("i18n") }
  function tr(key, english) { return root.strings.t(key, english) }
  readonly property var loc: ({
    tr: function(key, english) { return root.strings.t(key, english) },
    tn: function(key, count, english) { return root.strings.tn(key, count, english) },
    num: function(value, places) { return I18n.formatNumber(value, places) }
  })

  property string focusSection: "header"
  property bool cursorActive: false
  property string selectedMode: "fastest"
  property string lastMode: "fastest"
  property string selectedCountry: ""
  property string selectedCity: ""
  property string serverIdText: ""
  property string dnsText: ""
  property bool dnsEditorOpen: false
  property int nowTick: 0
  property bool keyboardNavigation: false
  // Set only by user edits to CONNECT, never by programmatic draft resets.
  property bool connectDraftDirty: false
  // The service this panel told it was open, so it can say when it closes.
  property var countedVpn: null
  // Kill Switch value awaiting confirmation while connected; "" when none.
  property string ksConfirmValue: ""
  // Sign-out waits for a second, explicit choice.
  property bool signOutConfirm: false
  // SETTINGS starts folded so the panel opens on status and CONNECT.
  property bool settingsOpen: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property var view: vpn.view
  readonly property bool degraded: view.state === Model.STATES.cliMissing || view.state === Model.STATES.signedOut || view.state === Model.STATES.guiConflict || view.state === Model.STATES.error || view.state === Model.STATES.stale
  readonly property bool showHealthy: view.state === Model.STATES.connected || view.state === Model.STATES.disconnected || view.state === Model.STATES.connecting || view.state === Model.STATES.disconnecting
  readonly property bool showWrites: showHealthy && vpn.canChangeSettings
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && vpn.installed && Model.canWrite(view.state)
  readonly property color barIconColor: {
    if (Model.iconUrgent(view.state, view.blocking)) return bar ? bar.urgent : Color.urgent
    if (Model.iconDim(view.state)) return Qt.darker(barForeground, 1.55)
    return barForeground
  }
  readonly property color iconColor: {
    if (Model.iconUrgent(view.state, view.blocking)) return urgent
    if (Model.iconDim(view.state)) return dim
    return foreground
  }
  // Header controls derive visibility from state, never from a child's
  // `visible`: that reads false while the parent is hidden, so a parent bound
  // to it could never show again.
  readonly property string heroDetailText: Model.heroDetail(view, root.loc)
  readonly property bool powerSwitchShown: vpn.installed && (Model.canWrite(view.state) || view.state === Model.STATES.connecting || view.state === Model.STATES.disconnecting)
  readonly property string toggleHint: {
    if (view.state === Model.STATES.connecting) return tr("action.connecting", "Connecting…")
    if (view.state === Model.STATES.disconnecting) return tr("action.disconnecting", "Disconnecting…")
    if (view.state === Model.STATES.connected) return tr("toggle.disconnect", "Disconnect Proton VPN")
    return tr("toggle.connect", "Connect Proton VPN")
  }
  readonly property var countryOptions: countryOptionList()
  readonly property var cityOptions: cityOptionList()
  readonly property var modeOptions: Model.modeOptions(vpn.freePlan, root.loc)
  readonly property string planNotice: Model.planBlockedReason(selectedMode, vpn.freePlan, root.loc)
  readonly property bool needsCountry: Model.modeNeedsCountry(selectedMode)
  readonly property bool requiresCountry: Model.modeRequiresCountry(selectedMode)
  readonly property bool needsCity: Model.modeNeedsCity(selectedMode)
  readonly property bool needsServer: Model.modeNeedsServer(selectedMode)
  readonly property var configSettings: Model.CONFIG_SETTINGS
  readonly property string copyCommand: Model.copyCommandFor(view.state)
  readonly property bool pickerOpen: modeDropdown.popupOpen || countryDropdown.popupOpen || cityDropdown.popupOpen || netshieldDropdown.popupOpen || killSwitchDropdown.popupOpen
  readonly property bool editorFocused: (serverField.visible && serverField.activeFocus) || (dnsField.visible && dnsField.activeFocus)
  readonly property var toggleSettings: toggleSettingList()
  readonly property var statusPairs: statusPairList()
  readonly property bool offerSwitch: Model.shouldOfferSwitch({
    state: view.state,
    busy: vpn.actionBusy,
    draft: connectOptions(),
    activeTarget: vpn.activeTarget,
    draftDirty: connectDraftDirty
  })
  // The connection to star: what this session connected to, or else the
  // server the tunnel is on.
  readonly property var currentTarget: view.state === Model.STATES.connected
    ? (vpn.activeTarget || Model.cleanTarget({ mode: "server", serverId: view.status.server || "" })) : null
  readonly property var quickRows: Model.quickConnectRows(vpn.favorites, vpn.recentTargets, currentTarget)
  readonly property string barLabel: root.bar && root.bar.vertical ? "" : Model.barLabelText(root.setting("barLabel", "none"), root.view)

  // Same font as BarIconButton's label.
  TextMetrics {
    id: barLabelMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.bar.iconFont
    text: root.barLabel
  }
  readonly property var focusRows: visibleFocusRows()
  readonly property var focusOrder: visibleFocusOrder()

  function toggleSettingList() {
    var list = []
    for (var i = 0; i < Model.CONFIG_SETTINGS.length; i++) {
      if (Model.CONFIG_SETTINGS[i].type === "toggle") list.push(Model.CONFIG_SETTINGS[i])
    }
    return list
  }

  function countryOptionList() {
    var list = []
    for (var i = 0; i < vpn.countries.length; i++) {
      list.push({ value: vpn.countries[i].code, label: vpn.countries[i].label })
    }
    return list
  }

  function cityOptionList() {
    var list = []
    for (var i = 0; i < vpn.cities.length; i++) {
      list.push({ value: vpn.cities[i].name, label: vpn.cities[i].label })
    }
    return list
  }

  function countryEmptyText() {
    if (vpn.countriesLoading) return tr("field.loadingCountries", "Loading countries…")
    if (vpn.countriesError !== "") return vpn.countriesError
    return tr("field.noCountries", "No countries found")
  }

  function cityEmptyText() {
    if (vpn.citiesLoading) return tr("field.loadingCities", "Loading cities…")
    if (vpn.citiesError !== "") return vpn.citiesError
    if (selectedCountry === "") return tr("field.countryFirst", "Choose a country first")
    return tr("field.noCities", "No cities found")
  }

  function connectOptions() {
    return {
      mode: selectedMode,
      country: selectedCountry,
      city: selectedCity,
      serverId: serverIdText
    }
  }

  function applyConnectDraft(draft) {
    selectedCountry = draft.country
    selectedCity = draft.city
    serverIdText = draft.serverId
    if (countryDropdown) countryDropdown.value = selectedCountry
    if (cityDropdown) cityDropdown.value = selectedCity
  }

  function refreshConnectLists() {
    if (needsCountry) vpn.refreshCountries()
    if (needsCity && selectedCountry !== "") vpn.refreshCities(selectedCountry)
    else vpn.clearCities()
  }

  function statusPairList() {
    var list = []
    var status = view.status
    if (!status) return list
    var now = Date.now() + nowTick
    if (view.state === Model.STATES.connected && vpn.linkActive) {
      var up = Model.durationText(vpn.linkSinceMs, now, root.loc)
      if (up !== "") list.push({ label: tr("status.duration", "Connected for"), value: up })
    }
    if (view.state === Model.STATES.connected || (view.stale && status.protocol !== "")) {
      list.push({ label: tr("status.load", "Load"), value: Model.displayLoad(status.load, root.loc) })
    }
    if (status.exitIp !== "") list.push({ label: tr("status.exitIp", "Exit IP"), value: status.exitIp })
    var updated = Model.lastUpdatedText(view, now, root.loc)
    if (updated !== "") list.push({ label: view.stale ? tr("hero.staleBadge", "Stale") : tr("status.updated", "Updated"), value: updated })
    return list
  }

  function visibleFocusRows() {
    var rows = []
    if (vpn.installed && (Model.canWrite(view.state) || view.state === Model.STATES.connecting || view.state === Model.STATES.disconnecting)) rows.push(["header"])
    if (view.state === Model.STATES.cliMissing) rows.push(["install"])
    if (view.state === Model.STATES.signedOut) rows.push(["signin"])
    if (copyCommand !== "") rows.push(["copy"])
    rows.push(["refresh"])
    if (vpn.countriesError !== "" || vpn.citiesError !== "") rows.push(["retry-locations"])
    if (showWrites && vpn.installed) {
      var connect = ["mode"]
      if (needsCountry) connect.push("country")
      if (needsCity) connect.push("city")
      if (needsServer) connect.push("server")
      rows.push(connect)
      if (offerSwitch) rows.push(["switch"])
      for (var q = 0; q < quickRows.length; q++) rows.push(["star:" + q, "quick:" + q])
      rows.push(["settings"])
      if (settingsOpen && vpn.configLoaded) {
        rows.push(["config:netshield", "config:kill-switch"])
        if (ksConfirmValue !== "") rows.push(["ks-cancel", "ks-confirm"])
        rows.push(["config:port-forwarding", "config:vpn-accelerator"])
        rows.push(["config:moderate-nat", "config:ipv6"])
        rows.push(["config:anonymous-crash-reports", "config:custom-dns"])
        if (showDnsField()) rows.push(["dns"])
        if (vpn.autoConnectWifi && vpn.wifiName !== "") rows.push(["trust"])
        if (view.state === Model.STATES.disconnected && !signOutConfirm) rows.push(["signout"])
        if (signOutConfirm) rows.push(["so-cancel", "so-confirm"])
      }
    }
    return rows
  }

  function visibleFocusOrder() {
    var order = []
    var rows = focusRows
    for (var i = 0; i < rows.length; i++) {
      for (var j = 0; j < rows[i].length; j++) order.push(rows[i][j])
    }
    return order
  }

  function dnsEnabled() {
    var value = String(vpn.configDisplayValue("custom-dns") || "")
    return Model.parseCustomDnsValue(value).enabled === true || vpn.pendingSetting === "custom-dns" && vpn.pendingValue === "on"
  }

  function showDnsField() {
    return dnsEnabled() || dnsEditorOpen
  }

  function ensureCursor() {
    var order = focusOrder
    if (order.length === 0) {
      focusSection = "refresh"
      return
    }
    if (order.indexOf(focusSection) === -1) focusSection = order[0]
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    keyboardNavigation = true
    ensureCursor()
    if (dx === 0 && dy === 0) return
    var rows = focusRows
    if (rows.length === 0) return
    var row = 0
    var col = 0
    for (var i = 0; i < rows.length; i++) {
      var found = rows[i].indexOf(focusSection)
      if (found !== -1) {
        row = i
        col = found
        break
      }
    }
    if (dy !== 0) {
      var nextRow = Math.max(0, Math.min(rows.length - 1, row + dy))
      var nextCols = rows[nextRow]
      col = Math.min(col, nextCols.length - 1)
      focusSection = nextCols[col]
    } else {
      var nextCol = Math.max(0, Math.min(rows[row].length - 1, col + dx))
      focusSection = rows[row][nextCol]
    }
    scrollCursorIntoView()
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "header") tryToggle()
    else if (focusSection === "refresh") refreshAll()
    else if (focusSection === "retry-locations") retryLocations()
    else if (focusSection === "copy") vpn.copyText(copyCommand)
    else if (focusSection === "install") vpn.installCli()
    else if (focusSection === "signin") vpn.signIn()
    else if (focusSection === "mode") modeDropdown.toggle()
    else if (focusSection === "country") countryDropdown.toggle()
    else if (focusSection === "city" && selectedCountry !== "") cityDropdown.toggle()
    else if (focusSection === "server") Qt.callLater(function() { if (serverField) serverField.forceActiveFocus() })
    else if (focusSection === "switch") switchNow()
    else if (focusSection === "settings") toggleSettingsFold()
    else if (focusSection.indexOf("quick:") === 0) connectQuick(parseInt(focusSection.substring(6), 10))
    else if (focusSection.indexOf("star:") === 0) starQuick(parseInt(focusSection.substring(5), 10))
    else if (focusSection === "dns") applyDns()
    else if (focusSection === "ks-cancel") cancelKillSwitch()
    else if (focusSection === "ks-confirm") confirmKillSwitch()
    else if (focusSection === "trust") vpn.toggleTrustedNetwork(vpn.wifiName)
    else if (focusSection === "signout") askSignOut()
    else if (focusSection === "so-cancel") cancelSignOut()
    else if (focusSection === "so-confirm") confirmSignOut()
    else if (focusSection.indexOf("config:") === 0) activateConfig(focusSection.substring(7))
  }

  function activateConfig(key) {
    var def = Model.settingDef(key)
    if (!def) return
    if (vpn.configUpgrade && vpn.configUpgrade[key]) {
      vpn.setConfig(key, def.values[def.values.length - 1])
      return
    }
    if (def.type === "toggle") {
      var current = String(vpn.configDisplayValue(key) || "off")
      vpn.setConfig(key, current === "on" ? "off" : "on")
      return
    }
    if (key === "netshield") netshieldDropdown.toggle()
    else if (key === "kill-switch") killSwitchDropdown.toggle()
    else if (key === "custom-dns") toggleCustomDns()
  }

  // While connected, a Kill Switch change drops and restores the tunnel, so
  // ask first with Cancel preselected; an accidental Enter changes nothing.
  function chooseKillSwitch(value) {
    if (value === vpn.configDisplayValue("kill-switch")) return
    if (!Model.isVpnActive(view)) {
      vpn.setKillSwitch(value)
      return
    }
    ksConfirmValue = value
    cursorActive = true
    focusSection = "ks-cancel"
    scrollItemIntoView(ksConfirm)
  }

  function askSignOut() {
    signOutConfirm = true
    cursorActive = true
    focusSection = "so-cancel"
    scrollItemIntoView(signOutConfirmRow)
  }

  function cancelSignOut() {
    signOutConfirm = false
    focusSection = "signout"
  }

  function confirmSignOut() {
    signOutConfirm = false
    focusSection = "refresh"
    vpn.signOut()
  }

  function toggleSettingsFold() {
    settingsOpen = !settingsOpen
    if (!settingsOpen) ksConfirmValue = ""
    cursorActive = true
    focusSection = "settings"
    scrollItemIntoView(settingsOpen ? settingsBody : settingsHeader)
  }

  function cancelKillSwitch() {
    ksConfirmValue = ""
    focusSection = "config:kill-switch"
  }

  function confirmKillSwitch() {
    var value = ksConfirmValue
    ksConfirmValue = ""
    focusSection = "config:kill-switch"
    if (value !== "") vpn.setKillSwitch(value)
  }

  function tryToggle() {
    if (!Model.canWrite(view.state) || vpn.actionBusy) {
      if (!root.opened) root.open()
      return
    }
    if (view.state === Model.STATES.connected) {
      vpn.disconnect()
      return
    }
    var plan = Model.buildConnectCommand(connectOptions(), root.loc)
    if (!plan.ok) {
      vpn.reportError(plan.message)
      if (!root.opened) root.open()
      return
    }
    vpn.connectWith(connectOptions())
  }

  function connectQuick(index) {
    var row = quickRows[index]
    if (row && !row.active) vpn.connectWith(row.target)
  }

  function starQuick(index) {
    var row = quickRows[index]
    if (row) vpn.toggleFavorite(row.target)
  }

  // f on a Quick connect row stars or unstars it.
  function starCursorRow() {
    var name = focusSection
    if (name.indexOf("quick:") === 0) starQuick(parseInt(name.substring(6), 10))
    else if (name.indexOf("star:") === 0) starQuick(parseInt(name.substring(5), 10))
  }

  // Omarchy gives a panel its bar before its settings. Until the bar has
  // injected them, the empty default would switch every opt-in off in the
  // shared service; after that, even an empty entry is the user's choice.
  property bool settingsInjected: false
  function pushSettings() {
    if (vpn && settingsInjected) vpn.setSettings(root.settings)
  }

  // With rememberRecent on, CONNECT starts where the last connection went.
  // Once, when the bar's settings first arrive; they come after load.
  property bool draftRestored: false
  function restoreDraft() {
    if (draftRestored || !settingsInjected) return
    draftRestored = true
    if (connectDraftDirty || !vpn.rememberRecent || vpn.recentTargets.length === 0) return
    var target = vpn.recentTargets[0]
    selectedMode = target.mode
    selectedCountry = target.country
    selectedCity = target.city
    serverIdText = target.serverId
    if (countryDropdown) countryDropdown.value = selectedCountry
    if (cityDropdown) cityDropdown.value = selectedCity
  }

  function switchNow() {
    if (vpn.connectWith(connectOptions())) connectDraftDirty = false
  }

  function connectNow() {
    vpn.connectWith(connectOptions())
  }

  function disconnectNow() {
    vpn.disconnect()
  }

  function retryLocations() {
    if (!vpn.installed) return
    vpn.refreshCountries(true)
    if (needsCity && selectedCountry !== "") vpn.refreshCities(selectedCountry, true)
  }

  // Opening the panel should not force slow list reloads ahead of what the
  // user is about to pick; Refresh, r, and middle-click still force them.
  function refreshOnOpen() {
    vpn.refresh()
    if (vpn.installed && (showHealthy || view.state === Model.STATES.stale)) {
      vpn.refreshCountries()
      vpn.refreshConfig()
      if (needsCity && selectedCountry !== "") vpn.refreshCities(selectedCountry)
    }
  }

  function refreshAll() {
    vpn.refresh()
    if (vpn.installed && (showHealthy || view.state === Model.STATES.stale)) {
      vpn.refreshCountries(true)
      vpn.refreshConfig()
      if (needsCity && selectedCountry !== "") vpn.refreshCities(selectedCountry, true)
    }
  }

  function applyDns() {
    var checked = Model.validateDnsList(dnsText, root.loc)
    if (!checked.ok) {
      vpn.reportError(checked.message)
      setFocusSection("dns")
      Qt.callLater(function() { if (dnsField) dnsField.forceActiveFocus() })
      return
    }
    vpn.setConfig("custom-dns", "on", { dns: dnsText })
  }

  function toggleCustomDns() {
    var dns = Model.parseCustomDnsValue(vpn.configDisplayValue("custom-dns"))
    if (dns.enabled) {
      dnsEditorOpen = false
      vpn.setConfig("custom-dns", "off")
      return
    }
    var checked = Model.validateDnsList(dnsText, root.loc)
    if (checked.ok) {
      applyDns()
      return
    }
    dnsEditorOpen = true
    setFocusSection("dns")
    Qt.callLater(function() { if (dnsField) dnsField.forceActiveFocus() })
  }

  function setFocusSection(name) {
    cursorActive = true
    keyboardNavigation = false
    focusSection = name
    ensureCursor()
  }

  function setHeaderCursor() {
    setFocusSection("header")
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    if (focusSection === "header") scrollItemIntoView(header)
    else if (focusSection === "refresh") scrollItemIntoView(refreshRow)
    else if (focusSection === "retry-locations") scrollItemIntoView(retryLocationsRow)
    else if (focusSection === "copy") scrollItemIntoView(copyRow)
    else if (focusSection === "install") scrollItemIntoView(installRow)
    else if (focusSection === "signin") scrollItemIntoView(signInRow)
    else if (focusSection === "mode") scrollItemIntoView(modeDropdown)
    else if (focusSection === "country") scrollItemIntoView(countryDropdown)
    else if (focusSection === "city") scrollItemIntoView(cityDropdown)
    else if (focusSection === "server") scrollItemIntoView(serverField)
    else if (focusSection === "switch") scrollItemIntoView(switchButton)
    else if (focusSection === "settings") scrollItemIntoView(settingsHeader)
    else if (focusSection.indexOf("quick:") === 0 || focusSection.indexOf("star:") === 0) scrollItemIntoView(quickList)
    else if (focusSection === "dns") scrollItemIntoView(dnsField)
    else if (focusSection === "config:netshield") scrollItemIntoView(netshieldDropdown)
    else if (focusSection === "config:kill-switch") scrollItemIntoView(killSwitchDropdown)
    else if (focusSection === "config:custom-dns") scrollItemIntoView(customDnsToggle)
    else if (focusSection === "ks-cancel" || focusSection === "ks-confirm") scrollItemIntoView(ksConfirm)
    else if (focusSection === "trust") scrollItemIntoView(trustRow)
    else if (focusSection === "signout") scrollItemIntoView(signOutRow)
    else if (focusSection === "so-cancel" || focusSection === "so-confirm") scrollItemIntoView(signOutConfirmRow)
    else {
      var grids = [choiceGrid, toggleGrid]
      for (var g = 0; g < grids.length; g++) {
        var grid = grids[g]
        if (!grid) continue
        for (var i = 0; i < grid.children.length; i++) {
          var child = grid.children[i]
          if (child && child.objectName === focusSection) {
            scrollItemIntoView(child)
            return
          }
        }
      }
      if (toggleGrid) scrollItemIntoView(toggleGrid)
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    trackOpen(opened)
    if (opened) openPanel()
    else {
      ksConfirmValue = ""
      signOutConfirm = false
    }
  }
  onVpnChanged: {
    if (countedVpn && countedVpn !== vpn) {
      countedVpn.panelClosed()
      countedVpn = null
      trackOpen(opened)
    }
    pushSettings()
  }
  Component.onDestruction: trackOpen(false)

  // The service stops polling `protonvpn status` while every panel is closed.
  function trackOpen(isOpen) {
    if (isOpen && !countedVpn && vpn) {
      countedVpn = vpn
      vpn.panelOpened()
    } else if (!isOpen && countedVpn) {
      countedVpn.panelClosed()
      countedVpn = null
    }
  }

  function openPanel() {
    cursorActive = false
    keyboardNavigation = false
    if (panelFlick) panelFlick.contentY = 0
    refreshOnOpen()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onSettingsChanged: {
    settingsInjected = true
    pushSettings()
    restoreDraft()
  }
  Component.onCompleted: {
    if (root.settings && Object.keys(root.settings).length > 0) settingsInjected = true
    pushSettings()
    restoreDraft()
  }
  onSelectedModeChanged: {
    var draft = Model.connectDraftForModeChange(lastMode, selectedMode, {
      country: selectedCountry,
      city: selectedCity,
      serverId: serverIdText
    })
    lastMode = selectedMode
    applyConnectDraft(draft)
    refreshConnectLists()
    ensureCursor()
  }
  onSelectedCountryChanged: {
    var draft = Model.connectDraftForCountryChange({
      country: selectedCountry,
      city: selectedCity,
      serverId: serverIdText
    })
    selectedCity = draft.city
    if (cityDropdown) cityDropdown.value = selectedCity
    if (countryDropdown) countryDropdown.value = selectedCountry
    if (needsCity && selectedCountry !== "") vpn.refreshCities(selectedCountry)
    else vpn.clearCities()
    ensureCursor()
  }

  Service {
    id: localVpn
    active: !root.sharedVpn
    // Replacement bars have no shared service; save settings through the bar.
    shell: root.bar && root.bar.shell ? root.bar.shell : null
  }

  Connections {
    target: vpn
    function onStateChanged() { root.ensureCursor() }
    // Any new connection (Switch, Quick connect, toggle, IPC) settles the draft.
    function onActiveTargetChanged() { root.connectDraftDirty = false }
    function onConfigLoadedChanged() {
      if (vpn.configLoaded) {
        var dns = Model.parseCustomDnsValue(vpn.configDisplayValue("custom-dns"))
        if (dns.ips.length > 0) root.dnsText = dns.ips.join(", ")
        if (!dns.enabled && vpn.pendingSetting !== "custom-dns") root.dnsEditorOpen = false
      }
      root.ensureCursor()
    }
    function onCountriesChanged() { root.ensureCursor() }
    function onCitiesChanged() { root.ensureCursor() }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshAll(); return "ok" }
    function connectVpn(): string { root.connectNow(); return "ok" }
    function disconnectVpn(): string { root.disconnectNow(); return "ok" }
    function toggleVpn(): string { root.tryToggle(); return "ok" }
    function connectFastest(): string { return vpn.connectWith({ mode: "fastest" }) ? "ok" : vpn.lastError }
    function connectTo(target: string): string {
      var parsed = Model.parseTargetSpec(target)
      if (!parsed) return root.tr("ipc.badTarget", "Use a country code (NL), a server ID (CH#242), a country and city (US New York), p2p, securecore, or tor with an optional country code, or random or fastest alone.")
      return vpn.connectWith(parsed) ? "ok" : vpn.lastError
    }
    function status(): string { return Model.tooltipText(root.view, root.loc) }
    function statusJson(): string { return Model.statusJson(root.view, { sinceMs: vpn.linkSinceMs, config: vpn.configValues }) }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: Model.tooltipText(root.view, root.loc)
    // Vertical bars stay icon-only, like Omarchy's battery percentage. The
    // slot widens to the label, as the battery widget's does.
    labelText: root.barLabel
    slotSize: Style.bar.iconSlot + (root.barLabel !== "" ? Math.ceil(barLabelMetrics.advanceWidth) + Style.space(8) : 0)
    iconComponent: Component {
      Item {
        ProtonVpnIcon {
          anchors.centerIn: parent
          iconSize: Style.space(11)
          color: root.barIconColor
          badgeColor: root.urgent
          crossed: Model.iconCrossed(root.view.state)
          warning: Model.iconWarning(root.view.state, root.view.blocking, root.view.stalled)
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.tryToggle()
      else if (buttonCode === Qt.MiddleButton) {
        if (!vpn.processBusy) root.refreshAll()
      } else {
        root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.pickerOpen || root.editorFocused
      onMoveRequested: function(dx, dy) {
        root.keyboardNavigation = true
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.ksConfirmValue !== "" ? root.cancelKillSwitch() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refreshAll()
        else if (t === "t" || t === "T") root.tryToggle()
        else if ((t === "s" || t === "S") && root.showWrites && vpn.installed) root.toggleSettingsFold()
        else if (t === "f" || t === "F") root.starCursorRow()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        function clampContentY() {
          var maxY = Math.max(0, contentHeight - height)
          if (contentY > maxY) contentY = maxY
          else if (contentY < 0) contentY = 0
        }

        onContentHeightChanged: clampContentY()
        onHeightChanged: clampContentY()

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.spacing.panelGap

          Column {
            width: parent.width
            spacing: Style.spacing.rowGap

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.headerHasCursor
            function focusHero() { root.setHeaderCursor() }

            PanelHero {
              id: hero
              width: parent.width
              title: Model.heroTitle(root.view)
              meta: Model.heroMeta(root.view, root.loc)
              // The protocol pill lives beside the toggle (trailingControl) so both
              // share one vertical center; PanelHero would pin it to the title line.
              detail: ""
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: Model.iconDim(root.view.state) ? 0.55 : 1.0
              iconComponent: Component {
                ProtonVpnIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                  badgeColor: root.urgent
                  crossed: Model.iconCrossed(root.view.state)
                  warning: Model.iconWarning(root.view.state, root.view.blocking, root.view.stalled)
                }
              }
              trailingControl: Component {
                Row {
                  visible: root.heroDetailText !== "" || root.powerSwitchShown
                  spacing: Style.space(12)

                BorderSurface {
                  id: detailPill
                  visible: root.heroDetailText !== ""
                  anchors.verticalCenter: parent.verticalCenter
                  implicitWidth: detailText.implicitWidth + Style.space(10)
                  implicitHeight: detailText.implicitHeight + Style.space(4)
                  color: "transparent"
                  borderSpec: Border.controlSpec("normal", hero.foreground, Color.accent)
                  radius: Style.cornerRadius

                  Text {
                    id: detailText
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: root.heroDetailText
                    color: hero.dim
                    font.family: hero.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                }

                ToggleSwitch {
                  id: powerSwitch
                  anchors.verticalCenter: parent.verticalCenter
                  visible: root.powerSwitchShown
                  checked: root.view.state === Model.STATES.connected || root.view.state === Model.STATES.connecting
                  busy: vpn.actionBusy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: root.tryToggle()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.toggleHint
                    fontFamily: hero.fontFamily
                  }
                }
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: vpn.actionStatus !== "" || vpn.lastError !== "" || vpn.restartNotice !== ""
            width: parent.width
            text: vpn.actionStatus !== "" ? vpn.actionStatus : (vpn.lastError !== "" ? vpn.lastError : vpn.restartNotice)
            color: vpn.lastError !== "" && vpn.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            visible: root.view.blocking === true
            width: parent.width
            text: Model.killSwitchBlockingText(root.loc)
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            visible: root.view.stalled === true
            width: parent.width
            text: Model.stalledText(root.loc)
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            visible: vpn.reconnectPending && !vpn.actionBusy
            width: parent.width
            text: root.tr("reconnect.pending", "Reconnect when the VPN drops is on; the next attempt runs shortly. Connecting or disconnecting yourself cancels it.")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            visible: vpn.portForwardingNotice !== "" && root.view.state === Model.STATES.connected
            width: parent.width
            text: vpn.portForwardingNotice
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Column {
            visible: root.degraded
            width: parent.width
            spacing: Style.spacing.xl

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: Model.degradedExplanation(root.view.state, root.loc)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: Model.degradedRemediation(root.view, root.loc)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Text {
              textFormat: Text.PlainText
              visible: Model.diagnosticDetail(root.view) !== ""
              width: parent.width
              text: Model.diagnosticDetail(root.view)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          ActionRow {
            id: installRow
            visible: root.view.state === Model.STATES.cliMissing
            width: parent.width
            title: root.tr("setup.install", "Install Proton VPN CLI")
            subtitle: root.tr("setup.installHint", "Opens Omarchy's installer in a terminal.")
            sectionName: "install"
            onActivated: vpn.installCli()
          }

          ActionRow {
            id: signInRow
            visible: root.view.state === Model.STATES.signedOut
            width: parent.width
            title: root.tr("setup.signIn", "Sign in")
            subtitle: root.tr("setup.signInHint", "Opens a terminal; this plugin never collects a password.")
            sectionName: "signin"
            onActivated: vpn.signIn()
          }

          ActionRow {
            id: copyRow
            visible: root.copyCommand !== ""
            width: parent.width
            title: root.tr("setup.copy", "Copy command")
            subtitle: root.copyCommand
            sectionName: "copy"
            onActivated: vpn.copyText(root.copyCommand)
          }

          RowLayout {
            id: statusRefreshRow
            width: parent.width
            spacing: Style.spacing.rowGap

            // Flow keeps Load, Exit IP, and Updated on one line beside Refresh and
            // wraps only when the values (e.g. an IPv6 exit IP) do not fit.
            Flow {
              id: statusGrid
              visible: vpn.installed && (root.showHealthy || root.view.state === Model.STATES.stale) && root.statusPairs.length > 0
              Layout.fillWidth: true
              Layout.preferredWidth: 0
              Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
              spacing: Style.spacing.labelGap

              Repeater {
                model: root.statusPairs
                Item {
                  required property var modelData
                  required property int index
                  implicitWidth: pair.implicitWidth + (index < root.statusPairs.length - 1 ? Style.spacing.xxl : 0)
                  implicitHeight: pair.implicitHeight
                  width: implicitWidth
                  height: implicitHeight

                  InfoPair {
                    id: pair
                    label: modelData.label
                    value: modelData.value
                  }
                }
              }
            }

            Item { Layout.fillWidth: true; visible: !statusGrid.visible }

            Button {
              id: refreshRow
              Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
              text: vpn.refreshing ? root.tr("refresh.running", "Refreshing…") : root.tr("refresh.label", "Refresh")
              tooltipText: vpn.refreshing ? root.tr("refresh.runningTip", "Checking Proton VPN…") : root.tr("refresh.tip", "Update status, locations, and settings")
              hasCursor: root.cursorActive && root.focusSection === "refresh"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.refreshAll()
              onHovered: function(on) { if (on) root.setFocusSection("refresh") }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: text !== "" && root.showHealthy && vpn.configLoaded
            width: parent.width
            text: Model.protectionsText(vpn.configValues, root.view, root.loc)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          // Tunnel traffic, read locally from sysfs only while a panel is open.
          Text {
            textFormat: Text.PlainText
            visible: vpn.trafficText !== "" && root.view.state === Model.STATES.connected
            width: parent.width
            text: vpn.trafficText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Text {
            textFormat: Text.PlainText
            visible: vpn.compatibilityWarning !== ""
            width: parent.width
            text: vpn.compatibilityWarning
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          ActionRow {
            id: retryLocationsRow
            visible: (vpn.countriesError !== "" || vpn.citiesError !== "") && vpn.installed
            width: parent.width
            title: root.tr("discovery.retry", "Retry locations")
            subtitle: vpn.countriesError !== "" ? vpn.countriesError : vpn.citiesError
            sectionName: "retry-locations"
            onActivated: root.retryLocations()
          }
          }

          Column {
            visible: root.showWrites && vpn.installed
            width: parent.width
            spacing: Style.spacing.rowGap

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: root.tr("section.connect", "CONNECT")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            RowLayout {
              id: connectRow
              width: parent.width
              spacing: Style.spacing.rowGap

              FieldColumn {
                FieldLabel { text: root.tr("field.mode", "Mode") }
                SearchableDropdown {
                  id: modeDropdown
                  Layout.fillWidth: true
                  Layout.preferredWidth: 0
                  showLabel: false
                  value: root.selectedMode
                  options: root.modeOptions
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  hasCursor: root.cursorActive && root.focusSection === "mode"
                  placeholderText: root.tr("field.searchModes", "Search modes")
                  onHovered: function(on) {
                    modeTip.tipHovered = on
                    if (on) root.setFocusSection("mode")
                  }
                  onChanged: function(value) {
                    root.connectDraftDirty = true
                    root.selectedMode = value
                  }

                  SettingTip {
                    id: modeTip
                    text: Model.modeTooltip(root.selectedMode, root.loc)
                    tipCursor: root.keyboardNavigation && modeDropdown.hasCursor
                    tipPopupOpen: modeDropdown.popupOpen
                  }
                }
              }

              FieldColumn {
                fieldVisible: root.needsCountry
                FieldLabel { text: root.tr("field.country", "Country") }
                SearchableDropdown {
                  id: countryDropdown
                  Layout.fillWidth: true
                  Layout.preferredWidth: 0
                  showLabel: false
                  value: root.selectedCountry
                  options: root.countryOptions
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  hasCursor: root.cursorActive && root.focusSection === "country"
                  placeholderText: root.tr("field.searchCountries", "Search countries")
                  triggerLabel: Model.connectFieldTriggerLabel("country", { mode: root.selectedMode, country: root.selectedCountry }, root.loc)
                  emptyText: root.countryEmptyText()
                  onHovered: function(on) {
                    countryTip.tipHovered = on
                    if (on) root.setFocusSection("country")
                  }
                  onChanged: function(value) {
                    root.connectDraftDirty = true
                    root.selectedCountry = value
                  }

                  SettingTip {
                    id: countryTip
                    text: Model.connectFieldTooltip("country", root.loc)
                    tipCursor: root.keyboardNavigation && countryDropdown.hasCursor
                    tipPopupOpen: countryDropdown.popupOpen
                  }
                }
              }

              FieldColumn {
                fieldVisible: root.needsCity
                FieldLabel { text: root.tr("field.city", "City") }
                SearchableDropdown {
                  id: cityDropdown
                  Layout.fillWidth: true
                  Layout.preferredWidth: 0
                  showLabel: false
                  value: root.selectedCity
                  options: root.cityOptions
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  hasCursor: root.cursorActive && root.focusSection === "city"
                  placeholderText: root.tr("field.searchCities", "Search cities")
                  triggerLabel: Model.connectFieldTriggerLabel("city", {
                    mode: root.selectedMode,
                    country: root.selectedCountry,
                    loading: vpn.citiesLoading && vpn.citiesCountry === root.selectedCountry
                  }, root.loc)
                  emptyText: root.cityEmptyText()
                  enabled: root.selectedCountry !== ""
                  onHovered: function(on) {
                    cityTip.tipHovered = on
                    if (on) root.setFocusSection("city")
                  }
                  onChanged: function(value) {
                    root.connectDraftDirty = true
                    root.selectedCity = value
                  }

                  SettingTip {
                    id: cityTip
                    text: Model.connectFieldTooltip("city", root.loc)
                    tipCursor: root.keyboardNavigation && cityDropdown.hasCursor
                    tipPopupOpen: cityDropdown.popupOpen
                  }
                }
              }

              FieldColumn {
                fieldVisible: root.needsServer
                FieldLabel { text: root.tr("field.server", "Server ID") }
                TextField {
                  id: serverField
                  Layout.fillWidth: true
                  Layout.preferredWidth: 0
                  foreground: root.foreground
                  placeholderText: "IT#23"
                  text: root.serverIdText
                  hasCursor: root.cursorActive && root.focusSection === "server" && !activeFocus
                  onHoveredChanged: if (hovered) root.setFocusSection("server")
                  onTextChanged: {
                    if (text !== root.serverIdText) root.connectDraftDirty = true
                    root.serverIdText = text
                  }
                  onAccepted: root.offerSwitch ? root.switchNow() : root.tryToggle()

                  SettingTip {
                    text: Model.connectFieldTooltip("server", root.loc)
                    tipHovered: serverField.hovered
                    tipCursor: root.keyboardNavigation && root.cursorActive && root.focusSection === "server"
                  }
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: root.planNotice !== ""
              width: parent.width
              text: root.planNotice
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Button {
              id: switchButton
              visible: root.offerSwitch
              width: parent.width
              bordered: true
              text: Model.switchLabel(root.connectOptions(), root.loc)
              tooltipText: root.tr("connect.switchTip", "Reconnect with these choices. Proton replaces the current connection.")
              hasCursor: root.cursorActive && root.focusSection === "switch"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.switchNow()
              onHovered: function(on) { if (on) root.setFocusSection("switch") }
            }

            PanelSectionHeader {
              visible: root.quickRows.length > 0
              text: root.tr("section.quick", "QUICK CONNECT")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: quickList
              visible: root.quickRows.length > 0
              width: parent.width
              spacing: Style.space(2)

              Repeater {
                model: root.quickRows

                QuickRow {
                  required property var modelData
                  required property int index
                  width: quickList.width
                  row: modelData
                  rowIndex: index
                }
              }
            }
          }

          Column {
            visible: root.showWrites && vpn.installed
            width: parent.width
            spacing: Style.spacing.rowGap

            PanelSeparator { foreground: root.foreground }

            CursorSurface {
              id: settingsHeader
              width: parent.width
              implicitHeight: settingsHeaderRow.implicitHeight + Style.space(8)
              hasCursor: root.cursorActive && root.focusSection === "settings"
              foreground: root.foreground
              fill: root.hoverFill

              MouseArea {
                id: settingsHeaderMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.setFocusSection("settings")
                onClicked: root.toggleSettingsFold()
              }

              SettingTip {
                text: root.settingsOpen ? root.tr("settings.hide", "Hide settings (s)") : root.tr("settings.show", "Show every Proton VPN setting (s)")
                tipHovered: settingsHeaderMouse.containsMouse
                tipCursor: root.keyboardNavigation && settingsHeader.hasCursor
              }

              RowLayout {
                id: settingsHeaderRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: Style.space(6)
                spacing: Style.spacing.controlGap

                PanelSectionHeader {
                  text: root.tr("section.settings", "SETTINGS")
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Item { Layout.fillWidth: true }

                Text {
                  textFormat: Text.PlainText
                  // Chevron down when open, pointing at the row when folded.
                  text: "󰅀"
                  rotation: root.settingsOpen ? 0 : (I18n.rightToLeft ? 90 : -90)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }
            }

            Column {
              id: settingsBody
              visible: root.settingsOpen
              width: parent.width
              spacing: Style.spacing.rowGap

            SettingHelp {
              width: parent.width
              text: Model.settingsSectionHelp(root.loc)
            }

            Text {
              textFormat: Text.PlainText
              visible: vpn.configError !== ""
              width: parent.width
              text: vpn.configError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            GridLayout {
              id: choiceGrid
              width: parent.width
              columns: 2
              columnSpacing: Style.spacing.rowGap
              rowSpacing: Style.spacing.labelGap

              FieldColumn {
                FieldLabel { text: Model.settingLabel("netshield", root.loc) }
                SearchableDropdown {
                  id: netshieldDropdown
                  Layout.fillWidth: true
                  Layout.preferredWidth: 0
                  showLabel: false
                  value: vpn.configDisplayValue("netshield")
                  options: Model.settingChoiceOptions("netshield", root.loc)
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  hasCursor: root.cursorActive && root.focusSection === "config:netshield"
                  placeholderText: Model.settingLabel("netshield", root.loc)
                  emptyText: vpn.configUpgrade.netshield ? root.tr("config.upgrade", "Upgrade to enable") : root.tr("config.noValues", "No values")
                  onHovered: function(on) {
                    netshieldTip.tipHovered = on
                    if (on) root.setFocusSection("config:netshield")
                  }
                  onChanged: function(value) { if (value !== vpn.configDisplayValue("netshield")) vpn.setConfig("netshield", value) }

                  SettingTip {
                    id: netshieldTip
                    text: Model.settingTooltip("netshield", root.loc)
                    tipCursor: root.keyboardNavigation && netshieldDropdown.hasCursor
                    tipPopupOpen: netshieldDropdown.popupOpen
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  visible: vpn.configUpgrade.netshield === true
                  Layout.fillWidth: true
                  text: root.tr("config.upgradeHint", "Upgrade to enable. Changing it still sends the CLI command so Proton can report the restriction.")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }

              FieldColumn {
                FieldLabel { text: Model.settingLabel("kill-switch", root.loc) }
                SearchableDropdown {
                  id: killSwitchDropdown
                  Layout.fillWidth: true
                  Layout.preferredWidth: 0
                  showLabel: false
                  value: vpn.configDisplayValue("kill-switch")
                  options: Model.settingChoiceOptions("kill-switch", root.loc)
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  hasCursor: root.cursorActive && root.focusSection === "config:kill-switch"
                  placeholderText: Model.settingLabel("kill-switch", root.loc)
                  onHovered: function(on) {
                    killSwitchTip.tipHovered = on
                    if (on) root.setFocusSection("config:kill-switch")
                  }
                  onChanged: function(value) { root.chooseKillSwitch(value) }

                  SettingTip {
                    id: killSwitchTip
                    text: Model.settingTooltip("kill-switch", root.loc)
                    tipCursor: root.keyboardNavigation && killSwitchDropdown.hasCursor
                    tipPopupOpen: killSwitchDropdown.popupOpen
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  visible: Model.isVpnActive(root.view) && root.ksConfirmValue === ""
                  Layout.fillWidth: true
                  text: root.tr("killSwitch.reconnectHint", "Changing it briefly reconnects the VPN.")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }
            }

            Column {
              id: ksConfirm
              visible: root.ksConfirmValue !== ""
              width: parent.width
              spacing: Style.spacing.rowGap

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: Model.killSwitchConfirmText(root.ksConfirmValue, Model.returnTarget(vpn.activeTarget, root.view.status, vpn.freePlan), root.loc)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Row {
                spacing: Style.spacing.rowGap

                Button {
                  text: root.tr("action.cancel", "Cancel")
                  bordered: true
                  hasCursor: root.cursorActive && root.focusSection === "ks-cancel"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.cancelKillSwitch()
                  onHovered: function(on) { if (on) root.setFocusSection("ks-cancel") }
                }

                Button {
                  text: root.tr("killSwitch.confirmButton", "Reconnect and change")
                  bordered: true
                  hasCursor: root.cursorActive && root.focusSection === "ks-confirm"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.confirmKillSwitch()
                  onHovered: function(on) { if (on) root.setFocusSection("ks-confirm") }
                }
              }
            }

            GridLayout {
              id: toggleGrid
              width: parent.width
              columns: 2
              columnSpacing: Style.spacing.rowGap
              rowSpacing: Style.spacing.rowGap

              Repeater {
                model: root.toggleSettings
                ToggleSettingRow {
                  required property var modelData
                  Layout.fillWidth: true
                  Layout.preferredWidth: 1
                  Layout.alignment: Qt.AlignTop | Qt.AlignLeft
                  setting: modelData
                }
              }

              ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop | Qt.AlignLeft
                spacing: 0

                Toggle {
                  id: customDnsToggle
                  Layout.fillWidth: true
                  implicitHeight: Style.spacing.controlHeight
                  titleSize: Style.font.body
                  label: Model.settingLabel("custom-dns", root.loc)
                  checked: Model.parseCustomDnsValue(vpn.configDisplayValue("custom-dns")).enabled
                  hasCursor: root.cursorActive && root.focusSection === "config:custom-dns"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onHovered: function(on) {
                    customDnsTip.tipHovered = on
                    if (on) root.setFocusSection("config:custom-dns")
                  }
                  onClicked: root.toggleCustomDns()

                  SettingTip {
                    id: customDnsTip
                    text: Model.settingTooltip("custom-dns", root.loc)
                    tipCursor: root.keyboardNavigation && customDnsToggle.hasCursor
                  }
                }

                Item {
                  Layout.fillWidth: true
                  height: root.showDnsField() ? dnsField.implicitHeight + Style.space(6) : 0
                  visible: height > 0
                  clip: true

                  TextField {
                    id: dnsField
                    y: Style.space(6)
                    width: parent.width
                    visible: root.showDnsField()
                    foreground: root.foreground
                    placeholderText: "1.1.1.1, 8.8.8.8"
                    text: root.dnsText
                    hasCursor: root.cursorActive && root.focusSection === "dns" && !activeFocus
                    onHoveredChanged: if (hovered) root.setFocusSection("dns")
                    onTextChanged: root.dnsText = text
                    onAccepted: root.applyDns()
                  }
                }
              }
            }

            ActionRow {
              id: trustRow
              visible: vpn.autoConnectWifi && vpn.wifiName !== ""
              width: parent.width
              title: vpn.wifiTrusted
                ? root.tr("wifi.untrust", "Stop trusting %1").arg(vpn.wifiName)
                : root.tr("wifi.trust", "Trust %1").arg(vpn.wifiName)
              subtitle: vpn.wifiTrusted
                ? root.tr("wifi.untrustHint", "Proton VPN connects automatically here again.")
                : root.tr("wifi.trustHint", "Proton VPN connects automatically on Wi-Fi you have not trusted. Trust this network to skip it.")
              sectionName: "trust"
              onActivated: vpn.toggleTrustedNetwork(vpn.wifiName)
            }

            ActionRow {
              id: signOutRow
              visible: root.view.state === Model.STATES.disconnected && !root.signOutConfirm
              width: parent.width
              title: root.tr("signout.title", "Sign out")
              subtitle: root.tr("signout.hint", "Signs this computer out of Proton VPN and clears the CLI's settings. Favorites stay.")
              sectionName: "signout"
              onActivated: root.askSignOut()
            }

            Column {
              id: signOutConfirmRow
              visible: root.signOutConfirm
              width: parent.width
              spacing: Style.spacing.rowGap

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: root.tr("signout.confirm", "Sign out of Proton VPN on this computer? You will need your password and 2FA to sign in again.")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Row {
                spacing: Style.spacing.rowGap

                Button {
                  text: root.tr("action.cancel", "Cancel")
                  bordered: true
                  hasCursor: root.cursorActive && root.focusSection === "so-cancel"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.cancelSignOut()
                  onHovered: function(on) { if (on) root.setFocusSection("so-cancel") }
                }

                Button {
                  text: root.tr("signout.title", "Sign out")
                  bordered: true
                  hasCursor: root.cursorActive && root.focusSection === "so-confirm"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.confirmSignOut()
                  onHovered: function(on) { if (on) root.setFocusSection("so-confirm") }
                }
              }
            }

            Item {
              width: parent.width
              height: Style.space(6)
            }
            }
          }
        }
      }
    }
  }

  Timer {
    interval: 15000
    running: root.opened
    repeat: true
    onTriggered: root.nowTick += 1
  }

  // One Quick connect target: a star to keep it, then its name. The row
  // connects; the current connection only says so.
  component QuickRow: CursorSurface {
    id: quickRow
    property var row: ({})
    property int rowIndex: 0
    readonly property string rowName: Model.targetName(row.target, vpn.countries, root.loc)
    readonly property bool starCursor: root.cursorActive && root.focusSection === "star:" + rowIndex

    hasCursor: root.cursorActive && root.focusSection === "quick:" + rowIndex
    foreground: root.foreground
    fill: root.hoverFill
    implicitHeight: Math.max(quickName.implicitHeight, quickStar.implicitHeight) + Style.space(10)

    MouseArea {
      id: quickMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: quickRow.row.active ? Qt.ArrowCursor : Qt.PointingHandCursor
      onEntered: root.setFocusSection("quick:" + quickRow.rowIndex)
      onClicked: root.connectQuick(quickRow.rowIndex)
    }

    SettingTip {
      text: quickRow.row.active
        ? root.tr("quick.activeTip", "You are connected here. Press f to star or unstar it.")
        : root.tr("quick.tip", "Connect to %1").arg(quickRow.rowName)
      tipHovered: quickMouse.containsMouse && !starMouse.containsMouse
      tipCursor: root.keyboardNavigation && quickRow.hasCursor
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(4)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      CursorSurface {
        Layout.preferredWidth: quickStar.implicitWidth + Style.space(10)
        Layout.preferredHeight: quickStar.implicitHeight + Style.space(4)
        hasCursor: quickRow.starCursor
        foreground: root.foreground
        fill: root.hoverFill

        Text {
          id: quickStar
          anchors.centerIn: parent
          textFormat: Text.PlainText
          // Nerd Font star, filled when kept.
          text: quickRow.row.favorite ? "\uf005" : "\uf006"
          color: quickRow.row.favorite ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        MouseArea {
          id: starMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.setFocusSection("star:" + quickRow.rowIndex)
          onClicked: root.starQuick(quickRow.rowIndex)
        }

        SettingTip {
          text: quickRow.row.favorite ? root.tr("quick.unstar", "Remove from favorites (f)") : root.tr("quick.star", "Keep in favorites (f)")
          tipHovered: starMouse.containsMouse
          tipCursor: root.keyboardNavigation && quickRow.starCursor
        }
      }

      Text {
        id: quickName
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: quickRow.rowName
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        visible: quickRow.row.active === true
        textFormat: Text.PlainText
        text: root.tr("quick.connected", "Connected")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  component FieldColumn: ColumnLayout {
    property bool fieldVisible: true
    visible: fieldVisible
    Layout.fillWidth: fieldVisible
    Layout.preferredWidth: fieldVisible ? 1 : 0
    Layout.minimumWidth: 0
    Layout.alignment: Qt.AlignTop | Qt.AlignLeft
    spacing: Style.spacing.labelGap
  }

  component FieldLabel: Text {
    Layout.fillWidth: true
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.subtitle
    font.bold: true
  }

  component ActionRow: CursorSurface {
    id: actionRow
    property string title: ""
    property string subtitle: ""
    property string sectionName: ""
    property string tipText: ""
    signal activated()

    hasCursor: root.cursorActive && root.focusSection === sectionName
    foreground: root.foreground
    fill: root.hoverFill
    implicitHeight: actionInner.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setFocusSection(actionRow.sectionName)
      onClicked: actionRow.activated()
    }

    SettingTip {
      text: actionRow.tipText
      tipHovered: actionMouse.containsMouse
      tipCursor: root.keyboardNavigation && actionRow.hasCursor
    }

    Column {
      id: actionInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(1)

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: actionRow.title
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        visible: actionRow.subtitle !== ""
        text: actionRow.subtitle
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""
    Layout.fillWidth: false
    spacing: Style.spacing.controlGap

    Text {
      textFormat: Text.PlainText
      text: label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      textFormat: Text.PlainText
      text: value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }
  }

  component SettingHelp: Text {
    Layout.fillWidth: true
    visible: true
    opacity: text !== "" ? 1 : 0
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  component SettingTip: PanelToolTip {
    property bool tipHovered: false
    property bool tipCursor: false
    property bool tipPopupOpen: false
    visible: text !== "" && (tipHovered || tipCursor) && !tipPopupOpen
    fontFamily: root.fontFamily
  }

  component ToggleSettingRow: Toggle {
    id: toggleSettingRow
    property var setting: ({})
    property bool tipHovered: false
    readonly property string key: String(setting.key || "")
    readonly property string currentValue: vpn.configDisplayValue(key)
    readonly property bool upgrade: vpn.configUpgrade && vpn.configUpgrade[key] === true
    objectName: "config:" + key

    Layout.fillWidth: true
    implicitHeight: Style.spacing.controlHeight
    titleSize: Style.font.body
    label: Model.settingLabel(key, root.loc)
    checked: String(currentValue) === "on"
    hasCursor: root.cursorActive && root.focusSection === "config:" + key
    foreground: root.foreground
    fontFamily: root.fontFamily
    onHovered: function(on) {
      tipHovered = on
      if (on) root.setFocusSection("config:" + key)
    }
    onClicked: vpn.setConfig(key, checked ? "off" : "on")

    SettingTip {
      text: Model.settingTooltip(toggleSettingRow.key, root.loc)
      tipHovered: toggleSettingRow.tipHovered
      tipCursor: root.keyboardNavigation && toggleSettingRow.hasCursor
    }
  }
}
