//
//  SwiftyMarkdownBlockTests.swift
//  SwiftyMarkdownTests
//
//  Created by George Nachman on 4/18/22.
//

@testable import SwiftyMarkdown
import XCTest

class SwiftyMarkdownBlockTests: XCTestCase {
    private func attempt(_ challenge: TokenTest) -> ChallengeReturn {
        let md = SwiftyMarkdown(string: challenge.input)
        md.applyAttachments = false
        let attributedString = md.attributedString()
        let tokens: [Token] = md.previouslyFoundTokens
        let stringTokens = tokens.filter { $0.type == .string && !$0.isMetadata }
        let linkTokens = tokens.filter({ $0.type == .string && (($0.characterStyles as? [CharacterStyle])?.contains(.link) ?? false) })
        let imageTokens = tokens.filter({ $0.type == .string && (($0.characterStyles as? [CharacterStyle])?.contains(.image) ?? false) })
        let existentTokenStyles = stringTokens.compactMap({ $0.characterStyles as? [CharacterStyle] })
        let expectedStyles = challenge.tokens.compactMap({ $0.characterStyles as? [CharacterStyle] })

        return ChallengeReturn(tokens: tokens,
                               stringTokens: stringTokens,
                               links: linkTokens,
                               images: imageTokens,
                               attributedString: attributedString,
                               foundStyles: existentTokenStyles,
                               expectedStyles: expectedStyles)
    }

    func testCodeBlockTokens() {
        let challenge = TokenTest(
            input: "```\nCode\nblock\n```",
            output: "Code\nBlock\n",
            tokens: [Token(type: .string, inputString: "Code", characterStyles: [CharacterStyle.code]),
                     Token(type: .string, inputString: "block", characterStyles: [CharacterStyle.code])])
        let results = attempt(challenge)
        XCTAssertEqual(results.tokens.count, challenge.tokens.count)
        for (expected, actual) in zip(challenge.tokens, results.tokens) {
            XCTAssertEqual(expected.characterStyles.count, actual.characterStyles.count)
            for (expected, actual) in zip(expected.characterStyles, actual.characterStyles) {
                XCTAssertTrue(expected.isEqualTo(actual))
            }
        }
    }

}
