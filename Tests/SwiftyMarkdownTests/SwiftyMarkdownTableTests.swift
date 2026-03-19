//
//  SwiftyMarkdownTableTests.swift
//  SwiftyMarkdownTests
//
//  Tests for markdown table parsing and rendering
//

import XCTest
@testable import SwiftyMarkdown

class SwiftyMarkdownTableTests: XCTestCase {

    // MARK: - Basic Table Parsing Tests

    func testSimpleTableParsing() {
        let input = """
        | Header 1 | Header 2 |
        |----------|----------|
        | Cell 1   | Cell 2   |
        """

        let md = SwiftyMarkdown(string: input)
        let attributedString = md.attributedString()

        // The table should be rendered (not empty)
        XCTAssertFalse(attributedString.string.isEmpty, "Table should render content")
        XCTAssertTrue(attributedString.string.contains("Header 1"), "Should contain header text")
        XCTAssertTrue(attributedString.string.contains("Cell 1"), "Should contain cell text")
    }

    func testTableWithMultipleRows() {
        let input = """
        | Name  | Age |
        |-------|-----|
        | Alice | 30  |
        | Bob   | 25  |
        | Carol | 35  |
        """

        let md = SwiftyMarkdown(string: input)
        let attributedString = md.attributedString()

        XCTAssertTrue(attributedString.string.contains("Alice"), "Should contain first row")
        XCTAssertTrue(attributedString.string.contains("Bob"), "Should contain second row")
        XCTAssertTrue(attributedString.string.contains("Carol"), "Should contain third row")
    }

    // MARK: - Alignment Tests

    func testLeftAlignment() {
        let input = """
        | Left |
        |:-----|
        | Text |
        """

        let processor = SwiftyLineProcessor(
            blockRules: SwiftyMarkdown.blockRules,
            rules: SwiftyMarkdown.lineRules,
            defaultRule: MarkdownLineStyle.body,
            tableLineStyle: MarkdownLineStyle.table
        )

        let lines = processor.process(input)
        guard let tableLine = lines.first(where: { $0.tableData != nil }),
              let table = tableLine.tableData else {
            XCTFail("Should find table data")
            return
        }

        XCTAssertEqual(table.alignments.first, .left, "Should be left aligned")
    }

    func testCenterAlignment() {
        let input = """
        | Center |
        |:------:|
        | Text   |
        """

        let processor = SwiftyLineProcessor(
            blockRules: SwiftyMarkdown.blockRules,
            rules: SwiftyMarkdown.lineRules,
            defaultRule: MarkdownLineStyle.body,
            tableLineStyle: MarkdownLineStyle.table
        )

        let lines = processor.process(input)
        guard let tableLine = lines.first(where: { $0.tableData != nil }),
              let table = tableLine.tableData else {
            XCTFail("Should find table data")
            return
        }

        XCTAssertEqual(table.alignments.first, .center, "Should be center aligned")
    }

    func testRightAlignment() {
        let input = """
        | Right |
        |------:|
        | Text  |
        """

        let processor = SwiftyLineProcessor(
            blockRules: SwiftyMarkdown.blockRules,
            rules: SwiftyMarkdown.lineRules,
            defaultRule: MarkdownLineStyle.body,
            tableLineStyle: MarkdownLineStyle.table
        )

        let lines = processor.process(input)
        guard let tableLine = lines.first(where: { $0.tableData != nil }),
              let table = tableLine.tableData else {
            XCTFail("Should find table data")
            return
        }

        XCTAssertEqual(table.alignments.first, .right, "Should be right aligned")
    }

    func testMixedAlignments() {
        let input = """
        | Left | Center | Right |
        |:-----|:------:|------:|
        | A    | B      | C     |
        """

        let processor = SwiftyLineProcessor(
            blockRules: SwiftyMarkdown.blockRules,
            rules: SwiftyMarkdown.lineRules,
            defaultRule: MarkdownLineStyle.body,
            tableLineStyle: MarkdownLineStyle.table
        )

        let lines = processor.process(input)
        guard let tableLine = lines.first(where: { $0.tableData != nil }),
              let table = tableLine.tableData else {
            XCTFail("Should find table data")
            return
        }

        XCTAssertEqual(table.alignments.count, 3)
        XCTAssertEqual(table.alignments[0], .left)
        XCTAssertEqual(table.alignments[1], .center)
        XCTAssertEqual(table.alignments[2], .right)
    }

    // MARK: - Edge Cases

    func testEmptyCells() {
        let input = """
        | A | B |
        |---|---|
        |   | X |
        | Y |   |
        """

        let md = SwiftyMarkdown(string: input)
        let attributedString = md.attributedString()

        XCTAssertTrue(attributedString.string.contains("X"), "Should contain non-empty cell")
        XCTAssertTrue(attributedString.string.contains("Y"), "Should contain non-empty cell")
    }

    func testTableFollowedByText() {
        let input = """
        | Header |
        |--------|
        | Cell   |

        Some text after the table.
        """

        let md = SwiftyMarkdown(string: input)
        let attributedString = md.attributedString()

        XCTAssertTrue(attributedString.string.contains("Header"), "Should contain table header")
        XCTAssertTrue(attributedString.string.contains("Cell"), "Should contain table cell")
        XCTAssertTrue(attributedString.string.contains("Some text after"), "Should contain text after table")
    }

