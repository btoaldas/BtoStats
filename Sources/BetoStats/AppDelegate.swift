import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private let cpuReader = CPUReader()
    private let memoryReader = MemoryReader()
    private var detailCPUItem: NSMenuItem!
    private var detailMemItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.attributedTitle = Self.grid(rows: [("CPU", "--%"), ("MEM", "--%")])
        buildMenu()

        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    private func buildMenu() {
        let menu = NSMenu()
        detailCPUItem = NSMenuItem(title: "CPU: midiendo…", action: nil, keyEquivalent: "")
        detailMemItem = NSMenuItem(title: "RAM: midiendo…", action: nil, keyEquivalent: "")
        menu.addItem(detailCPUItem)
        menu.addItem(detailMemItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir de BetoStats",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func tick() {
        let cpu = cpuReader.read()
        let mem = memoryReader.read()

        let cpuText = cpu.map { String(format: "%3.0f%%", $0.totalUsage * 100) } ?? " --%"
        let memText = mem.map { String(format: "%3.0f%%", $0.fractionUsed * 100) } ?? " --%"

        statusItem.button?.attributedTitle = Self.grid(rows: [("CPU", cpuText), ("MEM", memText)])

        if let cpu {
            detailCPUItem.title = String(format: "CPU: %.1f%% (%d núcleos)", cpu.totalUsage * 100, cpu.perCore.count)
        }
        if let mem {
            let usedGB = mem.usedBytes / 1_073_741_824
            let totalGB = mem.totalBytes / 1_073_741_824
            detailMemItem.title = String(format: "RAM: %.1f / %.0f GB (%.0f%%)", usedGB, totalGB, mem.fractionUsed * 100)
        }
    }

    /// Cuadrícula de dos filas en texto chiquito para el status item.
    /// Cada fila: etiqueta + valor con dígitos monoespaciados, alineado a la derecha.
    static func grid(rows: [(label: String, value: String)]) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 10
        paragraph.maximumLineHeight = 10
        paragraph.alignment = .right

        let labelFont = NSFont.monospacedSystemFont(ofSize: 7, weight: .semibold)
        let valueFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)

        let result = NSMutableAttributedString()
        for (index, row) in rows.enumerated() {
            let line = NSMutableAttributedString()
            line.append(NSAttributedString(string: row.label + " ", attributes: [
                .font: labelFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]))
            line.append(NSAttributedString(string: row.value, attributes: [
                .font: valueFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]))
            if index < rows.count - 1 {
                line.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: paragraph]))
            }
            result.append(line)
        }
        return result
    }
}
