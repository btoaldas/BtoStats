import Foundation

/// Disco del volumen raíz: total, libre crudo (statfs) y disponible estilo
/// Finder (incluye purgeable de APFS). Cadencia lenta — el espacio no cambia
/// por segundo.
final class DiskReader {
    struct Snapshot {
        let totalBytes: UInt64
        let freeBytes: UInt64        // f_bavail: libre real para el usuario
        let availableBytes: UInt64   // estilo Finder: incluye purgeable
        var usedBytes: UInt64 { totalBytes > freeBytes ? totalBytes - freeBytes : 0 }
    }

    func read() -> Snapshot? {
        var stat = statfs()
        guard statfs("/", &stat) == 0 else { return nil }
        let blockSize = UInt64(stat.f_bsize)
        let total = stat.f_blocks * blockSize
        let free = stat.f_bavail * blockSize

        var available = free
        if let values = try? URL(fileURLWithPath: "/").resourceValues(
               forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let important = values.volumeAvailableCapacityForImportantUsage,
           important > 0 {
            available = UInt64(important)
        }
        return Snapshot(totalBytes: total, freeBytes: free, availableBytes: available)
    }
}
