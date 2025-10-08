//
//  DiskPermissionManager.swift
//  uPic
//
//  Created by Svend Jin on 2021/01/19.
//  Copyright © 2021 Svend Jin. All rights reserved.
//

import Foundation
import Cocoa

public class DiskPermissionManager {
    
    // static
    public static var shared = DiskPermissionManager()

    // 储存当前开始授权访问的 URL 对象
    private var workingDirectoryBookmarkUrl: URL?
    // 储存根目录子目录访问的 URL 对象列表
    private var rootSubdirectoryUrls: [URL] = []
    
    private init() {}
    
    // MARK: - macOS Version Detection
    
    /// 检测是否需要使用根目录 bookmark 的临时解决方案
    /// macOS 26.0 存在根目录 bookmark 创建失败的 bug，需要使用子目录 bookmark 的解决方案
    /// 该 bug 已在 macOS 26.1 beta 中修复
    private func shouldUseRootSubdirectoryWorkaround() -> Bool {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        
        // macOS 26.0 需要使用临时解决方案
        if osVersion.majorVersion == 26 && osVersion.minorVersion == 0 {
            return true
        }
        
        return false
    }
    
    // MARK: - Directory Permission Prompts
    
    private func promptForWorkingDirectoryPermission(for directoryURL: URL = URL(fileURLWithPath: "/", isDirectory: true)) -> URL? {
        let openPanel = NSOpenPanel()
        openPanel.message = "Authorize".localized
        openPanel.prompt = "Authorize".localized
        openPanel.allowedContentTypes = []
        openPanel.allowsOtherFileTypes = false
        openPanel.canChooseFiles = false
        openPanel.canCreateDirectories = false
        openPanel.canChooseDirectories = true
        openPanel.directoryURL = directoryURL
        
        openPanel.runModal()
        return openPanel.urls.first
    }
    
    private func saveBookmarkData(for workDir: URL, defaultKey: DefaultsKey<Data>) {
        do {
            let bookmarkData = try workDir.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            
            // save in UserDefaults
            Defaults[defaultKey] = bookmarkData
        } catch {
            print("Failed to save bookmark data for \(workDir)", error)
        }
    }
    
