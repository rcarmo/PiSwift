import Foundation
import PiSwiftAI
import PiSwiftAgent

#if os(macOS)
import AppKit
import ApplicationServices
import CoreServices
#endif

enum ActionsToolError: LocalizedError, Sendable {
    case operationAborted
    case unsupportedPlatform
    case missingShortcutName
    case missingActionName
    case missingAXTarget
    case accessibilityPermissionRequired
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .operationAborted:
            return "Operation aborted"
        case .unsupportedPlatform:
            return "App action discovery is currently available on macOS only."
        case .missingShortcutName:
            return "Missing shortcut name or identifier."
        case .missingActionName:
            return "Missing accessibility action name."
        case .missingAXTarget:
            return "Missing accessibility target reference."
        case .accessibilityPermissionRequired:
            return "Accessibility permission is required. Enable this app in System Settings > Privacy & Security > Accessibility."
        case let .processFailed(message):
            return message
        }
    }
}

private struct DiscoveredAction: Encodable {
    var source: String
    var identifier: String
    var title: String
    var summary: String?
    var description: String?
    var category: String?
    var parameters: [DiscoveredParameter]
    var isDiscoverable: Bool?
    var openAppWhenRun: Bool?
    var canTriggerDirectly: Bool
    var triggerMode: String
    var triggerNote: String
}

private struct DiscoveredParameter: Encodable {
    var name: String
    var title: String?
    var type: String?
    var optional: Bool?
    var input: Bool?
}

private struct DiscoveredApp: Encodable {
    var name: String
    var bundleIdentifier: String?
    var processIdentifier: Int32
    var bundlePath: String?
    var actions: [DiscoveredAction]
}

private struct ActionsDiscoveryResult: Encodable {
    var apps: [DiscoveredApp]
    var appCount: Int
    var actionCount: Int
    var note: String
}

private struct ShortcutRunResult: Encodable {
    var shortcut: String
    var runner: String
    var exitCode: Int32
    var output: String
}

private struct ShortcutListItem: Encodable {
    var name: String
    var identifier: String?
}

private struct ShortcutListResult: Encodable {
    var shortcuts: [ShortcutListItem]
    var total: Int
    var returned: Int
    var truncated: Bool
    var note: String
}

#if os(macOS)
private struct AccessibilityActionTarget: Encodable {
    var appName: String
    var bundleIdentifier: String?
    var processIdentifier: Int32
    var targetRef: String
    var role: String?
    var title: String?
    var identifier: String?
    var description: String?
    var actions: [AccessibilityAction]
}

private struct AccessibilityAction: Encodable {
    var name: String
    var description: String?
}

private struct AccessibilityActionsResult: Encodable {
    var targets: [AccessibilityActionTarget]
    var targetCount: Int
    var actionCount: Int
    var note: String
}

private struct AccessibilityRunResult: Encodable {
    var appName: String
    var bundleIdentifier: String?
    var processIdentifier: Int32
    var targetRef: String
    var action: String
    var result: String
}

private struct AppInspectionResult: Encodable {
    var apps: [InspectedApp]
    var appCount: Int
    var note: String
}

private struct InspectedApp: Encodable {
    var name: String
    var bundleIdentifier: String?
    var processIdentifier: Int32
    var bundlePath: String?
    var isActive: Bool
    var isHidden: Bool
    var activationPolicy: String
    var accessibilityTrusted: Bool
    var focusedWindowTitle: String?
    var mainWindowTitle: String?
    var openDocuments: [String]
    var windows: [InspectedWindow]
}

private struct InspectedWindow: Encodable {
    var source: String
    var windowId: Int?
    var title: String?
    var role: String?
    var subrole: String?
    var document: String?
    var isOnScreen: Bool?
    var isMinimized: Bool?
    var bounds: WindowBounds?
}

private struct WindowBounds: Encodable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}
#endif

