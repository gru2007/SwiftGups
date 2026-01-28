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
        // Process line by line to handle newlines correctly
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        
        for (index, line) in lines.enumerated() {
            let isLastLine = index == lines.count - 1
            let nextLineIsEmpty = index < lines.count - 1 && lines[index + 1].isEmpty
            
            if line.isEmpty {
                // Empty line - paragraph break, keep as-is
                result.append("")
            } else if !isLastLine && !nextLineIsEmpty {
                // Non-empty line followed by non-empty line - add hard break
                result.append(line + "  ")
            } else {
                // Last line or line before empty line - no hard break
                result.append(line)
            }
        }
        
        text = result.joined(separator: "\n")
        
        return text
    }
}

