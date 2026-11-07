//
//  SwiftyMarkdown.swift
//  SwiftyMarkdown
//
//  Created by Simon Fairbairn on 05/03/2016.
//  Copyright © 2016 Voyage Travel Apps. All rights reserved.
//
import os.log
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension OSLog {
    private static var subsystem = "SwiftyMarkdown"
    static let swiftyMarkdownPerformance = OSLog(subsystem: subsystem, category: "Swifty Markdown Performance")
}

public enum CharacterStyle : String, CharacterStyling {
    case none
    case bold
    case italic
    case code
    case link
    case image
    case referencedLink
    case referencedImage
    case strikethrough
    
    public func isEqualTo(_ other: CharacterStyling) -> Bool {
        guard let other = other as? CharacterStyle else {
            return false
        }
        return other == self 
    }
}

enum MarkdownLineStyle : LineStyling {
    case yaml
    case h1
    case h2
    case h3
    case h4
    case h5
    case h6
    case previousH1
    case previousH2
    case body
    case blockquote
    case codeblock
    case unorderedList
    case unorderedListIndentFirstOrder
    case unorderedListIndentSecondOrder
    case orderedList
    case orderedListIndentFirstOrder
    case orderedListIndentSecondOrder
    case referencedLink
    case table
    case horizontalRule

    /// The style for the first paragraph of a list item. There are three levels
    /// of style; deeper items use the last.
    static func listItem(ordered: Bool, level: Int) -> MarkdownLineStyle {
        switch (ordered, level) {
        case (true, 0): return .orderedList
        case (true, 1): return .orderedListIndentFirstOrder
        case (true, _): return .orderedListIndentSecondOrder
        case (false, 0): return .unorderedList
        case (false, 1): return .unorderedListIndentFirstOrder
        case (false, _): return .unorderedListIndentSecondOrder
        }
    }

    var stringValue: String {
        switch self {
        case .yaml: return "yaml"
        case .h1: return "h1"
        case .h2: return "h2"
        case .h3: return "h3"
        case .h4: return "h4"
        case .h5: return "h5"
        case .h6: return "h6"
        case .previousH1: return "previousH1"
        case .previousH2: return "previousH2"
        case .body: return "body"
        case .blockquote: return "blockquote"
        case .codeblock: return "codeblock"
        case .unorderedList: return "unorderedList"
        case .unorderedListIndentFirstOrder: return "unorderedListIndentFirstOrder"
        case .unorderedListIndentSecondOrder: return "unorderedListIndentSecondOrder"
        case .orderedList: return "orderedList"
        case .orderedListIndentFirstOrder: return "orderedListIndentFirstOrder"
        case .orderedListIndentSecondOrder: return "orderedListIndentSecondOrder"
        case .referencedLink: return "referencedLink"
        case .table: return "table"
        case .horizontalRule: return "horizontalRule"
        }
    }
}

@objc public enum FontStyle : Int {
    case normal
    case bold
    case italic
    case boldItalic
}

// MARK: - Table Support

public enum TableColumnAlignment {
    case left
    case center
    case right
}

public struct ParsedTable {
    public let headers: [String]
    public let alignments: [TableColumnAlignment]
    public let rows: [[String]]
    public let columnCount: Int

    public init(headers: [String], alignments: [TableColumnAlignment], rows: [[String]]) {
        self.headers = headers
        self.alignments = alignments
        self.rows = rows
        self.columnCount = headers.count
    }
}

#if os(macOS)
@objc public protocol FontProperties {
    var fontName : String? { get set }
    var color : NSColor { get set }
    var fontSize : CGFloat { get set }
    var fontStyle : FontStyle { get set }
}
#else
@objc public protocol FontProperties {
    var fontName : String? { get set }
    var color : UIColor { get set }
    var fontSize : CGFloat { get set }
    var fontStyle : FontStyle { get set }
}
#endif