public func createActionsTool(cwd: String) -> AgentTool {
    AgentTool(
        label: "actions",
        name: "actions",
        description: "Inspect running apps and windows, discover App Intents metadata, run user Shortcuts, and invoke Apple Accessibility actions exposed by running app UI elements.",
        parameters: [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "operation": [
                    "type": "string",
                    "description": "Operation to perform: inspect_app, discover, list_running_apps, list_shortcuts, run_shortcut, list_ax_actions, perform_ax_action. Discovered AppIntent identifiers are not valid run_shortcut names unless the user has created a Shortcut for them.",
                    "enum": ["inspect_app", "discover", "list_running_apps", "list_shortcuts", "run_shortcut", "list_ax_actions", "perform_ax_action"],
                ],
                "app": ["type": "string", "description": "Optional app name or bundle identifier filter. inspect_app defaults to the frontmost app when omitted."],
                "include_undiscoverable": ["type": "boolean", "description": "Include App Intents marked as not discoverable."],
                "include_legacy": ["type": "boolean", "description": "Include legacy .intentdefinition SiriKit intents."],
                "limit": ["type": "number", "description": "Maximum number of shortcuts, actions per app, or accessibility targets to return. Defaults to a bounded result."],
                "app_limit": ["type": "number", "description": "Maximum number of apps to return from discovery. Defaults to a bounded result unless verbose is true."],
                "verbose": ["type": "boolean", "description": "Return larger raw discovery/listing output. Default false; agents should summarize instead of echoing raw tool output."],
                "name": ["type": "string", "description": "Shortcut name or identifier for run_shortcut."],
                "target": ["type": "string", "description": "Accessibility targetRef returned by list_ax_actions."],
                "action": ["type": "string", "description": "Accessibility action name returned by list_ax_actions, such as AXPress."],
                "max_depth": ["type": "number", "description": "Maximum accessibility tree depth for list_ax_actions."],
                "max_targets": ["type": "number", "description": "Maximum accessibility targets for list_ax_actions."],
                "input": ["type": "string", "description": "Optional text input passed to the shortcut via a temporary input file."],
                "input_path": ["type": "string", "description": "Optional file path passed to the shortcut with --input-path."],
                "output_path": ["type": "string", "description": "Optional output path passed to the shortcut with --output-path."],
            ]),
        ]
    ) { _, params, signal, _ in
        if signal?.isCancelled == true {
            throw ActionsToolError.operationAborted
        }

        let operation = params["operation"]?.value as? String ?? "discover"
        let verbose = boolValue(params["verbose"]) ?? false
        let output: String
        switch operation {
        case "inspect_app":
            #if os(macOS)
            let appFilter = params["app"]?.value as? String
            let limit = intValue(params["limit"]) ?? (verbose ? 100 : 20)
            output = try inspectApps(appFilter: appFilter, windowLimit: limit)
            #else
            throw ActionsToolError.unsupportedPlatform
            #endif
        case "discover":
            #if os(macOS)
            let appFilter = params["app"]?.value as? String
            let includeUndiscoverable = boolValue(params["include_undiscoverable"]) ?? false
            let includeLegacy = boolValue(params["include_legacy"]) ?? true
            let limit = intValue(params["limit"]) ?? (verbose ? Int.max : 8)
            let appLimit = intValue(params["app_limit"]) ?? (verbose ? Int.max : 8)
            output = try discoverRunningAppActions(
                appFilter: appFilter,
                includeUndiscoverable: includeUndiscoverable,
                includeLegacy: includeLegacy,
                limit: limit,
                appLimit: appLimit
            )
            #else
            throw ActionsToolError.unsupportedPlatform
            #endif
        case "list_running_apps":
            #if os(macOS)
            output = try encodePretty(listRunningApps(limit: intValue(params["limit"]) ?? (verbose ? Int.max : 50)))
            #else
            throw ActionsToolError.unsupportedPlatform
            #endif
        case "list_shortcuts":
            output = try encodePretty(listShortcuts(limit: intValue(params["limit"]) ?? (verbose ? Int.max : 30)))
        case "run_shortcut":
            guard let name = params["name"]?.value as? String, !name.isEmpty else {
                throw ActionsToolError.missingShortcutName
            }
            let input = params["input"]?.value as? String
            let inputPath = params["input_path"]?.value as? String
            let outputPath = params["output_path"]?.value as? String
            let result = try runShortcut(name: name, input: input, inputPath: inputPath, outputPath: outputPath, cwd: cwd)
            output = try encodePretty(result)
        case "list_ax_actions":
            #if os(macOS)
            let appFilter = params["app"]?.value as? String
            let maxDepth = intValue(params["max_depth"]) ?? 8
            let maxTargets = intValue(params["max_targets"]) ?? intValue(params["limit"]) ?? 200
            output = try discoverAccessibilityActions(appFilter: appFilter, maxDepth: maxDepth, maxTargets: maxTargets)
            #else
            throw ActionsToolError.unsupportedPlatform
            #endif
        case "perform_ax_action":
            #if os(macOS)
            guard let target = params["target"]?.value as? String, !target.isEmpty else {
                throw ActionsToolError.missingAXTarget
            }
            guard let action = params["action"]?.value as? String, !action.isEmpty else {
                throw ActionsToolError.missingActionName
            }
            output = try encodePretty(performAccessibilityAction(targetRef: target, action: action))
            #else
            throw ActionsToolError.unsupportedPlatform
            #endif
        default:
            throw ActionsToolError.processFailed("Unknown actions operation: \(operation)")
        }

        return AgentToolResult(content: [.text(TextContent(text: output.isEmpty ? "(no output)" : output))])
    }
}

#if os(macOS)
private func listRunningApps() -> [[String: AnyEncodableValue]] {
    listRunningApps(limit: Int.max)
}

