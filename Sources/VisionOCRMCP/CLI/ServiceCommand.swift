import ArgumentParser
import Foundation

struct ServiceCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "service",
        abstract: "Manage the background service (LaunchAgent)",
        subcommands: [
            InstallService.self,
            UninstallService.self,
            StartService.self,
            StopService.self,
            RestartService.self,
            StatusService.self,
            LogsService.self,
        ]
    )

    static let label = "com.stelaino.vision-ocr-mcp"
    static var plistPath: String {
        "\(NSHomeDirectory())/Library/LaunchAgents/\(label).plist"
    }
    static let logStdout = "/tmp/vision-ocr-mcp.stdout.log"
    static let logStderr = "/tmp/vision-ocr-mcp.stderr.log"
}

struct InstallService: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "install", abstract: "Install as background service")

    @Option(name: .shortAndLong, help: "Port for HTTP transport")
    var port: Int = 8765

    @Option(name: .long, help: "API key for authentication")
    var apiKey: String?

    @Flag(name: .long, help: "Enable Web UI")
    var ui: Bool = false

    func run() async throws {
        let plistPath = ServiceCommand.plistPath

        guard !FileManager.default.fileExists(atPath: plistPath) else {
            throw ServiceError.alreadyInstalled
        }

        guard let execPath = Bundle.main.executablePath ?? CommandLine.arguments.first else {
            throw ServiceError.installFailed(reason: "Cannot determine executable path")
        }

        var args = [execPath, "serve", "--transport", "http", "--port", "\(port)"]
        if let apiKey {
            args += ["--api-key", apiKey]
        }
        if ui {
            args += ["--ui"]
        }

        let plist = generatePlist(label: ServiceCommand.label, args: args)

        let dir = (plistPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)

        let result = shell("launchctl", "load", plistPath)
        guard result.status == 0 else {
            throw ServiceError.installFailed(reason: result.output)
        }

        print("Service installed successfully.")
        print("  Label: \(ServiceCommand.label)")
        print("  Port: \(port)")
        print("  Plist: \(plistPath)")
        print("  Logs: \(ServiceCommand.logStdout)")
        print("\nThe service will auto-start at login.")
    }

    private func generatePlist(label: String, args: [String]) -> String {
        let argsXML = args.map { "        <string>\($0)</string>" }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
        \(argsXML)
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>\(ServiceCommand.logStdout)</string>
            <key>StandardErrorPath</key>
            <string>\(ServiceCommand.logStderr)</string>
            <key>ProcessType</key>
            <string>Background</string>
        </dict>
        </plist>
        """
    }
}

struct UninstallService: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "uninstall", abstract: "Uninstall background service")

    func run() async throws {
        let plistPath = ServiceCommand.plistPath
        guard FileManager.default.fileExists(atPath: plistPath) else {
            throw ServiceError.notInstalled
        }

        _ = shell("launchctl", "unload", plistPath)
        try FileManager.default.removeItem(atPath: plistPath)
        print("Service uninstalled successfully.")
    }
}

struct StartService: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "start", abstract: "Start the service")

    func run() async throws {
        let result = shell("launchctl", "start", ServiceCommand.label)
        guard result.status == 0 else {
            throw ServiceError.startFailed(reason: result.output)
        }
        print("Service started.")
    }
}

struct StopService: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "stop", abstract: "Stop the service")

    func run() async throws {
        let result = shell("launchctl", "stop", ServiceCommand.label)
        guard result.status == 0 else {
            throw ServiceError.stopFailed(reason: result.output)
        }
        print("Service stopped.")
    }
}

struct RestartService: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "restart", abstract: "Restart the service")

    func run() async throws {
        _ = shell("launchctl", "stop", ServiceCommand.label)
        let result = shell("launchctl", "start", ServiceCommand.label)
        guard result.status == 0 else {
            throw ServiceError.startFailed(reason: result.output)
        }
        print("Service restarted.")
    }
}

struct StatusService: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Check service status")

    func run() async throws {
        let plistPath = ServiceCommand.plistPath
        guard FileManager.default.fileExists(atPath: plistPath) else {
            print("Status: Not installed")
            return
        }

        let result = shell("launchctl", "list", ServiceCommand.label)
        if result.status == 0 {
            print("Status: Running")
            print(result.output)
        } else {
            print("Status: Installed but not running")
        }
    }
}

struct LogsService: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "logs", abstract: "View service logs")

    @Option(name: .shortAndLong, help: "Number of lines to show")
    var lines: Int = 50

    func run() async throws {
        let result = shell("tail", "-n", "\(lines)", ServiceCommand.logStdout)
        print(result.output)
    }
}

@discardableResult
func shell(_ args: String...) -> (status: Int32, output: String) {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = args
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return (-1, error.localizedDescription)
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    return (process.terminationStatus, output)
}
