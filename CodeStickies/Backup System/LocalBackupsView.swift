import SwiftUI
import Combine

struct LocalBackupsView: View {
    @StateObject var bookmarkManager = BookmarkManager.shared
    @State var backups: [String] = []
    @State var timer: AnyCancellable?
    @State var lastFolderModificationDate: Date?

    private let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()
    @State var previewNote: String?
    var body: some View {
        Group {
            if let selectedFolder = bookmarkManager.selectedFolder {
                Text("Selected Folder: \(selectedFolder.path(percentEncoded: false))")
                    .sheet(item: $previewNote) { note in
                        PreviewBackupView(notes: fetchNotes(url: selectedFolder.appendingPathComponent(note, conformingTo: stickiesType)))
                    }
                if backups.isEmpty {
                    Text("No backups found in this folder")
                        .padding()
                } else {
                    ForEach(backups.sorted(by: {
                        guard let date1 = filenameDateFormatter.date(from: $0.replacingOccurrences(of: "backup_", with: "").replacingOccurrences(of: ".stickies", with: "")),
                              let date2 = filenameDateFormatter.date(from: $1.replacingOccurrences(of: "backup_", with: "").replacingOccurrences(of: ".stickies", with: "")) else {
                            return false
                        }
                        return date1 > date2
                    }), id: \.self) { filename in
                        Button(action: {
                            previewNote = filename
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(filename.replacingOccurrences(of: "backup_", with: "").replacingOccurrences(of: ".stickies", with: ""))
                                        .font(.headline)
                                    Text(filename)
                                        .font(.subheadline)
                                }
                                Spacer()
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        if confirm(description: "This will delete \(offsets.count) backups and cannot be undone") {
                            var failed = 0
                            for index in offsets {
                                let itemToDelete = backups[index]
                                do {
                                    try FileManager.default.removeItem(at: selectedFolder.appendingPathComponent(itemToDelete, conformingTo: stickiesType))
                                } catch {
                                    failed += 1
                                }
                            }
                            if failed > 0 {
                                CodeStickies.alert("Failed to delete Backup(s)", description: "\(failed) Backup(s) failed to delete", style: .critical)
                            }
                        }
                    }
                }
            } else {
                Text("No folder selected. Please select a folder for backups.")
            }
        }
        .onAppear {
            fetchBackups()
            timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { _ in
                guard let currentFolder = self.bookmarkManager.selectedFolder else { return }
                let currentModificationDate = self.getFolderModificationDate(for: currentFolder)

                if currentModificationDate != self.lastFolderModificationDate {
                    self.lastFolderModificationDate = currentModificationDate
                    self.fetchBackups()
                }
            }
        }
        .onDisappear {
            timer?.cancel()
            timer = nil
        }
    }
    
    func fetchBackups() {
        self.backups = []
        
        guard let folder = bookmarkManager.selectedFolder else {
            return
        }
        
        let fileManager = FileManager.default
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            
            for fileURL in fileURLs {
                let filename = fileURL.lastPathComponent
                
                if filename.hasPrefix("backup_") && filename.hasSuffix(".stickies") {
                    self.backups.append(filename)
                }
            }
        } catch {
            print("Error reading contents of directory \(folder.lastPathComponent): \(error.localizedDescription)")
        }
    }
    
    func getFolderModificationDate(for url: URL) -> Date? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.modificationDate] as? Date
        } catch {
            print("Error getting folder modification date: \(error.localizedDescription)")
            return nil
        }
    }
    
    func fetchNotes(url: URL) -> [Note]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoded = try? JSONDecoder().decode([Note].self, from: data)
        return decoded
    }
}

struct PreviewBackupView: View {
    let notes: [Note]?
    var body: some View {
        Form {
            if let notes {
                HStack {
                    Text("Number of Notes")
                    Spacer()
                    Text(notes.count.description)
                }
                Section("Notes in This Export") {
                    ForEach(notes) { note in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(note.title ?? "Untitled Note")
                                Text(note.text.string)
                                    .lineLimit(2)
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                            }
                            Spacer()
                            Text(note.language.config.name.uppercased())
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                    }
                }
            } else {
                Text("Error Loading Backup")
            }
        }
        .formStyle(.grouped)
        .scrollIndicators(.hidden)
    }
}

extension String: @retroactive Identifiable {
    public var id: String {
        return self.appending(UUID().uuidString)
    }
}