    private func restoreFileAccess(with bookmarkData: Data, defaultKey: DefaultsKey<Data>) -> URL? {
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale {
                // bookmarks could become stale as the OS changes
                print("Bookmark is stale, need to save a new one... ")
                saveBookmarkData(for: url, defaultKey: defaultKey)
            }
            return url
        } catch {
            print("Error resolving bookmark:", error)
            return nil
        }
    }
    
    // MARK: - Root Subdirectory Bookmark Methods (macOS 26.0 Workaround)
    
    /// 为根目录的所有子目录创建 security-scoped bookmark (macOS 26.0 临时解决方案)
    private func createRootSubdirectoryBookmarks(rootURL: URL) -> Bool {
        Logger.shared.verbose("开始为根目录子目录创建书签")
        
        // 通常无法创建 bookmark 的系统目录和文件
        let excludedPaths: Set<String> = [
            "home", "dev", "tmp", "var", "etc", "private",
            ".file", ".VolumeIcon.icns", ".fseventsd", ".DocumentRevisions-V100",
            ".Spotlight-V100", ".Trashes", ".vol", "net", "Volumes"
        ]
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [])
            var bookmarkDataArray: [Data] = []
            var subdirectoryNames: [String] = []
            var successCount = 0
            var failureCount = 0
            
            // 重要目录优先处理
            let priorityDirs = ["Applications", "System", "Users", "Library"]
            let allContents = contents.sorted { url1, url2 in
                let name1 = url1.lastPathComponent
                let name2 = url2.lastPathComponent
                let priority1 = priorityDirs.firstIndex(of: name1) ?? Int.max
                let priority2 = priorityDirs.firstIndex(of: name2) ?? Int.max
                return priority1 < priority2
            }
            
            for url in allContents {
                let fileName = url.lastPathComponent
                
                // 跳过已知的系统目录和隐藏文件
                if excludedPaths.contains(fileName) {
                    Logger.shared.verbose("跳过系统目录: \(url.path)")
                    continue
                }
                
                // 跳过以点开头的隐藏文件/目录（除了一些重要的目录）
                if fileName.hasPrefix(".") && !priorityDirs.contains(fileName) {
                    Logger.shared.verbose("跳过隐藏项目: \(url.path)")
                    continue
                }
                
                do {
                    let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    bookmarkDataArray.append(bookmarkData)
                    subdirectoryNames.append(fileName)
                    successCount += 1
                    Logger.shared.verbose("成功创建子目录书签: \(url.path)")
                } catch {
                    failureCount += 1
                    Logger.shared.verbose("为子目录创建书签失败: \(url.path), 错误: \(error.localizedDescription)")
                    // 继续处理其他目录，不因为单个目录失败而终止
                }
            }
            
            // 保存到 UserDefaults
            Defaults[.rootSubdirectoryBookmarks] = bookmarkDataArray
            Defaults[.rootSubdirectoryNames] = subdirectoryNames
            
            Logger.shared.verbose("根目录子目录书签创建完成，成功: \(successCount), 失败: \(failureCount), 总共有效书签: \(bookmarkDataArray.count)")
            
            // 只要有一些成功的书签就认为是成功的
            return bookmarkDataArray.count >= 2 // 至少需要2个有效书签才算成功
            
        } catch {
            Logger.shared.error("读取根目录内容失败: \(error)")
            return false
        }
    }
    
    /// 检查根目录子目录权限状态（macOS 26.0 临时解决方案）
    private func checkRootSubdirectoriesAuthorizationStatus() -> Bool {
        Logger.shared.verbose("开始检查根目录子目录权限状态")
        
        guard let bookmarkDataArray = Defaults[.rootSubdirectoryBookmarks],
              let storedNames = Defaults[.rootSubdirectoryNames],
              !bookmarkDataArray.isEmpty else {
            Logger.shared.verbose("未找到根目录子目录书签")
            return false
        }
        
        // 检查存储的书签数量是否合理
        if bookmarkDataArray.count < 2 {
            Logger.shared.verbose("有效书签数量太少，需要重新授权")
            return false
        }
        
        // 检查重要目录的书签是否存在（这些是最常用的目录）
        let importantDirs = ["Applications", "System", "Users", "Library"]
        let hasImportantDirs = importantDirs.contains { importantDir in
            storedNames.contains(importantDir)
        }
        
        if !hasImportantDirs {
            Logger.shared.verbose("缺少重要目录的书签，权限可能不完整")
            return false
        }
        
        // 尝试解析一些关键的 bookmark 来验证它们仍然有效
        var validBookmarks = 0
        for (index, bookmarkData) in bookmarkDataArray.enumerated() {
            if index >= storedNames.count { break }
            
            do {
                var isStale = false
                _ = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                if !isStale {
                    validBookmarks += 1
                }
            } catch {
                Logger.shared.verbose("书签解析失败: \(storedNames[index])")
            }
        }
        
        // 如果大部分书签都有效，认为权限状态良好
        let validRatio = Double(validBookmarks) / Double(bookmarkDataArray.count)
        let hasValidPermissions = validRatio > 0.6 // 60% 的书签有效就认为权限正常（考虑到某些目录可能会变化）
        
        Logger.shared.verbose("根目录子目录权限检查完成，有效书签: \(validBookmarks)/\(bookmarkDataArray.count)，比例: \(validRatio)")
        return hasValidPermissions
    }
    
    /// 启动根目录子目录访问（macOS 26.0 临时解决方案）
    private func startRootSubdirectoriesAccessing() -> Bool {
        Logger.shared.verbose("开始启动根目录子目录访问")
        
        guard let bookmarkDataArray = Defaults[.rootSubdirectoryBookmarks],
              let storedNames = Defaults[.rootSubdirectoryNames],
              !bookmarkDataArray.isEmpty else {
            Logger.shared.verbose("未找到根目录子目录书签")
            return false
        }
        
        // 停止之前的访问
        stopRootSubdirectoriesAccessing()
        
        var successCount = 0
        var failureCount = 0
        rootSubdirectoryUrls.removeAll()
        
        for (index, bookmarkData) in bookmarkDataArray.enumerated() {
            let dirName = index < storedNames.count ? storedNames[index] : "未知目录"
            
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                
                if isStale {
                    Logger.shared.verbose("书签已过期: \(dirName)")
                    failureCount += 1
                    continue
                }
                
                if url.startAccessingSecurityScopedResource() {
                    rootSubdirectoryUrls.append(url)
                    successCount += 1
                    Logger.shared.verbose("成功启动访问: \(url.path)")
                } else {
                    Logger.shared.verbose("启动安全作用域访问失败: \(url.path)")
                    failureCount += 1
                }
                
            } catch {
                Logger.shared.verbose("解析书签失败 (\(dirName)): \(error.localizedDescription)")
                failureCount += 1
            }
        }
        
        // 只要有一些成功的访问就认为成功
        let success = successCount >= 2 // 至少需要2个成功的访问
        Logger.shared.verbose("根目录子目录访问启动完成，成功: \(successCount), 失败: \(failureCount)")
        
        if !success {
            // 如果失败，清理已启动的访问
            stopRootSubdirectoriesAccessing()
        }
        
        return success
    }
    
    /// 停止根目录子目录访问（macOS 26.0 临时解决方案）
    private func stopRootSubdirectoriesAccessing() {
        Logger.shared.verbose("开始停止根目录子目录访问")
        
        for url in rootSubdirectoryUrls {
            url.stopAccessingSecurityScopedResource()
        }
        rootSubdirectoryUrls.removeAll()
        
        Logger.shared.verbose("根目录子目录访问停止完成")
    }
    
}

