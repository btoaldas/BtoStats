import Foundation

/// Serie de una métrica en tres resoluciones simultáneas:
/// 1 s (hasta 5 min), 6 s (hasta 30 min) y 12 s (hasta 1 h) —
/// los buckets se promedian al llenarse. Ventanas mayores (día/mes)
/// requerirán persistencia en disco (futuro).
struct MetricSeries {
    private(set) var base = RingBuffer<Double>(capacity: 300)
    private(set) var mid = RingBuffer<Double>(capacity: 300)
    private(set) var long = RingBuffer<Double>(capacity: 300)
    private var midAccumulator: (sum: Double, count: Int) = (0, 0)
    private var longAccumulator: (sum: Double, count: Int) = (0, 0)

    mutating func append(_ value: Double) {
        base.append(value)
        midAccumulator.sum += value
        midAccumulator.count += 1
        if midAccumulator.count >= 6 {
            mid.append(midAccumulator.sum / Double(midAccumulator.count))
            midAccumulator = (0, 0)
        }
        longAccumulator.sum += value
        longAccumulator.count += 1
        if longAccumulator.count >= 12 {
            long.append(longAccumulator.sum / Double(longAccumulator.count))
            longAccumulator = (0, 0)
        }
    }

    var last: Double? { base.last }

    /// Valores para una ventana de N segundos + capacidad de puntos de esa
    /// ventana (para fijar el dominio X y que la gráfica se DESPLACE en vez
    /// de comprimirse).
    func window(seconds: Int) -> (values: [Double], capacity: Int) {
        switch seconds {
        case ...300:
            return (Array(base.elements.suffix(seconds)), seconds)
        case ...1800:
            return (mid.elements, 300)
        default:
            return (long.elements, 300)
        }
    }
}
