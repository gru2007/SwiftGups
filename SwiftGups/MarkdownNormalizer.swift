import Foundation

enum MarkdownNormalizer {
    /// SwiftUI `Text(AttributedString(markdown:))` не всегда корректно раскладывает "мягкие" переносы и списки.
    /// Здесь мы приводим markdown к виду, который стабильно отображается:
    /// - маркеры списков `-`/`*` → `•`
    /// - одиночные переносы строк → hard-break (`"  \n"`)
    /// - заголовки markdown обрабатываются корректно
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
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Check if line is a markdown header (starts with #)
            let isHeader = trimmedLine.hasPrefix("#")
            
            if line.isEmpty {
                // Empty line - paragraph break, keep as-is
                result.append("")
            } else if isHeader {
                // Headers should not have hard breaks after them
                // Ensure there's a blank line after headers for proper markdown parsing
                result.append(line)
                if !isLastLine && !nextLineIsEmpty {
                    // Add blank line after header if next line is not empty
                    result.append("")
                }
            } else {
                // Check if previous line was a header
                let prevLineWasHeader = index > 0 && lines[index - 1].trimmingCharacters(in: .whitespaces).hasPrefix("#")
                
                if !isLastLine && !nextLineIsEmpty && !prevLineWasHeader {
                    // Non-empty line followed by non-empty line - add hard break
                    result.append(line + "  ")
                } else {
                    // Last line, line before empty line, or line after header - no hard break
                    result.append(line)
                }
            }
        }
        
        text = result.joined(separator: "\n")
        
        return text
    }
}

