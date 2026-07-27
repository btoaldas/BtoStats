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
        chartCard("Uso % (5 min)") {
            Chart {
                ForEach(Array(model.cpuHistory.enumerated()), id: \.offset) { index, value in
                    LineMark(x: .value("t", index), y: .value("%", value * 100),
                             series: .value("Serie", "CPU"))
                        .foregroundStyle(by: .value("Serie", "CPU"))
                }
                ForEach(Array(model.gpuHistory.enumerated()), id: \.offset) { index, value in
                    LineMark(x: .value("t", index), y: .value("%", value),
                             series: .value("Serie", "GPU"))
                        .foregroundStyle(by: .value("Serie", "GPU"))
                }
                ForEach(Array(model.memoryHistory.enumerated()), id: \.offset) { index, value in
                    LineMark(x: .value("t", index), y: .value("%", value * 100),
                             series: .value("Serie", "RAM"))
                        .foregroundStyle(by: .value("Serie", "RAM"))
                }
            }
            .chartForegroundStyleScale(["CPU": Color.blue, "GPU": Color.green, "RAM": Color.orange])
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartLegend(position: .top, alignment: .leading)
        }
    }

    private var networkChart: some View {
        chartCard("Red B/s (5 min)") {
            Chart {
                ForEach(Array(model.downloadHistory.enumerated()), id: \.offset) { index, value in
                    LineMark(x: .value("t", index), y: .value("B/s", value),
                             series: .value("Serie", "↓ Bajada"))
                        .foregroundStyle(by: .value("Serie", "↓ Bajada"))
                }
                ForEach(Array(model.uploadHistory.enumerated()), id: \.offset) { index, value in
                    LineMark(x: .value("t", index), y: .value("B/s", value),
                             series: .value("Serie", "↑ Subida"))
                        .foregroundStyle(by: .value("Serie", "↑ Subida"))
                }
            }
            .chartForegroundStyleScale(["↓ Bajada": Color.blue, "↑ Subida": Color.red])
            .chartXAxis(.hidden)
            .chartLegend(position: .top, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 14) {
                // pcpu de ps: 100 % = 1 core. Se muestran las dos lecturas que
                // pidió el requerimiento: % de TODO el equipo y % del uso actual.
                topList("Top CPU — equipo · del uso", model.topCPU) { sample in
                    let ofMachine = sample.value / Double(max(model.coreCount, 1))
                    let ofUse = model.totalCPUPercent > 0
                        ? sample.value / model.totalCPUPercent * 100 : 0
                    return String(format: "%.1f%% · %.0f%%", ofMachine, ofUse)
                }
                topList("Top RAM — uso · del total", model.topRAM) { sample in
                    let fraction = model.memoryTotalGB > 0
                        ? sample.value / 1e9 / model.memoryTotalGB * 100 : 0
                    return StatusItemController.bytes(UInt64(sample.value))
                        + String(format: " · %.0f%%", fraction)
                }
                topList("Top Red", model.topNetwork) { StatusItemController.rate($0.value) + "/s" }
            }
            if let gpuProcess = model.lastGPUProcess {
                Text("GPU en uso por: \(gpuProcess) — macOS no expone %GPU por proceso sin permisos de administrador; este es el último proceso que envió trabajo a la GPU.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
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