    func testTextFollowedByTable() {
        let input = """
        Some text before the table.

        | Header |
        |--------|
        | Cell   |
        """

        let md = SwiftyMarkdown(string: input)
        let attributedString = md.attributedString()

        XCTAssertTrue(attributedString.string.contains("Some text before"), "Should contain text before table")
        XCTAssertTrue(attributedString.string.contains("Header"), "Should contain table header")
        XCTAssertTrue(attributedString.string.contains("Cell"), "Should contain table cell")
    }

    func testMultipleTables() {
        let input = """
        | Table 1 |
        |---------|
        | A       |

        | Table 2 |
        |---------|
        | B       |
        """

        let md = SwiftyMarkdown(string: input)
        let attributedString = md.attributedString()

        XCTAssertTrue(attributedString.string.contains("Table 1"), "Should contain first table")
        XCTAssertTrue(attributedString.string.contains("Table 2"), "Should contain second table")
        XCTAssertTrue(attributedString.string.contains("A"), "Should contain first table data")
        XCTAssertTrue(attributedString.string.contains("B"), "Should contain second table data")
    }

    // MARK: - Inline Formatting Tests

    func testBoldInTableCell() {
        let input = """
        | Header |
        |--------|
        | **bold** |
        """

        let md = SwiftyMarkdown(string: input)
        let attributedString = md.attributedString()

        XCTAssertTrue(attributedString.string.contains("bold"), "Should contain bold text without markers")
        XCTAssertFalse(attributedString.string.contains("**"), "Should not contain bold markers")
    }

    func testItalicInTableCell() {
        let input = """
        | Header |
        |--------|
        | *italic* |
        """

        let md = SwiftyMarkdown(string: input)
        let attributedString = md.attributedString()

        XCTAssertTrue(attributedString.string.contains("italic"), "Should contain italic text without markers")
    }

    func testCodeInTableCell() {
        let input = """
        | Header |
        |--------|
        | `code` |
        """

        let md = SwiftyMarkdown(string: input)
        let attributedString = md.attributedString()

        XCTAssertTrue(attributedString.string.contains("code"), "Should contain code text without markers")
        XCTAssertFalse(attributedString.string.contains("`"), "Should not contain backtick markers")
    }

    func testLinkInTableCell() {
        let input = """
        | Header |
        |--------|
        | [link](http://example.com) |
        """

        let md = SwiftyMarkdown(string: input)
        let attributedString = md.attributedString()

        XCTAssertTrue(attributedString.string.contains("link"), "Should contain link text")
    }

    // MARK: - Invalid Table Tests

    func testLineWithPipeButNoTable() {
        // A line with pipes but not starting/ending with pipes should not be a table
        let input = "This | is | not | a table"

        let processor = SwiftyLineProcessor(
            blockRules: SwiftyMarkdown.blockRules,
            rules: SwiftyMarkdown.lineRules,
            defaultRule: MarkdownLineStyle.body,
            tableLineStyle: MarkdownLineStyle.table
        )

        let lines = processor.process(input)
        let hasTable = lines.contains { $0.tableData != nil }

        XCTAssertFalse(hasTable, "Should not detect a table without proper formatting")
    }

    func testHeaderWithoutSeparator() {
        // A potential header row without a separator should not create a table
        let input = """
        | Header |
        Normal text
        """

        let processor = SwiftyLineProcessor(
            blockRules: SwiftyMarkdown.blockRules,
            rules: SwiftyMarkdown.lineRules,
            defaultRule: MarkdownLineStyle.body,
            tableLineStyle: MarkdownLineStyle.table
        )

        let lines = processor.process(input)
        let hasTable = lines.contains { $0.tableData != nil }

        XCTAssertFalse(hasTable, "Should not create a table without separator")
    }

    // MARK: - Table Structure Tests

    func testColumnCount() {
        let input = """
        | A | B | C | D |
        |---|---|---|---|
        | 1 | 2 | 3 | 4 |
        """

        let processor = SwiftyLineProcessor(
            blockRules: SwiftyMarkdown.blockRules,
            rules: SwiftyMarkdown.lineRules,
            defaultRule: MarkdownLineStyle.body,
            tableLineStyle: MarkdownLineStyle.table
        )

        let lines = processor.process(input)
        guard let tableLine = lines.first(where: { $0.tableData != nil }),
              let table = tableLine.tableData else {
            XCTFail("Should find table data")
            return
        }

        XCTAssertEqual(table.columnCount, 4, "Should have 4 columns")
        XCTAssertEqual(table.headers.count, 4, "Should have 4 headers")
        XCTAssertEqual(table.rows.count, 1, "Should have 1 body row")
        XCTAssertEqual(table.rows[0].count, 4, "Row should have 4 cells")
    }

    func testHeadersOnly() {
        let input = """
        | Header 1 | Header 2 |
        |----------|----------|
        """

        let processor = SwiftyLineProcessor(
            blockRules: SwiftyMarkdown.blockRules,
            rules: SwiftyMarkdown.lineRules,
            defaultRule: MarkdownLineStyle.body,
            tableLineStyle: MarkdownLineStyle.table
        )

        let lines = processor.process(input)
        guard let tableLine = lines.first(where: { $0.tableData != nil }),
              let table = tableLine.tableData else {
            XCTFail("Should find table data")
            return
        }

        XCTAssertEqual(table.headers.count, 2, "Should have 2 headers")
        XCTAssertEqual(table.rows.count, 0, "Should have no body rows")
    }
}
