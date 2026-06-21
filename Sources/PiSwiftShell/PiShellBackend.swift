import Foundation
import PiSwiftAgent
import PiSwiftCodingAgent

@MainActor
public protocol PiShellBackend: AnyObject {
    var onEvent: ((PiShellBackendEvent) -> Void)? { get set }

    func start(settings: PiShellSettings) async
    func send(_ text: String, behavior: PiShellStreamingBehavior, attachments: [PiShellAttachment]) async
    func stop() async
    func restart(settings: PiShellSettings) async
    func resetSession() async
    func compact() async
    func restoreMessages() async
    func refreshState() async
    func setModel(_ option: PiShellModelOption) async
    func setThinkingLevel(_ level: String) async
    func setSessionName(_ name: String) async
    func refreshModels() async
    func refreshCommands() async
    func refreshSessionStats() async
}

public enum PiShellBackendEvent: Sendable {
    case status(PiShellBackendStatus)
    case modelChanged(PiShellModelOption)
    case thinkingChanged(String)
    case models([PiShellModelOption])
    case commands([PiShellSlashCommand])
    case sessionStats(PiShellSessionStats)
    case cwdChanged(String)
    case messageStarted(PiShellMessage)
    case messageUpdated(PiShellMessage)
    case messageFinished(PiShellMessage)
    case messagesRestored([PiShellMessage])
    case thinkingDelta(String)
    case tool(PiShellToolEvent)
    case error(String)
}

public extension PiShellToolsMode {
    var noToolsMode: NoToolsMode? {
        switch self {
        case .none: .all
        case .actions, .readOnly, .full: nil
        }
    }

    var toolNames: [String]? {
        switch self {
        case .none:
            nil
        case .actions:
            ["actions"]
        case .readOnly:
            ["read", "grep", "find", "ls"]
        case .full:
            ["read", "bash", "edit", "write", "grep", "find", "ls", "actions"]
        }
    }
}
