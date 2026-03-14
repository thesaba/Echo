//
//  ContentView.swift
//  Echo
//
//  Created by Saba Abesadze on 13/03/2026.
//

import SwiftUI

private let echoPurple = Color(red: 0x8E / 255, green: 0x44 / 255, blue: 0xAD / 255)

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
                    if case .recording = manager.state {
                        PulsingCircle(color: echoPurple, baseOpacity: 0.35, size: 150, maxScale: 1.08)
                    } else {
                        Circle()
                            .fill(echoPurple.opacity(0.35))
                            .frame(width: 150, height: 150)
                    }
                    
                    Circle()
                        .fill(
                            RadialGradient(colors: [echoPurple, echoPurple.opacity(0.6)],
                                           center: .center,
                                           startRadius: 4,
                                           endRadius: 60)
                        )
                        .frame(width: 90, height: 90)
                        .shadow(color: echoPurple.opacity(0.5), radius: 14, x: 0, y: 6)
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

private struct PulsingCircle: View {
    let color: Color
    let baseOpacity: Double
    let size: CGFloat
    let maxScale: CGFloat

    @State private var animate = false

    init(color: Color, baseOpacity: Double = 0.35, size: CGFloat, maxScale: CGFloat = 1.08) {
        self.color = color
        self.baseOpacity = baseOpacity
        self.size = size
        self.maxScale = maxScale
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(animate ? maxScale : 1.0)
            .opacity(animate ? baseOpacity : max(baseOpacity - 0.15, 0))
            .onAppear { animate = true }
            .onDisappear { animate = false }
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: animate)
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
                    .fill(echoPurple.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(echoPurple)
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

