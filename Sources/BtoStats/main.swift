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

// Modo verificación de terminación: BtoStats --kill <pid> [--force]
if let killIndex = CommandLine.arguments.firstIndex(of: "--kill"),
   killIndex + 1 < CommandLine.arguments.count,
   let pid = Int32(CommandLine.arguments[killIndex + 1]) {
    let force = CommandLine.arguments.contains("--force")
    let uid = ProcessKiller.ownerUID(of: pid).map(String.init) ?? "?"
    print("pid \(pid) uid \(uid) permitido=\(ProcessKiller.canTerminate(pid: pid))")
    switch ProcessKiller.terminate(pid: pid, force: force) {
    case .requested: print("resultado: señal enviada (force=\(force))")
    case .notPermitted: print("resultado: NO permitido (otro usuario)")
    case .failed(let reason): print("resultado: fallo — \(reason)")
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

// Instancia única: si ya corre otra copia (dev vs .app instalada, o dos .app),
// no arrancar una segunda que duplicaría íconos en la barra.
let runningCopies = NSRunningApplication.runningApplications(
    withBundleIdentifier: "ec.bto.BtoStats")
if runningCopies.count > 1 {
    FileHandle.standardError.write("BtoStats ya está corriendo — saliendo.\n".data(using: .utf8)!)
    exit(0)
}

if CommandLine.arguments.contains("--clusters") {
    let r = CPUReader(); _ = r.read(); Thread.sleep(forTimeInterval: 1)
    if let s = r.read() {
        print("total: \(Int(s.totalUsage*100))%  cores: \(s.perCore.count)")
        for c in s.clusters { print("  \(c.name): \(Int(c.usage*100))%") }
    }
    exit(0)
}

if CommandLine.arguments.contains("--power") {
    let r = PowerReader()
    _ = r.read()
    Thread.sleep(forTimeInterval: 1.0)
    if let p = r.read() {
        func f(_ w: Double?) -> String { w.map { String(format: "%.2f W", $0) } ?? "—" }
        print("CPU: \(f(p.cpuWatts))  GPU: \(f(p.gpuWatts))  ANE: \(f(p.aneWatts))")
    } else { print("IOReport sin datos") }
    exit(0)
}

if CommandLine.arguments.contains("--power-debug") {
    // volcar todos los canales de Energy Model para ver los nombres reales
    let r = PowerReader()
    _ = r.read(); Thread.sleep(forTimeInterval: 1.0); _ = r.read()
    exit(0)
}

if CommandLine.arguments.contains("--bluetooth") {
    let devices = BluetoothReader().read()
    if devices.isEmpty { print("sin dispositivos BT con batería") }
    for d in devices { print("\(d.name): \(d.batteryPercent)%") }
    exit(0)
}

if CommandLine.arguments.contains("--diskio") {
    let r = DiskIOReader()
    _ = r.read() // baseline
    // generar escritura
    let data = Data(repeating: 0, count: 50_000_000)
    try? data.write(to: URL(fileURLWithPath: "/tmp/btostats-iotest"))
    Thread.sleep(forTimeInterval: 2)
    if let s = r.read() {
        print(String(format: "lectura: %.1f MB/s  escritura: %.1f MB/s", s.readBps/1e6, s.writeBps/1e6))
    } else { print("sin datos") }
    try? FileManager.default.removeItem(atPath: "/tmp/btostats-iotest")
    exit(0)
}

if CommandLine.arguments.contains("--battery") {
    if let b = BatteryReader().read() {
        print("carga: \(b.percentage)%  cargando: \(b.isCharging)  restante: \(b.timeRemainingMinutes.map(String.init) ?? "?") min")
        print("salud: \(b.healthPercent)%  ciclos: \(b.cycleCount)  watts: \(b.watts)  temp: \(b.temperatureC.map { String(format: "%.1f", $0) } ?? "?")")
    } else { print("sin batería") }
    exit(0)
}

if CommandLine.arguments.contains("--wifi") {
    if let w = WiFiReader().read() {
        print("SSID: \(w.ssid ?? "?")  banda: \(w.bandGHz) GHz  canal: \(w.channel)")
        print("RSSI: \(w.rssiDBm) dBm (\(w.signalQuality)%)  ruido: \(w.noiseDBm) dBm  tx: \(w.txRateMbps) Mbps")
    } else { print("Wi-Fi no activo") }
    exit(0)
}

if CommandLine.arguments.contains("--system") {
    let sys = SystemReader().read()
    let h = Int(sys.uptimeSeconds) / 3600, m = (Int(sys.uptimeSeconds) % 3600) / 60
    print(String(format: "uptime: %dh %dm", h, m))
    print(String(format: "load avg: %.2f %.2f %.2f", sys.loadAverage.0, sys.loadAverage.1, sys.loadAverage.2))
    print("procesos: \(sys.processCount)")
    print(String(format: "swap: %.2f / %.2f GB", Double(sys.swapUsedBytes)/1e9, Double(sys.swapTotalBytes)/1e9))
    print(String(format: "comprimida: %.2f GB", Double(sys.compressedBytes)/1e9))
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
