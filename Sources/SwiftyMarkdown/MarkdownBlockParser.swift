//
//  MarkdownBlockParser.swift
//  SwiftyMarkdown
//
//  Parses Markdown block structure the way CommonMark and GitHub Flavored
//  Markdown do: a stack of open containers (blockquotes and list items) that
//  each line must continue, leaf blocks inside them, lazy continuation, and
//  tables. The tree is then flattened into the paragraphs SwiftyMarkdown
//  renders, one per leaf block (one per line for code), with each paragraph's
//  list level and quote depth.
//

import Foundation

/// One paragraph of output, before inline parsing.
struct MarkdownParagraph {
    enum Kind {
        /// An empty paragraph standing for a blank source line.
        case blank
        /// Ordinary text. Rendered as a blockquote when a quote encloses it directly.
        case text
        case heading(Int)
        /// One line of a code block.
        case code
        case rule
        case table(ParsedTable)
        /// The first paragraph of a list item. The marker includes the leading
        /// tabs and the tab after it.
        case listItem(marker: String, ordered: Bool)
        /// Where a link reference definition was. Removed before parse returns.
        case definition
    }

    var kind: Kind
    /// Inline source, with soft and hard breaks already resolved, or a literal
    /// code line.
    var text: String
    /// The nesting level of the innermost list item that contains this paragraph.
    var listLevel: Int?
    var quoteDepth: Int
    /// Whether the innermost container is a blockquote rather than a list item.
    var directlyInQuote: Bool
    /// For a line of code, whether it's the first line of its block.
    var startsCodeBlock = false
}

struct MarkdownBlockParserResult {
    var paragraphs: [MarkdownParagraph]
    /// Link reference definitions, by normalized label. The first definition of a
    /// label wins.
    var references: [String: String]
    var frontMatter: [String: String]
    /// The zero-based numbers of the source lines in code blocks, including fences.
    var codeLines: IndexSet
}

final class MarkdownBlockParser {
    static let lineSeparator = "\u{2028}"
    /// How deeply quotes and list items may nest. Deeper markers are text, so that
    /// hostile input can't make parsing quadratic or exhaust the stack.
    static let maximumNesting = 32

    private let softBreak: String
    private let bullet: String

    init(softBreakStyle: SoftBreakStyle, bullet: String) {
        switch softBreakStyle {
        case .lineBreak:
            softBreak = MarkdownBlockParser.lineSeparator
        case .space:
            softBreak = " "
        }
        self.bullet = bullet
    }

    func parse(_ string: String) -> MarkdownBlockParserResult {
        var lines = MarkdownBlockParser.lines(of: string)
        let originalLineCount = lines.count
        let frontMatter = MarkdownBlockParser.removeFrontMatter(&lines)
        // Front matter is removed from the start, so later lines keep their order.
        let firstLineNumber = originalLineCount - lines.count
        let builder = TreeBuilder(lines: lines, firstLineNumber: firstLineNumber)
        for (i, line) in lines.enumerated() {
            builder.add(line: line, number: firstLineNumber + i)
        }
        builder.finish()
        var paragraphs = [MarkdownParagraph]()
        flatten(builder.document, context: Context(), into: &paragraphs)
        return MarkdownBlockParserResult(paragraphs: MarkdownBlockParser.removingDefinitions(paragraphs),
                                         references: builder.references,
                                         frontMatter: frontMatter,
                                         codeLines: builder.codeLines)
    }

