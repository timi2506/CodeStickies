//
//  ContentView.swift
//  CodeStickies
//
//  Created by Tim on 15.05.25.
//

import SwiftUI
import SwiftUIIntrospect
import CodeEditorView
import LanguageSupport

struct ContentView: View {
    @Binding var note: Note
    @State private var position: CodeEditor.Position = CodeEditor.Position()
    @State private var messages: Set<TextLocated<Message>> = Set()
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
    var body: some View {
        VStack(spacing: 0) {
            HStack {
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
                    toggleMinimize()
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
                } else {
                    Text(note.title ?? "Untitled Note")
                        .foregroundStyle(.gray.opacity(0.5))
                        .onTapGesture {
                            editTitle.toggle()
                        }
                }
                Spacer()
                LanguagePicker("Language", selection: $note.language.config)
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
            }
            .padding(.horizontal, 10)
            .background(.ultraThickMaterial)
            if !minimized {
                CodeEditor(text: $note.text, position: $position, messages: $messages, language: $note.language.config.wrappedValue)
                    .environment(\.codeEditorTheme, colorScheme == .dark ? Theme.defaultDark : Theme.defaultLight)
                    .environment(\.codeEditorLayoutConfiguration, .init(showMinimap: false, wrapText: true))
            } else if resizing {
                CodeEditor(text: $note.text, position: $position, messages: $messages, language: $note.language.config.wrappedValue)
                    .environment(\.codeEditorTheme, colorScheme == .dark ? Theme.defaultDark : Theme.defaultLight)
                    .environment(\.codeEditorLayoutConfiguration, .init(showMinimap: false, wrapText: true))
                    .frame(height: resizeHeight)
            } else {
                Rectangle()
                    .frame(width: 100, height: 1)
                    .foregroundStyle(.clear)
            }
        }
        .popover(isPresented: $runSheet) {
            Form {
                RunView(code: Binding(get: { note.text }, set: { newValue in note.text = newValue ?? "" }))
            }
            .formStyle(.grouped)
            .frame(minWidth: 350, minHeight: 250)
        }
        .popover(isPresented: $showPackagify) {
            PackagifyView(code: $note.text)
                .frame(minWidth: 500, minHeight: 250)

        }
        
    }
    func toggleMinimize() {
        if minimized {
            resizing = true
            resizeHeight = 100
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
}

struct LanguagePicker: View {
    let title: String
    @Binding var language: LanguageConfiguration
    
    init(_ title: String, selection: Binding<LanguageConfiguration>) {
        self.title = title
        self._language = selection
    }
    var body: some View {
        CustomPicker(label: {
            HStack {
                Text(language.name)
                Image(systemName: "chevron.down")
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
                Button(action: {
                    selection = item.item
                }) {
                    HStack {
                        if comparableSelection?.name == item.name {
                            Image(systemName: "checkmark")
                        }
                        Text(item.name)
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
