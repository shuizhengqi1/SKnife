import Foundation

public struct Shell {
    public var run: ([String]) throws -> String

    public init(run: @escaping ([String]) throws -> String) {
        self.run = run
    }

    public static let live = Shell { arguments in
        guard let executable = arguments.first else {
            return ""
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(arguments.dropFirst())

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        let capturedOutput = LockedData()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                capturedOutput.append(data)
            }
        }

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }

        try process.run()

        if finished.wait(timeout: .now() + 5) == .timedOut {
            output.fileHandleForReading.readabilityHandler = nil
            process.terminate()
            throw ShellError.timedOut(command: arguments.joined(separator: " "))
        }

        output.fileHandleForReading.readabilityHandler = nil
        capturedOutput.append(output.fileHandleForReading.readDataToEndOfFile())
        let text = String(data: capturedOutput.value, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw ShellError.nonZeroExit(code: process.terminationStatus, message: text)
        }

        return text
    }
}

public enum ShellError: Error, Equatable, CustomStringConvertible {
    case nonZeroExit(code: Int32, message: String)
    case timedOut(command: String)

    public var description: String {
        switch self {
        case .nonZeroExit(let code, let message):
            return "Command exited \(code): \(message)"
        case .timedOut(let command):
            return "Command timed out: \(command)"
        }
    }
}

private final class LockedData {
    private let lock = NSLock()
    private var data = Data()

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    func append(_ newData: Data) {
        lock.lock()
        data.append(newData)
        lock.unlock()
    }
}