    /// A link label as CommonMark matches it: case-folded, trimmed, and with runs
    /// of whitespace collapsed to one space.
    static func normalizedLabel(_ label: String) -> String {
        return label.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    // MARK: - Input

    /// Splits at “\n”, “\r\n”, and “\r”.
    private static func lines(of string: String) -> [String] {
        // A byte order mark is one UTF-16 unit, so dropping it doesn't shift lines.
        let unmarked = string.hasPrefix("\u{FEFF}") ? String(string.dropFirst()) : string
        let normalized = unmarked.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return normalized.components(separatedBy: "\n")
    }

    /// Removes YAML front matter: a first line of “---” and everything through the
    /// next “---” or “...” line. Without a closing line, the opener is an ordinary rule.
    private static func removeFrontMatter(_ lines: inout [String]) -> [String: String] {
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---",
              let close = lines.dropFirst().firstIndex(where: { ["---", "..."].contains($0.trimmingCharacters(in: .whitespaces)) }) else {
            return [:]
        }
        var attributes = [String: String]()
        for line in lines[1..<close] {
            var parts = line.components(separatedBy: ":")
            guard parts.count >= 2 else {
                continue
            }
            let key = parts.removeFirst()
            attributes[key] = parts.joined()
        }
        let firstContent = lines[(close + 1)...].firstIndex { !$0.isEmpty } ?? lines.count
        lines.removeSubrange(0..<firstContent)
        return attributes
    }

    // MARK: - Flattening

    private static func isBlankOrDefinition(_ paragraph: MarkdownParagraph) -> Bool {
        switch paragraph.kind {
        case .blank, .definition:
            return true
        default:
            return false
        }
    }

    /// Removes definitions along with the blank lines that only separated them.
    /// Between two other paragraphs, a run of blank lines and definitions becomes
    /// the longer group of blank lines on either side of the definitions. At the
    /// start or end of the document it disappears.
    private static func removingDefinitions(_ paragraphs: [MarkdownParagraph]) -> [MarkdownParagraph] {
        var result = [MarkdownParagraph]()
        var i = 0
        while i < paragraphs.count {
            guard isBlankOrDefinition(paragraphs[i]) else {
                result.append(paragraphs[i])
                i += 1
                continue
            }
            var end = i
            while end < paragraphs.count && isBlankOrDefinition(paragraphs[end]) {
                end += 1
            }
            let run = paragraphs[i..<end]
            let isDefinition = { (paragraph: MarkdownParagraph) -> Bool in
                if case .definition = paragraph.kind {
                    return true
                }
                return false
            }
            if let first = run.firstIndex(where: isDefinition), let last = run.lastIndex(where: isDefinition) {
                if i > 0 && end < paragraphs.count {
                    let blanks = max(first - i, end - last - 1)
                    result.append(contentsOf: run.filter { !isDefinition($0) }.prefix(blanks))
                }
            } else {
                result.append(contentsOf: run)
            }
            i = end
        }
        return result
    }

    private struct Context {
        var listLevel: Int?
        var quoteDepth = 0
        var directlyInQuote = false
    }

    private func flatten(_ node: Block, context: Context, into output: inout [MarkdownParagraph]) {
        func emit(_ kind: MarkdownParagraph.Kind, _ text: String) {
            output.append(MarkdownParagraph(kind: kind,
                                            text: text,
                                            listLevel: context.listLevel,
                                            quoteDepth: context.quoteDepth,
                                            directlyInQuote: context.directlyInQuote))
        }
        func emitCode(_ lines: [String]) {
            for (i, line) in lines.enumerated() {
                emit(.code, line)
                output[output.count - 1].startsCodeBlock = i == 0
            }
        }
        switch node.kind {
        case .document:
            for child in node.children {
                flatten(child, context: context, into: &output)
            }
        case .quote:
            var inner = context
            inner.quoteDepth += 1
            inner.directlyInQuote = true
            for child in node.children {
                flatten(child, context: inner, into: &output)
            }
        case .list(let list):
            var number = list.start
            for child in node.children {
                if case .item = child.kind {
                    flattenItem(child, list: list, number: number, context: context, into: &output)
                    number += 1
                } else {
                    flatten(child, context: context, into: &output)
                }
            }
        case .item(let list):
            // Items are flattened by their list; this can't happen.
            flattenItem(node, list: list, number: list.start, context: context, into: &output)
        case .paragraph:
            emit(.text, joinedText(of: node.lines))
        case .heading(let level):
            emit(.heading(level), joinedText(of: node.lines))
        case .fencedCode:
            // An empty fenced block stays visible as one empty line of code.
            emitCode(node.lines.isEmpty ? [""] : node.lines)
        case .indentedCode:
            emitCode(node.lines)
        case .rule:
            emit(.rule, "")
        case .table(let table):
            emit(.table(table.parsed), "")
        case .blank:
            emit(.blank, "")
        case .referenceDefinition:
            emit(.definition, "")
        }
    }

    private func flattenItem(_ item: Block,
                             list: ListData,
                             number: Int,
                             context: Context,
                             into output: inout [MarkdownParagraph]) {
        var inner = context
        let level = context.listLevel.map { $0 + 1 } ?? 0
        inner.listLevel = level
        inner.directlyInQuote = false

        var children = item.children[...]
        var text = ""
        // Only a paragraph shares the marker's line. A heading, code, or quote that
        // starts the item follows an empty marker line.
        if let first = children.first, case .paragraph = first.kind {
            text = joinedText(of: first.lines)
            children = children.dropFirst()
        }
        var marker = list.ordered ? "\(number)." : bullet
        if let (checked, rest) = MarkdownBlockParser.taskListItem(text) {
            let checkbox = checked ? "☑" : "☐"
            if list.ordered {
                // The number stays; the checkbox goes before the text.
                text = checkbox + " " + rest
            } else {
                marker = checkbox
                text = rest
            }
        }
        let indent = String(repeating: "\t", count: level)
        output.append(MarkdownParagraph(kind: .listItem(marker: indent + marker + "\t", ordered: list.ordered),
                                        text: text,
                                        listLevel: level,
                                        quoteDepth: context.quoteDepth,
                                        directlyInQuote: false))
        for child in children {
            flatten(child, context: inner, into: &output)
        }
    }

    /// GFM task list items begin with “[ ]”, “[x]”, or “[X]” and whitespace.
    private static func taskListItem(_ text: String) -> (Bool, String)? {
        for (prefix, checked) in [("[ ]", false), ("[x]", true), ("[X]", true)] where text.hasPrefix(prefix) {
            let rest = text.dropFirst(prefix.count)
            if rest.isEmpty {
                return (checked, "")
            }
            if let next = rest.first, next == " " || next == "\t" || String(next) == lineSeparator {
                return (checked, String(rest.dropFirst()))
            }
        }
        return nil
    }

    /// Joins a paragraph's lines. A line ending in two spaces or a backslash is a
    /// hard break; any other line break is a soft break.
    private func joinedText(of lines: [String]) -> String {
        var result = ""
        for (index, rawLine) in lines.enumerated() {
            var line = Substring(rawLine).drop { $0 == " " || $0 == "\t" }
            let isLast = index == lines.count - 1
            if isLast {
                while let last = line.last, last == " " || last == "\t" {
                    line = line.dropLast()
                }
                result += line
                break
            }
            var trailingSpaces = 0
            while let last = line.last, last == " " || last == "\t" {
                if last == " " {
                    trailingSpaces += 1
                }
                line = line.dropLast()
            }
            let trailingBackslashes = line.reversed().prefix { $0 == "\\" }.count
            if trailingSpaces == 0 && trailingBackslashes % 2 == 1 {
                result += line.dropLast()
                result += MarkdownBlockParser.lineSeparator
            } else if trailingSpaces >= 2 {
                result += line
                result += MarkdownBlockParser.lineSeparator
            } else {
                result += line
                result += softBreak
            }
        }
        return result
    }
}

// MARK: - Tree

private struct ListData {
    var ordered: Bool
    /// The bullet character, or the delimiter after the number.
    var delimiter: Character
    var start: Int
    /// The marker's indentation relative to the enclosing container.
    var markerOffset: Int
    /// The marker's width plus the spaces after it.
    var padding: Int
    /// The marker's width, without the spaces after it.
    var markerWidth = 0
}

private struct FenceData {
    var character: Character
    var length: Int
    var indent: Int
}

// A class so that appending a row to a table in a Block's kind doesn't copy every
// earlier row.
private final class TableData {
    let header: [String]
    let alignments: [TableColumnAlignment]
    var rows: [[String]] = []

