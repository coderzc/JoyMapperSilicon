//
//  JoyConManager.swift
//  JoyConSwift
//
//  Created by magicien on 2019/06/16.
//  Copyright © 2019 DarkHorse. All rights reserved.
//

import Foundation
import IOKit
import IOKit.hid

let controllerTypeOutputReport: [UInt8] = [
    JoyCon.OutputType.subcommand.rawValue, // type
    0x0f, // packet counter
    0x00, 0x01, 0x00, 0x40, 0x00, 0x01, 0x00, 0x40, // rumble data
    Subcommand.CommandType.getSPIFlash.rawValue, // subcommand type
    0x12, 0x60, 0x00, 0x00, // address
    0x01, // data length
]

/// The manager class to handle controller connection/disconnection events
public class JoyConManager {
    private static let matchTimeout: TimeInterval = 3.0

    static let vendorID: Int32 = 0x057E
    static let joyConLID: Int32 = 0x2006 // Joy-Con (L)
    static let joyConRID: Int32 = 0x2007 // Joy-Con (R), Famicom Controller 1&2
    static let proConID: Int32 = 0x2009 // Pro Controller
    static let snesConID: Int32 = 0x2017 // SNES Controller

    static let joyConLType: UInt8 = 0x01
    static let joyConRType: UInt8 = 0x02
    static let proConType: UInt8 = 0x03
    static let famicomCon1Type: UInt8 = 0x07
    static let famicomCon2Type: UInt8 = 0x08
    static let snesConType: UInt8 = 0x0B

    private let manager: IOHIDManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var matchingControllers: [IOHIDDevice: Date] = [:]
    private var controllers: [IOHIDDevice: Controller] = [:]
    private var runLoop: RunLoop? = nil

    /// Handler for a controller connection event
    public var connectHandler: ((_ controller: Controller) -> Void)? = nil
    /// Handler for a controller disconnection event
    public var disconnectHandler: ((_ controller: Controller) -> Void)? = nil

    /// Initialize a manager
    public init() {}

    private func log(_ message: String) {
        NSLog("[JoyConManager] %@", message)
    }

    private func deviceDescription(_ device: IOHIDDevice) -> String {
        let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? -1
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? -1
        let serialID = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String ?? ""
        return String(format: "vendor=0x%04X product=0x%04X serial=%@", vendorID, productID, serialID)
    }

    private func clearMatch(for device: IOHIDDevice, reason: String) {
        guard self.matchingControllers.removeValue(forKey: device) != nil else { return }
        self.log("Cleared pending match (\(reason)) for \(self.deviceDescription(device))")
    }

    private func scheduleMatchTimeout(for device: IOHIDDevice) {
        let startedAt = Date()
        self.matchingControllers[device] = startedAt

        DispatchQueue.global().asyncAfter(deadline: .now() + JoyConManager.matchTimeout) { [weak self] in
            guard let self = self else { return }
            guard let currentStartedAt = self.matchingControllers[device] else { return }
            guard currentStartedAt == startedAt else { return }
            self.clearMatch(for: device, reason: "timeout")
            self.log("Retrying timed-out match for \(self.deviceDescription(device))")
            self.handleMatch(result: kIOReturnSuccess, sender: nil, device: device)
        }
    }

    let handleMatchCallback: IOHIDDeviceCallback = { (context, result, sender, device) in
        let manager: JoyConManager = unsafeBitCast(context, to: JoyConManager.self)
        manager.handleMatch(result: result, sender: sender, device: device)
    }

    let handleInputCallback: IOHIDValueCallback = { (context, result, sender, value) in
        let manager: JoyConManager = unsafeBitCast(context, to: JoyConManager.self)
        manager.handleInput(result: result, sender: sender, value: value)
    }

    let handleRemoveCallback: IOHIDDeviceCallback = { (context, result, sender, device) in
        let manager: JoyConManager = unsafeBitCast(context, to: JoyConManager.self)
        manager.handleRemove(result: result, sender: sender, device: device)
    }

