import AppKit

/// Status item con cuadrícula compacta multi-columna (2 filas, mono 9 pt)
/// y menú con detalle.
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let store: MetricStore
    private let settingsController = SettingsWindowController()
    let panelController = PanelController()
    private var contextMenu: NSMenu?
    private var renderCount = 0

    private let cpuMenuItem = NSMenuItem(title: "CPU: midiendo…", action: nil, keyEquivalent: "")
    private let memoryMenuItem = NSMenuItem(title: "RAM: midiendo…", action: nil, keyEquivalent: "")
    private let gpuMenuItem = NSMenuItem(title: "GPU: midiendo…", action: nil, keyEquivalent: "")
    private let sensorsMenuItem = NSMenuItem(title: "Sensores: midiendo…", action: nil, keyEquivalent: "")
    private let networkMenuItem = NSMenuItem(title: "Red: midiendo…", action: nil, keyEquivalent: "")
    private let diskMenuItem = NSMenuItem(title: "Disco: midiendo…", action: nil, keyEquivalent: "")

    init(store: MetricStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        applyGrid(Self.grid(columns: [
            [("CPU", "--"), ("MEM", "--")],
        ], rows: 2))
        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in [cpuMenuItem, gpuMenuItem, memoryMenuItem, sensorsMenuItem, networkMenuItem, diskMenuItem] {
            item.isEnabled = true
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "",
                                  action: #selector(openSettings),
                                  keyEquivalent: ",")
        settings.target = self
        settings.isEnabled = true
        settings.attributedTitle = Self.detailTitle("Preferencias…")
        menu.addItem(settings)
        // El badge de atajo del sistema siempre se pinta tenue; se embebe "⌘Q"
        // en el título para que salga en blanco pleno.
        let quit = NSMenuItem(title: "",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "")
        quit.isEnabled = true
        let quitTitle = NSMutableAttributedString(string: "Salir de BtoStats", attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.labelColor,
        ])
        quitTitle.append(NSAttributedString(string: "   ⌘Q", attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.labelColor,
        ]))
        quit.attributedTitle = quitTitle
        menu.addItem(quit)
        contextMenu = menu
    }

    /// El botón no computa el ancho de los right-tabs: fijar length explícito
    /// (de paso elimina cualquier baile de ancho al refrescar).
    private func applyGrid(_ grid: (title: NSAttributedString, width: CGFloat)) {
        statusItem.button?.attributedTitle = grid.title
        // margen mínimo: solo lo justo para que el botón no recorte los bordes
        statusItem.length = grid.width + 6
    }

    /// Clic izquierdo: panel grande. Clic derecho: menú de detalle.
    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem.menu = contextMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil // sin esto el menú captura también el clic izquierdo
        } else {
            panelController.toggle(relativeTo: statusItem.button, store: store)
        }
    }

    /// Título de ítem de detalle en blanco pleno (los ítems informativos sin
    /// autoenables igual se pintan tenues si se usa title plano).
    private static func detailTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.labelColor,
        ])
    }

    @objc private func openSettings() {
        settingsController.show()
    }

    /// Valor de una métrica para su celda, o nil si el reader aún no entrega dato.
    private func cellValue(for metric: MetricID) -> String {
        switch metric {
        case .cpu: return store.cpu.map { String(format: "%.0f%%", $0.totalUsage * 100) } ?? "--"
        case .memory: return store.memory.map { String(format: "%.0f%%", $0.fractionUsed * 100) } ?? "--"
        case .gpu: return store.gpu.map { String(format: "%.0f%%", $0.utilization) } ?? "--"
        case .temperature: return store.sensors?.cpuTempAvg.map { String(format: "%.0f°", $0) } ?? "--"
        case .network: return "" // el bloque de red se expande en render()
        case .diskFree: return store.disk.map { Self.bytes($0.availableBytes) } ?? "--"
        case .diskTotal: return store.disk.map { Self.bytes($0.totalBytes) } ?? "--"
        }
    }

    func render() {
        let config = AppConfig.shared
        let rows = config.gridRows

        // Cada métrica es un bloque de 1 celda, salvo la red: bloque indivisible
        // de 2 celdas contiguas en la misma columna (↑ arriba, ↓ abajo).
        var blocks: [[(String, String)]] = []
        for metric in config.visibleMetrics {
            if metric == .network {
                let up = store.network.map { Self.rate($0.uploadBps) } ?? "--"
                let down = store.network.map { Self.rate($0.downloadBps) } ?? "--"
                blocks.append([("↑", up), ("↓", down)])
            } else {
                blocks.append([(metric.gridLabel, cellValue(for: metric))])
            }
        }

        // Empaquetado por columnas de `rows` celdas sin partir bloques:
        // si el bloque no cabe en lo que queda de columna, se rellena y se abre otra.
        var columns: [[(String, String)?]] = []
        var current: [(String, String)?] = []
        for block in blocks {
            if current.count + block.count > rows {
                while current.count < rows { current.append(nil) }
                columns.append(current)
                current = []
            }
            current.append(contentsOf: block.map { Optional($0) })
            if current.count == rows {
                columns.append(current)
                current = []
            }
        }
        if !current.isEmpty {
            while current.count < rows { current.append(nil) }
            columns.append(current)
        }

        applyGrid(columns.isEmpty
            ? Self.grid(columns: [[("Bto", "Stats")]], rows: 1)
            : Self.grid(columns: columns, rows: rows))

        if let cpu = store.cpu {
            cpuMenuItem.attributedTitle = Self.detailTitle(String(format: "CPU: %.1f%% (%d núcleos)",
                                                                 cpu.totalUsage * 100, cpu.perCore.count))
        }
        if let memory = store.memory {
            memoryMenuItem.attributedTitle = Self.detailTitle(String(format: "RAM: %.1f / %.0f GB (%.0f%%)",
                                                                     memory.usedBytes / 1_073_741_824,
                                                                     memory.totalBytes / 1_073_741_824,
                                                                     memory.fractionUsed * 100))
        }
        if let gpu = store.gpu {
            var text = String(format: "GPU: %.1f%%", gpu.utilization)
            if let memory = gpu.usedMemoryBytes {
                text += String(format: " (memoria en uso: %.1f GB)", Double(memory) / 1e9)
            }
            gpuMenuItem.attributedTitle = Self.detailTitle(text)
        }
        if let sensors = store.sensors {
            var parts: [String] = []
            if let avg = sensors.cpuTempAvg, let peak = sensors.cpuTempMax {
                parts.append(String(format: "CPU %.0f° (máx %.0f°)", avg, peak))
            }
            if let gpuTemp = sensors.gpuTempAvg {
                parts.append(String(format: "GPU %.0f°", gpuTemp))
            }
            if !sensors.fanRPM.isEmpty {
                let fans = sensors.fanRPM.map { String(format: "%.0f", $0) }.joined(separator: " / ")
                parts.append("Ventiladores \(fans) RPM")
            }
            if !parts.isEmpty {
                sensorsMenuItem.attributedTitle = Self.detailTitle("Sensores: " + parts.joined(separator: "  ·  "))
            }
        }
        if let network = store.network {
            networkMenuItem.attributedTitle = Self.detailTitle(
                "Red: ↑ \(Self.rate(network.uploadBps))/s   ↓ \(Self.rate(network.downloadBps))/s")
        }
        renderCount += 1
        if renderCount == 10 {
            // sensores/GPU inexistentes en este equipo: decirlo en vez de
            // dejar "midiendo…" para siempre
            if store.sensors == nil {
                sensorsMenuItem.attributedTitle = Self.detailTitle("Sensores: no disponibles en este equipo")
            }
            if store.gpu == nil {
                gpuMenuItem.attributedTitle = Self.detailTitle("GPU: no disponible en este equipo")
            }
        }
        if let disk = store.disk {
            diskMenuItem.attributedTitle = Self.detailTitle(
                "Disco: \(Self.bytes(disk.availableBytes)) disponibles de \(Self.bytes(disk.totalBytes)) (libre real \(Self.bytes(disk.freeBytes)))")
        }
    }

    /// Tasa en B/s → texto de ancho fijo (5 caracteres).
    static func rate(_ bps: Double) -> String {
        let value = max(bps, 0)
        switch value {
        case ..<1000: return String(format: "%.0fB", value)
        case ..<999_500: return String(format: "%.0fK", value / 1000)
        case ..<999_500_000: return String(format: "%.1fM", value / 1_000_000)
        default: return String(format: "%.1fG", value / 1_000_000_000)
        }
    }

    /// Bytes → texto compacto decimal (como Finder: 1 GB = 1000³).
    static func bytes(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        switch value {
        case ..<999_500_000: return String(format: "%.0fM", value / 1_000_000)
        case ..<999_500_000_000: return String(format: "%.0fG", value / 1_000_000_000)
        default: return String(format: "%.2fT", value / 1_000_000_000_000)
        }
    }

    /// Cuadrícula de N columnas × `rows` filas para el status item.
    /// Alineación por relleno monoespaciado exacto por columna (los tab stops
    /// se desfasaban cuando un valor rozaba su posición): label a la izquierda,
    /// valor a la derecha, 1 espacio entre ambos, 2 entre columnas.
    static func grid(columns: [[(String, String)?]], rows: Int) -> (title: NSAttributedString, width: CGFloat) {
        let lineHeight: CGFloat = rows >= 4 ? 5.2 : (rows == 3 ? 6.6 : 9)
        let labelSize: CGFloat = rows >= 4 ? 4.5 : (rows == 3 ? 5 : 6.5)
        let valueSize: CGFloat = rows >= 4 ? 5.5 : (rows == 3 ? 6.5 : 8.5)
        let labelFont = NSFont.monospacedSystemFont(ofSize: labelSize, weight: .semibold)
        let valueFont = NSFont.monospacedSystemFont(ofSize: valueSize, weight: .medium)
        let baseline: CGFloat = rows >= 4 ? -1.5 : (rows == 3 ? -2 : -3)

        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakMode = .byClipping

        func attributed(_ text: String, _ font: NSFont, kern: CGFloat = 0) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
                .baselineOffset: baseline,
                .kern: kern,
            ])
        }

        // Separadores uniformes y mínimos: 0.5 espacios entre título y valor,
        // 1 espacio entre columnas (el medio espacio se logra con kern negativo).
        let spaceAdvance = (" " as NSString).size(withAttributes: [.font: valueFont]).width
        let halfSpace = attributed(" ", valueFont, kern: -spaceAdvance * 0.5)
        let columnSpace = attributed(" ", valueFont)

        // Ancho de cada columna en caracteres (fuentes mono → padding exacto).
        let metrics: [(label: Int, value: Int)] = columns.map { column in
            var label = 0, value = 0
            for cell in column.compactMap({ $0 }) {
                label = max(label, cell.0.count)
                value = max(value, cell.1.count)
            }
            return (label, value)
        }

        func pad(_ text: String, to width: Int, alignRight: Bool) -> String {
            let fill = String(repeating: " ", count: max(width - text.count, 0))
            return alignRight ? fill + text : text + fill
        }

        let result = NSMutableAttributedString()
        var maxWidth: CGFloat = 0
        for row in 0..<rows {
            let line = NSMutableAttributedString()
            for (index, column) in columns.enumerated() {
                let cell = row < column.count ? column[row] : nil
                if index > 0 {
                    line.append(columnSpace)
                }
                line.append(attributed(pad(cell?.0 ?? "", to: metrics[index].label, alignRight: false), labelFont))
                line.append(halfSpace)
                line.append(attributed(pad(cell?.1 ?? "", to: metrics[index].value, alignRight: true), valueFont))
            }
            maxWidth = max(maxWidth, line.size().width)
            if row < rows - 1 {
                line.append(attributed("\n", valueFont))
            }
            result.append(line)
        }
        return (result, ceil(maxWidth))
    }
}