    init(header: [String], alignments: [TableColumnAlignment]) {
        self.header = header
        self.alignments = alignments
    }

    var parsed: ParsedTable {
        return ParsedTable(headers: header, alignments: alignments, rows: rows)
    }
}

private final class Block {
    enum Kind {
        case document
        case quote
        case list(ListData)
        case item(ListData)
        case paragraph
        case heading(Int)
        case fencedCode(FenceData)
        case indentedCode
        case rule
        case table(TableData)
        case blank
        case referenceDefinition
    }

    var kind: Kind
    weak var parent: Block?
    var children = [Block]()
    var isOpen = true
    var lines = [String]()
    /// Blank lines inside a code block, verbatim. They belong to it only if more
    /// code follows.
    var pendingBlankLines = [String]()
    /// For a fence in a list item, whether it has taken a line at the margin (see
    /// keepInListItemsFence).
    var keepsMarginLines = false

    init(_ kind: Kind) {
        self.kind = kind
    }

    var lastOpenChild: Block? {
        guard let last = children.last, last.isOpen else {
            return nil
        }
        return last
    }

    var hasContent: Bool {
        return children.contains { block in
            if case .blank = block.kind {
                return false
            }
            return true
        }
    }

    var isContainer: Bool {
        switch kind {
        case .document, .quote, .list, .item:
            return true
        default:
            return false
        }
    }

    var acceptsLines: Bool {
        switch kind {
        case .paragraph, .fencedCode, .indentedCode, .table:
            return true
        default:
            return false
        }
    }

    var isNestingContainer: Bool {
        switch kind {
        case .quote, .item:
            return true
        default:
            return false
        }
    }

    var isCode: Bool {
        switch kind {
        case .fencedCode, .indentedCode:
            return true
        default:
            return false
        }
    }

    var isParagraph: Bool {
        if case .paragraph = kind {
            return true
        }
        return false
    }

    var isTable: Bool {
        if case .table = kind {
            return true
        }
        return false
    }

    func canContain(_ child: Kind) -> Bool {
        switch kind {
        case .document, .quote, .item:
            if case .item = child {
                return false
            }
            return true
        case .list:
            if case .item = child {
                return true
            }
            if case .blank = child {
                return true
            }
            return false
        default:
            return false
        }
    }
}

// MARK: - Line scanning

/// A cursor over one line that tracks columns, with tabs stopping every four.
private struct LineScanner {
    let characters: [Character]
    var offset = 0
    var column = 0
    /// True when the cursor sits partway through a tab.
    var partiallyConsumedTab = false

