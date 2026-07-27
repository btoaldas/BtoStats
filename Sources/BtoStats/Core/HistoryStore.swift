import Foundation

/// Histórico persistente en disco para gráficas de día/semana/mes.
/// Archivo binario append-only de muestras (timestamp + 4 métricas), en
/// ~/Library/Application Support/BtoStats/history.bin. Una muestra por minuto,
/// retención 31 días. OFF por defecto (opt-in): no escribe nada si está apagado.
final class HistoryStore {
    struct Sample {
        let timestamp: Double  // epoch seconds
        let cpu: Double        // 0-1
        let ram: Double        // 0-1
        let gpu: Double        // 0-100
        let temp: Double       // °C (0 si no hay)
    }

    private static let stride = 5 * MemoryLayout<Double>.size // 40 bytes
    private let url: URL
    private var lastWrite: Double = 0
    private let retention: Double = 31 * 86400

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BtoStats", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("history.bin")
    }

    /// Registra una muestra si pasó ≥1 min desde la última (llamar cada tick).
    func recordIfDue(cpu: Double, ram: Double, gpu: Double, temp: Double, now: Double) {
        guard AppConfig.shared.historyEnabled else { return }
        guard now - lastWrite >= 60 else { return }
        lastWrite = now
        var doubles = [now, cpu, ram, gpu, temp]
        let data = Data(bytes: &doubles, count: Self.stride)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    /// Muestras de los últimos `seconds` segundos (para la gráfica).
    func load(sinceSeconds seconds: Double, now: Double) -> [Sample] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let count = data.count / Self.stride
        var samples: [Sample] = []
        samples.reserveCapacity(count)
        data.withUnsafeBytes { raw in
            let doubles = raw.bindMemory(to: Double.self)
            for i in 0..<count {
                let base = i * 5
                let ts = doubles[base]
                if now - ts <= seconds {
                    samples.append(Sample(timestamp: ts, cpu: doubles[base+1],
                                          ram: doubles[base+2], gpu: doubles[base+3],
                                          temp: doubles[base+4]))
                }
            }
        }
        return samples
    }

    /// Recorta muestras más viejas que la retención (llamar de vez en cuando).
    func prune(now: Double) {
        guard let data = try? Data(contentsOf: url), data.count > Self.stride else { return }
        let cutoff = now - retention
        var kept = Data()
        data.withUnsafeBytes { raw in
            let doubles = raw.bindMemory(to: Double.self)
            for i in 0..<(data.count / Self.stride) where doubles[i*5] >= cutoff {
                kept.append(data.subdata(in: (i*Self.stride)..<((i+1)*Self.stride)))
            }
        }
        if kept.count < data.count { try? kept.write(to: url) }
    }
}
