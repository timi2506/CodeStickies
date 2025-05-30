import Cocoa
import Quartz
import SwiftUI
import LanguageSupport

class PreviewViewController: NSViewController, QLPreviewingController {

    private var hostingController: NSHostingController<AnyView>?

    func preparePreviewOfFile(at url: URL) async throws {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([Note].self, from: data)
        let previewSwiftUIView = PreviewSwiftUIView(notes: decoded)

        let hostingController = NSHostingController(rootView: AnyView(previewSwiftUIView))
        self.hostingController = hostingController

        addChild(hostingController)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.width, .height]
        view.addSubview(hostingController.view)
    }

    override func loadView() {
        self.view = NSView()
    }
}
import SwiftUI

struct PreviewSwiftUIView: View {
    let notes: [Note]
    var body: some View {
        Form {
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
                            Text(note.text)
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
        }
        .formStyle(.grouped)
        .scrollIndicators(.hidden)
    }
}

struct Note: Codable, Hashable, Identifiable {
    var id: UUID
    var text: String
    var title: String?
    var language: CodableLanguageConfiguration = CodableLanguageConfiguration(config: .none)
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
