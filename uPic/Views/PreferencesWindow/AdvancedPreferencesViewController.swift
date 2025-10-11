//
//  AdvancedPreferencesViewController.swift
//  uPic
//
//  Created by Svend Jin on 2019/6/11.
//  Copyright © 2019 Svend Jin. All rights reserved.
//

import Cocoa
import KeyboardShortcuts

class AdvancedPreferencesViewController: PreferencesViewController {
    
    @IBOutlet weak var selectFileShortcut: NSSearchField!
    @IBOutlet weak var pasteboardShortcut: NSSearchField!
    @IBOutlet weak var screenshotShortcut: NSSearchField!
    @IBOutlet weak var historyRecordWidth: NSTextField!
    @IBOutlet weak var historyRecordColumns: NSTextField!
    @IBOutlet weak var historyRecordSpacing: NSTextField!
    @IBOutlet weak var historyRecordPadding: NSTextField!
    @IBOutlet weak var historyRecordFileNameScrollSpeed: NSTextField!
    @IBOutlet weak var historyRecordFileNameScrollWaitTime: NSTextField!
    @IBOutlet weak var screenshotAppOption: NSPopUpButton!
    @IBOutlet weak var fullDiskAuthorizationImage: NSImageView!
    @IBOutlet weak var fullDiskAuthorizationButton: NSButton!
    @IBOutlet weak var resetPreferencesButton: NSButton!
    
