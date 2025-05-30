import SwiftUI
import UniformTypeIdentifiers

let stickiesType = UTType(filenameExtension: "stickies")!

struct StickiesDocument: FileDocument {

    static var readableContentTypes: [UTType] = [stickiesType]
    static var writableContentTypes: [UTType] = [stickiesType]

    var content: String

    init(content: String) {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let string = String(data: data, encoding: .utf8) {
            self.content = string
        } else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(content.utf8)
        return .init(regularFileWithContents: data)
    }
}