@objc public protocol LineProperties {
    var alignment : NSTextAlignment { get set }
    var lineSpacing: CGFloat { get set }
    var paragraphSpacing: CGFloat { get set }
}


/**
A class defining the styles that can be applied to the parsed Markdown. The `fontName` property is optional, and if it's not set then the `fontName` property of the Body style will be applied.

If that is not set, then the system default will be used.
*/
@objc open class BasicStyles : NSObject, FontProperties {
    public var fontName : String?
    #if os(macOS)
    public var color = NSColor.textColor
    #else
    public var color = UIColor.label
    #endif
    public var fontSize : CGFloat = 0.0
    public var fontStyle : FontStyle = .normal
}

@objc open class LineStyles : NSObject, FontProperties, LineProperties {
    public var fontName : String?
    #if os(macOS)
    public var color = NSColor.textColor
    #else
    public var color = UIColor.label
    #endif
    public var fontSize : CGFloat = 0.0
    public var fontStyle : FontStyle = .normal
    public var alignment: NSTextAlignment = .left
    public var lineSpacing : CGFloat = 0.0
    public var paragraphSpacing : CGFloat = 0.0
}

@objc open class LinkStyles : BasicStyles {
    public var underlineStyle: NSUnderlineStyle = .single
    #if os(macOS)
    public lazy var underlineColor = self.color
    #else
    public lazy var underlineColor = self.color
    #endif
}

#if os(macOS)
@objc open class TableStyles : NSObject {
    public var borderWidth: CGFloat = 0.5
    public var borderColor: NSColor = {
        if #available(macOS 10.14, *) {
            return .separatorColor
        } else {
            return .gridColor
        }
    }()
    public var cellPadding: CGFloat = 6.0
}

@objc open class TableCellStyles : LineStyles {
    // Inherits fontName, fontSize, color, fontStyle, alignment, lineSpacing, paragraphSpacing
}
#else
@objc open class TableStyles : NSObject {
    public var borderWidth: CGFloat = 0.5
    public var borderColor: UIColor = .separator
    public var cellPadding: CGFloat = 6.0
}

@objc open class TableCellStyles : LineStyles {
    // Inherits fontName, fontSize, color, fontStyle, alignment, lineSpacing, paragraphSpacing
}
#endif

/// How a soft line break (a newline inside a paragraph) is rendered.
public enum SoftBreakStyle {
    /// As a line break (U+2028) within the paragraph. Suits text whose author meant
    /// each line to stand alone, such as chat messages.
    case lineBreak
    /// As a space, so hard-wrapped text reflows. Suits Markdown files.
    case space
}

/// A class that takes a [Markdown](https://daringfireball.net/projects/markdown/) string or file and returns an NSAttributedString with the applied styles. Supports Dynamic Type.
@objc open class SwiftyMarkdown: NSObject {
    
