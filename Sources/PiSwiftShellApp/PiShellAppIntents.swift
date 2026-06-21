import AppIntents
import Foundation
import PiSwiftShell

struct PiShellSessionEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Pi Shell Session")
    }
    static var defaultQuery: PiShellSessionQuery {
        PiShellSessionQuery()
    }

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static var current: PiShellSessionEntity {
        PiShellSessionEntity(id: "current", name: "Current Session")
    }
}

struct PiShellSessionQuery: EntityQuery {
    func entities(for identifiers: [PiShellSessionEntity.ID]) async throws -> [PiShellSessionEntity] {
        identifiers.map { identifier in
            identifier == PiShellSessionEntity.current.id
                ? .current
                : PiShellSessionEntity(id: identifier, name: identifier)
        }
    }

    func suggestedEntities() async throws -> [PiShellSessionEntity] {
        [.current]
    }
}

struct AskPiShellIntent: AppIntent {
    static var title: LocalizedStringResource { "Ask Pi Shell" }
    static var description: IntentDescription {
        IntentDescription("Send a prompt to the current Pi Shell agent session.")
    }
    static var openAppWhenRun: Bool { true }
    static var isDiscoverable: Bool { true }

    @Parameter(title: "Prompt")
    var prompt: String

    @Parameter(title: "Session", default: PiShellSessionEntity.current)
    var session: PiShellSessionEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Ask Pi Shell \(\.$prompt)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(
            name: PiShellIntentBridge.askNotification,
            object: nil,
            userInfo: [PiShellIntentBridge.promptUserInfoKey: prompt]
        )
        return .result(dialog: "Sent to Pi Shell")
    }
}

struct NewPiShellSessionIntent: AppIntent {
    static var title: LocalizedStringResource { "Start New Pi Shell Session" }
    static var description: IntentDescription {
        IntentDescription("Clear the visible chat and start a fresh Pi Shell agent session.")
    }
    static var openAppWhenRun: Bool { true }
    static var isDiscoverable: Bool { true }

    static var parameterSummary: some ParameterSummary {
        Summary("Start a new Pi Shell session")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: PiShellIntentBridge.newSessionNotification, object: nil)
        return .result(dialog: "Started a new Pi Shell session")
    }
}

struct OpenPiShellIntent: AppIntent {
    static var title: LocalizedStringResource { "Open Pi Shell" }
    static var description: IntentDescription {
        IntentDescription("Open Pi Shell.")
    }
    static var openAppWhenRun: Bool { true }
    static var isDiscoverable: Bool { true }

    static var parameterSummary: some ParameterSummary {
        Summary("Open Pi Shell")
    }

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct PiShellShortcutsProvider: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .blue }

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskPiShellIntent(),
            phrases: [
                "Ask \(.applicationName) \(\.$prompt)",
                "Tell \(.applicationName) \(\.$prompt)",
            ],
            shortTitle: "Ask Pi",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: NewPiShellSessionIntent(),
            phrases: [
                "Start a new session in \(.applicationName)",
                "New \(.applicationName) session",
            ],
            shortTitle: "New Session",
            systemImageName: "plus.message"
        )
        AppShortcut(
            intent: OpenPiShellIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Show \(.applicationName)",
            ],
            shortTitle: "Open Pi",
            systemImageName: "pi"
        )
    }
}
