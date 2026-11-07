//
//  InlineNewBehaviorTests.swift
//  SwiftyMarkdownTests
//
//  Inline GitHub Flavored Markdown, as language models write it, that the
//  current tokenizer gets wrong. They're expected to fail until it's fixed.
//

import XCTest
@testable import SwiftyMarkdown

final class InlineNewBehaviorTests: XCTestCase {

    // Every test here describes behavior the current tokenizer lacks. The
    // expectation is strict, so a test that starts passing fails and should
    // move to a suite of behavior that holds.
    override func invokeTest() {
        XCTExpectFailure("Not implemented yet") {
            super.invokeTest()
        }
    }

    // MARK: Emphasis

    func testIntrawordUnderscoresAreLiteral() {
        // Today “snake_case_name” loses its underscores and turns italic.
        let attributed = render("Call snake_case_name now.")
        XCTAssertEqual(attributed.string, "Call snake_case_name now.")
        XCTAssertFalse(characterStyles(of: "case", in: attributed).contains("italic"))
    }

    func testSingleTildeStrikethrough() {
        let attributed = render("~gone~ here")
        XCTAssertEqual(attributed.string, "gone here")
        XCTAssertTrue(characterStyles(of: "gone", in: attributed).contains("strikethrough"))
    }

    // MARK: Links

    func testLinkDestinationWithParentheses() {
        // Today the whole link shows as raw text.
        let attributed = render("[wiki](https://en.wikipedia.org/wiki/Foo_(bar)) end")
        XCTAssertEqual(attributed.string, "wiki end")
        XCTAssertEqual(link(at: "wiki", in: attributed), "https://en.wikipedia.org/wiki/Foo_(bar)")
    }

    func testAngleBracketAutolink() {
        let attributed = render("<https://iterm2.com>")
        XCTAssertEqual(attributed.string, "https://iterm2.com")
        XCTAssertEqual(link(at: "iterm2", in: attributed), "https://iterm2.com")
    }

    func testBareURLIsLinkedWithoutTrailingPunctuation() {
        let attributed = render("See https://iterm2.com/docs.")
        XCTAssertEqual(attributed.string, "See https://iterm2.com/docs.")
        XCTAssertEqual(link(at: "docs", in: attributed), "https://iterm2.com/docs")
        let period = (attributed.string as NSString).length - 1
        XCTAssertNil(attributed.attribute(.link, at: period, effectiveRange: nil))
    }

    func testBareURLInParentheses() {
        let attributed = render("Docs are online (https://iterm2.com).")
        XCTAssertEqual(attributed.string, "Docs are online (https://iterm2.com).")
        XCTAssertEqual(link(at: "iterm2", in: attributed), "https://iterm2.com")
        let closing = (attributed.string as NSString).range(of: ")").location
        XCTAssertNil(attributed.attribute(.link, at: closing, effectiveRange: nil))
    }

    func testWWWAutolink() {
        let attributed = render("Visit www.iterm2.com today")
        XCTAssertEqual(link(at: "www", in: attributed), "http://www.iterm2.com")
    }

    // MARK: Code spans

    func testDoubleBacktickCodeSpan() {
        let attributed = render("Use ``a`b`` here")
        XCTAssertEqual(attributed.string, "Use a`b here")
        XCTAssertTrue(characterStyles(of: "a`b", in: attributed).contains("code"))
    }

    // MARK: Escapes, entities, and HTML

    func testBackslashEscapesOfPunctuation() {
        XCTAssertEqual(render("\\# \\> \\- \\+ \\! \\| \\~ \\. \\[x\\]").string, "# > - + ! | ~ . [x]")
    }

    func testEntities() {
        XCTAssertEqual(render("&amp; &lt;tag&gt; &copy; &#169; &#xA9;").string, "& <tag> © © ©")
    }

    func testBreakTagIsALineBreak() {
        // Models use <br> for line breaks, especially inside table cells.
        XCTAssertEqual(render("one<br>two<br/>three").string, "one" + lineSeparator + "two" + lineSeparator + "three")
    }
}
