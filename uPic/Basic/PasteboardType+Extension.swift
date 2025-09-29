//
//  PasteboardType+Extension.swift
//  uPic
//
//  Created by Svend Jin on 2019/6/26.
//  Copyright © 2019 Svend Jin. All rights reserved.
//

import Cocoa
import UniformTypeIdentifiers

extension NSPasteboard.PasteboardType {
    // MARK: 剪切板扩展，让 10.13 以前的版本也支持 FileUrl 类型

    static let backwardsCompatibleFileURL: NSPasteboard.PasteboardType = {
        return NSPasteboard.PasteboardType.fileURL
    } ()

    static let backwardsCompatibleURL: NSPasteboard.PasteboardType = {
        return NSPasteboard.PasteboardType.URL
    } ()

    static let gif: NSPasteboard.PasteboardType = NSPasteboard.PasteboardType(UTType.gif.identifier)

    static let jpeg: NSPasteboard.PasteboardType = NSPasteboard.PasteboardType(UTType.jpeg.identifier)

    static let bmp: NSPasteboard.PasteboardType = NSPasteboard.PasteboardType(UTType.bmp.identifier)

    static let ico: NSPasteboard.PasteboardType = NSPasteboard.PasteboardType(UTType.ico.identifier)
}

