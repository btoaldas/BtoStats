import AppKit

// Modo verificación: imprime muestras de todos los readers y sale.
// Uso: BetoStats --sample [segundos]
if CommandLine.arguments.contains("--sample") {
    let seconds = CommandLine.arguments.last.flatMap(Int.init) ?? 3
    let cpu = CPUReader()
    let memory = MemoryReader()
    let network = NetworkReader()
    let disk = DiskReader()

    for tick in 0...max(seconds, 1) {
        let c = cpu.read()
        let m = memory.read()
        let n = network.read()
        if tick > 0 {
            let cpuText = c.map { String(format: "%.1f%%", $0.totalUsage * 100) } ?? "--"
            let memText = m.map { String(format: "%.2f GB usados de %.0f GB (%.1f%%)",
                                         $0.usedBytes / 1e9, $0.totalBytes / 1e9,
                                         $0.fractionUsed * 100) } ?? "--"
            let netText = n.map { String(format: "↑ %.0f B/s  ↓ %.0f B/s  (totales: out %llu, in %llu)",
                                         $0.uploadBps, $0.downloadBps,
                                         $0.totalUploadBytes, $0.totalDownloadBytes) } ?? "--"
            print("t\(tick)  CPU \(cpuText)  |  RAM \(memText)  |  NET \(netText)")
        }
        if tick < max(seconds, 1) { Thread.sleep(forTimeInterval: 1.0) }
    }
    if let d = disk.read() {
        print(String(format: "DISK  total %llu bytes (%.1f GB)  libre_real %llu (%.1f GB)  disponible_finder %llu (%.1f GB)",
                     d.totalBytes, Double(d.totalBytes) / 1e9,
                     d.freeBytes, Double(d.freeBytes) / 1e9,
                     d.availableBytes, Double(d.availableBytes) / 1e9))
    } else {
        print("DISK  ERROR")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
