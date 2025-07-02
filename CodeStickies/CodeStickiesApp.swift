//
//  CodeStickiesApp.swift
//  CodeStickies
//
//  Created by Tim on 15.05.25.
//

import SwiftUI
import LanguageSupport
import UniformTypeIdentifiers

class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var launchDate = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchDate = Date()
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            print("Received URL: \(url)")
            if url.absoluteString == "codestickies://refresh" {
                BookmarkManager.shared.createBackup()
                print(launchDate.timeIntervalSinceNow)
                if launchDate.timeIntervalSinceNow <= -1 {
                    print("Longer than 1 sec")
                } else {
                    print("Less than 1 sec")
                    exit(0)
                }
            } else {
//                importStickies(from: url)
            }
        }
    }
}

@main
struct CodeStickiesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @AppStorage("windowMode") var windowMode = 0

    init() {
        NSWindow.swizzleCanBecomeKey()
        Task {
            await CodeRunner.shared.checkSwift()
            CodeRunner.shared.checkPackagify()
        }
    }
    @StateObject var notesManager = NotesManager.shared
    @State var exportNotes = false
    @State var exportSingleNote = false
    @State var importNotes = false
    @State private var document: StickiesDocument?
    @AppStorage("showInMenuBar") var showInMenuBar = true
    var body: some Scene {
        WindowGroup(id: "main") {
            WelcomeView(titleText: .constant("CodeStickies"), menu: .constant(WelcomeMenu(content: {
                WelcomeMenuButton(title: "Import Note", image: Image(systemName: "square.and.arrow.down"), action: {
                    importNotes = true
                })
                WelcomeMenuButton(title: "Export Notes", image: Image(systemName: "square.and.arrow.up"), action: {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    if let encoded = try? encoder.encode(notesManager.notes) {
                        if let jsonString = String(data: encoded, encoding: .utf8) {
                            document = StickiesDocument(content: jsonString)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                                exportNotes = true
                            }
                        }
                    }
                })
                WelcomeMenuButton(title: "Add Note", image: Image(systemName: "plus.app"), action: {
                    createAndOpenNote()
                })
            })), emptyMessage: "No Notes", recentNotes: $notesManager.notes)
            .padding(5)
            .background(.thickMaterial)
            .background(
                WindowAccessor(callback: { window in
                    window?.isMovableByWindowBackground = true
                })
            )
            .cornerRadius(10)
            .fileExporter(
                isPresented: $exportNotes,
                document: document,
                contentType: stickiesType,
                defaultFilename: "Stickies_Export_\(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none).replacingOccurrences(of: "/", with: "-"))"
            ) { result in
                switch result {
                case .success(let url):
                    alert("Successly exported Notes", description: "Saved to: \"\(url.path(percentEncoded: false))\"", style: .informational)
                    document = nil
                case .failure(_):
                    alert("Error", description: "An Error occured exporting Notes", style: .informational)
                    document = nil
                }
            }
            .fileImporter(isPresented: $importNotes, allowedContentTypes: [stickiesType], onCompletion: { result in
                switch result {
                case .success(let url):
                    importStickies(from: url)
                case .failure:
                    alert("Error Importing", description: "An Error occured importing your Notes", style: .critical)
                }
            })
        }
        .windowStyle(.plain)
        .commands {
            TextEditingCommands()
            CommandGroup(replacing: .appVisibility, addition: {
                Button("Close Main Window") {
                    dismissWindow.callAsFunction(id: "main")
                }
                .keyboardShortcut("W", modifiers: .command)
            })
            CommandMenu("Options") {
                Button("Clear All Notes") {
                    if confirm(description: "This action cannot be undone") {
                        for note in notesManager.notes {
                            dismissWindow(id: "note", value: note.id)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            notesManager.notes = []
                        }
                    }
                }
                Button("Close All Notes") {
                    for note in notesManager.notes {
                        dismissWindow(id: "note", value: note.id)
                    }
                }
                Button("Open All Notes") {
                    for note in notesManager.notes {
                        dismissWindow(id: "note", value: note.id)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        for note in notesManager.notes {
                            openWindow(id: "note", value: note.id)
                        }
                    }
                }
                Toggle("Show Menu Bar Icon", isOn: $showInMenuBar)
            }
        }
        WindowGroup(id: "exportSingleNote", for: SingleExportNote.self) { exportNote in
            if let note = exportNote.wrappedValue {
                let document = StickiesDocument(content: note.documentContent)
                VStack {
                    Text("Exporting Note")
                        .bold()
                    ProgressView()
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(15)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
                        exportSingleNote = true
                    })
                }
                .fileExporter(
                    isPresented: $exportSingleNote,
                    document: document,
                    contentType: stickiesType,
                    defaultFilename: note.note.title ?? "Untitled Note"
                ) { result in
                    switch result {
                    case .success(let url):
                        CodeStickies.alert("Successly exported Notes", description: "Saved to: \"\(url.path(percentEncoded: false))\"", style: .informational)
                        dismissWindow(id: "exportSingleNote")
                    case .failure(_):
                        CodeStickies.alert("Error", description: "An Error occured exporting Note", style: .informational)
                        dismissWindow(id: "exportSingleNote")
                    }
                }
                .onChange(of: exportSingleNote) { new in
                    if !new {
                        dismissWindow(id: "exportSingleNote")
                    }
                }
                .onDisappear {
                    exportSingleNote = false
                }
                .background(WindowAccessor(callback: { window in
                    window?.isMovableByWindowBackground = true
                }))
            }
        }
        .windowStyle(.plain)
        .handlesExternalEvents(matching: [])
        WindowGroup(id: "note", for: UUID.self) { uuid in
            NavigationStack {
                VStack {
                    if let unwrappedUUID = uuid.wrappedValue {
                        if let binding = notesManager.binding(for: unwrappedUUID) {
                            ContentView(note: binding)
                        } else {
                            ContentView(note: createNote(with: unwrappedUUID))
                        }
                    }
                }
                
            }
            .gesture(WindowDragGesture())
            .onWindowAppear { window in
                guard let w = window else { return }
                w.styleMask.remove([.miniaturizable])
                w.standardWindowButton(.closeButton)?.isHidden = true
                w.standardWindowButton(.miniaturizeButton)?.isHidden = true
                w.standardWindowButton(.zoomButton)?.isHidden = true
                w.styleMask.remove(.titled)
                w.styleMask.remove(.closable)
                w.styleMask.remove(.miniaturizable)
                w.styleMask.insert(.borderless)
                w.styleMask.insert(.resizable)
                w.backgroundColor = .clear
                w.isMovableByWindowBackground = true
            }
        }
        // macOS 15.0, iOS unavailable, tvOS unavailable, watchOS unavailable, visionOS unavailable
        .windowManagerRole(.associated)
        // iOS 18.0, macOS 15.0, tvOS 18.0, watchOS 11.0, visionOS 2.0
        .windowLevel(windowMode == 0 ? .normal : windowMode == 1 ? .floating : windowMode == 2 ? .desktop : .automatic)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Picker("Window Level", selection: $windowMode) {
                    Text("Normal")
                        .tag(0)
                        .keyboardShortcut("W", modifiers: [.command, .option])
                    Text("Floating")
                        .tag(1)
                        .keyboardShortcut("F", modifiers: [.command, .option])
                    Text("Desktop")
                        .tag(2)
                        .keyboardShortcut("D", modifiers: [.command, .option])
                }
            }
            CommandGroup(replacing: .newItem, addition: {
                Button("New Note") {
                    createAndOpenNote()
                }
                .keyboardShortcut("N", modifiers: .command)
            })
            CommandGroup(after: .windowArrangement, addition: {
                Button("Open Note Manager") {
                    openWindow(id: "main")
                }
                .keyboardShortcut("N", modifiers: [.command, .option])
            })
        }
        .handlesExternalEvents(matching: [])
        MenuBarExtra(isInserted: $showInMenuBar, content: {
            NavigationStack {
                Form {
                    Button("Add Note", systemImage: "plus") {
                        createAndOpenNote()
                    }
                    .buttonStyle(.plain)
                    Section("Options") {
                        ScrollView(.horizontal) {
                            HStack {
                                Button("Clear All Notes") {
                                    if confirm(description: "This action cannot be undone") {
                                        for note in notesManager.notes {
                                            dismissWindow(id: "note", value: note.id)
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                            notesManager.notes = []
                                        }
                                    }
                                }
                                Button("Close All Notes") {
                                    for note in notesManager.notes {
                                        dismissWindow(id: "note", value: note.id)
                                    }
                                }
                                Button("Open All Notes") {
                                    for note in notesManager.notes {
                                        dismissWindow(id: "note", value: note.id)
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                        for note in notesManager.notes {
                                            openWindow(id: "note", value: note.id)
                                        }
                                    }
                                }
                                Button("Export Notes") {
                                    let encoder = JSONEncoder()
                                    encoder.outputFormatting = .prettyPrinted
                                    if let encoded = try? encoder.encode(notesManager.notes) {
                                        if let jsonString = String(data: encoded, encoding: .utf8) {
                                            document = StickiesDocument(content: jsonString)
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                                                exportNotes = true
                                            }
                                        }
                                    }
                                }
                                Button("Import Notes") {
                                    importNotes = true
                                }
                            }
                        }
                        Toggle("Show Menu Bar Item", isOn: $showInMenuBar)
                    }
                    Section("Notes") {
                        ForEach(notesManager.notes) { note in
                            Button(action: { openWindow(id: "note", value: note.id) }) {
                                HStack {
                                    LazyVStack(alignment: .leading) {
                                        Text(note.title ?? "Untitled Note")
                                        Text(note.text.string)
                                            .multilineTextAlignment(.leading)
                                            .foregroundStyle(.gray)
                                            .font(.caption)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Text(note.language.config.name.uppercased())
                                        .font(.caption)
                                        .foregroundStyle(.gray)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete", systemImage: "trash") {
                                    if confirm("Are you sure you want to delete \"\(note.title ?? "Untitled Note")\"", description: "This action cannot be undone") {
                                        dismissWindow(id: "note", value: note.id)
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                                            notesManager.deleteNote(with: note.id)
                                        }
                                    }
                                }
                            }
                        }
                        if notesManager.notes.isEmpty {
                            Text("No Notes yet, try creating one!")
                                .foregroundStyle(.gray)
                        }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("CodeStickies")
            }
            .scrollIndicators(.never)
        }) {
            Image(systemName: "note.text")
        }
        .menuBarExtraStyle(.window)
        Settings{ SettingsView() }
            .windowStyle(.hiddenTitleBar)
    }
    func createAndOpenNote() {
        let id = UUID()
        let result = showTextfieldAlert("Add Note", description: "Add a Descriptive Title for your Note")
        if !((result?.isEmpty) ?? true) {
            createNote(with: id, name: result)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                openWindow(id: "note", value: id)
            }
        }
        
    }
    func importStickies(from url: URL) {
        for note in notesManager.notes {
            dismissWindow(id: "note", value: note.id)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            do {
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode([Note].self, from: data)
                importAlert() { response in
                    switch response {
                    case .addDuplicates:
                        addDuplicatesImport(decoded)
                    case .cancel:
                        print("Import Cancelled")
                    case .skipDuplicates:
                        skipDuplicatesImport(decoded)
                    case .replaceExisting:
                        replaceExistingImport(decoded)
                    }
                }
            } catch {
                alert("Error Importing", description: error.localizedDescription, style: .critical)
            }
        }
    }
    func skipDuplicatesImport(_ notes: [Note]) {
        var notesToImport: [Note] = []
        var duplicates: [Note] = []
        for note in notes {
            if !notesManager.notes.contains(where: { $0.id == note.id }) {
                notesToImport.append(note)
            } else {
                duplicates.append(note)
            }
        }
        if confirm("Confirm", description: "This will import \(notesToImport.count) Note(s) (\(duplicates.count) Duplicates skipped)") {
            for note in notesToImport {
                notesManager.notes.append(note)
            }
        }
    }
    func addDuplicatesImport(_ notes: [Note]) {
        var notesToImport: [Note] = []
        for note in notes {
            if !notesManager.notes.contains(where: { $0.id == note.id }) {
                notesToImport.append(note)
            } else {
                notesToImport.append(newID(for: note))
            }
        }
        if confirm("Confirm", description: "This will import \(notesToImport.count) Note(s)") {
            for note in notesToImport {
                notesManager.notes.append(note)
            }
        }
    }
    func newID(for note: Note) -> Note {
        return Note(id: UUID(), text: note.text)
    }
    func replaceExistingImport(_ notes: [Note]) {
        if confirm("Confirm", description: "This will remove your current Notes and import \(notes.count) new Note(s)") {
            notesManager.notes = notes
        }
    }
}

