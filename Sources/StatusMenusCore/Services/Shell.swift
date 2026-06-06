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
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: outputData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let errorText = String(data: errorData, encoding: .utf8) ?? ""
            throw ShellError.nonZeroExit(code: process.terminationStatus, message: errorText)
        }

        return text
    }
}

public enum ShellError: Error, Equatable, CustomStringConvertible {
    case nonZeroExit(code: Int32, message: String)

    public var description: String {
        switch self {
        case .nonZeroExit(let code, let message):
            return "Command exited \(code): \(message)"
        }
    }
}
