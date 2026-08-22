import QtQuick
import QtQuick.Shapes
import qs.Commons

// Monochrome Proton VPN mark from the official 36×36 SVG, fitted to the
// bar/panel slot. Theme color only — no Proton gradient — so it tracks
// Omarchy like Tailscale and Dropbox.
//
// The two brand paths are co-equal: `chevron` is the outer band and `facet`
// fills its notch. Drawing the chevron at reduced alpha and the facet at full
// strength reproduces the logo's light-inner-on-strong-outer depth without
// referencing the background, so it survives a translucent bar and any theme.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property color badgeColor: Color.urgent
  property bool crossed: false
  property bool warning: false

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  // The mark's own bounding box is 22 units wide inside the 36-unit viewBox
  // and is centred on it, so fitting 22 units to iconSize makes the painted
  // mark fill the slot the same way TailscaleIcon and DropboxIcon do.
  readonly property real markUnits: 22
  readonly property real unitPx: iconSize / markUnits
  readonly property real originUnits: 18 - markUnits / 2

  readonly property string chevronPath: "M15.8369 26.7462C16.673 28.2493 18.8202 28.3307 19.7694 26.8953L28.6208 13.511C29.5594 12.0916 28.6613 10.1886 26.9616 9.99524L9.56399 8.01572C7.70916 7.80467 6.3885 9.76048 7.29068 11.3824L7.36143 11.5089L15.1243 16.8282L15.03 25.2903L15.8369 26.7462Z"
  readonly property string facetPath: "M16.3354 25.3442L17.1209 24.1726L23.0878 15.1593C23.6095 14.3712 23.1116 13.3141 22.1677 13.2057L7.35938 11.5056L15.0305 25.2964C15.3105 25.79 16.0183 25.8171 16.3354 25.3442Z"

  readonly property real chevronAlpha: 0.62

  // Slash and badge sizing is clamped in device pixels so both still resolve
  // in an 11 px bar slot, then converted back to viewBox units.
  readonly property real slashHalfLen: 13
  readonly property real slashThick: Math.max(2.6, 1.75 / unitPx)
  readonly property real slashGap: Math.max(0.8, 0.8 / unitPx)

  readonly property real badgeSize: Math.max(4.5, iconSize * 0.36)
  readonly property real badgeRadius: (badgeSize / 2) / unitPx
  readonly property real badgeGap: Math.max(0.7, 0.9 / unitPx)
  readonly property real badgeCenter: 18 + markUnits / 2 - badgeRadius

  function slashQuad(halfLen, halfThick) {
    var a = -Math.PI / 4
    var ux = Math.cos(a)
    var uy = Math.sin(a)
    function corner(alongSign, acrossSign) {
      var x = 18 + ux * halfLen * alongSign - uy * halfThick * acrossSign
      var y = 18 + uy * halfLen * alongSign + ux * halfThick * acrossSign
      return x.toFixed(3) + " " + y.toFixed(3)
    }
    return "M" + corner(1, 1) + "L" + corner(1, -1) + "L" + corner(-1, -1) + "L" + corner(-1, 1) + "Z"
  }

  function badgeCircle(r) {
    var c = badgeCenter.toFixed(3)
    var left = (badgeCenter - r).toFixed(3)
    var right = (badgeCenter + r).toFixed(3)
    var rr = r.toFixed(3)
    return "M" + left + " " + c +
           "A" + rr + " " + rr + " 0 1 0 " + right + " " + c +
           "A" + rr + " " + rr + " 0 1 0 " + left + " " + c + "Z"
  }

  // Extra subpaths filled by the odd-even rule, which punches them straight
  // out of the mark. That keeps the slash and the badge separated from the
  // artwork on any background without painting a fake backdrop behind them.
  readonly property string knockouts: {
    var out = ""
    if (crossed) out += slashQuad(slashHalfLen + slashGap, slashThick / 2 + slashGap)
    if (warning) out += badgeCircle(badgeRadius + badgeGap)
    return out
  }

  Shape {
    width: 36
    height: 36
    anchors.centerIn: parent
    scale: root.unitPx
    antialiasing: true
    // No layer: an FBO would rasterise at 36 px and then scale, which visibly
    // softens the mark. CurveRenderer antialiases at the final resolution.
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: Qt.alpha(root.color, root.chevronAlpha)
      fillRule: ShapePath.OddEvenFill
      strokeWidth: 0
      PathSvg { path: root.chevronPath + root.knockouts }
    }

    ShapePath {
      fillColor: root.color
      fillRule: ShapePath.OddEvenFill
      strokeWidth: 0
      PathSvg { path: root.facetPath + root.knockouts }
    }
  }

  Rectangle {
    visible: root.crossed
    anchors.centerIn: parent
    width: root.slashHalfLen * 2 * root.unitPx
    height: root.slashThick * root.unitPx
    radius: height / 2
    color: root.color
    rotation: -45
    antialiasing: true
  }

  Rectangle {
    id: badge
    visible: root.warning
    width: root.badgeSize
    height: root.badgeSize
    radius: width / 2
    color: root.badgeColor
    antialiasing: true
    x: (root.badgeCenter - root.badgeRadius - root.originUnits) * root.unitPx
    y: (root.badgeCenter - root.badgeRadius - root.originUnits) * root.unitPx

    // Drawn rather than typeset: a text glyph this small renders as a smudge.
    // Below roughly 8 px the badge reads better as a plain urgent dot.
    readonly property bool showBang: width >= 7.5
    readonly property real strokeWidth: Math.max(1, width * 0.15)

    Rectangle {
      visible: badge.showBang
      width: badge.strokeWidth
      height: badge.height * 0.34
      radius: width / 2
      color: Color.background
      anchors.horizontalCenter: parent.horizontalCenter
      y: badge.height * 0.20
    }

    Rectangle {
      visible: badge.showBang
      width: badge.strokeWidth
      height: width
      radius: width / 2
      color: Color.background
      anchors.horizontalCenter: parent.horizontalCenter
      y: badge.height * 0.62
    }
  }
}
