import Foundation

/// Lee estado de memoria vía host_statistics64 (sin sudo).
/// "Usada" se aproxima al criterio de Activity Monitor:
/// app anónima (internal - purgeable) + wired + comprimida.
final class MemoryReader {
    let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)

    struct Snapshot {
        let usedBytes: Double
        let totalBytes: Double
        var fractionUsed: Double { totalBytes > 0 ? usedBytes / totalBytes : 0 }
    }

    func read() -> Snapshot? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageSize = Double(vm_kernel_page_size)
        let anonymous = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        let used = (anonymous + Double(stats.wire_count) + Double(stats.compressor_page_count)) * pageSize
        return Snapshot(usedBytes: max(used, 0), totalBytes: totalBytes)
    }
}