    static public var characterRules = [
        CharacterRule(primaryTag: CharacterRuleTag(tag: "![", type: .open), otherTags: [
                CharacterRuleTag(tag: "]", type: .close),
                CharacterRuleTag(tag: "[", type: .metadataOpen),
                CharacterRuleTag(tag: "]", type: .metadataClose)
        ], styles: [1 : CharacterStyle.image], metadataLookup: true, definesBoundary: true),
        CharacterRule(primaryTag: CharacterRuleTag(tag: "![", type: .open), otherTags: [
                CharacterRuleTag(tag: "]", type: .close),
                CharacterRuleTag(tag: "(", type: .metadataOpen),
                CharacterRuleTag(tag: ")", type: .metadataClose)
        ], styles: [1 : CharacterStyle.image], metadataLookup: false, definesBoundary: true),
        CharacterRule(primaryTag: CharacterRuleTag(tag: "[", type: .open), otherTags: [
                CharacterRuleTag(tag: "]", type: .close),
                CharacterRuleTag(tag: "[", type: .metadataOpen),
                CharacterRuleTag(tag: "]", type: .metadataClose)
        ], styles: [1 : CharacterStyle.link], metadataLookup: true, definesBoundary: true),
        CharacterRule(primaryTag: CharacterRuleTag(tag: "[", type: .open), otherTags: [
                CharacterRuleTag(tag: "]", type: .close),
                CharacterRuleTag(tag: "(", type: .metadataOpen),
                CharacterRuleTag(tag: ")", type: .metadataClose)
        ], styles: [1 : CharacterStyle.link], metadataLookup: false, definesBoundary: true),
        CharacterRule(primaryTag: CharacterRuleTag(tag: "`", type: .repeating), otherTags: [], styles: [1 : CharacterStyle.code], shouldCancelRemainingRules: true, balancedTags: true),
        CharacterRule(primaryTag:CharacterRuleTag(tag: "~", type: .repeating), otherTags : [], styles: [2 : CharacterStyle.strikethrough], minTags:2 , maxTags:2),
        CharacterRule(primaryTag: CharacterRuleTag(tag: "*", type: .repeating), otherTags: [], styles: [1 : CharacterStyle.italic, 2 : CharacterStyle.bold], minTags:1 , maxTags:2),
        CharacterRule(primaryTag: CharacterRuleTag(tag: "_", type: .repeating), otherTags: [], styles: [1 : CharacterStyle.italic, 2 : CharacterStyle.bold], minTags:1 , maxTags:2)
    ]
    
    let tokeniser = SwiftyTokeniser(with: SwiftyMarkdown.characterRules)

    open var tabStopInterval = CGFloat(10)

    /// The styles to apply to any H1 headers found in the Markdown
    open var h1 = LineStyles()
    
    /// The styles to apply to any H2 headers found in the Markdown
    open var h2 = LineStyles()
    
    /// The styles to apply to any H3 headers found in the Markdown
    open var h3 = LineStyles()
    
    /// The styles to apply to any H4 headers found in the Markdown
    open var h4 = LineStyles()
    
    /// The styles to apply to any H5 headers found in the Markdown
    open var h5 = LineStyles()
    
    /// The styles to apply to any H6 headers found in the Markdown
    open var h6 = LineStyles()
    
    /// The default body styles. These are the base styles and will be used for e.g. headers if no other styles override them.
    open var body = LineStyles()
    
    /// The styles to apply to any blockquotes found in the Markdown
    open var blockquotes = LineStyles()
    
    /// The styles to apply to any links found in the Markdown
    open var link = LinkStyles()
    
    /// The styles to apply to any bold text found in the Markdown
    open var bold = BasicStyles()
    
    /// The styles to apply to any italic text found in the Markdown
    open var italic = BasicStyles()
    
    /// The styles to apply to any code blocks or inline code text found in the Markdown
    open var code = BasicStyles()

    open var strikethrough = BasicStyles()

    /// The styles to apply to tables
    open var tableStyle = TableStyles()

    /// The styles to apply to table header cells (bold by default)
    open var tableHeader: TableCellStyles = {
        let styles = TableCellStyles()
        styles.fontStyle = .bold
        return styles
    }()

    /// The styles to apply to table body cells
    open var tableCell = TableCellStyles()

    public var bullet : String = "・"

    /// How a newline inside a paragraph is rendered. Hard breaks (two trailing spaces
    /// or a trailing backslash) are always line breaks.
    public var softBreakStyle: SoftBreakStyle = .lineBreak

    /// Rewrites the Markdown source of each paragraph, heading, list item, and table
    /// cell before its inline content is parsed. Code is not passed through it.
    public var inlineTransform: ((String) -> String)?

    /// The link reference definitions found by the most recent attributedString(),
    /// keyed by normalizedLinkLabel(_:). They're available to inlineTransform.
    public private(set) var linkReferences: [String: String] = [:]

    /// A link label as CommonMark matches it, for looking up linkReferences.
    public static func normalizedLinkLabel(_ label: String) -> String {
        return MarkdownBlockParser.normalizedLabel(label)
    }

