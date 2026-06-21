import Foundation
import SwiftUI

@MainActor
public final class PiShellViewModel: NSObject, ObservableObject {
    @Published public private(set) var messages: [PiShellMessage] = []
    @Published public private(set) var toolEvents: [PiShellToolEvent] = []
    @Published public private(set) var currentThinking = ""
    @Published public private(set) var isGenerating = false
    @Published public private(set) var backendStatus: PiShellBackendStatus = .idle
    @Published public private(set) var selectedModel: PiShellModelOption?
    @Published public private(set) var availableModels: [PiShellModelOption] = []
    @Published public private(set) var availableCommands: [PiShellSlashCommand] = []
    @Published public private(set) var sessionStats: PiShellSessionStats?
    @Published public private(set) var backendCwd = ""
    @Published public private(set) var errorMessage = ""
    @Published public private(set) var attachments: [PiShellAttachment] = []
    @Published public var thinkingLevel = "medium"
    @Published public var settings = PiShellSettings()
    @Published public var draft = ""
    @Published public var showingSettings = false
    @Published public var thinkingExpanded = true
    @Published public var toolsExpanded = true

    private let backend: PiShellBackend
    private var didStart = false
    private static let settingsKey = "PiSwiftShell.settings.v1"

    public init(backend: PiShellBackend = AgentSessionShellBackend()) {
        let loadedSettings = Self.loadSettings()
        self.backend = backend
        self.settings = loadedSettings
        self.thinkingLevel = loadedSettings.thinkingLevel
        super.init()
        self.backend.onEvent = { [weak self] event in
            self?.handle(event)
        }
        installIntentBridge()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public var modelStatusLine: String {
        guard backendStatus == .ready else { return backendStatus.label }
        let model = selectedModel?.id ?? "no-model"
        let cwd = formatCwd(backendCwd)
        let context = formatContextIndicator(sessionStats?.contextUsage, selectedModel)
        return [cwd, context, model, thinkingLevel].filter { !$0.isEmpty }.joined(separator: " | ")
    }

    public func start() {
        guard !didStart else { return }
        didStart = true
        Task {
            thinkingLevel = settings.thinkingLevel
            await backend.start(settings: settings)
        }
    }

    public func sendDraft(behavior: PiShellStreamingBehavior? = nil) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }
        let resolvedBehavior = behavior ?? (isGenerating ? .steer : .prompt)
        if resolvedBehavior == .prompt, handleSlashCommand(text) {
            draft = ""
            return
        }
        let pendingAttachments = attachments
        draft = ""
        attachments.removeAll()
        Task {
            await backend.send(text, behavior: resolvedBehavior, attachments: pendingAttachments)
        }
    }

    public func askFromIntent(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        start()
        draft = trimmed
        sendDraft(behavior: .prompt)
    }

    public func addAttachments(_ urls: [URL]) {
        var next = attachments
        for url in urls {
            let standardized = url.standardizedFileURL
            let attachment = PiShellAttachment(path: standardized.path, name: standardized.lastPathComponent)
            if !next.contains(attachment) {
                next.append(attachment)
            }
        }
        attachments = next
    }

    public func removeAttachment(_ attachment: PiShellAttachment) {
        attachments.removeAll { $0.id == attachment.id }
    }

    public func abort() {
        isGenerating = false
        currentThinking = ""
        toolEvents.removeAll()
        Task {
            await backend.stop()
        }
    }

    public func restartBackend() {
        backendStatus = .starting
        isGenerating = false
        currentThinking = ""
        toolEvents.removeAll()
        Task {
            await backend.restart(settings: settings)
        }
    }

    public func clearVisibleHistory() {
        messages.removeAll()
        toolEvents.removeAll()
        currentThinking = ""
        errorMessage = ""
        attachments.removeAll()
        Task {
            await backend.resetSession()
        }
    }

    public func compactSession() {
        Task {
            await backend.compact()
        }
    }

    public func selectModel(_ option: PiShellModelOption) {
        selectedModel = option
        settings.model = option.id
        saveSettings()
        Task {
            await backend.setModel(option)
        }
    }

    public func setThinkingLevel(_ level: String) {
        thinkingLevel = level
        settings.thinkingLevel = level
        saveSettings()
        Task {
            await backend.setThinkingLevel(level)
        }
    }

    public func setToolsMode(_ mode: PiShellToolsMode) {
        guard settings.toolsMode != mode else { return }
        settings.toolsMode = mode
        saveSettings()
        restartBackend()
    }

    public func applySettings() {
        showingSettings = false
        saveSettings()
        Task {
            thinkingLevel = settings.thinkingLevel
            await backend.restart(settings: settings)
        }
    }

    public func refreshCommandsIfNeeded(for text: String) {
        guard text.hasPrefix("/"), availableCommands.isEmpty else { return }
        Task {
            await backend.refreshCommands()
        }
    }

    public func commandSuggestions(for text: String) -> [PiShellSlashCommand] {
        guard text.hasPrefix("/"), !text.contains("\n") else { return [] }
        let normalized = text.lowercased()
        if normalized == "/" { return Array(availableCommands.prefix(6)) }
        if normalized.hasPrefix("/thinking") || normalized.hasPrefix("/think") {
            let prefix = normalized.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
            return ["off", "minimal", "low", "medium", "high", "xhigh"]
                .filter { prefix.isEmpty || $0.hasPrefix(prefix) }
                .map { PiShellSlashCommand(key: "/thinking \($0)", name: "/thinking \($0)", description: "Set thinking level to \($0)") }
        }
        return availableCommands
            .filter {
                $0.name.lowercased().hasPrefix(normalized) ||
                    $0.description.lowercased().contains(String(normalized.dropFirst()))
            }
            .prefix(6)
            .map { $0 }
    }

    public func applySlashSuggestion(_ command: PiShellSlashCommand) {
        let source = draft
        let suffix = source.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first.map(String.init) ?? ""
        draft = command.name + (suffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? " " : " \(suffix)")
    }

    public func resetSlashQuery() {
        guard draft.hasPrefix("/") else { return }
        draft = "/"
    }

    private func handle(_ event: PiShellBackendEvent) {
        switch event {
        case .status(let status):
            backendStatus = status
            isGenerating = status == .starting ? isGenerating : isGenerating
            if status == .ready {
                errorMessage = ""
            }
        case .modelChanged(let model):
            selectedModel = model
            if !availableModels.contains(model) {
                availableModels.insert(model, at: 0)
            }
        case .thinkingChanged(let level):
            thinkingLevel = level
            settings.thinkingLevel = level
        case .models(let models):
            availableModels = models
            if selectedModel == nil {
                selectedModel = models.first
            }
        case .commands(let commands):
            availableCommands = commands
        case .sessionStats(let stats):
            sessionStats = stats
        case .cwdChanged(let cwd):
            backendCwd = cwd
        case .messageStarted(let message):
            if message.role == .assistant {
                isGenerating = true
                currentThinking = ""
                toolEvents.removeAll()
            }
            upsert(message)
        case .messageUpdated(let message):
            upsert(message)
        case .messageFinished(let message):
            upsert(PiShellMessage(
                id: message.id,
                role: message.role,
                text: message.text,
                isStreaming: false,
                isError: message.isError,
                timestamp: message.timestamp
            ))
            if message.role == .assistant {
                isGenerating = false
            }
            trimHistory()
        case .messagesRestored(let restored):
            messages = Array(restored.suffix(settings.maxHistoryLength))
        case .thinkingDelta(let delta):
            currentThinking += delta
        case .tool(let event):
            if let index = toolEvents.firstIndex(where: { $0.id == event.id }) {
                toolEvents[index] = event
            } else {
                toolEvents.append(event)
            }
        case .error(let message):
            backendStatus = .failed(message)
            errorMessage = message
            isGenerating = false
            messages.append(PiShellMessage(role: .system, text: message, isError: true))
            trimHistory()
        }
    }

    private func installIntentBridge() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleAskIntentNotification(_:)),
            name: PiShellIntentBridge.askNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleNewSessionIntentNotification(_:)),
            name: PiShellIntentBridge.newSessionNotification,
            object: nil
        )
    }

    @objc private func handleAskIntentNotification(_ notification: Notification) {
        let prompt = notification.userInfo?[PiShellIntentBridge.promptUserInfoKey] as? String ?? ""
        askFromIntent(prompt)
    }

    @objc private func handleNewSessionIntentNotification(_ notification: Notification) {
        clearVisibleHistory()
    }

    private func upsert(_ message: PiShellMessage) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else {
            messages.append(message)
        }
        trimHistory()
    }

    private func handleSlashCommand(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return false }
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let commandName = parts.first.map { String($0).lowercased() } ?? ""
        let args = parts.dropFirst().first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""

        switch commandName {
        case "/new", "/clear":
            clearVisibleHistory()
            return true
        case "/compact":
            compactSession()
            return true
        case "/session":
            Task {
                await backend.refreshSessionStats()
                appendSystemSessionSummary()
            }
            return true
        case "/name":
            guard !args.isEmpty else {
                showError("Usage: /name <session name>")
                return true
            }
            settings.sessionName = args
            saveSettings()
            Task { await backend.setSessionName(args) }
            appendAssistantNotice("Session renamed to: \(args)")
            return true
        case "/thinking", "/think":
            if args.isEmpty {
                appendAssistantNotice("Current thinking level: \(thinkingLevel)")
                return true
            }
            let allowed = ["off", "minimal", "low", "medium", "high", "xhigh"]
            guard allowed.contains(args.lowercased()) else {
                showError("Usage: /thinking <off|minimal|low|medium|high|xhigh>")
                return true
            }
            setThinkingLevel(args.lowercased())
            appendAssistantNotice("Thinking level set to: \(args.lowercased())")
            return true
        case "/model":
            appendAssistantNotice("Use the model dropdown at the top of the panel to change models.")
            return true
        default:
            return false
        }
    }

    private func appendAssistantNotice(_ text: String) {
        messages.append(PiShellMessage(role: .assistant, text: text))
        trimHistory()
    }

    private func appendSystemSessionSummary() {
        guard let sessionStats else { return }
        appendAssistantNotice("""
        Session: \(sessionStats.sessionName)
        Messages: \(sessionStats.totalMessages)
        Context: \(formatContextIndicator(sessionStats.contextUsage, selectedModel))
        """)
    }

    private func showError(_ text: String) {
        errorMessage = text
        messages.append(PiShellMessage(role: .system, text: text, isError: true))
        trimHistory()
    }

    private func trimHistory() {
        let limit = max(1, settings.maxHistoryLength)
        if messages.count > limit {
            messages = Array(messages.suffix(limit))
        }
    }

    private func formatCwd(_ value: String) -> String {
        guard !value.isEmpty else { return "" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var next = value
        if next.hasPrefix(home) {
            next = "~" + next.dropFirst(home.count)
        }
        if next.count > 28 {
            next = "..." + next.suffix(27)
        }
        return next
    }

    private func formatContextIndicator(_ usage: PiShellContextUsage?, _ model: PiShellModelOption?) -> String {
        let contextWindow = usage?.contextWindow ?? model?.contextWindow ?? 0
        guard contextWindow > 0 else { return "?/0" }
        guard let percent = usage?.percent else { return "?/\(formatTokenCount(contextWindow))" }
        return "\(String(format: "%.1f", percent))%/\(formatTokenCount(contextWindow))"
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count < 1_000 { return "\(count)" }
        if count < 10_000 { return String(format: "%.1fk", Double(count) / 1_000) }
        if count < 1_000_000 { return "\(count / 1_000)k" }
        if count < 10_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        return "\(count / 1_000_000)M"
    }

    private static func loadSettings() -> PiShellSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              var decoded = try? JSONDecoder().decode(PiShellSettings.self, from: data) else {
            return PiShellSettings()
        }
        if decoded.toolsMode == .none {
            decoded.toolsMode = .actions
        }
        return decoded
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.settingsKey)
    }
}
