import Foundation
import AVFoundation
import Combine

/// Plays a briefing via the system speech synthesizer. Free, offline,
/// runs on every macOS 13+ Mac. Exposed as an `EnvironmentObject` so the
/// `ReportView` toolbar and `MenuBarContentView` can share play state.
@MainActor
final class AudioBriefPlayer: NSObject, ObservableObject {
    enum State {
        case idle
        case playing(reportID: UUID)
        case paused(reportID: UUID)
    }

    @Published private(set) var state: State = .idle

    private let synthesizer = AVSpeechSynthesizer()
    private var currentReportID: UUID?
    private var preferredVoiceID: String? {
        UserDefaults.standard.string(forKey: "audio.voice")
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func isPlaying(reportID: UUID) -> Bool {
        if case .playing(let id) = state, id == reportID { return true }
        return false
    }

    func isPaused(reportID: UUID) -> Bool {
        if case .paused(let id) = state, id == reportID { return true }
        return false
    }

    /// Start or resume playback for a given report+markdown pair.
    func play(reportID: UUID, markdown: String) {
        // If we're already paused on the same report, just resume.
        if case .paused(let id) = state, id == reportID {
            synthesizer.continueSpeaking()
            state = .playing(reportID: id)
            return
        }
        // Switch to this report: stop anything in flight first.
        stop()
        let script = SpeechScript.make(from: markdown)
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let utter = AVSpeechUtterance(string: script)
        if let voiceID = preferredVoiceID, let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utter.voice = voice
        } else {
            utter.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        utter.rate = 0.5
        currentReportID = reportID
        state = .playing(reportID: reportID)
        synthesizer.speak(utter)
    }

    func pause() {
        guard case .playing(let id) = state else { return }
        synthesizer.pauseSpeaking(at: .word)
        state = .paused(reportID: id)
    }

    func stop() {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        currentReportID = nil
        state = .idle
    }
}

extension AudioBriefPlayer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            // Only clear state if we're the still-current owner.
            if case .playing = state {
                state = .idle
                currentReportID = nil
            }
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            state = .idle
            currentReportID = nil
        }
    }
}
