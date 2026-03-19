//
//  main.swift
//  markdown2png
//
//  Test tool that uses SwiftyMarkdown to render markdown to PNG.
//
//  Usage: swift run markdown2png input.md [output.png]
//

import AppKit
import SwiftyMarkdown

func main() {
    let args = CommandLine.arguments

    guard args.count >= 2 else {
        print("Usage: \(args[0]) input.md [output.png]")
        print("")
        print("Renders a markdown file to a PNG image using SwiftyMarkdown.")
        print("If output.png is not specified, uses the input filename with .png extension.")
        exit(1)
    }

    let inputPath = args[1]
    let outputPath: String

    if args.count >= 3 {
        outputPath = args[2]
    } else {
        let inputURL = URL(fileURLWithPath: inputPath)
        let outputURL = inputURL.deletingPathExtension().appendingPathExtension("png")
        outputPath = outputURL.path
    }

    guard let markdownContent = try? String(contentsOfFile: inputPath, encoding: .utf8) else {
        print("Error: Could not read file at \(inputPath)")
        exit(1)
    }

    // Use SwiftyMarkdown to parse and render
    let md = SwiftyMarkdown(string: markdownContent)

    // Configure styles for visibility
    md.h1.fontSize = 28
    md.h2.fontSize = 22
    md.h3.fontSize = 18
    md.body.fontSize = 14
    md.code.fontSize = 13
    md.code.color = .systemRed
    md.tableHeader.fontSize = 14
    md.tableCell.fontSize = 14

    let attributedString = md.attributedString()

    guard let image = renderToImage(attributedString, maxWidth: 800) else {
        print("Error: Could not render to image")
        exit(1)
    }

    guard savePNG(image: image, to: outputPath) else {
        print("Error: Could not save PNG to \(outputPath)")
        exit(1)
    }

    print("Successfully saved to \(outputPath)")
}

func renderToImage(_ attrString: NSAttributedString, maxWidth: CGFloat) -> NSImage? {
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: maxWidth, height: 10000))
    textView.isEditable = false
    textView.isSelectable = false
    textView.drawsBackground = true
    textView.backgroundColor = .textBackgroundColor
    textView.textContainerInset = NSSize(width: 20, height: 20)

    textView.textStorage?.setAttributedString(attrString)
    textView.layoutManager?.ensureLayout(for: textView.textContainer!)

    guard let layoutManager = textView.layoutManager,
          let textContainer = textView.textContainer else {
        return nil
    }

    let glyphRange = layoutManager.glyphRange(for: textContainer)
    let textBounds = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

    let padding: CGFloat = 40
    let height = textBounds.height + padding * 2 + 40

    textView.frame = NSRect(x: 0, y: 0, width: maxWidth, height: height)

    guard let bitmapRep = textView.bitmapImageRepForCachingDisplay(in: textView.bounds) else {
        return nil
    }

    NSGraphicsContext.saveGraphicsState()
    if let context = NSGraphicsContext(bitmapImageRep: bitmapRep) {
        NSGraphicsContext.current = context
        NSColor.textBackgroundColor.setFill()
        NSRect(origin: .zero, size: textView.bounds.size).fill()
    }
    NSGraphicsContext.restoreGraphicsState()

    textView.cacheDisplay(in: textView.bounds, to: bitmapRep)

    let image = NSImage(size: textView.bounds.size)
    image.addRepresentation(bitmapRep)

    return image
}

func savePNG(image: NSImage, to path: String) -> Bool {
    guard let tiffData = image.tiffRepresentation,
          let bitmapRep = NSBitmapImageRep(data: tiffData),
          let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        return false
    }

    do {
        try pngData.write(to: URL(fileURLWithPath: path))
        return true
    } catch {
        print("Error writing file: \(error)")
        return false
    }
}

main()
