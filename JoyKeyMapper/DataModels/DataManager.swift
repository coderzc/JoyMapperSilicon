//
//  DataManager.swift
//  JoyKeyMapper
//
//  Created by magicien on 2019/07/14.
//  Copyright © 2019 DarkHorse. All rights reserved.
//

import CoreData
import JoyConSwift

enum StickType: String {
    case Mouse = "Mouse"
    case MouseWheel = "Mouse Wheel"
    case Key = "Key"
    case None = "None"
}

enum StickDirection: String {
    case Left = "Left"
    case Right = "Right"
    case Up = "Up"
    case Down = "Down"
}

private struct ControllerConfigSnapshot: Codable {
    let version: Int
    let sourceType: String?
    let defaultConfig: KeyConfigSnapshot
    let appConfigs: [AppConfigSnapshot]
}

private struct AppConfigSnapshot: Codable {
    let bundleID: String?
    let displayName: String?
    let icon: Data?
    let config: KeyConfigSnapshot
}

private struct KeyConfigSnapshot: Codable {
    let keyMaps: [KeyMapSnapshot]
    let leftStick: StickConfigSnapshot?
    let rightStick: StickConfigSnapshot?
}

private struct StickConfigSnapshot: Codable {
    let speed: Float
    let type: String?
    let keyMaps: [KeyMapSnapshot]
}

private struct KeyMapSnapshot: Codable {
    let button: String?
    let isEnabled: Bool
    let keyCode: Int16
    let modifiers: Int32
    let mouseButton: Int16
}

class DataManager: NSObject {
    let container: NSPersistentContainer

    var undoManager: UndoManager? {
        return self.container.viewContext.undoManager
    }
    
    var controllers: [ControllerData] {
        let context = self.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ControllerData")
        
        do {
            let result = try context.fetch(request) as! [ControllerData]
            return result
        } catch {
            fatalError("Failed to fetch ControllerData: \(error)")
        }
    }
    
