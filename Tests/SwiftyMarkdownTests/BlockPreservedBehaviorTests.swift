//
//  BlockPreservedBehaviorTests.swift
//  SwiftyMarkdownTests
//
//  Output that callers (iTerm2's AI chat, Clippings, tips, and the imgcat
//  Markdown porthole) rely on today. Replacing the line-at-a-time block parser
//  with one that understands paragraphs and containers must keep all of this.
//

import XCTest
@testable import SwiftyMarkdown

final class BlockPreservedBehaviorTests: XCTestCase {

    // MARK: Headings

    func testATXHeadings() {
        assertTextAndStyle("# H1\n## H2 ##\n### H3\n#### H4\n##### H5\n###### H6",
                           [heading(1, "H1"), heading(2, "H2"), heading(3, "H3"),
                            heading(4, "H4"), heading(5, "H5"), heading(6, "H6")])
    }

    func testHeadingWithInlineStyles() {
        let attributed = render("# **Bold** and *it*")
        XCTAssertEqual(attributed.string, "Bold and it")
        XCTAssertTrue(characterStyles(of: "Bold", in: attributed).contains("bold"))
        XCTAssertTrue(characterStyles(of: "it", in: attributed).contains("italic"))
    }

    func testSetextHeadings() {
        assertTextAndStyle("Title\n===\nSub\n---", [heading(1, "Title"), heading(2, "Sub")])
    }

