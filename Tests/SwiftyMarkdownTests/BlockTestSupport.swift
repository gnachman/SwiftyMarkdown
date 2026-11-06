//
//  BlockTestSupport.swift
//  SwiftyMarkdownTests
//
//  Helpers for end-to-end tests of block structure: render Markdown with the
//  public API and describe each output paragraph by its text, line style, list
//  level, and quote depth.
//

import XCTest
@testable import SwiftyMarkdown

/// One paragraph of rendered output.
struct RenderedBlock: Equatable, CustomStringConvertible {
    let text: String
    /// The swiftyMarkdownLineStyle attribute, or nil for an empty paragraph.
    let style: String?
    /// The swiftyMarkdownListLevel attribute, or nil outside lists.
    let listLevel: Int?
    /// The swiftyMarkdownQuoteDepth attribute, or 0 outside quotes.
    let quoteDepth: Int

    init(_ text: String, style: String?, listLevel: Int? = nil, quoteDepth: Int = 0) {
        self.text = text
        self.style = style
        self.listLevel = listLevel
        self.quoteDepth = quoteDepth
    }

    var description: String {
        var parts = [text.debugDescription, style ?? "empty"]
        if let listLevel {
            parts.append("list \(listLevel)")
        }
        if quoteDepth > 0 {
            parts.append("quote \(quoteDepth)")
        }
        return "(" + parts.joined(separator: ", ") + ")"
    }

    /// Text and style only, for comparing against behavior that predates the
    /// list-level and quote-depth attributes.
    var textAndStyle: String {
        return "(\(text.debugDescription), \(style ?? "empty"))"
    }
}

/// U+2028, which renders a line break inside a paragraph.
let lineSeparator = "\u{2028}"

let blank = RenderedBlock("", style: nil)

func body(_ text: String, list: Int? = nil, quote: Int = 0) -> RenderedBlock {
    return RenderedBlock(text, style: "body", listLevel: list, quoteDepth: quote)
}

func code(_ text: String, list: Int? = nil, quote: Int = 0) -> RenderedBlock {
    return RenderedBlock(text, style: "codeblock", listLevel: list, quoteDepth: quote)
}

func quote(_ text: String, depth: Int = 1, list: Int? = nil) -> RenderedBlock {
    return RenderedBlock(text, style: "blockquote", listLevel: list, quoteDepth: depth)
}

func heading(_ level: Int, _ text: String) -> RenderedBlock {
    return RenderedBlock(text, style: "h\(level)")
}

let rule = RenderedBlock(String(repeating: "\u{2500}", count: 30), style: "horizontalRule")

/// The line style SwiftyMarkdown uses for a list item at a level. It has three;
/// deeper items use the last, and the list-level attribute gives the real depth.
private func listStyle(ordered: Bool, level: Int) -> String {
    let base = ordered ? "orderedList" : "unorderedList"
    switch level {
    case 0:
        return base
    case 1:
        return base + "IndentFirstOrder"
    default:
        return base + "IndentSecondOrder"
    }
}

/// The first paragraph of a bulleted item: one tab per level, the bullet, a tab, the text.
func bullet(_ text: String, level: Int = 0, quote: Int = 0, marker: String = "・") -> RenderedBlock {
    return RenderedBlock(String(repeating: "\t", count: level) + marker + "\t" + text,
                         style: listStyle(ordered: false, level: level),
                         listLevel: level,
                         quoteDepth: quote)
}

/// The first paragraph of a numbered item.
func numbered(_ number: Int, _ text: String, level: Int = 0, quote: Int = 0) -> RenderedBlock {
    return RenderedBlock(String(repeating: "\t", count: level) + "\(number).\t" + text,
                         style: listStyle(ordered: true, level: level),
                         listLevel: level,
                         quoteDepth: quote)
}

func render(_ markdown: String,
            softBreak: SoftBreakStyle = .lineBreak,
            configure: (SwiftyMarkdown) -> Void = { _ in }) -> NSAttributedString {
    let md = SwiftyMarkdown(string: markdown)
    md.applyAttachments = false
    md.softBreakStyle = softBreak
    configure(md)
    return md.attributedString()
}

/// Splits rendered output at newlines, which separate paragraphs.
func blocks(of attributed: NSAttributedString) -> [RenderedBlock] {
    var result = [RenderedBlock]()
    let string = attributed.string as NSString
    var location = 0
    for paragraph in attributed.string.components(separatedBy: "\n") {
        let length = (paragraph as NSString).length
        if length == 0 {
            result.append(blank)
        } else {
            let attributes = attributed.attributes(at: location, effectiveRange: nil)
            result.append(RenderedBlock(paragraph,
                                        style: attributes[.swiftyMarkdownLineStyle] as? String,
                                        listLevel: (attributes[.swiftyMarkdownListLevel] as? NSNumber)?.intValue,
                                        quoteDepth: (attributes[.swiftyMarkdownQuoteDepth] as? NSNumber)?.intValue ?? 0))
        }
        location += length + 1
    }
    precondition(location == string.length + 1)
    return result
}

func blocks(_ markdown: String, softBreak: SoftBreakStyle = .lineBreak) -> [RenderedBlock] {
    return blocks(of: render(markdown, softBreak: softBreak))
}

/// The character styles on the first occurrence of `substring`.
func characterStyles(of substring: String, in attributed: NSAttributedString) -> Set<String> {
    let range = (attributed.string as NSString).range(of: substring)
    precondition(range.location != NSNotFound, "\(substring) not in \(attributed.string)")
    return Set(attributed.attribute(.swiftyMarkdownCharacterStyles, at: range.location, effectiveRange: nil) as? [String] ?? [])
}

func link(at substring: String, in attributed: NSAttributedString) -> String? {
    let range = (attributed.string as NSString).range(of: substring)
    precondition(range.location != NSNotFound, "\(substring) not in \(attributed.string)")
    let value = attributed.attribute(.link, at: range.location, effectiveRange: nil)
    if let url = value as? URL {
        return url.absoluteString
    }
    return value as? String
}

extension XCTestCase {
    /// Compares every field, including list level and quote depth.
    func assertBlocks(_ markdown: String,
                      softBreak: SoftBreakStyle = .lineBreak,
                      _ expected: [RenderedBlock],
                      file: StaticString = #filePath,
                      line: UInt = #line) {
        let actual = blocks(markdown, softBreak: softBreak)
        XCTAssertEqual(actual, expected,
                       "\nMarkdown: \(markdown.debugDescription)\nActual:   \(actual)\nExpected: \(expected)",
                       file: file, line: line)
    }

    /// Compares text and line style only. For behavior that already exists, whose
    /// output doesn't carry the newer list-level and quote-depth attributes yet.
    func assertTextAndStyle(_ markdown: String,
                            softBreak: SoftBreakStyle = .lineBreak,
                            _ expected: [RenderedBlock],
                            file: StaticString = #filePath,
                            line: UInt = #line) {
        let actual = blocks(markdown, softBreak: softBreak).map(\.textAndStyle)
        let wanted = expected.map(\.textAndStyle)
        XCTAssertEqual(actual, wanted,
                       "\nMarkdown: \(markdown.debugDescription)\nActual:   \(actual)\nExpected: \(wanted)",
                       file: file, line: line)
    }
}
