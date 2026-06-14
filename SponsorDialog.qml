import QtQuick 2.15

Rectangle {
    id: sponsorRoot
    anchors.fill: parent
    color: "#80000000"
    visible: false

    property int sponsorQrIndex: 0

    signal closeClicked
    signal qrClicked

    MouseArea {
        anchors.fill: parent
        onClicked: sponsorRoot.closeClicked()
    }

    Rectangle {
        anchors.centerIn: parent
        width: 280
        height: 150
        radius: 10
        color: "#FFFFFF"
        border.color: "#EEEEEE"

        MouseArea {
            anchors.fill: parent
        }

        Row {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            Column {
                width: parent.width - 100 - 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Text {
                    width: parent.width
                    text: "❤ 支持一下作者"
                    font.pixelSize: 13
                    font.bold: true
                    color: "#E65100"
                }

                Text {
                    width: parent.width
                    text: "这款阅读器花了很长时间\n开发和打磨，如果觉得好用\n希望能请作者喝杯奶茶 ☕\n你的支持是我的动力 ❤"
                    font.pixelSize: 9
                    color: "#666666"
                    wrapMode: Text.WordWrap
                    lineHeight: 1.4
                }

                Rectangle {
                    width: 52
                    height: 20
                    radius: 3
                    color: "#F5F5F5"
                    border.color: "#E0E0E0"
                    Text {
                        anchors.centerIn: parent
                        text: "关闭"
                        font.pixelSize: 10
                        color: "#999999"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: sponsorRoot.closeClicked()
                    }
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Image {
                    width: 100
                    height: 100
                    anchors.horizontalCenter: parent.horizontalCenter
                    source: sponsorQrIndex === 0 ? Qt.resolvedUrl("Thanks.PNG") : Qt.resolvedUrl("weixin.png")
                    fillMode: Image.PreserveAspectFit
                    cache: false

                    MouseArea {
                        anchors.fill: parent
                        onClicked: sponsorRoot.qrClicked()
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: sponsorQrIndex === 0 ? "爱发电 · 点击切换微信" : "微信 · 点击切换爱发电"
                    font.pixelSize: 8
                    color: "#AAAAAA"
                }
            }
        }
    }
}
