import AppKit
import BrowserKit
import Combine
import SwiftUI

/// "Found in Google Drive (12)": files whose contents match in Drive, below
/// the local results and "Found inside files", drawn like them. A click
/// opens the streamed file (Drive downloads it as it opens), a folder in
/// this pane, or the file's page when it is not on this Mac.
struct DriveResultsSection: View {
    @ObservedObject var pane: PaneModel
    @ObservedObject var account: GoogleDriveAccount
    let palette: Palette
    let home: URL

    var body: some View {
        content
            .onChange(of: account.generation) { _, _ in pane.restartDriveSearch() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("nexus.search.drive")
    }

    @ViewBuilder private var content: some View {
        switch pane.drive {
        case .hidden:
            EmptyView()
        case .connect:
            VStack(spacing: 0) {
                Hairline(palette: palette)
                DriveQuietRow(symbol: "cloud", text: "Connect Google Drive to search inside your Drive files",
                              palette: palette, action: connect)
            }
        case .connecting:
            VStack(spacing: 0) {
                Hairline(palette: palette)
                DriveQuietRow(symbol: "cloud", text: "Waiting for Google in your browser", palette: palette,
                              trailing: "Cancel", action: { account.cancelConnect() })
            }
        case .searching:
            VStack(spacing: 0) {
                Hairline(palette: palette)
                header(count: nil)
            }
        case .note(let text):
            VStack(spacing: 0) {
                Hairline(palette: palette)
                DriveQuietRow(symbol: "cloud", text: text, palette: palette, action: nil)
            }
        case .results(let hits) where hits.isEmpty:
            EmptyView()
        case .results(let hits):
            VStack(spacing: 0) {
                Hairline(palette: palette)
                header(count: hits.count)
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(hits) { hit in
                            DriveHitRow(hit: hit, palette: palette, home: home) { open(hit) }
                        }
                    }
                    .padding(.bottom, 6)
                }
                .frame(height: min(CGFloat(hits.count) * DriveHitRow.height + 6, DriveHitRow.height * 6 + 6))
            }
        }
    }

    private func header(count: Int?) -> some View {
        HStack(spacing: 8) {
            Text(count.map { "Found in Google Drive (\(ItemFormat.grouped($0)))" } ?? "Searching Google Drive")
                .font(NexusType.labelMediumNumbers)
                .foregroundStyle(palette.dim)
                .lineLimit(1)
                .fixedSize()
            Hairline(palette: palette)
            if count == nil || pane.driveRefreshing {
                ProgressView().controlSize(.mini).accessibilityLabel("Searching Google Drive")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func connect() {
        if account.status == .notSetUp {
            DriveHelpSheet.present(account: account, palette: palette)
        } else {
            account.connect()
        }
    }

    private func open(_ hit: DriveHit) {
        switch hit.target {
        case .file(let path):
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .folder(let path):
            pane.go(.folder(URL(fileURLWithPath: path, isDirectory: true)))
        case .web(let url):
            NSWorkspace.shared.open(url)
        case nil:
            NSSound.beep()
        }
    }
}

/// One file found in Drive: its icon, name, where it is and when it changed.
struct DriveHitRow: View {
    static let height: CGFloat = 24
    let hit: DriveHit
    let palette: Palette
    let home: URL
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                icon
                    .frame(width: 18, height: 18)
                Text(hit.file.name)
                    .font(NexusType.body)
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                Text(place)
                    .font(NexusType.callout)
                    .foregroundStyle(palette.faint)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 8)
                if let modified = hit.file.modifiedTime {
                    Text(ItemFormat.date(modified))
                        .font(NexusType.calloutNumbers)
                        .foregroundStyle(palette.dim)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 8)
            .frame(height: Self.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(ToolbarButtonStyle(palette: palette))
        .padding(.horizontal, 4)
        .help(hit.localPath == nil ? "Open in Google Drive on the web" : hit.file.name)
        .accessibilityLabel(hit.file.name)
        .accessibilityValue(place)
        .accessibilityHint(hit.localPath == nil ? "Opens in your browser" : "Opens the file")
    }

    @ViewBuilder private var icon: some View {
        if let path = hit.localPath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .interpolation(.high)
                .accessibilityHidden(true)
        } else {
            Image(systemName: Self.symbol(for: hit.file))
                .font(NexusType.rowSymbol)
                .imageScale(.small)
                .foregroundStyle(hit.file.isFolder ? palette.accent : palette.dim)
                .accessibilityHidden(true)
        }
    }

    /// The folder it is in, as the path bar writes it, or that it is only on the web.
    private var place: String {
        guard let path = hit.localPath else { return hit.file.kindTitle + ", on the web" }
        let folder = URL(fileURLWithPath: path).deletingLastPathComponent()
        return PathSegments.editableText(for: folder, home: home)
    }

    static func symbol(for file: DriveFile) -> String {
        switch file.mimeType {
        case DriveFile.folderType: return "folder"
        case "application/vnd.google-apps.document": return "doc.text"
        case "application/vnd.google-apps.spreadsheet": return "tablecells"
        case "application/vnd.google-apps.presentation": return "rectangle.on.rectangle"
        case "application/pdf": return "doc.richtext"
        default:
            if file.mimeType.hasPrefix("image/") { return "photo" }
            if file.mimeType.hasPrefix("video/") { return "film" }
            return "doc"
        }
    }
}