    var nextNonspace = 0
    var nextNonspaceColumn = 0
    var indent = 0
    var blank = false

    init(_ line: String) {
        characters = Array(line)
    }

    mutating func findNextNonspace() {
        var i = offset
        var columns = column
        while i < characters.count {
            let c = characters[i]
            if c == " " {
                columns += 1
            } else if c == "\t" {
                columns += 4 - columns % 4
            } else {
                break
            }
            i += 1
        }
        nextNonspace = i
        nextNonspaceColumn = columns
        indent = columns - column
        blank = i == characters.count
    }

    var peekNonspace: Character? {
        return nextNonspace < characters.count ? characters[nextNonspace] : nil
    }

    func character(at index: Int) -> Character? {
        return index < characters.count ? characters[index] : nil
    }

    mutating func advanceToNextNonspace() {
        offset = nextNonspace
        column = nextNonspaceColumn
        partiallyConsumedTab = false
    }

    mutating func advance(_ count: Int, columns: Bool) {
        var remaining = count
        while remaining > 0 && offset < characters.count {
            if characters[offset] == "\t" {
                let toTab = 4 - column % 4
                if columns {
                    partiallyConsumedTab = toTab > remaining
                    let step = min(remaining, toTab)
                    column += step
                    offset += partiallyConsumedTab ? 0 : 1
                    remaining -= step
                } else {
                    partiallyConsumedTab = false
                    column += toTab
                    offset += 1
                    remaining -= 1
                }
            } else {
                partiallyConsumedTab = false
                offset += 1
                column += 1
                remaining -= 1
            }
        }
    }

    /// Advances past one space or tab if there is one, as after a quote marker.
    mutating func advanceOptionalSpace() {
        if let c = character(at: offset), c == " " || c == "\t" {
            advance(1, columns: true)
        }
    }

    var rest: String {
        if partiallyConsumedTab {
            let spaces = String(repeating: " ", count: 4 - column % 4)
            return spaces + String(characters[min(offset + 1, characters.count)...])
        }
        return String(characters[offset...])
    }

    var restFromNextNonspace: Substring {
        return Substring(String(characters[nextNonspace...]))
    }
}

// MARK: - Building the tree

private final class TreeBuilder {
    let document = Block(.document)
    var references = [String: String]()
    var codeLines = IndexSet()
    private var lineNumber = 0
    private let lines: [String]
    private let firstLineNumber: Int

    init(lines: [String], firstLineNumber: Int) {
        self.lines = lines
        self.firstLineNumber = firstLineNumber
    }

    /// The line number of the line that would close `fence` if the fence took the
    /// lines before it: the next fence line of the same character below this one,
    /// provided it's bare and long enough. Any other fence there (one with an info
    /// string, such as “```sh”, or a shorter one) means the fence was never closed.
    /// Containers aren't tracked, beyond skipping quote markers.
    private func laterCloser(of fence: FenceData) -> Int? {
        var i = lineNumber - firstLineNumber + 1
        while i < lines.count {
            let trimmed = lines[i].drop { $0 == " " || $0 == "\t" || $0 == ">" }
            let length = trimmed.prefix { $0 == fence.character }.count
            if length >= 3 {
                let rest = trimmed.dropFirst(length)
                let bare = rest.allSatisfy { $0 == " " || $0 == "\t" }
                return bare && length >= fence.length ? firstLineNumber + i : nil
            }
            i += 1
        }
        return nil
    }

    private var scanner = LineScanner("")
    private var lastMatched: Block!
    private var unmatchedClosed = false

    private var tip: Block {
        var block = document
        while let child = block.lastOpenChild {
            block = child
        }
        return block
    }

