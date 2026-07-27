import Foundation

/// Histórico persistente con GESTIÓN DE RECURSOS: retención configurable,
/// tope de tamaño en disco, compactación automática de datos viejos
/// (downsampling) y guard de espacio libre. Nunca crece sin control.
///
/// Formato: archivo binario append-only de muestras de 40 bytes
/// (timestamp + cpu + ram + gpu + temp, todos Double) en
/// ~/Library/Application Support/BtoStats/history.bin
///
/// Presupuesto real: 1 muestra/min = 57 KB/día. Con compactación a 1/hora
/// tras la ventana fina, un año ocupa ~1 MB. OFF por defecto.
final class HistoryStore {
    struct Sample {
        let timestamp: Double  // epoch seconds
        let cpu: Double        // 0-1
        let ram: Double        // 0-1
        let gpu: Double        // 0-100
        let temp: Double       // °C (0 si no hay)
    }

    /// Política de recursos — toda parametrizable desde Preferencias.
    struct Policy {
        /// Días de retención (0 = sin límite de tiempo, solo por tamaño).
        var retentionDays: Int
        /// Tope duro del archivo en MB: al superarlo se descartan las más viejas.
        var maxSizeMB: Double
        /// Muestras más viejas que esto se compactan a 1 por hora.
        var fineDetailDays: Int
        /// No escribir si el disco tiene menos de este espacio libre (GB).
        var minFreeDiskGB: Double

        static let `default` = Policy(retentionDays: 90, maxSizeMB: 20,
                                      fineDetailDays: 7, minFreeDiskGB: 2)
    }

    private static let stride = 5 * MemoryLayout<Double>.size // 40 bytes
    private let url: URL
    private var lastWrite: Double = 0
    private var lastMaintenance: Double = 0
    private var diskFullSkip = false

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BtoStats", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("history.bin")
    }

    var fileURL: URL { url }

    /// Tamaño actual en disco (bytes) — para mostrarlo en Preferencias.
    var sizeBytes: UInt64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) as? UInt64 ?? 0
    }

    var sampleCount: Int { Int(sizeBytes) / Self.stride }

    /// Estimación de cuánto ocupará al año con la política actual.
    static func projectedYearlyBytes(_ policy: Policy) -> UInt64 {
        let fineSamples = Double(policy.fineDetailDays) * 24 * 60          // 1/min
        let coarseDays = max(Double(policy.retentionDays) - Double(policy.fineDetailDays), 0)
        let coarseSamples = coarseDays * 24                                 // 1/hora
        return UInt64((fineSamples + coarseSamples) * Double(Self.stride))
    }

    // MARK: - Escritura

    /// Registra una muestra si pasó ≥1 min desde la última (llamar cada tick).
    /// Se salta silenciosamente si el disco está bajo de espacio.
    func recordIfDue(cpu: Double, ram: Double, gpu: Double, temp: Double, now: Double) {
        guard AppConfig.shared.historyEnabled else { return }
        guard now - lastWrite >= 60 else { return }

        let policy = AppConfig.shared.historyPolicy
        guard hasFreeSpace(policy: policy) else {
            diskFullSkip = true
            return
        }
        diskFullSkip = false
        lastWrite = now

        var doubles = [now, cpu, ram, gpu, temp]
        let data = Data(bytes: &doubles, count: Self.stride)
        // API lanzable (no las deprecadas seekToEndOfFile/write, que levantan
        // NSException no atrapable y abortarían la app con el disco lleno).
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url)
        }

        // Mantenimiento (compactar + recortar) cada 6 h, no en cada escritura.
        if now - lastMaintenance >= 6 * 3600 {
            lastMaintenance = now
            maintain(now: now)
        }
    }

    /// ¿Hay espacio libre suficiente para seguir escribiendo?
    private func hasFreeSpace(policy: Policy) -> Bool {
        guard let values = try? url.deletingLastPathComponent()
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else { return true }
        return Double(available) / 1e9 >= policy.minFreeDiskGB
    }

    var isPausedForDiskSpace: Bool { diskFullSkip }

    // MARK: - Lectura

    /// Muestras de los últimos `seconds` segundos (para la gráfica).
    func load(sinceSeconds seconds: Double, now: Double) -> [Sample] {
        allSamples().filter { now - $0.timestamp <= seconds }
    }

    private func allSamples() -> [Sample] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let count = data.count / Self.stride
        guard count > 0 else { return [] }
        var samples: [Sample] = []
        samples.reserveCapacity(count)
        data.withUnsafeBytes { raw in
            let doubles = raw.bindMemory(to: Double.self)
            for i in 0..<count {
                let base = i * 5
                samples.append(Sample(timestamp: doubles[base], cpu: doubles[base+1],
                                      ram: doubles[base+2], gpu: doubles[base+3],
                                      temp: doubles[base+4]))
            }
        }
        return samples
    }

    // MARK: - Mantenimiento (compactar + recortar)

    /// Aplica la política: compacta lo viejo a 1 muestra/hora, borra lo que
    /// excede la retención y recorta si el archivo supera el tope de tamaño.
    func maintain(now: Double) {
        let policy = AppConfig.shared.historyPolicy
        var samples = allSamples()
        guard !samples.isEmpty else { return }
        let originalCount = samples.count

        // 1. Retención por tiempo.
        if policy.retentionDays > 0 {
            let cutoff = now - Double(policy.retentionDays) * 86400
            samples.removeAll { $0.timestamp < cutoff }
        }

        // 2. Compactación: lo más viejo que fineDetailDays → 1 muestra/hora
        //    (promedio del bucket). Reduce ~60× el espacio sin perder la forma.
        let fineCutoff = now - Double(policy.fineDetailDays) * 86400
        let old = samples.filter { $0.timestamp < fineCutoff }
        let recent = samples.filter { $0.timestamp >= fineCutoff }
        samples = Self.downsampleHourly(old) + recent

        // 3. Tope de tamaño: si aún excede, quedarse con las más recientes.
        let maxSamples = Int(policy.maxSizeMB * 1e6) / Self.stride
        if samples.count > maxSamples {
            samples = Array(samples.suffix(maxSamples))
        }

        guard samples.count != originalCount else { return }
        write(samples)
    }

    /// Promedia las muestras en buckets de 1 hora.
    private static func downsampleHourly(_ samples: [Sample]) -> [Sample] {
        guard !samples.isEmpty else { return [] }
        var buckets: [Double: [Sample]] = [:]
        for s in samples {
            let hour = (s.timestamp / 3600).rounded(.down) * 3600
            buckets[hour, default: []].append(s)
        }
        return buckets.keys.sorted().map { hour in
            let group = buckets[hour]!
            let n = Double(group.count)
            return Sample(timestamp: hour,
                          cpu: group.reduce(0) { $0 + $1.cpu } / n,
                          ram: group.reduce(0) { $0 + $1.ram } / n,
                          gpu: group.reduce(0) { $0 + $1.gpu } / n,
                          temp: group.reduce(0) { $0 + $1.temp } / n)
        }
    }

    private func write(_ samples: [Sample]) {
        var data = Data(capacity: samples.count * Self.stride)
        for s in samples.sorted(by: { $0.timestamp < $1.timestamp }) {
            var doubles = [s.timestamp, s.cpu, s.ram, s.gpu, s.temp]
            data.append(Data(bytes: &doubles, count: Self.stride))
        }
        try? data.write(to: url, options: .atomic)
    }

    /// Borra todo el histórico (botón en Preferencias).
    func deleteAll() {
        try? FileManager.default.removeItem(at: url)
        lastWrite = 0
    }
}
