import Foundation

/// Salud de RAM honesta: nivel de presión real del kernel.
/// No hay "liberar RAM" mágico sin costo: purge exige root y solo tira caché de
/// disco; forzar presión degrada el sistema (docs/VIABILIDAD.md §4). Lo útil es
/// mostrar la presión real y cerrar los procesos glotones.
enum MemoryAdvisor {
    enum Pressure: Int {
        case normal = 1, warning = 2, critical = 4

        var label: String {
            switch self {
            case .normal: return "normal"
            case .warning: return "alta"
            case .critical: return "crítica"
            }
        }
    }

    static func currentPressure() -> Pressure? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return nil
        }
        return Pressure(rawValue: Int(level))
    }

    static func advice(for pressure: Pressure) -> String {
        switch pressure {
        case .normal:
            return "Presión de memoria normal: la RAM \"llena\" es caché que macOS libera solo. No hace falta liberar nada."
        case .warning:
            return "Presión de memoria alta: el sistema está comprimiendo. Cierra los mayores consumidores del Top RAM."
        case .critical:
            return "Presión de memoria crítica: hay swap intenso. Cierra ya los mayores consumidores del Top RAM."
        }
    }
}
