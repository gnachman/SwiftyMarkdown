//
//  BlockNewBehaviorTests.swift
//  SwiftyMarkdownTests
//
//  Block structure that the line-at-a-time parser gets wrong: paragraphs that
//  span lines, blocks inside list items and quotes, nesting by indentation,
//  list numbering, and CommonMark's rules for which blocks may interrupt a
//  paragraph. These fail until the block parser understands paragraphs and
//  containers.
//

import XCTest
@testable import SwiftyMarkdown

final class BlockNewBehaviorTests: XCTestCase {

    // MARK: Paragraphs span lines

    func testSoftBreakIsALineBreakByDefault() {
        assertBlocks("one\ntwo\nthree", [body("one" + lineSeparator + "two" + lineSeparator + "three")])
    }

    func testSoftBreakAsSpaceReflows() {
        assertBlocks("one\ntwo\nthree", softBreak: .space, [body("one two three")])
    }

    func testLeadingWhitespaceOfContinuationLineIsDropped() {
        assertBlocks("one\n   two", softBreak: .space, [body("one two")])
    }

    func testBlankLineSeparatesParagraphs() {
        assertBlocks("a\nb\n\nc\nd", softBreak: .space, [body("a b"), blank, body("c d")])
    }

    func testWhitespaceOnlyLineIsBlank() {
        // Today it turns the line above into a heading.
        assertBlocks("a\n   \nb", [body("a"), blank, body("b")])
    }

    func testTrailingTwoSpacesAreAHardBreak() {
        assertBlocks("one  \ntwo", softBreak: .space, [body("one" + lineSeparator + "two")])
    }

    func testTrailingBackslashIsAHardBreak() {
        assertBlocks("one\\\ntwo", softBreak: .space, [body("one" + lineSeparator + "two")])
    }

    func testMultiLineSetextHeading() {
        assertBlocks("a\nb\n===", softBreak: .space, [heading(1, "a b")])
    }

    func testEmphasisSpansASoftBreak() {
        let attributed = render("*one\ntwo*", softBreak: .space)
        XCTAssertEqual(attributed.string, "one two")
        XCTAssertTrue(characterStyles(of: "one", in: attributed).contains("italic"))
        XCTAssertTrue(characterStyles(of: "two", in: attributed).contains("italic"))
    }

    func testLinkTextSpansASoftBreak() {
        let attributed = render("[one\ntwo](https://iterm2.com)", softBreak: .space)
        XCTAssertEqual(attributed.string, "one two")
        XCTAssertEqual(link(at: "two", in: attributed), "https://iterm2.com")
    }

    // MARK: What may interrupt a paragraph

    func testQuoteInterruptsParagraph() {
        assertBlocks("a\n> q", [body("a"), quote("q")])
    }

    func testRuleInterruptsParagraph() {
        assertBlocks("a\n***", [body("a"), rule])
    }

    func testBulletInterruptsParagraph() {
        assertBlocks("a\n- b", [body("a"), bullet("b")])
    }

    func testOrderedListStartingAtOneInterruptsParagraph() {
        assertBlocks("a\n1. b", [body("a"), numbered(1, "b")])
    }

    func testOrderedListStartingElsewhereDoesNotInterruptParagraph() {
        assertBlocks("The project was first released in\n2020. It has grown since.", softBreak: .space,
                     [body("The project was first released in 2020. It has grown since.")])
    }

    func testIndentedLineContinuesParagraph() {
        // Indented code can't interrupt a paragraph. Today this becomes code.
        assertBlocks("a\n    b", softBreak: .space, [body("a b")])
    }

    // MARK: Lazy continuation

    func testLazyContinuationOfListItem() {
        assertBlocks("- a\nb", softBreak: .space, [bullet("a b")])
    }

    func testLazyContinuationOfQuote() {
        assertBlocks("> a\nb", softBreak: .space, [quote("a b")])
    }

    // MARK: List items span lines and contain blocks

