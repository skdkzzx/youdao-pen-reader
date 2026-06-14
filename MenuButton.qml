import QtQuick 2.15

Rectangle {
    id: btn

    property alias label: labelText.text
    property int w: 60
    property int h: 24
    property color bg: "#DDDDDD"
    property color fg: "#333333"

    signal clicked

    width: w
    height: h
    radius: 4
    color: mouse.pressed ? "#C8C8C8" : bg

    Text {
        id: labelText
        anchors.centerIn: parent
        width: parent.width - 4
        font.pixelSize: 10
        color: fg
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        preventStealing: true
        onClicked: btn.clicked()
    }
}
