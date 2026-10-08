/*
 * TTSiro: icono de la barra que indica si la voz está precargada en memoria.
 *
 * No habla con el daemon directamente: consulta `ttsiro-piper --estado` (una línea JSON) cada pocos
 * segundos y ejecuta `--precargar` / `--salir` desde el popup o el menú contextual.
 */
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    // instalar.sh enlaza bin/ttsiro-piper en ~/.local/bin. Ruta completa: plasmashell puede no tener
    // ~/.local/bin en el PATH.
    readonly property string cli: "\"$HOME/.local/bin/ttsiro-piper\""
    readonly property string cmdEstado: cli + " --estado"
    // En un scope propio de systemd, para que el daemon no muera si se reinicia plasmashell.
    readonly property string cmdPrecargar: "systemd-run --user --scope --quiet " + cli + " --precargar || " + cli + " --precargar"
    readonly property string cmdLiberar: cli + " --salir"

    // lista | cargando | iniciando | otra_voz | apagado | sin_perfil | error | consultando
    property string estado: "consultando"
    property string voz: ""
    property int memoriaMb: 0
    property bool consultando: false
    property bool accionEnCurso: false

    readonly property bool lista: estado === "lista"
    readonly property bool trabajando: accionEnCurso || estado === "iniciando" || estado === "cargando"
    readonly property bool hayDaemon: ["iniciando", "cargando", "lista", "otra_voz"].indexOf(estado) >= 0

    readonly property string titulo: {
        switch (estado) {
        case "lista": return "Voz precargada"
        case "cargando": return "Cargando la voz…"
        case "iniciando": return "Iniciando el daemon…"
        case "otra_voz": return "La voz activa no está precargada"
        case "apagado": return "Voz no precargada"
        case "sin_perfil": return "TTSiro sin perfil activo"
        case "error": return "No se pudo consultar el estado"
        default: return "TTSiro"
        }
    }
    readonly property string detalle: {
        switch (estado) {
        case "lista": return voz + " · " + memoriaMb + " MB en memoria"
        case "cargando": return voz
        case "iniciando": return "Arrancando ttsirod…"
        case "otra_voz": return "Perfil activo: " + voz + ". El daemon tiene otra voz cargada; la primera lectura con esta tardará más."
        case "apagado": return "El daemon está apagado: la primera lectura tardará más."
        case "sin_perfil": return "Falta activo.env. Guarda un perfil desde la UI de TTSiro."
        case "error": return "Revisa que ~/.local/bin/ttsiro-piper exista (./instalar.sh)."
        default: return ""
        }
    }
    readonly property color colorEstado: {
        if (lista) return Kirigami.Theme.positiveTextColor
        if (trabajando) return Kirigami.Theme.neutralTextColor
        if (estado === "apagado" || estado === "otra_voz") return Kirigami.Theme.negativeTextColor
        return Kirigami.Theme.disabledTextColor
    }

    function procesarEstado(salida) {
        try {
            const d = JSON.parse(salida.trim())
            estado = d.estado
            voz = d.voz || ""
            memoriaMb = d.rss_mb || 0
        } catch (e) {
            estado = "error"
            voz = ""
            memoriaMb = 0
        }
    }
    function consultar() {
        if (consultando) return
        consultando = true
        ejecutor.connectSource(cmdEstado)
    }
    function precargar() {
        if (accionEnCurso) return
        accionEnCurso = true
        ejecutor.connectSource(cmdPrecargar)
    }
    function liberar() {
        if (accionEnCurso) return
        accionEnCurso = true
        ejecutor.connectSource(cmdLiberar)
    }

    P5Support.DataSource {
        id: ejecutor
        engine: "executable"
        connectedSources: []
        onNewData: (fuente, datos) => {
            disconnectSource(fuente)
            if (fuente === root.cmdEstado) {
                root.consultando = false
                root.procesarEstado(datos["stdout"] || "")
            } else {
                root.accionEnCurso = false
                root.consultar()
            }
        }
    }

    Timer {
        interval: root.trabajando ? 1000 : 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.consultar()
    }

    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    toolTipMainText: titulo
    toolTipSubText: detalle

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: "Precargar la voz"
            icon.name: "media-playback-start"
            enabled: !root.trabajando && !root.lista
            onTriggered: root.precargar()
        },
        PlasmaCore.Action {
            text: "Liberar memoria"
            icon.name: "edit-clear-all"
            enabled: !root.accionEnCurso && root.hayDaemon
            onTriggered: root.liberar()
        }
    ]

    compactRepresentation: MouseArea {
        id: compacto
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        Layout.minimumWidth: Plasmoid.formFactor === PlasmaCore.Types.Horizontal ? height : Kirigami.Units.iconSizes.small
        Layout.minimumHeight: Plasmoid.formFactor === PlasmaCore.Types.Vertical ? width : Kirigami.Units.iconSizes.small

        Kirigami.Icon {
            anchors.fill: parent
            source: "text-speak"
            fallback: "audio-volume-high"
            active: compacto.containsMouse
            opacity: root.lista || root.trabajando ? 1.0 : 0.6
        }

        // Punto de estado: verde = precargada, ámbar (parpadea) = cargando, rojo = no precargada.
        Rectangle {
            id: punto
            width: Math.max(6, Math.round(parent.height * 0.34))
            height: width
            radius: width / 2
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            color: root.colorEstado
            border.width: 1
            border.color: Kirigami.Theme.backgroundColor

            SequentialAnimation on opacity {
                running: root.trabajando
                loops: Animation.Infinite
                NumberAnimation { to: 0.25; duration: 600 }
                NumberAnimation { to: 1.0; duration: 600 }
                onRunningChanged: if (!running) punto.opacity = 1.0
            }
        }
    }

    fullRepresentation: ColumnLayout {
        spacing: Kirigami.Units.largeSpacing
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.preferredWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 7

        RowLayout {
            spacing: Kirigami.Units.largeSpacing
            Layout.fillWidth: true

            Kirigami.Icon {
                source: "text-speak"
                fallback: "audio-volume-high"
                implicitWidth: Kirigami.Units.iconSizes.large
                implicitHeight: Kirigami.Units.iconSizes.large
                opacity: root.lista || root.trabajando ? 1.0 : 0.6
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Kirigami.Heading {
                    level: 3
                    text: root.titulo
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
                PlasmaComponents3.Label {
                    text: root.detalle
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Button {
                Layout.fillWidth: true
                text: "Precargar ahora"
                icon.name: "media-playback-start"
                enabled: !root.trabajando && !root.lista
                onClicked: root.precargar()
            }
            PlasmaComponents3.Button {
                Layout.fillWidth: true
                text: "Liberar memoria"
                icon.name: "edit-clear-all"
                enabled: !root.accionEnCurso && root.hayDaemon
                onClicked: root.liberar()
            }
        }

        Item { Layout.fillHeight: true }
    }
}
