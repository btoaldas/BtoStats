import SwiftUI
import Charts

/// Panel grande: KPIs, gráficos en vivo (histórico de 5 min) y top procesos.
struct PanelView: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            kpiRow
            HStack(spacing: 14) {
                usageChart
                networkChart
            }
            .frame(height: 150)
            topsRow
        }
        .padding(16)
        .frame(width: 780)
    }

    // MARK: - KPIs

    private var kpiRow: some View {
        HStack(spacing: 10) {
            kpi("CPU", String(format: "%.0f%%", model.cpuUsage * 100),
                detail: "\(model.coreCount) núcleos")
            kpi("GPU", String(format: "%.0f%%", model.gpuUsage),
                detail: model.gpuTemp.map { String(format: "%.0f °C", $0) } ?? "")
            kpi("RAM", String(format: "%.0f%%", model.memoryFraction * 100),
                detail: String(format: "%.1f / %.0f GB", model.memoryUsedGB, model.memoryTotalGB))
            kpi("Temp CPU", model.cpuTemp.map { String(format: "%.0f °C", $0) } ?? "—",
                detail: fanDetail)
            kpi("Red", "↑ \(StatusItemController.rate(model.uploadBps))/s",
                detail: "↓ \(StatusItemController.rate(model.downloadBps))/s")
            kpi("Disco", StatusItemController.bytes(model.diskAvailable),
                detail: "de \(StatusItemController.bytes(model.diskTotal))")
        }
    }

    private var fanDetail: String {
        guard !model.fanRPM.isEmpty else { return "" }
        return model.fanRPM.map { String(format: "%.0f", $0) }.joined(separator: "/") + " rpm"
    }

    private func kpi(_ title: String, _ value: String, detail: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
            Text(detail.isEmpty ? " " : detail)
                .font(.caption2).foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Gráficos

    private var usageChart: some View {
        chartCard("CPU · GPU · RAM (5 min)") {
            Chart {
                ForEach(Array(model.cpuHistory.enumerated()), id: \.offset) { index, value in
                    LineMark(x: .value("t", index), y: .value("%", value * 100),
                             series: .value("serie", "CPU"))
                        .foregroundStyle(.blue)
                }
                ForEach(Array(model.gpuHistory.enumerated()), id: \.offset) { index, value in
                    LineMark(x: .value("t", index), y: .value("%", value),
                             series: .value("serie", "GPU"))
                        .foregroundStyle(.green)
                }
                ForEach(Array(model.memoryHistory.enumerated()), id: \.offset) { index, value in
                    LineMark(x: .value("t", index), y: .value("%", value * 100),
                             series: .value("serie", "RAM"))
                        .foregroundStyle(.orange)
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartLegend(.hidden)
        }
    }

    private var networkChart: some View {
        chartCard("Red B/s (5 min) — azul ↓, rojo ↑") {
            Chart {
                ForEach(Array(model.downloadHistory.enumerated()), id: \.offset) { index, value in
                    LineMark(x: .value("t", index), y: .value("B/s", value),
                             series: .value("serie", "↓"))
                        .foregroundStyle(.blue)
                }
                ForEach(Array(model.uploadHistory.enumerated()), id: \.offset) { index, value in
                    LineMark(x: .value("t", index), y: .value("B/s", value),
                             series: .value("serie", "↑"))
                        .foregroundStyle(.red)
                }
            }
            .chartXAxis(.hidden)
            .chartLegend(.hidden)
        }
    }

    private func chartCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Top procesos

    private var topsRow: some View {
        HStack(alignment: .top, spacing: 14) {
            topList("Top CPU", model.topCPU) { String(format: "%.1f%%", $0.value) }
            topList("Top RAM", model.topRAM) { StatusItemController.bytes(UInt64($0.value)) }
            topList("Top Red", model.topNetwork) { StatusItemController.rate($0.value) + "/s" }
        }
    }

    private func topList(_ title: String,
                         _ samples: [ProcessReader.ProcessSample],
                         value: @escaping (ProcessReader.ProcessSample) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).bold().foregroundStyle(.secondary)
            if samples.isEmpty {
                Text("midiendo…").font(.caption).foregroundStyle(.tertiary)
            }
            ForEach(samples) { sample in
                HStack {
                    Text(sample.name)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(value(sample))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
