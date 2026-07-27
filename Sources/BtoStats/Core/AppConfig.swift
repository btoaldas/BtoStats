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
        case .diskFree: return "L"
        case .diskTotal: return "T"
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
        static let panelScale = "panelScale"
        static let desktopWidgetEnabled = "desktopWidgetEnabled"
        static let desktopWidgetSize = "desktopWidgetSize"
        static let desktopWidgetOriginX = "desktopWidgetOriginX"
        static let desktopWidgetOriginY = "desktopWidgetOriginY"
        static let chartWindowSeconds = "chartWindowSeconds"
        static let panelPinned = "panelPinned"
    }

    enum DesktopWidgetSize: String, CaseIterable, Identifiable {
        case s, m, l, xl
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .s: return "S (1 anillo)"
            case .m: return "M (4 anillos)"
            case .l: return "L (6 métricas)"
            case .xl: return "XL (con gráfico)"
            }
        }
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

    /// Filas de la cuadrícula (2 por defecto; 3 y 4 con letra más pequeña).
    var gridRows: Int {
        get {
            let value = defaults.integer(forKey: Key.gridRows)
            return value == 0 ? 2 : min(max(value, 2), 4)
        }
        set { defaults.set(min(max(newValue, 2), 4), forKey: Key.gridRows) }
    }

    /// Escala del panel grande (0.8–1.6; botones −/+ en el propio panel).
    var panelScale: Double {
        get {
            let value = defaults.double(forKey: Key.panelScale)
            return value == 0 ? 1.0 : min(max(value, 0.8), 1.6)
        }
        set { defaults.set(min(max(newValue, 0.8), 1.6), forKey: Key.panelScale) }
    }

    /// Ventana temporal de las gráficas del panel (60/300/1800/3600 s).
    var chartWindowSeconds: Int {
        get {
            let value = defaults.integer(forKey: Key.chartWindowSeconds)
            return [60, 300, 1800, 3600].contains(value) ? value : 300
        }
        set { defaults.set(newValue, forKey: Key.chartWindowSeconds) }
    }

    /// Panel anclado: no se cierra al hacer clic fuera (OFF por defecto).
    var panelPinned: Bool {
        get { defaults.bool(forKey: Key.panelPinned) }
        set { defaults.set(newValue, forKey: Key.panelPinned) }
    }

    /// Widget de escritorio (fase 7) — OFF por defecto, como toda feature nueva.
    var desktopWidgetEnabled: Bool {
        get { defaults.bool(forKey: Key.desktopWidgetEnabled) }
        set { defaults.set(newValue, forKey: Key.desktopWidgetEnabled) }
    }

    var desktopWidgetSize: DesktopWidgetSize {
        get {
            DesktopWidgetSize(rawValue: defaults.string(forKey: Key.desktopWidgetSize) ?? "m") ?? .m
        }
        set { defaults.set(newValue.rawValue, forKey: Key.desktopWidgetSize) }
    }

    /// Posición persistida del widget de escritorio (nil = primera vez).
    var desktopWidgetOrigin: CGPoint? {
        get {
            guard defaults.object(forKey: Key.desktopWidgetOriginX) != nil else { return nil }
            return CGPoint(x: defaults.double(forKey: Key.desktopWidgetOriginX),
                           y: defaults.double(forKey: Key.desktopWidgetOriginY))
        }
        set {
            defaults.set(newValue?.x ?? 0, forKey: Key.desktopWidgetOriginX)
            defaults.set(newValue?.y ?? 0, forKey: Key.desktopWidgetOriginY)
        }
    }

    func setEnabled(_ metric: MetricID, _ enabled: Bool) {
        var set = disabledMetrics
        if enabled { set.remove(metric) } else { set.insert(metric) }
        disabledMetrics = set
    }

    // MARK: - Colores dinámicos y umbrales (v1.1)

    /// El valor en la barra cambia de color según su umbral. OFF por defecto:
    /// las features nuevas son opt-in para no tocar la experiencia base liviana.
    var dynamicColorsEnabled: Bool {
        get { defaults.bool(forKey: "dynamicColors") }
        set { defaults.set(newValue, forKey: "dynamicColors") }
    }

    /// Notificaciones cuando una métrica cruza su umbral crítico (OFF por defecto).
    var alertsEnabled: Bool {
        get { defaults.bool(forKey: "alertsEnabled") }
        set { defaults.set(newValue, forKey: "alertsEnabled") }
    }

    /// Umbral de una métrica. Unidades: fracción 0-1 (cpu/memory), 0-100
    /// (gpu/temperature), GB libres (diskFree). Defaults razonables de laptop.
    static let defaultThresholds: [MetricID: (warning: Double, critical: Double)] = [
        .cpu: (0.70, 0.90),
        .memory: (0.80, 0.92),
        .gpu: (80, 95),
        .temperature: (80, 92),
        .diskFree: (20, 10),
    ]

    func threshold(_ metric: MetricID, _ level: AlertLevel) -> Double {
        let key = "threshold.\(metric.rawValue).\(level == .critical ? "crit" : "warn")"
        if defaults.object(forKey: key) != nil { return defaults.double(forKey: key) }
        let d = Self.defaultThresholds[metric] ?? (0, 0)
        return level == .critical ? d.critical : d.warning
    }

    func setThreshold(_ metric: MetricID, _ level: AlertLevel, _ value: Double) {
        defaults.set(value, forKey: "threshold.\(metric.rawValue).\(level == .critical ? "crit" : "warn")")
    }

    func notifyChanged() {
        NotificationCenter.default.post(name: Self.changedNotification, object: nil)
    }
}
