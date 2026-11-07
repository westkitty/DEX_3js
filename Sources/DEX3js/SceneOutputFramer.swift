import Foundation

enum SceneOutputFrameResult {
    case lines([Data])
    case oversized
}

struct SceneOutputFramer {
    static let maximumLineBytes = 1_048_576
    private(set) var bufferedBytes = Data()

    mutating func append(_ data: Data) -> SceneOutputFrameResult {
        var remaining = data
        var lines: [Data] = []
        while !remaining.isEmpty {
            let capacity = Self.maximumLineBytes - bufferedBytes.count
            let count = min(remaining.count, max(1, capacity + 1))
            bufferedBytes.append(remaining.prefix(count))
            remaining.removeFirst(count)
            while let newline = bufferedBytes.firstIndex(of: 10) {
                guard bufferedBytes.distance(from: bufferedBytes.startIndex, to: newline) <= Self.maximumLineBytes else {
                    reset()
                    return .oversized
                }
                lines.append(Data(bufferedBytes.prefix(upTo: newline)))
                bufferedBytes.removeSubrange(...newline)
            }
            guard bufferedBytes.count <= Self.maximumLineBytes else {
                reset()
                return .oversized
            }
        }
        return .lines(lines)
    }

    mutating func finish() -> Int {
        let truncatedBytes = bufferedBytes.count
        reset()
        return truncatedBytes
    }

    mutating func reset() { bufferedBytes.removeAll(keepingCapacity: false) }
}
