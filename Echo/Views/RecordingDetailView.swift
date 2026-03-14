import SwiftUI
import Speech

private let echoPurple = Color(red: 0x8E / 255, green: 0x44 / 255, blue: 0xAD / 255)

struct RecordingDetailView: View {
    @EnvironmentObject var manager: RecordingManager
    let recordingID: UUID

    @State private var activeSegmentID: Int?

    var body: some View {
        VStack(spacing: 16) {
            header
            transcript
        }
        .padding()
        .navigationTitle("Transcript")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { _ = await manager.requestSpeechAuthorizationIfNeeded() }
        }
        .onChange(of: manager.playbackTime) { _, newValue in
            guard case let .playing(id) = manager.state, id == recordingID else {
                activeSegmentID = nil
                return
            }
            if let idx = manager.transcriptionSegmentIndex(for: recordingID, at: newValue) {
                activeSegmentID = idx
            } else {
                activeSegmentID = nil
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        if let recording = manager.recording(withID: recordingID) {
            VStack(alignment: .leading, spacing: 8) {
                Text(recording.displayName)
                    .font(.headline)

                HStack {
                    Button {
                        manager.play(recording)
                    } label: {
                        Label(playLabel, systemImage: playIconName)
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    if recording.isTranscribed {
                        Text("Transcribed")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(transcribeStatusText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            ContentUnavailableView("Recording not found", systemImage: "exclamationmark.triangle")
        }
    }

    private var playIconName: String {
        if case let .playing(id) = manager.state, id == recordingID {
            return "stop.fill"
        }
        return "play.fill"
    }

    private var playLabel: String {
        if case let .playing(id) = manager.state, id == recordingID {
            return "Stop"
        }
        return "Play"
    }

    private var transcribeStatusText: String {
        switch manager.speechAuthorization {
        case .notDetermined:
            return "Transcription needs permission"
        case .denied, .restricted:
            return "Transcription not allowed"
        case .authorized:
            return "Transcribing…"
        @unknown default:
            return "Transcription unavailable"
        }
    }

    @ViewBuilder
    private var transcript: some View {
        if let recording = manager.recording(withID: recordingID) {
            if !recording.transcriptionSegments.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(recording.transcriptionSegments) { seg in
                                Text(seg.text)
                                    .font(.body)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                                    .background(activeSegmentID == seg.id ? echoPurple.opacity(0.18) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .id(seg.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: activeSegmentID) { _, newValue in
                        guard let newValue else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            } else if let text = recording.transcription, !text.isEmpty {
                ScrollView {
                    Text(text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("No transcript yet", systemImage: "text.magnifyingglass")
            }
        }
    }
}

#Preview {
    NavigationStack {
        RecordingDetailView(recordingID: UUID())
            .environmentObject(RecordingManager())
    }
}