    func add(line: String, number: Int) {
        scanner = LineScanner(line)
        lineNumber = number
        unmatchedClosed = false

        // Phase 1: continue open containers.
        var container = document
        // How many quotes and list items enclose `container`.
        var nesting = 0
        while let child = container.lastOpenChild {
            scanner.findNextNonspace()
            switch matchContinuation(child) {
            case .matched:
                container = child
                if child.isNestingContainer {
                    nesting += 1
                }
                continue
            case .failed:
                if case .item(let item) = child.kind, keepInListItemsFence(item: item) {
                    return
                }
            case .consumedLine:
                return
            }
            break
        }
        lastMatched = container
        var startedItemOnThisLine = false

        // Phase 2: open new blocks.
        while !container.isCode {
            scanner.findNextNonspace()
            let indented = scanner.indent >= 4
            let c = scanner.peekNonspace

            let canNest = nesting < MarkdownBlockParser.maximumNesting
            if !indented, canNest, c == ">" {
                scanner.advanceToNextNonspace()
                scanner.advance(1, columns: false)
                scanner.advanceOptionalSpace()
                container = addChild(.quote, to: container)
                nesting += 1
            } else if !indented, let (level, content) = atxHeading() {
                let heading = addChild(.heading(level), to: container)
                heading.lines = [content]
                heading.isOpen = false
                return
            } else if !indented, let fence = openingFence() {
                scanner.advance(scanner.characters.count, columns: false)
                container = addChild(.fencedCode(fence), to: container)
                codeLines.insert(number)
                return
            } else if !indented, container.isParagraph, let level = setextUnderline() {
                container.kind = .heading(level)
                container.isOpen = false
                return
            } else if !indented, isThematicBreak() {
                let rule = addChild(.rule, to: container)
                rule.isOpen = false
                return
            } else if !indented, container.isParagraph, let table = tableHeader(paragraph: container) {
                closeUnmatched()
                let parent = container.parent!
                container.lines.removeLast()
                if container.lines.isEmpty {
                    parent.children.removeLast()
                } else {
                    container.isOpen = false
                }
                let block = Block(.table(table))
                block.parent = parent
                parent.children.append(block)
                return
            } else if canNest, !indented || isList(container), let data = listMarker(interruptingParagraph: container.isParagraph) {
                if case .list(let existing) = container.kind, existing.ordered == data.ordered, existing.delimiter == data.delimiter {
                    // Continues this list.
                } else {
                    container = addChild(.list(data), to: container)
                }
                container = addChild(.item(data), to: container)
                nesting += 1
                startedItemOnThisLine = true
            } else if !indented, isFootnoteDefinition() {
                // A footnote definition starts a paragraph of its own, even after text.
                addChild(.paragraph, to: container).lines = [scanner.rest]
                return
            } else if indented, !tip.isParagraph, !container.isTable, !scanner.blank {
                // Indented code can't interrupt a paragraph, and an indented line in a
                // table that continues is a row.
                scanner.advance(4, columns: true)
                container = addChild(.indentedCode, to: container)
            } else {
                break
            }
            if !container.isContainer {
                break
            }
        }

        // Phase 3: add the rest of the line.
        scanner.findNextNonspace()
        if !unmatchedClosed, !scanner.blank, tip.isParagraph, container === lastMatched {
            // Lazy continuation.
            tip.lines.append(scanner.rest)
            return
        }
        closeUnmatched()

        if scanner.blank {
            if container.isCode {
                container.pendingBlankLines.append(scanner.rest)
            } else if !startedItemOnThisLine {
                addChild(.blank, to: container).isOpen = false
            }
            return
        }
        switch container.kind {
        case .fencedCode, .indentedCode:
            container.lines.append(contentsOf: container.pendingBlankLines)
            container.pendingBlankLines = []
            container.lines.append(scanner.rest)
            codeLines.insert(number)
        case .paragraph:
            container.lines.append(scanner.rest)
        case .table(let table):
            table.rows.append(MarkdownBlockParser.cells(of: String(scanner.restFromNextNonspace), count: table.header.count))
        default:
            // A link reference definition can't interrupt a paragraph, so it's
            // recognized only where a paragraph would start.
            if addReferenceDefinition(scanner.rest) {
                addChild(.referenceDefinition, to: container).isOpen = false
            } else {
                addChild(.paragraph, to: container).lines = [scanner.rest]
            }
        }
    }

    func finish() {
        var block: Block? = tip
        while let current = block {
            finalize(current)
            block = current.parent
        }
    }

    // MARK: Continuation

    /// Language models often indent a fence under a list item but put its code or
    /// its closing fence at the margin. CommonMark ends the item (and the fence)
    /// there, which turns the rest of the document into code. Instead:
    ///  1. A line that closes the item's open fence closes it, and the item goes on.
    ///  2. Other lines stay in the fence if, at the first of them, the next fence
    ///     below would close it (see laterCloser), the line doesn't follow a blank
    ///     line, and it doesn't start the next item of the same list. After that,
    ///     every line is code until the closer.
    ///  3. While the fence keeps margin lines, its code is measured from the margin
    ///     (see fenceKeepsMarginLines), so indentation inside it stays consistent.
    /// Returns true if it took the line.
    private func keepInListItemsFence(item: ListData) -> Bool {
        let block = tip
        guard case .fencedCode(let fence) = block.kind else {
            return false
        }
        // The scanner is past the prefixes of containers that continued, such as a
        // quote's. A closer may be indented under the item, as far as its text and
        // three more columns.
        scanner.findNextNonspace()
        if scanner.indent <= item.markerOffset + item.padding + 3, TreeBuilder.closes(fence, scanner) {
            block.lines.append(contentsOf: block.pendingBlankLines)
            block.pendingBlankLines = []
            finalize(block)
            codeLines.insert(lineNumber)
            return true
        }
        // Once the fence keeps margin lines, they're all code until its closer.
        if !block.keepsMarginLines {
            guard block.pendingBlankLines.isEmpty, !startsSiblingItem(of: item), laterCloser(of: fence) != nil else {
                return false
            }
            block.keepsMarginLines = true
        }
        block.lines.append(contentsOf: block.pendingBlankLines)
        block.pendingBlankLines = []
        // Without the prefixes of containers that did continue, such as a quote's.
        block.lines.append(scanner.rest)
        codeLines.insert(lineNumber)
        return true
    }

