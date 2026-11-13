/// Languages supported in the first release.
public enum Language: String, CaseIterable, Codable, Sendable, Hashable {
    case english = "en"
    case spanish = "es"
    case portuguese = "pt"
    case haitianCreole = "ht"

    public var displayName: String {
        switch self {
        case .english: "English"
        case .spanish: "Español"
        case .portuguese: "Português"
        case .haitianCreole: "Kreyòl ayisyen"
        }
    }
}

/// A source → target direction for translation.
public struct LanguagePair: Codable, Sendable, Hashable {
    public let source: Language
    public let target: Language

    public init(source: Language, target: Language) {
        precondition(source != target, "source and target must differ")
        self.source = source
        self.target = target
    }

    /// Directions offered in the first release, listed in the order the picker shows them.
    ///
    /// English → Spanish and English → Portuguese use Apple's on-device Translation framework and speak
    /// the result aloud. The Spanish, Portuguese, and Haitian Creole → English directions use Whisper's
    /// translate task and need no translation model.
    public static let firstRelease: [LanguagePair] = [
        LanguagePair(source: .english, target: .spanish),
        LanguagePair(source: .english, target: .portuguese),
        LanguagePair(source: .spanish, target: .english),
        LanguagePair(source: .portuguese, target: .english),
        LanguagePair(source: .haitianCreole, target: .english),
    ]

    /// True when this direction's output comes from a translation model rather than Whisper's translate task.
    public var needsTranslationModel: Bool {
        target != .english
    }
}
