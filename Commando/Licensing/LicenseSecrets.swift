//
//  LicenseSecrets.swift
//  Commando
//  Jordan Trbuhovic 2026


import Foundation

enum LicenseSecrets {
    static var secret: String {
        String(bytes: unfolded, encoding: .utf8) ?? ""
    }

    private static var unfolded: [UInt8] {
        let a: [UInt8] = [0x5A, 0x3C, 0x91, 0xE7, 0x2B, 0x44, 0xD8, 0x0F]
        let b: [UInt8] = [0x66, 0xA1, 0x7C, 0x19, 0xB3, 0x58, 0xC2, 0x04]
        let mask = a + b

        let left: [UInt8] = [
            23, 83, 227, 147, 66, 41, 189, 125, 70, 230, 19, 109, 219, 82, 128, 107,
            56, 28, 223,
        ]

        let right: [UInt8] = [
            130, 92, 38, 177, 106, 108, 229, 21, 120, 221, 61, 226, 84, 54, 89, 240,
            148, 74, 42, 172,
        ]
        
        let packed = left + right

        return packed.enumerated().map { index, byte in
            byte ^ mask[index % mask.count]
        }
    }
}