    private static let listMarkerRegex = try! NSRegularExpression(pattern: "^(?:[-+*]|[0-9]{1,9}[.)])(?:[ \\t]|$)")

    /// Whether the line, from its next nonspace character, starts a list item.
    private func startsListItem() -> Bool {
        let rest = String(scanner.restFromNextNonspace)
        return TreeBuilder.listMarkerRegex.firstMatch(in: rest, range: NSRange(location: 0, length: (rest as NSString).length)) != nil
    }

    /// Whether `item` holds an open fence that has taken lines at the margin.
    private func fenceKeepsMarginLines(in item: Block) -> Bool {
        let block = tip
        guard case .fencedCode = block.kind, block.keepsMarginLines else {
            return false
        }
        var ancestor = block.parent
        while let current = ancestor {
            if case .item = current.kind {
                return current === item
            }
            ancestor = current.parent
        }
        return false
    }

    /// Whether the rest of the line starts an item of the same kind of list as `item`.
    private func startsSiblingItem(of item: ListData) -> Bool {
        let rest = Array(scanner.restFromNextNonspace)
        var i = 0
        if item.ordered {
            while i < rest.count, i < 9, rest[i].isASCII, rest[i].isNumber {
                i += 1
            }
            guard i > 0 else {
                return false
            }
        }
        guard i < rest.count, rest[i] == item.delimiter else {
            return false
        }
        return i + 1 == rest.count || rest[i + 1] == " " || rest[i + 1] == "\t"
    }

    private enum Continuation {
        case matched
        case failed
        case consumedLine
    }

    private func matchContinuation(_ block: Block) -> Continuation {
        switch block.kind {
        case .quote:
            guard scanner.indent <= 3, scanner.peekNonspace == ">" else {
                return .failed
            }
            scanner.advanceToNextNonspace()
            scanner.advance(1, columns: false)
            scanner.advanceOptionalSpace()
            return .matched
        case .list:
            return .matched
        case .item(let data):
            if scanner.blank {
                guard block.hasContent else {
                    return .failed
                }
                scanner.advanceToNextNonspace()
                return .matched
            }
            if fenceKeepsMarginLines(in: block) {
                // Its code is measured from the margin, not the item's text, so that
                // lines under the item and lines at the margin keep their relative
                // indentation. keepInListItemsFence takes the line.
                return .failed
            }
            if scanner.indent >= data.markerOffset + data.padding {
                scanner.advance(data.markerOffset + data.padding, columns: true)
                return .matched
            }
            // Under a marker wider than three, such as “100.”, a list item four columns
            // in is meant to nest, though it's short of the item's text column.
            let nestingIndent = data.markerOffset + min(data.markerWidth + 1, 4)
            if scanner.indent >= nestingIndent, startsListItem() {
                scanner.advance(nestingIndent, columns: true)
                return .matched
            }
            return .failed
        case .fencedCode(let fence):
            if scanner.indent <= 3, TreeBuilder.closes(fence, scanner) {
                block.lines.append(contentsOf: block.pendingBlankLines)
                block.pendingBlankLines = []
                finalize(block)
                codeLines.insert(lineNumber)
                return .consumedLine
            }
            var remaining = fence.indent
            while remaining > 0, let c = scanner.character(at: scanner.offset), c == " " || c == "\t" {
                scanner.advance(1, columns: true)
                remaining -= 1
            }
            return .matched
        case .indentedCode:
            if scanner.indent >= 4 {
                scanner.advance(4, columns: true)
                return .matched
            }
            if scanner.blank {
                scanner.advanceToNextNonspace()
                return .matched
            }
            return .failed
        case .paragraph, .table:
            return scanner.blank ? .failed : .matched
        case .document, .heading, .rule, .blank, .referenceDefinition:
            return .failed
        }
    }

    // MARK: Tree edits

    @discardableResult
    private func addChild(_ kind: Block.Kind, to container: Block) -> Block {
        closeUnmatched()
        var parent = container
        while !parent.canContain(kind) {
            finalize(parent)
            parent = parent.parent!
        }
        let block = Block(kind)
        block.parent = parent
        parent.children.append(block)
        return block
    }