    /// The zero-based numbers of the lines of `markdown` that are in code blocks,
    /// fenced or indented, counting lines as separated by “\n”, “\r\n”, or “\r”.
    /// Fence lines are included; blank lines inside a block may not be.
    public static func codeLines(in markdown: String) -> IndexSet {
        return MarkdownBlockParser(softBreakStyle: .lineBreak, bullet: "").parse(markdown).codeLines
    }

    func tokens(forInlineSource source: String) -> [Token] {
        return tokeniser.process(inlineTransform?(source) ?? source)
    }
    
    public var underlineLinks : Bool = false
    
    public var frontMatterAttributes : [String : String] {
        get {
            return self.parsedFrontMatterAttributes
        }
    }

    var parsedFrontMatterAttributes : [String : String] = [:]
    
    var currentType : MarkdownLineStyle = .body
    
    var string : String

    var previouslyFoundTokens : [Token] = []
    
    var applyAttachments = true
    
    let perfomanceLog = PerformanceLog(with: "SwiftyMarkdownPerformanceLogging", identifier: "Swifty Markdown", log: .swiftyMarkdownPerformance)
        
    /**
    
    - parameter string: A string containing [Markdown](https://daringfireball.net/projects/markdown/) syntax to be converted to an NSAttributedString
    
    - returns: An initialized SwiftyMarkdown object
    */
    public init(string : String ) {
        self.string = string
        super.init()
        self.setup()
    }
    
    /**
    A failable initializer that takes a URL and attempts to read it as a UTF-8 string
    
    - parameter url: The location of the file to read
    
    - returns: An initialized SwiftyMarkdown object, or nil if the string couldn't be read
    */
    public init?(url : URL ) {
        
        do {
            self.string = try NSString(contentsOf: url, encoding: String.Encoding.utf8.rawValue) as String
            
        } catch {
            self.string = ""
            return nil
        }
        super.init()
        self.setup()
    }
    
