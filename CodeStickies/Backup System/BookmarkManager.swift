import SwiftUI
import UniformTypeIdentifiers

class BookmarkManager: ObservableObject {
    init() {
        self.selectedFolder = restoreBookmark()
    }
    static let shared = BookmarkManager()
    private let bookmarkKey = "savedFolderBookmark"
    
    @Published var selectedFolder: URL?
    
    static func selectFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder"
        
        return panel.runModal() == .OK ? panel.url : nil
    }
    
    func saveBookmark(for url: URL) {
        do {
            selectedFolder = url
            let bookmark = try url.bookmarkData(options: [.withSecurityScope],
                                                 includingResourceValuesForKeys: nil,
                                                 relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        } catch {
            print("Error creating bookmark: \(error)")
        }
    }
    
    func restoreBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data,
                              options: [.withSecurityScope],
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            if isStale {
                print("Bookmark is stale")
                return nil
            }
            
            if url.startAccessingSecurityScopedResource() {
                return url
            }
        } catch {
            print("Failed to resolve bookmark: \(error)")
        }
        
        return nil
    }
    
    func pickFolder() {
        if let url = BookmarkManager.selectFolder() {
            BookmarkManager.shared.saveBookmark(for: url)
            _ = url.startAccessingSecurityScopedResource()
        }
    }
    
    func createBackup() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        let filename = "backup_\(formatter.string(from: Date())).stickies"
        let notesToBackup = NotesManager.shared.notes
        
        if let encoded = try? encoder.encode(notesToBackup), let selectedFolder {
            do {
                try encoded.write(to: selectedFolder.appendingPathComponent(filename, conformingTo: stickiesType))
                print("Backup created successfully at: \(selectedFolder.appendingPathComponent(filename).lastPathComponent)")
            } catch {
                print("Failed to create backup: \(error.localizedDescription)")
            }
        }
    }
}
