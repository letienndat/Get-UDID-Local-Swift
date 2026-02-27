//
//  InfoDevice.swift
//  Get UDID Local Swift
//
//  Created by Le Tien Dat on 2/27/26.
//

import Foundation

struct InfoDevice {
    var udid: String
    var imei: String
    var product: String
    var version: String
    var serial: String

    var description: String {
        """
        UDID: \(udid)
        IMEI: \(imei)
        PRODUCT: \(product)
        VERSION: \(version)
        SERIAL: \(serial)
        """
    }
}
