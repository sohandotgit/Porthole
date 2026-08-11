//
//  AtlantisTrafficListView.swift
//  atlantis
//

#if canImport(SwiftUI)
import SwiftUI

/// Shim. The Traffic List roadmap replaces both call sites; until then these keep
/// `AtlantisTrafficListView` compiling with theme-sourced color.
enum AtlantisPalette {
    static func statusColor(statusCode: Int?, hasError: Bool) -> Color {
        Color(AtlantisSyntaxTheme.statusDeep(
            AtlantisStatusFamily(statusCode: statusCode, hasError: hasError)))
    }

    /// The overview colors the method badge by status family, not by verb. The list view
    /// still wants a per-verb hue; it gets the neutral label color until its own roadmap.
    static func methodColor(_ method: String) -> Color {
        Color(AtlantisSyntaxTheme.labelHeading)
    }
}

struct AtlantisPathHost {
    let primary: String
    let host: String

    init(url: String) {
        guard let components = URLComponents(string: url) else {
            primary = url
            host = ""
            return
        }
        var path = components.path
        if let query = components.query, !query.isEmpty {
            path += "?" + query
        }
        primary = path.isEmpty ? url : path
        host = components.host ?? ""
    }
}

struct AtlantisTrafficRowView: View {
    let package: TrafficPackage

    private var pathHost: AtlantisPathHost { AtlantisPathHost(url: package.request.url) }
    private var hasError: Bool { package.error != nil }
    private var typeBadge: String? {
        if package.packageType == .websocket { return "WS" }
        if package.response?.isServerSentEventStream == true { return "SSE" }
        return nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(package.request.method)
                        .font(.caption.bold())
                        .foregroundColor(AtlantisPalette.methodColor(package.request.method))
                    if let typeBadge = typeBadge {
                        Text(typeBadge)
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                    }
                    if hasError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                    }
                    Spacer()
                    Text(statusText)
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .background(AtlantisPalette.statusColor(statusCode: package.response?.statusCode, hasError: hasError))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }
                Text(pathHost.primary)
                    .font(.body)
                    .lineLimit(1)
                Text(pathHost.host)
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    Text(AtlantisFormat.duration(startAt: package.startAt, endAt: package.endAt))
                    Text(AtlantisFormat.bytes(package.responseBodyData.count))
                    Text(AtlantisFormat.time(package.startAt))
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
        .listRowBackground(hasError ? Color.red.opacity(0.08) : Color.clear)
    }

    private var statusText: String {
        guard let statusCode = package.response?.statusCode else { return "—" }
        return "\(statusCode)"
    }
}

/// Observable list of captured traffic — filterable, pausable, exportable. The host
/// embeds this inside its own `NavigationView`/`NavigationStack`.
public struct AtlantisTrafficListView: View {

    @ObservedObject private var store: AtlantisTrafficStore
    @State private var query: String = ""
    @State private var errorsOnly: Bool = false
    @State private var showsClearConfirmation = false
    @State private var showsShareSheet = false
    @State private var exportedHARURL: URL?

    public init(store: AtlantisTrafficStore = Atlantis.trafficStore) {
        self.store = store
    }

    private var filteredPackages: [TrafficPackage] {
        AtlantisTrafficFilter.apply(store.packages, query: query, errorsOnly: errorsOnly).reversed()
    }

    public var body: some View {
        List {
            ForEach(filteredPackages, id: \.id) { package in
                NavigationLink(destination: AtlantisTrafficDetailView(package: package)) {
                    AtlantisTrafficRowView(package: package)
                }
            }
            .onDelete(perform: delete)
        }
        .searchable(text: $query)
        .toolbar {
            ToolbarItemGroup {
                Toggle("Errors only", isOn: $errorsOnly)
                Button {
                    showsClearConfirmation = true
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                Button {
                    store.isPaused.toggle()
                } label: {
                    Label(store.isPaused ? "Resume" : "Pause",
                          systemImage: store.isPaused ? "play.fill" : "pause.fill")
                }
                Button {
                    exportHAR()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
        .confirmationDialog("Clear all traffic?", isPresented: $showsClearConfirmation, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { store.clear() }
            Button("Cancel", role: .cancel) {}
        }
        #if os(iOS) || targetEnvironment(macCatalyst)
        .sheet(isPresented: $showsShareSheet) {
            if let exportedHARURL = exportedHARURL {
                AtlantisShareSheet(activityItems: [exportedHARURL])
            }
        }
        #endif
    }

    private func delete(at offsets: IndexSet) {
        let displayed = filteredPackages
        for offset in offsets {
            store.remove(displayed[offset])
        }
    }

    private func exportHAR() {
        let data = store.exportHAR()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlantis-traffic-\(Int(Date().timeIntervalSince1970))")
            .appendingPathExtension("har")
        do {
            try data.write(to: url)
        } catch {
            return
        }
        #if os(iOS) || targetEnvironment(macCatalyst)
        exportedHARURL = url
        showsShareSheet = true
        #elseif os(macOS)
        AtlantisMacExport.presentSavePanel(for: url)
        #endif
    }
}

#if os(iOS) || targetEnvironment(macCatalyst)
import UIKit

struct AtlantisShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(x: controller.view.bounds.midX,
                                         y: controller.view.bounds.midY,
                                         width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#elseif os(macOS)
import AppKit

enum AtlantisMacExport {
    static func presentSavePanel(for temporaryFileURL: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = temporaryFileURL.lastPathComponent
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.copyItem(at: temporaryFileURL, to: destination)
        }
    }
}
#endif
#endif
