import SwiftUI
import UserNotifications
import Foundation
import AppKit

class CodeRunner: ObservableObject {
    static let shared = CodeRunner()
    @Published var canExecuteSwift = false
    @Published var canOpenPackagify = false
    func checkSwift() async {
        let result = try? await safeShell("swift")
        if ((result?.contains("Welcome to Swift")) ?? false) {
            DispatchQueue.main.async {
                self.canExecuteSwift = true
            }
            Task {
                await sendNotification("Swift Test Completed", body: "The Swift Command was tested successfully and can be used in the Run Menu")
            }
        } else {
            DispatchQueue.main.async {
                self.canExecuteSwift = false
            }
            Task {
                await sendNotification("Swift Test Failed", body: "The Swift Command Test failed, if you don't have swift installed or do not need to use Swift you can safely ignore this Notification.")
            }

        }
    }
    func checkPackagify() {
        DispatchQueue.main.async { [self] in
            self.canOpenPackagify = checkForURLScheme(scheme: "packagify")
        }
    }
    func checkForURLScheme(scheme: String) -> Bool {
        guard let url = URL(string: "\(scheme)://") else {
            return false
        }
        return NSWorkspace.shared.urlForApplication(toOpen: url) != nil
    }
    @Published var task: Process?
    @discardableResult
    func safeShell(_ command: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            task = Process()
            let pipe = Pipe()
            
            task?.standardOutput = pipe
            task?.standardError = pipe
            task?.arguments = ["-c", command]
            task?.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task?.standardInput = nil
            
            task?.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output)
            }
            
            do {
                try task?.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
struct PackagifyView: View {
    @Binding var code: String
    @StateObject var codeRunner = CodeRunner.shared

    var body: some View {
        VStack {
            Text("Packagify your Note")
                .font(.title)
                .bold()
            Text("You can turn your Notes into Swift Packages with Packagify")
            Spacer()
            if codeRunner.canOpenPackagify {
                HStack {
                    Image(systemName: "checkmark")
                    Text("You're all set! Packagify is installed")
                }
                .foregroundStyle(.green)
                .bold()
                Button("Packagify Code") {
                    Task {
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp.swift", conformingTo: .swiftSource)
                        do {
                            try code.data(using: .utf8)?.write(to: tempURL)
                            let constructedURL = URL(string: "packagify://folder?path=\(tempURL.path(percentEncoded: true))")!
                            NSWorkspace.shared.open(constructedURL)
                        } catch {
                            CodeStickies.alert("Error Packagifying Note", description: error.localizedDescription)
                        }
                    }
                }
            } else {
                HStack {
                    Image(systemName: "xmark")
                    Text("Not ready yet! Packagify needs to be installed for this Feature to work")
                }
                .foregroundStyle(.red)
                .bold()
                HStack {
                    Button("Get Packagify") {
                        if confirm("Are you sure?", description: "This will download Packagify to your Downloads Folder") {
                            downloadAndOpenLatestPackagify()
                        }
                    }
                    Button("Check Again") {
                        codeRunner.checkPackagify()
                    }
                }
            }
        }
        .padding()
    }
}
struct RunView: View {
    let code: Binding<String?>
    @State var output: String?
    @AppStorage("runCommand") var runCommand = "swift $file"
    @State var fileExtension = "swift"
    @State var isRunning = false
    @StateObject var codeRunner = CodeRunner.shared
    var body: some View {
        Section(content: {
            HStack {
                TextField("File Extension", text: $fileExtension)
                    .textFieldStyle(.plain)
            }
            HStack {
                TextField("Command", text: $runCommand)
                    .textFieldStyle(.plain)
                Spacer()
                Button("Stop") {
                    codeRunner.task?.terminate()
                }
                .disabled(codeRunner.task == nil || !(codeRunner.task?.isRunning ?? false))
                Button("Run") {
                    Task {
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp.\(fileExtension)", conformingTo: .data)
                        do {
                            try code.wrappedValue?.data(using: .utf8)?.write(to: tempURL)
                            withAnimation() {
                                isRunning = true
                                output = nil
                            }
                            output = try await codeRunner.safeShell(runCommand.replacingOccurrences(of: "$file", with: "\"\(tempURL.path())\""))
                            withAnimation() {
                                isRunning = false
                            }
                        } catch {
                            output = error.localizedDescription
                        }
                    }
                }
                .disabled(codeRunner.task?.isRunning ?? false)
            }
        }, footer: {
            HStack {
                Text("Enter the command to use to run the provided Code, use $file to insert this Stickies Code as File\n\nExample: swift $file will be turned into swift \"\(FileManager.default.temporaryDirectory.appendingPathComponent("temp.\(fileExtension)", conformingTo: .data).path())\"\n\nTip: You can also create your own script as long as it takes the filepath as input in case you want to run more difficult workflows")
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
        })
        
        Section("Output") {
            TextEditor(text: Binding(get: {
                output ?? "Empty"
            }, set: { _ in
                
            }))
            .textEditorStyle(.plain)
            .blur(radius: isRunning ? 10 : 0)
            .overlay {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
    }
}


@discardableResult
func requestNotifications() async -> Bool {
    var result: Bool = false
    await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound, .criticalAlert]) { success, error in
        if success {
            result = true
        } else {
            result = false
        }
    }
    return result
}

func sendNotification(_ title: String, body: String, id: String? = nil, notificationRequestFailed: (() -> Void)? = nil) async {
    if await !requestNotifications() {
        notificationRequestFailed?()
    }
    let content = UNMutableNotificationContent()
    content.title = title
    content.subtitle = body
    content.sound = .none
    content.interruptionLevel = .timeSensitive

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    
    let request = UNNotificationRequest(identifier: id ?? UUID().uuidString, content: content, trigger: trigger)
    
    do {
        try await UNUserNotificationCenter.current().add(request)
    }
    
    catch { print(error.localizedDescription) }
}

import Foundation
import AppKit

func downloadAndOpenLatestPackagify() {
    let releasesAPI = "https://api.github.com/repos/timi2506/Packagify/releases/latest"
    
    // Fetch latest release JSON
    let task = URLSession.shared.dataTask(with: URL(string: releasesAPI)!) { data, _, error in
        guard let data = data, error == nil else {
            print("Failed to fetch release info:", error ?? "Unknown error")
            return
        }
        
        // Parse JSON to find the Packagify.zip URL
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]],
              let zipAsset = assets.first(where: { ($0["name"] as? String) == "Packagify.zip" }),
              let zipURLString = zipAsset["browser_download_url"] as? String,
              let zipURL = URL(string: zipURLString) else {
            print("Could not find Packagify.zip in release assets.")
            return
        }

        // Prepare destination in Downloads
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let destinationURL = downloadsURL.appendingPathComponent("Packagify.zip")

        // Download the ZIP file
        URLSession.shared.downloadTask(with: zipURL) { tempURL, _, error in
            guard let tempURL = tempURL, error == nil else {
                print("Failed to download ZIP:", error ?? "Unknown error")
                return
            }

            do {
                // Remove old file if exists
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)

                // Open the ZIP file in Finder
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(destinationURL)
                }

            } catch {
                print("Error handling downloaded ZIP:", error)
            }
        }.resume()
    }
    
    task.resume()
}
