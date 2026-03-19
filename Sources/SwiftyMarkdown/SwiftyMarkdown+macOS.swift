//
//  SwiftyMarkdown+macOS.swift
//  SwiftyMarkdown
//
//  Created by Simon Fairbairn on 17/12/2019.
//  Copyright © 2019 Voyage Travel Apps. All rights reserved.
//

import Foundation
#if os(macOS)
import AppKit

extension SwiftyMarkdown {
	
	func font( for line : SwiftyLine, characterOverride : CharacterStyle? = nil ) -> NSFont {
		var fontName : String?
		var fontSize : CGFloat?
		
		var globalBold = false
		var globalItalic = false
		
		let style : FontProperties
		// What type are we and is there a font name set?
		switch line.lineStyle as! MarkdownLineStyle {
		case .h1:
			style = self.h1
		case .h2:
			style = self.h2
		case .h3:
			style = self.h3
		case .h4:
			style = self.h4
		case .h5:
			style = self.h5
		case .h6:
			style = self.h6
		case .codeblock:
			style = self.code
		case .blockquote:
			style = self.blockquotes
		default:
			style = self.body
		}
		
		fontName = style.fontName
		fontSize = style.fontSize
		switch style.fontStyle {
		case .bold:
			globalBold = true
		case .italic:
			globalItalic = true
		case .boldItalic:
			globalItalic = true
			globalBold = true
		case .normal:
			break
		}

		if fontName == nil {
			fontName = body.fontName
		}
		
		if let characterOverride = characterOverride {
			switch characterOverride {
			case .code:
				fontName = code.fontName ?? fontName
				fontSize = code.fontSize
			case .link:
				fontName = link.fontName ?? fontName
				fontSize = link.fontSize
			case .bold:
				fontName = bold.fontName ?? fontName
				fontSize = bold.fontSize
				globalBold = true
			case .italic:
				fontName = italic.fontName ?? fontName
				fontSize = italic.fontSize
				globalItalic = true
			default:
				break
			}
		}
		
		fontSize = fontSize == 0.0 ? nil : fontSize
		let finalSize : CGFloat
		if let existentFontSize = fontSize {
			finalSize = existentFontSize
		} else {
			finalSize = NSFont.systemFontSize
		}
		var font : NSFont
		if let existentFontName = fontName {
			if let customFont = NSFont(name: existentFontName, size: finalSize)  {
				font = customFont
			} else {
				font = NSFont.systemFont(ofSize: finalSize)
			}
		} else {
			font = NSFont.systemFont(ofSize: finalSize)
		}
		
		if globalItalic || globalBold {
			var traits: NSFontDescriptor.SymbolicTraits = []
			if globalItalic { traits.insert(.italic) }
			if globalBold { traits.insert(.bold) }
			let styledDescriptor = font.fontDescriptor.withSymbolicTraits(traits)
			font = NSFont(descriptor: styledDescriptor, size: 0) ?? font
		}
		
		return font
		
	}
	
	func color( for line : SwiftyLine ) -> NSColor {
		// What type are we and is there a font name set?
		switch line.lineStyle as! MarkdownLineStyle {
		case .h1, .previousH1:
			return h1.color
		case .h2, .previousH2:
			return h2.color
		case .h3:
			return h3.color
		case .h4:
			return h4.color
		case .h5:
			return h5.color
		case .h6:
			return h6.color
		case .body:
			return body.color
		case .codeblock:
			return code.color
		case .blockquote:
			return blockquotes.color
		case .unorderedList, .unorderedListIndentFirstOrder, .unorderedListIndentSecondOrder, .orderedList, .orderedListIndentFirstOrder, .orderedListIndentSecondOrder:
			return body.color
		case .yaml:
			return body.color
		case .referencedLink:
			return body.color
		case .table:
			return tableCell.color
		}
	}

    // MARK: - Table Rendering

    func attributedStringForTable(_ table: ParsedTable) -> NSAttributedString {
        let result = NSMutableAttributedString()

        let nsTable = NSTextTable()
        nsTable.numberOfColumns = table.columnCount
        nsTable.collapsesBorders = true

        // Render header row
        for (colIndex, header) in table.headers.enumerated() {
            let cellString = attributedStringForTableCell(
                content: header,
                table: nsTable,
                row: 0,
                column: colIndex,
                alignment: table.alignments[safe: colIndex] ?? .left,
                isHeader: true
            )
            result.append(cellString)
        }

        // Render body rows
        for (rowIndex, row) in table.rows.enumerated() {
            for (colIndex, cell) in row.enumerated() {
                let cellString = attributedStringForTableCell(
                    content: cell,
                    table: nsTable,
                    row: rowIndex + 1,  // +1 because row 0 is headers
                    column: colIndex,
                    alignment: table.alignments[safe: colIndex] ?? .left,
                    isHeader: false
                )
                result.append(cellString)
            }
        }

        return result
    }

