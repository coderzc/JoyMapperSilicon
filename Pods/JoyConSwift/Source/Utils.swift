//
//  Utils.swift
//  JoyConSwift
//
//  Created by magicien on 2019/06/16.
//  Copyright © 2019 DarkHorse. All rights reserved.
//

import Foundation

func ReadInt16(from ptr: UnsafePointer<UInt8>) -> Int16 {
    var value: Int16 = 0
    memcpy(&value, ptr, MemoryLayout<Int16>.size)
    return value
}

func ReadUInt16(from ptr: UnsafePointer<UInt8>) -> UInt16 {
    var value: UInt16 = 0
    memcpy(&value, ptr, MemoryLayout<UInt16>.size)
    return value
}

func ReadInt32(from ptr: UnsafePointer<UInt8>) -> Int32 {
    var value: Int32 = 0
    memcpy(&value, ptr, MemoryLayout<Int32>.size)
    return value
}

func ReadUInt32(from ptr: UnsafePointer<UInt8>) -> UInt32 {
    var value: UInt32 = 0
    memcpy(&value, ptr, MemoryLayout<UInt32>.size)
    return value
}