    func testListItemContinuationLine() {
        assertBlocks("- a long\n  item", softBreak: .space, [bullet("a long item")])
    }

    func testListItemContinuationLineAsLineBreak() {
        assertBlocks("- a long\n  item", [bullet("a long" + lineSeparator + "item")])
    }

    func testSecondParagraphInListItem() {
        assertBlocks("1. a\n\n   b\n\n2. c",
                     [numbered(1, "a"), blank, body("b", list: 0), blank, numbered(2, "c")])
    }

    func testTwoMoreParagraphsInListItemIndentedFourSpaces() {
        assertBlocks("1. a\n\n    b\n\n    c",
                     [numbered(1, "a"), blank, body("b", list: 0), blank, body("c", list: 0)])
    }

    func testNextItemDirectlyAfterContinuationParagraph() {
        assertBlocks("1. a\n\n   b\n2. c",
                     [numbered(1, "a"), blank, body("b", list: 0), numbered(2, "c")])
    }

    func testFencedCodeInListItem() {
        assertBlocks("1. a\n\n   ```\n   x\n   ```\n2. b",
                     [numbered(1, "a"), blank, code("x", list: 0), numbered(2, "b")])
    }

    func testIndentedCodeInListItem() {
        // Code inside an item is indented four past the item's text column (2 here).
        assertBlocks("- a\n\n      code", [bullet("a"), blank, code("code", list: 0)])
    }

    func testQuoteInListItem() {
        assertBlocks("- a\n\n  > q", [bullet("a"), blank, quote("q", list: 0)])
    }

    func testNestedItemAfterContinuationParagraph() {
        assertBlocks("- a\n\n  detail\n\n  - sub",
                     [bullet("a"), blank, body("detail", list: 0), blank, bullet("sub", level: 1)])
    }

    func testUnindentedParagraphEndsList() {
        assertBlocks("- a\n\nb", [bullet("a"), blank, body("b")])
    }

    func testFenceInListItemClosesWithTheItem() {
        assertBlocks("- ```\n  x\n\nafter", [bullet(""), code("x", list: 0), blank, body("after")])
    }

    // MARK: Nesting by indentation

    func testTwoSpaceNesting() {
        assertBlocks("- a\n  - b\n    - c",
                     [bullet("a"), bullet("b", level: 1), bullet("c", level: 2)])
    }

    func testFourSpaceNesting() {
        assertBlocks("- a\n    - b\n        - c",
                     [bullet("a"), bullet("b", level: 1), bullet("c", level: 2)])
    }

    func testNestingUnderNumberUsesItsTextColumn() {
        assertBlocks("1. a\n   - b", [numbered(1, "a"), bullet("b", level: 1)])
    }

    func testTwoAndFourSpaceListsInOneDocument() {
        assertBlocks("- a\n  - b\n\npara\n\n- c\n    - d",
                     [bullet("a"), bullet("b", level: 1), blank, body("para"), blank,
                      bullet("c"), bullet("d", level: 1)])
    }

    func testIndentationInsideCodeDoesNotAffectNesting() {
        assertBlocks("```\nsteps:\n  - name: build\n```\n\n- a\n    - b",
                     [code("steps:"), code("  - name: build"), blank, bullet("a"), bullet("b", level: 1)])
    }

    func testItemBetweenColumnsNestsUnderNearestParent() {
        assertBlocks("- a\n    - b\n  - c", [bullet("a"), bullet("b", level: 1), bullet("c", level: 1)])
    }

    func testOneSpaceIsNotNesting() {
        assertBlocks("- a\n - b", [bullet("a"), bullet("b")])
    }

    func testMoreThanThreeLevels() {
        // Today the fourth level is flattened to the top.
        assertBlocks("- a\n  - b\n    - c\n      - d",
                     [bullet("a"), bullet("b", level: 1), bullet("c", level: 2), bullet("d", level: 3)])
    }