private func listRunningApps(limit: Int) -> [[String: AnyEncodableValue]] {
    NSWorkspace.shared.runningApplications
        .filter { $0.bundleURL != nil }
        .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        .prefix(max(0, limit))
        .map { app in
            [
                "name": AnyEncodableValue(app.localizedName ?? ""),
                "bundleIdentifier": AnyEncodableValue(app.bundleIdentifier ?? ""),
                "processIdentifier": AnyEncodableValue(app.processIdentifier),
                "bundlePath": AnyEncodableValue(app.bundleURL?.path ?? ""),
            ]
        }
}

private func inspectApps(appFilter: String?, windowLimit: Int) throws -> String {
    let apps = matchingRunningApps(appFilter: appFilter, defaultToFrontmost: true)
    let axTrusted = isAccessibilityTrusted(prompt: false)
    let inspected = apps.map {
        inspectApp($0, windowLimit: max(0, windowLimit), accessibilityTrusted: axTrusted)
    }
    let result = AppInspectionResult(
        apps: inspected,
        appCount: inspected.count,
        note: axTrusted
            ? "CoreGraphics reports visible windows; Accessibility adds focused/main window, document, role, subrole, and minimized state where the app exposes them."
            : "CoreGraphics reports visible windows. Enable Accessibility permission for this app to read focused windows, open document URLs, AX roles, and minimized state."
    )
    return try encodePretty(result)
}

private func matchingRunningApps(appFilter: String?, defaultToFrontmost: Bool) -> [NSRunningApplication] {
    if let appFilter, !appFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let normalizedFilter = appFilter.lowercased()
        return NSWorkspace.shared.runningApplications
            .filter { $0.bundleURL != nil }
            .filter { app in
                let haystacks = [
                    app.localizedName ?? "",
                    app.bundleIdentifier ?? "",
                    app.bundleURL?.path ?? "",
                ].map { $0.lowercased() }
                return haystacks.contains { $0.contains(normalizedFilter) }
            }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
    if defaultToFrontmost, let frontmost = NSWorkspace.shared.frontmostApplication {
        return [frontmost]
    }
    return NSWorkspace.shared.runningApplications
        .filter { $0.bundleURL != nil }
        .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
}

private func inspectApp(_ app: NSRunningApplication, windowLimit: Int, accessibilityTrusted: Bool) -> InspectedApp {
    let cgWindows = coreGraphicsWindows(for: app.processIdentifier, limit: windowLimit)
    var axWindows: [InspectedWindow] = []
    var focusedWindowTitle: String?
    var mainWindowTitle: String?

    if accessibilityTrusted {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        focusedWindowTitle = axElement(appElement, kAXFocusedWindowAttribute).flatMap {
            axString($0, kAXTitleAttribute)
        }
        mainWindowTitle = axElement(appElement, kAXMainWindowAttribute).flatMap {
            axString($0, kAXTitleAttribute)
        }
        axWindows = axWindowElements(appElement)
            .prefix(max(0, windowLimit))
            .map { inspectedAXWindow($0) }
    }

    let documents = (cgWindows + axWindows)
        .compactMap(\.document)
        .filter { !$0.isEmpty }
        .reduce(into: [String]()) { result, document in
            if !result.contains(document) {
                result.append(document)
            }
        }

    return InspectedApp(
        name: app.localizedName ?? "",
        bundleIdentifier: app.bundleIdentifier,
        processIdentifier: app.processIdentifier,
        bundlePath: app.bundleURL?.path,
        isActive: app.isActive,
        isHidden: app.isHidden,
        activationPolicy: activationPolicyName(app.activationPolicy),
        accessibilityTrusted: accessibilityTrusted,
        focusedWindowTitle: focusedWindowTitle,
        mainWindowTitle: mainWindowTitle,
        openDocuments: documents,
        windows: chooseWindowInventory(coreGraphics: cgWindows, accessibility: axWindows)
    )
}

private func chooseWindowInventory(coreGraphics: [InspectedWindow], accessibility: [InspectedWindow]) -> [InspectedWindow] {
    if accessibility.isEmpty {
        return coreGraphics
    }
    return accessibility + coreGraphics.filter { cgWindow in
        guard let title = cgWindow.title, !title.isEmpty else { return true }
        return !accessibility.contains { $0.title == title }
    }
}

private func coreGraphicsWindows(for pid: Int32, limit: Int) -> [InspectedWindow] {
    guard let rawWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    return rawWindows
        .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid || ($0[kCGWindowOwnerPID as String] as? Int).map(Int32.init) == pid }
        .filter { ($0[kCGWindowLayer as String] as? Int ?? 0) == 0 }
        .prefix(max(0, limit))
        .map { window in
            InspectedWindow(
                source: "coregraphics",
                windowId: window[kCGWindowNumber as String] as? Int,
                title: stringFromAny(window[kCGWindowName as String]),
                role: nil,
                subrole: nil,
                document: nil,
                isOnScreen: boolFromAny(window[kCGWindowIsOnscreen as String]),
                isMinimized: nil,
                bounds: boundsFromCGWindow(window[kCGWindowBounds as String])
            )
        }
}

