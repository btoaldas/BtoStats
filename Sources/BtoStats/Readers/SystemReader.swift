import Foundation

/// Datos "avanzados" del sistema vía sysctl (sin privilegios, baratos).
/// Uptime, load average, nº de procesos/hilos, swap y memoria comprimida.
final class SystemReader {
    struct Snapshot {
        let uptimeSeconds: Double
        let loadAverage: (Double, Double, Double) // 1, 5, 15 min
        let processCount: Int
        let swapUsedBytes: UInt64
        let swapTotalBytes: UInt64
        let compressedBytes: UInt64
    }

    func read() -> Snapshot {
        Snapshot(uptimeSeconds: uptime(),
                 loadAverage: loadAverage(),
                 processCount: processCount(),
                 swapUsedBytes: swap().used,
                 swapTotalBytes: swap().total,
                 compressedBytes: compressed())
    }

    private func uptime() -> Double {
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &boot, &size, nil, 0) == 0, boot.tv_sec != 0 else {
            return ProcessInfo.processInfo.systemUptime
        }
        return Date().timeIntervalSince1970 - Double(boot.tv_sec)
    }

    private func loadAverage() -> (Double, Double, Double) {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) == 3 else { return (0, 0, 0) }
        return (loads[0], loads[1], loads[2])
    }

    private func processCount() -> Int {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var length = 0
        guard sysctl(&mib, 4, nil, &length, nil, 0) == 0 else { return 0 }
        return length / MemoryLayout<kinfo_proc>.stride
    }

    private func swap() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        var mib: [Int32] = [CTL_VM, VM_SWAPUSAGE]
        guard sysctl(&mib, 2, &usage, &size, nil, 0) == 0 else { return (0, 0) }
        return (usage.xsu_used, usage.xsu_total)
    }

    private func compressed() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(stats.compressor_page_count) * UInt64(vm_kernel_page_size)
    }
}