    func testTabNestingCarriesListLevel() {
        assertBlocks("- a\n\t- b\n\t\t- c", [bullet("a"), bullet("b", level: 1), bullet("c", level: 2)])
    }

    // MARK: Numbering

    func testListStartsAtItsFirstNumber() {
        assertBlocks("3. a\n4. b", [numbered(3, "a"), numbered(4, "b")])
    }

    func testListNumbersCountFromTheStart() {
        // As in CommonMark, only the first number matters.
        assertBlocks("3. a\n7. b\n7. c", [numbered(3, "a"), numbered(4, "b"), numbered(5, "c")])
    }

    func testTwoDigitNumbers() {
        assertBlocks("1. a\n2. b\n10. c", [numbered(1, "a"), numbered(2, "b"), numbered(3, "c")])
    }

    func testParenthesisMarker() {
        assertBlocks("1) a\n2) b", [numbered(1, "a"), numbered(2, "b")])
    }

    func testPlusBullet() {
        assertBlocks("+ a", [bullet("a")])
    }

    func testBlankLineBetweenItemsKeepsNumbering() {
        assertBlocks("1. a\n\n2. b", [numbered(1, "a"), blank, numbered(2, "b")])
    }

    func testNumberingContinuesAfterCodeInItem() {
        assertBlocks("1. a\n\n   ```\n   x\n   ```\n\n2. b",
                     [numbered(1, "a"), blank, code("x", list: 0), blank, numbered(2, "b")])
    }

    func testNestedNumbering() {
        assertBlocks("1. a\n   1. b\n   2. c\n2. d",
                     [numbered(1, "a"), numbered(1, "b", level: 1), numbered(2, "c", level: 1), numbered(2, "d")])
    }

    func testNumberingRestartsAfterParagraphAtMargin() {
        assertBlocks("3. a\n\nx\n\n5. b", [numbered(3, "a"), blank, body("x"), blank, numbered(5, "b")])
    }

    // MARK: Blockquotes

    func testQuoteLinesFormOneParagraph() {
        assertBlocks("> a\n> b", softBreak: .space, [quote("a b")])
    }

    func testQuoteParagraphsSeparatedByBlankQuoteLine() {
        assertBlocks("> a\n>\n> b", [quote("a"), blank, quote("b")])
    }

    func testNestedQuote() {
        assertBlocks("> > a", [quote("a", depth: 2)])
    }

    func testQuoteDepthChanges() {
        assertBlocks("> a\n>\n> > b", [quote("a"), blank, quote("b", depth: 2)])
    }

    func testListInQuote() {
        assertBlocks("> - a\n> - b", [bullet("a", quote: 1), bullet("b", quote: 1)])
    }

    func testCodeInQuote() {
        assertBlocks("> ```\n> x\n> ```", [code("x", quote: 1)])
    }

    // MARK: Fences

    func testFenceWithInfoStringContainingPunctuation() {
        // Today “```c++” isn't an opener, so its closing fence opens a block that
        // swallows the rest of the document.
        assertBlocks("```c++\nint x;\n```\nafter", [code("int x;"), body("after")])
    }

    func testFenceWithCapitalizedInfoString() {
        assertBlocks("```Swift\nlet x = 1\n```\nafter", [code("let x = 1"), body("after")])
    }

    func testTildeFence() {
        assertBlocks("~~~\nx\n~~~\nafter", [code("x"), body("after")])
    }

    func testShorterFenceInsideLongerFenceIsContent() {
        assertBlocks("````\n```\nx\n```\n````\nafter",
                     [code("```"), code("x"), code("```"), body("after")])
    }

    // MARK: Model-written Markdown
    //
    // Language models write GitHub Flavored Markdown shaped by chat interfaces:
    // blank lines between paragraphs, single newlines meant as line breaks,
    // nested lists indented with spaces, and fences that often break a numbered
    // list, after which the list resumes at the next number.

