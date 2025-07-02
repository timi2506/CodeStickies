import Foundation
import AppKit
import Combine

class BackupScheduler: ObservableObject {
    static let shared = BackupScheduler()
    
    private let agentLabel = "com.timi2506.codestickies-backup"
    private let fileManager = FileManager.default

    @Published var timeInterval: TimeInterval? {
        didSet {
            guard let interval = timeInterval else { return }
            updateTimeInterval(interval)
            if !isEnabled {
                enableAutoBackup()
            }
        }
    }
    
    @Published var isEnabled: Bool = false
    var timer: Timer?
    private var appSupportDirectory: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodeStickies")
    }

    private var scriptURL: URL {
        appSupportDirectory.appendingPathComponent("refresh.sh")
    }

    private var plistURL: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    private init() {
        refreshState()
    }

    func refreshState() {
        timeInterval = readCurrentInterval()
        isEnabled = checkIfEnabled()
    }

    func enableAutoBackup() {
        guard let interval = timeInterval else { return }
        do {
            timer?.invalidate()
            timer = nil
            timer = Timer.scheduledTimer(withTimeInterval: timeInterval ?? 3600, repeats: true, block: {_ in
                NSWorkspace.shared.open(URL(string: "codestickies://refresh")!)
            })
            try fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
            print(Bundle.main.bundleURL)
            let scriptSource = Bundle.main.bundleURL.appendingPathComponent("Contents").appendingPathComponent("Resources").appendingPathComponent("refresh.sh")
            print(scriptSource)
            guard fileManager.fileExists(atPath: scriptSource.path) else {
                print("refresh.sh not found in project root")
                return
            }

            try? fileManager.removeItem(at: scriptURL)
            try fileManager.copyItem(at: scriptSource, to: scriptURL)
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            let plist = generatePlist(interval: interval)
            let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try plistData.write(to: plistURL)

            _ = try? runLaunchctl(arguments: ["unload", plistURL.path])
            _ = try runLaunchctl(arguments: ["load", plistURL.path])

            isEnabled = true
            print("Auto-backup enabled")
        } catch {
            print("Failed to enable auto-backup: \(error)")
            isEnabled = false
        }
    }

    func disableAutoBackup() {
        do {
            timer?.invalidate()
            timer = nil
            _ = try? runLaunchctl(arguments: ["unload", plistURL.path])
            try? fileManager.removeItem(at: plistURL)
            try? fileManager.removeItem(at: scriptURL)
            isEnabled = false
            print("Auto-backup disabled and cleaned up.")
        } catch {
            print("Failed to disable auto-backup: \(error)")
        }
    }

    private func updateTimeInterval(_ interval: TimeInterval) {
        guard isEnabled else { return }
        do {
            timer?.invalidate()
            timer = nil
            timer = Timer.scheduledTimer(withTimeInterval: timeInterval ?? 3600, repeats: true, block: {_ in
                NSWorkspace.shared.open(URL(string: "codestickies://refresh")!)
            })
            let plist = generatePlist(interval: interval)
            let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try plistData.write(to: plistURL)

            _ = try? runLaunchctl(arguments: ["unload", plistURL.path])
            _ = try runLaunchctl(arguments: ["load", plistURL.path])

            print("Auto-backup interval updated to \(interval) seconds")
        } catch {
            print("Failed to update auto-backup interval: \(error)")
        }
    }

    private func readCurrentInterval() -> TimeInterval? {
        guard fileManager.fileExists(atPath: plistURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: plistURL)
            if let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
               let interval = plist["StartInterval"] as? Int {
                return TimeInterval(interval)
            }
        } catch {
            print("Failed to read current interval: \(error)")
        }
        return nil
    }

    private func checkIfEnabled() -> Bool {
        do {
            let output = try runLaunchctl(arguments: ["list"])
            return output.contains(agentLabel)
        } catch {
            print("Failed to check auto-backup status: \(error)")
            return false
        }
    }

    private func generatePlist(interval: TimeInterval) -> [String: Any] {
        [
            "Label": agentLabel,
            "ProgramArguments": [scriptURL.path],
            "StartInterval": Int(interval),
            "RunAtLoad": true,
            "StandardOutPath": "/tmp/codestickies.backup.log",
            "StandardErrorPath": "/tmp/codestickies.backup.err"
        ]
    }

    @discardableResult
    private func runLaunchctl(arguments: [String]) throws -> String {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        try task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
