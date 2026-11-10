import Foundation
import AVFoundation
import os

// MARK: - Gnani Voice Agent

/// The app's only voice provider.
///
/// Speech-to-text uses **Gnani Prisma v2.5** (`POST /stt/v3`).
/// Text-to-speech uses **Gnani Timbre v2.5** (`POST /api/v1/tts/inference`).
///
/// Reads `GNANI_API_KEY` from the app's `.env` (exposed via
/// `AppDelegate.sharedEnvVars`). Optional overrides:
///
///   GNANI_STT_MODEL      prisma-v2.5   (default)
///   GNANI_STT_LANGUAGE   en-IN         (one language per request)
///   GNANI_TTS_MODEL      timbre-v2.5   (default)
///   GNANI_TTS_VOICE      Kaveri        (voice from the Timbre v2.5 catalog)
///   GNANI_TTS_LANGUAGE   auto          (auto-detect from the input script)
final class GnaniVoiceAgent: NSObject {

    // MARK: - Configuration

    enum VoiceError: LocalizedError {
        case noAPIKey
        case networkError(Error)
        case timedOut
        case unauthorized
        case insufficientCredit
        case rateLimited
        case emptyAudio
        case emptyTranscription
        case emptyText
        case playbackFailed
        case server(Int, String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "No Gnani API key configured"
            case .networkError(let error): return "Network error: \(error.localizedDescription)"
            case .timedOut: return "Gnani request timed out"
            case .unauthorized: return "Invalid Gnani API key"
            case .insufficientCredit: return "Gnani account has insufficient credit"
            case .rateLimited: return "Gnani is rate limiting requests. Try again in a moment."
            case .emptyAudio: return "Nothing was recorded"
            case .emptyTranscription: return "Nothing heard"
            case .emptyText: return "Nothing to speak"
            case .playbackFailed: return "Could not play the synthesized audio"
            case .server(let code, let message): return "Gnani error \(code): \(message)"
            }
        }
    }

    private static let sttEndpoint = URL(string: "https://api.vachana.ai/stt/v3")!
    private static let ttsEndpoint = URL(string: "https://api.vachana.ai/api/v1/tts/inference")!
    private static let defaultSTTModel = "prisma-v2.5"
    private static let defaultTTSModel = "timbre-v2.5"
    private static let defaultSTTLanguage = "en-IN"
    private static let defaultTTSVoice = "Kaveri"
    private static let defaultTTSLanguage = "auto"
    private static let timeoutSeconds: TimeInterval = 45

    private let logger = Logger(subsystem: "com.secondself.app", category: "GnaniVoice")
    private var audioPlayer: AVAudioPlayer?

    // MARK: - Credentials and settings

    /// Whether a Gnani API key is available in `.env`.
    var hasAPIKey: Bool {
        apiKey != nil
    }

    /// True while synthesized speech is playing.
    var isSpeaking: Bool {
        audioPlayer?.isPlaying ?? false
    }

    private var apiKey: String? {
        let key = AppDelegate.sharedEnvVars["GNANI_API_KEY"]
        guard let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sttModel: String {
        Self.setting("GNANI_STT_MODEL", fallback: Self.defaultSTTModel)
    }

    private var sttLanguage: String {
        Self.setting("GNANI_STT_LANGUAGE", fallback: Self.defaultSTTLanguage)
    }

    private var ttsModel: String {
        Self.setting("GNANI_TTS_MODEL", fallback: Self.defaultTTSModel)
    }

    private var ttsVoice: String {
        Self.setting("GNANI_TTS_VOICE", fallback: Self.defaultTTSVoice)
    }

    private var ttsLanguage: String {
        Self.setting("GNANI_TTS_LANGUAGE", fallback: Self.defaultTTSLanguage)
    }

    private static func setting(_ key: String, fallback: String) -> String {
        guard let value = AppDelegate.sharedEnvVars[key]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty else {
            return fallback
        }
        return value
    }

    // MARK: - Speech to Text (Gnani Prisma v2.5)

    /// Transcribe a short WAV recording with Gnani Prisma v2.5.
    /// - Parameter fileURL: Path to a WAV audio file (16 kHz mono PCM).
    /// - Returns: The transcribed text.
    func transcribe(fileURL: URL) async throws -> String {
        guard let apiKey else {
            throw VoiceError.noAPIKey
        }

        let audioData: Data
        do {
            audioData = try Data(contentsOf: fileURL)
        } catch {
            throw VoiceError.networkError(error)
        }

        guard !audioData.isEmpty else {
            throw VoiceError.emptyAudio
        }

        logger.info("Transcribing \(audioData.count) bytes with Gnani Prisma v2.5")

        var form = MultipartFormData()
        form.addField(name: "model", value: sttModel)
        form.addField(name: "language_code", value: sttLanguage)
        form.addField(name: "format", value: "transcribe")
        form.addFile(
            name: "audio_file",
            fileName: fileURL.lastPathComponent,
            mimeType: "audio/wav",
            data: audioData
        )
        form.finalize()

        var request = URLRequest(url: Self.sttEndpoint)
        request.httpMethod = "POST"
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key-ID")
        request.httpBody = form.data
        request.timeoutInterval = Self.timeoutSeconds

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            logger.error("Prisma request timed out")
            throw VoiceError.timedOut
        } catch {
            logger.error("Prisma network error: \(error.localizedDescription)")
            throw VoiceError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VoiceError.networkError(URLError(.badServerResponse))
        }

        try validate(status: httpResponse.statusCode, body: data, service: "Prisma")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VoiceError.emptyTranscription
        }

        if let success = json["success"] as? Bool, !success {
            throw VoiceError.server(httpResponse.statusCode, Self.errorMessage(from: data))
        }

        guard let transcript = json["transcript"] as? String else {
            throw VoiceError.emptyTranscription
        }

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw VoiceError.emptyTranscription
        }

        logger.info("Prisma transcription: \(trimmed.prefix(60))...")
        return trimmed
    }

    // MARK: - Text to Speech (Gnani Timbre v2.5)

    /// Synthesize text into WAV audio with Gnani Timbre v2.5.
    func synthesize(text: String) async throws -> Data {
        guard let apiKey else {
            throw VoiceError.noAPIKey
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw VoiceError.emptyText
        }

        logger.info("Synthesizing \(trimmed.count) characters with Gnani Timbre v2.5")

        let payload: [String: Any] = [
            "text": trimmed,
            "voice": ttsVoice,
            "model": ttsModel,
            "language": ttsLanguage,
            "speed": 1.0,
            "audio_config": [
                "sample_rate": 24000,
                "num_channels": 1,
                "sample_width": 2,
                "encoding": "linear_pcm",
                "container": "wav",
            ],
        ]

        var request = URLRequest(url: Self.ttsEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key-ID")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = Self.timeoutSeconds

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            logger.error("Timbre request timed out")
            throw VoiceError.timedOut
        } catch {
            logger.error("Timbre network error: \(error.localizedDescription)")
            throw VoiceError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VoiceError.networkError(URLError(.badServerResponse))
        }

        try validate(status: httpResponse.statusCode, body: data, service: "Timbre")

        guard !data.isEmpty else {
            throw VoiceError.server(httpResponse.statusCode, "Empty audio response")
        }

        return data
    }

    // MARK: - Playback

    /// Fetch Timbre audio and play it through the default output device.
    func speak(_ text: String) async throws {
        let audio = try await synthesize(text: text)
        stopSpeaking()

        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(data: audio)
        } catch {
            logger.error("AVAudioPlayer failed: \(error.localizedDescription)")
            throw VoiceError.playbackFailed
        }

        player.prepareToPlay()
        audioPlayer = player
        player.play()
    }

    /// Stop any speech that is currently playing.
    func stopSpeaking() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    // MARK: - Helpers

    private func validate(status: Int, body: Data, service: String) throws {
        switch status {
        case 200:
            return
        case 401, 403:
            logger.error("\(service) auth failed (\(status))")
            throw VoiceError.unauthorized
        case 402:
            logger.error("\(service) insufficient credit (402)")
            throw VoiceError.insufficientCredit
        case 429:
            logger.error("\(service) rate limited (429)")
            throw VoiceError.rateLimited
        default:
            let message = Self.errorMessage(from: body)
            logger.error("\(service) failed \(status): \(message)")
            throw VoiceError.server(status, message)
        }
    }

    private static func errorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let text = String(data: data, encoding: .utf8) ?? "Unknown error"
            return String(text.prefix(300))
        }

        if let detail = json["detail"] as? [String: Any] {
            if let code = detail["error_code"] as? String,
               let message = detail["message"] as? String {
                return "\(code): \(message)"
            }
            if let message = detail["message"] as? String {
                return message
            }
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }

        if let message = json["message"] as? String {
            return message
        }

        let text = String(data: data, encoding: .utf8) ?? "Unknown error"
        return String(text.prefix(300))
    }
}
