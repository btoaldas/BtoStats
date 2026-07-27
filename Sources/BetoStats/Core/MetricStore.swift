import Foundation

/// Último snapshot + histórico corto por métrica.
/// Acceso SOLO desde el hilo principal (los readers publican vía main).
final class MetricStore {
    static let historyCapacity = 300 // 5 min a 1 s

    private(set) var cpu: CPUReader.Snapshot?
    private(set) var memory: MemoryReader.Snapshot?
    private(set) var network: NetworkReader.Snapshot?
    private(set) var disk: DiskReader.Snapshot?

    private(set) var cpuHistory = RingBuffer<Double>(capacity: historyCapacity)
    private(set) var memoryHistory = RingBuffer<Double>(capacity: historyCapacity)
    private(set) var uploadHistory = RingBuffer<Double>(capacity: historyCapacity)
    private(set) var downloadHistory = RingBuffer<Double>(capacity: historyCapacity)

    func updateFast(cpu: CPUReader.Snapshot?,
                    memory: MemoryReader.Snapshot?,
                    network: NetworkReader.Snapshot?) {
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
    }

    func updateDisk(_ disk: DiskReader.Snapshot?) {
        if let disk { self.disk = disk }
    }
}
