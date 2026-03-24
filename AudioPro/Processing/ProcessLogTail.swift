import Foundation

struct ProcessLogTail: Sendable, Equatable {
    nonisolated static let defaultMaxBytes = 128 * 1024

    let maxBytes: Int
    private(set) var data = Data()

    nonisolated init(maxBytes: Int = ProcessLogTail.defaultMaxBytes) {
        self.maxBytes = max(1, maxBytes)
    }

    nonisolated mutating func append(_ newData: Data) {
        guard newData.isEmpty == false else { return }

        if newData.count >= maxBytes {
            data = Data(newData.suffix(maxBytes))
            return
        }

        data.append(newData)
        if data.count > maxBytes {
            data.removeFirst(data.count - maxBytes)
        }
    }

    nonisolated var stringValue: String {
        String(decoding: data, as: UTF8.self)
    }
}