private func boundsFromCGWindow(_ value: Any?) -> WindowBounds? {
    guard let dict = value as? [String: Any] else { return nil }
    return WindowBounds(
        x: doubleFromAny(dict["X"]) ?? 0,
        y: doubleFromAny(dict["Y"]) ?? 0,
        width: doubleFromAny(dict["Width"]) ?? 0,
        height: doubleFromAny(dict["Height"]) ?? 0
    )
}

private func axWindowElements(_ appElement: AXUIElement) -> [AXUIElement] {
    axValue(appElement, kAXWindowsAttribute) as? [AXUIElement] ?? []
}

private func inspectedAXWindow(_ element: AXUIElement) -> InspectedWindow {
    let position = axPoint(element, kAXPositionAttribute)
    let size = axSize(element, kAXSizeAttribute)
    return InspectedWindow(
        source: "accessibility",
        windowId: nil,
        title: axString(element, kAXTitleAttribute),
        role: axString(element, kAXRoleAttribute),
        subrole: axString(element, kAXSubroleAttribute),
        document: axString(element, kAXDocumentAttribute),
        isOnScreen: nil,
        isMinimized: axBool(element, kAXMinimizedAttribute),
        bounds: WindowBounds(
            x: Double(position?.x ?? 0),
            y: Double(position?.y ?? 0),
            width: Double(size?.width ?? 0),
            height: Double(size?.height ?? 0)
        )
    )
}

private func activationPolicyName(_ policy: NSApplication.ActivationPolicy) -> String {
    switch policy {
    case .regular:
        return "regular"
    case .accessory:
        return "accessory"
    case .prohibited:
        return "prohibited"
    @unknown default:
        return "unknown"
    }
}

private func discoverRunningAppActions(
    appFilter: String?,
    includeUndiscoverable: Bool,
    includeLegacy: Bool,
    limit: Int,
    appLimit: Int
) throws -> String {
    let normalizedFilter = appFilter?.lowercased()
    var discoveredApps: [DiscoveredApp] = []

    for runningApp in NSWorkspace.shared.runningApplications where runningApp.bundleURL != nil {
        guard discoveredApps.count < appLimit else { break }
        guard let bundleURL = runningApp.bundleURL else { continue }
        let appName = runningApp.localizedName ?? bundleURL.deletingPathExtension().lastPathComponent
        let bundleIdentifier = runningApp.bundleIdentifier
        if let normalizedFilter {
            let haystacks = [appName, bundleIdentifier ?? "", bundleURL.path].map { $0.lowercased() }
            guard haystacks.contains(where: { $0.contains(normalizedFilter) }) else { continue }
        }

        var actions = discoverModernAppIntents(in: bundleURL, includeUndiscoverable: includeUndiscoverable)
        if includeLegacy {
            actions.append(contentsOf: discoverLegacyIntentDefinitions(in: bundleURL))
        }
        if actions.count > limit {
            actions = Array(actions.prefix(limit))
        }
        guard !actions.isEmpty else { continue }
        discoveredApps.append(DiscoveredApp(
            name: appName,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: runningApp.processIdentifier,
            bundlePath: bundleURL.path,
            actions: actions
        ))
    }

    let actionCount = discoveredApps.reduce(0) { $0 + $1.actions.count }
    let result = ActionsDiscoveryResult(
        apps: discoveredApps,
        appCount: discoveredApps.count,
        actionCount: actionCount,
        note: "Bounded result. Use app, limit, app_limit, or verbose=true for more detail. Discovery reads AppIntents metadata and legacy .intentdefinition files. These records are introspection only; trigger automation through an existing user Shortcut and run_shortcut."
    )
    return try encodePretty(result)
}

