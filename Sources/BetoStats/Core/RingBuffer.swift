import Foundation

/// Buffer circular de capacidad fija para histórico corto de métricas.
struct RingBuffer<Element> {
    private var storage: [Element] = []
    private var writeIndex = 0
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    var count: Int { storage.count }

    mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[writeIndex] = element
        }
        writeIndex = (writeIndex + 1) % capacity
    }

    /// Elementos en orden cronológico (el más viejo primero).
    var elements: [Element] {
        guard storage.count == capacity else { return storage }
        return Array(storage[writeIndex...]) + Array(storage[..<writeIndex])
    }

    var last: Element? {
        guard !storage.isEmpty else { return nil }
        let index = (writeIndex - 1 + storage.count) % storage.count
        return storage[index]
    }
}