    func setup() {
        #if os(macOS)
        self.setFontColorForAllStyles(with: .labelColor)
        #elseif !os(watchOS)
        if #available(iOS 13.0, tvOS 13.0, *) {
            self.setFontColorForAllStyles(with: .label)
        }
        #endif
    }
    
    /**
    Set font size for all styles
    
    - parameter size: size of font
    */
    open func setFontSizeForAllStyles(with size: CGFloat) {
        h1.fontSize = size
        h2.fontSize = size
        h3.fontSize = size
        h4.fontSize = size
        h5.fontSize = size
        h6.fontSize = size
        body.fontSize = size
        italic.fontSize = size
        bold.fontSize = size
        code.fontSize = size
        link.fontSize = size
        link.fontSize = size
        strikethrough.fontSize = size
    }
    
    #if os(macOS)
    open func setFontColorForAllStyles(with color: NSColor) {
        h1.color = color
        h2.color = color
        h3.color = color
        h4.color = color
        h5.color = color
        h6.color = color
        body.color = color
        italic.color = color
        bold.color = color
        code.color = color
        link.color = color
        blockquotes.color = color
        strikethrough.color = color
    }
    #else
    open func setFontColorForAllStyles(with color: UIColor) {
        h1.color = color
        h2.color = color
        h3.color = color
        h4.color = color
        h5.color = color
        h6.color = color
        body.color = color
        italic.color = color
        bold.color = color
        code.color = color
        link.color = color
        blockquotes.color = color
        strikethrough.color = color
    }
    #endif
    
    open func setFontNameForAllStyles(with name: String) {
        h1.fontName = name
        h2.fontName = name
        h3.fontName = name
        h4.fontName = name
        h5.fontName = name
        h6.fontName = name
        body.fontName = name
        italic.fontName = name
        bold.fontName = name
        code.fontName = name
        link.fontName = name
        blockquotes.fontName = name
        strikethrough.fontName = name
    }
    
    
    /**
    Generates an NSAttributedString from the string or URL passed at initialisation. Custom fonts or styles are applied to the appropriate elements when this method is called.
    
    - returns: An NSAttributedString with the styles applied
    */
    open func attributedString(from markdownString : String? = nil) -> NSAttributedString {
        
        self.previouslyFoundTokens.removeAll()
        self.perfomanceLog.start()
        
        if let existentMarkdownString = markdownString {
            self.string = existentMarkdownString
        }
        let attributedString = NSMutableAttributedString(string: "")
        let parser = MarkdownBlockParser(softBreakStyle: softBreakStyle, bullet: bullet)
        let parsed = parser.parse(self.string)
        self.parsedFrontMatterAttributes = parsed.frontMatter

        self.perfomanceLog.tag(with: "(block parsing complete)")

        self.tokeniser.metadataLookup = parsed.references
        self.linkReferences = parsed.references

        // Set when the previous paragraph already ended itself with a styled newline.
        var newlineAppended = false
        for (idx, paragraph) in parsed.paragraphs.enumerated() {
            if idx > 0 && !newlineAppended {
                attributedString.append(NSAttributedString(string: "\n"))
            }
            newlineAppended = false

            let lineStyle: MarkdownLineStyle
            var marker: String?
            let finalTokens: [Token]
            switch paragraph.kind {
            case .blank, .definition:
                continue
            case .table(let table):
                let tableString = NSMutableAttributedString(attributedString: attributedStringForTable(table))
                let tableRange = NSRange(location: 0, length: tableString.length)
                tableString.addAttribute(.swiftyMarkdownLineStyle,
                                         value: MarkdownLineStyle.table.stringValue,
                                         range: tableRange)
                if let listLevel = paragraph.listLevel {
                    tableString.addAttribute(.swiftyMarkdownListLevel, value: NSNumber(value: listLevel), range: tableRange)
                }
                if paragraph.quoteDepth > 0 {
                    tableString.addAttribute(.swiftyMarkdownQuoteDepth, value: NSNumber(value: paragraph.quoteDepth), range: tableRange)
                }
                attributedString.append(tableString)
                // Each cell ends with its own newline, the last one included.
                newlineAppended = true
                continue
            case .rule:
                lineStyle = .horizontalRule
                finalTokens = [Token(type: .string,
                                     inputString: String(repeating: "\u{2500}", count: 30))]
            case .code:
                lineStyle = .codeblock
                finalTokens = [Token(type: .string,
                                     inputString: paragraph.text,
                                     characterStyles: [CharacterStyle.code])]
            case .heading(let level):
                lineStyle = [.h1, .h2, .h3, .h4, .h5, .h6][level - 1]
                finalTokens = self.tokens(forInlineSource: paragraph.text)
            case .text:
                lineStyle = paragraph.directlyInQuote ? .blockquote : .body
                finalTokens = self.tokens(forInlineSource: paragraph.text)
            case let .listItem(itemMarker, ordered):
                lineStyle = MarkdownLineStyle.listItem(ordered: ordered, level: paragraph.listLevel ?? 0)
                marker = itemMarker
                finalTokens = self.tokens(forInlineSource: paragraph.text)
            }
            self.previouslyFoundTokens.append(contentsOf: finalTokens)
            self.perfomanceLog.tag(with: "(tokenising complete for paragraph \(idx)")

            var tokensToRender = finalTokens
            if lineStyle == .codeblock && paragraph.text.isEmpty {
                // An empty line of code has no characters to carry its style, so the
                // newline that ends it does, even at the end of the document.
                tokensToRender = [Token(type: .string, inputString: "\n", characterStyles: [CharacterStyle.code])]
                newlineAppended = true
            }
            let rendered = NSMutableAttributedString(attributedString: attributedStringFor(tokens: tokensToRender,
                                                                                         in: SwiftyLine(line: paragraph.text, lineStyle: lineStyle),
                                                                                         marker: marker,
                                                                                         listLevel: paragraph.listLevel,
                                                                                         quoteDepth: paragraph.quoteDepth))
            if paragraph.startsCodeBlock {
                rendered.addAttribute(.swiftyMarkdownCodeBlockStart, value: true, range: NSRange(location: 0, length: rendered.length))
            }
            attributedString.append(rendered)
        }
        
        self.perfomanceLog.end()
        
        return attributedString
    }
    
}

