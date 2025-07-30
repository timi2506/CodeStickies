//
//  ContentView.swift
//  CodeStickies
//
//  Created by Tim on 15.05.25.
//

import SwiftUI
import CodeEditorView
import LanguageSupport
import FoundationModels

struct ContentView: View {
    @Binding var note: Note
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @State var minimized = false
    @State var savedWindowSize: CGSize = .zero
    @State var resizing = false
    @State var resizeHeight: CGFloat = 0
    @FocusState var focused: Bool
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @State var runSheet = false
    @State var editTitle = false
    @State var showPackagify = false
    @State var aiView = false
    @State var previousText: AttributedString?
    @State var aiPrompt = ""
    @State var aiState: AIState = .idle
    @State var modelSession: LanguageModelSession = LanguageModelSession(instructions: {
        "You are a helpful AI Text Assistant inside of a macOS App called \"CodeStickies\" that allows users to create small Windows - similar to Apple's Sticky Notes - where they can write down Notes or Code. ALWAYS JUST MODIFY THE NOTE do NOT add any Comments but rather just respond with the Modified Note directly without any CodeBlocks or similar."
    })
    @State var attributedSelection = AttributedTextSelection()
    @AppStorage("noteCornerRadius") var windowCornerRadius: Int = 15
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    windowButtons(geometry: geometry)
                    
