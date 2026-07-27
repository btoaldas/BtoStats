import AppKit

// Modo verificación: imprime muestras de todos los readers y sale.
// Uso: BtoStats --sample [segundos]
if CommandLine.arguments.contains("--sample") {
    let seconds = CommandLine.arguments.last.flatMap(Int.init) ?? 3
    let cpu = CPUReader()
    let memory = MemoryReader()
    let network = NetworkReader()
    let disk = DiskReader()
    let gpu = GPUReader()
    let sensors = SensorsReader()

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
            let gpuText = gpu.read().map { String(format: "%.1f%%", $0.utilization) } ?? "--"
            var sensorText = "--"
            if let sn = sensors.read() {
                let cpuT = sn.cpuTempAvg.map { String(format: "cpu %.1f°C (max %.1f°C)", $0, sn.cpuTempMax ?? $0) } ?? "cpu --"
                let gpuT = sn.gpuTempAvg.map { String(format: "gpu %.1f°C", $0) } ?? "gpu --"
                let fans = sn.fanRPM.map { String(format: "%.0f", $0) }.joined(separator: "/")
                sensorText = "\(cpuT)  \(gpuT)  fans \(fans) rpm"
            }
            print("t\(tick)  CPU \(cpuText)  |  RAM \(memText)  |  NET \(netText)")
            print("      GPU \(gpuText)  |  SENS \(sensorText)")
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

// Modo verificación de top procesos: BtoStats --top
if CommandLine.arguments.contains("--top") {
    let reader = ProcessReader()
    _ = reader.read() // baseline para los deltas de red
    Thread.sleep(forTimeInterval: 3.0)
    let snapshot = reader.read()
    print("TOP CPU:")
    for p in snapshot.topCPU { print(String(format: "  %6d  %5.1f%%  %@", p.pid, p.value, p.name)) }
    print("TOP RAM:")
    for p in snapshot.topRAM { print(String(format: "  %6d  %8.0f MB  %@", p.pid, p.value / 1048576, p.name)) }
    print("TOP RED (B/s, delta 3 s):")
    for p in snapshot.topNetwork { print(String(format: "  %6d  %10.0f  %@", p.pid, p.value, p.name)) }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