@discardableResult
func createNote(with uuid: UUID? = nil, name: String? = nil) -> Binding<Note> {
    let id = uuid ?? UUID()
    if let existing = NotesManager.shared.binding(for: id) {
        return existing
    } else {
        DispatchQueue.main.async {
            NotesManager.shared.notes.append(Note(id: id, text: "NEW NOTE", title: name))
        }
        print("Created Note with ID: \(id.uuidString)")
        return NotesManager.shared.binding(for: id) ?? .constant(Note(id: UUID(), text: "", title: name))
    }
}
import FoundationModels
@Generable
struct GenerableNote {
    @Guide(description: "The Contents of the Note") var text: String
    @Guide(description: "The Title of the Note") var title: String?
}
struct Note: Codable, Hashable, Identifiable {
    var id: UUID
    var text: AttributedString
    var title: String?
    var language: CodableLanguageConfiguration = CodableLanguageConfiguration(config: .none)
}

class NotesManager: ObservableObject {
    static let shared = NotesManager()
    @Published var notes: [Note] = [] {
        didSet {
            saveNotes()
        }
    }
    init() {
        loadNotes()
    }
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public func saveNotes() {
        if let saveData = try? encoder.encode(notes) {
            UserDefaults.standard.set(saveData, forKey: "notes")
        }
    }
    public func loadNotes() {
        if let savedData = try? decoder.decode([Note].self, from: UserDefaults.standard.data(forKey: "notes") ?? Data()) {
            notes = savedData
        }
    }
}

