import AppKit

/// Status item con cuadrícula compacta multi-columna (2 filas, mono 9 pt)
/// y menú con detalle.
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let store: MetricStore

    private let cpuMenuItem = NSMenuItem(title: "CPU: midiendo…", action: nil, keyEquivalent: "")
    private let memoryMenuItem = NSMenuItem(title: "RAM: midiendo…", action: nil, keyEquivalent: "")
    private let gpuMenuItem = NSMenuItem(title: "GPU: midiendo…", action: nil, keyEquivalent: "")
    private let sensorsMenuItem = NSMenuItem(title: "Sensores: midiendo…", action: nil, keyEquivalent: "")
    private let networkMenuItem = NSMenuItem(title: "Red: midiendo…", action: nil, keyEquivalent: "")
    private let diskMenuItem = NSMenuItem(title: "Disco: midiendo…", action: nil, keyEquivalent: "")

    init(store: MetricStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.attributedTitle = Self.grid(columns: [
            [("CPU", " --%"), ("MEM", " --%")],
            [("↑", "   --"), ("↓", "   --")],
        ])
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
        // El badge de atajo del sistema siempre se pinta tenue; se embebe "⌘Q"
        // en el título para que salga en blanco pleno.
        let quit = NSMenuItem(title: "",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "")
        quit.isEnabled = true
        let quitTitle = NSMutableAttributedString(string: "Salir de BetoStats", attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.labelColor,
        ])
        quitTitle.append(NSAttributedString(string: "   ⌘Q", attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.labelColor,
        ]))
        quit.attributedTitle = quitTitle
        menu.addItem(quit)
        statusItem.menu = menu
    }

    /// Título de ítem de detalle en blanco pleno (los ítems informativos sin
    /// autoenables igual se pintan tenues si se usa title plano).
    private static func detailTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.labelColor,
        ])
    }

    func render() {
        let cpuText = store.cpu.map { String(format: "%3.0f%%", $0.totalUsage * 100) } ?? " --%"
        let memText = store.memory.map { String(format: "%3.0f%%", $0.fractionUsed * 100) } ?? " --%"
        let upText = store.network.map { Self.rate($0.uploadBps) } ?? "   --"
        let downText = store.network.map { Self.rate($0.downloadBps) } ?? "   --"

        var columns: [[(String, String)]] = [
            [("CPU", cpuText), ("MEM", memText)],
        ]
        if store.gpu != nil || store.sensors?.cpuTempAvg != nil {
            let gpuText = store.gpu.map { String(format: "%3.0f%%", $0.utilization) } ?? " --%"
            let tempText = store.sensors?.cpuTempAvg.map { String(format: "%3.0f°", $0) } ?? " --°"
            columns.append([("GPU", gpuText), ("TMP", tempText)])
        }
        columns.append([("↑", upText), ("↓", downText)])
        if let disk = store.disk {
            columns.append([("D", Self.bytes(disk.availableBytes)),
                            (" ", Self.bytes(disk.totalBytes))])
        }
        statusItem.button?.attributedTitle = Self.grid(columns: columns)

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
        if let disk = store.disk {
            diskMenuItem.attributedTitle = Self.detailTitle(
                "Disco: \(Self.bytes(disk.availableBytes)) disponibles de \(Self.bytes(disk.totalBytes)) (libre real \(Self.bytes(disk.freeBytes)))")
        }
    }

    /// Tasa en B/s → texto de ancho fijo (5 caracteres).
    static func rate(_ bps: Double) -> String {
        let value = max(bps, 0)
        switch value {
        case ..<1000: return String(format: "%3.0fB", value)
        case ..<999_500: return String(format: "%3.0fK", value / 1000)
        case ..<999_500_000: return String(format: "%3.1fM", value / 1_000_000)
        default: return String(format: "%3.1fG", value / 1_000_000_000)
        }
    }

    /// Bytes → texto compacto decimal (como Finder: 1 GB = 1000³).
    static func bytes(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        switch value {
        case ..<999_500_000: return String(format: "%4.0fM", value / 1_000_000)
        case ..<999_500_000_000: return String(format: "%4.0fG", value / 1_000_000_000)
        default: return String(format: "%4.2fT", value / 1_000_000_000_000)
        }
    }

    /// Cuadrícula de N columnas × 2 filas para el status item.
    /// Cada columna es [(label, valor) fila superior, (label, valor) fila inferior].
    static func grid(columns: [[(String, String)]]) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 9
        paragraph.maximumLineHeight = 9
        paragraph.alignment = .left

        let labelFont = NSFont.monospacedSystemFont(ofSize: 6.5, weight: .semibold)
        let valueFont = NSFont.monospacedSystemFont(ofSize: 8.5, weight: .medium)
        let baseline: CGFloat = -3

        let result = NSMutableAttributedString()
        for row in 0..<2 {
            let line = NSMutableAttributedString()
            for (columnIndex, column) in columns.enumerated() {
                guard row < column.count else { continue }
                let (label, value) = column[row]
                if columnIndex > 0 {
                    line.append(NSAttributedString(string: " ", attributes: [
                        .font: valueFont, .paragraphStyle: paragraph, .baselineOffset: baseline,
                    ]))
                }
                line.append(NSAttributedString(string: label + " ", attributes: [
                    .font: labelFont,
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraph,
                    .baselineOffset: baseline,
                ]))
                line.append(NSAttributedString(string: value, attributes: [
                    .font: valueFont,
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraph,
                    .baselineOffset: baseline,
                ]))
            }
            if row == 0 {
                line.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: paragraph]))
            }
            result.append(line)
        }
        return result
    }
}
