import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ExpanderTester

ApplicationWindow {
    id: win
    width: 940
    height: Math.min(920, Screen.desktopAvailableHeight - 40)
    minimumWidth: 940
    minimumHeight: 700
    visible: true
    title: "CAN I/O Expander — Tester (PEAK PCAN-USB)"

    readonly property string monoFont: "Consolas"

    ExpanderController {
        id: ctrl
        onLogLine: (line) => {
            if (logArea.length > 60000)
                logArea.clear()
            logArea.append(line)
        }
        onErrorOccurred: (message) => {
            errorDialog.text = message
            errorDialog.open()
        }
    }

    Component.onDestruction: ctrl.disconnectBus()

    Dialog {
        id: errorDialog
        property alias text: errorLabel.text
        title: "Errore"
        modal: true
        anchors.centerIn: parent
        width: Math.min(560, win.width - 40)
        standardButtons: Dialog.Ok
        Label {
            id: errorLabel
            width: parent.width
            wrapMode: Text.Wrap
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 6

        // ---- Connessione ----
        GroupBox {
            title: "Connessione"
            Layout.fillWidth: true
            RowLayout {
                spacing: 10
                ComboBox {
                    id: cboChannel
                    model: ctrl.channelNames
                    enabled: !ctrl.connected
                    implicitWidth: 140
                }
                ComboBox {
                    id: cboBaud
                    model: ctrl.baudNames
                    enabled: !ctrl.connected
                    implicitWidth: 120
                }
                Label { text: "Nodo:" }
                SpinBox {
                    from: 0
                    to: 15
                    value: ctrl.node
                    editable: true
                    onValueModified: ctrl.node = value
                }
                Button {
                    text: ctrl.connected ? "Disconnetti" : "Connetti"
                    implicitWidth: 110
                    onClicked: ctrl.toggleConnection(cboChannel.currentIndex, cboBaud.currentIndex)
                }
                Label {
                    text: ctrl.connected ? "Connesso" : "Disconnesso"
                    color: ctrl.connected ? "forestgreen" : "firebrick"
                    font.bold: true
                }
            }
        }

        // ---- Direzione (CONFIG) ----
        GroupBox {
            title: "Direzione pin (CONFIG)  —  1 = uscita, 0 = ingresso"
            Layout.fillWidth: true
            RowLayout {
                spacing: 10
                Label { text: "Maschera (hex):" }
                TextField {
                    id: txtDir
                    text: "FFFF0000"
                    implicitWidth: 110
                    font.family: win.monoFont
                }
                Button {
                    text: "Imposta direzione"
                    onClicked: ctrl.setDirection(txtDir.text)
                }
                Button {
                    text: "Tutte uscite"
                    onClicked: { txtDir.text = "FFFFFFFF"; ctrl.setDirection(txtDir.text) }
                }
                Button {
                    text: "Tutti ingressi"
                    onClicked: { txtDir.text = "00000000"; ctrl.setDirection(txtDir.text) }
                }
            }
        }

        // ---- Uscite (OUTPUT) ----
        GroupBox {
            title: "Uscite (OUTPUT)  —  premuto = livello alto"
            Layout.fillWidth: true
            RowLayout {
                anchors.fill: parent
                spacing: 12
                GridLayout {
                    columns: 16
                    rowSpacing: 4
                    columnSpacing: 2
                    Repeater {
                        id: outRepeater
                        model: 32
                        Button {
                            required property int index
                            text: index
                            checkable: true
                            implicitWidth: 45
                            implicitHeight: 40
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                ColumnLayout {
                    Button {
                        text: "Scrivi uscite"
                        Layout.fillWidth: true
                        onClicked: ctrl.writeOutputs(win.outputBits())
                    }
                    Button {
                        text: "Azzera"
                        Layout.fillWidth: true
                        onClicked: {
                            for (let i = 0; i < 32; i++)
                                outRepeater.itemAt(i).checked = false
                            ctrl.writeOutputs(win.outputBits())
                        }
                    }
                }
            }
        }

        // ---- Stato pin (STATUS) ----
        GroupBox {
            title: "Stato pin (STATUS)  —  verde = alto"
            Layout.fillWidth: true
            RowLayout {
                anchors.fill: parent
                spacing: 12
                GridLayout {
                    columns: 16
                    rowSpacing: 4
                    columnSpacing: 2
                    Repeater {
                        model: 32
                        Rectangle {
                            required property int index
                            implicitWidth: 45
                            implicitHeight: 40
                            color: ctrl.pinStates[index] ? "limegreen" : "gainsboro"
                            border.color: "gray"
                            Label {
                                anchors.centerIn: parent
                                text: parent.index
                                color: "black"
                            }
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                Button {
                    text: "Leggi stato"
                    Layout.alignment: Qt.AlignTop
                    onClicked: ctrl.requestStatus()
                }
            }
        }

        // ---- Encoder ----
        GroupBox {
            title: "Encoder incrementali (conteggi 16 bit con segno)"
            Layout.fillWidth: true
            ColumnLayout {
                spacing: 6
                RowLayout {
                    spacing: 18
                    Repeater {
                        model: 8
                        ColumnLayout {
                            id: encCell
                            required property int index
                            spacing: 2
                            Label { text: "ENC" + encCell.index }
                            Rectangle {
                                implicitWidth: 90
                                implicitHeight: 26
                                color: "white"
                                border.color: "gray"
                                Label {
                                    anchors.centerIn: parent
                                    text: ctrl.encValues[encCell.index]
                                    font.family: win.monoFont
                                    font.pixelSize: 15
                                    font.bold: true
                                    color: "black"
                                }
                            }
                        }
                    }
                }
                RowLayout {
                    spacing: 10
                    Label { text: "Periodo (ms):" }
                    TextField {
                        id: txtPeriod
                        text: "50"
                        implicitWidth: 60
                        validator: IntValidator { bottom: 0; top: 65535 }
                    }
                    Button {
                        text: "Imposta periodo"
                        onClicked: ctrl.setEncPeriod(txtPeriod.text)
                    }
                    Button {
                        text: "Stop periodico"
                        onClicked: { txtPeriod.text = "0"; ctrl.setEncPeriod(txtPeriod.text) }
                    }
                    Button {
                        text: "Azzera encoder"
                        onClicked: ctrl.resetEncoders()
                    }
                }
            }
        }

        // ---- Analogico (solo MAX 10) ----
        GroupBox {
            title: "Ingressi analogici (ADC 12 bit, solo MAX 10)  —  giallo = sotto soglia, rosso = sopra soglia"
            Layout.fillWidth: true
            ColumnLayout {
                spacing: 6
                RowLayout {
                    spacing: 18
                    Repeater {
                        id: anaRepeater
                        model: 8
                        ColumnLayout {
                            id: anaCell
                            required property int index
                            property alias thrText: thrField.text
                            spacing: 2
                            Label { text: "AN" + anaCell.index }
                            Rectangle {
                                implicitWidth: 90
                                implicitHeight: 26
                                color: (ctrl.adcOver >> anaCell.index) & 1 ? "lightsalmon" : "lightyellow"
                                border.color: "gray"
                                Label {
                                    anchors.centerIn: parent
                                    text: ctrl.adcValues[anaCell.index] < 0 ? "-" : ctrl.adcValues[anaCell.index]
                                    font.family: win.monoFont
                                    font.pixelSize: 15
                                    font.bold: true
                                    color: "black"
                                }
                            }
                            TextField {
                                id: thrField
                                text: "FFF"
                                implicitWidth: 90
                                font.family: win.monoFont
                            }
                        }
                    }
                }
                RowLayout {
                    spacing: 10
                    Label { text: "Soglie (hex, 12 bit):" }
                    Button {
                        text: "Imposta soglie"
                        onClicked: ctrl.setThresholds(win.thresholdTexts())
                    }
                    Button {
                        text: "Tutte a fondo scala"
                        onClicked: {
                            for (let i = 0; i < 8; i++)
                                anaRepeater.itemAt(i).thrText = "FFF"
                            ctrl.setThresholds(win.thresholdTexts())
                        }
                    }
                }
            }
        }

        // ---- Log ----
        GroupBox {
            title: "Traffico CAN"
            Layout.fillWidth: true
            Layout.fillHeight: true
            ColumnLayout {
                anchors.fill: parent
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    TextArea {
                        id: logArea
                        readOnly: true
                        font.family: win.monoFont
                        font.pixelSize: 12
                        wrapMode: TextEdit.NoWrap
                        onTextChanged: cursorPosition = length
                    }
                }
                Button {
                    text: "Pulisci"
                    Layout.alignment: Qt.AlignRight
                    onClicked: logArea.clear()
                }
            }
        }
    }

    function outputBits() {
        let bits = []
        for (let i = 0; i < 32; i++)
            bits.push(outRepeater.itemAt(i).checked)
        return bits
    }

    function thresholdTexts() {
        let t = []
        for (let i = 0; i < 8; i++)
            t.push(anaRepeater.itemAt(i).thrText)
        return t
    }
}
