//
//  ObjC+Exception.swift
//  BatteryData
//
//  Created by Dmytro Izyuk on 17.12.2025.
//

import Foundation

enum ObjC {
    static func catchException<T>(_ block: @escaping () -> T?) -> T? {
        let anyResult = _ObjCExceptionCatcher.catch {
            block() as Any
        }
        return anyResult as? T
    }
}
