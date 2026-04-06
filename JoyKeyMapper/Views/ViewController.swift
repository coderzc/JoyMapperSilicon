//
//  ViewController.swift
//  JoyKeyMapper
//
//  Created by magicien on 2019/07/14.
//  Copyright © 2019 DarkHorse. All rights reserved.
//

import AppKit
import InputMethodKit
import JoyConSwift

class ViewController: NSViewController {
    
    @IBOutlet weak var controllerCollectionView: NSCollectionView!
    @IBOutlet weak var appTableView: NSTableView!
    @IBOutlet weak var appAddRemoveButton: NSSegmentedControl!
    @IBOutlet weak var configTableView: NSOutlineView!
    
    var appDelegate: AppDelegate? {
        return NSApplication.shared.delegate as? AppDelegate
    }
    var selectedController: GameController? {
        didSet {
            self.appTableView.reloadData()
            self.configTableView.reloadData()
            self.updateAppAddRemoveButtonState()
        }
    }
    var selectedControllerData: ControllerData? {
        return self.selectedController?.data
    }
    var selectedAppConfig: AppConfig? {
        guard let data = self.selectedControllerData else {
            return nil
        }
        let row = self.appTableView.selectedRow
        if row < 1 {
            return nil
        }
        return data.appConfigs?[row - 1] as? AppConfig
    }
    var selectedKeyConfig: KeyConfig? {
        if self.appTableView.selectedRow < 0 {
            return nil
        }
        return self.selectedAppConfig?.config ?? self.selectedControllerData?.defaultConfig
    }
    var keyDownHandler: Any?

    override func viewDidLoad() {
        super.viewDidLoad()

        if self.controllerCollectionView == nil { return }
        
        self.controllerCollectionView.delegate = self
        self.controllerCollectionView.dataSource = self
        
        self.appTableView.delegate = self
        self.appTableView.dataSource = self
        
        self.configTableView.delegate = self
        self.configTableView.dataSource = self
        
        self.updateAppAddRemoveButtonState()

        NotificationCenter.default.addObserver(self, selector: #selector(controllerAdded), name: .controllerAdded, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(controllerRemoved), name: .controllerRemoved, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(controllerConnected), name: .controllerConnected, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(controllerDisconnected), name: .controllerDisconnected, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(controllerIconChanged), name: .controllerIconChanged, object: nil)
    }
    
    override func viewDidDisappear() {

    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    // MARK: - Apps
    
    @IBAction func clickAppSegmentButton(_ sender: NSSegmentedControl) {
        let selectedSegment = sender.selectedSegment
        
        if selectedSegment == 0 {
            self.addApp()
        } else if selectedSegment == 1 {
            self.removeApp()
        }
    }
    
    func updateAppAddRemoveButtonState() {
        if self.selectedController == nil {
            self.appAddRemoveButton.setEnabled(false, forSegment: 0)
            self.appAddRemoveButton.setEnabled(false, forSegment: 1)
        } else if self.appTableView.selectedRow < 1 {
            self.appAddRemoveButton.setEnabled(true, forSegment: 0)
            self.appAddRemoveButton.setEnabled(false, forSegment: 1)
        } else {
            self.appAddRemoveButton.setEnabled(true, forSegment: 0)
            self.appAddRemoveButton.setEnabled(true, forSegment: 1)
        }        
    }
    
    func addApp() {
        guard let controller = self.selectedController else { return }
        
        let panel = NSOpenPanel()
        panel.message = NSLocalizedString("Choose an app to add", comment: "Choosing app message")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.canChooseFiles = true
        panel.allowedFileTypes = ["app"]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { [weak self] response in
            if response == .OK {
                guard let url = panel.url else { return }
                controller.addApp(url: url)
                self?.appTableView.reloadData()
            }
        }
    }
    
    func removeApp() {
        guard let controller = self.selectedController else { return }
        guard let appConfig = self.selectedAppConfig else { return }
        let appName = self.convertAppName(appConfig.app?.displayName)
        
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String.localizedStringWithFormat(NSLocalizedString("Do you really want to delete the settings for %@?", comment: "Do you really want to delete the settings for <app>?"), appName)
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK"))
        let result = alert.runModal()
        
        if result == .alertSecondButtonReturn {
            controller.removeApp(appConfig)
            self.appTableView.reloadData()
            self.configTableView.reloadData()
        }
    }
    
    // MARK: - Controllers

    private func syncControllerSelection() {
        guard let collectionView = self.controllerCollectionView else { return }
        let controllers = self.appDelegate?.controllers ?? []

        if controllers.isEmpty {
            self.selectedController = nil
            collectionView.deselectAll(nil)
            return
        }

        let selectedIndex: Int?
        if let selectedController = self.selectedController {
            selectedIndex = controllers.firstIndex(where: { $0 === selectedController })
        } else {
            selectedIndex = 0
        }

        guard let index = selectedIndex, controllers.indices.contains(index) else {
            self.selectedController = nil
            collectionView.deselectAll(nil)
            return
        }

        let indexPath = IndexPath(item: index, section: 0)
        collectionView.selectItems(at: [indexPath], scrollPosition: [])
        self.selectedController = controllers[index]
    }
    
    @objc func controllerAdded() {
        DispatchQueue.main.async { [weak self] in
            self?.controllerCollectionView.reloadData()
            self?.syncControllerSelection()
        }
    }
    
    @objc func controllerConnected() {
        DispatchQueue.main.async { [weak self] in
            self?.controllerCollectionView.reloadData()
            self?.syncControllerSelection()
        }
    }
    
    @objc func controllerDisconnected() {
        DispatchQueue.main.async { [weak self] in
            self?.controllerCollectionView.reloadData()
            self?.syncControllerSelection()
        }
    }
    
    @objc func controllerRemoved(_ notification: NSNotification) {
        guard let gameController = notification.object as? GameController else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let _self = self else { return }
            let numItems = _self.controllerCollectionView.numberOfItems(inSection: 0)
            for i in 0..<numItems {
                if let item = self?.controllerCollectionView.item(at: i) as? ControllerViewItem {
                    if item.controller === gameController {
                        self?.controllerCollectionView.deselectAll(nil)
                    }
                }
            }
            self?.controllerCollectionView.reloadData()
            self?.syncControllerSelection()
        }
    }
    
    @objc func controllerIconChanged(_ notification: NSNotification) {
        DispatchQueue.main.async { [weak self] in
            self?.controllerCollectionView.reloadData()
            self?.syncControllerSelection()
        }
    }

    private func refreshControllerConfig(_ controller: GameController) {
        if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            controller.switchApp(bundleID: bundleID)
        } else {
            controller.updateKeyMap()
        }

        if self.selectedController === controller {
            self.appTableView.reloadData()
            self.configTableView.reloadData()
        }
    }

