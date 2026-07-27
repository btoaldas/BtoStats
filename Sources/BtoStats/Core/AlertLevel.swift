import AppKit

/// Nivel de una métrica frente a sus umbrales. Base de los colores dinámicos
/// del widget y de las alertas (v1.1).
enum AlertLevel {
    case normal, warning, critical

    var color: NSColor {
        switch self {
        case .normal: return .labelColor
        case .warning: return .systemYellow
        case .critical: return .systemRed
        }
    }
}

/// Umbrales por métrica (warning y critical). Configurables — los valores por
/// defecto son razonables para un laptop. diskFree es inverso: alerta cuando
/// queda POCO espacio.
struct MetricThresholds {
    /// Devuelve el nivel de una métrica dado su valor crudo (en la unidad
    /// natural: fracción 0-1 para CPU/RAM, 0-100 para GPU, °C, bytes libres).
    static func level(for metric: MetricID, value: Double) -> AlertLevel {
        let config = AppConfig.shared
        switch metric {
        case .cpu:
            return band(value, warn: config.threshold(.cpu, .warning),
                        crit: config.threshold(.cpu, .critical))
        case .memory:
            return band(value, warn: config.threshold(.memory, .warning),
                        crit: config.threshold(.memory, .critical))
        case .gpu:
            return band(value, warn: config.threshold(.gpu, .warning),
                        crit: config.threshold(.gpu, .critical))
        case .temperature:
            return band(value, warn: config.threshold(.temperature, .warning),
                        crit: config.threshold(.temperature, .critical))
        case .diskFree:
            // inverso: menos GB libres = peor
            let warnGB = config.threshold(.diskFree, .warning)
            let critGB = config.threshold(.diskFree, .critical)
            let freeGB = value / 1_000_000_000
            if freeGB <= critGB { return .critical }
            if freeGB <= warnGB { return .warning }
            return .normal
        case .network, .diskTotal:
            return .normal
        }
    }

    private static func band(_ value: Double, warn: Double, crit: Double) -> AlertLevel {
        if value >= crit { return .critical }
        if value >= warn { return .warning }
        return .normal
    }
}
