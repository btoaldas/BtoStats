import SwiftUI
import Charts

/// Panel grande: KPIs, gráficos en vivo (histórico de 5 min) y top procesos.
struct PanelView: View {
    @ObservedObject var model: PanelModel
    @State private var scale: Double = AppConfig.shared.panelScale

    private var processFont: CGFloat { 11 * scale }
    private var kpiFont: CGFloat { 17 * scale }

    @State private var windowSeconds: Int = AppConfig.shared.chartWindowSeconds

    var body: some View {
        VStack(alignment: .leading, spacing: 12 * scale) {
            controlBar
            kpiRow
            HStack(spacing: 14) {
                usageChart
                networkChart
            }
            .frame(height: 150 * scale)
            topsRow
        }
        .padding(.top, 10)
        .padding([.horizontal, .bottom], 16)
        .frame(width: 820 * scale)
    }

    /// Fila única y compacta: ventana temporal de las gráficas + zoom.
    private var controlBar: some View {
        HStack(spacing: 8) {
            Picker("", selection: $windowSeconds) {
                Text("1 min").tag(60)
                Text("5 min").tag(300)
                Text("30 min").tag(1800)
                Text("1 h").tag(3600)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
            .onChange(of: windowSeconds) { _, newValue in
                AppConfig.shared.chartWindowSeconds = newValue
            }
            Spacer()
            Button { changeScale(-0.1) } label: { Image(systemName: "minus.magnifyingglass") }
                .buttonStyle(.borderless)
                .disabled(scale <= 0.81)
            Text("\(Int((scale * 100).rounded())) %")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button { changeScale(0.1) } label: { Image(systemName: "plus.magnifyingglass") }
                .buttonStyle(.borderless)
                .disabled(scale >= 1.59)
        }
        .frame(height: 22)
    }

    private func changeScale(_ delta: Double) {
        scale = min(max(scale + delta, 0.8), 1.6)
        AppConfig.shared.panelScale = scale
    }

    /// Nombres tipo "com.apple.Virtualization.VirtualMachine" → "VirtualMachine".
    private func displayName(_ raw: String) -> String {
        guard raw.count > 18, raw.contains(".") else { return raw }
        if let last = raw.split(separator: ".").last, last.count >= 3 {
            return String(last)
        }
        return raw
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
            kpi("Disco libre", StatusItemController.bytes(model.diskAvailable),
                detail: "total \(StatusItemController.bytes(model.diskTotal))")
        }
    }

    private var fanDetail: String {
        guard !model.fanRPM.isEmpty else { return "" }
        return model.fanRPM.map { String(format: "%.0f", $0) }.joined(separator: "/") + " rpm"
    }

    private func kpi(_ title: String, _ value: String, detail: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(size: kpiFont, weight: .semibold, design: .rounded))
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

    /// Corre el eje X para que el último punto quede SIEMPRE en el borde
    /// derecho: la gráfica se desplaza en vez de comprimirse.
    private func shifted(_ values: [Double]) -> [(x: Int, y: Double)] {
        let offset = model.windowCapacity - values.count
        return values.enumerated().map { (x: $0.offset + offset, y: $0.element) }
    }

    private var usageChart: some View {
        chartCard("Uso % — en vivo") {
            Chart {
                ForEach(shifted(model.cpuHistory), id: \.x) { point in
                    LineMark(x: .value("t", point.x), y: .value("%", point.y * 100),
                             series: .value("Serie", "CPU"))
                        .foregroundStyle(by: .value("Serie", "CPU"))
                }
                ForEach(shifted(model.gpuHistory), id: \.x) { point in
                    LineMark(x: .value("t", point.x), y: .value("%", point.y),
                             series: .value("Serie", "GPU"))
                        .foregroundStyle(by: .value("Serie", "GPU"))
                }
                ForEach(shifted(model.memoryHistory), id: \.x) { point in
                    LineMark(x: .value("t", point.x), y: .value("%", point.y * 100),
                             series: .value("Serie", "RAM"))
                        .foregroundStyle(by: .value("Serie", "RAM"))
                }
            }
            .chartForegroundStyleScale(["CPU": Color.blue, "GPU": Color.green, "RAM": Color.orange])
            .chartYScale(domain: 0...100)
            .chartXScale(domain: 0...model.windowCapacity)
            .chartXAxis(.hidden)
            .chartLegend(position: .top, alignment: .leading)
        }
    }

