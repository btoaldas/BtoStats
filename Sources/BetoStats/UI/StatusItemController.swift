import AppKit

/// Status item con cuadrícula compacta multi-columna (2 filas, mono 9 pt)
/// y menú con detalle.
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let store: MetricStore

    private let cpuMenuItem = NSMenuItem(title: "CPU: midiendo…", action: nil, keyEquivalent: "")
    private let memoryMenuItem = NSMenuItem(title: "RAM: midiendo…", action: nil, keyEquivalent: "")
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
        menu.addItem(cpuMenuItem)
        menu.addItem(memoryMenuItem)
        menu.addItem(networkMenuItem)
        menu.addItem(diskMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir de BetoStats",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func render() {
        let cpuText = store.cpu.map { String(format: "%3.0f%%", $0.totalUsage * 100) } ?? " --%"
        let memText = store.memory.map { String(format: "%3.0f%%", $0.fractionUsed * 100) } ?? " --%"
        let upText = store.network.map { Self.rate($0.uploadBps) } ?? "   --"
        let downText = store.network.map { Self.rate($0.downloadBps) } ?? "   --"

        var columns: [[(String, String)]] = [
            [("CPU", cpuText), ("MEM", memText)],
            [("↑", upText), ("↓", downText)],
        ]
        if let disk = store.disk {
            columns.append([("D", Self.bytes(disk.availableBytes)),
                            ("", Self.bytes(disk.totalBytes))])
        }
        statusItem.button?.attributedTitle = Self.grid(columns: columns)

        if let cpu = store.cpu {
            cpuMenuItem.title = String(format: "CPU: %.1f%% (%d núcleos)",
                                       cpu.totalUsage * 100, cpu.perCore.count)
        }
        if let memory = store.memory {
            memoryMenuItem.title = String(format: "RAM: %.1f / %.0f GB (%.0f%%)",
                                          memory.usedBytes / 1_073_741_824,
                                          memory.totalBytes / 1_073_741_824,
                                          memory.fractionUsed * 100)
        }
        if let network = store.network {
            networkMenuItem.title = "Red: ↑ \(Self.rate(network.uploadBps))/s   ↓ \(Self.rate(network.downloadBps))/s"
        }
        if let disk = store.disk {
            diskMenuItem.title = "Disco: \(Self.bytes(disk.availableBytes)) disponibles de \(Self.bytes(disk.totalBytes)) (libre real \(Self.bytes(disk.freeBytes)))"
        }
    }

    /// Tasa en B/s → texto de ancho fijo (5 caracteres).
    static func rate(_ bps: Double) -> String {
        let value = max(bps, 0)
        switch value {
        case ..<1000: return String(format: "%4.0fB", value)
        case ..<999_500: return String(format: "%4.0fK", value / 1000)
        case ..<999_500_000: return String(format: "%4.1fM", value / 1_000_000)
        default: return String(format: "%4.1fG", value / 1_000_000_000)
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

    /// Cuadrícula de N columnas × 2 filas para el status item.
    /// Cada columna es [(label, valor) fila superior, (label, valor) fila inferior].
    static func grid(columns: [[(String, String)]]) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 10
        paragraph.maximumLineHeight = 10
        paragraph.alignment = .left

        let labelFont = NSFont.monospacedSystemFont(ofSize: 7, weight: .semibold)
        let valueFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)

        let result = NSMutableAttributedString()
        for row in 0..<2 {
            let line = NSMutableAttributedString()
            for (columnIndex, column) in columns.enumerated() {
                guard row < column.count else { continue }
                let (label, value) = column[row]
                if columnIndex > 0 {
                    line.append(NSAttributedString(string: "  ", attributes: [
                        .font: valueFont, .paragraphStyle: paragraph,
                    ]))
                }
                if !label.isEmpty {
                    line.append(NSAttributedString(string: label + " ", attributes: [
                        .font: labelFont,
                        .foregroundColor: NSColor.labelColor,
                        .paragraphStyle: paragraph,
                    ]))
                }
                line.append(NSAttributedString(string: value, attributes: [
                    .font: valueFont,
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraph,
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
