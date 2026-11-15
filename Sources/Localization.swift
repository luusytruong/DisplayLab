import Foundation

/// Localized UI text. The key is the English text (the development language); translations
/// live in Resources/<lang>.lproj/Localizable.strings. Format arguments are all `%@` strings.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

func L(_ key: String, _ args: String...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: args)
}