    // MARK: Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        resetAllValues()
    }
    
    override func loadView() {
        super.loadView()
        setupKeyboardShortcutsView()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        
        checkFullDiskAuthorizationStatus()
    }
    
    func resetAllValues() {
        setHistoryRecordTextFieldDefaultText()
        setScreenshotAppDefaultValue()
    }
    
    func setHistoryRecordTextFieldDefaultText() {
        historyRecordWidth.stringValue = "\(HistoryRecordWidthGlobal)"
        historyRecordColumns.stringValue = "\(HistoryRecordColumnsGlobal)"
        historyRecordSpacing.stringValue = "\(HistoryRecordSpacingGlobal)"
        historyRecordPadding.stringValue = "\(HistoryRecordPaddingGlobal)"
        historyRecordFileNameScrollSpeed.stringValue = "\(HistoryRecordFileNameScrollSpeedGlobal)"
        historyRecordFileNameScrollWaitTime.stringValue = "\(HistoryRecordFileNameScrollWaitTimeGlobal)"
    }
    
    func setScreenshotAppDefaultValue() {
        screenshotAppOption.selectItem(at: ScreenUtil.getScreenshotApp().rawValue)
    }
    
    func checkFullDiskAuthorizationStatus() {
        let isAuthorized = DiskPermissionManager.shared.checkFullDiskAuthorizationStatus()
        if isAuthorized {
            fullDiskAuthorizationImage.image = NSImage(named: NSImage.statusAvailableName)
            fullDiskAuthorizationButton.title = "Manage Permission".localized // 更直观的按钮文本
        } else {
            fullDiskAuthorizationImage.image = NSImage(named: NSImage.statusPartiallyAvailableName)
            fullDiskAuthorizationButton.title = "Grant Permission".localized // 更直观的按钮文本
        }
    }
    
    @IBAction func didClickHistoryRecordConfigurationResetButton(_ sender: NSButton) {
        
        Defaults.removeObject(forKey: Keys.historyRecordWidth)
        Defaults.removeObject(forKey: Keys.historyRecordColumns)
        Defaults.removeObject(forKey: Keys.historyRecordSpacing)
        Defaults.removeObject(forKey: Keys.historyRecordPadding)
        Defaults.removeObject(forKey: Keys.historyRecordFileNameScrollSpeed)
        Defaults.removeObject(forKey: Keys.historyRecordFileNameScrollWaitTime)
        Defaults.synchronize()
        
        DispatchQueue.main.async {
            self.setHistoryRecordTextFieldDefaultText()
            ConfigNotifier.postNotification(.changeHistoryList)
        }
    }
    
    @IBAction func didClickHistoryRecordConfigurationSaveButton(_ sender: NSButton) {
        Defaults[.historyRecordWidth] = Float(historyRecordWidth.stringValue)
        Defaults[.historyRecordColumns] = Int(historyRecordColumns.stringValue)
        Defaults[.historyRecordSpacing] = Float(historyRecordSpacing.stringValue)
        Defaults[.historyRecordPadding] = Float(historyRecordPadding.stringValue)
        Defaults[.historyRecordFileNameScrollSpeed] = Double(historyRecordFileNameScrollSpeed.stringValue)
        Defaults[.historyRecordFileNameScrollWaitTime] = Float(historyRecordFileNameScrollWaitTime.stringValue)
        
        ConfigNotifier.postNotification(.changeHistoryList)
    }
    
    @IBAction func didChangeScreenshotApp(_ sender: NSPopUpButton) {
        ScreenUtil.setScreenshotApp(ScreenshotApp(rawValue: sender.indexOfSelectedItem) ?? .system)
    }
    
    @IBAction func didClickOpenOutputFormatCustomizationPanelButton(_ sender: NSButton) {
        let outputFormatCustomizationViewController = storyboard!.instantiateController(withIdentifier: "OutputFormatCustomization") as! OutputFormatCustomization
    
        presentAsSheet(outputFormatCustomizationViewController)
    }
    
    @IBAction func didClickfullDiskAuthorizationButton(_ sender: NSButton) {
        let isAuthorized = DiskPermissionManager.shared.checkFullDiskAuthorizationStatus()
        if isAuthorized {
            // 已授权状态下，提供重新授权选项
            let alert = NSAlert()
            alert.messageText = "Disk Access Permission".localized
            alert.informativeText = "Current disk access permission is active. What would you like to do?".localized
            alert.addButton(withTitle: "Re-authorize".localized)
            alert.addButton(withTitle: "Revoke Permission".localized)
            alert.addButton(withTitle: "Cancel".localized)
            
            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                // 重新授权：先清除现有权限，再请求新权限
                DiskPermissionManager.shared.cancelFullDiskPermissions()
                DiskPermissionManager.shared.requestFullDiskPermissions()
            case .alertSecondButtonReturn:
                // 撤销权限：需要二次确认
                let confirmAlert = NSAlert()
                confirmAlert.messageText = "Confirm Revoke Permission".localized
                confirmAlert.informativeText = "Are you sure you want to revoke disk access permission? This may affect file uploading functionality.".localized
                confirmAlert.addButton(withTitle: "Revoke".localized)
                confirmAlert.addButton(withTitle: "Cancel".localized)
                confirmAlert.alertStyle = .warning
                
                if confirmAlert.runModal() == .alertFirstButtonReturn {
                    DiskPermissionManager.shared.cancelFullDiskPermissions()
                }
            default:
                // 取消，不做任何操作
                break
            }
        } else {
            // 未授权状态下，直接请求授权
            DiskPermissionManager.shared.requestFullDiskPermissions()
        }
        
        // 延迟检查状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.checkFullDiskAuthorizationStatus()
        }
    }
    
    @IBAction func resetPreferencesButtonClicked(_ sender: NSButton) {
        let alert = NSAlert()
        
        alert.messageText = "Reset User Preferences?".localized
        alert.informativeText = "⚠️ Note that this will reset all user preferences".localized
        
        // Add button and avoid the focus ring
        let cancelString = "Cancel".localized
        alert.addButton(withTitle: cancelString).refusesFirstResponder = true
        
        let yesString = "Yes".localized
        alert.addButton(withTitle: yesString).refusesFirstResponder = true
        
        let modalResult = alert.runModal()
        
        switch modalResult {
        case .alertFirstButtonReturn:
            print("Cancel Resetting User Preferences")
        case .alertSecondButtonReturn:
            ConfigManager.shared.removeAllUserDefaults()
            ConfigManager.shared.firstSetup()
            ScreenUtil.resetScreenshotApp()
            KeyboardShortcuts.resetAll()
            
            DispatchQueue.main.async {
                ConfigNotifier.postNotification(.changeHistoryList)
                self.resetAllValues()
            }
            
        default:
            print("Cancel Resetting User Preferences")
        }
    }
    
    func setupKeyboardShortcutsView() {
        selectFileShortcut.addSubview(KeyboardShortcuts.RecorderCocoa(for: .selectFileShortcut))
        pasteboardShortcut.addSubview(KeyboardShortcuts.RecorderCocoa(for: .pasteboardShortcut))
        screenshotShortcut.addSubview(KeyboardShortcuts.RecorderCocoa(for: .screenshotShortcut))
    }
}
