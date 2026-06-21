import Foundation
import PiSwiftAI

public enum PiShellRole: String, Sendable, Codable {
    case user
    case assistant
    case system
}

public enum PiShellToolsMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case none
    case actions
    case readOnly
    case full

    public var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "None"
        case .actions: "Actions"
        case .readOnly: "Read-only"
        case .full: "Full"
        }
    }
}

public struct PiShellSettings: Sendable, Equatable, Codable {
    public var model: String
    public var thinkingLevel: String
    public var toolsMode: PiShellToolsMode
    public var persistentSession: Bool
    public var sessionName: String
    public var scale: Double
    public var maxHistoryLength: Int

    public init(
        model: String = "",
        thinkingLevel: String = "medium",
        toolsMode: PiShellToolsMode = .actions,
        persistentSession: Bool = false,
        sessionName: String = "Pi Assistant",
        scale: Double = 1,
        maxHistoryLength: Int = 100
    ) {
        self.model = model
        self.thinkingLevel = thinkingLevel
        self.toolsMode = toolsMode
        self.persistentSession = persistentSession
        self.sessionName = sessionName
        self.scale = scale
        self.maxHistoryLength = maxHistoryLength
    }
}

public struct PiShellModelOption: Identifiable, Hashable, Sendable {
    public var id: String
    public var provider: String
    public var modelId: String
    public var name: String
    public var contextWindow: Int
    public var reasoning: Bool

    public init(model: Model) {
        self.provider = model.provider
        self.modelId = model.id
        self.id = "\(model.provider)/\(model.id)"
        self.name = id
        self.contextWindow = model.contextWindow
        self.reasoning = model.reasoning
    }

    public init(id: String, provider: String = "", modelId: String = "", name: String? = nil, contextWindow: Int = 0, reasoning: Bool = false) {
        self.id = id
        self.provider = provider
        self.modelId = modelId
        self.name = name ?? id
        self.contextWindow = contextWindow
        self.reasoning = reasoning
    }
}

public struct PiShellMessage: Identifiable, Equatable, Sendable {
    public var id: String
    public var role: PiShellRole
    public var text: String
    public var isStreaming: Bool
    public var isError: Bool
    public var timestamp: Date

    public init(
        id: String = UUID().uuidString,
        role: PiShellRole,
        text: String,
        isStreaming: Bool = false,
        isError: Bool = false,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
        self.isError = isError
        self.timestamp = timestamp
    }
}

public struct PiShellToolEvent: Identifiable, Equatable, Sendable {
    public var id: String
    public var toolName: String
    public var status: String
    public var summary: String
    public var details: String
    public var isError: Bool

    public init(id: String, toolName: String, status: String, summary: String = "", details: String = "", isError: Bool = false) {
        self.id = id
        self.toolName = toolName
        self.status = status
        self.summary = summary
        self.details = details
        self.isError = isError
    }
}

public struct PiShellAttachment: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public var path: String
    public var name: String

    public init(path: String, name: String) {
        self.path = path
        self.name = name
    }
}

public struct PiShellSlashCommand: Identifiable, Equatable, Sendable {
    public var id: String { key }
    public var key: String
    public var name: String
    public var description: String
    public var source: String

    public init(key: String, name: String? = nil, description: String = "", source: String = "builtin") {
        self.key = key
        self.name = name ?? key
        self.description = description
        self.source = source
    }
}

public struct PiShellContextUsage: Equatable, Sendable {
    public var tokens: Int?
    public var contextWindow: Int
    public var percent: Double?

    public init(tokens: Int?, contextWindow: Int, percent: Double?) {
        self.tokens = tokens
        self.contextWindow = contextWindow
        self.percent = percent
    }
}

public struct PiShellSessionStats: Equatable, Sendable {
    public var sessionName: String
    public var sessionId: String
    public var totalMessages: Int
    public var contextUsage: PiShellContextUsage?

    public init(sessionName: String, sessionId: String, totalMessages: Int, contextUsage: PiShellContextUsage?) {
        self.sessionName = sessionName
        self.sessionId = sessionId
        self.totalMessages = totalMessages
        self.contextUsage = contextUsage
    }
}

public enum PiShellStreamingBehavior: Sendable {
    case prompt
    case steer
    case followUp
}

public enum PiShellBackendStatus: Equatable, Sendable {
    case idle
    case starting
    case ready
    case generating
    case compacting
    case retrying(String)
    case failed(String)

    public var label: String {
        switch self {
        case .idle: "Idle"
        case .starting: "Starting"
        case .ready: "Ready"
        case .generating: "Generating"
        case .compacting: "Compacting"
        case .retrying(let message): message
        case .failed(let message): message
        }
    }
}
