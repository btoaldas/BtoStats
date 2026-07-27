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

    func refresh(from store: MetricStore) {
        if let cpuSnapshot = store.cpu { cpu = cpuSnapshot.totalUsage }
        if let gpuSnapshot = store.gpu { gpu = gpuSnapshot.utilization }
        if let memory = store.memory { ram = memory.fractionUsed }
        if let diskSnapshot = store.disk {
            let used = Double(diskSnapshot.usedBytes)
            disk = diskSnapshot.totalBytes > 0 ? used / Double(diskSnapshot.totalBytes) : 0
            diskFreeText = StatusItemController.bytes(diskSnapshot.availableBytes)
        }
        cpuTemp = store.sensors?.cpuTempAvg
        if let network = store.network {
            uploadBps = network.uploadBps
            downloadBps = network.downloadBps
        }
        cpuHistory = store.cpuHistory.elements
        ramHistory = store.memoryHistory.elements
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
        .animation(.easeOut(duration: 0.5), value: fraction)
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

    @ViewBuilder private var content: some View {
        switch size {
        case .s:
            cpuRing(diameter: 96)
        case .m:
            grid2x2(diameter: 84)
        case .l:
            VStack(spacing: 14) {
                grid2x2(diameter: 78)
                HStack(spacing: 14) {
                    tempRing(diameter: 78)
                    networkCell
                }
            }
        case .xl:
            VStack(spacing: 14) {
                grid2x2(diameter: 78)
                HStack(spacing: 14) {
                    tempRing(diameter: 78)
                    networkCell
                }
                historyChart
            }
        }
    }

    private func cpuRing(diameter: CGFloat) -> some View {
        RingGauge(title: "CPU", fraction: model.cpu,
                  valueText: String(format: "%.0f%%", model.cpu * 100),
                  color: .blue, diameter: diameter)
    }

    private func tempRing(diameter: CGFloat) -> some View {
        RingGauge(title: "Temp",
                  fraction: (model.cpuTemp ?? 0) / 100,
                  valueText: model.cpuTemp.map { String(format: "%.0f°", $0) } ?? "—",
                  color: .red, diameter: diameter)
    }

    private func grid2x2(diameter: CGFloat) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                cpuRing(diameter: diameter)
                RingGauge(title: "GPU", fraction: model.gpu / 100,
                          valueText: String(format: "%.0f%%", model.gpu),
                          color: .green, diameter: diameter)
            }
            HStack(spacing: 14) {
                RingGauge(title: "RAM", fraction: model.ram,
                          valueText: String(format: "%.0f%%", model.ram * 100),
                          color: .orange, diameter: diameter)
                RingGauge(title: "Disk", fraction: model.disk,
                          valueText: String(format: "%.0f%%", model.disk * 100),
                          color: .cyan, diameter: diameter)
            }
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

    private var historyChart: some View {
        Chart {
            ForEach(Array(model.cpuHistory.enumerated()), id: \.offset) { index, value in
                LineMark(x: .value("t", index), y: .value("%", value * 100),
                         series: .value("s", "CPU"))
                    .foregroundStyle(.blue)
            }
            ForEach(Array(model.ramHistory.enumerated()), id: \.offset) { index, value in
                LineMark(x: .value("t", index), y: .value("%", value * 100),
                         series: .value("s", "RAM"))
                    .foregroundStyle(.orange)
            }
        }
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 46)
    }
}