    func testNumberedListResumesAfterUnindentedFence() {
        // The fence ends the list; “2.” starts a new list at 2, which must show as 2.
        assertBlocks("1. Install:\n```\nmake\n```\n2. Run:\n```\n./app\n```\n3. Done.",
                     [numbered(1, "Install:"), code("make"), numbered(2, "Run:"), code("./app"), numbered(3, "Done.")])
    }

    func testNumberedListResumesAfterUnindentedFenceWithBlankLines() {
        assertBlocks("1. a\n\n```\nx\n```\n\n2. b",
                     [numbered(1, "a"), blank, code("x"), blank, numbered(2, "b")])
    }

    func testBoldLineFollowedDirectlyByList() {
        assertBlocks("**Options:**\n- a\n- b", [body("Options:"), bullet("a"), bullet("b")])
    }

    func testBulletsNestedThreeSpacesUnderNumbers() {
        assertBlocks("1. **Setup**\n   - Install\n   - Configure\n2. **Use**",
                     [numbered(1, "Setup"), bullet("Install", level: 1), bullet("Configure", level: 1), numbered(2, "Use")])
    }

    func testKeyValueLinesKeepTheirLineBreaks() {
        assertBlocks("Name: iTerm2\nVersion: 3.7", [body("Name: iTerm2" + lineSeparator + "Version: 3.7")])
    }

    func testFenceLanguages() {
        for language in ["objective-c", "shell", "c++", "Swift", "jsonc"] {
            assertBlocks("```\(language)\nx\n```\nafter", [code("x"), body("after")])
        }
    }

    func testTaskListItems() {
        // GFM task list items show a checkbox in place of the bullet.
        assertBlocks("- [ ] todo\n- [x] done\n- [X] also", [bullet("todo", marker: "☐"), bullet("done", marker: "☑"), bullet("also", marker: "☑")])
    }

    func testTypicalReply() {
        let reply = """
            ## Installing

            To install, follow these steps:

            1. Clone the repository:
               ```bash
               git clone https://example.com/repo.git
               ```
            2. Build it:
               - On macOS, run `make`.
               - On Linux, run `make linux`.
            3. Run the tests.

            Let me know if you hit problems.
            """
        assertBlocks(reply, [heading(2, "Installing"),
                             blank,
                             body("To install, follow these steps:"),
                             blank,
                             numbered(1, "Clone the repository:"),
                             code("git clone https://example.com/repo.git", list: 0),
                             numbered(2, "Build it:"),
                             bullet("On macOS, run make.", level: 1),
                             bullet("On Linux, run make linux.", level: 1),
                             numbered(3, "Run the tests."),
                             blank,
                             body("Let me know if you hit problems.")])
    }

    // MARK: Tables

    func testLineDirectlyAfterTableIsARow() {
        // GFM ends a table only at a blank line or another block's start, so a
        // plain line right after the last row is a row of its own, with the
        // missing cell left empty (spec example 201). Today it's a paragraph.
        let attributed = render("| a | b |\n|---|---|\n| 1 | 2 |\nAfter the table.")
        XCTAssertEqual(attributed.string.components(separatedBy: "\n").filter { !$0.isEmpty },
                       ["a", "b", "1", "2", "After the table."])
        let range = (attributed.string as NSString).range(of: "After the table.")
        XCTAssertNotEqual(range.location, NSNotFound)
        XCTAssertEqual(attributed.attribute(.swiftyMarkdownLineStyle, at: range.location, effectiveRange: nil) as? String, "table")
    }

    // MARK: Front matter and rules at the top

    func testRuleOnFirstLineIsNotFrontMatter() {
        assertBlocks("***\nHello", [rule, body("Hello")])
    }

    func testUnclosedFrontMatterOpenerIsARule() {
        // Today the whole document disappears.
        assertBlocks("---\nHello", [rule, body("Hello")])
    }

    func testSpacedRules() {
        assertBlocks("- - -\n\n* * *", [rule, blank, rule])
    }
}