    /// Closes the open blocks that this line didn't continue.
    private func closeUnmatched() {
        guard !unmatchedClosed else {
            return
        }
        unmatchedClosed = true
        var block = tip
        while block !== lastMatched {
            finalize(block)
            guard let parent = block.parent else {
                break
            }
            block = parent
        }
    }

    private func finalize(_ block: Block) {
        guard block.isOpen else {
            return
        }
        block.isOpen = false
        if block.isCode, !block.pendingBlankLines.isEmpty, let parent = block.parent {
            // Blank lines after the last line of code aren't part of it.
            for _ in block.pendingBlankLines {
                let blank = Block(.blank)
                blank.isOpen = false
                blank.parent = parent
                parent.children.append(blank)
            }
            block.pendingBlankLines = []
        }
    }

    private func isList(_ block: Block) -> Bool {
        if case .list = block.kind {
            return true
        }
        return false
    }

    // MARK: Block starts

    private func atxHeading() -> (Int, String)? {
        var i = scanner.nextNonspace
        var level = 0
        while scanner.character(at: i) == "#" {
            level += 1
            i += 1
        }
        guard (1...6).contains(level) else {
            return nil
        }
        if let c = scanner.character(at: i), c != " " && c != "\t" {
            return nil
        }
        let whitespace = CharacterSet(charactersIn: " \t")
        var content = String(scanner.characters[i...]).trimmingCharacters(in: whitespace)
        // An optional closing sequence of #s, preceded by a space unless it's everything.
        let withoutHashes = String(content.reversed().drop { $0 == "#" }.reversed())
        if withoutHashes.isEmpty {
            content = ""
        } else if withoutHashes.count < content.count, let last = withoutHashes.last, last == " " || last == "\t" {
            content = withoutHashes.trimmingCharacters(in: whitespace)
        }
        return (level, content)
    }

    private func openingFence() -> FenceData? {
        guard let c = scanner.peekNonspace, c == "`" || c == "~" else {
            return nil
        }
        var i = scanner.nextNonspace
        while scanner.character(at: i) == c {
            i += 1
        }
        let length = i - scanner.nextNonspace
        guard length >= 3 else {
            return nil
        }
        if c == "`" && scanner.characters[i...].contains("`") {
            return nil
        }
        return FenceData(character: c, length: length, indent: scanner.indent)
    }

    /// Whether the line at `scanner`, from its next nonspace character, closes `fence`.
    private static func closes(_ fence: FenceData, _ scanner: LineScanner) -> Bool {
        var i = scanner.nextNonspace
        var length = 0
        while scanner.character(at: i) == fence.character {
            length += 1
            i += 1
        }
        guard length >= fence.length else {
            return false
        }
        return scanner.characters[i...].allSatisfy { $0 == " " || $0 == "\t" }
    }

    private func setextUnderline() -> Int? {
        let rest = scanner.restFromNextNonspace.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
        guard let first = rest.first, first == "=" || first == "-", rest.allSatisfy({ $0 == first }) else {
            return nil
        }
        return first == "=" ? 1 : 2
    }

    private func isThematicBreak() -> Bool {
        guard let c = scanner.peekNonspace, c == "-" || c == "*" || c == "_" else {
            return false
        }
        var count = 0
        for ch in scanner.characters[scanner.nextNonspace...] {
            if ch == c {
                count += 1
            } else if ch != " " && ch != "\t" {
                return false
            }
        }
        return count >= 3
    }

    private func tableHeader(paragraph: Block) -> TableData? {
        guard let headerLine = paragraph.lines.last else {
            return nil
        }
        let delimiterLine = String(scanner.restFromNextNonspace)
        guard delimiterLine.contains("|"), headerLine.contains("|"),
              let alignments = MarkdownBlockParser.alignments(ofDelimiterRow: delimiterLine) else {
            return nil
        }
        let header = MarkdownBlockParser.cells(of: headerLine, count: nil)
        guard header.count == alignments.count else {
            return nil
        }
        return TableData(header: header, alignments: alignments)
    }

