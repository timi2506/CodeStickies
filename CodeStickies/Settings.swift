import SwiftUI

struct SettingsView: View {
    @AppStorage("showInMenuBar") var showInMenuBar = true

    var body: some View {
        NavigationStack {
            TabView {
                backups
                    .tabItem {
                        Label("Backups", systemImage: "cloud")
                    }
                about
                    .tabItem {
                        Label("About", systemImage: "info.circle")
                    }
            }
            .tabViewStyle(.tabBarOnly)
        }
    }
    @State var aboutSelectServiceAlert = false
    var about: some View {
        Form {
            HStack {
                Spacer()
                VStack {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140.0, height: 140.0)
                        .background {
                            Image(nsImage: NSApp.applicationIconImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 140.0, height: 140.0)
                                .blur(radius: 50)
                        }
                    Text("CodeStickies")
                        .font(.system(size: 36.0))
                        .bold()
                    
                    Spacer().frame(height: 7.0)
                    
                    Text("Version \(NSApp.currentAppVersion)")
                        .font(.system(size: 13.0))
                        .fontWeight(.light)
                        .foregroundColor(.gray)
                }
                Spacer()
            }
            SocialButton(name: "timi2506", description: "Developer") {
                aboutSelectServiceAlert = true
            }
            Section("Special Thanks") {
                SocialButton(name: "xezrunner", description: "Helping with things like swizzling NSWindow Properties and other advanced things :D", url: URL(string: "https://github.com/xezrunner")!)
                PackageButton(imageURL: nil, name: "CodeEditorView", description: "SwiftUI code editor view for iOS, visionOS, and macOS", url: URL(string: "https://github.com/mchakravarty/CodeEditorView")!)
            }
        }
        .formStyle(.grouped)
        .alert("Choose a Social Platform to check out", isPresented: $aboutSelectServiceAlert, actions: {
            Button("GitHub", image: ImageResource(name: "github", bundle: .main)) {
                NSWorkspace.shared.open(URL(string: "https://github.com/timi2506")!)
            }
            .buttonStyle(.borderedProminent)
            
            Button("Twitter", image: ImageResource(name: "twitter", bundle: .main)) {
                NSWorkspace.shared.open(URL(string: "https://x.com/timi2506")!)
            }
            .buttonStyle(.borderedProminent)

            Button("Cancel", role: .cancel) {
                aboutSelectServiceAlert = false
            }
        })
    }
    @StateObject var bookmarkManager = BookmarkManager.shared
    @StateObject var backupScheduler = BackupScheduler.shared
    @State var timeInterval: TimeInterval = 3600
    var backups: some View {
        Form {
            Section("General") {
                Picker("Time Interval", selection: $backupScheduler.timeInterval) {
                    Text("15 minutes").tag(TimeInterval(900))
                    Text("30 minutes").tag(TimeInterval(1800))
                    Text("1 hour").tag(TimeInterval(3600))
                    Text("2 hours").tag(TimeInterval(7200))
                    Text("4 hours").tag(TimeInterval(14400))
                }
                Toggle("Enable Auto Backup", isOn: $backupScheduler.isEnabled)
                    .onChange(of: backupScheduler.isEnabled) { enabled in
                        if enabled {
                            backupScheduler.enableAutoBackup()
                        } else {
                            backupScheduler.disableAutoBackup()
                        }
                    }
            }
            Section(content: {
                Button("Select Folder", systemImage: "folder") {
                    bookmarkManager.pickFolder()
                }
                .buttonStyle(.plain)
                Button("Create Backup", systemImage: "plus") {
                    bookmarkManager.createBackup()
                    CodeStickies.alert("Backup created", description: "The Backup was created and saved successfully", style: .informational)
                }
                .buttonStyle(.plain)
                NavigationLink(destination: {
                    List {
                        LocalBackupsView()
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }) {
                    Label("Created Backups", systemImage: "cloud")
                }
            }, header: {
                Text("Local Backup")
            }, footer: {
                Text("WARNING: This is an experimental feature, while it should work it needs your Mac to be unlocked while backing up.")
            })
            Section("Cloud Backup") {
                Text("Coming soon...").foregroundStyle(.gray)
            }
        }
        .formStyle(.grouped)
    }
}

struct SocialButton: View {
    init(name: String, github: String, description: String, action: @escaping () -> Void) {
        self.name = name
        self.github = github
        self.description = description
        self.action = action
    }
    init(name: String, github: String, description: String, url: URL) {
        self.name = name
        self.github = github
        self.description = description
        self.action = { NSWorkspace.shared.open(url) }
    }
    init(name: String, description: String, action: @escaping () -> Void) {
        self.name = name
        self.github = name
        self.description = description
        self.action = action
    }
    init(name: String, description: String, url: URL) {
        self.name = name
        self.github = name
        self.description = description
        self.action = { NSWorkspace.shared.open(url) }
    }
    var name: String
    var github: String
    var description: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                AsyncImage(url: URL(string: "https://avatars.githubusercontent.com/\(github)")!, content: { img in
                    img
                        .resizable()
                        .frame(width: 35, height: 35)
                        .scaledToFill()
                        .clipShape(.circle)
                }, placeholder: {
                    Image("default-pfp")
                        .resizable()
                        .frame(width: 35, height: 35)
                        .scaledToFill()
                        .clipShape(.circle)
                })
                VStack(alignment: .leading) {
                    Text(name)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                Spacer()
                Image(systemName: "person.fill")
                    .foregroundStyle(.gray)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

struct PackageButton: View {
    var imageURL: URL?
    var name: String
    var description: String
    var url: URL
    var body: some View {
        Button(action: { NSWorkspace.shared.open(url) }) {
            HStack {
                AsyncImage(url: imageURL, content: { img in
                    img
                        .resizable()
                        .frame(width: 35, height: 35)
                        .scaledToFill()
                        .clipShape(.circle)
                }, placeholder: {
                    Image("default-pfp")
                        .resizable()
                        .frame(width: 35, height: 35)
                        .scaledToFill()
                        .clipShape(.rect(cornerRadius: 5))
                })
                VStack(alignment: .leading) {
                    Text(name)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                Spacer()
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(.gray)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
