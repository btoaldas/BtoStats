import Foundation

/// Top procesos por CPU, RAM y red. Spawnea binarios del sistema que llevan
/// las entitlements necesarias en su propia firma (ps/top/nettop ven procesos
/// de todos los usuarios sin sudo — docs/VIABILIDAD.md §4).
/// COSTO: top -l 1 ~750 ms de CPU → llamar solo con el panel abierto, cada ~5 s,
/// nunca en el tick rápido. nettop SIEMPRE con -n (sin él bloquea ~5 s en DNS).
final class ProcessReader {
    struct ProcessSample: Identifiable {
        let pid: Int32
        let name: String
        let value: Double // %CPU, bytes de RAM, o B/s de red según el top
        var id: Int32 { pid }
    }

    struct Snapshot {
        let topCPU: [ProcessSample]
        let topRAM: [ProcessSample]
        let topNetwork: [ProcessSample]
        let totalCPUPercent: Double // suma de pcpu de TODOS los procesos (100 = 1 core)
    }

    private var previousNet: [Int32: (inBytes: UInt64, outBytes: UInt64, name: String)] = [:]
    private var previousNetUptime: TimeInterval?

    /// Descarta la línea base de red por proceso (llamar al abrir el panel:
    /// un delta contra una muestra de hace horas daría tasas sin sentido).
    func resetNetworkBaseline() {
        previousNet = [:]
        previousNetUptime = nil
    }

    func read(limit: Int = 8) -> Snapshot {
        let cpu = topCPU(limit: limit)
        return Snapshot(topCPU: cpu.samples,
                        topRAM: topRAM(limit: limit),
                        topNetwork: topNetwork(limit: limit),
                        totalCPUPercent: cpu.total)
    }

    // MARK: - CPU (ps, ~30 ms)

    private func topCPU(limit: Int) -> (samples: [ProcessSample], total: Double) {
        guard let output = Self.run("/bin/ps", ["-Aceo", "pid,ppid,pcpu,comm", "-r"]) else { return ([], 0) }
        let ownPid = ProcessInfo.processInfo.processIdentifier
        var total = 0.0
        var samples: [ProcessSample] = []
        for line in output.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]),
                  let cpu = Double(parts[2]) else { continue }
            // bajo carga nuestro top/nettop del ciclo anterior puede seguir vivo
            // durante este ps: los hijos propios no son "top procesos" del usuario
            guard ppid != ownPid else { continue }
            total += cpu
            if samples.count < limit {
                samples.append(ProcessSample(pid: pid, name: String(parts[3]), value: cpu))
            }
        }
        return (samples, total)
    }

    // MARK: - RAM (top, ~750 ms — solo panel abierto)

    private func topRAM(limit: Int) -> [ProcessSample] {
        guard let output = Self.run("/usr/bin/top",
                                    ["-l", "1", "-o", "mem", "-n", "\(limit)",
                                     "-stats", "pid,command,mem"]) else { return [] }
        var rows: [ProcessSample] = []
        var inTable = false
        for line in output.split(separator: "\n") {
            if line.hasPrefix("PID") { inTable = true; continue }
            guard inTable else { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3,
                  let pid = Int32(parts[0]),
                  let bytes = Self.parseMemory(String(parts[parts.count - 1])) else { continue }
            let name = parts[1..<(parts.count - 1)].joined(separator: " ")
            rows.append(ProcessSample(pid: pid, name: name, value: Double(bytes)))
        }
        return Array(rows.prefix(limit))
    }

    /// "6413M", "1G", "903M+", "512K-" → bytes.
    private static func parseMemory(_ text: String) -> UInt64? {
        var cleaned = text
        while let last = cleaned.last, "+-".contains(last) { cleaned.removeLast() }
        guard let unit = cleaned.last else { return nil }
        let number = String(cleaned.dropLast())
        guard let value = Double(number), value.isFinite, value >= 0 else { return nil }
        let multiplier: Double
        switch unit {
        case "K": multiplier = 1024
        case "M": multiplier = 1024 * 1024
        case "G": multiplier = 1024 * 1024 * 1024
        case "B": multiplier = 1
        default: return UInt64(exactly: (Double(cleaned) ?? -1).rounded())
        }
        return UInt64(exactly: (value * multiplier).rounded())
    }

    // MARK: - Red por proceso (nettop -n, ~17 ms; B/s por deltas)

    private func topNetwork(limit: Int) -> [ProcessSample] {
        guard let output = Self.run("/usr/bin/nettop",
                                    ["-P", "-x", "-L", "1", "-n",
                                     "-J", "bytes_in,bytes_out"]) else { return [] }
        let now = ProcessInfo.processInfo.systemUptime
        var current: [Int32: (inBytes: UInt64, outBytes: UInt64, name: String)] = [:]

        for line in output.split(separator: "\n").dropFirst() {
            // formato: nombre.pid,bytes_in,bytes_out, — el nombre puede traer
            // comas: los números se toman desde el FINAL y el resto es nombre
            var fields = line.split(separator: ",", omittingEmptySubsequences: false)
            if fields.last?.isEmpty == true { fields.removeLast() }
            guard fields.count >= 3,
                  let outBytes = UInt64(fields.removeLast()),
                  let inBytes = UInt64(fields.removeLast()) else { continue }
            let identifier = fields.joined(separator: ",")
            guard let dot = identifier.lastIndex(of: "."),
                  let pid = Int32(identifier[identifier.index(after: dot)...]) else { continue }
            current[pid] = (inBytes, outBytes, String(identifier[..<dot]))
        }

        defer {
            previousNet = current
            previousNetUptime = now
        }
        guard let previousUptime = previousNetUptime, now > previousUptime else { return [] }
        let dt = now - previousUptime

        let rates: [ProcessSample] = current.compactMap { pid, sample in
            guard let previous = previousNet[pid],
                  // nettop acumula sobre sockets VIVOS: al cerrarse conexiones el
                  // total puede bajar — un delta negativo no es tráfico, se descarta
                  sample.inBytes >= previous.inBytes,
                  sample.outBytes >= previous.outBytes else { return nil }
            let delta = (sample.inBytes - previous.inBytes) + (sample.outBytes - previous.outBytes)
            guard delta > 0 else { return nil }
            return ProcessSample(pid: pid, name: sample.name, value: Double(delta) / dt)
        }
        return Array(rates.sorted { $0.value > $1.value }.prefix(limit))
    }

    // MARK: - Spawn

    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        // stderr a /dev/null: un Pipe sin drenar se llena (64 KB) y bloquea
        // al hijo → deadlock permanente de la cola de muestreo
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // red de seguridad: ningún muestreo debe colgar la cola para siempre
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 10, execute: watchdog)
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return String(data: data, encoding: .utf8)
    }
}