// Utils
extension DiskPermissionManager {
    
    /// 检查完全磁盘访问权限状态
    /// - Returns: 是否已授权完全磁盘访问权限
    func checkFullDiskAuthorizationStatus() -> Bool {
        Logger.shared.verbose("开始检查是否有全盘访问权限")
        
        // 如果需要使用临时解决方案（macOS 26.0）
        if shouldUseRootSubdirectoryWorkaround() {
            Logger.shared.verbose("使用根目录子目录权限检查方案 (macOS 26.0 临时解决方案)")
            return checkRootSubdirectoriesAuthorizationStatus()
        }
        
        // 传统的根目录 bookmark 检查方案
        if let data = Defaults[.rootDirectoryBookmark] {
            do {
                var isStale = true
                let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                if isStale {
                    // bookmarks could become stale as the OS changes
                    print("Bookmark is stale, need to save a new one... ")
                    Logger.shared.verbose("没有全盘访问权限-书签已过期，需要保存一个新的...")
                } else if (url.path == "/") {
                    Logger.shared.verbose("有全盘访问权限")
                    return true
                } else {
                    Logger.shared.verbose("没有全盘访问权限-书签路径为\(url.path)")
                }
            } catch {
                print("Error resolving bookmark:", error)
                Logger.shared.error("没有全盘访问权限-书签错误\(error)")
            }
        } else {
            Logger.shared.verbose("没有全盘访问权限-未找到传统根目录书签")
        }
        
        // 如果传统方案失败，检查是否有子目录 bookmarks 作为回退方案
        if let bookmarks = Defaults[.rootSubdirectoryBookmarks], !bookmarks.isEmpty {
            Logger.shared.verbose("传统根目录方案失败，尝试检查子目录权限方案")
            return checkRootSubdirectoriesAuthorizationStatus()
        }
        
        Logger.shared.verbose("没有找到任何有效的磁盘访问权限")
        return false
    }
    
    /// 请求完全磁盘访问权限
    func requestFullDiskPermissions() {
        Logger.shared.verbose("开始授权根目录权限")
        guard let url = self.promptForWorkingDirectoryPermission() else {
            Logger.shared.verbose("授权根目录权限失败")
            return
        }
        
        // 如果需要使用临时解决方案（macOS 26.0）
        if shouldUseRootSubdirectoryWorkaround() {
            Logger.shared.verbose("使用根目录子目录权限授权方案 (macOS 26.0 临时解决方案)")
            if url.path == "/" {
                if createRootSubdirectoryBookmarks(rootURL: url) {
                    Logger.shared.verbose("根目录子目录权限授权成功")
                } else {
                    Logger.shared.verbose("根目录子目录权限授权失败")
                }
            } else {
                Logger.shared.verbose("用户未选择根目录，无法使用子目录授权方案")
            }
            return
        }
        
        // 传统的根目录 bookmark 方案
        // 先尝试创建 bookmark 来检查是否成功
        do {
            _ = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            // 如果成功，保存 bookmark
            self.saveBookmarkData(for: url, defaultKey: .rootDirectoryBookmark)
            Logger.shared.verbose("授权根目录权限成功-\(url.path)")
        } catch {
            Logger.shared.error("创建根目录 bookmark 失败: \(error)")
            
            // 如果传统方案失败，尝试使用临时解决方案
            if url.path == "/" {
                Logger.shared.verbose("根目录 bookmark 创建失败，尝试使用子目录方案")
                if createRootSubdirectoryBookmarks(rootURL: url) {
                    Logger.shared.verbose("fallback 到根目录子目录权限授权成功")
                } else {
                    Logger.shared.verbose("fallback 到根目录子目录权限授权也失败")
                }
            }
        }
    }
    
    
    func cancelFullDiskPermissions() {
        Logger.shared.verbose("取消授权根目录权限")
        
        // 清除传统的根目录 bookmark
        Defaults[.rootDirectoryBookmark] = nil
        
        // 清除临时解决方案的子目录 bookmarks
        Defaults[.rootSubdirectoryBookmarks] = nil
        Defaults[.rootSubdirectoryNames] = nil
        
        // 停止当前的访问
        stopDirectoryAccessing()
        
        Logger.shared.verbose("取消根目录权限成功")
    }
    
