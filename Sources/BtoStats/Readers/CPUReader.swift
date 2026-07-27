import Foundation

/// Lee uso de CPU del sistema vía host_processor_info (sin sudo).
/// Calcula el delta de ticks entre lecturas: la primera llamada devuelve nil.
final class CPUReader {
    /// mach_host_self() incrementa una referencia al port en CADA llamada:
    /// obtenerlo una sola vez evita la fuga acumulativa.
    private static let host = mach_host_self()
    private var previousTicks: [UInt32] = []

    struct Snapshot {
        let totalUsage: Double        // 0.0 – 1.0
        let perCore: [Double]         // 0.0 – 1.0 por núcleo
        let clusters: [(name: String, usage: Double)] // promedio por clúster
    }

    /// Topología de clústeres (nombre + nº de cores), leída una vez.
    /// En M5 Pro: "Super" (6) + "Performance" (12).
    private static let topology: [(name: String, cores: Int)] = {
        func sysctlInt(_ name: String) -> Int {
            var value = 0; var size = MemoryLayout<Int>.size
            return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : 0
        }
        func sysctlString(_ name: String) -> String {
            var size = 0
            guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
            var buf = [CChar](repeating: 0, count: size)
            sysctlbyname(name, &buf, &size, nil, 0)
            return String(cString: buf)
        }
        let levels = sysctlInt("hw.nperflevels")
        guard levels > 0 else { return [] }
        return (0..<levels).map { i in
            (name: sysctlString("hw.perflevel\(i).name"),
             cores: sysctlInt("hw.perflevel\(i).logicalcpu"))
        }
    }()

    func read() -> Snapshot? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(Self.host,
                                         PROCESSOR_CPU_LOAD_INFO,
                                         &cpuCount,
                                         &info,
                                         &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), size)
        }

        let states = Int(CPU_STATE_MAX)
        var current = [UInt32](repeating: 0, count: Int(cpuCount) * states)
        for i in 0..<current.count {
            current[i] = UInt32(bitPattern: info[i])
        }

        guard previousTicks.count == current.count else {
            previousTicks = current
            return nil
        }

        var perCore: [Double] = []
        var busyTotal: Double = 0
        var allTotal: Double = 0

        for core in 0..<Int(cpuCount) {
            let base = core * states
            let user = Double(current[base + Int(CPU_STATE_USER)] &- previousTicks[base + Int(CPU_STATE_USER)])
            let system = Double(current[base + Int(CPU_STATE_SYSTEM)] &- previousTicks[base + Int(CPU_STATE_SYSTEM)])
            let nice = Double(current[base + Int(CPU_STATE_NICE)] &- previousTicks[base + Int(CPU_STATE_NICE)])
            let idle = Double(current[base + Int(CPU_STATE_IDLE)] &- previousTicks[base + Int(CPU_STATE_IDLE)])

            let busy = user + system + nice
            let total = busy + idle
            perCore.append(total > 0 ? busy / total : 0)
            busyTotal += busy
            allTotal += total
        }

        previousTicks = current

        // Agrupar por clúster: el nivel de mayor rendimiento ocupa los índices
        // menores (convención M-series verificada).
        var clusters: [(name: String, usage: Double)] = []
        var offset = 0
        for level in Self.topology where level.cores > 0 {
            let slice = perCore[offset..<min(offset + level.cores, perCore.count)]
            if !slice.isEmpty {
                clusters.append((level.name, slice.reduce(0, +) / Double(slice.count)))
            }
            offset += level.cores
        }

        return Snapshot(totalUsage: allTotal > 0 ? busyTotal / allTotal : 0,
                        perCore: perCore, clusters: clusters)
    }
}
