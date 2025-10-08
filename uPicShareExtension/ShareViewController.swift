//
//  ShareViewController.swift
//  uPicShareExtension
//
//  Created by Licardo on 2021/1/12.
//  Copyright © 2021 Svend Jin. All rights reserved.
//

import Cocoa

class ShareViewController: NSViewController {
    
    @IBOutlet weak var label: NSTextField!
    @IBOutlet weak var timerLabel: NSTextField!
    @IBOutlet weak var okButton: NSButton!
    
    override var nibName: NSNib.Name? {
        return NSNib.Name("ShareViewController")
    }
    
    override func loadView() {
        super.loadView()
        
        label.stringValue = "Processing files...".localized
        self.timerLabel.stringValue = "Please wait...".localized
        okButton.title = "OK".localized

        processSelectedFiles { filePaths in
            DispatchQueue.main.async {
                if !filePaths.isEmpty {
                    self.label.stringValue = "Success".localized
                    self.timerLabel.stringValue = "Launching uPic...".localized
                    
                    // 将文件路径编码并通过 URL Scheme 传递给主应用
                    let encodedPaths = filePaths.compactMap { $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) }
                    let pathsParam = encodedPaths.joined(separator: ",")
                    let encodeUrl = "uPic://files?\(pathsParam)"
                    
                    if let url = URL(string: encodeUrl) {
                        NSWorkspace.shared.open(url)
                        debugPrint("调用主应用，传递文件路径: \(filePaths)")
                    } else {
                        debugPrint("创建 URL 失败: \(encodeUrl)")
                    }
                    
                    // 成功后短暂延迟关闭
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        let cancelError = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
                        self.extensionContext!.cancelRequest(withError: cancelError)
                    }
                } else {
                    self.label.stringValue = "Failed to process files".localized
                    self.timerLabel.stringValue = "Please try again".localized
                    
                    // 失败后 3 秒关闭
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        let cancelError = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
                        self.extensionContext!.cancelRequest(withError: cancelError)
                    }
                }
            }
        }
    }
    
    func processSelectedFiles(completion: @escaping ([String]) -> Void) {
        let item = self.extensionContext!.inputItems[0] as! NSExtensionItem
        var filePaths: [String] = []
        var processedCount = 0
        
        guard let itemProviders = item.attachments, !itemProviders.isEmpty else {
            completion([])
            return
        }
        
        let totalCount = itemProviders.count
        
        for itemProvider in itemProviders {
            if itemProvider.hasItemConformingToTypeIdentifier("public.url") {
                itemProvider.loadItem(forTypeIdentifier: "public.url", options: nil) { (data, error) in
                    defer {
                        processedCount += 1
                        if processedCount == totalCount {
                            // 所有文件处理完成，返回文件路径数组
                            completion(filePaths)
                        }
                    }
                    
                    if let error = error {
                        debugPrint("加载文件项失败: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let nsData = data as? NSData,
                          let originalURL = NSURL(dataRepresentation: nsData as Data, relativeTo: nil) as URL? else {
                        debugPrint("无法解析文件URL")
                        return
                    }
                    
                    // 直接获取原始文件路径，不再复制文件
                    let filePath = originalURL.path
                    filePaths.append(filePath)
                    debugPrint("获取到文件路径: \(filePath)")
                }
            } else {
                processedCount += 1
                if processedCount == totalCount {
                    completion(filePaths)
                }
            }
        }
    }
    
    @IBAction func didClickOKButton(_ sender: NSButton) {
        let cancelError = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
        self.extensionContext!.cancelRequest(withError: cancelError)
    }
}
