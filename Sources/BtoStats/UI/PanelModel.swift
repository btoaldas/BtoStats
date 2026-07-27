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
        if let gpu = store.gpu { gpuUsage = gpu.utilization }
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
        cpuHistory = store.cpuHistory.elements
        gpuHistory = store.gpuHistory.elements
        memoryHistory = store.memoryHistory.elements
        uploadHistory = store.uploadHistory.elements
        downloadHistory = store.downloadHistory.elements
    }
}