    private func listMarker(interruptingParagraph: Bool) -> ListData? {
        let start = scanner.nextNonspace
        guard let c = scanner.character(at: start) else {
            return nil
        }
        var data: ListData
        var markerEnd: Int
        if c == "-" || c == "+" || c == "*" {
            data = ListData(ordered: false, delimiter: c, start: 1, markerOffset: scanner.indent, padding: 0)
            markerEnd = start + 1
        } else if c.isASCII, c.isNumber {
            var i = start
            var digits = ""
            while let d = scanner.character(at: i), d.isASCII, d.isNumber, digits.count < 9 {
                digits.append(d)
                i += 1
            }
            guard let delimiter = scanner.character(at: i), delimiter == "." || delimiter == ")",
                  let number = Int(digits) else {
                return nil
            }
            if interruptingParagraph && number != 1 {
                return nil
            }
            data = ListData(ordered: true, delimiter: delimiter, start: number, markerOffset: scanner.indent, padding: 0)
            markerEnd = i + 1
        } else {
            return nil
        }
        if let next = scanner.character(at: markerEnd), next != " " && next != "\t" {
            return nil
        }
        let restIsBlank = scanner.characters[markerEnd...].allSatisfy { $0 == " " || $0 == "\t" }
        if interruptingParagraph && restIsBlank {
            return nil
        }

        scanner.advanceToNextNonspace()
        scanner.advance(markerEnd - start, columns: true)
        let markerWidth = markerEnd - start
        data.markerWidth = markerWidth
        let saved = scanner
        var spaces = 0
        while spaces <= 4, let ch = scanner.character(at: scanner.offset), ch == " " || ch == "\t" {
            let before = scanner.column
            scanner.advance(1, columns: true)
            spaces += scanner.column - before
        }
        if spaces >= 5 || spaces < 1 || restIsBlank {
            // Content starts one space after the marker; the rest is indentation.
            scanner = saved
            data.padding = markerWidth + 1
            scanner.advanceOptionalSpace()
        } else {
            data.padding = markerWidth + spaces
        }
        return data
    }

    private static let footnoteDefinitionRegex = try! NSRegularExpression(pattern: "^\\[\\^[^\\]]+\\]:")

    private func isFootnoteDefinition() -> Bool {
        let rest = String(scanner.restFromNextNonspace)
        return TreeBuilder.footnoteDefinitionRegex.firstMatch(in: rest, range: NSRange(location: 0, length: (rest as NSString).length)) != nil
    }

    // MARK: Link reference definitions

    // A label starting with “^” is a GFM footnote definition, not a link reference.
    // Anything after the destination other than a title makes the line text.
    private static let referenceDefinitionRegex = try! NSRegularExpression(
        pattern: "^ {0,3}\\[([^\\]^][^\\]]*)\\]:[ \\t]*(<[^>]*>|\\S+)(?:[ \\t]+(?:\"[^\"]*\"|'[^']*'|\\([^)]*\\)))?[ \\t]*$")

    /// Records a line like “[label]: destination "title"” and returns true, or
    /// returns false. The title, which is optional, is ignored.
    private func addReferenceDefinition(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = TreeBuilder.referenceDefinitionRegex.firstMatch(in: trimmed, range: range),
              let labelRange = Range(match.range(at: 1), in: trimmed),
              let destinationRange = Range(match.range(at: 2), in: trimmed) else {
            return false
        }
        let label = MarkdownBlockParser.normalizedLabel(String(trimmed[labelRange]))
        var destination = trimmed[destinationRange]
        if destination.hasPrefix("<") && destination.hasSuffix(">") && destination.count >= 2 {
            destination = destination.dropFirst().dropLast()
        }
        // The first definition of a label wins (CommonMark).
        if references[label] == nil {
            references[label] = String(destination)
        }
        return true
    }
}

// MARK: - Tables

extension MarkdownBlockParser {
    /// Splits a table row into cells, removing the outer pipes and unescaping \|.
    /// With a count, pads or truncates to that many cells.
    fileprivate static func cells(of row: String, count: Int?) -> [String] {
        var line = Substring(row.trimmingCharacters(in: .whitespaces))
        if line.hasPrefix("|") {
            line = line.dropFirst()
        }
        if line.hasSuffix("|") && !line.hasSuffix("\\|") {
            line = line.dropLast()
        }
        var cells = [String]()
        var current = ""
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            let next = line.index(after: i)
            if c == "\\", next < line.endIndex, line[next] == "|" {
                current.append("|")
                i = line.index(after: next)
                continue
            }
            if c == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(c)
            }
            i = next
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        guard let count else {
            return cells
        }
        if cells.count < count {
            cells.append(contentsOf: Array(repeating: "", count: count - cells.count))
        } else if cells.count > count {
            cells = Array(cells.prefix(count))
        }
        return cells
    }

    fileprivate static func alignments(ofDelimiterRow row: String) -> [TableColumnAlignment]? {
        var result = [TableColumnAlignment]()
        for cell in cells(of: row, count: nil) {
            var body = Substring(cell)
            let left = body.hasPrefix(":")
            if left {
                body = body.dropFirst()
            }
            let right = body.hasSuffix(":")
            if right {
                body = body.dropLast()
            }
            guard !body.isEmpty, body.allSatisfy({ $0 == "-" }) else {
                return nil
            }
            if left && right {
                result.append(.center)
            } else if right {
                result.append(.right)
            } else {
                result.append(.left)
            }
        }
        return result
    }
}
