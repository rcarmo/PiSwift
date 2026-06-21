import SwiftUI
import UniformTypeIdentifiers
import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

public struct PiShellView: View {
    @StateObject private var viewModel: PiShellViewModel

    public init(viewModel: PiShellViewModel = PiShellViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationSplitView {
            ShellSidebar(viewModel: viewModel)
                .navigationTitle("Pi")
        } detail: {
            NativeShellDetail(viewModel: viewModel)
                .navigationTitle("Pi Shell")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            viewModel.restartBackend()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Restart agent session")

                        Button {
                            #if os(macOS)
                            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                            #else
                            viewModel.showingSettings = true
                            #endif
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .help("Settings")
                    }
                }
        }
        .sheet(isPresented: $viewModel.showingSettings) {
            ShellSettingsSheet(viewModel: viewModel)
        }
        .task {
            viewModel.start()
        }
    }
}

private struct ShellSidebar: View {
    @ObservedObject var viewModel: PiShellViewModel

    var body: some View {
        List {
            Section("Session") {
                LabeledContent("State", value: viewModel.backendStatus.label)
                if let model = viewModel.selectedModel?.id {
                    LabeledContent("Model", value: model)
                }
                LabeledContent("Thinking", value: viewModel.thinkingLevel)
                if let stats = viewModel.sessionStats {
                    LabeledContent("Messages", value: "\(stats.totalMessages)")
                }
            }

            Section {
                Button {
                    viewModel.clearVisibleHistory()
                } label: {
                    Label("New Session", systemImage: "plus.message")
                }

                Button {
                    viewModel.compactSession()
                } label: {
                    Label("Compact Context", systemImage: "rectangle.compress.vertical")
                }

                Button {
                    viewModel.restartBackend()
                } label: {
                    Label("Restart Agent", systemImage: "arrow.clockwise")
                }
            }

            if !viewModel.toolEvents.isEmpty {
                Section("Tool Activity") {
                    ForEach(viewModel.toolEvents) { event in
                        Label("\(event.toolName) - \(event.status)", systemImage: event.isError ? "exclamationmark.triangle" : "terminal")
                            .foregroundStyle(event.isError ? Color.red : Color.primary)
                    }
                }
            }
        }
    }
}

private struct NativeShellDetail: View {
    @ObservedObject var viewModel: PiShellViewModel

    var body: some View {
        VStack(spacing: 0) {
            TranscriptView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            TransientActivityView(viewModel: viewModel)
                .padding(.horizontal)
                .padding(.bottom, 8)

            Divider()

            ComposerView(viewModel: viewModel)
                .padding()
        }
        .background(PiShellTheme.panelFill)
    }
}

private struct ToolbarModelPicker: View {
    @ObservedObject var viewModel: PiShellViewModel

    var body: some View {
        Picker("Model", selection: Binding(
            get: { viewModel.selectedModel?.id ?? "" },
            set: { id in
                guard let option = viewModel.availableModels.first(where: { $0.id == id }) else { return }
                viewModel.selectModel(option)
            }
        )) {
            ForEach(viewModel.availableModels) { model in
                Text(modelLabel(model)).tag(model.id)
            }
        }
        .labelsHidden()
        .frame(minWidth: 180, idealWidth: 260, maxWidth: 360)
    }

    private func modelLabel(_ model: PiShellModelOption) -> String {
        var parts = [model.id]
        if model.reasoning { parts.append("reasoning") }
        if model.contextWindow > 0 { parts.append("\(model.contextWindow / 1000)k ctx") }
        return parts.joined(separator: " - ")
    }
}

private struct ToolbarThinkingPicker: View {
    @ObservedObject var viewModel: PiShellViewModel
    private let thinkingLevels = ["off", "minimal", "low", "medium", "high", "xhigh"]

    var body: some View {
        Picker("Thinking", selection: Binding(
            get: { viewModel.thinkingLevel },
            set: { viewModel.setThinkingLevel($0) }
        )) {
            ForEach(thinkingLevels, id: \.self) { level in
                Text(level).tag(level)
            }
        }
        .labelsHidden()
        .frame(width: 120)
    }
}

private struct ShellSettingsSheet: View {
    @ObservedObject var viewModel: PiShellViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ShellSettingsSidebar(viewModel: viewModel)
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            viewModel.applySettings()
                            dismiss()
                        }
                    }
                }
        }
        .frame(minWidth: 440, minHeight: 520)
    }
}

