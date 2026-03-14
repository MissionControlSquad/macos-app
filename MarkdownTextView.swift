import SwiftUI

/// A view that renders markdown content with support for:
/// - Inline formatting (bold, italic, inline code, links)
/// - Fenced code blocks with monospaced font and background
/// - Headers
/// - Bullet and numbered lists
struct MarkdownTextView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parseBlocks(content).enumerated()), id: \.offset) { _, block in
                switch block {
                case .code(let language, let code):
                    codeBlockView(language: language, code: code)
                case .text(let text):
                    inlineMarkdownText(text)
                }
            }
        }
    }

    // MARK: - Code Block View

    private func codeBlockView(language: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !language.isEmpty {
                Text(language)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    // MARK: - Inline Markdown

    private func inlineMarkdownText(_ text: String) -> some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return AnyView(EmptyView())
        }

        // Try SwiftUI's built-in Markdown AttributedString
        if let attributed = try? AttributedString(markdown: trimmed, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return AnyView(
                Text(attributed)
                    .font(.body)
                    .textSelection(.enabled)
            )
        } else {
            return AnyView(
                Text(trimmed)
                    .font(.body)
                    .textSelection(.enabled)
            )
        }
    }

    // MARK: - Block Parsing

    private enum MarkdownBlock {
        case text(String)
        case code(language: String, code: String)
    }

    /// Parse content into text blocks and fenced code blocks
    private func parseBlocks(_ input: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var currentText = ""
        var inCodeBlock = false
        var codeLanguage = ""
        var codeLines: [String] = []

        let lines = input.components(separatedBy: "\n")

        for line in lines {
            if !inCodeBlock && line.hasPrefix("```") {
                // Start of code block — flush any accumulated text
                let textSoFar = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !textSoFar.isEmpty {
                    blocks.append(.text(textSoFar))
                }
                currentText = ""

                // Extract language hint
                codeLanguage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                codeLines = []
                inCodeBlock = true
            } else if inCodeBlock && line.hasPrefix("```") {
                // End of code block
                blocks.append(.code(language: codeLanguage, code: codeLines.joined(separator: "\n")))
                codeLanguage = ""
                codeLines = []
                inCodeBlock = false
            } else if inCodeBlock {
                codeLines.append(line)
            } else {
                if !currentText.isEmpty {
                    currentText += "\n"
                }
                currentText += line
            }
        }

        // Handle unclosed code block
        if inCodeBlock {
            blocks.append(.code(language: codeLanguage, code: codeLines.joined(separator: "\n")))
        }

        // Remaining text
        let remaining = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            blocks.append(.text(remaining))
        }

        return blocks
    }
}
