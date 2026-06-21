import Markdown
import SwiftUI

struct ShellMarkdownView: View {
    var source: String
    var isStreaming: Bool

    private var shouldUsePreview: Bool {
        source.count > (isStreaming ? 12_000 : 45_000)
    }

    private var blocks: [Markup] {
        let document = Document(parsing: preparedSource(source, isStreaming: isStreaming))
        return Array(document.children)
    }

    var body: some View {
        if shouldUsePreview {
            LargeMarkdownPreview(source: source, isStreaming: isStreaming)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    ShellMarkdownBlock(markup: block, listDepth: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct LargeMarkdownPreview: View {
    var source: String
    var isStreaming: Bool

    private var preview: String {
        if isStreaming {
            return source.tail(maxCharacters: 12_000, prefix: "[Large response streaming - showing the latest text]\n\n")
        }
        return source.middleElidedPreview(head: 24_000, tail: 12_000)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preview)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(isStreaming ? "Large response is still streaming. Full text will be available from copy." : "Large response preview. Use the row copy button for the full text.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(PiShellTheme.surface.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: PiShellTheme.controlRadius, style: .continuous))
    }
}

private struct ShellMarkdownBlock: View {
    var markup: Markup
    var listDepth: Int

    var body: some View {
        if let heading = markup as? Heading {
            ShellMarkdownInline(markup: heading)
                .font(headingFont(heading.level))
                .padding(.top, heading.level <= 2 ? 4 : 2)
        } else if let paragraph = markup as? Paragraph {
            ShellMarkdownInline(markup: paragraph)
        } else if let codeBlock = markup as? CodeBlock {
            ShellMarkdownCodeBlock(codeBlock: codeBlock)
        } else if let list = markup as? UnorderedList {
            ShellMarkdownList(items: Array(list.listItems), ordered: false, startIndex: 1, depth: listDepth)
        } else if let list = markup as? OrderedList {
            ShellMarkdownList(items: Array(list.listItems), ordered: true, startIndex: Int(list.startIndex), depth: listDepth)
        } else if let table = markup as? Markdown.Table {
            ShellMarkdownTableView(table: table)
        } else if let blockquote = markup as? BlockQuote {
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(blockquote.children.enumerated()), id: \.offset) { _, child in
                        ShellMarkdownBlock(markup: child, listDepth: listDepth)
                    }
                }
            }
            .padding(.vertical, 2)
        } else if markup is ThematicBreak {
            Divider()
                .padding(.vertical, 4)
        } else if let html = markup as? HTMLBlock {
            Text(html.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.body.monospaced())
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
        } else {
            ForEach(Array(markup.children.enumerated()), id: \.offset) { _, child in
                ShellMarkdownBlock(markup: child, listDepth: listDepth)
            }
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title3.weight(.semibold)
        case 2: .headline.weight(.semibold)
        default: .callout.weight(.semibold)
        }
    }
}

private struct ShellMarkdownInline: View {
    var markup: Markup

    var body: some View {
        Text(attributedInline(markup))
            .font(.body)
            .textSelection(.enabled)
    }
}

private struct ShellMarkdownCodeBlock: View {
    var codeBlock: CodeBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let language = codeBlock.language, !language.isEmpty {
                Text(language)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(codeBlock.code)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(PiShellTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: PiShellTheme.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PiShellTheme.controlRadius, style: .continuous)
                .stroke(PiShellTheme.separator.opacity(0.35), lineWidth: 1)
        }
    }
}

private struct ShellMarkdownList: View {
    var items: [ListItem]
    var ordered: Bool
    var startIndex: Int
    var depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                ShellMarkdownListItem(
                    item: item,
                    marker: marker(for: item, index: index),
                    depth: depth
                )
            }
        }
    }

    private func marker(for item: ListItem, index: Int) -> String {
        if let checkbox = item.checkbox {
            return checkbox == .checked ? "[x]" : "[ ]"
        }
        return ordered ? "\(startIndex + index)." : "-"
    }
}

private struct ShellMarkdownListItem: View {
    var item: ListItem
    var marker: String
    var depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 8) {
                Text(marker)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: markerWidth, alignment: .trailing)
                VStack(alignment: .leading, spacing: 5) {
                    let children = Array(item.children)
                    let inlineChildren = children.filter { $0 is Paragraph }
                    if inlineChildren.isEmpty {
                        EmptyView()
                    } else {
                        ForEach(Array(inlineChildren.enumerated()), id: \.offset) { _, child in
                            ShellMarkdownBlock(markup: child, listDepth: depth)
                        }
                    }
                    ForEach(Array(children.filter { !($0 is Paragraph) }.enumerated()), id: \.offset) { _, child in
                        if let unordered = child as? UnorderedList {
                            ShellMarkdownList(items: Array(unordered.listItems), ordered: false, startIndex: 1, depth: depth + 1)
                                .padding(.top, 1)
                        } else if let ordered = child as? OrderedList {
                            ShellMarkdownList(items: Array(ordered.listItems), ordered: true, startIndex: Int(ordered.startIndex), depth: depth + 1)
                                .padding(.top, 1)
                        } else {
                            ShellMarkdownBlock(markup: child, listDepth: depth + 1)
                        }
                    }
                }
            }
        }
        .padding(.leading, CGFloat(depth) * 14)
    }

    private var markerWidth: CGFloat {
        max(18, CGFloat(marker.count) * 8)
    }
}

private struct ShellMarkdownTableView: View {
    var table: Markdown.Table

