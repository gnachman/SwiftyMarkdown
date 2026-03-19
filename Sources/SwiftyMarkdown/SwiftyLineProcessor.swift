//
//  SwiftyLineProcessor.swift
//  SwiftyMarkdown
//
//  Created by Simon Fairbairn on 16/12/2019.
//  Copyright © 2019 Voyage Travel Apps. All rights reserved.
//

import Foundation
import os.log

extension OSLog {
	private static var subsystem = "SwiftyLineProcessor"
	static let swiftyLineProcessorPerformance = OSLog(subsystem: subsystem, category: "Swifty Line Processor Performance")
}

public protocol LineStyling {
    var shouldTokeniseLine : Bool { get }
    func styleIfFoundStyleAffectsPreviousLine() -> LineStyling?
}

public struct SwiftyLine : CustomStringConvertible {
    public let line : String
    public let lineStyle : LineStyling
    public let literal: Bool
    public let tableData: ParsedTable?

    public var description: String {
        return self.line + " (\(String(describing: lineStyle))"
    }

    init(line: String, lineStyle: LineStyling, literal: Bool = false, tableData: ParsedTable? = nil) {
        self.line = line
        self.lineStyle = lineStyle
        self.literal = literal
        self.tableData = tableData
    }
}

extension SwiftyLine : Equatable {
    public static func == ( _ lhs : SwiftyLine, _ rhs : SwiftyLine ) -> Bool {
        return lhs.line == rhs.line
    }
}

public enum Remove {
    case leading
    case trailing
    case both
    case entireLine
    case none
}

public enum ChangeApplication {
    case current
    case previous
	case untilClose
}

public struct FrontMatterRule {
	let openTag : String
	let closeTag : String
	let keyValueSeparator : Character
}

public struct LineRule {
    let token : String
    let removeFrom : Remove
    let type : LineStyling
    let shouldTrim : Bool
    let changeAppliesTo : ChangeApplication
    
    public init(token : String, type : LineStyling, removeFrom : Remove = .leading, shouldTrim : Bool = true, changeAppliesTo : ChangeApplication = .current ) {
        self.token = token
        self.type = type
        self.removeFrom = removeFrom
        self.shouldTrim = shouldTrim
        self.changeAppliesTo = changeAppliesTo
    }
}

public struct BlockRule: Equatable {
    public static func == (lhs: BlockRule, rhs: BlockRule) -> Bool {
        return lhs.startRegex === rhs.startRegex
    }

    let startRegex: NSRegularExpression
    let endToken: String
    let type: LineStyling
}

// MARK: - Table Parsing

enum TableState {
    case idle
    case potentialTable(headerLine: String)
    case inTable(header: String, separator: String, bodyRows: [String])
}

public class SwiftyLineProcessor {

	public var processEmptyStrings : LineStyling?
	public internal(set) var frontMatterAttributes : [String : String] = [:]

	var closeToken : String? = nil
    let defaultType : LineStyling

    let blockRules : [BlockRule]
    let lineRules : [LineRule]
	let frontMatterRules : [FrontMatterRule]

    var tableState: TableState = .idle
    let tableLineStyle: LineStyling

	let perfomanceLog = PerformanceLog(with: "SwiftyLineProcessorPerformanceLogging", identifier: "Line Processor", log: OSLog.swiftyLineProcessorPerformance)
	    
    public init(blockRules : [BlockRule],
                rules : [LineRule],
                defaultRule: LineStyling,
                frontMatterRules : [FrontMatterRule] = [],
                tableLineStyle: LineStyling? = nil) {
        self.blockRules = blockRules
        self.lineRules = rules
        self.defaultType = defaultRule
		self.frontMatterRules = frontMatterRules
        self.tableLineStyle = tableLineStyle ?? defaultRule
    }
    
