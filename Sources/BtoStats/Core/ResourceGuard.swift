import Foundation

/// Protección de recursos del sistema: la app se auto-limita cuando el equipo
/// está bajo presión, para no ser parte del problema que monitorea.
///
/// - Batería baja y desconectado → sondea más lento (ahorra energía).
/// - Presión de memoria crítica → pausa los readers caros.
/// - Presupuesto documentado: en modo normal el sondeo cuesta <0.1 % de un
///   core; el histórico está acotado por su propia política de tamaño.
enum ResourceGuard {
    /// Multiplicador de la cadencia según el estado del equipo.
    /// 1 = normal, 2 = mitad de frecuencia, 4 = un cuarto.
    static func intervalMultiplier(battery: BatteryReader.Snapshot?) -> Double {
        guard AppConfig.shared.resourceGuardEnabled else { return 1 }

        // Presión de memoria crítica: bajar mucho el ritmo.
        if MemoryAdvisor.currentPressure() == .critical { return 4 }

        // Batería baja sin cargador: ahorrar energía.
        if let battery, !battery.isCharging {
            if battery.percentage <= 10 { return 4 }
            if battery.percentage <= 20 { return 2 }
        }
        return 1
    }

    /// ¿Conviene saltarse los readers caros (SMC, IOKit, IOReport) este ciclo?
    static func shouldSkipExpensiveReaders(battery: BatteryReader.Snapshot?) -> Bool {
        guard AppConfig.shared.resourceGuardEnabled else { return false }
        if MemoryAdvisor.currentPressure() == .critical { return true }
        if let battery, !battery.isCharging, battery.percentage <= 10 { return true }
        return false
    }

    /// Texto del estado actual para mostrarlo en el panel.
    static func statusText(battery: BatteryReader.Snapshot?) -> String {
        let multiplier = intervalMultiplier(battery: battery)
        if multiplier == 1 { return "normal" }
        if MemoryAdvisor.currentPressure() == .critical { return "ahorro (memoria crítica)" }
        return "ahorro (batería baja)"
    }
}
