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
                text: "使用教程 (" + (pageLines.length > 0 ? Math.floor(pageLine / 8) + 1 + "/" + Math.ceil(pageLines.length / 8) : "1/1") + ")"
                font.pixelSize: 12
                font.bold: true
                color: "#333333"
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                font.family: "Microsoft YaHei"
            }
        }

        Text {
            width: parent.width
            height: parent.height - 28
            text: {
                var start = pageLine;
                var end = Math.min(start + 8, pageLines.length);
                var page = [];
                for (var i = start; i < end; i++)
                    page.push(pageLines[i]);
                return page.join("\n");
            }
            font.pixelSize: 12
            color: "#333333"
            lineHeight: 1.5
            wrapMode: Text.WordWrap
            clip: true
            font.family: "Microsoft YaHei"
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.topMargin: 28
        property real startX: 0
        property real startY: 0
        property bool moved: false

        onPressed: {
            startX = mouseX;
            startY = mouseY;
            moved = false;
        }
        onPositionChanged: {
            if (Math.abs(mouseX - startX) > 10 || Math.abs(mouseY - startY) > 10)
                moved = true;
        }
        onReleased: {
            if (moved) {
                var dy = mouseY - startY;
                if (dy < -10 && pageLine + 8 < pageLines.length)
                    pageLine += 8;
                else if (dy > 10 && pageLine >= 8)
                    pageLine -= 8;
            } else {
                if (mouseX > width / 2 && pageLine + 8 < pageLines.length)
                    pageLine += 8;
                else if (mouseX <= width / 2 && pageLine >= 8)
                    pageLine -= 8;
            }
        }
    }
}
