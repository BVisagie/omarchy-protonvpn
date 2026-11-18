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
  // Esc, or any action key, hides the tooltip that is showing; moving the
  // cursor or the pointer to another control shows its own again.
  property bool tipsDismissed: false
  property int openTips: 0
  onFocusSectionChanged: tipsDismissed = false

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
  readonly property bool pickerOpen: modeDropdown.popupOpen || countryDropdown.popupOpen || cityDropdown.popupOpen || netshieldDropdown.popupOpen
  readonly property bool editorFocused: (serverField.visible && serverField.activeFocus) || (dnsField.visible && dnsField.activeFocus)
  readonly property bool signOutAvailable: view.state === Model.STATES.disconnected
  readonly property var statusLines: statusLineList()
  readonly property var cliInfo: Model.cliVersionInfo(vpn.cliPackage, Date.now() + nowTick, root.loc)
  // Disconnected, or connecting: the button under CONNECT starts the
  // connection; connected with edited choices, it switches.
  readonly property bool showConnectButton: offerSwitch || view.state === Model.STATES.disconnected
  readonly property string refreshTip: {
    if (vpn.refreshing) return tr("refresh.runningTip", "Checking Proton VPN…")
    var updated = Model.relativeTime(view.lastUpdatedMs, Date.now() + nowTick, root.loc)
    return updated !== ""
      ? tr("refresh.tipUpdated", "Updated %1. Refresh status, locations, and settings (r)").arg(updated)
      : tr("refresh.tip", "Refresh status, locations, and settings (r)")
  }
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

  function countryOptionList() {
    var list = []
    for (var i = 0; i < vpn.countries.length; i++) {
      list.push({ value: vpn.countries[i].code, label: vpn.countries[i].name, description: vpn.countries[i].code })
    }
    return list
  }

  function cityOptionList() {
    var list = []
    for (var i = 0; i < vpn.cities.length; i++) {
      var city = vpn.cities[i]
      list.push(city.features !== "" ? { value: city.name, label: city.name, description: city.features } : { value: city.name, label: city.name })
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

  // One label/value line per topic: the session, its traffic, and what
  // protects it. "Updated" lives in Refresh's tooltip unless status is stale.
  function statusLineList() {
    var lines = []
    var status = view.status || ({})
    var now = Date.now() + nowTick
    var session = []
    if (view.state === Model.STATES.connected) {
      var up = vpn.linkActive ? Model.durationText(vpn.linkSinceMs, now, root.loc) : ""
      if (up !== "") session.push({ label: tr("status.duration", "Connected for"), value: up })
      session.push({ label: tr("status.load", "Load"), value: Model.displayLoad(status.load, root.loc) })
      if (status.exitIp) session.push({ label: tr("status.exitIp", "Exit IP"), value: status.exitIp })
    } else if (view.state === Model.STATES.stale) {
      if (status.protocol) session.push({ label: tr("status.load", "Load"), value: Model.displayLoad(status.load, root.loc) })
      var when = Model.relativeTime(view.lastUpdatedMs, now, root.loc)
      if (when !== "") session.push({ label: tr("status.lastUpdate", "Last update"), value: when })
    }
    if (session.length > 0) lines.push(session)
    if (view.state === Model.STATES.connected) {
      var traffic = Model.trafficPairs(vpn.traffic, root.loc)
      if (traffic.length > 0) lines.push(traffic)
    }
    if (showHealthy && vpn.configLoaded) {
      var protections = Model.protectionPairs(vpn.configValues, view, root.loc)
      if (protections.length > 0) lines.push(protections)
    }
    return lines
  }


  function visibleFocusRows() {
    var rows = []
    rows.push(powerSwitchShown ? ["refresh", "header"] : ["refresh"])
    if (view.state === Model.STATES.cliMissing) rows.push(["install"])
    if (view.state === Model.STATES.signedOut) rows.push(["signin"])
    if (copyCommand !== "") rows.push(["copy"])
    if (vpn.countriesError !== "" || vpn.citiesError !== "") rows.push(["retry-locations"])
    if (showWrites && vpn.installed) {
      rows.push(["mode"])
      var place = []
      if (needsCountry) place.push("country")
      if (needsCity) place.push("city")
      if (needsServer) place.push("server")
      if (place.length > 0) rows.push(place)
      if (showConnectButton) rows.push(["switch"])
      for (var q = 0; q < quickRows.length; q++) rows.push(["star:" + q, "quick:" + q])
      rows.push(["settings"])
      if (settingsOpen && vpn.configLoaded) {
        // The rows as they appear: switches in pairs, then the footer line.
        if (vpn.autoConnectWifi && vpn.wifiName !== "") rows.push(["trust"])
        rows.push(["config:netshield"])
        rows.push(["config:kill-switch", "config:vpn-accelerator"])
        if (ksConfirmValue !== "") rows.push(["ks-cancel", "ks-confirm"])
        rows.push(["config:custom-dns", "config:ipv6"])
        if (showDnsField()) rows.push(["dns"])
        rows.push(["config:port-forwarding", "config:moderate-nat"])
        rows.push(["config:anonymous-crash-reports"])
      }
      // The footer line shows even when settings failed to load.
      if (settingsOpen) {
        var footer = []
        if (signOutConfirm) footer = ["so-cancel", "so-confirm"]
        else {
          if (cliInfo.installed !== "") footer.push("cli-check")
          if (cliInfo.newer) footer.push("cli-update")
          if (signOutAvailable) footer.push("signout")
        }
        if (footer.length > 0) rows.push(footer)
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
    else if (focusSection === "switch") primaryConnect()
    else if (focusSection === "settings") toggleSettingsFold()
    else if (focusSection.indexOf("quick:") === 0) connectQuick(parseInt(focusSection.substring(6), 10))
    else if (focusSection.indexOf("star:") === 0) starQuick(parseInt(focusSection.substring(5), 10))
    else if (focusSection === "dns") applyDns()
    else if (focusSection === "ks-cancel") cancelKillSwitch()
    else if (focusSection === "ks-confirm") confirmKillSwitch()
    else if (focusSection === "trust") vpn.toggleTrustedNetwork(vpn.wifiName)
    else if (focusSection === "cli-check") vpn.checkCliUpdates()
    else if (focusSection === "cli-update") vpn.updateSystem()
    else if (focusSection === "signout") askSignOut()
    else if (focusSection === "so-cancel") cancelSignOut()
    else if (focusSection === "so-confirm") confirmSignOut()
    else if (focusSection.indexOf("config:") === 0) activateConfig(focusSection.substring(7))
  }

  function activateConfig(key) {
    var def = Model.settingDef(key)
    // Until settings load, a switch shows Off without knowing; changing it
    // then would send a guess.
    if (!def || !vpn.configLoaded) return
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
    else if (key === "kill-switch") chooseKillSwitch(switchChecked("kill-switch") ? "off" : "standard")
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
    scrollItemIntoView(cliFooter)
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

  function primaryConnect() {
    if (view.state === Model.STATES.connected) switchNow()
    else if (view.state === Model.STATES.disconnected) tryToggle()
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
    vpn.readCliPackage()
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
    else if (focusSection === "refresh") scrollItemIntoView(header)
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
    else if (focusSection === "ks-cancel" || focusSection === "ks-confirm") scrollItemIntoView(ksConfirm)
    else if (focusSection === "trust") scrollItemIntoView(trustRow)
    else if (focusSection === "cli-check" || focusSection === "cli-update") scrollItemIntoView(cliFooter)
    else if (focusSection === "signout") scrollItemIntoView(cliFooter)
    else if (focusSection === "so-cancel" || focusSection === "so-confirm") scrollItemIntoView(cliFooter)
    else if (focusSection.indexOf("config:") === 0) scrollItemIntoView(findSection(settingsBody, focusSection) || settingsBody)
  }

  // A setting's tooltip; on the free plan it says the setting needs an upgrade.
  function settingTip(key) {
    var tip = Model.settingTooltip(key, root.loc)
    return vpn.configUpgrade[key] === true ? tr("config.upgradeTip", "Upgrade to enable. %1").arg(tip) : tip
  }

  function switchChecked(key) {
    var value = vpn.configDisplayValue(key)
    if (key === "custom-dns") return Model.parseCustomDnsValue(value).enabled
    if (key === "kill-switch") return value !== "" && value !== "off"
    return value === "on"
  }

  // SETTINGS rows carry their cursor name as objectName.
  function findSection(item, name) {
    if (!item) return null
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) {
      var found = findSection(item.children[i], name)
      if (found) return found
    }
    return null
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // A dropdown keeps keyboard focus after its list closes, and with it a
  // focus ring beside the cursor's; hand focus back to the panel.
  onPickerOpenChanged: if (!pickerOpen) Qt.callLater(function() {
    // A click that closed the list may have landed in a text field.
    if (root.opened && !root.pickerOpen && !root.editorFocused) keyCatcher.forceActiveFocus()
  })

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

  // Hides the tooltips that are showing; false when none was.
  function dismissTips() {
    if (openTips === 0 || tipsDismissed) return false
    tipsDismissed = true
    return true
  }

  // A tooltip counts once while visible, and stops counting when destroyed.
  function countTip(tip, on) {
    if (tip.counted === on) return
    tip.counted = on
    openTips = Math.max(0, openTips + (on ? 1 : -1))
  }

  function openPanel() {
    tipsDismissed = false
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
    // Omarchy still limits the panel to the screen; 720 lets the open panel
    // fit without scrolling in all but its fullest states.
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.pickerOpen || root.editorFocused
      onMoveRequested: function(dx, dy) {
        root.keyboardNavigation = true
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: {
        root.dismissTips()
        if (root.cursorActive) root.activateCursor()
      }
      // The first Esc hides a tooltip; the next one closes as before.
      onCloseRequested: {
        if (!root.dismissTips()) {
          if (root.ksConfirmValue !== "") root.cancelKillSwitch()
          else root.close()
        }
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        root.dismissTips()
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
                  spacing: Style.space(10)

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

                PanelActionButton {
                  id: refreshAction
                  property bool hot: false
                  anchors.verticalCenter: parent.verticalCenter
                  // Dimmed, not disabled: a disabled button stops showing the cursor.
                  opacity: vpn.refreshing ? 0.45 : 1
                  iconText: "󰑐"
                  foreground: hero.foreground
                  fontFamily: hero.fontFamily
                  hasCursor: root.cursorActive && root.focusSection === "refresh"
                  onClicked: root.refreshAll()
                  onHovered: function(on) {
                    hot = on
                    if (on) root.setFocusSection("refresh")
                  }

                  SettingTip {
                    text: root.refreshTip
                    tipHovered: refreshAction.hot
                    tipCursor: root.keyboardNavigation && refreshAction.hasCursor
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

                  SettingTip {
                    text: root.toggleHint
                    tipHovered: powerSwitch.containsMouse
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

          Column {
            id: statusBlock
            visible: root.statusLines.length > 0
            width: parent.width
            spacing: Style.spacing.labelGap

            Repeater {
              model: root.statusLines

              // Flow wraps a line only when its values (an IPv6 exit IP) do not fit.
              Flow {
                id: statusLine
                required property var modelData
                width: statusBlock.width
                // Flow spaces rows too; keep lines tight and gap the pairs here.
                spacing: 0

                Repeater {
                  model: statusLine.modelData
                  Item {
                    required property var modelData
                    required property int index
                    implicitWidth: pair.implicitWidth + (index < statusLine.modelData.length - 1 ? Style.spacing.xxl : 0)
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
            }
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

          // Separators sit between blocks, so the gap above and below each is
          // the panel gap.
          PanelSeparator {
            visible: connectBlock.visible
            foreground: root.foreground
          }

          Column {
            id: connectBlock
            visible: root.showWrites && vpn.installed
            width: parent.width
            spacing: Style.spacing.rowGap

            PanelSectionHeader {
              text: root.tr("section.connect", "CONNECT")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            // Mode has the full width in every mode so nothing jumps; where to
            // connect goes on the row below, at most two fields wide.
            FieldColumn {
              width: parent.width
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

            RowLayout {
              id: connectRow
              visible: root.needsCountry || root.needsServer
              width: parent.width
              spacing: Style.spacing.rowGap

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
                  onAccepted: {
                    root.dismissTips()
                    root.offerSwitch ? root.switchNow() : root.tryToggle()
                  }
                  // Esc hides a tooltip, then hands the keys back to the panel.
                  Keys.onEscapePressed: if (!root.dismissTips()) keyCatcher.forceActiveFocus()

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

            TipButton {
              id: switchButton
              visible: root.showConnectButton
              width: parent.width
              bordered: true
              // The panel's one emphasised action, in the kit's own style.
              active: root.view.state !== Model.STATES.connected
              verticalPadding: Style.space(9)
              text: Model.connectButtonLabel(root.view.state, root.connectOptions(), vpn.countries, root.loc)
              section: "switch"
              tip: root.view.state === Model.STATES.connected
                ? root.tr("connect.switchTip", "Reconnect with these choices. Proton replaces the current connection.")
                : root.tr("connect.connectTip", "Connect with these choices (t)")
              hasCursor: root.cursorActive && root.focusSection === "switch"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.primaryConnect()
            }
          }

          Column {
            id: quickBlock
            visible: root.showWrites && vpn.installed && root.quickRows.length > 0
            width: parent.width
            spacing: Style.spacing.rowGap

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

          PanelSeparator {
            visible: settingsBlock.visible
            foreground: root.foreground
          }

          Column {
            id: settingsBlock
            visible: root.showWrites && vpn.installed
            width: parent.width
            spacing: Style.spacing.rowGap

            // Styled like the CONNECT header; the chevron carries the cursor,
            // as the network panel's header actions do, and the whole row clicks.
            Item {
              id: settingsHeader
              width: parent.width
              implicitHeight: settingsChevron.height

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
                tipCursor: root.keyboardNavigation && settingsChevron.hasCursor
              }

              PanelSectionHeader {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.tr("section.settings", "SETTINGS")
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              PanelActionButton {
                id: settingsChevron
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: root.settingsOpen ? "󰅀" : (I18n.rightToLeft ? "󰅁" : "󰅂")
                foreground: root.foreground
                fontFamily: root.fontFamily
                hasCursor: root.cursorActive && root.focusSection === "settings"
                onClicked: root.toggleSettingsFold()
                onHovered: function(on) { if (on) root.setFocusSection("settings") }
              }
            }

            // NetShield on its own row, the switches in two columns, and the
            // CLI on one footer line. Captions live in tooltips, so every row
            // is one line and the open panel fits without scrolling.
            Column {
              id: settingsBody
              visible: root.settingsOpen
              width: parent.width
              spacing: Style.space(2)

              Text {
                textFormat: Text.PlainText
                visible: vpn.configError !== ""
                width: parent.width
                leftPadding: Style.spacing.controlPaddingX
                bottomPadding: Style.space(4)
                text: vpn.configError
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }

              SettingRow {
                id: trustRow
                visible: vpn.autoConnectWifi && vpn.wifiName !== ""
                width: parent.width
                section: "trust"
                title: vpn.wifiTrusted
                  ? root.tr("wifi.untrust", "Stop trusting %1").arg(vpn.wifiName)
                  : root.tr("wifi.trust", "Trust %1").arg(vpn.wifiName)
                tip: vpn.wifiTrusted
                  ? root.tr("wifi.untrustHint", "Proton VPN connects automatically here again.")
                  : root.tr("wifi.trustHint", "Proton VPN connects automatically on Wi-Fi you have not trusted. Trust this network to skip it.")
                onActivated: vpn.toggleTrustedNetwork(vpn.wifiName)
              }

              SettingRow {
                width: parent.width
                section: "config:netshield"
                title: Model.settingLabel("netshield", root.loc)
                tip: root.settingTip("netshield")
                tipBlocked: netshieldDropdown.popupOpen
                onActivated: netshieldDropdown.toggle()

                // The open list is as wide as this field; 62% leaves room for
                // the longest option description beside the NetShield label.
                SearchableDropdown {
                  id: netshieldDropdown
                  width: Math.round(settingsBody.width * 0.62)
                  showLabel: false
                  value: vpn.configDisplayValue("netshield")
                  options: Model.settingChoiceOptions("netshield", root.loc)
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  hasCursor: root.cursorActive && root.focusSection === "config:netshield"
                  placeholderText: Model.settingLabel("netshield", root.loc)
                  emptyText: vpn.configUpgrade.netshield ? root.tr("config.upgrade", "Upgrade to enable") : root.tr("config.noValues", "No values")
                  onHovered: function(on) { if (on) root.setFocusSection("config:netshield") }
                  onChanged: function(value) { if (value !== vpn.configDisplayValue("netshield")) vpn.setConfig("netshield", value) }
                }
              }

              SwitchPair { leftKey: "kill-switch"; rightKey: "vpn-accelerator" }

              Column {
                id: ksConfirm
                visible: root.ksConfirmValue !== ""
                width: parent.width
                leftPadding: Style.spacing.controlPaddingX
                topPadding: Style.space(4)
                bottomPadding: Style.space(6)
                spacing: Style.spacing.rowGap

                Text {
                  textFormat: Text.PlainText
                  width: parent.width - parent.leftPadding
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

              SwitchPair { leftKey: "custom-dns"; rightKey: "ipv6" }

              Item {
                width: parent.width
                height: root.showDnsField() ? dnsField.implicitHeight + Style.space(6) : 0
                visible: height > 0
                clip: true

                TextField {
                  id: dnsField
                  x: Style.spacing.controlPaddingX
                  y: Style.space(2)
                  width: parent.width - Style.spacing.controlPaddingX * 2
                  visible: root.showDnsField()
                  foreground: root.foreground
                  placeholderText: "1.1.1.1, 8.8.8.8"
                  text: root.dnsText
                  hasCursor: root.cursorActive && root.focusSection === "dns" && !activeFocus
                  onHoveredChanged: if (hovered) root.setFocusSection("dns")
                  onTextChanged: root.dnsText = text
                  onAccepted: {
                    root.dismissTips()
                    root.applyDns()
                  }
                  // Esc hides a tooltip, then hands the keys back to the panel.
                  Keys.onEscapePressed: if (!root.dismissTips()) keyCatcher.forceActiveFocus()
                }
              }

              SwitchPair { leftKey: "port-forwarding"; rightKey: "moderate-nat" }
              SwitchPair { leftKey: "anonymous-crash-reports"; rightKey: "" }

              // The CLI on one line: version and state, Check, Update when
              // newer, and Sign out while disconnected. Signing out swaps the
              // line for its confirm, so nothing grows.
              Item {
                id: cliFooter
                visible: root.cliInfo.installed !== "" || root.signOutAvailable || root.signOutConfirm
                width: parent.width
                implicitHeight: footerRow.implicitHeight + Style.spacing.rowGap * 2

                Rectangle {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.topMargin: Style.space(4)
                  height: 1
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
                }

                RowLayout {
                  id: footerRow
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  anchors.leftMargin: Style.spacing.controlPaddingX
                  anchors.rightMargin: Style.spacing.controlPaddingX
                  spacing: Style.spacing.rowGap

                  Text {
                    id: cliBlock
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    color: root.signOutConfirm ? root.urgent : root.foreground
                    text: root.signOutConfirm
                      ? root.tr("signout.ask", "Sign out?")
                      : (root.cliInfo.installed !== "" ? root.tr("cli.installedVersion", "Proton VPN CLI %1").arg(root.cliInfo.installed) : "")

                    Text {
                      x: parent.contentWidth + Style.space(6)
                      width: Math.max(0, parent.width - x)
                      anchors.baseline: parent.baseline
                      textFormat: Text.PlainText
                      elide: Text.ElideRight
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      color: root.signOutConfirm ? root.dim
                        : (vpn.cliCheckError !== "" ? root.urgent : (root.cliInfo.newer ? Color.accent : root.dim))
                      text: root.signOutConfirm
                        ? root.tr("signout.favoritesStay", "Favorites stay.")
                        : (vpn.cliCheckError !== "" ? "· " + root.tr("cli.checkFailedShort", "check failed")
                          : (root.cliInfo.newer ? "→ " + root.cliInfo.latest
                            : (root.cliInfo.status !== "" ? "· " + root.cliInfo.status : "")))
                    }
                  }

                  TipButton {
                    visible: !root.signOutConfirm && root.cliInfo.installed !== ""
                    bordered: true
                    verticalPadding: Style.space(3)
                    text: vpn.cliChecking ? root.tr("cli.checking", "Checking…") : root.tr("cli.check", "Check")
                    section: "cli-check"
                    tip: (vpn.cliCheckError !== "" ? vpn.cliCheckError + " " : "")
                      + (root.cliInfo.source !== "" ? root.tr("cli.latestFrom", "Latest from %1.").arg(root.cliInfo.source) + " " : "")
                      + root.tr("cli.checkTip", "Asks your Arch mirrors with checkupdates. Nothing else reaches the network.")
                    hasCursor: root.cursorActive && root.focusSection === "cli-check"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: vpn.checkCliUpdates()
                  }

                  TipButton {
                    visible: !root.signOutConfirm && root.cliInfo.newer
                    bordered: true
                    verticalPadding: Style.space(3)
                    text: root.tr("cli.update", "Update")
                    section: "cli-update"
                    tip: root.tr("cli.updateTip", "Opens Omarchy's system update in a terminal. It updates every package, the Proton VPN CLI included.")
                    hasCursor: root.cursorActive && root.focusSection === "cli-update"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: vpn.updateSystem()
                  }

                  // Quiet until the cursor reaches it, then red: it is the one
                  // destructive action here.
                  TipButton {
                    id: signOutRow
                    readonly property bool armed: root.cursorActive && root.focusSection === "signout"
                    visible: !root.signOutConfirm && root.signOutAvailable
                    bordered: armed
                    verticalPadding: Style.space(3)
                    text: root.tr("signout.title", "Sign out")
                    section: "signout"
                    tip: root.tr("signout.tip", "Clears the CLI's settings; signing in again needs your password and 2FA. Favorites stay.")
                    hasCursor: armed
                    foreground: armed ? root.urgent : root.foreground
                    fontFamily: root.fontFamily
                    onClicked: root.askSignOut()
                  }

                  Button {
                    id: signOutConfirmRow
                    visible: root.signOutConfirm
                    bordered: true
                    verticalPadding: Style.space(3)
                    text: root.tr("action.cancel", "Cancel")
                    hasCursor: root.cursorActive && root.focusSection === "so-cancel"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: root.cancelSignOut()
                    onHovered: function(on) { if (on) root.setFocusSection("so-cancel") }
                  }

                  Button {
                    visible: root.signOutConfirm
                    bordered: true
                    verticalPadding: Style.space(3)
                    text: root.tr("signout.title", "Sign out")
                    hasCursor: root.cursorActive && root.focusSection === "so-confirm"
                    foreground: root.urgent
                    fontFamily: root.fontFamily
                    onClicked: root.confirmSignOut()
                    onHovered: function(on) { if (on) root.setFocusSection("so-confirm") }
                  }
                }
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
    implicitHeight: Math.max(Style.spacing.controlHeight, quickName.implicitHeight + Style.space(8))

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
      // The star's box is 10 wider than the star, so the star sits on the
      // same text edge as the SETTINGS rows.
      anchors.leftMargin: Style.spacing.controlPaddingX - Style.space(5)
      anchors.rightMargin: Style.spacing.controlPaddingX
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

  // Labels sit quietly above the fields they name; the values are bright.
  component FieldLabel: Text {
    Layout.fillWidth: true
    textFormat: Text.PlainText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
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

  component SettingTip: PanelToolTip {
    id: tipPopup
    property bool tipHovered: false
    property bool tipCursor: false
    property bool tipPopupOpen: false
    property bool counted: false
    // An open dropdown takes Esc for itself, so no tooltip shows over one.
    visible: text !== "" && (tipHovered || tipCursor) && !tipPopupOpen && !root.pickerOpen && !root.tipsDismissed
    onVisibleChanged: root.countTip(tipPopup, visible)
    Component.onDestruction: root.countTip(tipPopup, false)
    fontFamily: root.fontFamily
  }

  // A Button whose tooltip the panel counts, so Esc can hide it; it shows
  // under the pointer and under the keyboard cursor, as SettingTip does.
  component TipButton: Button {
    id: tipButton
    property string tip: ""
    property string section: ""
    property bool mouseIn: false
    onHovered: function(on) {
      mouseIn = on
      if (on) root.setFocusSection(section)
    }

    SettingTip {
      text: tipButton.tip
      tipHovered: tipButton.mouseIn
      tipCursor: root.keyboardNavigation && root.cursorActive && root.focusSection === tipButton.section
    }
  }

  // A SETTINGS row: label and an optional caption on the left, its control
  // on the right. Borderless; the cursor and hover tint it, as Omarchy's
  // list rows do. A row without a section is not a cursor stop itself.
  component SettingRow: CursorSurface {
    id: settingRow
    property string section: ""
    property string title: ""
    property string caption: ""
    property color captionColor: root.dim
    property string tip: ""
    property bool tipBlocked: false
    property bool danger: false
    default property alias controls: controlSlot.data
    signal activated()

    objectName: section
    hasCursor: section !== "" && root.cursorActive && root.focusSection === section
    foreground: danger ? root.urgent : root.foreground
    fill: danger ? Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.10) : root.hoverFill
    implicitHeight: Math.max(Style.spacing.controlHeight, rowText.implicitHeight + Style.space(8), controlSlot.implicitHeight + Style.space(4))

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: settingRow.section !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: if (settingRow.section !== "") root.setFocusSection(settingRow.section)
      onClicked: settingRow.activated()
    }

    SettingTip {
      text: settingRow.tip
      tipHovered: rowMouse.containsMouse
      tipCursor: root.keyboardNavigation && settingRow.hasCursor
      tipPopupOpen: settingRow.tipBlocked
    }

    Column {
      id: rowText
      anchors.left: parent.left
      anchors.right: controlSlot.left
      anchors.leftMargin: Style.spacing.controlPaddingX
      anchors.rightMargin: Style.spacing.controlGap
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: settingRow.title
        color: settingRow.danger && settingRow.hasCursor ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        visible: settingRow.caption !== ""
        width: parent.width
        text: settingRow.caption
        color: settingRow.captionColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }

    Row {
      id: controlSlot
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.controlPaddingX
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.rowGap
    }
  }

  // Two switch rows side by side, split by a hairline. An empty right key
  // leaves that half blank.
  component SwitchPair: RowLayout {
    id: switchPair
    property string leftKey: ""
    property string rightKey: ""
    width: parent ? parent.width : 0
    spacing: Style.space(10)

    SwitchCell {
      key: switchPair.leftKey
      Layout.fillWidth: true
      Layout.preferredWidth: 1
    }

    Rectangle {
      Layout.fillHeight: true
      Layout.preferredWidth: 1
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
    }

    Item {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      implicitHeight: rightCell.visible ? rightCell.implicitHeight : 0

      SwitchCell {
        id: rightCell
        visible: key !== ""
        anchors.fill: parent
        key: switchPair.rightKey
      }
    }
  }

  component SwitchCell: SettingRow {
    id: cell
    property string key: ""
    section: key !== "" ? "config:" + key : ""
    title: key !== "" ? Model.settingShortLabel(key, root.loc) : ""
    tip: key !== "" ? root.settingTip(key) : ""
    onActivated: root.activateConfig(key)

    ToggleSwitch {
      interactive: false
      checked: root.switchChecked(cell.key)
      busy: vpn.pendingSetting !== "" && vpn.pendingSetting === cell.key
      foreground: root.foreground
    }
  }


}
