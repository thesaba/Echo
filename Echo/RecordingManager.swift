import Foundation
import AVFoundation
import Combine
import Speech
import WatchConnectivity

@MainActor
final class RecordingManager: ObservableObject {
    static let shared = RecordingManager()

    enum State: Equatable {
        case idle
        case recording(startDate: Date)
        case playing(id: UUID)
    }

    struct Recording: Identifiable, Equatable {
        struct TranscriptionSegment: Identifiable, Equatable {
            let id: Int
            let text: String
            let startTime: TimeInterval
            let duration: TimeInterval
        }

        let id: UUID
        var createdAt: Date
        var fileURL: URL
        var duration: TimeInterval?
        var isTranscribed: Bool
        var transcription: String?
        var transcriptionSegments: [TranscriptionSegment]

        var displayName: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: createdAt)
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var recordings: [Recording] = []
    @Published private(set) var speechAuthorization: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published private(set) var playbackTime: TimeInterval = 0
    @Published private(set) var isICloudAvailable: Bool = false

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var playbackTimer: Timer?

    private let fileManager = FileManager.default
    private let speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer()
    private let fileCoordinator = NSFileCoordinator(filePresenter: nil)
    private var presenter: RecordingsFolderPresenter?

    private var wcSession: WCSession?

    init() {
        configureWatchConnectivity()
        configureStorageAndObservation()
        loadExistingRecordings()
        refreshSpeechAuthorization()
    }

    private var localRecordingsDirectory: URL {
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Recordings", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var iCloudRecordingsDirectory: URL? {
        guard let container = fileManager.url(forUbiquityContainerIdentifier: nil) else { return nil }
        let docs = container.appendingPathComponent("Documents", isDirectory: true)
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        return dir
    }

    private var preferredRecordingsDirectory: URL {
        if let cloud = iCloudRecordingsDirectory, isICloudAvailable {
            return cloud
        }
        return localRecordingsDirectory
    }

    var storageStatusText: String {
        if isICloudAvailable {
            return "Syncing with iCloud"
        }
        return "Stored locally"
    }

    func retryICloud() {
        let wasAvailable = isICloudAvailable
        configureStorageAndObservation()

        if !wasAvailable, isICloudAvailable {
            migrateLocalRecordingsToICloud()
        }
        loadExistingRecordings()
    }

    private func configureStorageAndObservation() {
        isICloudAvailable = fileManager.url(forUbiquityContainerIdentifier: nil) != nil
        if let cloud = iCloudRecordingsDirectory, isICloudAvailable {
            ensureDirectoryExistsCoordinated(cloud)
            presenter = RecordingsFolderPresenter(url: cloud) { [weak self] in
                Task { @MainActor in
                    self?.loadExistingRecordings()
                }
            }
        } else {
            presenter = nil
        }
    }

    private func migrateLocalRecordingsToICloud() {
        guard let cloudDir = iCloudRecordingsDirectory, isICloudAvailable else { return }
        ensureDirectoryExistsCoordinated(cloudDir)

        guard let localURLs = try? fileManager.contentsOfDirectory(at: localRecordingsDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        for sourceURL in localURLs where sourceURL.pathExtension.lowercased() == "m4a" {
            let destURL = cloudDir.appendingPathComponent(sourceURL.lastPathComponent)
            if fileManager.fileExists(atPath: destURL.path) { continue }

            var error: NSError?
            fileCoordinator.coordinate(writingItemAt: destURL, options: [.forReplacing], error: &error) { _ in
                do {
                    try self.fileManager.moveItem(at: sourceURL, to: destURL)
                } catch {
                    // Best-effort migration; ignore failures.
                }
            }
        }
    }

    private func ensureDirectoryExistsCoordinated(_ url: URL) {
        var error: NSError?
        fileCoordinator.coordinate(writingItemAt: url, options: [.forReplacing], error: &error) { _ in
            if !self.fileManager.fileExists(atPath: url.path) {
                try? self.fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }

    private func loadExistingRecordings() {
        let dir = preferredRecordingsDirectory
        guard let urls = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]) else { return }
        let items: [Recording] = urls.compactMap { url in
            let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) ?? UUID()
            let values = try? url.resourceValues(forKeys: [.creationDateKey])
            let created = values?.creationDate ?? Date()
            return Recording(id: id,
                             createdAt: created,
                             fileURL: url,
                             duration: nil,
                             isTranscribed: false,
                             transcription: nil,
                             transcriptionSegments: [])
        }
        recordings = items.sorted(by: { $0.createdAt > $1.createdAt })
    }

