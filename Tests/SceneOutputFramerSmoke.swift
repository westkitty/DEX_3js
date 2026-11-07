import Foundation

@main struct SceneOutputFramerSmoke {
    static func main() {
        var framer = SceneOutputFramer()
        let small = Data("{\"ok\":true}\n".utf8)
        guard case .lines(let smallLines) = framer.append(small), smallLines == [Data("{\"ok\":true}".utf8)] else {
            fatalError("Small complete JSON response was not framed")
        }

        let prefix = Data("{\"ok\":true,\"payload\":\"".utf8)
        let suffix = Data("\"}".utf8)
        let payload = Data(repeating: 97, count: SceneOutputFramer.maximumLineBytes - prefix.count - suffix.count)
        var nearLimit = prefix
        nearLimit.append(payload); nearLimit.append(suffix)
        precondition(nearLimit.count == SceneOutputFramer.maximumLineBytes)
        nearLimit.append(10)
        guard case .lines(let nearLimitLines) = framer.append(nearLimit), nearLimitLines.count == 1,
              (try? JSONSerialization.jsonObject(with: nearLimitLines[0])) != nil else {
            fatalError("Valid response at the configured limit was rejected")
        }

        guard case .oversized = framer.append(Data(repeating: 120, count: SceneOutputFramer.maximumLineBytes + 1)) else {
            fatalError("Oversized unterminated output was not rejected")
        }
        precondition(framer.bufferedBytes.isEmpty, "Overflow must release its retained buffer")
        var oversizedTerminated = Data(repeating: 120, count: SceneOutputFramer.maximumLineBytes + 1)
        oversizedTerminated.append(10)
        guard case .oversized = framer.append(oversizedTerminated) else { fatalError("Oversized terminated line was not rejected") }

        let malformed = Data("not-json\n".utf8)
        let invalidUTF8 = Data([0xff, 0xfe, 10])
        var malformedBatch = malformed
        malformedBatch.append(invalidUTF8)
        guard case .lines(let malformedLines) = framer.append(malformedBatch), malformedLines == [Data("not-json".utf8), Data([0xff, 0xfe])] else {
            fatalError("Malformed JSON or invalid UTF-8 must remain line-bounded for controlled rejection")
        }
        precondition((try? JSONSerialization.jsonObject(with: malformedLines[0])) == nil)
        precondition(String(data: malformedLines[1], encoding: .utf8) == nil)

        let truncated = Data("{\"id\":7".utf8)
        guard case .lines(let noCompleteLines) = framer.append(truncated), noCompleteLines.isEmpty else { fatalError("Partial response must wait for its delimiter") }
        precondition(framer.finish() == truncated.count, "Child termination must expose the truncated byte count")
        precondition(framer.bufferedBytes.isEmpty)
        _ = framer.append(truncated)
        framer.reset()
        precondition(framer.finish() == 0, "Cancellation reset must discard buffered partial output")

        print("PASS: output framing small/1MiB/oversize/malformed/invalid-UTF8/truncated/cancel cases")
    }
}
