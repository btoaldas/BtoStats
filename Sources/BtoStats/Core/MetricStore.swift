import Foundation

/// Último snapshot + histórico corto por métrica.
/// Acceso SOLO desde el hilo principal (los readers publican vía main).
final class MetricStore {
    static let historyCapacity = 300 // 5 min a 1 s

    private(set) var cpu: CPUReader.Snapshot?
    private(set) var memory: MemoryReader.Snapshot?
    private(set) var network: NetworkReader.Snapshot?
    private(set) var disk: DiskReader.Snapshot?
    private(set) var gpu: GPUReader.Snapshot?
    private(set) var sensors: SensorsReader.Snapshot?
    private(set) var system: SystemReader.Snapshot?
    private(set) var wifi: WiFiReader.Snapshot?
    private(set) var battery: BatteryReader.Snapshot?
    private(set) var diskIO: DiskIOReader.Snapshot?

    private(set) var cpuHistory = MetricSeries()
    private(set) var memoryHistory = MetricSeries()
    private(set) var uploadHistory = MetricSeries()
    private(set) var downloadHistory = MetricSeries()
    private(set) var gpuHistory = MetricSeries()
    /// Muestreo del último proceso en enviar trabajo a la GPU (1 por tick):
    /// base del "top GPU aproximado" — macOS no da %GPU por proceso sin admin.
    private(set) var gpuSubmitterHistory = RingBuffer<String>(capacity: historyCapacity)
    private(set) var cpuTempHistory = MetricSeries()

    func updateFast(cpu: CPUReader.Snapshot?,
                    memory: MemoryReader.Snapshot?,
                    network: NetworkReader.Snapshot?,
                    gpu: GPUReader.Snapshot? = nil,
                    sensors: SensorsReader.Snapshot? = nil) {
        if let cpu {
            self.cpu = cpu
            cpuHistory.append(cpu.totalUsage)
        }
        if let memory {
            self.memory = memory
            memoryHistory.append(memory.fractionUsed)
        }
        if let network {
            self.network = network
            uploadHistory.append(network.uploadBps)
            downloadHistory.append(network.downloadBps)
        }
        if let gpu {
            self.gpu = gpu
            gpuHistory.append(gpu.utilization)
            if let submitter = gpu.lastSubmitterName {
                gpuSubmitterHistory.append(submitter)
            }
        }
        if let sensors {
            self.sensors = sensors
            if let temp = sensors.cpuTempAvg { cpuTempHistory.append(temp) }
        }
    }

    func updateDisk(_ disk: DiskReader.Snapshot?) {
        if let disk { self.disk = disk }
    }

    func updateSystem(_ system: SystemReader.Snapshot?) {
        if let system { self.system = system }
    }

    func updateWiFi(_ wifi: WiFiReader.Snapshot?) { self.wifi = wifi }
    func updateBattery(_ battery: BatteryReader.Snapshot?) { self.battery = battery }
    func updateDiskIO(_ io: DiskIOReader.Snapshot?) { if let io { self.diskIO = io } }
}