    func findLeadingLineElement( _ element : LineRule, in string : String ) -> String {
        var output = string
        if let range = output.index(output.startIndex, offsetBy: element.token.count, limitedBy: output.endIndex), output[output.startIndex..<range] == element.token {
            output.removeSubrange(output.startIndex..<range)
            return output
        }
        return output
    }
    
    func findTrailingLineElement( _ element : LineRule, in string : String ) -> String {
        var output = string
        let token = element.token.trimmingCharacters(in: .whitespaces)
        if let range = output.index(output.endIndex, offsetBy: -(token.count), limitedBy: output.startIndex), output[range..<output.endIndex] == token {
            output.removeSubrange(range..<output.endIndex)
            return output
            
        }
        return output
    }

    func processBlockTokens(_ currentRule: BlockRule?, line: String) -> BlockRule? {
        if let rule = currentRule {
            if rule.endToken == line {
                return nil
            }
            return rule
        }

        return blockRules.first { rule in
            rule.startRegex.firstMatch(in: line,
                                       range: NSRange(0..<(line as NSString).length)) != nil
        }
    }

    func processLineLevelAttributes( _ text : String) -> SwiftyLine? {
        if text.isEmpty, let style = processEmptyStrings {
            return SwiftyLine(line: "", lineStyle: style)
        }
        let previousLines = lineRules.filter({ $0.changeAppliesTo == .previous })

        for element in lineRules {
            guard element.token.count > 0 else {
                continue
            }
            var output : String = (element.shouldTrim) ? text.trimmingCharacters(in: .whitespaces) : text
            let unprocessed = output
			
			if let hasToken = self.closeToken, unprocessed != hasToken {
				return nil
			}
            
			if !text.contains(element.token) {
				continue
			}
			
            switch element.removeFrom {
            case .leading:
                output = findLeadingLineElement(element, in: output)
            case .trailing:
                output = findTrailingLineElement(element, in: output)
            case .both:
                output = findLeadingLineElement(element, in: output)
                output = findTrailingLineElement(element, in: output)
			case .entireLine:
				let maybeOutput = output.replacingOccurrences(of: element.token, with: "")
				output = ( maybeOutput.isEmpty ) ? maybeOutput : output
            default:
                break
            }
            // Only if the output has changed in some way
            guard unprocessed != output else {
                continue
            }
			if element.changeAppliesTo == .untilClose {
				self.closeToken = (self.closeToken == nil) ? element.token : nil
				return nil
			}

			
			
            output = (element.shouldTrim) ? output.trimmingCharacters(in: .whitespaces) : output
            return SwiftyLine(line: output, lineStyle: element.type)
            
        }
        
		for element in previousLines {
			let output = (element.shouldTrim) ? text.trimmingCharacters(in: .whitespaces) : text
			let charSet = CharacterSet(charactersIn: element.token )
			if output.unicodeScalars.allSatisfy({ charSet.contains($0) }) {
				return SwiftyLine(line: "", lineStyle: element.type)
			}
		}
		
        return SwiftyLine(line: text.trimmingCharacters(in: .whitespaces), lineStyle: defaultType)
    }
	