private func discoverModernAppIntents(in bundleURL: URL, includeUndiscoverable: Bool) -> [DiscoveredAction] {
    let metadataURL = bundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
        .appendingPathComponent("Metadata.appintents", isDirectory: true)
        .appendingPathComponent("extract.actionsdata")

    let candidateURL = FileManager.default.fileExists(atPath: metadataURL.path)
        ? metadataURL
        : bundleURL
            .appendingPathComponent("Metadata.appintents", isDirectory: true)
            .appendingPathComponent("extract.actionsdata")

    guard let data = try? Data(contentsOf: candidateURL),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let actions = root["actions"] as? [String: Any] else {
        return []
    }

    return actions.compactMap { identifier, rawAction in
        guard let action = rawAction as? [String: Any] else { return nil }
        let visibility = action["visibilityMetadata"] as? [String: Any]
        let isDiscoverable = boolFromAny(action["isDiscoverable"]) ?? boolFromAny(visibility?["isDiscoverable"])
        if !includeUndiscoverable, isDiscoverable == false {
            return nil
        }

        let descriptionMetadata = action["descriptionMetadata"] as? [String: Any]
        return DiscoveredAction(
            source: "appintents",
            identifier: stringFromAny(action["identifier"]) ?? identifier,
            title: localizedString(from: action["title"]) ?? identifier,
            summary: summaryString(from: action),
            description: localizedString(from: descriptionMetadata?["descriptionText"]),
            category: localizedString(from: descriptionMetadata?["categoryName"]),
            parameters: parameters(from: action["parameters"]),
            isDiscoverable: isDiscoverable,
            openAppWhenRun: boolFromAny(action["openAppWhenRun"]),
            canTriggerDirectly: false,
            triggerMode: "requires_user_shortcut",
            triggerNote: "Create or use a Shortcuts.app shortcut that wraps this app action, then call actions.run_shortcut with that Shortcut's name or identifier."
        )
    }
    .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
}

private func discoverLegacyIntentDefinitions(in bundleURL: URL) -> [DiscoveredAction] {
    let resourcesURL = bundleURL
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
    guard let enumerator = FileManager.default.enumerator(
        at: resourcesURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else {
        return []
    }

    var actions: [DiscoveredAction] = []
    for case let fileURL as URL in enumerator where fileURL.pathExtension == "intentdefinition" {
        guard let data = try? Data(contentsOf: fileURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let intents = plist["INIntents"] as? [[String: Any]] else {
            continue
        }
        for intent in intents {
            guard boolFromAny(intent["INIntentDeprecated"]) != true else { continue }
            let identifier = stringFromAny(intent["INIntentName"]) ?? stringFromAny(intent["INIntentClassName"]) ?? "LegacyIntent"
            actions.append(DiscoveredAction(
                source: "intentdefinition",
                identifier: identifier,
                title: stringFromAny(intent["INIntentTitle"]) ?? identifier,
                summary: nil,
                description: stringFromAny(intent["INIntentDescription"]),
                category: stringFromAny(intent["INIntentCategory"]),
                parameters: legacyParameters(from: intent["INIntentParameters"]),
                isDiscoverable: nil,
                openAppWhenRun: nil,
                canTriggerDirectly: false,
                triggerMode: "requires_user_shortcut",
                triggerNote: "Legacy SiriKit intent definitions are discoverable metadata here. Trigger them through a user Shortcut, not by invoking the intent class name directly."
            ))
        }
    }
    return actions.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
}

private func discoverAccessibilityActions(appFilter: String?, maxDepth: Int, maxTargets: Int) throws -> String {
    guard isAccessibilityTrusted(prompt: true) else {
        throw ActionsToolError.accessibilityPermissionRequired
    }

    let normalizedFilter = appFilter?.lowercased()
    var targets: [AccessibilityActionTarget] = []

    for runningApp in NSWorkspace.shared.runningApplications where runningApp.bundleURL != nil {
        guard targets.count < maxTargets else { break }
        let appName = runningApp.localizedName ?? runningApp.bundleURL?.deletingPathExtension().lastPathComponent ?? ""
        let bundleIdentifier = runningApp.bundleIdentifier
        if let normalizedFilter {
            let haystacks = [appName, bundleIdentifier ?? "", runningApp.bundleURL?.path ?? ""].map { $0.lowercased() }
            guard haystacks.contains(where: { $0.contains(normalizedFilter) }) else { continue }
        }

        let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
        collectAccessibilityTargets(
            element: appElement,
            app: runningApp,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            path: [],
            depth: 0,
            maxDepth: max(0, maxDepth),
            maxTargets: maxTargets,
            targets: &targets
        )
    }

    let actionCount = targets.reduce(0) { $0 + $1.actions.count }
    let result = AccessibilityActionsResult(
        targets: targets,
        targetCount: targets.count,
        actionCount: actionCount,
        note: "These are macOS Accessibility actions discovered through AXUIElementCopyActionNames. Use perform_ax_action with targetRef and action to invoke them through AXUIElementPerformAction."
    )
    return try encodePretty(result)
}

private func performAccessibilityAction(targetRef: String, action: String) throws -> AccessibilityRunResult {
    guard isAccessibilityTrusted(prompt: true) else {
        throw ActionsToolError.accessibilityPermissionRequired
    }
    let target = try parseAccessibilityTargetRef(targetRef)
    guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == target.pid }) else {
        throw ActionsToolError.processFailed("No running application found for pid \(target.pid).")
    }

    let appElement = AXUIElementCreateApplication(target.pid)
    let element = try accessibilityElement(root: appElement, path: target.path)
    let error = AXUIElementPerformAction(element, action as CFString)
    guard error == .success else {
        throw ActionsToolError.processFailed("AXUIElementPerformAction failed for \(action): \(error)")
    }

    return AccessibilityRunResult(
        appName: app.localizedName ?? "",
        bundleIdentifier: app.bundleIdentifier,
        processIdentifier: app.processIdentifier,
        targetRef: targetRef,
        action: action,
        result: "performed"
    )
}

