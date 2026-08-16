//
//  AppDistribution.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import Foundation

enum AppDistribution {
    private static let minimumReceiptBytes: Int64 = 512

    #if APP_STORE
    static let isAppStoreBuild = true
    #else
    static let isAppStoreBuild = false
    #endif

    static var usesDirectLicensing: Bool {
        !isAppStoreBuild
    }

    static var isMacAppStore: Bool {
        if isAppStoreBuild {
            return true
        }

        guard let receiptURL = Bundle.main.appStoreReceiptURL else {
            return false
        }

        let path = receiptURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            return false
        }

        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: path),
            let size = attributes[.size] as? NSNumber
        else {
            return false
        }

        return size.int64Value >= minimumReceiptBytes
    }
}