    func testHeadingFontSizeComesFromStyle() {
        let attributed = render("# Big") { $0.h1.fontSize = 31 }
        let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, 31)
    }

    // MARK: Paragraphs

    func testSingleLineParagraph() {
        assertTextAndStyle("Hello", [body("Hello")])
    }

    func testBlankLineBetweenParagraphsIsAnEmptyParagraph() {
        assertTextAndStyle("a\n\nb", [body("a"), blank, body("b")])
    }

    func testEscapedAsterisksAreLiteral() {
        assertTextAndStyle("\\*not italic\\*", [body("*not italic*")])
    }

    // MARK: Thematic breaks

    func testDashesAfterBlankLineAreARule() {
        assertTextAndStyle("a\n\n---\n\nb", [body("a"), blank, rule, blank, body("b")])
    }

    // MARK: Code

    func testFencedCodeIsLiteralAndOneParagraphPerLine() {
        // AI chat finds code blocks by their codeblock line style and joins adjacent
        // ones to place a copy button, so each line stays its own paragraph.
        assertTextAndStyle("```\n**x**\n  y\n```\nafter",
                           [code("**x**"), code("  y"), body("after")])
    }

    func testFencedCodeHasCodeCharacterStyle() {
        let attributed = render("```\nlet a = 1\n```")
        XCTAssertEqual(characterStyles(of: "let a = 1", in: attributed), ["code"])
    }

    func testUnclosedFenceRunsToTheEnd() {
        // A streamed AI reply can stop mid-fence.
        assertTextAndStyle("```\nunclosed\nmore", [code("unclosed"), code("more")])
    }

    func testIndentedCodeAtStart() {
        assertTextAndStyle("    code\n    more", [code("code"), code("more")])
    }

    func testIndentedCodeAfterBlankLine() {
        assertTextAndStyle("text\n\n    indented", [body("text"), blank, code("indented")])
    }

    func testCodeFontComesFromStyle() {
        let attributed = render("use `x` here") { $0.code.fontName = "Menlo-Regular" }
        let range = (attributed.string as NSString).range(of: "x")
        let font = attributed.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.fontName, "Menlo-Regular")
    }

    // MARK: Lists

    func testDashAndStarBullets() {
        assertTextAndStyle("- a\n* b", [bullet("a"), bullet("b")])
    }

    func testCustomBullet() {
        let attributed = render("- a") { $0.bullet = "•" }
        XCTAssertEqual(attributed.string, "•\ta")
    }

    func testOrderedListCountsFromOne() {
        assertTextAndStyle("1. a\n1. b\n1. c", [numbered(1, "a"), numbered(2, "b"), numbered(3, "c")])
    }

    func testTabNestedBullets() {
        assertTextAndStyle("- a\n\t- b\n\t\t- c\n- d",
                           [bullet("a"), bullet("b", level: 1), bullet("c", level: 2), bullet("d")])
    }

    func testTabNestedNumbers() {
        assertTextAndStyle("1. a\n\t1. b\n\t1. c\n1. d",
                           [numbered(1, "a"), numbered(1, "b", level: 1), numbered(2, "c", level: 1), numbered(2, "d")])
    }

    func testNestedItemsIndentFurther() {
        let attributed = render("- a\n\t- b")
        func headIndent(at location: Int) -> CGFloat {
            return (attributed.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 0
        }
        let nested = (attributed.string as NSString).range(of: "b").location
        XCTAssertGreaterThan(headIndent(at: nested), headIndent(at: 0))
    }

    // MARK: Blockquotes

    func testSingleLineBlockquote() {
        assertTextAndStyle("> a", [quote("a")])
    }

    // MARK: Inline

    func testInlineCharacterStyles() {
        let attributed = render("**b** *i* `c` ~~s~~")
        XCTAssertEqual(attributed.string, "b i c s")
        XCTAssertTrue(characterStyles(of: "b", in: attributed).contains("bold"))
        XCTAssertTrue(characterStyles(of: "i", in: attributed).contains("italic"))
        XCTAssertTrue(characterStyles(of: "c", in: attributed).contains("code"))
        XCTAssertTrue(characterStyles(of: "s", in: attributed).contains("strikethrough"))
    }

    func testInlineLink() {
        let attributed = render("see [docs](https://iterm2.com) now")
        XCTAssertEqual(attributed.string, "see docs now")
        XCTAssertEqual(link(at: "docs", in: attributed), "https://iterm2.com")
    }

    func testReferenceLink() {
        let attributed = render("see [docs][1]\n\n[1]: https://iterm2.com")
        XCTAssertEqual(link(at: "docs", in: attributed), "https://iterm2.com")
        XCTAssertFalse(attributed.string.contains("[1]"))
    }

    // MARK: Front matter

    func testClosedFrontMatterIsRemoved() {
        assertTextAndStyle("---\ntitle: x\n---\nbody", [body("body")])
    }

    // MARK: CommonMark rules that already hold

    func testFenceInsideIndentedCodeIsCode() {
        assertBlocks("    ```\n    x\n    ```", [code("```"), code("x"), code("```")])
    }

    func testFenceInterruptsParagraph() {
        assertBlocks("a\n```\nx\n```", [body("a"), code("x")])
    }

    func testHeadingInterruptsParagraph() {
        assertBlocks("a\n# H", [body("a"), heading(1, "H")])
    }

    func testIndentedClosingFenceIsContent() {
        assertBlocks("```\n    ```\nx\n```", [code("    ```"), code("x")])
    }

    func testIndentedCodeDirectlyAfterHeading() {
        assertBlocks("# H\n    code", [heading(1, "H"), code("code")])
    }

    func testTrailingSpacesAtEndOfParagraphAreRemoved() {
        assertBlocks("one  \n\ntwo", [body("one"), blank, body("two")])
    }

    // MARK: Inline and table rules that already hold

    func testCodeSpanContentIsLiteral() {
        let attributed = render("`snake_case` and `*x*` and `https://x.y`")
        XCTAssertEqual(attributed.string, "snake_case and *x* and https://x.y")
        XCTAssertNil(attributed.attribute(.link, at: (attributed.string as NSString).range(of: "https").location, effectiveRange: nil))
    }

    func testUnderscoreEmphasisNextToIdentifier() {
        let attributed = render("_note_: use snake_case")
        XCTAssertEqual(attributed.string, "note: use snake_case")
        XCTAssertTrue(characterStyles(of: "note", in: attributed).contains("italic"))
        XCTAssertFalse(characterStyles(of: "snake", in: attributed).contains("italic"))
    }

    func testURLInLinkTextIsNotLinkedAgain() {
        let attributed = render("[Visit https://iterm2.com today](https://iterm2.com/download)")
        XCTAssertEqual(attributed.string, "Visit https://iterm2.com today")
        XCTAssertEqual(link(at: "Visit", in: attributed), "https://iterm2.com/download")
        XCTAssertEqual(link(at: "today", in: attributed), "https://iterm2.com/download")
    }

    func testParagraphAfterBlankLineFollowingTable() {
        // Models put a blank line after a table, which GFM needs to end it.
        // BlockNewBehaviorTests.testLineDirectlyAfterTableIsARow covers the case without one.
        let attributed = render("| a | b |\n|---|---|\n| 1 | 2 |\n\nAfter the table.")
        let range = (attributed.string as NSString).range(of: "After the table.")
        XCTAssertNotEqual(range.location, NSNotFound)
        XCTAssertEqual(attributed.attribute(.swiftyMarkdownLineStyle, at: range.location, effectiveRange: nil) as? String, "body")
    }

    func testBlockStartEndsTable() {
        let attributed = render("| a | b |\n|---|---|\n| 1 | 2 |\n# After")
        let range = (attributed.string as NSString).range(of: "After")
        XCTAssertNotEqual(range.location, NSNotFound)
        XCTAssertEqual(attributed.attribute(.swiftyMarkdownLineStyle, at: range.location, effectiveRange: nil) as? String, "h1")
    }

    // MARK: Tables

    func testTableCells() {
        let attributed = render("| a | b |\n|---|---|\n| 1 | 2 |")
        XCTAssertEqual(attributed.string.components(separatedBy: "\n").filter { !$0.isEmpty }, ["a", "b", "1", "2"])
    }
}