extension SwiftyMarkdown {
    
    /// - Parameters:
    ///   - marker: For the first paragraph of a list item, its leading tabs, bullet or number, and tab.
    ///   - listLevel: The level of the innermost list item containing the paragraph.
    ///   - quoteDepth: How many blockquotes contain the paragraph.
    func attributedStringFor(tokens : [Token],
                             in line : SwiftyLine,
                             marker: String? = nil,
                             listLevel: Int? = nil,
                             quoteDepth: Int = 0) -> NSAttributedString {
        
        var finalTokens = tokens
        let finalAttributedString = NSMutableAttributedString()
        var attributes : [NSAttributedString.Key : AnyObject] = [:]
    
        guard let markdownLineStyle = line.lineStyle as? MarkdownLineStyle else {
            preconditionFailure("The passed line style is not a valid Markdown Line Style")
        }

        let interval = tabStopInterval
        // How far text inside a list item (but not its first paragraph) is indented.
        let listIndent = listLevel.map { interval * CGFloat($0 + 1) } ?? 0
        let quoteIndent = 20.0 * CGFloat(quoteDepth)

        let lineProperties : LineProperties
        attributes[.swiftyMarkdownLineStyle] = markdownLineStyle.stringValue as AnyObject
        if let listLevel {
            attributes[.swiftyMarkdownListLevel] = NSNumber(value: listLevel)
        }
        if quoteDepth > 0 {
            attributes[.swiftyMarkdownQuoteDepth] = NSNumber(value: quoteDepth)
        }
        switch markdownLineStyle {
        case .h1:
            lineProperties = self.h1
        case .h2:
            lineProperties = self.h2
        case .h3:
            lineProperties = self.h3
        case .h4:
            lineProperties = self.h4
        case .h5:
            lineProperties = self.h5
        case .h6:
            lineProperties = self.h6
        case .codeblock:
            lineProperties = body
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.firstLineHeadIndent = 20.0 + listIndent + quoteIndent
            paragraphStyle.headIndent = listIndent + quoteIndent
            attributes[.paragraphStyle] = paragraphStyle
        case .blockquote:
            lineProperties = self.blockquotes
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.firstLineHeadIndent = listIndent + max(20.0, quoteIndent)
            paragraphStyle.headIndent = listIndent + max(20.0, quoteIndent)
            attributes[.paragraphStyle] = paragraphStyle
        case .unorderedList, .unorderedListIndentFirstOrder, .unorderedListIndentSecondOrder, .orderedList, .orderedListIndentFirstOrder, .orderedListIndentSecondOrder:
            lineProperties = body
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: quoteIndent + interval, options: [:])]
            paragraphStyle.defaultTabInterval = interval
            paragraphStyle.firstLineHeadIndent = quoteIndent
            paragraphStyle.headIndent = quoteIndent + listIndent

            attributes[.paragraphStyle] = paragraphStyle
            if let marker {
                finalTokens.insert(Token(type: .string, inputString: marker), at: 0)
            }

