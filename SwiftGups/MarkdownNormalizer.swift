import Foundation

enum MarkdownNormalizer {
    /// SwiftUI `Text(AttributedString(markdown:))` не всегда корректно раскладывает "мягкие" переносы и списки.
    /// Здесь мы приводим markdown к виду, который стабильно отображается:
    /// - маркеры списков `-`/`*` → `•`
    /// - одиночные переносы строк → hard-break (`"  \n"`)
    static func normalizeForText(_ markdown: String) -> String {
        var text = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        
        // Unordered list markers -> bullets (so Text doesn't "схлопывать" list layout)
        text = text.replacingOccurrences(
            of: #"(?m)^(\s*)[-*]\s+"#,
            with: "$1• ",
            options: .regularExpression
        )
        
        // Single newlines become hard breaks in Markdown.
        // Keep paragraph breaks (double newlines) as-is.
        text = text.replacingOccurrences(
            of: #"(?<!\n)\n(?!\n)"#,
            with: "  \n",
            options: .regularExpression
        )
        
        return text
    }
}

