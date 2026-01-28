import SwiftUI

struct AppMarkdownText: View {
    let markdown: String
    
    var body: some View {
        let normalized = MarkdownNormalizer.normalizeForText(markdown)
        
        if let attributed = try? AttributedString(
            markdown: normalized,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        ) {
            Text(attributed)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(markdown)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

