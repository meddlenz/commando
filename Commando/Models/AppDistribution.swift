//
//  AppDistribution.swift
//  Commando
//

import Foundation

enum AppDistribution {
    static var isMacAppStore: Bool {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else { return false }
        return FileManager.default.fileExists(atPath: receiptURL.path)
    }
}