private struct TranscriptView: View {
    @ObservedObject var viewModel: PiShellViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if viewModel.messages.isEmpty {
                        EmptyTranscriptView()
                            .frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        ForEach(viewModel.messages) { message in
                            MessageRow(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .background(PiShellTheme.panelFill)
            .onChange(of: viewModel.messages.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
            .onChange(of: viewModel.messages.last?.text) { _, _ in
                guard let id = viewModel.messages.last?.id else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }
}

private struct EmptyTranscriptView: View {
    var body: some View {
        VStack(spacing: 10) {
            PiMark()
                .scaleEffect(1.4)
            Text("Pi Assistant")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MessageRow: View {
    var message: PiShellMessage
    @State private var hovering = false
    private let userProfile = ShellUserProfile.current
    private var segments: [MessageSegment] {
        MessageSegment.build(from: message.text, role: message.role)
    }
    private var author: String {
        switch message.role {
        case .assistant: "Pi"
        case .user: userProfile.displayName
        case .system: "System"
        }
    }
    private var timestamp: String {
        message.timestamp.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(author)
                        .font(.callout.weight(.semibold))
                    Text(timestamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if message.isStreaming {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.72)
                            .frame(width: 14, height: 14)
                    }
                    Spacer(minLength: 8)
                    CopyButton(text: message.text)
                        .opacity(hovering ? 1 : 0)
                        .allowsHitTesting(hovering)
                }

                ForEach(segments) { segment in
                    switch segment.kind {
                    case .text:
                        if message.role == .assistant {
                            ShellMarkdownView(source: segment.content, isStreaming: message.isStreaming)
                                .foregroundStyle(message.isError ? Color.red : Color.primary)
                        } else {
                            Text(segment.content)
                                .font(.body)
                                .textSelection(.enabled)
                                .foregroundStyle(message.isError ? Color.red : Color.primary)
                        }
                    case .image(let source):
                        ShellImage(source: source, fallback: segment.raw)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(hovering ? PiShellTheme.messageHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var avatar: some View {
        switch message.role {
        case .assistant:
            PiMark().frame(width: 32, height: 32)
        case .user:
            if let image = userProfile.image {
                #if os(macOS)
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
                    .overlay(Circle().stroke(PiShellTheme.separator.opacity(0.45), lineWidth: 1))
                    .frame(width: 32, height: 32)
                #else
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
                    .overlay(Circle().stroke(PiShellTheme.separator.opacity(0.45), lineWidth: 1))
                    .frame(width: 32, height: 32)
                #endif
            } else {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.18))
                    Text(initials(from: userProfile.displayName))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 32, height: 32)
            }
        case .system:
            ZStack {
                Circle().fill(Color.secondary.opacity(0.18))
                Image(systemName: "info")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 32, height: 32)
        }
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let initials = parts.compactMap(\.first).map { String($0) }.joined()
        return initials.isEmpty ? "U" : initials.uppercased()
    }
}

private struct MessageSegment: Identifiable {
    enum Kind {
        case text
        case image(String)
    }

    var id = UUID()
    var kind: Kind
    var content: String
    var raw: String

    static func build(from text: String, role: PiShellRole) -> [MessageSegment] {
        guard role == .assistant, !text.isEmpty else {
            return [MessageSegment(kind: .text, content: text, raw: text)]
        }

        let pattern = #"```svg\s*\r?\n([\s\S]*?)```|<svg\b[\s\S]*?</svg>|<img\b[^>]*src\s*=\s*["']([^"']+)["'][^>]*>|!\[[^\]]*\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return [MessageSegment(kind: .text, content: text, raw: text)]
        }

        var segments: [MessageSegment] = []
        var last = text.startIndex
        let nsRange = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, options: [], range: nsRange) {
            guard let range = Range(match.range(at: 0), in: text) else { continue }
            if range.lowerBound > last {
                let before = String(text[last..<range.lowerBound])
                if !before.isEmpty {
                    segments.append(MessageSegment(kind: .text, content: before, raw: before))
                }
            }

            let raw = String(text[range])
            let source: String
            if match.range(at: 1).location != NSNotFound, let svgRange = Range(match.range(at: 1), in: text) {
                source = svgDataURI(String(text[svgRange]))
            } else if raw.lowercased().hasPrefix("<svg") {
                source = svgDataURI(raw)
            } else if match.range(at: 2).location != NSNotFound, let srcRange = Range(match.range(at: 2), in: text) {
                source = String(text[srcRange])
            } else if match.range(at: 3).location != NSNotFound, let srcRange = Range(match.range(at: 3), in: text) {
                source = String(text[srcRange])
            } else {
                source = ""
            }
            if !source.isEmpty {
                segments.append(MessageSegment(kind: .image(source), content: source, raw: raw))
            }
            last = range.upperBound
        }
        if last < text.endIndex {
            let tail = String(text[last...])
            if !tail.isEmpty {
                segments.append(MessageSegment(kind: .text, content: tail, raw: tail))
            }
        }
        return segments.isEmpty ? [MessageSegment(kind: .text, content: text, raw: text)] : segments
    }

    private static func svgDataURI(_ svg: String) -> String {
        let data = Data(svg.utf8).base64EncodedString()
        return "data:image/svg+xml;base64,\(data)"
    }
}

private struct ShellImage: View {
    var source: String
    var fallback: String
    var opensLightbox = true
    var maxDisplayHeight: CGFloat? = 360
    @State private var presented = false

    var body: some View {
        Group {
            if isSVGDataURI(source) {
                SVGDocumentView(source: source, fallback: fallback)
            } else if let image = platformImage(from: source) {
                image
                    .resizable()
                    .scaledToFit()
            } else if let url = URL(string: source) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        Text(fallback).font(.caption).textSelection(.enabled)
                    }
                }
            } else {
                Text(fallback).font(.caption).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: maxDisplayHeight)
        .padding(8)
        .background(PiShellTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: PiShellTheme.controlRadius, style: .continuous))
        .onTapGesture {
            if opensLightbox {
                presented = true
            }
        }
        .sheet(isPresented: $presented) {
            LightboxImage(source: source, fallback: fallback)
        }
    }

    private func isSVGDataURI(_ source: String) -> Bool {
        source.lowercased().hasPrefix("data:image/svg+xml")
    }

    private func platformImage(from source: String) -> Image? {
        guard source.hasPrefix("data:"), let comma = source.firstIndex(of: ",") else { return nil }
        let metadata = source[..<comma]
        let payload = source[source.index(after: comma)...]
        let data: Data?
        if metadata.contains(";base64") {
            data = Data(base64Encoded: String(payload))
        } else {
            data = String(payload).removingPercentEncoding.flatMap { Data($0.utf8) }
        }
        guard let data else { return nil }
        #if os(macOS)
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #else
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #endif
    }
}

#if os(macOS)
private struct SVGDocumentView: NSViewRepresentable {
    var source: String
    var fallback: String

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.setValue(false, forKey: "drawsBackground")
        view.loadHTMLString(html, baseURL: nil)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        view.loadHTMLString(html, baseURL: nil)
    }

    private var html: String {
        svgHTML(source: source, fallback: fallback)
    }
}
#else
private struct SVGDocumentView: UIViewRepresentable {
    var source: String
    var fallback: String

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.loadHTMLString(html, baseURL: nil)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        view.loadHTMLString(html, baseURL: nil)
    }