    private var headerCells: [Markdown.Table.Cell] {
        Array(table.head.cells)
    }

    private var rows: [[Markdown.Table.Cell]] {
        Array(table.body.rows).map { Array($0.cells) }
    }

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(headerCells.indices, id: \.self) { index in
                        cellView(headerCells[index], column: index, isHeader: true)
                    }
                }
                ForEach(rows.indices, id: \.self) { rowIndex in
                    let row = rows[rowIndex]
                    GridRow {
                        ForEach(0..<max(headerCells.count, row.count), id: \.self) { index in
                            if index < row.count {
                                cellView(row[index], column: index, isHeader: false)
                            } else {
                                cellView(nil, column: index, isHeader: false)
                            }
                        }
                    }
                }
            }
            .background(PiShellTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: PiShellTheme.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PiShellTheme.controlRadius, style: .continuous)
                    .stroke(PiShellTheme.separator.opacity(0.45), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private func cellView(_ cell: Markdown.Table.Cell?, column: Int, isHeader: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let cell {
                Text(attributedTableCell(cell))
                    .textSelection(.enabled)
                    .font(isHeader ? .body.weight(.semibold) : .body)
                    .frame(maxWidth: .infinity, alignment: alignment(for: column))
            }
        }
        .frame(minWidth: 100, maxWidth: 260, minHeight: 30, alignment: .topLeading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(isHeader ? Color.secondary.opacity(0.08) : Color.clear)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(PiShellTheme.separator.opacity(0.35))
                .frame(width: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PiShellTheme.separator.opacity(isHeader ? 0.5 : 0.25))
                .frame(height: 1)
        }
    }

    private func alignment(for column: Int) -> Alignment {
        let alignments = table.columnAlignments
        guard column < alignments.count else { return SwiftUI.Alignment.leading }
        switch alignments[column] {
        case .some(.center):
            return SwiftUI.Alignment.center
        case .some(.right):
            return SwiftUI.Alignment.trailing
        default:
            return SwiftUI.Alignment.leading
        }
    }
}

private func attributedInline(_ markup: Markup) -> AttributedString {
    if let text = markup as? Markdown.Text {
        return AttributedString(text.string)
    }
    if let code = markup as? InlineCode {
        return styled(code.code, presentation: .code)
    }
    if let html = markup as? InlineHTML {
        return AttributedString(html.rawHTML)
    }
    if markup is LineBreak {
        return AttributedString("\n")
    }
    if let softBreak = markup as? SoftBreak {
        return AttributedString(softBreak.plainText)
    }
    if let image = markup as? Markdown.Image {
        return AttributedString(image.plainText)
    }

    var attributed = attributedChildren(markup)
    if markup is Strong {
        attributed = applying(.stronglyEmphasized, to: attributed)
    } else if markup is Emphasis {
        attributed = applying(.emphasized, to: attributed)
    } else if markup is Strikethrough {
        attributed = applying(.strikethrough, to: attributed)
    } else if let link = markup as? Markdown.Link, let destination = link.destination, let url = URL(string: destination) {
        attributed.link = url
        attributed.foregroundColor = .accentColor
    }
    return attributed
}

private func attributedChildren(_ markup: Markup) -> AttributedString {
    Array(markup.children).reduce(into: AttributedString()) { result, child in
        result += attributedInline(child)
    }
}

private func attributedTableCell(_ cell: Markdown.Table.Cell) -> AttributedString {
    let children = Array(cell.children)
    guard !children.isEmpty else { return AttributedString() }
    return children.reduce(into: AttributedString()) { result, child in
        if let paragraph = child as? Paragraph {
            result += attributedChildren(paragraph)
        } else {
            result += attributedInline(child)
        }
    }
}

private func styled(_ text: String, presentation: InlinePresentationIntent) -> AttributedString {
    var attributed = AttributedString(text)
    attributed.inlinePresentationIntent = presentation
    return attributed
}

private func applying(_ presentation: InlinePresentationIntent, to source: AttributedString) -> AttributedString {
    var attributed = source
    attributed.inlinePresentationIntent = presentation
    return attributed
}

private func preparedSource(_ source: String, isStreaming: Bool) -> String {
    let normalized = source.replacingOccurrences(of: "\t", with: "    ")
    guard isStreaming else { return normalized }
    return closingUnterminatedFence(in: normalized)
}

private func closingUnterminatedFence(in source: String) -> String {
    var openFence: String?
    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let fence: String?
        if trimmed.hasPrefix("```") {
            fence = "```"
        } else if trimmed.hasPrefix("~~~") {
            fence = "~~~"
        } else {
            fence = nil
        }
        guard let fence else { continue }
        if openFence == nil {
            openFence = fence
        } else if openFence == fence {
            openFence = nil
        }
    }
    guard let openFence else { return source }
    return source + "\n" + openFence
}

private extension String {
    func tail(maxCharacters: Int, prefix: String = "") -> String {
        guard count > maxCharacters else { return self }
        let start = index(endIndex, offsetBy: -maxCharacters)
        return prefix + String(self[start...])
    }

    func middleElidedPreview(head: Int, tail: Int) -> String {
        guard count > head + tail else { return self }
        let headEnd = index(startIndex, offsetBy: head)
        let tailStart = index(endIndex, offsetBy: -tail)
        return String(self[..<headEnd])
            + "\n\n[Large response shortened in the transcript. Use copy for the full text.]\n\n"
            + String(self[tailStart...])
    }
}
