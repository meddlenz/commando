//
//  AppLock.swift
//  Commando
//  Jordan Trbuhovic 2026
//

import Foundation

enum AppLock {
    enum Reason: Equatable {
        case updateRequired(minimumVersion: String, updateURL: URL?)
    }

    static var reasonOverride: Reason?

    private(set) static var reason: Reason?

    static var isLocked: Bool {
        reasonOverride != nil || reason != nil
    }

    static var updateRequiredMessage: String {
        switch activeReason {
        case .updateRequired(let minimumVersion, _):
            return "This version of Commando is no longer supported. Please download and install the latest update to continue."
        case .none:
            return ""
        }
    }

    static var updateURL: URL? {
        switch activeReason {
        case .updateRequired(_, let url):
            return url
        case .none:
            return nil
        }
    }

    static func lockForUpdate(minimumVersion: String, updateURL: URL?) {
        reason = .updateRequired(minimumVersion: minimumVersion, updateURL: updateURL)
    }

    static func clear() {
        reason = nil
    }

    private static var activeReason: Reason? {
        reasonOverride ?? reason
    }
}