                    if editTitle {
                        TextField(note.title ?? "Untitled Note", text: Binding(get: {
                            note.title ?? ""
                        }, set: { newValue in
                            if newValue.isEmpty {
                                note.title = nil
                            } else {
                                note.title = newValue
                            }
                        }), onCommit: { editTitle.toggle() })
                        .textFieldStyle(.plain)
                        .lineLimit(1)
                    } else {
                        Text(note.title ?? "Untitled Note")
                            .lineLimit(1)
                            .foregroundStyle(.gray.opacity(0.5))
                            .onTapGesture {
                                editTitle.toggle()
                            }
                    }
                    Spacer()
                    buttons()
                }
                .padding(.horizontal, 10)
                .background(.ultraThickMaterial)
                VStack {
                    if !minimized {
                        NoteEditor(note: $note, selection: $attributedSelection)
                        if aiView {
                            GlassEffectContainer {
                                HStack {
                                    TextField("Describe Changes", text: $aiPrompt)
                                        .textFieldStyle(.plain)
                                        .padding(5)
                                        .glassEffect(in: RoundedRectangle(cornerRadius: 5))
                                    if !aiPrompt.isEmpty {
                                        Button(action: {
                                            Task {
                                                previousText = note.text
                                                aiState = .generating
                                                let session = modelSession.streamResponse(generating: GenerableNote.self, prompt: {
                                                    NotePrompt(userPrompt: aiPrompt, note: GenerableNote(text: note.text.string, title: note.title ?? "Untitled Note"))
                                                })
                                                withAnimation() {
                                                    aiPrompt = ""
                                                }
                                                do {
                                                    for try await chunk in session {
                                                        note = Note(id: note.id, text: AttributedString(chunk.text ?? ""), title: note.title, language: note.language)
                                                    }
                                                    aiState = .finished
                                                } catch {
                                                    switch error {
                                                    case LanguageModelSession.GenerationError.guardrailViolation:
                                                        aiState = .error(error: "Unsafe Content Detected")
                                                    default:
                                                        aiState = .error(error: error.localizedDescription)
                                                    }
                                                }
                                            }
                                        }) {
                                            Image(systemName: "paperplane.fill")
                                                .padding(5)
                                                .glassEffect(in: RoundedRectangle(cornerRadius: 5))
                                        }
                                        .buttonStyle(.plain)
                                        .labelStyle(.iconOnly)
                                        .disabled(aiState == .generating)
                                    } else {
                                        Button(action: {
                                            aiView = false
                                        }) {
                                            Image(systemName: "xmark")
                                                .padding(5)
                                                .glassEffect(in: RoundedRectangle(cornerRadius: 5))
                                        }
                                        .buttonStyle(.plain)
                                        .labelStyle(.iconOnly)
                                    }
                                }
                                .padding(2.5)
                            }
                            .animation(.snappy, value: aiPrompt)
                            if aiState != .idle {
                                HStack {
                                    switch aiState {
                                    case .idle:
                                        Text("Idle")
                                            .padding(.horizontal)
                                    case .generating:
                                        ProgressView().controlSize(.small)
                                            .padding(.horizontal, 5)
                                    case .finished:
                                        Text("Finished Generating")
                                            .padding(.horizontal)
                                    case .error(error: let error):
                                        Text(error)
                                            .foregroundStyle(.red)
                                            .lineLimit(1)
                                            .padding(.horizontal)
                                    }
                                    Spacer()
                                    Button("Revert Changes") {
                                        withAnimation() {
                                            if let previousText {
                                                note.text = previousText
                                                aiState = .idle
                                            }
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(aiState != .finished || previousText == nil)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(5)
                                .glassEffect(in: RoundedRectangle(cornerRadius: 5))
                                .padding(.horizontal, 2.5)
                                .animation(.snappy, value: aiState)
                            }
                        }
                    } else if resizing {
                        NoteEditor(note: $note, selection: $attributedSelection)
                            .frame(height: resizeHeight)
                    } else {
                        Rectangle()
                            .frame(width: 100, height: 1)
                            .foregroundStyle(.clear)
                    }
                }
            }
        }
        .clipShape(.rect(cornerRadius: CGFloat(windowCornerRadius)))
        .popover(isPresented: $runSheet) {
            Form {
                RunView(code: Binding(get: { note.text.string }, set: { newValue in note.text.string = newValue ?? "" }))
            }
            .formStyle(.grouped)
            .frame(minWidth: 350, minHeight: 250)
        }
        .popover(isPresented: $showPackagify) {
            PackagifyView(code: $note.text.string)
                .frame(minWidth: 500, minHeight: 250)
        }
        .onWindowAppear { window = $0 }
        
    }
    @State var window: NSWindow?
    func toggleMinimize(size: CGSize? = nil) {
        if minimized {
            resizing = true
            resizeHeight = size?.height ?? 100
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                minimized = false
                resizing = false
            }
        } else {
            resizing = true
            resizeHeight = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                minimized = true
                resizing = false
            }
        }
    }
    @AppStorage("compactMenu") var compactMenu = false
    @ViewBuilder func buttons() -> some View {
        if compactMenu {
            Menu(content: {
                LanguagePicker("Language", systemImage: "globe", selection: $note.language.config)
                    .lineLimit(1)
                if SystemLanguageModel.default.availability == .available {
                    Toggle("Apple Intelligence", systemImage: "apple.intelligence", isOn: Binding(get: {
                        aiView
                    }, set: { bool in
                        withAnimation() {
                            aiView = bool
                        }
                    }))
                }
                Button("Packagify", systemImage: "shippingbox.fill") {
                    showPackagify = true
                }
                Button("Run", systemImage: "play.fill") {
                    runSheet = true
                }
                ShareLink("Export Note", item: note.text, preview: SharePreview(note.text.string))
            }) {
                Image(systemName: "ellipsis")
                    .bold()
                    .foregroundStyle(.gray)
                    .frame(width: 15, height: 15)
                    .background(.gray.opacity(0.05))
                    .cornerRadius(2.5)
                    .padding(.vertical, 5)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .contentShape(.rect)
        } else {
            LanguagePicker("Language", selection: $note.language.config)
                .lineLimit(1)
            if SystemLanguageModel.default.availability == .available {
                Button(action: {
                    withAnimation() {
                        aiView.toggle()
                    }
                }) {
                    Image(systemName: "apple.intelligence")
                        .bold()
                        .foregroundStyle(.gray)
                        .frame(width: 15, height: 15)
                        .background(.gray.opacity(0.05))
                        .cornerRadius(2.5)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .contentShape(.rect)
            }
            Button(action: {
                showPackagify = true
            }) {
                Image(systemName: "shippingbox.fill")
                    .bold()
                    .foregroundStyle(.gray)
                    .frame(width: 15, height: 15)
                    .background(.gray.opacity(0.05))
                    .cornerRadius(2.5)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .contentShape(.rect)
            Button(action: {
                runSheet = true
            }) {
                Image(systemName: "play.fill")
                    .bold()
                    .foregroundStyle(.gray)
                    .frame(width: 15, height: 15)
                    .background(.gray.opacity(0.05))
                    .cornerRadius(2.5)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .contentShape(.rect)
            ShareLink(item: note.text, preview: SharePreview(note.text.string)) {
                Image(systemName: "square.and.arrow.up.fill")
                    .bold()
                    .foregroundStyle(.gray)
                    .frame(width: 15, height: 15)
                    .background(.gray.opacity(0.05))
                    .cornerRadius(2.5)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .contentShape(.rect)
        }
    }
    var isKey: Bool { window?.isKeyWindow == true }
    @AppStorage("alternativeWindowButtons") var alternativeWindowButtons = false
    @ViewBuilder func windowButtons(geometry: GeometryProxy) -> some View {
        if alternativeWindowButtons {
            WindowButton(isKey: isKey, color: .windowRed, systemImage: "xmark") {
                dismissWindow.callAsFunction()
            }
            .keyboardShortcut("W", modifiers: .command)
            
            WindowButton(isKey: isKey, color: .windowYellow, systemImage: "minus") {
                toggleMinimize(size: geometry.size)
            }
            .keyboardShortcut("M", modifiers: .command)
        } else {
            Button(action: {
                dismissWindow.callAsFunction()
            }) {
                Image(systemName: "xmark")
                    .bold()
                    .foregroundStyle(.gray)
                    .frame(width: 15, height: 15)
                    .background(.gray.opacity(0.05))
                    .cornerRadius(2.5)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .contentShape(.rect)
            .keyboardShortcut("W", modifiers: .command)
            Button(action: {
                toggleMinimize(size: geometry.size)
            }) {
                Image(systemName: "minus")
                    .bold()
                    .foregroundStyle(.gray)
                    .frame(width: 15, height: 15)
                    .background(.gray.opacity(0.05))
                    .cornerRadius(2.5)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .contentShape(.rect)
            .keyboardShortcut("M", modifiers: .command)
        }
    }
}

struct WindowButton: View {
    var isKey: Bool
    var color: Color
    var systemImage: String
    var action: () -> Void
    @AppStorage("States.HoveringWindowButtons") var hovering = false
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .foregroundStyle(isKey ? color : .gray.opacity(0.25))
                    .frame(width: 12.5, height: 12.5)
                if hovering {
                    Image(systemName: systemImage)
                        .font(.system(size: 7.5))
                        .fontWeight(.black)
                        .foregroundStyle(.black.opacity(0.5))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover(perform: { hovering = $0 })
    }
}

extension Color {
    static var windowRed: Color = Color(red: 1, green: 0.37, blue: 0.34)
    static var windowYellow: Color = Color(red: 1, green: 0.74, blue: 0.18)
}

struct NoteEditor: View {
    @Binding var note: Note
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    @State private var position: CodeEditor.Position = CodeEditor.Position()
    @State private var messages: Set<TextLocated<Message>> = Set()
    @Binding var selection: AttributedTextSelection
    @AppStorage("Notes.AlignmentStore") var savedAlignment = TextEditingToolbar.topTrailing.description
    @State var alignment: Alignment =  TextEditingToolbar.topTrailing.value
    @Environment(\.fontResolutionContext) var fontResolutionContext
    @State var bold = false
    @State var italic = false
    @State var size: CGFloat = 0
    @State var changeSize = false
    @State var toolbarFont: Font = .body
    var body: some View {
        VStack {
            if note.language.config == .none {
                TextEditor(text: $note.text, selection: $selection)
                    .background(.ultraThickMaterial)
            } else {
                CodeEditor(text: $note.text.string, position: $position, messages: $messages, language: $note.language.config.wrappedValue)
                    .environment(\.codeEditorTheme, colorScheme == .dark ? Theme.defaultDark : Theme.defaultLight)
                    .environment(\.codeEditorLayoutConfiguration, .init(showMinimap: false, wrapText: true))
            }
        }
        .overlay(alignment: alignment) {
            if note.language.config == .none && selection != AttributedTextSelection() {
                HStack {
                    Spacer().frame(width: 10)
                    Button(action: {
                        note.text.transformAttributes(in: &selection) { container in
                            let currentFont = container.font ?? .default
                            let resolved = currentFont.resolve(in: fontResolutionContext)
                            container.font = currentFont.bold(!resolved.isBold)
                        }
                        checkAttributes()
                    }) {
                        Image(systemName: "bold")
                            .fontWeight(bold ? .black : .thin)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .contentShape(.rect)
                    .keyboardShortcut("B", modifiers: .command)
                    .font(toolbarFont)
                    Button(action: {
                        note.text.transformAttributes(in: &selection) { container in
                            let currentFont = container.font ?? .default
                            let resolved = currentFont.resolve(in: fontResolutionContext)
                            container.font = currentFont.italic(!resolved.isItalic)
                        }
                        checkAttributes()
                    }) {
                        Image(systemName: "italic")
                            .bold(italic ? true : false)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .contentShape(.rect)
                    .keyboardShortcut("I", modifiers: .command)
                    .font(toolbarFont)
                    Button(action: {
                        changeSize.toggle()
                    }) {
                        Text(size, format: .number)
                    }
                    .buttonStyle(.plain)
                    .font(toolbarFont)
                    .popover(isPresented: $changeSize) {
                        HStack {
                            TextField("Font Size", value: Binding(get: {
                                size
                            }, set: { newValue in
                                setSize(size: newValue ?? 1)
                                checkAttributes()
                            }), format: .number)
                            Stepper(value: Binding(
                                get: { size }, set: { newValue in
                                    setSize(size: newValue)
                                    checkAttributes()
                                }
                            ), label: {
                                EmptyView().frame(width: 0, height: 0)
                            })
                        }
                        .padding()
                    }
                    Spacer().frame(width: 10)

                }
                .padding(5)
                .glassEffect(.regular.interactive(), in: .capsule)
                .contentShape(.capsule)
                .contextMenu {
                    Picker("Alignment", selection: Binding(get: {
                        TextEditingToolbar(from: alignment)
                    }, set: { newValue in
                        withAnimation() {
                            alignment = newValue.value
                        }
                    })) {
                        ForEach(TextEditingToolbar.allCases, id: \.self) { alignment in
                            Text(alignment.description)
                                .tag(alignment)
                        }
                    }
                    Picker("Size", selection: Binding(get: { ToolbarSize(from: toolbarFont) }, set: { newValue in
                        toolbarFont = newValue.font
                    })) {
                        ForEach(ToolbarSize.allCases, id: \.self) { font in
                            Text(font.fontDescription)
                                .tag(font)
                        }
                    }
                }
                .padding(5)

            }
        }
        .onChange(of: selection) {
            checkAttributes()
        }
        .onChange(of: alignment) {
            withAnimation() {
                if savedAlignment != TextEditingToolbar(from: alignment).description {
                    savedAlignment = TextEditingToolbar(from: alignment).description
                }
            }
        }
        .onChange(of: savedAlignment) {
            withAnimation() {
                if savedAlignment != TextEditingToolbar(from: alignment).description {
                    alignment = TextEditingToolbar.allCases.first(where: { $0.description == savedAlignment })?.value ?? .topTrailing
                }
            }
        }
        .onAppear {
            withAnimation() {
                if savedAlignment != TextEditingToolbar(from: alignment).description {
                    alignment = TextEditingToolbar.allCases.first(where: { $0.description == savedAlignment })?.value ?? .topTrailing
                }
            }
        }
    }
    func checkAttributes() {
        DispatchQueue.main.async {
            note.text.transformAttributes(in: &selection) { container in
                let currentFont = container.font ?? .default
                let resolved = currentFont.resolve(in: fontResolutionContext)
                bold = resolved.isBold
                italic = resolved.isItalic
                size = resolved.pointSize
            }
        }
    }
    func setSize(size: CGFloat) {
        DispatchQueue.main.async {
            note.text.transformAttributes(in: &selection) { container in
                let currentFont = container.font ?? .default
                container.font = currentFont.pointSize(size)
            }
        }
    }
    enum ToolbarSize: Hashable, CaseIterable {
        init(from font: Font) {
            switch font {
            case .body:
                    self = .body
            case .title:
                self = .title
            case .title2:
                self = .title2
            case .title3:
                self = .title3
            case .largeTitle:
                self = .largeTitle
            default:
                self = .body
            }
        }
        case body
        case title3
        case title2
        case title
        case largeTitle
        
        var font: Font {
            switch self {
            case .body:
                    .body
            case .title:
                    .title
            case .title2:
                    .title2
            case .title3:
                    .title3
            case .largeTitle:
                    .largeTitle
            }
        }
        var fontDescription: String {
            switch self {
            case .body:
                "Regular"
            case .title3:
                "Medium"
            case .title2:
                "Large"
            case .title:
                "Extra Large"
            case .largeTitle:
                "Huge"
            }
        }
    }
    enum TextEditingToolbar: Hashable, CaseIterable, Codable {
        init(from alignment: Alignment) {
            switch alignment {
            case .topLeading:
                self = .topLeading
            case .top:
                self = .top
            case .topTrailing:
                self = .topLeading
            case .bottomLeading:
                self = .bottomLeading
            case .bottom:
                self = .bottom
            case .bottomTrailing:
                self = .bottomTrailing
            default:
                self = .topTrailing
            }
            
        }
        case topLeading
        case top
        case topTrailing
        case bottomLeading
        case bottom
        case bottomTrailing
        
        var description: String {
            switch self {
            case .topLeading:
                "Top Left"
            case .top:
                "Top Center"
            case .topTrailing:
                "Top Right"
            case .bottomLeading:
                "Bottom Left"
            case .bottom:
                "Bottom Center"
            case .bottomTrailing:
                "Bottom Right"
            }
        }
        var value: Alignment {
            switch self {
            case .topLeading:
                    .topLeading
            case .top:
                    .top
            case .topTrailing:
                    .topTrailing
            case .bottomLeading:
                    .bottomLeading
            case .bottom:
                    .bottom
            case .bottomTrailing:
                    .bottomTrailing
            }
        }
    }
}

@Generable
struct NotePrompt {
    @Guide(description: "The User Prompt which you will base your response on") var userPrompt: String
    @Guide(description: "The Note to modify") var note: GenerableNote
}

struct LanguagePicker: View {
    var title: String
    var systemImage: String
    @Binding var language: LanguageConfiguration
    
    init(_ title: String, systemImage: String? = nil, selection: Binding<LanguageConfiguration>) {
        self.title = title
        self._language = selection
        self.systemImage = systemImage ?? "chevron.down"
    }
    var body: some View {
        CustomPicker(label: {
            HStack {
                Text(language.name)
                Image(systemName: systemImage)
            }
            .bold()
            .foregroundStyle(.gray)
        }, selection: $language, pickFrom: [
            CustomPickerItem(item: .none, name: "Text"),
            CustomPickerItem(item: .agda(), name: "Agda"),
            CustomPickerItem(item: .cabal(), name: "Cabal"),
            CustomPickerItem(item: .cypher(), name: "Cypher"),
            CustomPickerItem(item: .haskell(), name: "Haskell"),
            CustomPickerItem(item: .sqlite(), name: "SQLite"),
            CustomPickerItem(item: .swift(), name: "Swift")
        ])
        .menuStyle(.button)
        .buttonStyle(.plain)
    }
}

struct CustomPicker<Selection, Label: View>: View {
    let label: () -> Label
    @Binding var selection: Selection
    @State var comparableSelection: CustomPickerItem<Selection>?
    let pickFrom: [CustomPickerItem<Selection>]
    var body: some View {
        Menu(content: {
            ForEach(pickFrom) { item in
                if comparableSelection?.name == item.name {
                    Button(item.name, systemImage: "checkmark") {
                        selection = item.item
                    }
                } else {
                    Button(item.name) {
                        selection = item.item
                    }
                }
            }
        }, label: label)
    }
}

extension LanguageConfiguration: @retroactive Identifiable {
    public var id: String {
        name
    }
}

struct CustomPickerItem<CustomType>: Identifiable {
    let id = UUID()
    let item: CustomType
    let name: String
}

enum AIState: Equatable {
    case idle
    case generating
    case finished
    case error(error: String)
}

extension AttributedString {
    var string: String {
        get {
            return String(self.characters)
        }
        set {
            self = AttributedString(newValue)
        }
    }
}

struct ScaledToLayoutView<Content: View>: View {
    let scale: CGFloat
    let content: () -> Content

    var body: some View {
        GeometryReader { geo in
            content()
                .scaleEffect(scale)
                .frame(
                    width: geo.size.width * scale,
                    height: geo.size.height * scale
                )
        }
    }
}
