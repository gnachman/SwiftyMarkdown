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
    func styleIfFoundStyleAffectsPreAndBackLine() -> LineStyling?
}

public struct SwiftyLine : CustomStringConvertible {
    public var line : String
    public let lineStyle : LineStyling
    public var tableData: [[String]] = []
    public var literal: Bool

    public var description: String {
        return self.line + " (\(String(describing: lineStyle))"
    }

    init(line: String, lineStyle: LineStyling, literal: Bool = false) {
        self.line = line
        self.lineStyle = lineStyle
        self.literal = literal
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
    case preAndBack
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

public class SwiftyLineProcessor {
    
	public var processEmptyStrings : LineStyling?
	public internal(set) var frontMatterAttributes : [String : String] = [:]
	
	var closeToken : String? = nil
    let defaultType : LineStyling

    let blockRules : [BlockRule]
    let lineRules : [LineRule]
	let frontMatterRules : [FrontMatterRule]
	
	let perfomanceLog = PerformanceLog(with: "SwiftyLineProcessorPerformanceLogging", identifier: "Line Processor", log: OSLog.swiftyLineProcessorPerformance)
	    
    public init(blockRules : [BlockRule],
                rules : [LineRule],
                defaultRule: LineStyling,
                frontMatterRules : [FrontMatterRule] = []) {
        self.blockRules = blockRules
        self.lineRules = rules
        self.defaultType = defaultRule
		self.frontMatterRules = frontMatterRules
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
		while !closeFound {
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
    
    public func process( _ string : String ) -> [SwiftyLine] {
        var swiftyLines : [SwiftyLine] = []
		
		
        self.perfomanceLog.start()
        var lines = string.components(separatedBy: CharacterSet.newlines)

        lines = self.processFrontMatter(lines)
        
        self.perfomanceLog.tag(with: "(Front matter completed)")
		
        var currentBlockRule: BlockRule?
        var tableData:[[String]] = []
        for  heading in lines {
            
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

            guard var input = processLineLevelAttributes(String(heading)) else {
                continue
            }

            if let existentPrevious = input.lineStyle.styleIfFoundStyleAffectsPreviousLine(),
               swiftyLines.count > 0 {
                if let idx = swiftyLines.firstIndex(of: swiftyLines.last!) {
                    let updatedPrevious = swiftyLines.last!
                    swiftyLines[idx] = SwiftyLine(line: updatedPrevious.line, lineStyle: existentPrevious)
                }
                continue
            } else if input.lineStyle.styleIfFoundStyleAffectsPreAndBackLine() != nil,
                      swiftyLines.count > 0 {
                let updatedPrevious: SwiftyLine = swiftyLines.last!
                let updatedPreviousLineStyle:MarkdownLineStyle = updatedPrevious.lineStyle as! MarkdownLineStyle
                if let lineStyle: MarkdownLineStyle = updatedPrevious.lineStyle as? MarkdownLineStyle, lineStyle == .table {
                    var contentArr:[String] = String(heading).trimmingCharacters(in: .whitespaces).components(separatedBy: "|") as [String]
                    contentArr.removeAll(where: { $0.count == 0})
                    var currentArr:[String] = contentArr.map({ content in
                        return content.trimmingCharacters(in: .whitespaces)
                    })
                    if currentArr.filter({ content in
                        let charSet = CharacterSet(charactersIn: "-" )
                        return content.unicodeScalars.allSatisfy({ charSet.contains($0) }) && content.count >= 3
                    }).count == currentArr.count {  // Check if each element contains only ---
                        var preArr:[String] = updatedPrevious.line.trimmingCharacters(in: .whitespaces).components(separatedBy: "|") as [String]
                        preArr.removeAll(where: {$0.count == 0})
                        if currentArr.count >= preArr.count {
                            tableData.append(preArr)
                            swiftyLines.removeLast()
                            input.line = ""
                        }
                    } else if updatedPreviousLineStyle != .table {  // This case is the first row of the table
                        
                    } else if updatedPrevious.line == "", currentArr.count > 0 {  // This case is a content item of the table
                        let headerData: [String] = tableData.first!
                        guard headerData.count >= currentArr.count else {continue}
                        while headerData.count - currentArr.count > 0 {
                            currentArr.append("")
                        }
                        tableData.append(currentArr)
                        if heading == lines.last {
                            var tableLine: SwiftyLine = swiftyLines.last!
                            tableLine.tableData = tableData
                            tableData = []
                            swiftyLines[swiftyLines.count-1] = tableLine
                            continue
                        } else {
                            continue
                        }
                    }
                }
            } else {
                if tableData.count > 0 {
                    var tableLine: SwiftyLine = swiftyLines.last!
                    tableLine.tableData = tableData
                    tableData = []
                    swiftyLines[swiftyLines.count-1] = tableLine
                }
            }
            swiftyLines.append(input)
			
			self.perfomanceLog.tag(with: "(line completed: \(heading)")
        }
        return swiftyLines
    }
    
}


