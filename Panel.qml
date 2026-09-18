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
    if (Model.iconUrgent(view.state)) return bar ? bar.urgent : Color.urgent
    if (Model.iconDim(view.state)) return Qt.darker(barForeground, 1.55)
    return barForeground
  }
  readonly property color iconColor: {
    if (Model.iconUrgent(view.state)) return urgent
    if (Model.iconDim(view.state)) return dim
    return foreground
  }
  // Header controls derive visibility from state, never from a child's
  // `visible`: that reads false while the parent is hidden, so a parent bound
  // to it could never show again.
  readonly property string heroDetailText: Model.heroDetail(view)
  readonly property bool powerSwitchShown: vpn.installed && (Model.canWrite(view.state) || view.state === Model.STATES.connecting || view.state === Model.STATES.disconnecting)
  readonly property string toggleHint: {
    if (view.state === Model.STATES.connecting) return "Connecting…"
    if (view.state === Model.STATES.disconnecting) return "Disconnecting…"
    if (view.state === Model.STATES.connected) return "Disconnect Proton VPN"
    return "Connect Proton VPN"
  }
  readonly property var countryOptions: countryOptionList()
  readonly property var cityOptions: cityOptionList()
  readonly property var modeOptions: Model.CONNECTION_MODES
  readonly property bool needsCountry: Model.modeNeedsCountry(selectedMode)
  readonly property bool requiresCountry: Model.modeRequiresCountry(selectedMode)
  readonly property bool needsCity: Model.modeNeedsCity(selectedMode)
  readonly property bool needsServer: Model.modeNeedsServer(selectedMode)
  readonly property var configSettings: Model.CONFIG_SETTINGS
  readonly property string copyCommand: Model.copyCommandFor(view.state)
  readonly property bool pickerOpen: modeDropdown.popupOpen || countryDropdown.popupOpen || cityDropdown.popupOpen || netshieldDropdown.popupOpen || killSwitchDropdown.popupOpen
  readonly property bool editorFocused: (serverField.visible && serverField.activeFocus) || (dnsField.visible && dnsField.activeFocus)
  readonly property var netshieldSetting: Model.settingDef("netshield")
  readonly property var killSwitchSetting: Model.settingDef("kill-switch")
  readonly property var toggleSettings: toggleSettingList()
  readonly property var statusPairs: statusPairList()
  readonly property bool offerSwitch: Model.shouldOfferSwitch({
    state: view.state,
    busy: vpn.actionBusy,
    draft: connectOptions(),
    activeTarget: vpn.activeTarget,
    draftDirty: connectDraftDirty
  })
  readonly property var recentChoices: Model.recentChoices(vpn.recentTargets, vpn.activeTarget)
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
    if (vpn.countriesLoading) return "Loading countries…"
    if (vpn.countriesError !== "") return vpn.countriesError
    return "No countries found"
  }

  function cityEmptyText() {
    if (vpn.citiesLoading) return "Loading cities…"
    if (vpn.citiesError !== "") return vpn.citiesError
    if (selectedCountry === "") return "Choose a country first"
    return "No cities found"
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
    if (view.state === Model.STATES.connected || (view.stale && status.protocol !== "")) {
      list.push({ label: "Load", value: Model.displayLoad(status.load) })
    }
    if (status.exitIp !== "") list.push({ label: "Exit IP", value: status.exitIp })
    var updated = Model.lastUpdatedText(view, Date.now() + nowTick)
    if (updated !== "") list.push({ label: view.stale ? "Stale" : "Updated", value: updated })
    return list
  }

  function visibleFocusRows() {
    var rows = []
    if (vpn.installed && (Model.canWrite(view.state) || view.state === Model.STATES.connecting || view.state === Model.STATES.disconnecting)) rows.push(["header"])
    if (copyCommand !== "") rows.push(["copy"])
    if (view.state === Model.STATES.signedOut) rows.push(["terminal"])
    rows.push(["refresh"])
    if (vpn.countriesError !== "" || vpn.citiesError !== "") rows.push(["retry-locations"])
    if (showWrites && vpn.installed) {
      var connect = ["mode"]
      if (needsCountry) connect.push("country")
      if (needsCity) connect.push("city")
      if (needsServer) connect.push("server")
      rows.push(connect)
      if (offerSwitch) rows.push(["switch"])
      if (recentChoices.length > 0) {
        var recent = []
        for (var r = 0; r < recentChoices.length; r++) recent.push("recent:" + r)
        rows.push(recent)
      }
      if (vpn.configLoaded) {
        rows.push(["config:netshield", "config:kill-switch"])
        if (ksConfirmValue !== "") rows.push(["ks-cancel", "ks-confirm"])
        rows.push(["config:port-forwarding", "config:vpn-accelerator"])
        rows.push(["config:moderate-nat", "config:ipv6"])
        rows.push(["config:anonymous-crash-reports", "config:custom-dns"])
        if (showDnsField()) rows.push(["dns"])
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
    else if (focusSection === "terminal") vpn.openTerminal()
    else if (focusSection === "mode") modeDropdown.toggle()
    else if (focusSection === "country") countryDropdown.toggle()
    else if (focusSection === "city" && selectedCountry !== "") cityDropdown.toggle()
    else if (focusSection === "server") Qt.callLater(function() { if (serverField) serverField.forceActiveFocus() })
    else if (focusSection === "switch") switchNow()
    else if (focusSection.indexOf("recent:") === 0) connectRecent(parseInt(focusSection.substring(7), 10))
    else if (focusSection === "dns") applyDns()
    else if (focusSection === "ks-cancel") cancelKillSwitch()
    else if (focusSection === "ks-confirm") confirmKillSwitch()
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
    var plan = Model.buildConnectCommand(connectOptions())
    if (!plan.ok) {
      vpn.reportError(plan.message)
      if (!root.opened) root.open()
      return
    }
    vpn.connectWith(connectOptions())
  }

  function connectRecent(index) {
    var target = recentChoices[index]
    if (target) vpn.connectWith(target)
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
    var checked = Model.validateDnsList(dnsText)
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
    var checked = Model.validateDnsList(dnsText)
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
    else if (focusSection === "terminal") scrollItemIntoView(terminalRow)
    else if (focusSection === "mode") scrollItemIntoView(modeDropdown)
    else if (focusSection === "country") scrollItemIntoView(countryDropdown)
    else if (focusSection === "city") scrollItemIntoView(cityDropdown)
    else if (focusSection === "server") scrollItemIntoView(serverField)
    else if (focusSection === "switch") scrollItemIntoView(switchButton)
    else if (focusSection.indexOf("recent:") === 0) scrollItemIntoView(recentGrid)
    else if (focusSection === "dns") scrollItemIntoView(dnsField)
    else if (focusSection === "config:netshield") scrollItemIntoView(netshieldDropdown)
    else if (focusSection === "config:kill-switch") scrollItemIntoView(killSwitchDropdown)
    else if (focusSection === "config:custom-dns") scrollItemIntoView(customDnsToggle)
    else if (focusSection === "ks-cancel" || focusSection === "ks-confirm") scrollItemIntoView(ksConfirm)
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

  function choiceOptions(def) {
    var options = []
    if (!def || !def.values) return options
    for (var i = 0; i < def.values.length; i++) {
      var value = def.values[i]
      var option = {
        value: value,
        label: def.valueLabels && def.valueLabels[value] ? def.valueLabels[value] : value
      }
      if (def.valueDescriptions && def.valueDescriptions[value]) option.description = def.valueDescriptions[value]
      options.push(option)
    }
    return options
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    trackOpen(opened)
    if (opened) openPanel()
    else ksConfirmValue = ""
  }
  onVpnChanged: {
    if (countedVpn && countedVpn !== vpn) {
      countedVpn.panelClosed()
      countedVpn = null
      trackOpen(opened)
    }
    if (vpn) vpn.setSettings(root.settings)
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
  onSettingsChanged: if (vpn) vpn.setSettings(root.settings)
  Component.onCompleted: if (vpn) vpn.setSettings(root.settings)
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
  }

  Connections {
    target: vpn
    function onStateChanged() { root.ensureCursor() }
    // Any new connection (Switch, RECENT, toggle, IPC) settles the draft.
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
    function status(): string { return Model.tooltipText(root.view) }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: Model.tooltipText(root.view)
    iconComponent: Component {
      Item {
        ProtonVpnIcon {
          anchors.centerIn: parent
          iconSize: Style.space(11)
          color: root.barIconColor
          badgeColor: root.urgent
          crossed: Model.iconCrossed(root.view.state)
          warning: Model.iconWarning(root.view.state)
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
              meta: Model.heroMeta(root.view)
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
                  warning: Model.iconWarning(root.view.state)
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

          Column {
            visible: root.degraded
            width: parent.width
            spacing: Style.spacing.xl

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: Model.degradedExplanation(root.view.state)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: Model.degradedRemediation(root.view)
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
            id: copyRow
            visible: root.copyCommand !== ""
            width: parent.width
            title: "Copy command"
            subtitle: root.copyCommand
            sectionName: "copy"
            onActivated: vpn.copyText(root.copyCommand)
          }

          ActionRow {
            id: terminalRow
            visible: root.view.state === Model.STATES.signedOut
            width: parent.width
            title: "Open terminal"
            subtitle: "Sign in there; this plugin never collects a password."
            sectionName: "terminal"
            onActivated: vpn.openTerminal()
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
              text: vpn.refreshing ? "Refreshing…" : "Refresh"
              tooltipText: vpn.refreshing ? "Checking Proton VPN…" : "Update status, locations, and settings"
              hasCursor: root.cursorActive && root.focusSection === "refresh"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.refreshAll()
              onHovered: function(on) { if (on) root.setFocusSection("refresh") }
            }
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
            title: "Retry locations"
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
              text: "CONNECT"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            RowLayout {
              id: connectRow
              width: parent.width
              spacing: Style.spacing.rowGap

              FieldColumn {
                FieldLabel { text: "Mode" }
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
                  placeholderText: "Search modes"
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
                    text: Model.modeTooltip(root.selectedMode)
                    tipCursor: root.keyboardNavigation && modeDropdown.hasCursor
                    tipPopupOpen: modeDropdown.popupOpen
                  }
                }
              }

              FieldColumn {
                fieldVisible: root.needsCountry
                FieldLabel { text: "Country" }
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
                  placeholderText: "Search countries"
                  triggerLabel: Model.connectFieldTriggerLabel("country", { mode: root.selectedMode, country: root.selectedCountry })
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
                    text: Model.connectFieldTooltip("country")
                    tipCursor: root.keyboardNavigation && countryDropdown.hasCursor
                    tipPopupOpen: countryDropdown.popupOpen
                  }
                }
              }

              FieldColumn {
                fieldVisible: root.needsCity
                FieldLabel { text: "City" }
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
                  placeholderText: "Search cities"
                  triggerLabel: Model.connectFieldTriggerLabel("city", {
                    mode: root.selectedMode,
                    country: root.selectedCountry,
                    loading: vpn.citiesLoading && vpn.citiesCountry === root.selectedCountry
                  })
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
                    text: Model.connectFieldTooltip("city")
                    tipCursor: root.keyboardNavigation && cityDropdown.hasCursor
                    tipPopupOpen: cityDropdown.popupOpen
                  }
                }
              }

              FieldColumn {
                fieldVisible: root.needsServer
                FieldLabel { text: "Server ID" }
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
                    text: Model.connectFieldTooltip("server")
                    tipHovered: serverField.hovered
                    tipCursor: root.keyboardNavigation && root.cursorActive && root.focusSection === "server"
                  }
                }
              }
            }


            Button {
              id: switchButton
              visible: root.offerSwitch
              width: parent.width
              bordered: true
              text: Model.switchLabel(root.connectOptions())
              tooltipText: "Reconnect with these choices. Proton replaces the current connection."
              hasCursor: root.cursorActive && root.focusSection === "switch"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.switchNow()
              onHovered: function(on) { if (on) root.setFocusSection("switch") }
            }

            PanelSectionHeader {
              visible: root.recentChoices.length > 0
              text: "RECENT"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            GridLayout {
              id: recentGrid
              visible: root.recentChoices.length > 0
              width: parent.width
              columns: Math.max(1, Math.min(3, root.recentChoices.length))
              columnSpacing: Style.spacing.rowGap
              rowSpacing: Style.spacing.labelGap

              Repeater {
                model: root.recentChoices

                Button {
                  required property var modelData
                  required property int index
                  Layout.fillWidth: true
                  Layout.preferredWidth: 1
                  text: modelData.label
                  tooltipText: "Reconnect using " + modelData.label + (modelData.detail ? " · last used " + modelData.detail : "")
                  hasCursor: root.cursorActive && root.focusSection === "recent:" + index
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.connectRecent(index)
                  onHovered: function(on) { if (on) root.setFocusSection("recent:" + index) }
                }
              }
            }
          }

          Column {
            visible: root.showWrites && vpn.installed
            width: parent.width
            spacing: Style.spacing.rowGap

            PanelSeparator { foreground: root.foreground }

            Column {
              width: parent.width
              spacing: Style.spacing.labelGap

              PanelSectionHeader {
                text: "SETTINGS"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              SettingHelp {
                width: parent.width
                text: Model.SETTINGS_SECTION_HELP
              }
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
                FieldLabel { text: "NetShield" }
                SearchableDropdown {
                  id: netshieldDropdown
                  Layout.fillWidth: true
                  Layout.preferredWidth: 0
                  showLabel: false
                  value: vpn.configDisplayValue("netshield")
                  options: root.choiceOptions(root.netshieldSetting)
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  hasCursor: root.cursorActive && root.focusSection === "config:netshield"
                  placeholderText: "NetShield"
                  emptyText: vpn.configUpgrade.netshield ? "Upgrade to enable" : "No values"
                  onHovered: function(on) {
                    netshieldTip.tipHovered = on
                    if (on) root.setFocusSection("config:netshield")
                  }
                  onChanged: function(value) { if (value !== vpn.configDisplayValue("netshield")) vpn.setConfig("netshield", value) }

                  SettingTip {
                    id: netshieldTip
                    text: Model.settingTooltip("netshield")
                    tipCursor: root.keyboardNavigation && netshieldDropdown.hasCursor
                    tipPopupOpen: netshieldDropdown.popupOpen
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  visible: vpn.configUpgrade.netshield === true
                  Layout.fillWidth: true
                  text: "Upgrade to enable. Changing it still sends the CLI command so Proton can report the restriction."
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }

              FieldColumn {
                FieldLabel { text: "Kill Switch" }
                SearchableDropdown {
                  id: killSwitchDropdown
                  Layout.fillWidth: true
                  Layout.preferredWidth: 0
                  showLabel: false
                  value: vpn.configDisplayValue("kill-switch")
                  options: root.choiceOptions(root.killSwitchSetting)
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  hasCursor: root.cursorActive && root.focusSection === "config:kill-switch"
                  placeholderText: "Kill Switch"
                  onHovered: function(on) {
                    killSwitchTip.tipHovered = on
                    if (on) root.setFocusSection("config:kill-switch")
                  }
                  onChanged: function(value) { root.chooseKillSwitch(value) }

                  SettingTip {
                    id: killSwitchTip
                    text: Model.settingTooltip("kill-switch")
                    tipCursor: root.keyboardNavigation && killSwitchDropdown.hasCursor
                    tipPopupOpen: killSwitchDropdown.popupOpen
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  visible: Model.isVpnActive(root.view) && root.ksConfirmValue === ""
                  Layout.fillWidth: true
                  text: vpn.ksStep !== "idle" ? "Changing: the VPN reconnects when done." : "Changing it briefly reconnects the VPN."
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
                text: Model.killSwitchConfirmText(root.ksConfirmValue, Model.killSwitchReturnTarget(vpn.activeTarget, root.view.status))
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Row {
                spacing: Style.spacing.rowGap

                Button {
                  text: "Cancel"
                  bordered: true
                  hasCursor: root.cursorActive && root.focusSection === "ks-cancel"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.cancelKillSwitch()
                  onHovered: function(on) { if (on) root.setFocusSection("ks-cancel") }
                }

                Button {
                  text: "Reconnect and change"
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
                  label: "Custom DNS"
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
                    text: Model.settingTooltip("custom-dns")
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

            Item {
              width: parent.width
              height: Style.space(6)
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
    label: setting.label || ""
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
      text: Model.settingTooltip(toggleSettingRow.key)
      tipHovered: toggleSettingRow.tipHovered
      tipCursor: root.keyboardNavigation && toggleSettingRow.hasCursor
    }
  }
}
