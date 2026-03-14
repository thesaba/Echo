//
//  ContentView.swift
//  Echo
//
//  Created by Saba Abesadze on 13/03/2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var manager = RecordingManager.shared
    @State private var selection: Tab = .record

    enum Tab {
        case record
        case library
    }

    var body: some View {
        TabView(selection: $selection) {
            RecordView()
                .environmentObject(manager)
                .tabItem {
                    Label("Record", systemImage: "circle.fill")
                }
                .tag(Tab.record)

            LibraryView()
                .environmentObject(manager)
                .tabItem {
                    Label("Library", systemImage: "waveform")
                }
                .tag(Tab.library)
        }
    }
}

private struct RecordView: View {
    @EnvironmentObject var manager: RecordingManager
    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(timeString)
                .font(.system(size: 42, weight: .medium, design: .monospaced))
                .padding(.vertical, 8)

            Button(action: toggle) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.red, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 120, height: 120)
                        .shadow(color: .red.opacity(0.4), radius: 16, x: 0, y: 8)

                    Circle()
                        .strokeBorder(Color.white.opacity(0.4), lineWidth: 4)
                        .frame(width: 120, height: 120)

                    Image(systemName: iconName)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)

            Spacer()
        }
        .padding()
        .onChange(of: manager.state) { _, newValue in
            handleStateChange(newValue)
        }
        .onAppear {
            handleStateChange(manager.state)
        }
    }

    private var title: String {
        switch manager.state {
        case .recording:
            return "Recording"
        case .playing:
            return "Playing"
        case .idle:
            return "Ready to record"
        }
    }

    private var subtitle: String {
        switch manager.state {
        case .recording:
            return "Tap to stop"
        case .playing:
            return "Tap to stop playback"
        case .idle:
            return "Capture moments with a single tap"
        }
    }

    private var iconName: String {
        switch manager.state {
        case .recording:
            return "stop.fill"
        default:
            return "mic.fill"
        }
    }

    private var accessibilityLabel: String {
        switch manager.state {
        case .recording:
            return "Stop recording"
        default:
            return "Start recording"
        }
    }

    private var timeString: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: elapsed) ?? "00:00"
    }

    private func toggle() {
        Task {
            await manager.toggleRecording()
        }
    }

    private func handleStateChange(_ state: RecordingManager.State) {
        timer?.invalidate()
        switch state {
        case let .recording(startDate):
            elapsed = Date().timeIntervalSince(startDate)
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                elapsed = Date().timeIntervalSince(startDate)
            }
        default:
            timer = nil
        }
    }
}

private struct LibraryView: View {
    @EnvironmentObject var manager: RecordingManager

    var body: some View {
        NavigationStack {
            Group {
                if manager.recordings.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No recordings yet")
                            .font(.headline)
                        Text("Your conversations and ideas will appear here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(manager.recordings) { recording in
                            NavigationLink {
                                RecordingDetailView(recordingID: recording.id)
                                    .environmentObject(manager)
                            } label: {
                                RecordingRow(recording: recording)
                            }
                        }
                        .onDelete { indexSet in
                            indexSet.map { manager.recordings[$0] }.forEach { manager.delete($0) }
                        }
                    }
                }
            }
            .navigationTitle("Recordings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(manager.storageStatusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(manager.storageStatusText)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        manager.retryICloud()
                    } label: {
                        Label("Retry iCloud", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }
}

private struct RecordingRow: View {
    @EnvironmentObject var manager: RecordingManager
    let recording: RecordingManager.Recording

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.displayName)
                    .font(.subheadline.weight(.semibold))
                if let duration = recording.duration {
                    Text(durationString(duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    private var iconName: String {
        if case let .playing(id) = manager.state, id == recording.id {
            return "pause.fill"
        }
        return "play.fill"
    }

    private func durationString(_ value: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: value) ?? "0:00"
    }
}

#Preview {
    ContentView()
}

