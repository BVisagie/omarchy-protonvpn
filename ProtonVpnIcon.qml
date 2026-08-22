import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Ui

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

  Shape {
    id: shield
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4

    ShapePath {
      fillColor: root.color
      strokeWidth: 0
      startX: root.width * 0.50
      startY: root.height * 0.06
      PathLine { x: root.width * 0.86; y: root.height * 0.22 }
      PathLine { x: root.width * 0.86; y: root.height * 0.52 }
      PathQuad {
        x: root.width * 0.50
        y: root.height * 0.94
        controlX: root.width * 0.86
        controlY: root.height * 0.78
      }
      PathQuad {
        x: root.width * 0.14
        y: root.height * 0.52
        controlX: root.width * 0.14
        controlY: root.height * 0.78
      }
      PathLine { x: root.width * 0.14; y: root.height * 0.22 }
      PathLine { x: root.width * 0.50; y: root.height * 0.06 }
    }
  }

  Rectangle {
    visible: !root.crossed
    width: Math.max(3, root.width * 0.22)
    height: width
    radius: width / 2
    color: Color.background
    opacity: 0.92
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: -root.height * 0.04
  }

  Rectangle {
    visible: root.crossed
    anchors.centerIn: parent
    width: parent.width * 1.18
    height: Math.max(2, parent.height * 0.14)
    radius: height / 2
    color: root.color
    rotation: -45
  }

  BorderSurface {
    visible: root.warning
    width: Math.max(7, parent.width * 0.42)
    height: width
    radius: width / 2
    color: root.badgeColor
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    borderSpec: Border.flat(Color.popups.background, 1)

    Text {
      anchors.centerIn: parent
      text: "!"
      color: Color.background
      font.family: Style.font.family
      font.pixelSize: Math.max(6, parent.height * 0.72)
      font.bold: true
    }
  }
}
