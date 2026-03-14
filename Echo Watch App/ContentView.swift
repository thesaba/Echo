//
//  ContentView.swift
//  Echo Watch App
//
//  Created by Saba Abesadze on 13/03/2026.
//

import SwiftUI
import AVFoundation
import Combine
import WatchConnectivity

struct ContentView: View {
    @StateObject private var watchManager = WatchRecordingManager()

    var body: some View {
        TabView {
            RecordingRootView(manager: watchManager)
            RecordingsScreen(manager: watchManager)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
    }
}

private struct RecordingRootView: View {
    @ObservedObject var manager: WatchRecordingManager

    var body: some View {
        Group {
            if manager.isRecording {
                RecordingActiveView(manager: manager)
            } else {
                RecordingIdleView(manager: manager)
            }
        }
    }
}

private struct RecordingIdleView: View {
    @ObservedObject var manager: WatchRecordingManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.echoPurple.opacity(0.35))
                        .frame(width: 150, height: 150)

                    Button {
                        manager.toggleRecording()
                    } label: {
                        Circle()
                            .fill(
                                RadialGradient(colors: [Color.echoPurple, Color.echoPurple.opacity(0.6)],
                                               center: .center,
                                               startRadius: 4,
                                               endRadius: 60)
                            )
                            .frame(width: 90, height: 90)
                            .shadow(color: Color.echoPurple.opacity(0.5), radius: 14, x: 0, y: 6)
                    }
                    .buttonStyle(.plain)
                }

                Text("Swipe left for recordings")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 6)
            }
        }
    }
}

private struct RecordingActiveView: View {
    @ObservedObject var manager: WatchRecordingManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                ZStack {
                    PulsingCircle(color: Color.echoPurple, baseOpacity: 0.3, size: 110, maxScale: 1.08)

                    Button {
                        manager.toggleRecording()
                    } label: {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(
                                LinearGradient(colors: [Color.echoPurple, Color.echoPurple.opacity(0.7)],
                                               startPoint: .top,
                                               endPoint: .bottom)
                            )
                            .frame(width: 70, height: 70)
                            .shadow(color: Color.echoPurple.opacity(0.7), radius: 12, x: 0, y: 5)
                    }
                    .buttonStyle(.plain)
                }

                Text(manager.elapsedString)
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)

                Spacer(minLength: 8)

                WaveformView()
                    .frame(height: 60)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
        }
    }
}

private struct RecordingsScreen: View {
    @ObservedObject var manager: WatchRecordingManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 8) {
                Text("Recordings")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 8)

                if manager.recordings.isEmpty {
                    Spacer()
                    Text("No recordings yet")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(manager.recordings, id: \.self) { name in
                                RecordingRowView(name: name, manager: manager)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                    }
                }
            }
        }
    }
}

private struct RecordingRowView: View {
    let name: String
    @ObservedObject var manager: WatchRecordingManager

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.echoPurple.opacity(0.25))
                    .frame(width: 26, height: 26)
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text(displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            manager.togglePlayback(for: name)
        }
    }

    private var iconName: String {
        manager.currentlyPlaying == name ? "pause.fill" : "play.fill"
    }

    private var displayName: String {
        name.replacingOccurrences(of: ".m4a", with: "")
    }
}

final class WatchRecordingManager: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    @Published var isRecording = false
    @Published var recordings: [String] = []
    @Published var elapsed: TimeInterval = 0
    @Published var progressRotation: Double = 0
    @Published var currentlyPlaying: String?

    private var recorder: AVAudioRecorder?
    private var createdAt: Date?
    private var timer: Timer?
    private var player: AVAudioPlayer?

    var elapsedString: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: elapsed) ?? "00:00"
    }

    func toggleRecording() {
        if isRecording {
            stop()
        } else {
            start()
        }
    }

    private func start() {
        WatchConnectivitySender.shared.activateIfNeeded()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .default)
        try? session.setActive(true)

        createdAt = Date()
        let url = recordingsDirectory().appendingPathComponent(UUID().uuidString + ".m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        recorder = try? AVAudioRecorder(url: url, settings: settings)
        recorder?.delegate = self
        recorder?.record()
        isRecording = true
        startTimer()
    }

    private func stop() {
        recorder?.stop()
        isRecording = false
        stopTimer()
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if flag {
            recordings.insert(recorder.url.lastPathComponent, at: 0)
            WatchConnectivitySender.shared.transfer(url: recorder.url, createdAt: createdAt ?? Date())
        }
    }

    // MARK: - Playback

    func togglePlayback(for fileName: String) {
        if currentlyPlaying == fileName {
            stopPlayback()
            return
        }

        let url = recordingsDirectory().appendingPathComponent(fileName)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)

            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            player?.play()
            currentlyPlaying = fileName
        } catch {
            stopPlayback()
        }
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        currentlyPlaying = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func startTimer() {
        timer?.invalidate()
        let start = Date()
        elapsed = 0
        progressRotation = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let dt = Date().timeIntervalSince(start)
            DispatchQueue.main.async {
                self.elapsed = dt
                self.progressRotation = (dt.truncatingRemainder(dividingBy: 4)) / 4 * 360
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        elapsed = 0
        progressRotation = 0
    }

    private func recordingsDirectory() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("WatchRecordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}

private final class WatchConnectivitySender: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivitySender()
    private override init() {}

    func activateIfNeeded() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil { session.delegate = self }
        if session.activationState != .activated { session.activate() }
    }

    func transfer(url: URL, createdAt: Date) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let metadata: [String: Any] = ["createdAt": createdAt]
        _ = session.transferFile(url, metadata: metadata)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
}

#Preview {
    ContentView()
}

