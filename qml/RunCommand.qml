/*
    SPDX-FileCopyrightText: 2014 Marco Martin <mart@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Effects

import org.kde.config // KAuthorized
import org.kde.kcmutils // KCMLauncher
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.milou as Milou
import org.kde.krunner.private.view
import org.kde.kirigami as Kirigami

Item {
    id: root

    required property RunnerWindow runnerWindow
    property string query
    property string singleRunner
    property bool highlightSelection: false
    property bool showHistory: false
    property string priorSearch: ""
    property alias runnerManager: results.runnerManager
    readonly property int resultCount: results.count
    // The header's small contextual icon is the currently highlighted native
    // application match; no separate provider query or synthetic action.
    readonly property var currentApplicationItem: results.currentItem
        && results.currentItem.index >= 0
        && results.currentItem.applicationResult ? results.currentItem : null
    readonly property bool showApplicationContext: root.searching
        && root.currentApplicationItem !== null && root.capsuleWidth >= 520

    LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    function activatePrimaryResultAction() {
        const item = results.currentItem
        if (!item || item.index < 0 || !item.actions || item.actions.length === 0) return
        root.highlightSelection = true
        results.runAction(0)
    }

    function isKeyUp(event) {
        return event.key === Qt.Key_Up || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_K)
    }
    function isKeyDown(event) {
        return event.key === Qt.Key_Down || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_J)
    }

    readonly property bool searching: query.length > 0 || showHistory
    property bool railActive: false
    property real revealTime: 0.7
    // Full 640-unit surface on normal displays; don't paint outside narrow windows.
    readonly property real availablePanelWidth: Math.min(640, Math.max(0, width - 40))
    property real capsuleWidth: searching ? availablePanelWidth
        : railActive && availablePanelWidth >= 640 ? 384 : availablePanelWidth
    Behavior on capsuleWidth { NumberAnimation { duration: root.railActive ? 440 : 380; easing.type: Easing.OutCubic } }
    onCapsuleWidthChanged: if (runnerWindow) runnerWindow.refreshGlassRegion()
    onRevealTimeChanged: if (runnerWindow) runnerWindow.refreshGlassRegion()
    onWidthChanged: if (runnerWindow) runnerWindow.refreshGlassRegion()
    onRailActiveChanged: {
        if (railActive) { revealTime = 0; revealClock.restart() }
        else { revealClock.stop(); revealTime = 0.7 }
    }
    NumberAnimation { id: revealClock; target: root; property: "revealTime"; from: 0; to: 0.7; duration: 700 }
    Timer { id: hideRail; interval: 900; onTriggered: if (!searchHover.hovered) root.railActive = false }
    function progress(index, extra) {
        if (!railActive || searching) return 0
        const p = Math.max(0, Math.min(1, (revealTime - 0.12 - index * 0.055 - extra) / (extra ? 0.16 : 0.28)))
        return p * p * (3 - 2 * p)
    }
    implicitWidth: 680
    property real requestedPanelHeight: 56
    property real reservedWindowHeight: 136
    implicitHeight: reservedWindowHeight
    onSearchingChanged: {
        if (searching) {
            releaseWindowSpace.stop()
            reservedWindowHeight = 533
            settleResults.restart()
        } else {
            settleResults.stop()
            requestedPanelHeight = 56
            releaseWindowSpace.restart()
        }
    }
    Timer {
        id: settleResults
        interval: 90
        onTriggered: {
            if (root.searching) {
                // Keep the panel stable while providers replace/reorder batches.
                root.requestedPanelHeight = Math.max(root.requestedPanelHeight, content.implicitHeight)
            }
        }
    }
    Timer {
        id: releaseWindowSpace
        interval: 360
        onTriggered: {
            if (root.searching) return
            if (sizeMorph.running) restart()
            else root.reservedWindowHeight = 136
        }
    }
    Connections {
        target: results
        function onContentHeightChanged() { if (root.searching) settleResults.restart() }
        function onCountChanged() { if (root.searching) settleResults.restart() }
    }
    Connections {
        target: listView
        function onContentHeightChanged() { if (root.searching) settleResults.restart() }
    }
    Kirigami.Theme.inherit: false
    Kirigami.Theme.textColor: "#eef0f6"
    Kirigami.Theme.backgroundColor: "#292b33"
    Kirigami.Theme.highlightColor: "#2878ed"
    Kirigami.Theme.highlightedTextColor: "#ffffff"

    Connections {
        target: root.runnerWindow
        function onHistoryBehaviorChanged() {
            root.runnerManager.historyEnabled = root.runnerWindow.historyBehavior !== RunnerWindow.Disabled
        }
        function onActivityChanged(activity) {
            if (activity) {
                root.runnerManager.setHistoryEnvironmentIdentifier(activity)
            }
        }
    }
    Component.onCompleted: {
        console.info("KRunner Spotlight custom interface loaded");
        runnerManager.historyEnabled = runnerWindow.historyBehavior !== RunnerWindow.Disabled
    }

    onQueryChanged: {
        highlightSelection = false
        if (query.length > 0) settleResults.restart()
        queryField.text = query;
    }

    Connections {
        target: root.runnerWindow
        function onVisibleChanged() {
            if (root.runnerWindow.visible) {
                root.railActive = false
                queryField.forceActiveFocus();
                listView.currentIndex = -1
                if (root.runnerWindow.retainPriorSearch) {
                    // If we manually specified a query(D-Bus invocation) we don't want to retain the prior search
                    if (!root.query) {
                        queryField.text = root.priorSearch
                        queryField.select(root.query.length, 0)
                        fadedTextCompletion.text = ""
                    }
                }
            } else {
                if (root.runnerWindow.retainPriorSearch) {
                    root.priorSearch = root.query
                }
                root.singleRunner = ""
                root.query = ""
                fadedTextCompletion.text = "";
                root.showHistory = false
            }
        }
    }

    Connections {
        target: root
        function onShowHistoryChanged() {
            if (root.showHistory) {
                // we store 50 entries in the history but only show 20 in the UI so it doesn't get too huge
                listView.model = root.runnerManager.history.slice(0, 20)
            } else {
                listView.model = []
            }
        }
    }

    GlassPanel {
        id: resultCard
        objectName: "spotlightGlass"
        x: 20; y: 36
        width: root.capsuleWidth
        height: root.requestedPanelHeight
        radius: root.searching ? 30.75 : 28
        cornerFactor: root.searching ? 0.64 : 0.55228475
        surfaceColor: "#60363742"
        rimLight: true
        Behavior on height {
            NumberAnimation {
                id: sizeMorph
                duration: 320
                easing.type: Easing.OutCubic
            }
        }
        Behavior on radius { NumberAnimation { duration: 320; easing.type: Easing.InOutCubic } }
        Behavior on cornerFactor { NumberAnimation { duration: 320; easing.type: Easing.InOutCubic } }
        onHeightChanged: if (root.runnerWindow) root.runnerWindow.refreshGlassRegion()
    }
    Item {
        id: contentViewport
        x: 20; y: 36
        width: root.width - 40
        height: resultCard.height
        clip: true
    ColumnLayout {
        id: content
        width: parent.width
        height: implicitHeight
        spacing: 0
    Item {
        id: searchBar
        Layout.fillWidth: true
        Layout.preferredHeight: 56
        HoverHandler {
            id: searchHover
            onHoveredChanged: {
                if (hovered && !root.searching) { hideRail.stop(); root.railActive = true }
                else hideRail.restart()
            }
        }
        Canvas {
            id: bridge
            x: 372; y: 17; width: 238; height: 58
            visible: !root.searching && root.railActive && root.revealTime < 0.42
            opacity: {
                const t = root.revealTime
                if (!root.railActive) return 0
                if (t < 0.06) return t / 0.06 * 0.46
                if (t < 0.18) return 0.46
                return Math.max(0, 0.46 * (1 - (t - 0.18) / 0.24))
            }
            onPaint: {
                const c = getContext("2d")
                c.clearRect(0,0,width,height)
                c.fillStyle = "#45515c"
                c.beginPath(); c.moveTo(18,29)
                c.bezierCurveTo(20,20,34,9,55,8)
                c.bezierCurveTo(72,0,91,7,104,13)
                c.bezierCurveTo(118,21,137,3,153,11)
                c.bezierCurveTo(184,19,214,15,220,29)
                c.bezierCurveTo(214,43,184,39,153,47)
                c.bezierCurveTo(137,55,118,37,104,45)
                c.bezierCurveTo(91,51,72,58,55,50)
                c.bezierCurveTo(34,49,20,38,18,29)
                c.closePath(); c.fill()
            }
        }
        QQC2.TextField {
            id: queryField
            objectName: "spotlightQuery"
            property bool allowCompletion: false

            x: 0; y: 0
            z: 2
            width: root.capsuleWidth
            height: 56
            font.pixelSize: 26
            font.family: "Noto Sans"
            color: "#f0f1f6"
            placeholderTextColor: "#aeb0ba"
            selectionColor: "#2275e6"
            selectedTextColor: "white"
            leftPadding: 61
            rightPadding: root.showApplicationContext ? 64 : 40
            font.weight: Font.Normal
            topPadding: 14
            bottomPadding: 14

            activeFocusOnPress: true
            placeholderText: results.singleRunner ? i18nc("Textfield placeholder text, query specific KRunner plugin",
                                                    "Search '%1'…", results.singleRunnerMetaData.name)
                                                : i18nc("Textfield placeholder text", "Spotlight Search")
            background: Item { z: -2 }
            // An optical action cue similar to the Mac's inline Open pill.
            // It is intentionally passive: Enter still runs the normal native
            // result, while Tab continues to invoke the provider's first action.
            TextMetrics {
                id: typedQueryMetrics
                font: queryField.font
                text: queryField.text
            }
            QQC2.Label {
                id: openHint
                x: queryField.leftPadding + typedQueryMetrics.advanceWidth + 10
                anchors.verticalCenter: parent.verticalCenter
                text: "↵ Open"
                font.family: queryField.font.family
                font.pixelSize: 11
                color: "#c7c9d2"
                leftPadding: 8; rightPadding: 8
                topPadding: 3; bottomPadding: 3
                opacity: 0.78
                visible: root.showApplicationContext && queryField.text.length > 0
                    && queryField.cursorPosition === queryField.text.length
                    && queryField.selectedText.length === 0 && !queryField.inputMethodComposing
                    && (fadedTextCompletion.text.length === 0 || !fadedTextCompletion.visible)
                    && x + implicitWidth + 14 < queryField.width - queryField.rightPadding
                z: 1
                background: Rectangle {
                    radius: height / 2
                    color: "#327d818c"
                    border.color: "#26ffffff"
                    border.width: 0.65
                }
                Accessible.ignored: true
            }
            // The header icon follows the selected app, never a fixed logo.
            // Mac images show this on typed application results; other provider
            // categories remain unadorned instead of displaying a wrong icon.
            Kirigami.Icon {
                id: contextAppIcon
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: 26; height: 26
                source: root.currentApplicationItem
                    ? root.currentApplicationItem.model.decoration : ""
                visible: root.showApplicationContext
                z: 1
                Accessible.ignored: true
            }
            Kirigami.Icon {
                anchors.left: parent.left
                anchors.leftMargin: 21
                anchors.verticalCenter: parent.verticalCenter
                width: 23; height: 23
                source: "search"
                color: "#bdc0cb"
            }

            QQC2.Label {
                id: fadedTextCompletion
                leftPadding: parent.leftPadding
                topPadding: parent.topPadding
                rightPadding: parent.rightPadding
                bottomPadding: parent.bottomPadding
                width: parent.width
                height: parent.height
                elide: Text.ElideRight
                visible: text !== queryField.text
                    && queryField.implicitWidth < (queryField.width
                                                - queryField.leftPadding
                                                - queryField.rightPadding)
                opacity: 0.5
                text: ""
                textFormat: Text.PlainText
                renderType: parent.renderType
                color: parent.color
                focus: false
                z: -1
            }

            function focusCurrentListView() {
                if (listView.count > 0) {
                    listView.forceActiveFocus();
                } else if (results.count > 0) {
                    results.forceActiveFocus();
                }
            }

            onTextChanged: {
                root.query = queryField.text
                if (!allowCompletion || !root.query ) { // Clear suggestion in case it was disabled or the query is cleared
                    fadedTextCompletion.text = ""
                } else if (root.runnerWindow.historyBehavior === RunnerWindow.CompletionSuggestion) {
                    // Match the user's exact typed characters to account for case insensitive matches
                    fadedTextCompletion.text = text + root.runnerManager.getHistorySuggestion(text).substring(text.length)
                } else if (length > 0 && root.runnerWindow.historyBehavior === RunnerWindow.ImmediateCompletion) {
                    var oldText = text
                    var suggestedText = root.runnerManager.getHistorySuggestion(text);
                    if (suggestedText.length > 0) {
                        text = text + suggestedText.substr(oldText.length)
                        select(text.length, oldText.length)
                    }
                }
            }
            Keys.onPressed: event => {
                if (root.isKeyUp(event) || root.isKeyDown(event)) root.highlightSelection = true
                allowCompletion = (event.key !== Qt.Key_Backspace && event.key !== Qt.Key_Delete)
                // We only need to handle the Key_End case, the first item is focused by default
                if (event.key === Qt.Key_End && results.count > 0 && cursorPosition === text.length) {
                    results.currentIndex = results.count - 1
                    event.accepted = true;
                    focusCurrentListView()
                }
                if (root.runnerWindow.historyBehavior === RunnerWindow.CompletionSuggestion
                    && fadedTextCompletion.text.length > 0
                    && cursorPosition === text.length
                    && event.key === Qt.Key_Right
                ) {
                    queryField.text = fadedTextCompletion.text
                    fadedTextCompletion.text = ""
                    event.accepted = true
                }
                if (queryField.text.length === 0 && (root.isKeyUp(event) || root.isKeyDown(event))) {
                    event.accepted = true
                    root.showHistory = true;
                    focusCurrentListView()
                }
                !event.accepted && results.navigationKeyHandler(event)
            }
            Keys.onTabPressed: event => {
                event.accepted = true
                if (!root.query) { root.railActive = !root.railActive; return }
                root.activatePrimaryResultAction()
            }
            function closeOrRun(event) {
                // Close KRunner if no text was typed and enter was pressed, FEATURE: 211225
                if (!root.query) {
                    root.runnerWindow.visible = false
                } else {
                    results.runCurrentIndex(event)
                }
            }
            Keys.onEnterPressed: event => closeOrRun(event)
            Keys.onReturnPressed: event => closeOrRun(event)

            Keys.onEscapePressed: {
                root.runnerWindow.visible = false
            }

            Kirigami.Icon {
                anchors {
                    right: parent.right
                    rightMargin: 6 // from PlasmaStyle TextFieldStyle
                    verticalCenter: parent.verticalCenter
                }
                // match clear button
                width: 18
                height: width
                source: "expand"
                visible: false
                enabled: root.runnerManager.history.length > 0

                MouseArea {
                    anchors.fill: parent
                    onPressed: {
                        root.showHistory = !root.showHistory
                        if (root.showHistory) {
                            listView.forceActiveFocus(); // is the history list
                        } else {
                            queryField.forceActiveFocus();
                        }
                    }
                }
            }
        }
        Repeater {
            model: [
                {name: "Applications", icon: "applications-all", runner: "krunner_services"},
                {name: "Files", icon: "folder", runner: "baloosearch"},
                {name: "Actions", icon: "view-list-details", runner: "krunner_shell"},
                {name: "Clipboard", icon: "edit-copy", runner: "clipboard"}
            ]
            delegate: QQC2.ToolButton {
                id: categoryButton
                required property var modelData
                required property int index
                x: 394 + index * 64 + (-42 - index * 7) * (1 - root.progress(index, 0))
                y: 1
                z: 3
                width: 54; height: 54
                opacity: root.progress(index, 0)
                scale: 0.36 + 0.64 * root.progress(index, 0)
                visible: !root.searching && opacity > 0.001
                enabled: root.railActive && opacity > 0.8
                readonly property bool selected: root.singleRunner === modelData.runner
                Accessible.name: modelData.name
                hoverEnabled: true
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: modelData.name
                onClicked: {
                    if (modelData.runner === "clipboard") {
                        root.runnerWindow.visible = false
                        root.runnerWindow.openClipboardHistory()
                    } else {
                        root.singleRunner = selected ? "" : modelData.runner
                        queryField.forceActiveFocus()
                    }
                }
                background: Rectangle {
                    objectName: "spotlightGlass"
                    radius: width / 2
                    color: categoryButton.selected ? "#a8457bb8" : categoryButton.hovered ? "#80555968" : "#60484a57"
                    border.width: 1
                    border.color: categoryButton.selected ? "#74baff" : "#e8ffffff"
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: "#000000"
                        shadowBlur: 0.6
                        shadowVerticalOffset: 4
                        shadowOpacity: 0.34
                    }
                }
                contentItem: Item {
                    opacity: root.progress(categoryButton.index, 0.12)
                    Canvas {
                        width: 25; height: 25
                        anchors.centerIn: parent
                        onPaint: {
                            const c = getContext("2d")
                            c.clearRect(0, 0, width, height)
                            c.strokeStyle = "#e0e3ed"
                            c.fillStyle = "#e0e3ed"
                            c.lineWidth = 1.8
                            c.lineCap = "round"
                            c.lineJoin = "round"
                            const kind = categoryButton.modelData.runner
                            c.beginPath()
                            if (kind === "krunner_services") {
                                c.arc(12.5, 12.5, 10, 0, Math.PI * 2)
                                c.stroke()
                                c.beginPath()
                                c.moveTo(7.5, 17); c.lineTo(12.5, 7); c.lineTo(17.5, 17)
                                c.moveTo(9.5, 13.5); c.lineTo(15.5, 13.5)
                            } else if (kind === "baloosearch") {
                                c.moveTo(3, 7); c.lineTo(10, 7); c.lineTo(12, 10)
                                c.lineTo(22, 10); c.lineTo(22, 20); c.lineTo(3, 20); c.closePath()
                            } else if (kind === "krunner_shell") {
                                c.moveTo(3, 7); c.lineTo(12.5, 2); c.lineTo(22, 7)
                                c.lineTo(12.5, 12); c.closePath()
                                c.moveTo(3, 12); c.lineTo(12.5, 17); c.lineTo(22, 12)
                                c.moveTo(3, 17); c.lineTo(12.5, 22); c.lineTo(22, 17)
                            } else {
                                c.rect(8, 8, 13, 15)
                                c.moveTo(5, 18); c.lineTo(3, 18); c.lineTo(3, 3); c.lineTo(16, 3); c.lineTo(16, 5)
                            }
                            c.stroke()
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        Layout.leftMargin: 20
        Layout.rightMargin: 20
        color: "#40ffffff"
        visible: root.searching && (resultScroll.visible || historyScroll.visible)
    }

    QQC2.ScrollView {
        id: resultScroll
        padding: 0
        background: Item {}
        QQC2.ScrollBar.vertical: QQC2.ScrollBar {
            policy: QQC2.ScrollBar.AlwaysOff
            implicitWidth: 5
            contentItem: Rectangle {
                implicitWidth: 5
                radius: 2.5
                color: parent.pressed ? "#65758d" : "#aab3c2"
                opacity: parent.active ? 0.8 : 0.4
            }
            background: Item {}
        }
        visible: root.query.length > 0 && results.count > 0
        enabled: visible
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: Math.min(394, results.contentHeight)
        Layout.maximumHeight: 394
        // Measured from the supplied @2x Mac screenshots: selection inset 10,
        // separator-to-row gap 10. The bottom inset matches the side insets.
        Layout.leftMargin: 10
        Layout.rightMargin: 10
        Layout.topMargin: 10
        // Optical compensation for the frame stroke at fractional display scale.
        Layout.bottomMargin: 10.75
        // This replaces the ColumnLayout spacing


        Milou.ResultsView {
            id: results
            queryString: root.query
            queryField: queryField
            singleRunner: root.singleRunner
            clip: true
            highlight: Item {}
            onActiveFocusChanged: if (activeFocus) root.highlightSelection = true
            delegate: SpotlightResult {
                highlightEnabled: root.highlightSelection
                onNavigationRequested: root.highlightSelection = true
                onHoverNavigationRequested: root.highlightSelection = false
                width: results.width
            }

            Keys.onTabPressed: event => {
                event.accepted = true
                root.activatePrimaryResultAction()
            }
            Keys.onBacktabPressed: event => { event.accepted = true }
            Keys.onEscapePressed: {
                root.runnerWindow.visible = false
            }

            onActivated: {
                if (!root.runnerWindow.pinned) {
                    root.runnerWindow.visible = false
                }
            }

            onUpdateQueryString: (text, cursorPosition) => {
                queryField.text = text
                queryField.select(cursorPosition, root.query.length)
                queryField.focus = true;
            }
        }
    }

    QQC2.ScrollView {
        id: historyScroll
        QQC2.ScrollBar.vertical: QQC2.ScrollBar {
            policy: QQC2.ScrollBar.AlwaysOff
            implicitWidth: 5
            contentItem: Rectangle {
                implicitWidth: 5
                radius: 2.5
                color: parent.pressed ? "#65758d" : "#aab3c2"
                opacity: parent.active ? 0.8 : 0.4
            }
            background: Item {}
        }
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: Math.min(360, listView.contentHeight)
        Layout.maximumHeight: 360
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        // This replaces the ColumnLayout spacing
        Layout.topMargin: Kirigami.Units.smallSpacing
        visible: root.query.length === 0 && listView.count > 0
        // don't accept keyboard input when not visible so the keys propagate to the other list
        enabled: visible

        ListView {
            id: listView // needs this id so the delegate can access it
            keyNavigationWraps: true
            highlight: PlasmaExtras.Highlight {}
            highlightMoveDuration: 0
            activeFocusOnTab: true
            model: []
            reuseItems: true
            delegate: Milou.ResultDelegate {
                id: resultDelegate

                required property var modelData

                width: listView.width
                typeText: index === 0 ? i18n("Recent Queries") : ""
                displayText: modelData
                actions: [{
                    iconSource: "list-remove-symbolic",
                    text: i18n("Remove")
                }]
                Accessible.description: i18n("Recent Queries")
            }

            onActiveFocusChanged: {
                if (!activeFocus && currentIndex == listView.count-1) {
                    currentIndex = 0;
                }
            }
            Keys.onReturnPressed: runCurrentIndex(event)
            Keys.onEnterPressed: runCurrentIndex(event)

            Keys.onTabPressed: {
                if (currentIndex == listView.count-1) {
                    listView.nextItemInFocusChain(true).forceActiveFocus();
                } else {
                    incrementCurrentIndex()
                }
            }
            Keys.onBacktabPressed: {
                if (currentIndex == 0) {
                    listView.nextItemInFocusChain(false).forceActiveFocus();
                } else {
                    decrementCurrentIndex()
                }
            }
            Keys.onPressed: event => {
                if (root.isKeyUp(event)) {
                    decrementCurrentIndex();
                } else if (root.isKeyDown(event)) {
                    incrementCurrentIndex();
                } else if (event.text !== "" && !event.accepted) {
                    // This prevents unprintable control characters from being inserted
                    if (event.key == Qt.Key_Escape) {
                        root.showHistory = false
                    } else if (!/[\x00-\x1F\x7F]/.test(event.text)) {
                        queryField.text += event.text;
                    }
                    queryField.focus = true;
                }
            }

            Keys.onUpPressed: decrementCurrentIndex()
            Keys.onDownPressed: incrementCurrentIndex()

            function runCurrentIndex(event) {
                var entry = root.runnerManager.history[currentIndex]
                if (entry) {
                    // If user presses Shift+Return to invoke an action, invoke the first runner action
                    if (event && event.modifiers === Qt.ShiftModifier
                            && currentItem.actions && currentItem.actions.length > 0) {
                        runAction(0);
                        return
                    }

                    queryField.text = entry
                    queryField.forceActiveFocus();
                }
            }

            function runAction(actionIndex) {
                if (actionIndex === 0) {
                    // QStringList changes just reset the model, so we'll remember the index and set it again
                    var currentIndex = listView.currentIndex
                    root.runnerManager.removeFromHistory(currentIndex)
                    model = root.runnerManager.history
                    listView.currentIndex = currentIndex
                }
            }
        }

    }

    QQC2.Label {
        text: "↑ ↓  Navigate        ↵  Open        Esc  Close"
        visible: false
        Layout.fillWidth: true
        Layout.topMargin: 12
        Layout.bottomMargin: 6
        horizontalAlignment: Text.AlignHCenter
        color: "#818797"
        opacity: 0.8
        font.pixelSize: 11
    }

    } // content layout
    } // animated clipping viewport
}
