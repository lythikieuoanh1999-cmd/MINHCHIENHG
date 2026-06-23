import Foundation
import AVFoundation

@MainActor
final class VoiceRecorder: ObservableObject {
    @Published var isRecording = false
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    func requestPermission(_ completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default)
        try session.setActive(true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kenios_rec.m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.record()
        recorder = rec
        fileURL = url
        isRecording = true
    }

    func stop() -> Data? {
        recorder?.stop()
        recorder = nil
        isRecording = false
        guard let url = fileURL else { return nil }
        return try? Data(contentsOf: url)
    }
}
