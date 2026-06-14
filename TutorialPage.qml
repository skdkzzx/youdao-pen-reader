import QtQuick 2.15

Rectangle {
    id: tutorialRoot
    anchors.fill: parent
    color: "#FFFBF0"
    visible: false

    property var pageLines: []
    property int pageLine: 0

    signal closeClicked

    Column {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 4

        Row {
            width: parent.width
            height: 24
            spacing: 6

            Rectangle {
                width: 58
                height: 24
                radius: 4
                color: "#DDDDDD"
                Text {
                    anchors.centerIn: parent
                    text: "返回"
                    font.pixelSize: 11
                    color: "#333333"
                    font.family: "Microsoft YaHei"
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: tutorialRoot.closeClicked()
                }
            }

            Text {
                width: parent.width - 58 - 6
                height: 24
                text: "使用教程（请上下滑动阅读）"
                font.pixelSize: 12
                font.bold: true
                color: "#333333"
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                font.family: "Microsoft YaHei"
            }
        }

        // 可滚动内容区域，替代硬编码分页
        Flickable {
            width: parent.width
            height: parent.height - 28
            contentWidth: width
            contentHeight: contentText.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            Text {
                id: contentText
                width: parent.width
                text: pageLines.join("\n")
                font.pixelSize: 12
                color: "#333333"
                lineHeight: 1.5
                wrapMode: Text.WordWrap
                font.family: "Microsoft YaHei"
            }
        }
    }
}