private func collectAccessibilityTargets(
    element: AXUIElement,
    app: NSRunningApplication,
    appName: String,
    bundleIdentifier: String?,
    path: [Int],
    depth: Int,
    maxDepth: Int,
    maxTargets: Int,
    targets: inout [AccessibilityActionTarget]
) {
    guard targets.count < maxTargets else { return }

    let actions = accessibilityActions(for: element)
    if !actions.isEmpty {
        targets.append(AccessibilityActionTarget(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: app.processIdentifier,
            targetRef: accessibilityTargetRef(pid: app.processIdentifier, path: path),
            role: axString(element, kAXRoleAttribute),
            title: axString(element, kAXTitleAttribute),
            identifier: axString(element, kAXIdentifierAttribute),
            description: axString(element, kAXDescriptionAttribute),
            actions: actions
        ))
    }

    guard depth < maxDepth, targets.count < maxTargets else { return }
    let children = axChildren(element)
    for (index, child) in children.enumerated() {
        collectAccessibilityTargets(
            element: child,
            app: app,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            path: path + [index],
            depth: depth + 1,
            maxDepth: maxDepth,
            maxTargets: maxTargets,
            targets: &targets
        )
        if targets.count >= maxTargets {
            break
        }
    }
}

private func accessibilityActions(for element: AXUIElement) -> [AccessibilityAction] {
    var namesRef: CFArray?
    guard AXUIElementCopyActionNames(element, &namesRef) == .success,
          let names = namesRef as? [String] else {
        return []
    }

    return names.map { name in
        var descriptionRef: CFString?
        let error = AXUIElementCopyActionDescription(element, name as CFString, &descriptionRef)
        return AccessibilityAction(
            name: name,
            description: error == .success ? descriptionRef as String? : nil
        )
    }
}

private func accessibilityElement(root: AXUIElement, path: [Int]) throws -> AXUIElement {
    var current = root
    for index in path {
        let children = axChildren(current)
        guard children.indices.contains(index) else {
            throw ActionsToolError.processFailed("Accessibility target path is no longer valid.")
        }
        current = children[index]
    }
    return current
}

private func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    guard let children = axValue(element, kAXChildrenAttribute) as? [AXUIElement] else {
        return []
    }
    return children
}

private func axString(_ element: AXUIElement, _ attribute: String) -> String? {
    axValue(element, attribute) as? String
}

private func axBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
    boolFromAny(axValue(element, attribute))
}

private func axElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    guard let raw = axValue(element, attribute) else { return nil }
    let cf = raw as CFTypeRef
    guard CFGetTypeID(cf) == AXUIElementGetTypeID() else { return nil }
    return (raw as! AXUIElement)
}

private func axPoint(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
    guard let raw = axValue(element, attribute) else { return nil }
    let cf = raw as CFTypeRef
    guard CFGetTypeID(cf) == AXValueGetTypeID() else {
        return nil
    }
    let value = raw as! AXValue
    guard AXValueGetType(value) == .cgPoint else { return nil }
    var point = CGPoint.zero
    guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
    return point
}

private func axSize(_ element: AXUIElement, _ attribute: String) -> CGSize? {
    guard let raw = axValue(element, attribute) else { return nil }
    let cf = raw as CFTypeRef
    guard CFGetTypeID(cf) == AXValueGetTypeID() else {
        return nil
    }
    let value = raw as! AXValue
    guard AXValueGetType(value) == .cgSize else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(value, .cgSize, &size) else { return nil }
    return size
}

private func axValue(_ element: AXUIElement, _ attribute: String) -> Any? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
        return nil
    }
    return value
}

private func accessibilityTargetRef(pid: Int32, path: [Int]) -> String {
    let encodedPath = path.map(String.init).joined(separator: ".")
    return "ax://pid/\(pid)/path/\(encodedPath)"
}

private func parseAccessibilityTargetRef(_ ref: String) throws -> (pid: Int32, path: [Int]) {
    let prefix = "ax://pid/"
    guard ref.hasPrefix(prefix) else {
        throw ActionsToolError.processFailed("Invalid accessibility targetRef: \(ref)")
    }
    let remainder = ref.dropFirst(prefix.count)
    let parts = remainder.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false)
    guard parts.count == 3, parts[1] == "path", let pid = Int32(parts[0]) else {
        throw ActionsToolError.processFailed("Invalid accessibility targetRef: \(ref)")
    }
    let path = parts[2].isEmpty ? [] : parts[2].split(separator: ".").compactMap { Int($0) }
    return (pid, path)
}