    private func attributedStringForTableCell(
        content: String,
        table: NSTextTable,
        row: Int,
        column: Int,
        alignment: TableColumnAlignment,
        isHeader: Bool
    ) -> NSAttributedString {
        let block = NSTextTableBlock(
            table: table,
            startingRow: row,
            rowSpan: 1,
            startingColumn: column,
            columnSpan: 1
        )

        // Set border
        block.setWidth(tableStyle.borderWidth, type: .absoluteValueType, for: .border)
        block.setBorderColor(tableStyle.borderColor)

        // Set padding
        block.setWidth(tableStyle.cellPadding, type: .absoluteValueType, for: .padding)

        // Create paragraph style with the text block
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.textBlocks = [block]

        // Set alignment
        switch alignment {
        case .left:
            paragraphStyle.alignment = .left
        case .center:
            paragraphStyle.alignment = .center
        case .right:
            paragraphStyle.alignment = .right
        }

        // Get font and color based on whether this is a header or body cell
        let cellStyles: TableCellStyles = isHeader ? tableHeader : tableCell

        var font: NSFont
        let fontSize = cellStyles.fontSize > 0 ? cellStyles.fontSize : body.fontSize > 0 ? body.fontSize : NSFont.systemFontSize

        if let fontName = cellStyles.fontName ?? body.fontName,
           let customFont = NSFont(name: fontName, size: fontSize) {
            font = customFont
        } else {
            font = NSFont.systemFont(ofSize: fontSize)
        }

        // Apply font style
        switch cellStyles.fontStyle {
        case .bold:
            let boldDescriptor = font.fontDescriptor.withSymbolicTraits(.bold)
            font = NSFont(descriptor: boldDescriptor, size: 0) ?? font
        case .italic:
            let italicDescriptor = font.fontDescriptor.withSymbolicTraits(.italic)
            font = NSFont(descriptor: italicDescriptor, size: 0) ?? font
        case .boldItalic:
            var traits = font.fontDescriptor.symbolicTraits
            traits.insert(.bold)
            traits.insert(.italic)
            let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
            font = NSFont(descriptor: descriptor, size: 0) ?? font
        case .normal:
            break
        }

        let color = cellStyles.color

        // Tokenize cell content for inline formatting
        let tokens = tokeniser.process(content)

        // Build the attributed string for this cell
        let cellResult = NSMutableAttributedString()

        for token in tokens {
            var attributes: [NSAttributedString.Key: Any] = [
                .paragraphStyle: paragraphStyle,
                .font: font,
                .foregroundColor: color
            ]

            if let styles = token.characterStyles as? [CharacterStyle] {
                let hasBold = styles.contains(.bold)
                let hasItalic = styles.contains(.italic)
                if hasBold || hasItalic {
                    var traits: NSFontDescriptor.SymbolicTraits = []
                    if hasBold { traits.insert(.bold) }
                    if hasItalic { traits.insert(.italic) }
                    let styledDescriptor = font.fontDescriptor.withSymbolicTraits(traits)
                    attributes[.font] = NSFont(descriptor: styledDescriptor, size: 0) ?? font
                    // Use italic color if italic, otherwise bold color
                    attributes[.foregroundColor] = hasItalic ? italic.color : bold.color
                }
                if styles.contains(.code) {
                    if let codeFontName = code.fontName,
                       let codeFont = NSFont(name: codeFontName, size: code.fontSize > 0 ? code.fontSize : fontSize) {
                        attributes[.font] = codeFont
                    }
                    attributes[.foregroundColor] = code.color
                }
                if let linkIdx = styles.firstIndex(of: .link), linkIdx < token.metadataStrings.count {
                    attributes[.foregroundColor] = link.color
                    attributes[.link] = token.metadataStrings[linkIdx]
                    if underlineLinks {
                        attributes[.underlineStyle] = link.underlineStyle.rawValue
                        attributes[.underlineColor] = link.underlineColor
                    }
                }
                if styles.contains(.strikethrough) {
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                    attributes[.foregroundColor] = strikethrough.color
                }
            }

            cellResult.append(NSAttributedString(string: token.outputString, attributes: attributes))
        }

        // Add newline at end of cell (required for NSTextTable)
        let newlineAttributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle,
            .font: font
        ]
        cellResult.append(NSAttributedString(string: "\n", attributes: newlineAttributes))

        return cellResult
    }

}

// Helper extension for safe array access
private extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

#endif
