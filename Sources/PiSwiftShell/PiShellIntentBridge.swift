import Foundation

public enum PiShellIntentBridge {
    public static let askNotification = Notification.Name("PiShellIntentBridge.ask")
    public static let newSessionNotification = Notification.Name("PiShellIntentBridge.newSession")
    public static let promptUserInfoKey = "prompt"
}