    // 获取安全授权，根目录授权优先获取，无根目录书签时获取主目录书签
    func startDirectoryAccessing() -> Bool {
        Logger.shared.verbose("开始获取安全授权")
        
        stopDirectoryAccessing()
        
        // 如果需要使用临时解决方案（macOS 26.0）并且有子目录 bookmarks
        if shouldUseRootSubdirectoryWorkaround() {
            if let bookmarks = Defaults[.rootSubdirectoryBookmarks], !bookmarks.isEmpty {
                Logger.shared.verbose("使用根目录子目录访问方案 (macOS 26.0 临时解决方案)")
                let success = startRootSubdirectoriesAccessing()
                if success {
                    Logger.shared.verbose("获取安全授权完成--根目录子目录方案")
                    return true
                }
                Logger.shared.verbose("根目录子目录方案失败，尝试其他方案")
            }
        }
        
        // 获取根目录授权书签（传统方案或 macOS 26.1+ 修复后的方案）
        if let data = Defaults[.rootDirectoryBookmark], let url = restoreFileAccess(with: data, defaultKey: .rootDirectoryBookmark) {
            
            workingDirectoryBookmarkUrl = url
            let flag = url.startAccessingSecurityScopedResource()
            Logger.shared.verbose("获取安全授权完成--根目录-\(url.path)")
            return flag
        }
        
        Logger.shared.verbose("未获取安全授权")
        return false
    }
    
    func stopDirectoryAccessing() {
        Logger.shared.verbose("开始停止获取安全授权")
        
        // 停止根目录子目录访问
        stopRootSubdirectoriesAccessing()
        
        // 停止传统的单一目录访问
        if let url = workingDirectoryBookmarkUrl {
            url.stopAccessingSecurityScopedResource()
            workingDirectoryBookmarkUrl = nil
        }
        
        Logger.shared.verbose("停止获取安全授权完成")
    }
    
    /// 打开系统偏好设置 - 完全磁盘访问权限
    func openPreferences() {
        // 使用工作区打开系统偏好设置中的完全磁盘访问权限设置页面
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    /// 尝试从子目录方案升级到根目录方案（当系统修复 bug 后）
    /// 在应用启动时调用，检查是否可以升级到更好的方案
    func tryUpgradeToRootDirectoryPermission() {
        Logger.shared.verbose("检查是否可以升级到根目录权限方案")
        
        // 如果当前系统不需要使用临时解决方案，但我们有子目录 bookmarks
        if !shouldUseRootSubdirectoryWorkaround() {
            if let _ = Defaults[.rootSubdirectoryBookmarks], 
               Defaults[.rootDirectoryBookmark] == nil {
                Logger.shared.verbose("系统已修复根目录 bookmark bug，但当前使用子目录方案，尝试升级")
                
                // 尝试创建根目录 bookmark 来测试是否已修复
                let testURL = URL(fileURLWithPath: "/", isDirectory: true)
                do {
                    _ = try testURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    Logger.shared.verbose("根目录 bookmark 创建测试成功，系统已修复 bug")
                    
                    // 注意：这里不能自动升级，因为需要用户重新授权
                    // 只是清除临时方案的数据，提示用户重新授权会使用更好的方案
                    Logger.shared.verbose("清除临时方案数据，等待用户重新授权")
                    Defaults[.rootSubdirectoryBookmarks] = nil
                    Defaults[.rootSubdirectoryNames] = nil
                    
                } catch {
                    Logger.shared.verbose("根目录 bookmark 创建测试失败，系统尚未修复: \(error)")
                }
            }
        }
    }
}
