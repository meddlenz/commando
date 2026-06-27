//
//  MenuBarIconSettings.swift
//  Commando
//

import AppKit
import Foundation

enum MenuBarIconSettings {

    enum Option: String, CaseIterable {
        case badgeColoured
        case badge
        case dogtags
        case helmet

        var title: String {
            switch self {
            case .badge:
                return "Badge"
            case .badgeColoured:
                return "Badge (Coloured)"
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
            case .badgeColoured:
                return "MenuBarIconBadgeColoured"
            case .dogtags:
                return "MenuBarIconDogtags"
            case .helmet:
                return "MenuBarIconHelmet"
            }
        }

        var usesTemplateRendering: Bool {
            switch self {
            case .badgeColoured:
                return false
            default:
                return true
            }
        }
    }

    private static let selectedIconKey = "menuBarIcon"

    static var selectedOption: Option {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: selectedIconKey),
                  let option = Option(rawValue: rawValue) else {
                return .badgeColoured
            }
            return option
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: selectedIconKey)
            NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        }
    }

    static func previewImage(for option: Option) -> NSImage {
        let fallback = NSImage(size: NSSize(width: 18, height: 18))
        guard let image = NSImage(named: NSImage.Name(option.assetName)),
              image.isValid,
              image.size.width > 0,
              image.size.height > 0,
              let copy = image.copy() as? NSImage else {
            return fallback
        }

        copy.size = NSSize(width: 18, height: 18)
        copy.isTemplate = option.usesTemplateRendering
        return copy
    }
}
