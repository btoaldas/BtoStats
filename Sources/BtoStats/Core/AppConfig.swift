import Foundation

/// Identificador de cada métrica mostrable en la cuadrícula.
/// Las celdas activas se emparejan de a dos por columna, en el orden configurado.
enum MetricID: String, CaseIterable, Identifiable {
    case cpu, memory, gpu, temperature, network, diskFree, diskTotal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cpu: return "CPU %"
        case .memory: return "RAM %"
        case .gpu: return "GPU %"
        case .temperature: return "Temperatura CPU"
        case .network: return "Red ↑↓ (bloque)"
        case .diskFree: return "Disco disponible"
        case .diskTotal: return "Disco total"
        }
    }

    var gridLabel: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "MEM"
        case .gpu: return "GPU"
        case .temperature: return "TMP"
        case .network: return "↑↓"
        case .diskFree: return "D"
        case .diskTotal: return " "
        }
    }
}

/// Configuración persistente (UserDefaults con suite propia — la app corre
/// también como binario suelto sin bundle). Todo parametrizable.
final class AppConfig {
    static let shared = AppConfig()
    static let changedNotification = Notification.Name("BtoStatsConfigChanged")

    private let defaults = UserDefaults(suiteName: "ec.bto.BtoStats") ?? .standard

    private enum Key {
        static let metricOrder = "metricOrder"
        static let disabledMetrics = "disabledMetrics"
        static let fastInterval = "fastInterval"
        static let gridRows = "gridRows"
    }

    /// Migración de configs previas: networkUp/networkDown eran métricas sueltas
    /// y ahora son el bloque único "network".
    private static func migrate(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        return raw.map { $0 == "networkUp" || $0 == "networkDown" ? "network" : $0 }
                  .filter { seen.insert($0).inserted }
    }

    /// Orden de las celdas; las no listadas (métricas nuevas tras actualizar) van al final.
    var metricOrder: [MetricID] {
        get {
            let stored = Self.migrate(defaults.stringArray(forKey: Key.metricOrder) ?? [])
                .compactMap(MetricID.init(rawValue:))
            let missing = MetricID.allCases.filter { !stored.contains($0) }
            return stored + missing
        }
        set { defaults.set(newValue.map(\.rawValue), forKey: Key.metricOrder) }
    }

    var disabledMetrics: Set<MetricID> {
        get {
            Set(Self.migrate(defaults.stringArray(forKey: Key.disabledMetrics) ?? [])
                .compactMap(MetricID.init(rawValue:)))
        }
        set { defaults.set(newValue.map(\.rawValue).sorted(), forKey: Key.disabledMetrics) }
    }

    var visibleMetrics: [MetricID] {
        metricOrder.filter { !disabledMetrics.contains($0) }
    }

    /// Cadencia del tick rápido en segundos (1–5).
    var fastInterval: Double {
        get {
            let value = defaults.double(forKey: Key.fastInterval)
            return value == 0 ? 1.0 : min(max(value, 1.0), 5.0)
        }
        set { defaults.set(min(max(newValue, 1.0), 5.0), forKey: Key.fastInterval) }
    }

    /// Filas de la cuadrícula (2 por defecto; 3 con letra más pequeña).
    var gridRows: Int {
        get {
            let value = defaults.integer(forKey: Key.gridRows)
            return value == 0 ? 2 : min(max(value, 2), 3)
        }
        set { defaults.set(min(max(newValue, 2), 3), forKey: Key.gridRows) }
    }

    func setEnabled(_ metric: MetricID, _ enabled: Bool) {
        var set = disabledMetrics
        if enabled { set.remove(metric) } else { set.insert(metric) }
        disabledMetrics = set
    }

    func notifyChanged() {
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
    }
}