    private func controllerDisplayName(_ controller: GameController) -> String {
        let typeName = NSLocalizedString(controller.type.rawValue, comment: "Controller type")
        guard let serialID = controller.data.serialID, !serialID.isEmpty else {
            return typeName
        }

        let suffixLength = min(4, serialID.count)
        let suffix = String(serialID.suffix(suffixLength))
        return "\(typeName) (\(suffix))"
    }

    private func showOperationError(_ error: Error) {
        NSApplication.shared.presentError(error as NSError)
    }

    func copyKeyMappings(from sourceController: GameController) {
        guard let dataManager = self.appDelegate?.dataManager else { return }
        let targetControllers = (self.appDelegate?.controllers ?? []).filter { $0 !== sourceController }

        guard !targetControllers.isEmpty else {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("No other controllers available", comment: "No copy target")
            alert.informativeText = NSLocalizedString("Connect or add another controller first, then try copying the settings again.", comment: "No copy target info")
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK"))
            alert.runModal()
            return
        }

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26), pullsDown: false)
        targetControllers.forEach { controller in
            popup.addItem(withTitle: self.controllerDisplayName(controller))
            popup.lastItem?.representedObject = controller
        }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Copy controller settings", comment: "Copy controller settings")
        alert.informativeText = NSLocalizedString("The target controller's current mappings will be replaced.", comment: "Copy controller settings info")
        alert.accessoryView = popup
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))
        alert.addButton(withTitle: NSLocalizedString("Copy", comment: "Copy"))

        guard alert.runModal() == .alertSecondButtonReturn else { return }
        guard let targetController = popup.selectedItem?.representedObject as? GameController else { return }

        dataManager.copyControllerConfig(from: sourceController.data, to: targetController.data)
        _ = dataManager.save()

        self.refreshControllerConfig(sourceController)
        self.refreshControllerConfig(targetController)
    }
    
    // MARK: - Import
    
    @IBAction func importKeyMappings(_ sender: NSButton) {
        guard let controller = self.selectedController else { return }
        self.importKeyMappings(for: controller)
    }

    func importKeyMappings(for controller: GameController) {
        guard let dataManager = self.appDelegate?.dataManager else { return }

        let panel = NSOpenPanel()
        panel.message = NSLocalizedString("Choose a key mapping file", comment: "Choose a key mapping file")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedFileTypes = ["jmpmap", "jkmap", "json"]
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            guard let url = panel.url else { return }

            do {
                try dataManager.importControllerConfig(from: url, into: controller.data)
                _ = dataManager.save()
                self?.refreshControllerConfig(controller)
            } catch {
                self?.showOperationError(error)
            }
        }
    }
    
    // MARK: - Export
    
    @IBAction func exportKeyMappngs(_ sender: NSButton) {
        guard let controller = self.selectedController else { return }
        self.exportKeyMappings(for: controller)
    }

    func exportKeyMappings(for controller: GameController) {
        guard let dataManager = self.appDelegate?.dataManager else { return }

        let savePanel = NSSavePanel()
        savePanel.message = NSLocalizedString("Save key mapping data", comment: "Save key mapping data")
        savePanel.allowedFileTypes = ["jmpmap"]
        savePanel.nameFieldStringValue = "\(self.controllerDisplayName(controller)).jmpmap"

        savePanel.begin { [weak self] response in
            guard response == .OK else { return }
            guard let url = savePanel.url else { return }

            do {
                try dataManager.exportControllerConfig(controller.data, to: url)
            } catch {
                self?.showOperationError(error)
            }
        }
    }
    
    // MARK: - Options
    
    @IBAction func didPushOptions(_ sender: NSButton) {
        guard let controller = self.storyboard?.instantiateController(withIdentifier: "AppSettingsViewController") as? AppSettingsViewController else { return }
        
        self.presentAsSheet(controller)
    }
}
