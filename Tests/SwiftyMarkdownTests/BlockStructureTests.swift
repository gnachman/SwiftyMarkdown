//
//  BlockStructureTests.swift
//  SwiftyMarkdownTests
//
//  Block structure as CommonMark and GitHub Flavored Markdown define it, which
//  the line-at-a-time parser that MarkdownBlockParser replaced got wrong:
//  paragraphs that span lines, blocks inside list items and quotes, nesting by
//  indentation, list numbering, which blocks may interrupt a paragraph, and
//  Markdown as language models write it.
//

import XCTest
@testable import SwiftyMarkdown

final class BlockStructureTests: XCTestCase {

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
        // The old parser turned the line above into a heading.
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

    func testIndentedCodeInQuoteOpenedAfterParagraph() {
        assertBlocks("para\n>     code", [body("para"), code("code", quote: 1)])
    }

    func testIndentedCodeInListItemOpenedAfterParagraph() {
        assertBlocks("text\n-     code", [body("text"), bullet(""), code("code", list: 0)])
    }

    func testIndentedLineContinuesParagraph() {
        // Indented code can't interrupt a paragraph.
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

    func testItemStartingWithAHeadingHasAnEmptyMarkerLine() {
        // Only a paragraph shares the marker's line. A heading, code, or quote
        // that starts an item follows a marker line of its own.
        assertBlocks("- # Title", [bullet(""), RenderedBlock("Title", style: "h1", listLevel: 0)])
    }

    func testUnindentedParagraphEndsList() {
        assertBlocks("- a\n\nb", [bullet("a"), blank, body("b")])
    }

    func testFenceInListItemClosedAtTheMargin() {
        // Models often indent the opening fence under the item but not the closing one.
        assertBlocks("- a\n  ```\n  x\n```\n- b", [bullet("a"), code("x", list: 0), bullet("b")])
    }

    func testCodeAtTheMarginInsideAListItemsFence() {
        assertBlocks("1. Install:\n   ```sh\nmake install\n   ```\n2. Run it\n\nThe end.",
                     [numbered(1, "Install:"), code("make install", list: 0), numbered(2, "Run it"), blank, body("The end.")])
    }

    func testCodeAtTheMarginThatLooksLikeMarkdown() {
        // Comments, diff lines, and lists are ordinary in code.
        assertBlocks("1. Install:\n   ```bash\nnpm ci\n# then build\n- old\n> quoted\nnpm run build\n```\n2. Run it.\n\nThe end.",
                     [numbered(1, "Install:"), code("npm ci", list: 0), code("# then build", list: 0), code("- old", list: 0),
                      code("> quoted", list: 0), code("npm run build", list: 0), numbered(2, "Run it."), blank, body("The end.")])
    }

    func testFenceOpenedOnTheMarkerLineWithCodeAtTheMargin() {
        assertBlocks("- ```bash\nnpm ci\n```\n- next", [bullet(""), code("npm ci", list: 0), bullet("next")])
    }

    func testFenceInQuotedListItemClosedAtTheQuotesMargin() {
        assertBlocks("> - ```sh\n>   x\n> code\n> ```\n> after",
                     [bullet("", quote: 1), code("x", list: 0, quote: 1), code("code", list: 0, quote: 1), quote("after")])
        XCTAssertEqual(SwiftyMarkdown.codeLines(in: "> - ```sh\n>   x\n> code\n> ```\n> after"), IndexSet([0, 1, 2, 3]))
    }

    func testOtherFenceCharacterInsideAFenceIsContent() {
        assertBlocks("- item\n  ```\n  ~~~sh\ncode at margin\n  ```\n- next",
                     [bullet("item"), code("~~~sh", list: 0), code("code at margin", list: 0), bullet("next")])
    }

    func testUnclosedFenceInListItemFollowedByProseAfterABlankLine() {
        // Prose at the margin after a blank line ends the item and its fence, as in
        // CommonMark, even though a later bare fence could pair with the item's.
        assertBlocks("- step\n  ```\n  code\n\nProse after the list.\n\n```\nother\n```\n\n# Heading\n\nMore prose",
                     [bullet("step"), code("code", list: 0), blank, body("Prose after the list."), blank,
                      code("other"), blank, heading(1, "Heading"), blank, body("More prose")])
    }

    func testCodeAtTheMarginWithBlankLinesInside() {
        assertBlocks("1. Install:\n   ```bash\nnpm ci\n\nnpm run build\n```\n2. Run it.",
                     [numbered(1, "Install:"), code("npm ci", list: 0), blank, code("npm run build", list: 0), numbered(2, "Run it.")])
    }

    func testUnclosedFenceInListItemBeforeALaterBareFence() {
        // A known limit: the next fence below is bare, so it's taken as the item's
        // closer even though it opens another block. Margin lines up to it are code.
        assertBlocks("1. Run:\n   ```sh\n   ls\nThen read the docs.\n```\nplain\n```",
                     [numbered(1, "Run:"), code("ls", list: 0), code("Then read the docs.", list: 0), body("plain"),
                      // The last fence opens an empty block, which ends the text with a newline.
                      blank, blank])
    }

    func testLaterFenceTooShortToCloseDoesNotKeepMarginLines() {
        assertBlocks("- a\n  ````\n  x\ny\n```\nz",
                     [bullet("a"), code("x", list: 0), body("y"), code("z")])
    }

    func testUnclosedFenceInListItemIsNotClosedByALaterBlocksFence() {
        assertBlocks("1. Step\n   ```\n   code\nprose here\n\n```sh\nreal code\n```",
                     [numbered(1, "Step"), code("code", list: 0), body("prose here"), blank, code("real code")])
    }

    func testUnclosedFenceInListItemDoesNotSwallowTheNextItem() {
        assertBlocks("1. First:\n   ```bash\n   cmd1\n2. Second:\n   ```bash\n   cmd2\n   ```\n3. Third",
                     [numbered(1, "First:"), code("cmd1", list: 0), numbered(2, "Second:"), code("cmd2", list: 0), numbered(3, "Third")])
        // The empty paragraph is the next item's empty code block.
        assertBlocks("- a\n  ```\n  x\n- b\n  ```\nafter",
                     [bullet("a"), code("x", list: 0), bullet("b"), blank, body("after")])
    }

    func testCodeAtTheMarginOfAQuotedListItemsFence() {
        assertBlocks("> - a\n>   ```\n> code\n>   ```\n\n```\nz\n```",
                     [bullet("a", quote: 1), code("code", list: 0, quote: 1), blank, code("z")])
    }

    func testFenceInListItemClosesWithTheItem() {
        // Never closed, so an unindented line ends the item and the fence (CommonMark).
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

    func testNestingUnderAWideMarker() {
        // Four columns past a marker wider than three nests, though it's short of the
        // item's text column.
        assertBlocks("100. x\n    - b", [numbered(100, "x"), bullet("b", level: 1)])
        assertBlocks("10.   x\n    - b", [numbered(10, "x"), bullet("b", level: 1)])
    }

    func testOneSpaceIsNotNesting() {
        assertBlocks("- a\n - b", [bullet("a"), bullet("b")])
    }

    func testMoreThanThreeLevels() {
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
        // The old parser didn't take “```c++” as an opener, so its closing fence
        // opened a block that swallowed the rest of the document.
        assertBlocks("```c++\nint x;\n```\nafter", [code("int x;"), body("after")])
    }

    func testFenceWithCapitalizedInfoString() {
        assertBlocks("```Swift\nlet x = 1\n```\nafter", [code("let x = 1"), body("after")])
    }

    func testTildeFence() {
        assertBlocks("~~~\nx\n~~~\nafter", [code("x"), body("after")])
    }

    func testWhitespaceOnlyLineInFenceIsKeptVerbatim() {
        assertBlocks("```\na\n \nb\n```", [code("a"), code(" "), code("b")])
    }

    func testEmptyCodeLineIsMarkedAsCode() {
        // An empty line has no characters of its own, so the newline ending it carries its style.
        let attributed = render("```\na\n\nb\n```")
        XCTAssertEqual(attributed.string, "a\n\nb")
        XCTAssertEqual(attributed.attribute(.swiftyMarkdownLineStyle, at: 2, effectiveRange: nil) as? String, "codeblock")
        XCTAssertNil(render("a\n\nb").attribute(.swiftyMarkdownLineStyle, at: 2, effectiveRange: nil))
    }

    func testEmptyFencedCodeBlockIsStillCode() {
        let attributed = render("```\n```\nafter")
        XCTAssertEqual(attributed.string, "\nafter")
        XCTAssertEqual(attributed.attribute(.swiftyMarkdownLineStyle, at: 0, effectiveRange: nil) as? String, "codeblock")
    }

    func testEmptyFencedCodeBlockAtTheEndIsStillCode() {
        let attributed = render("text\n\n```\n```")
        XCTAssertEqual(attributed.string, "text\n\n\n")
        XCTAssertEqual(attributed.attribute(.swiftyMarkdownLineStyle, at: 6, effectiveRange: nil) as? String, "codeblock")
    }

    func testEmptyLastLineOfCodeIsKept() {
        let attributed = render("```\ncode\n\n```")
        XCTAssertEqual(attributed.string, "code\n\n")
        XCTAssertEqual(attributed.attribute(.swiftyMarkdownLineStyle, at: 5, effectiveRange: nil) as? String, "codeblock")
    }

    func testTableCellsCarryListLevelAndQuoteDepth() {
        let attributed = render("- a\n\n  > | h |\n  > |---|\n  > | c |")
        let range = (attributed.string as NSString).range(of: "c")
        XCTAssertEqual((attributed.attribute(.swiftyMarkdownListLevel, at: range.location, effectiveRange: nil) as? NSNumber)?.intValue, 0)
        XCTAssertEqual((attributed.attribute(.swiftyMarkdownQuoteDepth, at: range.location, effectiveRange: nil) as? NSNumber)?.intValue, 1)
    }

    func testFirstLineOfEachCodeBlockIsMarked() {
        let attributed = render("```sh\nls\n```\n```py\na\nb\n```\n\n    c")
        func marked(_ text: String) -> Bool {
            let location = (attributed.string as NSString).range(of: text).location
            return attributed.attribute(.swiftyMarkdownCodeBlockStart, at: location, effectiveRange: nil) as? Bool ?? false
        }
        XCTAssertTrue(marked("ls"))
        XCTAssertTrue(marked("a"))
        XCTAssertFalse(marked("b"))
        XCTAssertTrue(marked("c"))
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

    func testOrderedTaskListItemsKeepTheirNumbers() {
        assertBlocks("1. [x] done\n2. [ ] todo", [numbered(1, "☑ done"), numbered(2, "☐ todo")])
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
        // missing cell left empty (spec example 201).
        let attributed = render("| a | b |\n|---|---|\n| 1 | 2 |\nAfter the table.")
        XCTAssertEqual(attributed.string.components(separatedBy: "\n").filter { !$0.isEmpty },
                       ["a", "b", "1", "2", "After the table."])
        let range = (attributed.string as NSString).range(of: "After the table.")
        XCTAssertNotEqual(range.location, NSNotFound)
        XCTAssertEqual(attributed.attribute(.swiftyMarkdownLineStyle, at: range.location, effectiveRange: nil) as? String, "table")
    }

    // MARK: Link reference definitions

    func testReferenceDefinitionCannotInterruptParagraph() {
        assertBlocks("Sources:\n[1]: https://example.com/a\n[2]: https://example.com/b",
                     [body("Sources:" + lineSeparator + "[1]: https://example.com/a" + lineSeparator + "[2]: https://example.com/b")])
    }

    func testConsecutiveReferenceDefinitionsAreRemoved() {
        let attributed = render("[a][a] and [b][b]\n\n[a]: https://example.com/a\n[b]: https://example.com/b")
        XCTAssertEqual(link(at: "a", in: attributed), "https://example.com/a")
        XCTAssertEqual(link(at: "b", in: attributed), "https://example.com/b")
        XCTAssertFalse(attributed.string.contains("example.com"))
    }

    func testBlankLinesAroundDefinitionsCollapse() {
        XCTAssertEqual(render("See [docs][1].\n\n[1]: https://x.y").string, "See docs.")
        XCTAssertEqual(render("a\n\n[x]: u\n\nb").string, "a\n\nb")
        XCTAssertEqual(render("a\n\n[x]: u\n[y]: v\n\n\nb").string, "a\n\n\nb")
        XCTAssertEqual(render("[x]: u\n\nb").string, "b")
    }

    func testFirstDefinitionOfALabelWins() {
        let attributed = render("[x][a]\n\n[a]: https://first\n[a]: https://second")
        XCTAssertEqual(link(at: "x", in: attributed), "https://first")
    }

    func testLabelsMatchRegardlessOfCaseAndSpacing() {
        let attributed = render("[x][Foo  Bar]\n\n[foo bar]: https://first\n[FOO BAR]: https://second")
        XCTAssertEqual(link(at: "x", in: attributed), "https://first")
    }

    func testRemovedDefinitionsLeaveOnlyBlankParagraphs() {
        // The blank lines after the definition are the longer group, so two are kept.
        let paragraphs = MarkdownBlockParser(softBreakStyle: .lineBreak, bullet: "・").parse("# H\n[x]: u\n\n\nb").paragraphs
        let kinds = paragraphs.map { paragraph -> String in
            switch paragraph.kind {
            case .blank: return "blank"
            case .definition: return "definition"
            case .heading: return "heading"
            default: return "other"
            }
        }
        XCTAssertEqual(kinds, ["heading", "blank", "blank", "other"])
    }

    func testReferenceDestinationOmitsAngleBracketsAndTitle() {
        let attributed = render("[foo][x]\n\n[x]: <http://x.y> \"Title\"")
        XCTAssertEqual(link(at: "foo", in: attributed), "http://x.y")
    }

    func testLineWithTextAfterDestinationIsNotADefinition() {
        assertBlocks("[Note]: remember to restart", [body("[Note]: remember to restart")])
    }

    func testReferenceDefinitionWithTitles() {
        for title in ["\"T\"", "'T'", "(T)"] {
            let attributed = render("[foo][x]\n\n[x]: http://x.y \(title)")
            XCTAssertEqual(link(at: "foo", in: attributed), "http://x.y", title)
            XCTAssertFalse(attributed.string.contains("x.y"), title)
        }
    }

    // MARK: Footnote definitions

    func testConsecutiveFootnoteDefinitionsAreSeparateParagraphs() {
        // As in GFM, where a footnote definition is a block of its own.
        assertBlocks("Text.\n[^1]: First note.\n[^2]: Second note.",
                     [body("Text."), body("[^1]: First note."), body("[^2]: Second note.")])
    }

    // MARK: Indentation inside quotes

    private func paragraphStyle(of substring: String, in attributed: NSAttributedString) -> NSParagraphStyle? {
        let range = (attributed.string as NSString).range(of: substring)
        return attributed.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
    }

    func testEverythingInAQuoteIsIndented() {
        let attributed = render("> para\n>\n> - item\n>\n>   more\n>\n> # head")
        let quoteIndent = paragraphStyle(of: "para", in: attributed)?.headIndent ?? 0
        XCTAssertGreaterThan(quoteIndent, 0)
        for text in ["item", "more", "head"] {
            let style = paragraphStyle(of: text, in: attributed)
            XCTAssertGreaterThanOrEqual(style?.firstLineHeadIndent ?? 0, quoteIndent, text)
            XCTAssertGreaterThanOrEqual(style?.headIndent ?? 0, quoteIndent, text)
        }
        let item = paragraphStyle(of: "item", in: attributed)
        let more = paragraphStyle(of: "more", in: attributed)
        XCTAssertEqual(more?.firstLineHeadIndent, item?.headIndent)
    }

    // MARK: Finding code in the source

    func testCodeLines() {
        // Line 2 is indented code; line 4 continues the item's paragraph; line 6 is
        // indented code in the item; lines 7 through 9 are a fence and its content.
        let markdown = "a\n\n    code\n- x\n    more\n\n        in item\n```\n    fenced\n```\nafter"
        XCTAssertEqual(SwiftyMarkdown.codeLines(in: markdown), IndexSet([2, 6, 7, 8, 9]))
    }

    func testCodeLinesInNestedListItem() {
        let markdown = "1. Step\n   - Run:\n     ```\n     make\n     ```"
        XCTAssertEqual(SwiftyMarkdown.codeLines(in: markdown), IndexSet([2, 3, 4]))
    }

    func testCodeLinesCountFrontMatter() {
        XCTAssertEqual(SwiftyMarkdown.codeLines(in: "---\na: b\n---\n\n    code"), IndexSet([4]))
    }

    func testCodeLinesWithCarriageReturns() {
        XCTAssertEqual(SwiftyMarkdown.codeLines(in: "a\r\n\r\n    code"), IndexSet([2]))
    }

    // MARK: Hostile input

    func testDeeplyNestedQuotesDoNotOverflowTheStack() {
        let attributed = render(String(repeating: ">", count: 100_000) + " x")
        XCTAssertTrue(attributed.string.hasSuffix("x"))
    }

    func testNestingStopsAtTheLimit() {
        let markdown = String(repeating: "> ", count: MarkdownBlockParser.maximumNesting + 1) + "x"
        let quotes = blocks(markdown).map(\.quoteDepth).max()
        XCTAssertEqual(quotes, MarkdownBlockParser.maximumNesting)
        XCTAssertTrue(render(markdown).string.hasSuffix("> x"))
    }

    func testDeeplyNestedListsDoNotOverflowTheStack() {
        let markdown = (0..<2_000).map { String(repeating: " ", count: $0 * 2) + "- x" }.joined(separator: "\n")
        XCTAssertFalse(render(markdown).string.isEmpty)
    }

    func testIndentedCodeAfterATableInAClosingQuote() {
        XCTAssertEqual(SwiftyMarkdown.codeLines(in: "> | a | b |\n> |---|---|\n    code"), IndexSet([2]))
    }

    func testOneBlankLineAfterATable() {
        XCTAssertEqual(render("| a | b |\n|---|---|\n| x | z |\n\nafter").string, "a\nb\nx\nz\n\nafter")
    }

    // MARK: Front matter and rules at the top

    func testRuleOnFirstLineIsNotFrontMatter() {
        assertBlocks("***\nHello", [rule, body("Hello")])
    }

    func testUnclosedFrontMatterOpenerIsARule() {
        // The old parser hid the whole document.
        assertBlocks("---\nHello", [rule, body("Hello")])
    }

    func testFrontMatterClosedWithDots() {
        assertBlocks("---\ntitle: x\n...\nHello", [body("Hello")])
    }

    func testFootnoteDefinitionIsNotALinkReference() {
        assertBlocks("[^1]: A note.", [body("[^1]: A note.")])
    }

    func testFrontMatterCloserWithTrailingWhitespace() {
        assertBlocks("---\ntitle: x\n--- \nbody", [body("body")])
    }

    func testLeadingByteOrderMarkIsIgnored() {
        assertBlocks("\u{FEFF}```\nx\n```", [code("x")])
        XCTAssertEqual(SwiftyMarkdown.codeLines(in: "\u{FEFF}```\nx\n```"), IndexSet([0, 1, 2]))
    }

    func testSpacedRules() {
        assertBlocks("- - -\n\n* * *", [rule, blank, rule])
    }
}