private func isAccessibilityTrusted(prompt: Bool) -> Bool {
    let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}
#endif

private func parameters(from value: Any?) -> [DiscoveredParameter] {
    guard let items = value as? [[String: Any]] else { return [] }
    return items.map { parameter in
        DiscoveredParameter(
            name: stringFromAny(parameter["name"]) ?? "",
            title: localizedString(from: parameter["title"]),
            type: valueTypeDescription(parameter["valueType"]),
            optional: boolFromAny(parameter["isOptional"]),
            input: boolFromAny(parameter["isInput"])
        )
    }
}

private func legacyParameters(from value: Any?) -> [DiscoveredParameter] {
    guard let items = value as? [[String: Any]] else { return [] }
    return items.map { parameter in
        DiscoveredParameter(
            name: stringFromAny(parameter["INIntentParameterName"]) ?? "",
            title: stringFromAny(parameter["INIntentParameterDisplayName"]),
            type: stringFromAny(parameter["INIntentParameterType"]),
            optional: nil,
            input: nil
        )
    }
}

private func summaryString(from action: [String: Any]) -> String? {
    guard let configuration = action["actionConfiguration"] as? [String: Any],
          let summary = configuration["actionSummary"] as? [String: Any],
          let wrapper = summary["wrapper"] as? [String: Any],
          let summaryString = wrapper["summaryString"] as? [String: Any] else {
        return nil
    }
    return stringFromAny(summaryString["formatString"])
}

private func localizedString(from value: Any?) -> String? {
    if let string = value as? String {
        return string
    }
    guard let dict = value as? [String: Any] else { return nil }
    if let key = stringFromAny(dict["key"]) {
        return key
    }
    if let title = dict["title"] {
        return localizedString(from: title)
    }
    if let wrapper = dict["wrapper"] {
        return localizedString(from: wrapper)
    }
    return nil
}

private func valueTypeDescription(_ value: Any?) -> String? {
    guard let dict = value as? [String: Any],
          let key = dict.keys.sorted().first,
          let nested = dict[key] as? [String: Any] else {
        return nil
    }
    if let wrapper = nested["wrapper"] as? [String: Any] {
        if let typeName = stringFromAny(wrapper["typeName"]) {
            return "\(key):\(typeName)"
        }
        if let identifier = stringFromAny(wrapper["identifier"]) {
            return "\(key):\(identifier)"
        }
        if let typeIdentifier = stringFromAny(wrapper["typeIdentifier"]) {
            return "\(key):\(typeIdentifier)"
        }
        if let typeIdentifier = wrapper["typeIdentifier"] {
            return "\(key):\(typeIdentifier)"
        }
    }
    return key
}

private func runShortcut(name: String, input: String?, inputPath: String?, outputPath: String?, cwd: String) throws -> ShortcutRunResult {
    if inputPath?.isEmpty != false, outputPath?.isEmpty != false {
        let output = try runShortcutAppleEvent(name: name, input: input)
        return ShortcutRunResult(shortcut: name, runner: "Shortcuts Events Apple Event srct/run", exitCode: 0, output: output)
    }

    var temporaryInputURL: URL?
    var arguments = ["run", name]
    if let input, !input.isEmpty {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("piswift-shortcut-input-\(UUID().uuidString).txt")
        try input.write(to: tempURL, atomically: true, encoding: .utf8)
        temporaryInputURL = tempURL
        arguments.append(contentsOf: ["--input-path", tempURL.path])
    }
    if let inputPath, !inputPath.isEmpty {
        arguments.append(contentsOf: ["--input-path", resolveToCwd(inputPath, cwd: cwd)])
    }
    if let outputPath, !outputPath.isEmpty {
        arguments.append(contentsOf: ["--output-path", resolveToCwd(outputPath, cwd: cwd)])
    }

    defer {
        if let temporaryInputURL {
            try? FileManager.default.removeItem(at: temporaryInputURL)
        }
    }

    let commandOutput = try runShortcutsCommand(arguments)
    return ShortcutRunResult(shortcut: name, runner: "/usr/bin/shortcuts", exitCode: 0, output: commandOutput)
}

private func listShortcuts(limit: Int) throws -> ShortcutListResult {
    let output = try runShortcutsCommand(["list", "--show-identifiers"])
    let shortcuts = output
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map { parseShortcutListLine(String($0)) }
    let bounded = Array(shortcuts.prefix(max(0, limit)))
    return ShortcutListResult(
        shortcuts: bounded,
        total: shortcuts.count,
        returned: bounded.count,
        truncated: bounded.count < shortcuts.count,
        note: bounded.count < shortcuts.count
            ? "Bounded result. Use limit or verbose=true for more shortcuts. Agents should summarize this output instead of pasting it verbatim."
            : "Agents should summarize this output instead of pasting it verbatim."
    )
}

