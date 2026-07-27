import Foundation
import IOKit

/// GPU % vía IOKit público: IOAccelerator → PerformanceStatistics
/// ("Device Utilization %", mismo dato que Activity Monitor).
/// Claves no documentadas pero estables ~10 años; fail-soft si faltan.
/// El valor crudo se actualiza sub-segundo y puede dar 0 transitorio bajo
/// carga → EMA para suavizar (docs/VIABILIDAD.md §3).
final class GPUReader {
    struct Snapshot {
        let utilization: Double        // 0-100, suavizada
        let usedMemoryBytes: UInt64?
        let lastSubmitterName: String? // último proceso que envió trabajo a la GPU
    }

    private var service: io_service_t = 0
    private var ema: Double?

    init() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iterator) == kIOReturnSuccess else { return }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if Self.performanceStatistics(of: entry) != nil {
                service = entry // se retiene para releer propiedades por tick
                return
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
    }

    deinit {
        if service != 0 { IOObjectRelease(service) }
    }

    func read() -> Snapshot? {
        guard service != 0,
              let stats = Self.performanceStatistics(of: service) else { return nil }

        guard let raw = (stats["Device Utilization %"] as? NSNumber)?.doubleValue
                ?? (stats["GPU Activity(%)"] as? NSNumber)?.doubleValue else { return nil }

        let clamped = min(max(raw, 0), 100)
        let smoothed = ema.map { $0 * 0.6 + clamped * 0.4 } ?? clamped
        ema = smoothed

        let memory = (stats["In use system memory"] as? NSNumber)?.uint64Value
        return Snapshot(utilization: smoothed,
                        usedMemoryBytes: memory,
                        lastSubmitterName: lastSubmitterName())
    }

    /// AGCInfo.fLastSubmissionPID: no hay GPU %-por-proceso sin sudo en macOS;
    /// esto al menos identifica al último proceso que mandó trabajo al driver.
    private func lastSubmitterName() -> String? {
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = properties?.takeRetainedValue() as? [String: Any],
              let agc = dict["AGCInfo"] as? [String: Any],
              let pid = (agc["fLastSubmissionPID"] as? NSNumber)?.int32Value, pid > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: 1024)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func performanceStatistics(of entry: io_registry_entry_t) -> [String: Any]? {
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = properties?.takeRetainedValue() as? [String: Any] else { return nil }
        return dict["PerformanceStatistics"] as? [String: Any]
    }
}
