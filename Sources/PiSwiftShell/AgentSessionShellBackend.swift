import Foundation
import PiSwiftAI
import PiSwiftAgent
import PiSwiftCodingAgent

private let shellSystemPrompt = """
You are replying inside a native SwiftUI assistant app. The app renders Markdown and inline images via data: URIs where supported. For visuals, prefer Markdown images or data URI image tags. Keep responses readable in a resizable Apple app window and avoid unnecessarily large blocks of markup.
"""

@MainActor
public final class AgentSessionShellBackend: PiShellBackend, @unchecked Sendable {
    public var onEvent: ((PiShellBackendEvent) -> Void)?

    private var session: AgentSession?
    private var unsubscribe: (@Sendable () -> Void)?
    private var settings = PiShellSettings()
    private var activeAssistantMessageId: String?
    private var activeAssistantText = ""
    private var activeAssistantLastEmit = Date.distantPast
    private var activeAssistantLastEmitCount = 0
    private let streamingEmitInterval: TimeInterval = 0.12
    private let streamingEmitCharacterStride = 1_500

    public init() {}

    public func start(settings: PiShellSettings) async {
        self.settings = settings
        onEvent?(.status(.starting))
        await disposeSession()

        let options = CreateAgentSessionOptions(
            thinkingLevel: ThinkingLevel(rawValue: settings.thinkingLevel),
            sessionId: settings.persistentSession ? settings.sessionName : nil,
            systemPrompt: .builder { base in
                base + "\n\n" + shellSystemPrompt
            },
            toolNames: settings.toolsMode.toolNames,
            noTools: settings.toolsMode.noToolsMode
        )

        let result = await createAgentSession(options)
        session = result.session
        unsubscribe = result.session.subscribe { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event)
            }
        }

        if let configuredModel = parseModel(settings.model),
           let model = result.session.modelRegistry.find(configuredModel.provider, configuredModel.modelId) {
            try? await result.session.setModel(model)
        }

        let model = result.session.agent.state.model
        let thinking = result.session.agent.state.thinkingLevel.rawValue
        onEvent?(.modelChanged(PiShellModelOption(model: model)))
        onEvent?(.thinkingChanged(thinking))
        onEvent?(.status(.ready))
        onEvent?(.cwdChanged(result.session.sessionManager.getCwd()))
        await refreshModels()
        await refreshCommands()
        await refreshSessionStats()
        await restoreMessages()

        if let message = result.modelFallbackMessage, !message.isEmpty {
            onEvent?(.error(message))
        }
    }

    public func send(_ text: String, behavior: PiShellStreamingBehavior = .prompt, attachments: [PiShellAttachment] = []) async {
        guard let session else {
            onEvent?(.error("Backend is not ready."))
            return
        }
        do {
            let resolved = try resolvePrompt(text: text, attachments: attachments, includeImages: behavior == .prompt)
            switch behavior {
            case .prompt:
                try await session.prompt(resolved.text, options: resolved.options)
            case .steer:
                session.steer(resolved.text)
                onEvent?(.status(.ready))
            case .followUp:
                session.followUp(resolved.text)
                onEvent?(.status(.ready))
            }
        } catch {
            onEvent?(.error(error.localizedDescription))
        }
    }

    public func stop() async {
        await session?.abort()
        onEvent?(.status(.ready))
    }

    public func restart(settings: PiShellSettings) async {
        await disposeSession()
        await start(settings: settings)
    }

    public func resetSession() async {
        guard let session else { return }
        _ = await session.newSession(NewSessionOptions())
        session.sessionManager.appendSessionInfo(settings.sessionName)
        onEvent?(.messagesRestored([]))
        onEvent?(.status(.ready))
        await refreshSessionStats()
    }

    public func compact() async {
        guard let session else { return }
        do {
            _ = try await session.compact()
            onEvent?(.messageFinished(PiShellMessage(role: .assistant, text: "Session compacted.")))
            await refreshSessionStats()
        } catch {
            onEvent?(.error(error.localizedDescription))
        }
    }

    public func restoreMessages() async {
        guard let session else { return }
        onEvent?(.messagesRestored(session.messages.compactMap { shellMessage(from: $0, streaming: false) }))
    }

    public func refreshState() async {
        guard let session else { return }
        onEvent?(.cwdChanged(session.sessionManager.getCwd()))
        onEvent?(.modelChanged(PiShellModelOption(model: session.agent.state.model)))
        onEvent?(.thinkingChanged(session.agent.state.thinkingLevel.rawValue))
        onEvent?(.status(.ready))
    }

    public func setModel(_ option: PiShellModelOption) async {
        guard let session else { return }
        guard let model = session.modelRegistry.find(option.provider, option.modelId) else { return }
        do {
            try await session.setModel(model)
            onEvent?(.modelChanged(PiShellModelOption(model: model)))
        } catch {
            onEvent?(.error(error.localizedDescription))
        }
    }

    public func setThinkingLevel(_ level: String) async {
        guard let session else { return }
        let next = ThinkingLevel(rawValue: level) ?? .off
        session.setThinkingLevel(next)
        onEvent?(.thinkingChanged(session.agent.state.thinkingLevel.rawValue))
        await refreshSessionStats()
    }

    public func setSessionName(_ name: String) async {
        guard let session else { return }
        session.sessionManager.appendSessionInfo(name)
        settings.sessionName = name
        await refreshSessionStats()
    }

    public func refreshModels() async {
        guard let session else { return }
        let models = await session.getAvailableModels().map(PiShellModelOption.init(model:))
        onEvent?(.models(models))
    }

    public func refreshCommands() async {
        guard let session else { return }
        var commands = builtinCommands()
        commands.append(contentsOf: loadSlashCommands(LoadSlashCommandsOptions(cwd: session.sessionManager.getCwd())).map {
            PiShellSlashCommand(key: "/\($0.name)", description: $0.description, source: $0.source)
        })
        onEvent?(.commands(unique(commands)))
    }

    public func refreshSessionStats() async {
        guard let session else { return }
        let stats = session.getSessionStats()
        let usage = stats.contextUsage.map {
            PiShellContextUsage(tokens: $0.tokens, contextWindow: $0.contextWindow, percent: $0.percent)
        }
        onEvent?(.sessionStats(PiShellSessionStats(
            sessionName: session.sessionManager.getSessionName() ?? settings.sessionName,
            sessionId: stats.sessionId,
            totalMessages: stats.totalMessages,
            contextUsage: usage
        )))
    }

    private func handle(_ event: AgentSessionEvent) {
        guard case .agent(let agentEvent) = event else {
            handleSessionEvent(event)
            return
        }
        handleAgentEvent(agentEvent)
    }

    private func handleSessionEvent(_ event: AgentSessionEvent) {
        switch event {
        case .autoCompactionStart:
            onEvent?(.status(.compacting))
        case .autoCompactionEnd(let result, let aborted, _):
            if aborted {
                onEvent?(.messageFinished(PiShellMessage(role: .assistant, text: "Compaction cancelled.")))
            } else if result != nil {
                onEvent?(.messageFinished(PiShellMessage(role: .assistant, text: "Session compacted.")))
            }
            onEvent?(.status(.ready))
            Task { await refreshSessionStats() }
        case .autoRetryStart(let attempt, let maxAttempts, let delayMs, let errorMessage):
            let seconds = max(1, Int(ceil(Double(delayMs) / 1000.0)))
            let detail = errorMessage.isEmpty ? "" : ": \(errorMessage)"
            onEvent?(.status(.retrying("Retry \(attempt)/\(maxAttempts) in \(seconds)s\(detail)")))
        case .autoRetryEnd(let success, _, let finalError):
            if success {
                onEvent?(.status(.ready))
            } else if let finalError {
                onEvent?(.error(finalError))
            } else {
                onEvent?(.status(.ready))
            }
        case .agent:
            break
        }
    }

    private func handleAgentEvent(_ agentEvent: AgentEvent) {
        switch agentEvent {
        case .agentStart:
            onEvent?(.status(.generating))
        case .messageStart(let message):
            if case .assistant(let assistant) = message {
                activeAssistantMessageId = assistantId(assistant)
                activeAssistantText = text(from: assistant.content)
                activeAssistantLastEmit = Date()
                activeAssistantLastEmitCount = activeAssistantText.count
            }
            onEvent?(.messageStarted(shellMessage(from: message, streaming: message.role == "assistant")))
        case .messageUpdate(let message, let assistantEvent):
            switch assistantEvent {
            case .textDelta(_, let delta, let partial):
                activeAssistantText += delta
                emitStreamingAssistantUpdateIfNeeded(partial)
                return
            case .textEnd(_, _, let partial):
                activeAssistantText = text(from: partial.content)
                activeAssistantLastEmit = Date()
                activeAssistantLastEmitCount = activeAssistantText.count
                onEvent?(.messageUpdated(shellMessage(from: partial, text: activeAssistantText, streaming: true)))
                return
            case .thinkingDelta(_, let delta, _):
                onEvent?(.thinkingDelta(delta))
            default:
                break
            }
            onEvent?(.messageUpdated(shellMessage(from: message, streaming: message.role == "assistant")))
        case .messageEnd(let message):
            onEvent?(.messageFinished(shellMessage(from: message, streaming: false)))
            if case .assistant = message {
                activeAssistantMessageId = nil
                activeAssistantText = ""
                activeAssistantLastEmit = .distantPast
                activeAssistantLastEmitCount = 0
            }
        case .toolExecutionStart(let toolCallId, let toolName, _):
            onEvent?(.tool(PiShellToolEvent(id: toolCallId, toolName: toolName, status: "running", summary: "")))
        case .toolExecutionUpdate(let toolCallId, let toolName, let args, let partial):
            onEvent?(.tool(PiShellToolEvent(id: toolCallId, toolName: toolName, status: "running", summary: summarize(args), details: text(from: partial.content))))
        case .toolExecutionEnd(let toolCallId, let toolName, let result, let isError):
            onEvent?(.tool(PiShellToolEvent(id: toolCallId, toolName: toolName, status: isError ? "error" : "done", details: text(from: result.content), isError: isError)))
        case .agentEnd:
            onEvent?(.status(.ready))
            Task { await refreshSessionStats() }
        case .turnStart, .turnEnd:
            break
        }
    }

    private func emitStreamingAssistantUpdateIfNeeded(_ partial: AssistantMessage) {
        let now = Date()
        let countDelta = activeAssistantText.count - activeAssistantLastEmitCount
        guard now.timeIntervalSince(activeAssistantLastEmit) >= streamingEmitInterval ||
              countDelta >= streamingEmitCharacterStride else {
            return
        }
        activeAssistantLastEmit = now
        activeAssistantLastEmitCount = activeAssistantText.count
        onEvent?(.messageUpdated(shellMessage(from: partial, text: activeAssistantText, streaming: true)))
    }

    private func shellMessage(from message: AgentMessage, streaming: Bool) -> PiShellMessage {
        switch message {
        case .user(let user):
            return PiShellMessage(id: "user-\(user.timestamp)", role: .user, text: text(from: user.content), timestamp: Date(timeIntervalSince1970: TimeInterval(user.timestamp) / 1000))
        case .assistant(let assistant):
            let body = text(from: assistant.content)
            let isError = assistant.stopReason == .error || assistant.stopReason == .aborted
            return PiShellMessage(
                id: activeAssistantMessageId ?? assistantId(assistant),
                role: .assistant,
                text: isError ? (assistant.errorMessage ?? body) : body,
                isStreaming: streaming,
                isError: isError,
                timestamp: Date(timeIntervalSince1970: TimeInterval(assistant.timestamp) / 1000)
            )
        case .toolResult(let result):
            return PiShellMessage(id: "tool-\(result.toolCallId)-\(result.timestamp)", role: .system, text: text(from: result.content), isError: result.isError, timestamp: Date(timeIntervalSince1970: TimeInterval(result.timestamp) / 1000))
        case .custom(let custom):
            return PiShellMessage(id: "custom-\(custom.timestamp)", role: .system, text: custom.role, timestamp: Date(timeIntervalSince1970: TimeInterval(custom.timestamp) / 1000))
        }
    }

    private func shellMessage(from assistant: AssistantMessage, text body: String, streaming: Bool) -> PiShellMessage {
        let isError = assistant.stopReason == .error || assistant.stopReason == .aborted
        return PiShellMessage(
            id: activeAssistantMessageId ?? assistantId(assistant),
            role: .assistant,
            text: isError ? (assistant.errorMessage ?? body) : body,
            isStreaming: streaming,
            isError: isError,
            timestamp: Date(timeIntervalSince1970: TimeInterval(assistant.timestamp) / 1000)
        )
    }

    private func resolvePrompt(text: String, attachments: [PiShellAttachment], includeImages: Bool) throws -> (text: String, options: PromptOptions?) {
        guard !attachments.isEmpty else {
            return (text.isEmpty ? "Please review the attached context." : text, nil)
        }
        let result = try processFileArguments(attachments.map(\.path))
        let parts = [result.textContent, text].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let promptText = parts.isEmpty ? "Please review the attached file(s)." : parts.joined(separator: "\n\n")
        let options = includeImages && !result.imageAttachments.isEmpty ? PromptOptions(images: result.imageAttachments) : nil
        return (promptText, options)
    }

    private func assistantId(_ assistant: AssistantMessage) -> String {
        if let responseId = assistant.responseId, !responseId.isEmpty {
            return responseId
        }
        return "assistant-\(assistant.timestamp)"
    }

    private func text(from content: UserContent) -> String {
        switch content {
        case .text(let text):
            text
        case .blocks(let blocks):
            text(from: blocks)
        }
    }

    private func text(from blocks: [ContentBlock]) -> String {
        blocks.compactMap { block in
            switch block {
            case .text(let text):
                text.text
            case .thinking:
                nil
            case .image:
                "[image]"
            case .toolCall(let call):
                "Tool: \(call.name)"
            }
        }.joined(separator: "\n")
    }

    private func builtinCommands() -> [PiShellSlashCommand] {
        [
            PiShellSlashCommand(key: "/new", description: "Start a new session"),
            PiShellSlashCommand(key: "/compact", description: "Compact the current session context"),
            PiShellSlashCommand(key: "/session", description: "Show session info and context usage"),
            PiShellSlashCommand(key: "/name", description: "Set the session display name"),
            PiShellSlashCommand(key: "/thinking", description: "Set thinking level: off|minimal|low|medium|high|xhigh"),
            PiShellSlashCommand(key: "/think", description: "Alias for /thinking"),
            PiShellSlashCommand(key: "/model", description: "Use the model dropdown in the panel header"),
            PiShellSlashCommand(key: "/clear", description: "Clear visible chat history in the panel")
        ]
    }

    private func unique(_ commands: [PiShellSlashCommand]) -> [PiShellSlashCommand] {
        var seen: Set<String> = []
        return commands.filter { seen.insert($0.key).inserted }
    }

    private func summarize(_ args: [String: AnyCodable]) -> String {
        guard !args.isEmpty else { return "" }
        let object = args.mapValues(\.jsonValue)
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return object.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "\n")
        }
        return text
    }

    private func disposeSession() async {
        unsubscribe?()
        unsubscribe = nil
        await session?.abort()
        session?.dispose()
        session = nil
        activeAssistantMessageId = nil
        activeAssistantText = ""
    }

    private func parseModel(_ value: String) -> (provider: String, modelId: String)? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let slash = trimmed.firstIndex(of: "/"), slash > trimmed.startIndex else { return nil }
        let modelStart = trimmed.index(after: slash)
        guard modelStart < trimmed.endIndex else { return nil }
        return (String(trimmed[..<slash]), String(trimmed[modelStart...]))
    }
}