private func parseShortcutListLine(_ line: String) -> ShortcutListItem {
    guard line.hasSuffix(")"),
          let open = line.lastIndex(of: "(") else {
        return ShortcutListItem(name: line, identifier: nil)
    }
    let name = line[..<open].trimmingCharacters(in: .whitespaces)
    let identifier = line[line.index(after: open)..<line.index(before: line.endIndex)]
        .trimmingCharacters(in: .whitespaces)
    return ShortcutListItem(name: name, identifier: identifier.isEmpty ? nil : identifier)
}

private func runShortcutAppleEvent(name: String, input: String?) throws -> String {
    #if os(macOS)
    let event = NSAppleEventDescriptor.appleEvent(
        withEventClass: fourCharCode("srct"),
        eventID: fourCharCode("run "),
        targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: "com.apple.shortcuts.events"),
        returnID: AEReturnID(kAutoGenerateReturnID),
        transactionID: AETransactionID(kAnyTransactionID)
    )
    event.setParam(shortcutObjectSpecifier(nameOrIdentifier: name), forKeyword: keyDirectObject)
    if let input, !input.isEmpty {
        event.setParam(NSAppleEventDescriptor(string: input), forKeyword: fourCharCode("inpt"))
    }
    let reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: 600)
    return appleEventString(reply) ?? ""
    #else
    throw ActionsToolError.unsupportedPlatform
    #endif
}

#if os(macOS)
private func shortcutObjectSpecifier(nameOrIdentifier: String) -> NSAppleEventDescriptor {
    let record = NSAppleEventDescriptor.record()
    record.setDescriptor(NSAppleEventDescriptor(typeCode: fourCharCode("srct")), forKeyword: AEKeyword(keyAEDesiredClass))
    record.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: AEKeyword(keyAEContainer))
    record.setDescriptor(NSAppleEventDescriptor(enumCode: shortcutLookupForm(nameOrIdentifier)), forKeyword: AEKeyword(keyAEKeyForm))
    record.setDescriptor(NSAppleEventDescriptor(string: nameOrIdentifier), forKeyword: AEKeyword(keyAEKeyData))
    return record.coerce(toDescriptorType: DescType(typeObjectSpecifier)) ?? record
}

private func shortcutLookupForm(_ value: String) -> OSType {
    uuidRegex.firstMatch(in: value, options: [], range: NSRange(value.startIndex..., in: value)) == nil ? OSType(formName) : OSType(formUniqueID)
}

private let uuidRegex = try! NSRegularExpression(
    pattern: #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"#
)

private func appleEventString(_ descriptor: NSAppleEventDescriptor?) -> String? {
    guard let descriptor else { return nil }
    if let string = descriptor.stringValue {
        return string
    }
    let direct = descriptor.paramDescriptor(forKeyword: keyDirectObject)
    if let string = direct?.stringValue {
        return string
    }
    if let direct, direct.numberOfItems > 0 {
        return (1...direct.numberOfItems)
            .compactMap { direct.atIndex($0)?.stringValue }
            .joined(separator: "\n")
    }
    return nil
}
#endif

private func fourCharCode(_ string: String) -> OSType {
    string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
}

private func runShortcutsCommand(_ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
    process.arguments = arguments

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
        throw ActionsToolError.processFailed(errorOutput.isEmpty ? output : errorOutput)
    }
    return output
}

private func encodePretty<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    return String(data: data, encoding: .utf8) ?? "{}"
}

private func stringFromAny(_ value: Any?) -> String? {
    switch value {
    case let string as String:
        return string
    case let number as NSNumber:
        return number.stringValue
    default:
        return nil
    }
}

private func boolFromAny(_ value: Any?) -> Bool? {
    switch value {
    case let bool as Bool:
        return bool
    case let number as NSNumber:
        return number.boolValue
    case let string as String:
        return Bool(string)
    default:
        return nil
    }
}

private func doubleFromAny(_ value: Any?) -> Double? {
    switch value {
    case let double as Double:
        return double
    case let float as Float:
        return Double(float)
    case let cgFloat as CGFloat:
        return Double(cgFloat)
    case let int as Int:
        return Double(int)
    case let number as NSNumber:
        return number.doubleValue
    case let string as String:
        return Double(string)
    default:
        return nil
    }
}

private func boolValue(_ value: AnyCodable?) -> Bool? {
    if let bool = value?.value as? Bool {
        return bool
    }
    if let string = value?.value as? String {
        return Bool(string)
    }
    if let number = value?.value as? NSNumber {
        return number.boolValue
    }
    return nil
}

private struct AnyEncodableValue: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        self.encodeClosure = value.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
