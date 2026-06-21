import SwiftUI
import PiSwiftShell
#if os(macOS)
import AppKit
#endif

struct PiSwiftShellApplication: App {
    @StateObject private var viewModel = PiShellViewModel()

    var body: some Scene {
        #if os(macOS)
        WindowGroup("Pi Shell", id: "shell") {
            PiShellView(viewModel: viewModel)
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            PiShellStatusMenu(viewModel: viewModel)
        } label: {
            Label("Pi", systemImage: viewModel.isGenerating ? "arrow.triangle.2.circlepath" : "pi")
        }
        .commands {
            CommandMenu("Pi Shell") {
                Button("New Session") {
                    viewModel.clearVisibleHistory()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Compact Context") {
                    viewModel.compactSession()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button("Restart Agent") {
                    viewModel.restartBackend()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

            }
        }

        Settings {
            PiShellSettingsView(viewModel: viewModel)
        }
        .windowResizability(.contentSize)
        #else
        WindowGroup("Pi Shell") {
            PiShellView(viewModel: viewModel)
        }
        #endif
    }
}

PiSwiftShellApplication.main()

#if os(macOS)
private struct PiShellStatusMenu: View {
    @ObservedObject var viewModel: PiShellViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(viewModel.backendStatus.label)
        if let model = viewModel.selectedModel?.id {
            Text(model)
        }
        if !viewModel.messages.isEmpty {
            Text("Messages: \(viewModel.messages.count)")
        }

        Divider()

        Button("Show Window") {
            openWindow(id: "shell")
        }

        Button("Clear History") {
            viewModel.clearVisibleHistory()
        }

        Button("Restart Backend") {
            viewModel.restartBackend()
        }

        Button("Settings") {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            openWindow(id: "shell")
        }
    }
}
#endif
