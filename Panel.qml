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
  readonly property bool degraded: view.state === Model.STATES.cliMissing || view.state === Model.STATES.signedOut || view.state === Model.STATES.guiConflict || view.state === Model.STATES.error
  readonly property bool showHealthy: !degraded
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && vpn.installed && Model.canToggleConnection(view.state)
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
  readonly property string toggleHint: view.state === Model.STATES.connected || view.state === Model.STATES.disconnecting ? "Disconnect Proton VPN" : "Connect Proton VPN"
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
    if (vpn.installed && (Model.canToggleConnection(view.state) || view.state === Model.STATES.connecting || view.state === Model.STATES.disconnecting)) order.push("header")
    if (copyCommand !== "") order.push("copy")
    if (view.state === Model.STATES.signedOut) order.push("terminal")
    order.push("refresh")
    if (showHealthy && vpn.installed) {
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
    else if (key === "custom-dns") {
      var dns = Model.parseCustomDnsValue(vpn.configDisplayValue("custom-dns"))
      if (dns.enabled) vpn.setConfig("custom-dns", "off")
      else applyDns()
    }
  }

  function tryToggle() {
    if (!Model.canToggleConnection(view.state) || vpn.actionBusy) {
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

  function refreshAll() {
    vpn.refresh()
    if (vpn.installed && showHealthy) {
      vpn.refreshCountries(true)
      vpn.refreshConfig()
      if (needsCity && selectedCountry !== "") vpn.refreshCities(selectedCountry, true)
    }
  }

  function applyDns() {
    vpn.setConfig("custom-dns", "on", { dns: dnsText })
  }

  function setFocusSection(name) {
    cursorActive = true
    focusSection = name
    ensureCursor()
    scrollCursorIntoView()
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
    else if (focusSection === "copy") scrollItemIntoView(copyRow)
    else if (focusSection === "terminal") scrollItemIntoView(terminalRow)
    else if (focusSection === "mode") scrollItemIntoView(modeDropdown)
    else if (focusSection === "country") scrollItemIntoView(countryDropdown)
    else if (focusSection === "city") scrollItemIntoView(cityDropdown)
    else if (focusSection === "server") scrollItemIntoView(serverField)
    else if (focusSection === "dns") scrollItemIntoView(dnsField)
    else if (configColumn) scrollItemIntoView(configColumn)
  }

  function choiceOptions(def) {
    var options = []
    if (!def || !def.values) return options
    for (var i = 0; i < def.values.length; i++) {
      var value = def.values[i]
      options.push({ value: value, label: def.valueLabels && def.valueLabels[value] ? def.valueLabels[value] : value })
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
    function connectVpn(): string { root.tryToggle(); return "ok" }
    function disconnectVpn(): string { vpn.disconnect(); return "ok" }
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
                  visible: vpn.installed && (Model.canToggleConnection(root.view.state) || root.view.state === Model.STATES.connecting || root.view.state === Model.STATES.disconnecting)
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
              text: Model.degradedRemediation(root.view.state)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
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
            visible: root.showHealthy && vpn.installed
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

          Column {
            visible: root.showHealthy && vpn.installed
            width: parent.width
            spacing: Style.space(10)

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "CONNECT"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            SearchableDropdown {
              id: modeDropdown
              width: parent.width
              label: "Mode"
              value: root.selectedMode
              options: root.modeOptions
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusSection === "mode"
              placeholderText: "Search modes"
              onHovered: function(on) { if (on) root.setFocusSection("mode") }
              onChanged: function(value) { root.selectedMode = value }
            }

            SearchableDropdown {
              id: countryDropdown
              visible: root.needsCountry
              width: parent.width
              label: "Country"
              value: root.selectedCountry
              options: root.countryOptions
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusSection === "country"
              placeholderText: "Search countries"
              emptyText: vpn.countriesError !== "" ? vpn.countriesError : "No countries found"
              onHovered: function(on) { if (on) root.setFocusSection("country") }
              onChanged: function(value) { root.selectedCountry = value }
            }

            SearchableDropdown {
              id: cityDropdown
              visible: root.needsCity
              width: parent.width
              label: "City"
              value: root.selectedCity
              options: root.cityOptions
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.focusSection === "city"
              placeholderText: "Search cities"
              emptyText: vpn.citiesError !== "" ? vpn.citiesError : "No cities found"
              onHovered: function(on) { if (on) root.setFocusSection("city") }
              onChanged: function(value) { root.selectedCity = value }
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

              Text {
                width: parent.width
                text: "The CLI has no machine-readable server list. Proton publishes IDs at " + Model.SERVER_LIST_URL + "."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }

          Column {
            visible: root.showHealthy && vpn.installed
            width: parent.width
            spacing: Style.space(10)

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "SETTINGS"
              foreground: root.foreground
              fontFamily: root.fontFamily
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

              SearchableDropdown {
                id: netshieldDropdown
                width: parent.width
                label: "NetShield"
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

              SearchableDropdown {
                id: killSwitchDropdown
                width: parent.width
                label: "Kill switch"
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
                visible: root.view.state === Model.STATES.connected
                width: parent.width
                text: "Disconnect before changing Kill Switch."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
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
                  description: vpn.configUpgrade["custom-dns"] ? "Upgrade to enable." : "Passed as one --dns argument after local validation. Requires a new VPN connection."
                  checked: Model.parseCustomDnsValue(vpn.configDisplayValue("custom-dns")).enabled
                  hasCursor: root.cursorActive && root.focusSection === "config:custom-dns"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onHovered: function(on) { if (on) root.setFocusSection("config:custom-dns") }
                  onClicked: {
                    var enabled = Model.parseCustomDnsValue(vpn.configDisplayValue("custom-dns")).enabled
                    if (enabled) vpn.setConfig("custom-dns", "off")
                    else root.applyDns()
                  }
                }

                TextField {
                  id: dnsField
                  visible: Model.parseCustomDnsValue(vpn.configDisplayValue("custom-dns")).enabled || root.focusSection === "dns"
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

  component ToggleSettingRow: Toggle {
    property var setting: ({})
    readonly property string key: String(setting.key || "")
    readonly property string currentValue: vpn.configDisplayValue(key)
    readonly property bool upgrade: vpn.configUpgrade && vpn.configUpgrade[key] === true

    width: parent.width
    label: setting.label || ""
    description: upgrade ? "Upgrade to enable. The CLI will report the plan requirement if changed." : (setting.restart ? "Requires a new VPN connection to apply." : "")
    checked: String(currentValue) === "on"
    hasCursor: root.cursorActive && root.focusSection === "config:" + key
    foreground: root.foreground
    fontFamily: root.fontFamily
    onHovered: function(on) { if (on) root.setFocusSection("config:" + key) }
    onClicked: vpn.setConfig(key, checked ? "off" : "on")
  }
}
