import Foundation
import IOKit

/// I/O de disco en bytes/s vía IOKit IOBlockStorageDriver (público, sin sudo).
/// Suma los bytes leídos/escritos de todos los drivers de bloque; delta entre
/// lecturas. La primera llamada devuelve nil.
final class DiskIOReader {
    struct Snapshot {
        let readBps: Double
        let writeBps: Double
    }

    private var previous: (read: UInt64, write: UInt64, uptime: TimeInterval)?

    func read() -> Snapshot? {
        guard let totals = Self.totals() else { return nil }
        let now = ProcessInfo.processInfo.systemUptime
        defer { previous = (totals.read, totals.write, now) }
        guard let previous, now > previous.uptime,
              totals.read >= previous.read, totals.write >= previous.write else { return nil }
        let dt = now - previous.uptime
        return Snapshot(readBps: Double(totals.read - previous.read) / dt,
                        writeBps: Double(totals.write - previous.write) / dt)
    }

    private static func totals() -> (read: UInt64, write: UInt64)? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOBlockStorageDriver"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0, write: UInt64 = 0, found = false
        var drive = IOIteratorNext(iterator)
        while drive != 0 {
            defer { IOObjectRelease(drive); drive = IOIteratorNext(iterator) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(drive, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let stats = dict["Statistics"] as? [String: Any] else { continue }
            read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            write += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            found = true
        }
        return found ? (read, write) : nil
    }
}