    init(completion: @escaping (DataManager?) -> Void) {
        self.container = NSPersistentContainer(name: "JoyKeyMapper")
        super.init()
        
        self.container.loadPersistentStores { [weak self] (storeDescription, error) in
            if let error = error {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                
                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error)")
            }
            self?.container.viewContext.automaticallyMergesChangesFromParent = true
            self?.container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
            
            completion(self)
        }
    }
    
    func save() -> Bool {
        let context = self.container.viewContext
         
        if !context.commitEditing() {
            NSLog("\(NSStringFromClass(type(of: self))) unable to commit editing before saving")
            return false
        }
        
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // Customize this code block to include application-specific recovery steps.
                let nserror = error as NSError
                NSApplication.shared.presentError(nserror)

                return false
            }
        }
        
        return true
    }
    
    // MARK: - Import/Export data
    
    func createContext(for url: URL) -> NSManagedObjectContext? {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: self.container.managedObjectModel)
        do {
            // TODO: Set options
            try coordinator.addPersistentStore(ofType: NSBinaryStoreType, configurationName: nil, at: url, options: nil)
        } catch {
            let nserror = error as NSError
            NSApplication.shared.presentError(nserror)

            return nil
        }

        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        
        return context
    }
    
    func saveData(object: NSManagedObject, to url: URL) -> Bool {
        guard let context = self.createContext(for: url) else { return false }
        
        context.insert(object)
        if !context.commitEditing() {
            return false
        }
        
        do {
            try context.save()
        } catch {
            // Customize this code block to include application-specific recovery steps.
            let nserror = error as NSError
            NSApplication.shared.presentError(nserror)

            return false
        }
        
        return true
    }
    
    func loadData<T: NSManagedObject>(from url: URL) -> [T]? {
        guard let context = self.createContext(for: url) else { return nil }
        guard let entityName = T.entity().name else { return nil }
        
        let request = NSFetchRequest<T>(entityName: entityName)
        do {
            return try context.fetch(request)
        } catch {
            let nserror = error as NSError
            NSApplication.shared.presentError(nserror)
        }

        return nil
    }

    func exportControllerConfig(_ controller: ControllerData, to url: URL) throws {
        let snapshot = self.makeSnapshot(from: controller)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    func importControllerConfig(from url: URL, into controller: ControllerData) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let snapshot = try decoder.decode(ControllerConfigSnapshot.self, from: data)
        self.apply(snapshot: snapshot, to: controller)
    }

    func copyControllerConfig(from source: ControllerData, to destination: ControllerData) {
        let snapshot = self.makeSnapshot(from: source)
        self.apply(snapshot: snapshot, to: destination)
    }

    // MARK: - ControllerData
    
    func createControllerData(type: JoyCon.ControllerType) -> ControllerData {
        let controller = ControllerData(context: self.container.viewContext)
        controller.appConfigs = []
        controller.defaultConfig = self.createKeyConfig(type: type)
        
        return controller
    }
    
    func getControllerData(controller: JoyConSwift.Controller) -> ControllerData {
        let serialID = controller.serialID
        let context = self.container.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "ControllerData")
        request.predicate = NSPredicate(format: "serialID == %@", serialID)

        do {
            let result = try context.fetch(request) as! [ControllerData]
            if result.count > 0 {
                return result[0]
            }
        } catch {
            fatalError("Failed to fetch ControllerData: \(error)")
        }

        let controller = self.createControllerData(type: controller.type)
        controller.serialID = serialID
        
        return controller
    }
    
    // MARK: - AppConfig
    
    func createAppConfig(type: JoyCon.ControllerType) -> AppConfig {
        let appConfig = AppConfig(context: self.container.viewContext)
        appConfig.app = self.createAppData()
        appConfig.config = self.createKeyConfig(type: type)

        return appConfig
    }

    // MARK: - AppData

    func createAppData() -> AppData {
        let appData = AppData(context: self.container.viewContext)

        return appData
    }

    // MARK: - KeyConfig

    func createKeyConfig(type: JoyCon.ControllerType) -> KeyConfig {
        let keyConfig = KeyConfig(context: self.container.viewContext)
        
        if type == .JoyConL || type == .ProController {
            keyConfig.leftStick = self.createStickConfig()
        }
        if type == .JoyConR || type == .ProController {
            keyConfig.rightStick = self.createStickConfig()
        }
        
        keyConfig.keyMaps = []
        
        return keyConfig
    }

    // MARK: - KeyMap

    func createKeyMap() -> KeyMap {
        let keyMap = KeyMap(context: self.container.viewContext)
        
        return keyMap
    }
    
    // MARK: - StickConfig
    
    func createStickConfig() -> StickConfig {
        let stickConfig = StickConfig(context: self.container.viewContext)

        stickConfig.speed = 10.0
        stickConfig.type = StickType.None.rawValue

        let left = self.createKeyMap()
        left.button = StickDirection.Left.rawValue
        stickConfig.addToKeyMaps(left)

        let right = self.createKeyMap()
        right.button = StickDirection.Right.rawValue
        stickConfig.addToKeyMaps(right)

        let up = self.createKeyMap()
        up.button = StickDirection.Up.rawValue
        stickConfig.addToKeyMaps(up)

        let down = self.createKeyMap()
        down.button = StickDirection.Down.rawValue
        stickConfig.addToKeyMaps(down)
        
        return stickConfig
    }
    
    // MARK: - Common
    
    func delete(_ object: NSManagedObject) {
        self.container.viewContext.delete(object)
    }

    private func makeSnapshot(from controller: ControllerData) -> ControllerConfigSnapshot {
        let appConfigs = (controller.appConfigs?.array as? [AppConfig] ?? []).map {
            self.makeSnapshot(from: $0)
        }

        return ControllerConfigSnapshot(
            version: 1,
            sourceType: controller.type,
            defaultConfig: self.makeSnapshot(from: controller.defaultConfig),
            appConfigs: appConfigs
        )
    }

    private func makeSnapshot(from appConfig: AppConfig) -> AppConfigSnapshot {
        return AppConfigSnapshot(
            bundleID: appConfig.app?.bundleID,
            displayName: appConfig.app?.displayName,
            icon: appConfig.app?.icon,
            config: self.makeSnapshot(from: appConfig.config)
        )
    }

    private func makeSnapshot(from keyConfig: KeyConfig?) -> KeyConfigSnapshot {
        return KeyConfigSnapshot(
            keyMaps: self.makeSnapshots(from: keyConfig?.keyMaps),
            leftStick: self.makeSnapshot(from: keyConfig?.leftStick),
            rightStick: self.makeSnapshot(from: keyConfig?.rightStick)
        )
    }

    private func makeSnapshot(from stickConfig: StickConfig?) -> StickConfigSnapshot? {
        guard let stickConfig = stickConfig else { return nil }

        return StickConfigSnapshot(
            speed: stickConfig.speed,
            type: stickConfig.type,
            keyMaps: self.makeSnapshots(from: stickConfig.keyMaps)
        )
    }

    private func makeSnapshots(from keyMaps: NSSet?) -> [KeyMapSnapshot] {
        return (keyMaps?.allObjects as? [KeyMap] ?? [])
            .sorted { ($0.button ?? "") < ($1.button ?? "") }
            .map { keyMap in
                KeyMapSnapshot(
                    button: keyMap.button,
                    isEnabled: keyMap.isEnabled,
                    keyCode: keyMap.keyCode,
                    modifiers: keyMap.modifiers,
                    mouseButton: keyMap.mouseButton
                )
            }
    }

    private func apply(snapshot: ControllerConfigSnapshot, to controller: ControllerData) {
        if let defaultConfig = controller.defaultConfig {
            controller.defaultConfig = nil
            self.deleteKeyConfig(defaultConfig)
        }

        let existingApps = controller.appConfigs?.array as? [AppConfig] ?? []
        existingApps.forEach { appConfig in
            controller.removeFromAppConfigs(appConfig)
            self.deleteAppConfig(appConfig)
        }

        controller.defaultConfig = self.createKeyConfig(from: snapshot.defaultConfig)
        snapshot.appConfigs
            .map { self.createAppConfig(from: $0) }
            .forEach { controller.addToAppConfigs($0) }
    }

    private func createAppConfig(from snapshot: AppConfigSnapshot) -> AppConfig {
        let appConfig = AppConfig(context: self.container.viewContext)
        let appData = AppData(context: self.container.viewContext)

        appData.bundleID = snapshot.bundleID
        appData.displayName = snapshot.displayName
        appData.icon = snapshot.icon

        appConfig.app = appData
        appConfig.config = self.createKeyConfig(from: snapshot.config)

        return appConfig
    }

    private func createKeyConfig(from snapshot: KeyConfigSnapshot) -> KeyConfig {
        let keyConfig = KeyConfig(context: self.container.viewContext)

        snapshot.keyMaps
            .map { self.createKeyMap(from: $0) }
            .forEach { keyConfig.addToKeyMaps($0) }

        if let leftStick = snapshot.leftStick {
            keyConfig.leftStick = self.createStickConfig(from: leftStick)
        }
        if let rightStick = snapshot.rightStick {
            keyConfig.rightStick = self.createStickConfig(from: rightStick)
        }

        return keyConfig
    }

    private func createStickConfig(from snapshot: StickConfigSnapshot) -> StickConfig {
        let stickConfig = StickConfig(context: self.container.viewContext)
        stickConfig.speed = snapshot.speed
        stickConfig.type = snapshot.type

        snapshot.keyMaps
            .map { self.createKeyMap(from: $0) }
            .forEach { stickConfig.addToKeyMaps($0) }

        return stickConfig
    }

    private func createKeyMap(from snapshot: KeyMapSnapshot) -> KeyMap {
        let keyMap = KeyMap(context: self.container.viewContext)
        keyMap.button = snapshot.button
        keyMap.isEnabled = snapshot.isEnabled
        keyMap.keyCode = snapshot.keyCode
        keyMap.modifiers = snapshot.modifiers
        keyMap.mouseButton = snapshot.mouseButton

        return keyMap
    }

    private func deleteAppConfig(_ appConfig: AppConfig) {
        if let config = appConfig.config {
            appConfig.config = nil
            self.deleteKeyConfig(config)
        }
        if let app = appConfig.app {
            appConfig.app = nil
            self.delete(app)
        }
        self.delete(appConfig)
    }

    private func deleteKeyConfig(_ keyConfig: KeyConfig) {
        let keyMaps = keyConfig.keyMaps?.allObjects as? [KeyMap] ?? []
        keyMaps.forEach { keyConfig.removeFromKeyMaps($0) }
        keyMaps.forEach { self.delete($0) }

        if let leftStick = keyConfig.leftStick {
            keyConfig.leftStick = nil
            self.deleteStickConfig(leftStick)
        }
        if let rightStick = keyConfig.rightStick {
            keyConfig.rightStick = nil
            self.deleteStickConfig(rightStick)
        }

        self.delete(keyConfig)
    }

    private func deleteStickConfig(_ stickConfig: StickConfig) {
        let keyMaps = stickConfig.keyMaps?.allObjects as? [KeyMap] ?? []
        keyMaps.forEach { stickConfig.removeFromKeyMaps($0) }
        keyMaps.forEach { self.delete($0) }
        self.delete(stickConfig)
    }
}