extension NotesManager {
    func binding(for id: UUID) -> Binding<Note>? {
        guard let index = notes.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        return Binding(
            get: { self.notes[index] },
            set: { self.notes[index] = $0 }
        )
    }
    func deleteNote(with id: UUID) {
        if let index = notes.firstIndex(where: { $0.id == id }) {
            notes.remove(at: index)
        }
    }

}

import AppKit

// A helper view that gives you the NSWindow for any SwiftUI view:
struct WindowAccessor: NSViewRepresentable {
    var callback: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        // Dispatch to next runloop so that v.window is non-nil
        DispatchQueue.main.async {
            self.callback(v.window)
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) { }
}

extension View {
    func onWindowAppear(_ callback: @escaping (NSWindow?) -> Void) -> some View {
        background(WindowAccessor(callback: callback))
    }
}
import AppKit
import ObjectiveC.runtime

extension NSWindow {
    @objc func swizzled_canBecomeKey() -> Bool {
        return true
    }

    static func swizzleCanBecomeKey() {
        let originalSelector = #selector(getter: NSWindow.canBecomeKey)
        let swizzledSelector = #selector(swizzled_canBecomeKey)

        guard
            let originalMethod = class_getInstanceMethod(NSWindow.self, originalSelector),
            let swizzledMethod = class_getInstanceMethod(NSWindow.self, swizzledSelector)
        else { return }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

func showTextfieldAlert(_ title: String, description: String) -> String? {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = description

    let textField = NSTextField()
    textField.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
    alert.accessoryView = textField

    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")

    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
        return textField.stringValue
    } else {
        return nil
    }
}
func confirm(_ title: String? = nil, description: String, trueButton: String? = nil, falseButton: String? = nil) -> Bool {
    let alert = NSAlert()
    alert.messageText = title ?? "Are you sure?"
    alert.informativeText = description

    alert.addButton(withTitle: trueButton ?? "OK")
    alert.addButton(withTitle: falseButton ?? "Cancel")
    
    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
        return true
    } else {
        return false
    }
}
func importAlert(onResponse: @escaping (ImportAlertOptions) -> Void) {
    let alert = NSAlert()
    alert.messageText = "Choose an Import Method"
    alert.informativeText = "Choose what to do with the new Stickies"
    alert.addButton(withTitle: "Add Duplicates")
    alert.addButton(withTitle: "Cancel")
    alert.addButton(withTitle: "Skip Duplicates")
    alert.addButton(withTitle: "Replace Existing")

    let response = alert.runModal()
    switch response {
    case .alertFirstButtonReturn:
        onResponse(.addDuplicates)
    case .alertSecondButtonReturn:
        onResponse(.cancel)
    case .alertThirdButtonReturn:
        onResponse(.skipDuplicates)
    default:
        onResponse(.replaceExisting)
    }
}