    private var html: String {
        svgHTML(source: source, fallback: fallback)
    }
}
#endif

private func svgHTML(source: String, fallback: String) -> String {
    let escapedFallback = fallback
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
    return """
    <!doctype html>
    <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html, body {
            margin: 0;
            width: 100%;
            height: 100%;
            background: transparent;
            overflow: hidden;
          }
          body {
            display: flex;
            align-items: center;
            justify-content: center;
          }
          img {
            max-width: 100%;
            max-height: 100%;
            object-fit: contain;
          }
        </style>
      </head>
      <body>
        <img src="\(source)" alt="\(escapedFallback)">
      </body>
    </html>
    """
}

private struct LightboxImage: View {
    var source: String
    var fallback: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.92).ignoresSafeArea()
            ShellImage(source: source, fallback: fallback, opensLightbox: false, maxDisplayHeight: nil)
                .padding(40)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding()
        }
    }
}

private struct CopyButton: View {
    var text: String

    var body: some View {
        Button {
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #else
            UIPasteboard.general.string = text
            #endif
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help("Copy")
    }
}

private struct TransientActivityView: View {
    @ObservedObject var viewModel: PiShellViewModel

    var body: some View {
        if viewModel.isGenerating && (!viewModel.currentThinking.isEmpty || !viewModel.toolEvents.isEmpty) {
            VStack(spacing: 8) {
                if !viewModel.currentThinking.isEmpty {
                    DisclosureGroup(isExpanded: $viewModel.thinkingExpanded) {
                        Text(tryAttributed(viewModel.currentThinking))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(.top, 4)
                    } label: {
                        Label("Thinking", systemImage: "brain")
                    }
                }

                if !viewModel.toolEvents.isEmpty {
                    DisclosureGroup(isExpanded: $viewModel.toolsExpanded) {
                        VStack(spacing: 6) {
                            ForEach(viewModel.toolEvents) { event in
                                HStack(alignment: .top) {
                                    Image(systemName: event.isError ? "exclamationmark.triangle" : "terminal")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(event.toolName) - \(event.status)").font(.caption.weight(.semibold))
                                        if !event.summary.isEmpty {
                                            Text(event.summary).font(.caption).foregroundStyle(.secondary)
                                        }
                                        if !event.details.isEmpty {
                                            Text(event.details)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(event.isError ? Color.red : Color.secondary)
                                                .textSelection(.enabled)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(8)
                                .background(PiShellTheme.elevated)
                                .clipShape(RoundedRectangle(cornerRadius: PiShellTheme.controlRadius, style: .continuous))
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        Label("Tool activity", systemImage: "wrench.and.screwdriver")
                    }
                }
            }
            .padding(10)
            .background(PiShellTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: PiShellTheme.controlRadius, style: .continuous))
        }
    }

    private func tryAttributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

private struct ComposerView: View {
    @ObservedObject var viewModel: PiShellViewModel
    @FocusState private var focused: Bool
    @State private var showingAttachmentPicker = false
    @State private var slashSelectionIndex = 0
    private var trimmedDraft: String {
        viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var hasInput: Bool {
        !trimmedDraft.isEmpty
    }
    private var isStopMode: Bool {
        viewModel.isGenerating && !hasInput
    }
    private var suggestions: [PiShellSlashCommand] {
        viewModel.commandSuggestions(for: viewModel.draft)
    }
    private var selectedSuggestion: PiShellSlashCommand? {
        guard !suggestions.isEmpty else { return nil }
        let index = min(max(0, slashSelectionIndex), suggestions.count - 1)
        return suggestions[index]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.errorMessage.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(viewModel.errorMessage)
                        .textSelection(.enabled)
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(Color.red)
                .padding(8)
                .background(Color.red.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: PiShellTheme.controlRadius, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                if !suggestions.isEmpty {
                    SlashSuggestions(commands: suggestions, selectedIndex: slashSelectionIndex) { index, command in
                        slashSelectionIndex = index
                        viewModel.applySlashSuggestion(command)
                        focused = true
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    TextField("Message", text: $viewModel.draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .focused($focused)
                        .font(.title3)
                        .padding(.top, 2)
                        .frame(minHeight: 30, alignment: .topLeading)
                        .onChange(of: viewModel.draft) { _, value in
                            viewModel.refreshCommandsIfNeeded(for: value)
                            if slashSelectionIndex >= suggestions.count {
                                slashSelectionIndex = max(0, suggestions.count - 1)
                            }
                        }
                        .onSubmit {
                            viewModel.sendDraft()
                        }
                        .onKeyPress(.downArrow) {
                            guard !suggestions.isEmpty else { return .ignored }
                            slashSelectionIndex = (slashSelectionIndex + 1) % suggestions.count
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            guard !suggestions.isEmpty else { return .ignored }
                            slashSelectionIndex = (slashSelectionIndex - 1 + suggestions.count) % suggestions.count
                            return .handled
                        }
                        .onKeyPress(.tab) {
                            guard let selectedSuggestion else { return .ignored }
                            viewModel.applySlashSuggestion(selectedSuggestion)
                            slashSelectionIndex = 0
                            return .handled
                        }
                        .onKeyPress(.return) {
                            guard let selectedSuggestion else { return .ignored }
                            viewModel.applySlashSuggestion(selectedSuggestion)
                            slashSelectionIndex = 0
                            return .handled
                        }
                        .onKeyPress(.escape) {
                            guard !suggestions.isEmpty else { return .ignored }
                            viewModel.resetSlashQuery()
                            slashSelectionIndex = 0
                            return .handled
                        }

                    if !viewModel.attachments.isEmpty {
                        AttachmentStrip(viewModel: viewModel)
                    }

                    composerControls
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(PiShellTheme.composerFill)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(PiShellTheme.separator.opacity(focused ? 0.55 : 0.32), lineWidth: 1)
                }
                .fileImporter(
                    isPresented: $showingAttachmentPicker,
                    allowedContentTypes: [.item],
                    allowsMultipleSelection: true
                ) { result in
                    if case .success(let urls) = result {
                        viewModel.addAttachments(urls)
                        focused = true
                    }
                }
            }
        }
    }

    private var composerControls: some View {
        HStack(spacing: 12) {
            Button {
                showingAttachmentPicker = true
                focused = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .regular))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Add attachments")

            StatusMenu(viewModel: viewModel)

            Spacer(minLength: 12)

            ModelThinkingMenu(viewModel: viewModel)

            Button {
                startDictation()
            } label: {
                Image(systemName: "mic")
                    .font(.system(size: 20, weight: .regular))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Dictate")

            Button {
                if isStopMode {
                    viewModel.abort()
                } else {
                    viewModel.sendDraft()
                }
            } label: {
                Image(systemName: isStopMode ? "stop.fill" : "arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .background {
                Circle()
                    .fill(PiShellTheme.surface)
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .help(viewModel.isGenerating ? "Stop or steer" : "Send")
        }
    }

    private func startDictation() {
        focused = true
        #if os(macOS)
        DispatchQueue.main.async {
            NSApp.sendAction(Selector(("startDictation:")), to: nil, from: nil)
        }
        #else
        UIApplication.shared.sendAction(Selector(("startDictation:")), to: nil, from: nil, for: nil)
        #endif
    }
}

private struct StatusMenu: View {
    @ObservedObject var viewModel: PiShellViewModel

    var body: some View {
        Menu {
            Section("Tools") {
                ForEach(PiShellToolsMode.allCases) { mode in
                    Button {
                        viewModel.setToolsMode(mode)
                    } label: {
                        Label(mode.label, systemImage: viewModel.settings.toolsMode == mode ? "checkmark" : "")
                    }
                }
            }

            Section("Session") {
                Button {
                    viewModel.clearVisibleHistory()
                } label: {
                    Label("New Session", systemImage: "plus.message")
                }
                Button {
                    viewModel.restartBackend()
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
                Button {
                    viewModel.compactSession()
                } label: {
                    Label("Compact", systemImage: "arrow.down.right.and.arrow.up.left")
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: statusIcon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(statusColor)
                Text(viewModel.settings.toolsMode.label)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(viewModel.backendStatus.label)
    }

    private var statusIcon: String {
        switch viewModel.backendStatus {
        case .ready: "checkmark.shield"
        case .generating: "waveform"
        case .failed: "exclamationmark.triangle"
        case .starting, .compacting, .retrying: "clock"
        case .idle: "circle"
        }
    }

    private var statusColor: Color {
        switch viewModel.backendStatus {
        case .ready: .accentColor
        case .generating: .accentColor
        case .failed: .red
        case .starting, .compacting, .retrying: .orange
        case .idle: .secondary
        }
    }
}

private struct AttachmentStrip: View {
    @ObservedObject var viewModel: PiShellViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.attachments) { attachment in
                    HStack(spacing: 6) {
                        Image(systemName: icon(for: attachment.name))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(attachment.name)
                            .font(.caption)
                            .lineLimit(1)
                        Button {
                            viewModel.removeAttachment(attachment)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(PiShellTheme.surface)
                    .clipShape(Capsule())
                }
            }
        }
    }

    private func icon(for name: String) -> String {
        let lower = name.lowercased()
        if lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".gif") || lower.hasSuffix(".webp") {
            return "photo"
        }
        if lower.hasSuffix(".pdf") {
            return "doc.richtext"
        }
        if lower.hasSuffix(".swift") || lower.hasSuffix(".js") || lower.hasSuffix(".ts") || lower.hasSuffix(".py") || lower.hasSuffix(".go") || lower.hasSuffix(".rs") {
            return "curlybraces"
        }
        return "paperclip"
    }
}

private struct ModelThinkingMenu: View {
    @ObservedObject var viewModel: PiShellViewModel
    private let thinkingLevels = ["off", "minimal", "low", "medium", "high", "xhigh"]

    var body: some View {
        Menu {
            Menu {
                ForEach(viewModel.availableModels) { model in
                    Button {
                        viewModel.selectModel(model)
                    } label: {
                        HStack {
                            Text(model.name)
                            if model.id == viewModel.selectedModel?.id {
                                Text("✓")
                            }
                        }
                    }
                }
            } label: {
                Text("Model")
            }

            Menu {
                ForEach(thinkingLevels, id: \.self) { level in
                    Button {
                        viewModel.setThinkingLevel(level)
                    } label: {
                        HStack {
                            Text(level)
                            if level == viewModel.thinkingLevel {
                                Text("✓")
                            }
                        }
                    }
                }
            } label: {
                Text("Thinking")
            }
        } label: {
            HStack(spacing: 8) {
                Text(shortModelName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(viewModel.thinkingLevel.capitalized)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help(viewModel.selectedModel?.id ?? "Select model")
    }

    private var shortModelName: String {
        guard let model = viewModel.selectedModel else { return "Model" }
        let value = model.modelId.isEmpty ? model.id : model.modelId
        return value
            .replacingOccurrences(of: "gpt-", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "claude-", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "-latest", with: "", options: [.caseInsensitive])
    }
}

private struct SlashSuggestions: View {
    var commands: [PiShellSlashCommand]
    var selectedIndex: Int
    var onSelect: (Int, PiShellSlashCommand) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                Button {
                    onSelect(index, command)
                } label: {
                    HStack(spacing: 8) {
                        Text(command.name).font(.caption.weight(.semibold))
                        Text(command.description.isEmpty ? command.source : command.description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .background(index == selectedIndex ? Color.accentColor.opacity(0.16) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(4)
        .background(PiShellTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: PiShellTheme.controlRadius, style: .continuous))
    }
}

private struct ShellSettingsSidebar: View {
    @ObservedObject var viewModel: PiShellViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Agent")
                    .font(.headline)

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                    SettingsTextFieldRow(title: "Model", text: $viewModel.settings.model, prompt: "provider/model-id")

                    GridRow {
                        SettingsLabel("Thinking")
                        Picker("Thinking", selection: $viewModel.settings.thinkingLevel) {
                            ForEach(["off", "minimal", "low", "medium", "high", "xhigh"], id: \.self) { level in
                                Text(level).tag(level)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }

                    GridRow {
                        SettingsLabel("Tools")
                        Picker("Tools", selection: $viewModel.settings.toolsMode) {
                            ForEach(PiShellToolsMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }

                    GridRow {
                        SettingsLabel("Persistent session")
                        Toggle("Keep this session across launches", isOn: $viewModel.settings.persistentSession)
                            .toggleStyle(.switch)
                    }

                    SettingsTextFieldRow(title: "Session name", text: $viewModel.settings.sessionName, prompt: "Pi Assistant")
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Conversation")
                    .font(.headline)

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                    GridRow {
                        SettingsLabel("Visible history")
                        Stepper(value: $viewModel.settings.maxHistoryLength, in: 10...500, step: 10) {
                            Text("\(viewModel.settings.maxHistoryLength) messages")
                                .frame(width: 120, alignment: .leading)
                        }
                    }
                }
            }

            Spacer(minLength: 4)

            HStack {
                Button("Clear Conversation...", role: .destructive) {
                    viewModel.clearVisibleHistory()
                }
                Spacer()
                Button("Apply Changes") {
                    viewModel.applySettings()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560, height: 390)
    }
}

private struct SettingsLabel: View {
    var title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .foregroundStyle(.secondary)
            .frame(width: 130, alignment: .trailing)
    }
}

private struct SettingsTextFieldRow: View {
    var title: String
    @Binding var text: String
    var prompt: String

    var body: some View {
        GridRow {
            SettingsLabel(title)
            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
        }
    }
}

public struct PiShellSettingsView: View {
    @ObservedObject private var viewModel: PiShellViewModel

    public init(viewModel: PiShellViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ShellSettingsSidebar(viewModel: viewModel)
    }
}