	func processFrontMatter( _ strings : [String] ) -> [String] {
		guard let firstString = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines) else {
			return strings
		}
		var rulesToApply : FrontMatterRule? = nil
		for matter in self.frontMatterRules {
			if firstString == matter.openTag {
				rulesToApply = matter
				break
			}
		}
		guard let existentRules = rulesToApply else {
			return strings
		}
		var outputString = strings
		// Remove the first line, which is the front matter opening tag
		let _ = outputString.removeFirst()
		var closeFound = false
		while !closeFound && !outputString.isEmpty {
			let nextString = outputString.removeFirst()
			if nextString == existentRules.closeTag {
				closeFound = true
				continue
			}
			var keyValue = nextString.components(separatedBy: "\(existentRules.keyValueSeparator)")
			if keyValue.count < 2 {
				continue
			}
			let key = keyValue.removeFirst()
			let value = keyValue.joined()
			self.frontMatterAttributes[key] = value
		}
		while outputString.first?.isEmpty ?? false {
			outputString.removeFirst()
		}
		return outputString
	}

    // MARK: - Table Detection and Parsing

    /// Check if a line is a valid table row (contains | and starts/ends with |)
    func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return false }
        // Must start and end with | for a proper table row
        return trimmed.hasPrefix("|") && trimmed.hasSuffix("|")
    }

    /// Check if a line is a table separator row (e.g., |:---|:---:|---:|)
    func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|") && trimmed.hasSuffix("|") else { return false }

        // Remove leading and trailing |
        let inner = String(trimmed.dropFirst().dropLast())
        let cells = inner.components(separatedBy: "|")

        // Each cell should match the pattern :?-+:?
        for cell in cells {
            let cellTrimmed = cell.trimmingCharacters(in: .whitespaces)
            if cellTrimmed.isEmpty { continue }

            // Check for valid separator pattern: optional : at start, one or more -, optional : at end
            var remaining = cellTrimmed[...]
            if remaining.hasPrefix(":") {
                remaining = remaining.dropFirst()
            }
            guard !remaining.isEmpty else { return false }

            // Must have at least one dash
            var hasDash = false
            while remaining.hasPrefix("-") {
                hasDash = true
                remaining = remaining.dropFirst()
            }
            guard hasDash else { return false }

            if remaining.hasPrefix(":") {
                remaining = remaining.dropFirst()
            }
            guard remaining.isEmpty else { return false }
        }

        return true
    }

    /// Parse cells from a table row, handling escape sequences (\| and \\)
    func parseCells(from line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Remove leading and trailing |
        let inner = String(trimmed.dropFirst().dropLast())
        return splitOnUnescapedPipes(inner).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Split a string on unescaped | and unescape \| and \\ sequences
    private func splitOnUnescapedPipes(_ string: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var i = string.startIndex

        while i < string.endIndex {
            let char = string[i]
            if char == "\\" {
                let nextIndex = string.index(after: i)
                if nextIndex < string.endIndex {
                    let nextChar = string[nextIndex]
                    if nextChar == "\\" {
                        // Escaped backslash: \\ -> \
                        current.append("\\")
                        i = string.index(i, offsetBy: 2)
                        continue
                    } else if nextChar == "|" {
                        // Escaped pipe: \| -> |
                        current.append("|")
                        i = string.index(i, offsetBy: 2)
                        continue
                    }
                }
                // Lone backslash or backslash followed by something else - keep as-is
                current.append(char)
                i = string.index(after: i)
            } else if char == "|" {
                // Unescaped pipe - end of cell
                cells.append(current)
                current = ""
                i = string.index(after: i)
            } else {
                current.append(char)
                i = string.index(after: i)
            }
        }
        cells.append(current)
        return cells
    }

    /// Parse alignments from a separator row
    func parseAlignments(from separatorLine: String) -> [TableColumnAlignment] {
        let cells = parseCells(from: separatorLine)
        return cells.map { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            let startsWithColon = trimmed.hasPrefix(":")
            let endsWithColon = trimmed.hasSuffix(":")

            if startsWithColon && endsWithColon {
                return .center
            } else if endsWithColon {
                return .right
            } else {
                return .left
            }
        }
    }

    /// Build a ParsedTable from collected table lines
    func buildTable(header: String, separator: String, bodyRows: [String]) -> ParsedTable {
        let headers = parseCells(from: header)
        let columnCount = headers.count
        let alignments = parseAlignments(from: separator)

        // Normalize rows to match header column count
        let rows = bodyRows.map { row -> [String] in
            var cells = parseCells(from: row)
            if cells.count < columnCount {
                // Pad short rows with empty cells
                cells.append(contentsOf: Array(repeating: "", count: columnCount - cells.count))
            } else if cells.count > columnCount {
                // Truncate long rows
                cells = Array(cells.prefix(columnCount))
            }
            return cells
        }
        return ParsedTable(headers: headers, alignments: alignments, rows: rows)
    }

    public func process( _ string : String ) -> [SwiftyLine] {
        var swiftyLines : [SwiftyLine] = []


		self.perfomanceLog.start()

		var lines = string.components(separatedBy: CharacterSet.newlines)
		lines = self.processFrontMatter(lines)

		self.perfomanceLog.tag(with: "(Front matter completed)")

        var currentBlockRule: BlockRule?
        tableState = .idle

        /// Helper to emit a completed table
        func emitTable(header: String, separator: String, bodyRows: [String]) {
            let table = buildTable(header: header, separator: separator, bodyRows: bodyRows)
            swiftyLines.append(SwiftyLine(line: "", lineStyle: tableLineStyle, tableData: table))
        }

        for heading in lines {

            // Handle table state machine first
            switch tableState {
            case .idle:
                if isTableRow(heading) {
                    tableState = .potentialTable(headerLine: heading)
                    continue
                }
            case .potentialTable(let headerLine):
                if isTableSeparator(heading) {
                    tableState = .inTable(header: headerLine, separator: heading, bodyRows: [])
                    continue
                } else {
                    // Not a valid table, process the header line normally
                    tableState = .idle
                    if let input = processLineLevelAttributes(headerLine) {
                        swiftyLines.append(input)
                    }
                    // Check if current line could start a new table
                    if isTableRow(heading) {
                        tableState = .potentialTable(headerLine: heading)
                        continue
                    }
                    // Otherwise fall through to process current line normally
                }
            case .inTable(let header, let separator, var bodyRows):
                if isTableRow(heading) && !isTableSeparator(heading) {
                    bodyRows.append(heading)
                    tableState = .inTable(header: header, separator: separator, bodyRows: bodyRows)
                    continue
                } else {
                    // Table ended, emit it
                    emitTable(header: header, separator: separator, bodyRows: bodyRows)
                    tableState = .idle
                    // Check if current line starts a new table
                    if isTableRow(heading) {
                        tableState = .potentialTable(headerLine: heading)
                        continue
                    }
                    // Otherwise fall through to process current line normally
                }
            }

            if processEmptyStrings == nil && heading.isEmpty {
                continue
            }

            if let update = processBlockTokens(currentBlockRule, line: String(heading)) {
                if currentBlockRule == nil {
                    currentBlockRule = update
                    continue
                }
            } else {
                defer {
                    currentBlockRule = nil
                }
                if currentBlockRule != nil {
                    // Skip over end token
                    continue
                }
            }

            if let blockRule = currentBlockRule {
                swiftyLines.append(SwiftyLine(line: String(heading),
                                              lineStyle: blockRule.type,
                                              literal: true))
                continue
            }

            guard let input = processLineLevelAttributes(String(heading)) else {
				continue
			}

            if let existentPrevious = input.lineStyle.styleIfFoundStyleAffectsPreviousLine(),
               swiftyLines.count > 0 {
                if let idx = swiftyLines.firstIndex(of: swiftyLines.last!) {
                    let updatedPrevious = swiftyLines.last!
                    swiftyLines[idx] = SwiftyLine(line: updatedPrevious.line, lineStyle: existentPrevious)
                }
                continue
            }
            swiftyLines.append(input)

			self.perfomanceLog.tag(with: "(line completed: \(heading)")
        }

        // Handle any remaining table at end of input
        switch tableState {
        case .inTable(let header, let separator, let bodyRows):
            emitTable(header: header, separator: separator, bodyRows: bodyRows)
        case .potentialTable(let headerLine):
            // Just a header line without separator, process as normal
            if let input = processLineLevelAttributes(headerLine) {
                swiftyLines.append(input)
            }
        case .idle:
            break
        }
        tableState = .idle

        return swiftyLines
    }
    
}


