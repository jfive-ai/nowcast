import Foundation
import AVFoundation
import Combine
import ObjectiveC

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
    /// FIX (codex review PRs #32/#43): monotonically-increasing playback
    /// session id. Every new `play()` bumps this. Delegate callbacks
    /// carry the session id they were started under (associated via
    /// `objc_setAssociatedObject` on the utterance), and only mutate
    /// state if it matches `currentSessionID`. This prevents a late
    /// `didCancel` from an old, stopped utterance from clobbering the
    /// state of the new utterance that started immediately after.
    private var currentSessionID: UInt64 = 0
    private static var sessionKey: UInt8 = 0

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
        currentSessionID &+= 1
        let sessionID = currentSessionID
        objc_setAssociatedObject(utter, &Self.sessionKey, NSNumber(value: sessionID), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        currentReportID = reportID
        state = .playing(reportID: reportID)
        synthesizer.speak(utter)
    }

    /// Attempt to pause; only mutates state when the synthesizer
    /// confirms the transition. FIX (codex review PR #32 P2): previously
    /// `state` flipped to `.paused` unconditionally, even when the
    /// utterance had finished and the pause call returned `false`.
    func pause() {
        guard case .playing(let id) = state else { return }
        let didPause = synthesizer.pauseSpeaking(at: .word)
        if didPause {
            state = .paused(reportID: id)
        }
    }

    func stop() {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        currentReportID = nil
        state = .idle
    }

    fileprivate func sessionID(for utterance: AVSpeechUtterance) -> UInt64? {
        (objc_getAssociatedObject(utterance, &Self.sessionKey) as? NSNumber)?.uint64Value
    }
}

extension AudioBriefPlayer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            // FIX (codex review PR #32 P1): only clear state if this
            // callback belongs to the currently-active session.
            guard let sid = sessionID(for: utterance), sid == currentSessionID else { return }
            // Match both `.playing` and `.paused` — `didFinish` can fire
            // on a stale utterance after pause in some macOS releases.
            switch state {
            case .idle: return
            case .playing, .paused:
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
            // FIX (codex review PR #32/#43 P1): a stale cancel from the
            // previously-stopped utterance must NOT reset the state of
            // the new utterance that started immediately after. Compare
            // the per-utterance session id.
            guard let sid = sessionID(for: utterance), sid == currentSessionID else { return }
            state = .idle
            currentReportID = nil
        }
    }
}
