//
//  SwiftyLine.swift
//  SwiftyMarkdown
//
//  Created by Simon Fairbairn on 16/12/2019.
//  Copyright © 2019 Voyage Travel Apps. All rights reserved.
//

import Foundation

public protocol LineStyling {
}

/// A paragraph's text and line style, which choose its font and color.
public struct SwiftyLine : CustomStringConvertible {
    public let line : String
    public let lineStyle : LineStyling

    public var description: String {
        return self.line + " (\(String(describing: lineStyle))"
    }

    init(line: String, lineStyle: LineStyling) {
        self.line = line
        self.lineStyle = lineStyle
    }
}
