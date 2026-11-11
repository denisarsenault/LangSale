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

    /// First-release sources. Target defaults to English until product confirms otherwise.
    public static let firstRelease: [LanguagePair] = [
        LanguagePair(source: .spanish, target: .english),
        LanguagePair(source: .portuguese, target: .english),
        LanguagePair(source: .haitianCreole, target: .english),
    ]
}
