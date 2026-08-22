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

  property string focusSection: "header"
  property bool cursorActive: false
  property string selectedMode: "fastest"
  property string selectedCountry: ""
  property string selectedCity: ""
  property string serverIdText: ""
  property string dnsText: ""
  property int nowTick: 0

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

  function visibleFocusOrder() {
    var order = []
    if (vpn.installed && (Model.canWrite(view.state) || view.state === Model.STATES.connecting || view.state === Model.STATES.disconnecting)) order.push("header")
    if (copyCommand !== "") order.push("copy")
    if (view.state === Model.STATES.signedOut) order.push("terminal")
    order.push("refresh")
    if (vpn.countriesError !== "" || vpn.citiesError !== "") order.push("retry-locations")
    if (showWrites && vpn.installed) {
      order.push("mode")
      if (needsCountry) order.push("country")
      if (needsCity) order.push("city")
      if (needsServer) order.push("server")
      if (vpn.configLoaded) {
        for (var i = 0; i < configSettings.length; i++) {
          order.push("config:" + configSettings[i].key)
          if (configSettings[i].key === "custom-dns" && dnsEnabled()) order.push("dns")
        }
      }
    }
    return order
  }

  function dnsEnabled() {
    var value = String(vpn.configDisplayValue("custom-dns") || "")
    return Model.parseCustomDnsValue(value).enabled === true || vpn.pendingSetting === "custom-dns" && vpn.pendingValue === "on"
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
    ensureCursor()
    if (dy === 0) return
    var order = focusOrder
    var index = order.indexOf(focusSection)
    if (index < 0) index = 0
    var next = Math.max(0, Math.min(order.length - 1, index + dy))
    focusSection = order[next]
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
    else if (focusSection === "city") cityDropdown.toggle()
    else if (focusSection === "server") Qt.callLater(function() { if (serverField) serverField.forceActiveFocus() })
    else if (focusSection === "dns") applyDns()
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
      vpn.setConfig("custom-dns", "off")
      return
    }
    var checked = Model.validateDnsList(dnsText)
    if (checked.ok) {
      applyDns()
      return
    }
    setFocusSection("dns")
    Qt.callLater(function() { if (dnsField) dnsField.forceActiveFocus() })
  }

  function setFocusSection(name) {
    cursorActive = true
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
    else if (focusSection === "dns") scrollItemIntoView(dnsField)
    else if (focusSection === "config:netshield") scrollItemIntoView(netshieldDropdown)
    else if (focusSection === "config:kill-switch") scrollItemIntoView(killSwitchDropdown)
    else if (focusSection === "config:custom-dns") scrollItemIntoView(dnsField.visible ? dnsField : configColumn)
    else if (configColumn) {
      for (var i = 0; i < configColumn.children.length; i++) {
        var child = configColumn.children[i]
        if (child && child.objectName === focusSection) {
          scrollItemIntoView(child)
          return
        }
      }
      scrollItemIntoView(configColumn)
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

  onOpenedChanged: if (opened) {
    cursorActive = false
    if (panelFlick) panelFlick.contentY = 0
    refreshAll()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onSelectedModeChanged: {
    if (needsCountry) vpn.refreshCountries()
    if (needsCity && selectedCountry !== "") vpn.refreshCities(selectedCountry)
    ensureCursor()
  }
  onSelectedCountryChanged: {
    selectedCity = ""
    if (needsCity && selectedCountry !== "") vpn.refreshCities(selectedCountry)
    ensureCursor()
  }

  Service {
    id: vpn
    settings: root.settings
  }

  Connections {
    target: vpn
    function onStateChanged() { root.ensureCursor() }
    function onConfigLoadedChanged() {
      if (vpn.configLoaded) {
        var dns = Model.parseCustomDnsValue(vpn.configDisplayValue("custom-dns"))
        if (dns.ips.length > 0) root.dnsText = dns.ips.join(", ")
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
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.pickerOpen || root.editorFocused
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
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
          spacing: Style.space(12)

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
              detail: Model.heroDetail(root.view)
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
                ToggleSwitch {
                  id: powerSwitch
                  visible: vpn.installed && (Model.canWrite(root.view.state) || root.view.state === Model.STATES.connecting || root.view.state === Model.STATES.disconnecting)
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

          Text {
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
            spacing: Style.space(10)

            Text {
              width: parent.width
              text: Model.degradedExplanation(root.view.state)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: Model.degradedRemediation(root.view)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Text {
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

          Column {
            visible: vpn.installed && (root.showHealthy || root.view.state === Model.STATES.stale)
            width: parent.width
            spacing: Style.spacing.labelGap

            InfoPair {
              visible: root.view.status && root.view.status.server !== ""
              label: "Server"
              value: root.view.status.server
            }
            InfoPair {
              visible: root.view.status && root.view.status.location !== ""
              label: "Location"
              value: root.view.status.location
            }
            InfoPair {
              visible: root.view.state === Model.STATES.connected || (root.view.stale && root.view.status && root.view.status.protocol !== "")
              label: "Load"
              value: Model.displayLoad(root.view.status.load)
            }
            InfoPair {
              visible: root.view.status && root.view.status.protocol !== ""
              label: "Protocol"
              value: root.view.status.protocol
            }
            InfoPair {
              visible: Model.lastUpdatedText(root.view, Date.now()) !== ""
              label: root.view.stale ? "Stale" : "Updated"
              value: Model.lastUpdatedText(root.view, Date.now() + root.nowTick)
            }
          }

          ActionRow {
            id: refreshRow
            width: parent.width
            title: "Refresh"
            subtitle: vpn.refreshing ? "Checking Proton VPN…" : "Update status, locations, and settings"
            sectionName: "refresh"
            onActivated: root.refreshAll()
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

          Column {
            visible: root.showWrites && vpn.installed
            width: parent.width
            spacing: Style.space(10)

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "CONNECT"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            SettingHelp {
              text: Model.CONNECT_SECTION_HELP
            }

            Column {
              width: parent.width
              spacing: Style.spacing.labelGap

              Text {
                text: "Mode"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              SettingHelp {
                text: Model.modeHelp(root.selectedMode)
              }

              SearchableDropdown {
                id: modeDropdown
                width: parent.width
                showLabel: false
                value: root.selectedMode
                options: root.modeOptions
                foreground: root.foreground
                fontFamily: root.fontFamily
                hasCursor: root.cursorActive && root.focusSection === "mode"
                placeholderText: "Search modes"
                onHovered: function(on) { if (on) root.setFocusSection("mode") }
                onChanged: function(value) { root.selectedMode = value }
              }
            }

            Column {
              visible: root.needsCountry
              width: parent.width
              spacing: Style.spacing.labelGap

              Text {
                text: "Country"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              SettingHelp {
                text: Model.connectFieldHelp("country")
              }

              SearchableDropdown {
                id: countryDropdown
                width: parent.width
                showLabel: false
                value: root.selectedCountry
                options: root.countryOptions
                foreground: root.foreground
                fontFamily: root.fontFamily
                hasCursor: root.cursorActive && root.focusSection === "country"
                placeholderText: "Search countries"
                emptyText: root.countryEmptyText()
                onHovered: function(on) { if (on) root.setFocusSection("country") }
                onChanged: function(value) { root.selectedCountry = value }
              }
            }

            Column {
              visible: root.needsCity
              width: parent.width
              spacing: Style.spacing.labelGap

              Text {
                text: "City"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              SettingHelp {
                text: Model.connectFieldHelp("city")
              }

              SearchableDropdown {
                id: cityDropdown
                width: parent.width
                showLabel: false
                value: root.selectedCity
                options: root.cityOptions
                foreground: root.foreground
                fontFamily: root.fontFamily
                hasCursor: root.cursorActive && root.focusSection === "city"
                placeholderText: "Search cities"
                emptyText: root.cityEmptyText()
                onHovered: function(on) { if (on) root.setFocusSection("city") }
                onChanged: function(value) { root.selectedCity = value }
              }
            }

            Column {
              visible: root.needsServer
              width: parent.width
              spacing: Style.spacing.labelGap

              Text {
                text: "Server ID"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              SettingHelp {
                text: Model.connectFieldHelp("server")
              }

              TextField {
                id: serverField
                width: parent.width
                foreground: root.foreground
                placeholderText: "IT#23"
                text: root.serverIdText
                hasCursor: root.cursorActive && root.focusSection === "server" && !activeFocus
                onHoveredChanged: if (hovered) root.setFocusSection("server")
                onTextChanged: root.serverIdText = text
                onAccepted: root.tryToggle()
              }
            }
          }

          Column {
            visible: root.showWrites && vpn.installed
            width: parent.width
            spacing: Style.space(10)

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "SETTINGS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            SettingHelp {
              text: Model.SETTINGS_SECTION_HELP
            }

            Text {
              visible: vpn.configError !== ""
              width: parent.width
              text: vpn.configError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Column {
              id: configColumn
              width: parent.width
              spacing: Style.space(10)

              Column {
                width: parent.width
                spacing: Style.spacing.labelGap

                Text {
                  text: "NetShield"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                SettingHelp {
                  text: Model.settingCaption("netshield")
                }

                SearchableDropdown {
                  id: netshieldDropdown
                  width: parent.width
                  showLabel: false
                  value: vpn.configDisplayValue("netshield")
                  options: root.choiceOptions(root.netshieldSetting)
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  hasCursor: root.cursorActive && root.focusSection === "config:netshield"
                  placeholderText: "NetShield"
                  emptyText: vpn.configUpgrade.netshield ? "Upgrade to enable" : "No values"
                  onHovered: function(on) { if (on) root.setFocusSection("config:netshield") }
                  onChanged: function(value) { if (value !== vpn.configDisplayValue("netshield")) vpn.setConfig("netshield", value) }
                }

                Text {
                  visible: vpn.configUpgrade.netshield === true
                  width: parent.width
                  text: "Upgrade to enable. Changing it still sends the CLI command so Proton can report the restriction."
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }

              Column {
                width: parent.width
                spacing: Style.spacing.labelGap

                Text {
                  text: "Kill switch"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                SettingHelp {
                  text: Model.settingCaption("kill-switch")
                }

                SearchableDropdown {
                  id: killSwitchDropdown
                  width: parent.width
                  showLabel: false
                  value: vpn.configDisplayValue("kill-switch")
                  options: root.choiceOptions(root.killSwitchSetting)
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  hasCursor: root.cursorActive && root.focusSection === "config:kill-switch"
                  placeholderText: "Kill switch"
                  onHovered: function(on) { if (on) root.setFocusSection("config:kill-switch") }
                  onChanged: function(value) { if (value !== vpn.configDisplayValue("kill-switch")) vpn.setConfig("kill-switch", value) }
                }

                Text {
                  visible: Model.isVpnActive(root.view)
                  width: parent.width
                  text: "Disconnect before changing Kill Switch."
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }

              Repeater {
                model: root.toggleSettings
                ToggleSettingRow {
                  required property var modelData
                  width: configColumn.width
                  setting: modelData
                }
              }

              Column {
                width: parent.width
                spacing: Style.space(6)

                Toggle {
                  width: parent.width
                  label: "Custom DNS"
                  description: Model.settingDescription("custom-dns", { upgrade: vpn.configUpgrade["custom-dns"] === true })
                  checked: Model.parseCustomDnsValue(vpn.configDisplayValue("custom-dns")).enabled
                  hasCursor: root.cursorActive && root.focusSection === "config:custom-dns"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onHovered: function(on) { if (on) root.setFocusSection("config:custom-dns") }
                  onClicked: root.toggleCustomDns()
                }

                TextField {
                  id: dnsField
                  visible: root.dnsEnabled() || root.focusSection === "dns" || root.focusSection === "config:custom-dns"
                  width: parent.width
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

  component ActionRow: CursorSurface {
    id: actionRow
    property string title: ""
    property string subtitle: ""
    property string sectionName: ""
    signal activated()

    hasCursor: root.cursorActive && root.focusSection === sectionName
    foreground: root.foreground
    fill: root.hoverFill
    implicitHeight: actionInner.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setFocusSection(actionRow.sectionName)
      onClicked: actionRow.activated()
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
        width: parent.width
        text: actionRow.title
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
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
    width: parent.width
    spacing: Style.space(8)

    Text {
      text: label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      width: Style.space(90)
    }
    Text {
      text: value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      width: Math.max(0, parent.width - Style.space(90) - parent.spacing)
    }
  }

  component SettingHelp: Text {
    width: parent.width
    visible: text !== ""
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  component ToggleSettingRow: Toggle {
    property var setting: ({})
    readonly property string key: String(setting.key || "")
    readonly property string currentValue: vpn.configDisplayValue(key)
    readonly property bool upgrade: vpn.configUpgrade && vpn.configUpgrade[key] === true
    objectName: "config:" + key

    width: parent.width
    label: setting.label || ""
    description: Model.settingDescription(key, { upgrade: upgrade })
    checked: String(currentValue) === "on"
    hasCursor: root.cursorActive && root.focusSection === "config:" + key
    foreground: root.foreground
    fontFamily: root.fontFamily
    onHovered: function(on) { if (on) root.setFocusSection("config:" + key) }
    onClicked: vpn.setConfig(key, checked ? "off" : "on")
  }
}