    func handleMatch(result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
        if self.matchingControllers[device] != nil {
            self.log("Ignoring in-flight match for \(self.deviceDescription(device))")
            return
        }

        if (self.controllers.contains { (dev, ctrl) in dev == device }) {
            self.log("Ignoring duplicate match for \(self.deviceDescription(device))")
            return
        }

        self.log("Matched HID device \(self.deviceDescription(device))")
        self.scheduleMatchTimeout(for: device)
        let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(0x01), controllerTypeOutputReport, controllerTypeOutputReport.count);
        if (result != kIOReturnSuccess) {
            self.clearMatch(for: device, reason: "set-report-error")
            self.log(String(format: "Failed to query controller type for %@, IOHIDDeviceSetReport error: %d", self.deviceDescription(device), result))
            return
        }
        self.log("Requested controller type for \(self.deviceDescription(device))")
    }

    func handleControllerType(device: IOHIDDevice, result: IOReturn, value: IOHIDValue) {
        guard self.matchingControllers[device] != nil else { return }
        let ptr = IOHIDValueGetBytePtr(value)
        let address = ReadUInt32(from: ptr+14)
        let length = Int((ptr+18).pointee)
        guard address == 0x6012, length == 1 else { return }
        let buffer = UnsafeBufferPointer(start: ptr+19, count: length)
        let data = Array(buffer)

        var _controller: Controller? = nil
        switch data[0] {
        case JoyConManager.joyConLType:
            _controller = JoyConL(device: device)
            break
        case JoyConManager.joyConRType:
            _controller = JoyConR(device: device)
            break
        case JoyConManager.proConType:
            _controller = ProController(device: device)
            break
        case JoyConManager.famicomCon1Type:
            _controller = FamicomController1(device: device)
            break
        case JoyConManager.famicomCon2Type:
            _controller = FamicomController2(device: device)
            break
        case JoyConManager.snesConType:
            _controller = SNESController(device: device)
            break
        default:
            break
        }

        guard let controller = _controller else { return }
        self.log("Resolved controller type 0x\(String(data[0], radix: 16)) for \(self.deviceDescription(device))")
        self.clearMatch(for: device, reason: "resolved")
        self.controllers[device] = controller
        controller.isConnected = true
        controller.readInitializeData { [weak self] in
            self?.log("Initialized controller \(controller.serialID)")
            self?.connectHandler?(controller)
        }
    }

    func handleInput(result: IOReturn, sender: UnsafeMutableRawPointer?, value: IOHIDValue) {
        guard let sender = sender else { return }
        let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue();

        if self.matchingControllers[device] != nil {
            self.handleControllerType(device: device, result: result, value: value)
            return
        }

        guard let controller = self.controllers[device] else { return }
        if (result == kIOReturnSuccess) {
            controller.handleInput(value: value)
        } else {
            controller.handleError(result: result, value: value)
        }
    }

    func handleRemove(result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
        self.clearMatch(for: device, reason: "removed")
        guard let controller = self.controllers[device] else { return }
        self.log("Controller removed \(self.deviceDescription(device))")
        controller.isConnected = false

        self.controllers.removeValue(forKey: device)
        controller.cleanUp()

        self.disconnectHandler?(controller)
    }

    private func registerDeviceCallback() {
        IOHIDManagerRegisterDeviceMatchingCallback(self.manager, self.handleMatchCallback, unsafeBitCast(self, to: UnsafeMutableRawPointer.self))
        IOHIDManagerRegisterDeviceRemovalCallback(self.manager, self.handleRemoveCallback, unsafeBitCast(self, to: UnsafeMutableRawPointer.self))
        IOHIDManagerRegisterInputValueCallback(self.manager, self.handleInputCallback, unsafeBitCast(self, to: UnsafeMutableRawPointer.self))
    }

    private func unregisterDeviceCallback() {
        IOHIDManagerRegisterDeviceMatchingCallback(self.manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(self.manager, nil, nil)
        IOHIDManagerRegisterInputValueCallback(self.manager, nil, nil)
    }

    private func processConnectedDevices() {
        guard let devices = IOHIDManagerCopyDevices(self.manager) as? Set<IOHIDDevice> else {
            self.log("No HID devices found during rescan")
            return
        }

        let supportedProductIDs: Set<Int32> = [
            JoyConManager.joyConLID,
            JoyConManager.joyConRID,
            JoyConManager.proConID,
            JoyConManager.snesConID,
        ]

        let matchedDevices = devices.filter { device in
            let vendorID = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? NSNumber)?.int32Value
            let productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.int32Value
            return vendorID == JoyConManager.vendorID && productID.map(supportedProductIDs.contains) == true
        }

        if matchedDevices.isEmpty {
            self.log("No supported connected controllers found during rescan")
            return
        }

        self.log("Found \(matchedDevices.count) connected controller(s) during rescan")
        matchedDevices.forEach { device in
            self.handleMatch(result: kIOReturnSuccess, sender: nil, device: device)
        }
    }

    public func rescanConnectedDevices() {
        self.processConnectedDevices()
    }

    private func cleanUp() {
        self.matchingControllers.removeAll()
        self.controllers.values.forEach { controller in
            controller.cleanUp()
        }
        self.controllers.removeAll()
    }

    /// Start waiting for controller connection/disconnection events in the current thread.
    /// If you don't want to stop the current thread, use `runAsync()` instead.
    /// - Returns: kIOReturnSuccess if succeeded. IOReturn error value if failed.
    public func run() -> IOReturn {
        let joyConLCriteria: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad,
            kIOHIDVendorIDKey: JoyConManager.vendorID,
            kIOHIDProductIDKey: JoyConManager.joyConLID,
        ]
        let joyConRCriteria: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad,
            kIOHIDVendorIDKey: JoyConManager.vendorID,
            kIOHIDProductIDKey: JoyConManager.joyConRID,
        ]
        let proConCriteria: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad,
            kIOHIDVendorIDKey: JoyConManager.vendorID,
            kIOHIDProductIDKey: JoyConManager.proConID,
        ]
        let snesConCriteria: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad,
            kIOHIDVendorIDKey: JoyConManager.vendorID,
            kIOHIDProductIDKey: JoyConManager.snesConID,
        ]
        let criteria = [joyConLCriteria, joyConRCriteria, proConCriteria, snesConCriteria]

        let runLoop = RunLoop.current

        IOHIDManagerSetDeviceMatchingMultiple(self.manager, criteria as CFArray)
        IOHIDManagerScheduleWithRunLoop(self.manager, runLoop.getCFRunLoop(), CFRunLoopMode.defaultMode.rawValue)
        let ret = IOHIDManagerOpen(self.manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        if (ret != kIOReturnSuccess) {
            self.log("Failed to open HID manager: \(ret)")
            return ret
        }
        self.log("HID manager started")

        self.registerDeviceCallback()
        self.processConnectedDevices()

        self.runLoop = runLoop
        self.runLoop?.run()

        IOHIDManagerClose(self.manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        IOHIDManagerUnscheduleFromRunLoop(self.manager, runLoop.getCFRunLoop(), CFRunLoopMode.defaultMode.rawValue)
        self.log("HID manager stopped")

        return kIOReturnSuccess
    }

    /// Start waiting for controller connection/disconnection events in a new thread.
    /// If you want to wait for the events synchronously, use `run()` instead.
    /// - Returns: kIOReturnSuccess if succeeded. IOReturn error value if failed.
    public func runAsync() -> IOReturn {
        DispatchQueue.global().async { [weak self] in
            _ = self?.run()
        }
        return kIOReturnSuccess
    }

    /// Stop waiting for controller connection/disconnection events
    public func stop() {
        if let currentLoop = self.runLoop?.getCFRunLoop() {
            CFRunLoopStop(currentLoop)
        }

        self.unregisterDeviceCallback()
        self.cleanUp()
    }
}
