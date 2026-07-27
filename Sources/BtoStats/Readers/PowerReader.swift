import Foundation
import CIOReport

/// Potencia en watts de CPU, GPU y ANE (Neural Engine) vía IOReport privado
/// (sin sudo). Suscribe el grupo "Energy Model" y mide el delta de energía
/// entre dos muestras: watts = ΔenergíaJ / Δt. Fail-soft: si algún canal no
/// existe, esa métrica queda nil. (Solo distribución local — API privada.)
final class PowerReader {
    struct Snapshot {
        let cpuWatts: Double?
        let gpuWatts: Double?
        let aneWatts: Double?
    }

    private var subscription: IOReportSubscriptionRef?
    private var subscribedChannels: CFMutableDictionary?
    private var previousSample: CFDictionary?
    private var previousTime: TimeInterval = 0

    init() {
        guard let channels = IOReportCopyChannelsInGroup("Energy Model" as CFString, nil, 0, 0, 0)?
                .takeRetainedValue() else { return }
        let mutable = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, channels)
        var subbed: Unmanaged<CFMutableDictionary>?
        let sub = IOReportCreateSubscription(nil, mutable, &subbed, 0, nil)
        subscription = sub
        subscribedChannels = subbed?.takeRetainedValue()
    }

    deinit {
        // IOReportSubscriptionRef llega como OpaquePointer (no es tipo CF que
        // ARC gestione): liberar explícitamente al destruir el reader.
        if let subscription {
            BtoReleaseIOReportSubscription(subscription)
        }
    }

    func read() -> Snapshot? {
        guard let subscription, let subscribedChannels else { return nil }
        guard let sample = IOReportCreateSamples(subscription, subscribedChannels, nil)?
                .takeRetainedValue() else { return nil }
        let now = ProcessInfo.processInfo.systemUptime
        defer { previousSample = sample; previousTime = now }

        guard let previousSample, now > previousTime else { return nil }
        let dt = now - previousTime
        guard let delta = IOReportCreateSamplesDelta(previousSample, sample, nil)?
                .takeRetainedValue() else { return nil }

        var energy: [String: Double] = [:] // joules por canal
        IOReportIterate(delta) { channel in
            guard let nameRef = IOReportChannelGetChannelName(channel) else { return 0 }
            let name = nameRef.takeUnretainedValue() as String
            let unit = (IOReportChannelGetUnitLabel(channel)?.takeUnretainedValue() as String?) ?? ""
            let raw = Double(IOReportSimpleGetIntegerValue(channel, 0))
            energy[name] = raw * Self.toJoules(unit: unit)
            return 0
        }

        func watts(_ keys: [String]) -> Double? {
            let total = keys.compactMap { energy[$0] }.reduce(0, +)
            guard keys.contains(where: { energy[$0] != nil }) else { return nil }
            let w = total / dt
            // descartar valores absurdos (unidad mal interpretada)
            return (w.isFinite && w >= 0 && w < 500) ? w : nil
        }

        return Snapshot(cpuWatts: watts(["CPU Energy", "ECPU", "PCPU"]),
                        gpuWatts: watts(["GPU Energy", "GPU"]),
                        aneWatts: watts(["ANE Energy", "ANE", "ANE0"]))
    }

    /// Unidad de energía de IOReport → factor a joules.
    private static func toJoules(unit: String) -> Double {
        switch unit.lowercased() {
        case "mj": return 1e-3
        case "uj", "µj": return 1e-6
        case "nj": return 1e-9
        default: return 1e-3 // Energy Model de Apple Silicon reporta mJ
        }
    }
}
