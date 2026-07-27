import Foundation
import Combine

/// Estado observable del panel grande. Se actualiza desde el hilo principal
/// en cada tick (métricas) y cada ~5 s (top procesos).
final class PanelModel: ObservableObject {
    @Published var cpuUsage: Double = 0            // 0-1
    @Published var memoryUsedGB: Double = 0
    @Published var memoryTotalGB: Double = 0
    @Published var memoryFraction: Double = 0      // 0-1
    @Published var gpuUsage: Double = 0            // 0-100
    @Published var cpuTemp: Double?
    @Published var gpuTemp: Double?
    @Published var fanRPM: [Double] = []
    @Published var uploadBps: Double = 0
    @Published var downloadBps: Double = 0
    @Published var diskAvailable: UInt64 = 0
    @Published var diskTotal: UInt64 = 0
    @Published var coreCount: Int = 0

    @Published var cpuHistory: [Double] = []       // 0-1
    @Published var gpuHistory: [Double] = []       // 0-100
    @Published var memoryHistory: [Double] = []    // 0-1
    @Published var uploadHistory: [Double] = []    // B/s
    @Published var downloadHistory: [Double] = []  // B/s

    @Published var lastGPUProcess: String?
    /// (proceso, % de muestras de la ventana de 5 min en que fue el último en usar la GPU)
    @Published var topGPU: [(name: String, percent: Double)] = []
    @Published var totalCPUPercent: Double = 0   // suma pcpu (100 = 1 core)
    @Published var topCPU: [ProcessReader.ProcessSample] = []
    @Published var topRAM: [ProcessReader.ProcessSample] = []
    @Published var topNetwork: [ProcessReader.ProcessSample] = []

    func refresh(from store: MetricStore) {
        if let cpu = store.cpu {
            cpuUsage = cpu.totalUsage
            coreCount = cpu.perCore.count
        }
        if let memory = store.memory {
            memoryUsedGB = memory.usedBytes / 1e9
            memoryTotalGB = memory.totalBytes / 1e9
            memoryFraction = memory.fractionUsed
        }
        if let gpu = store.gpu {
            gpuUsage = gpu.utilization
            lastGPUProcess = gpu.lastSubmitterName
        }
        if let sensors = store.sensors {
            cpuTemp = sensors.cpuTempAvg
            gpuTemp = sensors.gpuTempAvg
            fanRPM = sensors.fanRPM
        }
        if let network = store.network {
            uploadBps = network.uploadBps
            downloadBps = network.downloadBps
        }
        if let disk = store.disk {
            diskAvailable = disk.availableBytes
            diskTotal = disk.totalBytes
        }
        let submitters = store.gpuSubmitterHistory.elements
        if !submitters.isEmpty {
            var counts: [String: Int] = [:]
            for name in submitters { counts[name, default: 0] += 1 }
            topGPU = counts
                .map { (name: $0.key, percent: Double($0.value) / Double(submitters.count) * 100) }
                .sorted { $0.percent > $1.percent }
                .prefix(8)
                .map { $0 }
        }
        cpuHistory = store.cpuHistory.elements
        gpuHistory = store.gpuHistory.elements
        memoryHistory = store.memoryHistory.elements
        uploadHistory = store.uploadHistory.elements
        downloadHistory = store.downloadHistory.elements
    }
}