    func refreshSpeechAuthorization() {
        speechAuthorization = SFSpeechRecognizer.authorizationStatus()
    }

    func requestSpeechAuthorizationIfNeeded() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        speechAuthorization = current
        if current != .notDetermined { return current }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    self.speechAuthorization = status
                    continuation.resume(returning: status)
                }
            }
        }
    }

    func startRecording() async {
        guard case .idle = state else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            return
        }

        let id = UUID()
        // Record locally first; if iCloud is available we'll move the finished file in `stopRecording()`.
        let url = localRecordingsDirectory.appendingPathComponent("\(id.uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.isMeteringEnabled = true
            recorder?.record()
            state = .recording(startDate: Date())
        } catch {
            recorder = nil
            try? AVAudioSession.sharedInstance().setActive(false)
        }
    }

    func stopRecording() {
        guard case let .recording(startDate) = state else { return }
        recorder?.stop()
        let url = recorder?.url
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        state = .idle

        guard let url else { return }

        let finalURL = moveRecordingToPreferredLocationIfNeeded(url)
        let duration = Date().timeIntervalSince(startDate)
        let recording = Recording(id: UUID(uuidString: finalURL.deletingPathExtension().lastPathComponent) ?? UUID(),
                                  createdAt: startDate,
                                  fileURL: finalURL,
                                  duration: duration,
                                  isTranscribed: false,
                                  transcription: nil,
                                  transcriptionSegments: [])
        recordings.insert(recording, at: 0)

        Task {
            await transcribeIfPossible(recordingID: recording.id)
        }
    }

    private func moveRecordingToPreferredLocationIfNeeded(_ sourceURL: URL) -> URL {
        let destinationDirectory = preferredRecordingsDirectory
        guard destinationDirectory != sourceURL.deletingLastPathComponent() else { return sourceURL }

        let destinationURL = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        ensureDirectoryExistsCoordinated(destinationDirectory)

        var error: NSError?
        fileCoordinator.coordinate(writingItemAt: destinationURL, options: [.forReplacing], error: &error) { _ in
            do {
                if self.fileManager.fileExists(atPath: destinationURL.path) {
                    try self.fileManager.removeItem(at: destinationURL)
                }
                try self.fileManager.moveItem(at: sourceURL, to: destinationURL)
            } catch {
                // If move fails, keep local copy.
            }
        }
        if fileManager.fileExists(atPath: destinationURL.path) { return destinationURL }
        return sourceURL
    }

    func toggleRecording() async {
        switch state {
        case .idle, .playing:
            await startRecording()
        case .recording:
            stopRecording()
        }
    }

    func play(_ recording: Recording) {
        if case let .playing(id) = state, id == recording.id {
            stopPlayback()
            return
        }
        stopPlayback()
        do {
            player = try AVAudioPlayer(contentsOf: recording.fileURL)
            player?.prepareToPlay()
            player?.play()
            state = .playing(id: recording.id)
            startPlaybackTimer()
        } catch {
            player = nil
            state = .idle
        }
    }

    func stopPlayback() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        player?.stop()
        player = nil
        playbackTime = 0
        if case .recording = state {
            return
        }
        state = .idle
    }

    func delete(_ recording: Recording) {
        var error: NSError?
        fileCoordinator.coordinate(writingItemAt: recording.fileURL, options: [.forDeleting], error: &error) { url in
            try? self.fileManager.removeItem(at: url)
        }
        recordings.removeAll { $0.id == recording.id }
    }

    func recording(withID id: UUID) -> Recording? {
        recordings.first(where: { $0.id == id })
    }

    func transcriptionSegmentIndex(for recordingID: UUID, at time: TimeInterval) -> Int? {
        guard let rec = recording(withID: recordingID) else { return nil }
        let segments = rec.transcriptionSegments
        guard !segments.isEmpty else { return nil }
        return segments.lastIndex(where: { time >= $0.startTime })
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard let player else { return }
            self.playbackTime = player.currentTime
            if !player.isPlaying {
                self.stopPlayback()
            }
        }
    }

    private func transcribeIfPossible(recordingID: UUID) async {
        guard let index = recordings.firstIndex(where: { $0.id == recordingID }) else { return }

        let status = await requestSpeechAuthorizationIfNeeded()
        guard status == .authorized else { return }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }
        let url = recordings[index].fileURL

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = false
        request.shouldReportPartialResults = false

        await withCheckedContinuation { continuation in
            _ = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    let best = result.bestTranscription
                    let segments: [Recording.TranscriptionSegment] = best.segments.enumerated().map { idx, seg in
                        Recording.TranscriptionSegment(
                            id: idx,
                            text: seg.substring,
                            startTime: seg.timestamp,
                            duration: seg.duration
                        )
                    }
                    Task { @MainActor in
                        guard let idx = self.recordings.firstIndex(where: { $0.id == recordingID }) else { return }
                        self.recordings[idx].transcription = best.formattedString
                        self.recordings[idx].transcriptionSegments = segments
                        self.recordings[idx].isTranscribed = !best.formattedString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    if result.isFinal {
                        continuation.resume()
                    }
                    return
                }

                if error != nil {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - WatchConnectivity import

    func importWatchRecording(fileURL: URL, metadata: [String: Any]?) {
        let createdAt = (metadata?["createdAt"] as? Date) ?? Date()
        let id = UUID()
        let destinationURL = preferredRecordingsDirectory.appendingPathComponent("\(id.uuidString).m4a")
        ensureDirectoryExistsCoordinated(preferredRecordingsDirectory)

        var error: NSError?
        fileCoordinator.coordinate(writingItemAt: destinationURL, options: [.forReplacing], error: &error) { _ in
            do {
                if self.fileManager.fileExists(atPath: destinationURL.path) {
                    try self.fileManager.removeItem(at: destinationURL)
                }
                try self.fileManager.copyItem(at: fileURL, to: destinationURL)
            } catch {
                return
            }
        }

        let recording = Recording(id: id,
                                  createdAt: createdAt,
                                  fileURL: destinationURL,
                                  duration: nil,
                                  isTranscribed: false,
                                  transcription: nil,
                                  transcriptionSegments: [])
        recordings.insert(recording, at: 0)
        Task {
            await transcribeIfPossible(recordingID: recording.id)
        }
    }

    private func configureWatchConnectivity() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = WatchConnectivityReceiver(manager: self)
        session.activate()
        wcSession = session
    }
}

// MARK: - iCloud folder observation

private final class RecordingsFolderPresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        return q
    }()

    private let onChange: () -> Void

    init(url: URL, onChange: @escaping () -> Void) {
        self.presentedItemURL = url
        self.onChange = onChange
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    deinit {
        NSFileCoordinator.removeFilePresenter(self)
    }

    func presentedItemDidChange() {
        onChange()
    }

    func presentedSubitemDidAppear(at url: URL) {
        onChange()
    }

    func presentedSubitemDidChange(at url: URL) {
        onChange()
    }

    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) {
        onChange()
    }
}

// MARK: - WatchConnectivity receiver

private final class WatchConnectivityReceiver: NSObject, WCSessionDelegate {
    private weak var manager: RecordingManager?

    init(manager: RecordingManager) {
        self.manager = manager
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        DispatchQueue.main.async { [weak self] in
            self?.manager?.importWatchRecording(fileURL: file.fileURL, metadata: file.metadata)
        }
    }
}

