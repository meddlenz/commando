//
//  AppInfo.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import Foundation

enum AppInfo {
    static let companyURL = URL(string: "https://manticore.nz")!
    static let purchaseURL = URL(string: "https://manticore.nz/commando/purchase")!
    static let licenseCheckURL = LicenseEndpoints.checkURL
    static let licenseReportURL = LicenseEndpoints.reportURL
    static let privacyURL = URL(string: "https://manticore.nz/commando/privacy")!
    static let termsURL = URL(string: "https://manticore.nz/commando/terms")!
    static let newsURL = URL(string: "https://manticore.nz/news")!

    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Commando"
    }

    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var version: String {
        let short = shortVersion
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    static var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
    }
}
