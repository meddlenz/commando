//
//  MenuBarIconSettings.swift
//  Commando
//

import Foundation

enum MenuBarIconSettings {

    enum Option: String, CaseIterable {
        case badge
        case dogtags
        case helmet

        var title: String {
            switch self {
            case .badge:
                return "Badge"
            case .dogtags:
                return "Dog Tags"
            case .helmet:
                return "Helmet"
            }
        }

        var assetName: String {
            switch self {
            case .badge:
                return "MenuBarIconBadge"
            case .dogtags:
                return "MenuBarIconDogtags"
            case .helmet:
                return "MenuBarIconHelmet"
            }
        }
    }

    private static let selectedIconKey = "menuBarIcon"

    static var selectedOption: Option {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: selectedIconKey),
                  let option = Option(rawValue: rawValue) else {
                return .badge
            }
            return option
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: selectedIconKey)
            NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        }
    }
}
