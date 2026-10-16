// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Controls.ItemDelegate {
    id: row
    objectName: "spotlightResult"
    readonly property string debugTitle: model.display || ""
    required property int index
    required property var model
    required property var actions
    // Milou can retain a removed delegate while replacing/reordering a batch.
    // Its index becomes -1; never paint or interact with that stale result.
    visible: index >= 0
    enabled: index >= 0
    readonly property bool applicationResult: model.category === "Applications" || model.category === "Application"
    readonly property bool hasPrimaryAction: actions && actions.length > 0
    readonly property string detailText: selectionShown && hasPrimaryAction
        ? (actions[0].text || "Action") : activeAction >= 0
        ? (actions[activeAction].text || "Action") : (model.subtext || "")
    property bool highlightEnabled: true
    readonly property bool selectionShown: isCurrent && highlightEnabled
    signal navigationRequested()
    signal hoverNavigationRequested()
    property int activeAction: -1
    readonly property bool isCurrent: ListView.isCurrentItem
    // The Mac reference uses a 56-point highlight and a 2-point gap after
    // the first result. Row geometry stays fixed as text changes.
    implicitHeight: index === 0 ? 58 : 56
    topPadding: 0; bottomPadding: index === 0 ? 2 : 0
    leftPadding: 11; rightPadding: 10
    leftInset: 0; rightInset: 0; topInset: 0; bottomInset: 0
    hoverEnabled: true
    Accessible.name: model.display || ""
    Accessible.description: model.subtext || ""
    onHoveredChanged: if (hovered && index >= 0) { hoverNavigationRequested(); ListView.view.currentIndex = index }
    onIsCurrentChanged: if (!isCurrent) activeAction = -1
    onClicked: {
        if (index < 0) return
        ListView.view.currentIndex = index
        ListView.view.runCurrentIndex()
    }
    function activateNextAction() {
        if (activeAction >= actions.length - 1) return false
        activeAction++
        return true
    }
    function activatePreviousAction() {
        if (activeAction < 0) return false
        activeAction--
        return true
    }
    function activateLastAction() { activeAction = actions.length - 1 }
    background: Item {
        GlassPanel {
            width: parent.width
            height: 56
            radius: 21.375
            cornerFactor: 0.665
            outlineWidth: 0
            outlineColor: "transparent"
            pathInset: 0
            surfaceColor: row.selectionShown ? "#4e7bdf" : row.hovered ? "#575962" : "transparent"
        }
    }
    contentItem: RowLayout {
        spacing: 20
        Kirigami.Icon {
            source: row.model.decoration
            Layout.preferredWidth: 29
            Layout.preferredHeight: 29
            selected: row.isCurrent
        }
        ColumnLayout {
            id: resultText
            Layout.fillWidth: true
            spacing: 2
            Controls.Label {
                id: titleLabel
                text: row.model.display || ""
                Layout.fillWidth: true
                font.pixelSize: 17
                font.family: "Noto Sans" // match the search field across KDE font themes
                font.weight: Font.Normal
                color: row.selectionShown ? "white" : "#eceef5"
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
            Controls.Label {
                id: subtitleLabel
                text: row.model.subtext || ""
                Layout.fillWidth: true
                visible: text.length > 0 && !row.applicationResult
                font.pixelSize: 14
                font.family: "Noto Sans"
                color: row.selectionShown ? "#d8e8ff" : "#777777"
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
        }
        Item {
            id: detailArea
            readonly property bool showDetail: row.detailText.length > 0 && (row.applicationResult || row.activeAction >= 0)
            readonly property bool showBadge: row.selectionShown && row.hasPrimaryAction
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            Layout.preferredWidth: implicitWidth
            implicitWidth: Math.min(row.availableWidth * 0.43,
                (detailArea.showDetail ? detailLabel.implicitWidth : 0)
                + (detailArea.showBadge ? tabBadge.implicitWidth : 0)
                + (detailArea.showDetail && detailArea.showBadge ? 8 : 0))
            implicitHeight: Math.max(detailArea.showDetail ? detailLabel.implicitHeight : 0,
                detailArea.showBadge ? tabBadge.implicitHeight : 0)
            visible: detailArea.showDetail || detailArea.showBadge
            Controls.Label {
                id: detailLabel
                anchors.left: parent.left
                anchors.right: detailArea.showBadge ? tabBadge.left : parent.right
                anchors.rightMargin: detailArea.showBadge ? 8 : 0
                anchors.verticalCenter: parent.verticalCenter
                text: row.detailText
                visible: detailArea.showDetail
                font.pixelSize: 11
                font.family: "Noto Sans"
                color: row.selectionShown ? "#a8c9ff" : "#92949e"
                elide: Text.ElideRight
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignRight
            }
            Controls.Label {
                id: tabBadge
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "tab"
                visible: detailArea.showBadge
                font.pixelSize: 12
                font.family: "Noto Sans"
                color: "white"
                leftPadding: 6; rightPadding: 6
                topPadding: 2; bottomPadding: 2
                background: Rectangle {
                    radius: 5
                    color: row.selectionShown ? "#609cff" : "#555555"
                }
            }
        }
    }
}