    private var networkChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Red — en vivo").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("enlace \(model.linkSpeedText)")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("· pico \(StatusItemController.rate(peakVisible))/s")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            Chart {
                ForEach(shifted(model.downloadHistory), id: \.x) { point in
                    LineMark(x: .value("t", point.x), y: .value("B/s", point.y),
                             series: .value("Serie", "↓ Bajada"))
                        .foregroundStyle(by: .value("Serie", "↓ Bajada"))
                }
                ForEach(shifted(model.uploadHistory), id: \.x) { point in
                    LineMark(x: .value("t", point.x), y: .value("B/s", point.y),
                             series: .value("Serie", "↑ Subida"))
                        .foregroundStyle(by: .value("Serie", "↑ Subida"))
                }
            }
            .chartForegroundStyleScale(["↓ Bajada": Color.blue, "↑ Subida": Color.red])
            .chartXScale(domain: 0...model.windowCapacity)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let bps = value.as(Double.self) {
                            Text(StatusItemController.rate(bps) + "/s")
                                .font(.system(size: 9))
                        }
                    }
                }
            }
            .chartLegend(position: .top, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Máximo de la ventana visible (la escala Y ya es dinámica: Charts la
    /// ajusta al máximo actual — el ancho de banda del enlace es el dato fijo
    /// de la izquierda, la velocidad real es la gráfica).
    private var peakVisible: Double {
        max(model.downloadHistory.max() ?? 0, model.uploadHistory.max() ?? 0)
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
                topGPUList
            }
            Text("Top GPU: aproximado por muestreo (% del tiempo en que cada proceso fue el último en enviar trabajo a la GPU). El % exacto por proceso requiere el helper de administrador (fase 8).")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Circle()
                    .fill(model.memoryPressure == .normal ? Color.green
                          : model.memoryPressure == .warning ? Color.yellow : Color.red)
                    .frame(width: 8, height: 8)
                Text(MemoryAdvisor.advice(for: model.memoryPressure))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var topGPUList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.helperActive ? "Top GPU — ms/s (exacto)" : "Top GPU — % tiempo (aprox.)")
                .font(.caption).bold().foregroundStyle(.secondary)
            if model.helperActive {
                if model.topGPUExact.isEmpty {
                    Text("midiendo…").font(.caption).foregroundStyle(.tertiary)
                }
                ForEach(model.topGPUExact, id: \.name) { entry in
                    HStack {
                        Text(displayName(entry.name))
                            .font(.system(size: processFont)).lineLimit(1)
                            .truncationMode(.tail).help(entry.name)
                        Spacer(minLength: 8)
                        Text(String(format: "%.0f ms/s", entry.gpuMs))
                            .font(.system(size: processFont, weight: .medium))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            } else {
                if model.topGPU.isEmpty {
                    Text("midiendo…").font(.caption).foregroundStyle(.tertiary)
                }
                ForEach(model.topGPU, id: \.name) { entry in
                    HStack {
                        Text(displayName(entry.name))
                            .font(.system(size: processFont)).lineLimit(1)
                            .truncationMode(.tail).help(entry.name)
                        Spacer(minLength: 8)
                        Text(String(format: "%.0f%%", entry.percent))
                            .font(.system(size: processFont, weight: .medium))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
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
                HStack(spacing: 4) {
                    killButton(for: sample)
                    Text(displayName(sample.name))
                        .font(.system(size: processFont))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(sample.name)
                    Spacer(minLength: 8)
                    Text(value(sample))
                        .font(.system(size: processFont, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Cerrar proceso: SIEMPRE con confirmación; forzar es una opción aparte
    /// del mismo diálogo. Procesos de otro usuario: deshabilitado (helper fase 8).
    private func killButton(for sample: ProcessReader.ProcessSample) -> some View {
        let own = ProcessKiller.canTerminate(pid: sample.pid)
        let canAct = own || model.helperActive
        return Button {
            confirmAndTerminate(sample, privileged: !own)
        } label: {
            Image(systemName: "xmark.circle")
                .font(.system(size: 10))
                .foregroundStyle(canAct ? Color.red.opacity(0.8) : Color.gray.opacity(0.4))
        }
        .buttonStyle(.plain)
        .disabled(!canAct)
        .help(own ? "Cerrar \(sample.name) (con confirmación)"
              : model.helperActive ? "Cerrar \(sample.name) — proceso privilegiado (doble confirmación)"
              : "Proceso de otro usuario — activa las funciones de administrador en Preferencias")
    }

    private func confirmAndTerminate(_ sample: ProcessReader.ProcessSample, privileged: Bool) {
        let safeName = String(sample.name.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
            .prefix(60))
        let alert = NSAlert()
        alert.messageText = "¿Cerrar \"\(safeName)\" (PID \(sample.pid))?"
        alert.informativeText = privileged
            ? "⚠️ Proceso de otro usuario o del sistema. Cerrarlo puede desestabilizar la sesión. Se cerrará con privilegios de administrador."
            : "Terminar pide el cierre educado (la app puede preguntar si guardas cambios). Forzar cierre mata el proceso al instante y puede perder datos."
        alert.alertStyle = privileged ? .critical : .warning
        alert.addButton(withTitle: "Terminar")
        alert.addButton(withTitle: "Forzar cierre")
        alert.addButton(withTitle: "Cancelar")
        NSApp.activate(ignoringOtherApps: true)
        let choice = alert.runModal()
        guard choice != .alertThirdButtonReturn else { return }
        let force = choice == .alertSecondButtonReturn

        // Segunda confirmación para procesos privilegiados (root/otros).
        if privileged {
            let confirm = NSAlert()
            confirm.messageText = "Confirmar cierre privilegiado de \"\(safeName)\""
            confirm.informativeText = "Esta acción usa el ayudante de administrador. ¿Seguro?"
            confirm.alertStyle = .critical
            confirm.addButton(withTitle: "Sí, cerrar")
            confirm.addButton(withTitle: "Cancelar")
            guard confirm.runModal() == .alertFirstButtonReturn else { return }
            HelperClient.shared.terminatePrivileged(pid: sample.pid, force: force,
                                                     name: sample.name) { result in
                if result != "ok" { Self.showError(sample.name, result) }
            }
            return
        }

        let outcome = ProcessKiller.terminate(pid: sample.pid, force: force,
                                              expectedName: sample.name)
        if case .failed(let reason) = outcome { Self.showError(sample.name, reason) }
    }

    private static func showError(_ name: String, _ reason: String) {
        let error = NSAlert()
        error.messageText = "No se pudo cerrar \(name)"
        error.informativeText = reason
        error.runModal()
    }
}