/// A single quiet line in the section: connect, waiting, or a note.
struct DriveQuietRow: View {
    let symbol: String
    let text: String
    let palette: Palette
    var trailing: String?
    let action: (() -> Void)?

    var body: some View {
        let label = HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(NexusType.smallSymbol)
                .foregroundStyle(palette.faint)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(text)
                .font(NexusType.callout)
                .foregroundStyle(action == nil ? palette.faint : palette.dim)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).font(NexusType.callout).foregroundStyle(palette.accent)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .contentShape(Rectangle())

        if let action {
            Button(action: action) { label }
                .buttonStyle(ToolbarButtonStyle(palette: palette))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .accessibilityIdentifier("nexus.search.drive.connect")
        } else {
            label.padding(.horizontal, 4).padding(.vertical, 2)
        }
    }
}

/// How to let Nexus search inside Google Drive: a Desktop app OAuth client of
/// the person's own, the Drive API turned on, and the JSON saved where Nexus
/// reads it.
struct DriveHelpView: View {
    @ObservedObject var account: GoogleDriveAccount
    let palette: Palette
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Search inside Google Drive")
                .font(NexusType.title)
                .foregroundStyle(palette.strong)
            Text("Nexus asks Google Drive to search the contents of your files, so nothing is downloaded. It uses an OAuth client that you create, with read-only access.")
                .font(NexusType.body)
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                step(1, "In Google Cloud Console, create a project and enable the Google Drive API.")
                step(2, "Set up the OAuth consent screen and add your Google account as a test user.")
                step(3, "Under Credentials, create an OAuth client ID of type Desktop app and download its JSON.")
                step(4, "Save the file as ~/.config/grand-line/google-oauth.json, then choose Connect.")
            }
            Text(account.status == .notSetUp ? "No client file is saved yet." : "The client file is in place.")
                .font(NexusType.callout)
                .foregroundStyle(palette.dim)
            HStack(spacing: 8) {
                Button("Open Google Cloud Console") { NSWorkspace.shared.open(GoogleDriveAccount.consoleURL) }
                Button("Show folder") { showFolder() }
                Spacer(minLength: 8)
                Button("Done", action: close)
                    .keyboardShortcut(.cancelAction)
                Button("Connect") {
                    account.connect()
                    close()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(account.status == .notSetUp)
            }
        }
        .padding(20)
        .frame(width: 460)
        .background(palette.panel)
        .onAppear { account.reload() }
        // The file may be saved while the sheet is open.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in account.reload() }
        .accessibilityIdentifier("nexus.drive.help")
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).")
                .font(NexusType.calloutNumbers)
                .foregroundStyle(palette.dim)
                .frame(width: 16, alignment: .trailing)
            Text(text)
                .font(NexusType.callout)
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func showFolder() {
        let folder = account.configLocation.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}

@MainActor
enum DriveHelpSheet {
    /// Shows the help as a sheet on the front window (a browser window or
    /// Settings), or as its own small window when there is none.
    static func present(account: GoogleDriveAccount, palette: Palette) {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = "Search inside Google Drive"
        let parent = NSApp.keyWindow
        let close: () -> Void = { [weak panel, weak parent] in
            guard let panel else { return }
            if let parent, panel.sheetParent === parent { parent.endSheet(panel) } else { panel.close() }
        }
        panel.contentViewController = NSHostingController(rootView: DriveHelpView(account: account, palette: palette, close: close))
        if let parent, parent.attachedSheet == nil {
            parent.beginSheet(panel)
        } else {
            panel.center()
            panel.makeKeyAndOrderFront(nil)
        }
    }
}