        case .body:
            lineProperties = body
        case .yaml, .previousH1, .previousH2, .referencedLink, .table, .horizontalRule:
            lineProperties = body
        }
        switch markdownLineStyle {
        case .codeblock, .blockquote, .unorderedList, .unorderedListIndentFirstOrder, .unorderedListIndentSecondOrder,
                .orderedList, .orderedListIndentFirstOrder, .orderedListIndentSecondOrder:
            break
        default:
            // Headings, text continuing a list item, and rules inside a quote or list item.
            let indent = quoteIndent + listIndent
            if indent > 0 {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.firstLineHeadIndent = indent
                paragraphStyle.headIndent = indent
                attributes[.paragraphStyle] = paragraphStyle
            }
        }
        
        let paragraphStyle = attributes[.paragraphStyle] as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        if lineProperties.alignment != .left {
            paragraphStyle.alignment = lineProperties.alignment
        }
        paragraphStyle.lineSpacing = lineProperties.lineSpacing
        paragraphStyle.paragraphSpacing = lineProperties.paragraphSpacing
        attributes[.paragraphStyle] = paragraphStyle
        
        
        for token in finalTokens {
            attributes[.font] = self.font(for: line)
            attributes[.link] = nil
            attributes[.strikethroughStyle] = nil
            attributes[.foregroundColor] = self.color(for: line)
            attributes[.underlineStyle] = nil
            guard let styles = token.characterStyles as? [CharacterStyle] else {
                continue
            }
            attributes[.swiftyMarkdownCharacterStyles] = styles.map {
                $0.rawValue
            } as AnyObject
            if styles.contains(.italic) {
                attributes[.font] = self.font(for: line, characterOverride: .italic)
                attributes[.foregroundColor] = self.italic.color
            }
            if styles.contains(.bold) {
                attributes[.font] = self.font(for: line, characterOverride: .bold)
                attributes[.foregroundColor] = self.bold.color
            }
            
            if let linkIdx = styles.firstIndex(of: .link), linkIdx < token.metadataStrings.count {
                attributes[.foregroundColor] = self.link.color
                attributes[.font] = self.font(for: line, characterOverride: .link)
                attributes[.link] = token.metadataStrings[linkIdx] as AnyObject

                if underlineLinks {
                    attributes[.underlineStyle] = self.link.underlineStyle.rawValue as AnyObject
                    attributes[.underlineColor] = self.link.underlineColor
                }
            }
                        
            if styles.contains(.strikethrough) {
                attributes[.font] = self.font(for: line, characterOverride: .strikethrough)
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue as AnyObject
                attributes[.foregroundColor] = self.strikethrough.color
            }
            
            #if !os(watchOS)
            if let imgIdx = styles.firstIndex(of: .image), imgIdx < token.metadataStrings.count {
                if !self.applyAttachments {
                    continue
                }
                #if !os(macOS)
                let image1Attachment = NSTextAttachment()
                image1Attachment.image = UIImage(named: token.metadataStrings[imgIdx])
                let str = NSAttributedString(attachment: image1Attachment)
                finalAttributedString.append(str)
                #elseif !os(watchOS)
                let image1Attachment = NSTextAttachment()
                image1Attachment.image = NSImage(named: token.metadataStrings[imgIdx])
                let str = NSAttributedString(attachment: image1Attachment)
                finalAttributedString.append(str)
                #endif
                continue
            }
            #endif
            
            if styles.contains(.code) {
                attributes[.foregroundColor] = self.code.color
                attributes[.font] = self.font(for: line, characterOverride: .code)
            } else {
                // Switch back to previous font
            }
            let str = NSAttributedString(string: token.outputString, attributes: attributes)
            finalAttributedString.append(str)
        }
    
        return finalAttributedString
    }
}

public extension NSAttributedString.Key {
    static let swiftyMarkdownLineStyle = NSAttributedString.Key("swiftyMarkdownLineStyle")
    static let swiftyMarkdownCharacterStyles = NSAttributedString.Key("swiftyMarkdownCharacterStyle")
    /// On every paragraph inside a list item: the item's nesting level, 0 for the outermost list.
    /// A paragraph that continues an item (rather than starting it) has this but no marker.
    static let swiftyMarkdownListLevel = NSAttributedString.Key("swiftyMarkdownListLevel")
    /// On every paragraph inside a blockquote: how many quotes enclose it.
    static let swiftyMarkdownQuoteDepth = NSAttributedString.Key("swiftyMarkdownQuoteDepth")
    /// On the first line of each code block, so adjacent blocks can be told apart.
    static let swiftyMarkdownCodeBlockStart = NSAttributedString.Key("swiftyMarkdownCodeBlockStart")
}
