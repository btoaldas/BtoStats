import SwiftUI
import Charts

/// Estado del widget de escritorio (se refresca en cada tick mientras esté activo).
final class DesktopWidgetModel: ObservableObject {
    @Published var cpu: Double = 0          // 0-1
    @Published var gpu: Double = 0          // 0-100
    @Published var ram: Double = 0          // 0-1
    @Published var disk: Double = 0         // 0-1 (usado/total)
    @Published var diskFreeText: String = "—"
    @Published var cpuTemp: Double?
    @Published var uploadBps: Double = 0
    @Published var downloadBps: Double = 0
    @Published var cpuHistory: [Double] = []
    @Published var ramHistory: [Double] = []
    @Published var gpuHistory: [Double] = []
    @Published var upHistory: [Double] = []
    @Published var downHistory: [Double] = []
    @Published var windowCapacity: Int = 300
    @Published var diskTotalText: String = "—"
    @Published var visibleMetrics: [MetricID] = []

    func refresh(from store: MetricStore) {
        if let cpuSnapshot = store.cpu { cpu = cpuSnapshot.totalUsage }
        if let gpuSnapshot = store.gpu { gpu = gpuSnapshot.utilization }
        if let memory = store.memory { ram = memory.fractionUsed }
        if let diskSnapshot = store.disk {
            let used = Double(diskSnapshot.usedBytes)
            disk = diskSnapshot.totalBytes > 0 ? used / Double(diskSnapshot.totalBytes) : 0
            diskFreeText = StatusItemController.bytes(diskSnapshot.availableBytes)
            diskTotalText = StatusItemController.bytes(diskSnapshot.totalBytes)
        }
        visibleMetrics = AppConfig.shared.visibleMetrics
        cpuTemp = store.sensors?.cpuTempAvg
        if let network = store.network {
            uploadBps = network.uploadBps
            downloadBps = network.downloadBps
        }
        // misma ventana temporal que el panel (config centralizada):
        // 1 min / 5 min / 30 min / 1 h
        let seconds = AppConfig.shared.chartWindowSeconds
        let cpuWindow = store.cpuHistory.window(seconds: seconds)
        cpuHistory = cpuWindow.values
        windowCapacity = cpuWindow.capacity
        ramHistory = store.memoryHistory.window(seconds: seconds).values
        gpuHistory = store.gpuHistory.window(seconds: seconds).values
        upHistory = store.uploadHistory.window(seconds: seconds).values
        downHistory = store.downloadHistory.window(seconds: seconds).values
    }
}

