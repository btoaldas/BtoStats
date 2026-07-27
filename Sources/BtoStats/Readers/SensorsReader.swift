import Foundation

/// Temperaturas y ventiladores vía SMC (lectura, sin sudo).
/// Descubrimiento dinámico: enumera las claves reales del equipo y filtra por
/// prefijo + rango físico (las tablas por chip cambian por generación e incluso
/// por dispositivo — política fail-soft de docs/VIABILIDAD.md §2).
final class SensorsReader {
    struct Snapshot {
        let cpuTempAvg: Double?
        let cpuTempMax: Double?
        let gpuTempAvg: Double?
        let fanRPM: [Double]
    }

    private let smc: SMC?
    private var cpuKeys: [String] = []
    private var gpuKeys: [String] = []
    private var fanKeys: [String] = []

    /// Rango físico plausible en °C; fuera de esto es sensor basura.
    private static let plausibleRange = 5.0...120.0

    init() {
        smc = SMC()
        discover()
    }

    private func discover() {
        guard let smc else { return }
        let all = smc.allKeys()
        // Tp* = sensores de cores CPU, Tg* = GPU (M-series, tipo flt).
        cpuKeys = all.filter { $0.hasPrefix("Tp") && smc.keyType($0) == "flt " }
        gpuKeys = all.filter { $0.hasPrefix("Tg") && smc.keyType($0) == "flt " }

        let fanCount = smc.uint("FNum") ?? 0
        fanKeys = (0..<min(fanCount, 8)).map { "F\($0)Ac" }
    }

    var hasSensors: Bool { !(cpuKeys.isEmpty && gpuKeys.isEmpty && fanKeys.isEmpty) }

    func read() -> Snapshot? {
        guard let smc, hasSensors else { return nil }

        let cpuTemps = Self.plausible(cpuKeys.compactMap { smc.float($0).map(Double.init) })
        let gpuTemps = Self.plausible(gpuKeys.compactMap { smc.float($0).map(Double.init) })
        let fans = fanKeys.compactMap { smc.float($0).map(Double.init) }.filter { $0 >= 0 }

        return Snapshot(cpuTempAvg: Self.average(cpuTemps),
                        cpuTempMax: cpuTemps.max(),
                        gpuTempAvg: Self.average(gpuTemps),
                        fanRPM: fans)
    }

    private static func plausible(_ values: [Double]) -> [Double] {
        values.filter { plausibleRange.contains($0) }
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
