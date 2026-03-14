import Foundation
import AppIntents

@available(iOS 16.0, *)
struct StartEchoRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Echo Recording"
    static var description = IntentDescription("Start a new recording in Echo.")

    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await RecordingManager.shared.toggleRecording()
        return .result()
    }
}

@available(iOS 16.0, *)
struct StopEchoRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Echo Recording"
    static var description = IntentDescription("Stop the current recording in Echo.")

    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        if case .recording = await RecordingManager.shared.state {
            await RecordingManager.shared.stopRecording()
        }
        return .result()
    }
}

@available(iOS 16.0, *)
struct EchoAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartEchoRecordingIntent(),
            phrases: [
                "Start recording in \(.applicationName)"
            ],
            shortTitle: "Start Recording",
            systemImageName: "record.circle.fill"
        )
        AppShortcut(
            intent: StopEchoRecordingIntent(),
            phrases: [
                "Stop recording in \(.applicationName)"
            ],
            shortTitle: "Stop Recording",
            systemImageName: "stop.circle.fill"
        )
    }
}