/// Anillo de progreso estilo widget nativo.
struct RingGauge: View {
    let title: String
    let fraction: Double     // 0-1
    let valueText: String
    let color: Color
    var diameter: CGFloat = 78

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: diameter * 0.1)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0.002), 1))
                .stroke(color, style: StrokeStyle(lineWidth: diameter * 0.1, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: diameter * 0.16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Text(valueText)
                    .font(.system(size: diameter * 0.2, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Widget de escritorio: anillos en tiempo real, tamaños S/M/L/XL.
struct DesktopWidgetView: View {
    @ObservedObject var model: DesktopWidgetModel
    let size: AppConfig.DesktopWidgetSize

    var body: some View {
        content
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.black.opacity(0.72))
            )
    }

    /// Cuántos tiles muestra cada tamaño (XL además agrega el gráfico).
    private var tileLimit: Int {
        switch size {
        case .s: return 1
        case .m: return 4
        case .l: return 6
        case .xl: return 8
        }
    }

    @ViewBuilder private var content: some View {
        // diskTotal no aplica al widget (el "libre" ya va en la celda de red)
        let metrics = Array(model.visibleMetrics.filter { $0 != .diskTotal }.prefix(tileLimit))
        if metrics.isEmpty {
            Text("Activa métricas en Preferencias")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
        } else if size == .s {
            tile(for: metrics[0], diameter: 96)
        } else {
            VStack(spacing: 14) {
                LazyVGrid(columns: [GridItem(.fixed(84)), GridItem(.fixed(84))],
                          spacing: 14) {
                    ForEach(metrics) { metric in
                        tile(for: metric, diameter: 78)
                    }
                }
                if size == .xl {
                    historyChart
                }
            }
        }
    }

    /// Cada métrica configurada se dibuja como anillo o celda según su tipo.
    @ViewBuilder private func tile(for metric: MetricID, diameter: CGFloat) -> some View {
        switch metric {
        case .cpu:
            RingGauge(title: "CPU", fraction: model.cpu,
                      valueText: String(format: "%.0f%%", model.cpu * 100),
                      color: .blue, diameter: diameter)
        case .memory:
            RingGauge(title: "RAM", fraction: model.ram,
                      valueText: String(format: "%.0f%%", model.ram * 100),
                      color: .orange, diameter: diameter)
        case .gpu:
            RingGauge(title: "GPU", fraction: model.gpu / 100,
                      valueText: String(format: "%.0f%%", model.gpu),
                      color: .green, diameter: diameter)
        case .temperature:
            RingGauge(title: "Temp", fraction: (model.cpuTemp ?? 0) / 100,
                      valueText: model.cpuTemp.map { String(format: "%.0f°", $0) } ?? "—",
                      color: .red, diameter: diameter)
        case .diskFree:
            RingGauge(title: "Disk", fraction: model.disk,
                      valueText: String(format: "%.0f%%", model.disk * 100),
                      color: .cyan, diameter: diameter)
        case .network:
            networkCell
        case .diskTotal:
            EmptyView() // filtrado arriba: no aplica al widget
        }
    }

    private var networkCell: some View {
        VStack(spacing: 6) {
            Label {
                Text(StatusItemController.rate(model.uploadBps) + "/s").monospacedDigit()
            } icon: { Image(systemName: "arrow.up") }
                .foregroundStyle(.red.opacity(0.9))
            Label {
                Text(StatusItemController.rate(model.downloadBps) + "/s").monospacedDigit()
            } icon: { Image(systemName: "arrow.down") }
                .foregroundStyle(.blue.opacity(0.9))
            Text("libre " + model.diskFreeText)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
        }
        .font(.system(size: 13, weight: .medium))
        .frame(width: 78, height: 78)
    }

    /// Sparkline de estado: 5 líneas con los MISMOS colores de los anillos
    /// (CPU azul, GPU verde, RAM naranja, subida roja, bajada celeste). La red
    /// se normaliza al pico de la ventana — sin ejes ni valores: solo estado.
    /// Corre el eje X para que el presente quede SIEMPRE en el borde derecho:
    /// la gráfica se desplaza en vez de comprimirse (mismo motor que el panel).
    private func shifted(_ values: [Double]) -> [(x: Int, y: Double)] {
        let offset = model.windowCapacity - values.count
        return values.enumerated().map { (x: $0.offset + offset, y: $0.element) }
    }

    private var historyChart: some View {
        let redPeak = max(model.upHistory.max() ?? 0, model.downHistory.max() ?? 0, 1)
        return Chart {
            ForEach(shifted(model.cpuHistory), id: \.x) { point in
                LineMark(x: .value("t", point.x), y: .value("v", point.y * 100),
                         series: .value("s", "CPU"))
                    .foregroundStyle(.blue)
            }
            ForEach(shifted(model.gpuHistory), id: \.x) { point in
                LineMark(x: .value("t", point.x), y: .value("v", point.y),
                         series: .value("s", "GPU"))
                    .foregroundStyle(.green)
            }
            ForEach(shifted(model.ramHistory), id: \.x) { point in
                LineMark(x: .value("t", point.x), y: .value("v", point.y * 100),
                         series: .value("s", "RAM"))
                    .foregroundStyle(.orange)
            }
            ForEach(shifted(model.upHistory), id: \.x) { point in
                LineMark(x: .value("t", point.x), y: .value("v", point.y / redPeak * 100),
                         series: .value("s", "Subida"))
                    .foregroundStyle(.red)
            }
            ForEach(shifted(model.downHistory), id: \.x) { point in
                LineMark(x: .value("t", point.x), y: .value("v", point.y / redPeak * 100),
                         series: .value("s", "Bajada"))
                    .foregroundStyle(.cyan)
            }
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: 0...model.windowCapacity)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 46)
    }
}