enum ImportAlertOptions: CaseIterable {
    case addDuplicates
    case cancel
    case skipDuplicates
    case replaceExisting
    var description: String {
        switch self {
        case .addDuplicates:
            "Add Duplicates"
        case .cancel:
            "Cancel"
        case .skipDuplicates:
            "Skip Duplicates"
        case .replaceExisting:
            "Replace Existing"
        }
    }
}
func alert(_ title: String, description: String, style: NSAlert.Style? = .informational) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = description

    alert.addButton(withTitle: "OK")
    alert.alertStyle = style!
    alert.runModal()
}
enum LanguageConfigurationKind: Int, Codable {
    case none = 0
    case agda = 1
    case cabal = 2
    case cypher = 3
    case haskell = 4
    case sqlite = 5
    case swift = 6
}

struct CodableLanguageConfiguration: Codable, Hashable, Equatable {
    var config: LanguageConfiguration

    init(config: LanguageConfiguration) {
        self.config = config
    }

    enum CodingKeys: String, CodingKey {
        case kind
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let kind = Self.kind(for: config)
        try container.encode(kind, forKey: .kind)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(LanguageConfigurationKind.self, forKey: .kind)
        self.config = Self.config(for: kind)
    }

    static func == (lhs: CodableLanguageConfiguration, rhs: CodableLanguageConfiguration) -> Bool {
        return kind(for: lhs.config) == kind(for: rhs.config)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(Self.kind(for: config))
    }

    private static func kind(for config: LanguageConfiguration) -> LanguageConfigurationKind {
        switch config {
        case .none:
            return .none
        case .agda():
            return .agda
        case .cabal():
            return .cabal
        case .cypher():
            return .cypher
        case .haskell():
            return .haskell
        case .sqlite():
            return .sqlite
        case .swift():
            return .swift
        default:
            return .none
        }
    }

    private static func config(for kind: LanguageConfigurationKind) -> LanguageConfiguration {
        switch kind {
        case .none:
            return .none
        case .agda:
            return .agda()
        case .cabal:
            return .cabal()
        case .cypher:
            return .cypher()
        case .haskell:
            return .haskell()
        case .sqlite:
            return .sqlite()
        case .swift:
            return .swift()
        }
    }
}

struct SingleExportNote: Codable, Hashable {
    var documentContent: String
    var note: Note
}
