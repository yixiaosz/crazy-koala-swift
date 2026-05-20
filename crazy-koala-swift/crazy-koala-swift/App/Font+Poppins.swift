// App/Font+Poppins.swift
// Poppins font convenience extensions (dev-plan §7, §2)

import SwiftUI

enum PoppinsWeight: String {
    case regular = "Poppins-Regular"
    case medium = "Poppins-Medium"
    case bold = "Poppins-Bold"
    case extraBold = "Poppins-ExtraBold"
    case light = "Poppins-Light"
    case italic = "Poppins-Italic"
    case lightItalic = "Poppins-LightItalic"
}

extension Font {
    static func poppins(_ weight: PoppinsWeight = .regular, size: CGFloat) -> Font {
        .custom(weight.rawValue, size: size)
    }
}
