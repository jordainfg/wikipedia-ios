import Foundation

public extension UIColor {
    public convenience init(_ hex: Int, alpha: CGFloat) {
        let r = CGFloat((hex & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((hex & 0xFF00) >> 8) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
    
    @objc(initWithHexInteger:)
    public convenience init(_ hex: Int) {
        self.init(hex, alpha: 1)
    }
    
    public class func wmf_colorWithHex(_ hex: Int) -> UIColor {
        return UIColor(hex)
    }

    fileprivate static let base10 = UIColor(0x222222)
    fileprivate static let base20 = UIColor(0x54595D)
    fileprivate static let base30 = UIColor(0x72777D)
    fileprivate static let base50 = UIColor(0xA2A9B1)
    fileprivate static let base70 = UIColor(0xC8CCD1)
    fileprivate static let base80 = UIColor(0xEAECF0)
    fileprivate static let base90 = UIColor(0xF8F9FA)
    fileprivate static let base100 = UIColor(0xFFFFFF)
    fileprivate static let red30 = UIColor(0xB32424)
    fileprivate static let red50 = UIColor(0xCC3333)
    fileprivate static let yellow50 = UIColor(0xFFCC33)
    fileprivate static let green50 = UIColor(0x00AF89)
    fileprivate static let blue10 = UIColor(0x2A4B8D)
    fileprivate static let blue50 = UIColor(0x3366CC)
    fileprivate static let mesophere = UIColor(0x43464A)
    fileprivate static let thermosphere = UIColor(0x2E3136)
    fileprivate static let stratosphere = UIColor(0x6699FF)
    fileprivate static let exosphere = UIColor(0x27292D)
    fileprivate static let accent = UIColor(0x00AF89)
    fileprivate static let sunsetRed = UIColor(0xFF6E6E)
    fileprivate static let accent10 = UIColor(0x2A4B8D)
    fileprivate static let amate = UIColor(0xE1DAD1)
    fileprivate static let parchment = UIColor(0xF8F1E3)
    fileprivate static let masi = UIColor(0x646059)
    fileprivate static let papyrus = UIColor(0xF0E6D6)
    fileprivate static let kraft = UIColor(0xCBC8C1)
    fileprivate static let osage = UIColor(0xFF9500)
    
    fileprivate static let masi60PercentAlpha = UIColor(0x646059, alpha:0.6)
    fileprivate static let black50PercentAlpha = UIColor(0x000000, alpha:0.5)
    fileprivate static let black75PercentAlpha = UIColor(0x000000, alpha:0.75)
    
    public static let wmf_darkGray = UIColor(0x4D4D4B)
    public static let wmf_lightGray = UIColor(0x9AA0A7)
    public static let wmf_gray = UIColor.base70
    public static let wmf_lighterGray = UIColor.base80
    public static let wmf_lightestGray = UIColor(0xF5F5F5) // also known as refresh gray

    public static let wmf_darkBlue = UIColor.blue10
    public static let wmf_blue = UIColor.blue50
    public static let wmf_lightBlue = UIColor(0xEAF3FF)

    public static let wmf_green = UIColor.green50
    public static let wmf_lightGreen = UIColor(0xD5FDF4)

    public static let wmf_red = UIColor.red50
    public static let wmf_lightRed = UIColor(0xFFE7E6)
    
    public static let wmf_yellow = UIColor.yellow50
    public static let wmf_lightYellow = UIColor(0xFEF6E7)
    
    public static let wmf_orange = UIColor(0xFF5B00)
    
    public static let wmf_purple = UIColor(0x7F4AB3)
    public static let wmf_lightPurple = UIColor(0xF3E6FF)

    public func wmf_hexStringIncludingAlpha(_ includeAlpha: Bool) -> String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        getRed(&r, green: &g, blue: &b, alpha: &a)
        
        var hexString = String(format: "%02X%02X%02X", Int(255.0 * r), Int(255.0 * g), Int(255.0 * b))
        if (includeAlpha) {
            hexString = hexString.appendingFormat("%02X", Int(255.0 * a))
        }
        return hexString
    }
    
    public var wmf_hexString: String {
        return wmf_hexStringIncludingAlpha(false)
    }
}

@objc(WMFColors)
public class Colors: NSObject {
    fileprivate static let light = Colors(baseBackground: .base80, midBackground: .base90, paperBackground: .base100, chromeBackground: .base100,  popoverBackground: .base100, subCellBackground: .base100, overlayBackground: .black50PercentAlpha, keyboardBarSearchFieldBackground: .base80, primaryText: .base10, secondaryText: .base30, tertiaryText: .base70, disabledText: .base30, chromeText: .base20, link: .blue50, accent: .green50, border: .base70 , shadow: .base80, secondaryAction: .blue10, icon: nil, iconBackground: nil, destructive: .red50, error: .red50, warning: .yellow50, unselected: .base50)

    fileprivate static let sepia = Colors(baseBackground: .amate, midBackground: .papyrus, paperBackground: .parchment, chromeBackground: .parchment, popoverBackground: .base100, subCellBackground: .papyrus, overlayBackground: .masi60PercentAlpha, keyboardBarSearchFieldBackground: .base80, primaryText: .base10, secondaryText: .masi, tertiaryText: .masi, disabledText: .base30, chromeText: .base20, link: .blue50, accent: .green50, border: .kraft, shadow: .kraft, secondaryAction: .accent10, icon: .masi, iconBackground: .amate, destructive: .red30, error: .red30, warning: .osage, unselected: .masi)
    
    fileprivate static let dark = Colors(baseBackground: .base10, midBackground: .exosphere, paperBackground: .thermosphere, chromeBackground: .mesophere, popoverBackground: .base10, subCellBackground: .exosphere, overlayBackground: .black75PercentAlpha, keyboardBarSearchFieldBackground: .thermosphere, primaryText: .base90, secondaryText: .base70, tertiaryText: .base70, disabledText: .base70, chromeText: .base90, link: .stratosphere, accent: .green50, border: .mesophere, shadow: .base10, secondaryAction: .accent10, icon: .base70, iconBackground: .exosphere, destructive: .sunsetRed, error: .sunsetRed, warning: .yellow50, unselected: .base70)
    
    fileprivate static let widgetiOS9 = Colors(baseBackground: .clear, midBackground: .clear, paperBackground: .clear, chromeBackground: .clear, popoverBackground: .clear, subCellBackground: .clear, overlayBackground: UIColor(white: 0.3, alpha: 0.3), keyboardBarSearchFieldBackground: .thermosphere, primaryText: .base90, secondaryText: .base70, tertiaryText: .base70, disabledText: .base70, chromeText: .base90, link: .stratosphere, accent: .green50, border: .mesophere, shadow: .base10, secondaryAction: .accent10, icon: .base70, iconBackground: .exosphere, destructive: .sunsetRed, error: .sunsetRed, warning: .yellow50, unselected: .base70)

    fileprivate static let widget = Colors(baseBackground: .clear, midBackground: .clear, paperBackground: .clear, chromeBackground: .clear,  popoverBackground: .clear, subCellBackground: .clear, overlayBackground: UIColor(white: 1.0, alpha: 0.4), keyboardBarSearchFieldBackground: .base80, primaryText: .base10, secondaryText: .base20, tertiaryText: .base20, disabledText: .base30, chromeText: .base20, link: .blue50, accent: .green50, border: UIColor(white: 0, alpha: 0.10) , shadow: .base80, secondaryAction: .blue10, icon: nil, iconBackground: nil, destructive: .red50, error: .red50, warning: .yellow50, unselected: .base50)
    
    public let baseBackground: UIColor
    public let midBackground: UIColor
    public let subCellBackground: UIColor
    public let paperBackground: UIColor
    public let popoverBackground: UIColor
    public let chromeBackground: UIColor
    public let overlayBackground: UIColor
    
    public let primaryText: UIColor
    public let secondaryText: UIColor
    public let tertiaryText: UIColor
    public let disabledText: UIColor
    
    public let chromeText: UIColor
    
    public let link: UIColor
    public let accent: UIColor
    public let secondaryAction: UIColor
    public let destructive: UIColor
    public let warning: UIColor
    public let error: UIColor
    public let unselected: UIColor

    public let border: UIColor
    public let shadow: UIColor
    
    public let icon: UIColor?
    public let iconBackground: UIColor?
    
    public let keyboardBarSearchFieldBackground: UIColor
    
    public let linkToAccent: Gradient
    
    //Someday, when the app is all swift, make this class a struct.
    init(baseBackground: UIColor, midBackground: UIColor, paperBackground: UIColor, chromeBackground: UIColor, popoverBackground: UIColor, subCellBackground: UIColor, overlayBackground: UIColor, keyboardBarSearchFieldBackground: UIColor, primaryText: UIColor, secondaryText: UIColor, tertiaryText: UIColor, disabledText: UIColor, chromeText: UIColor, link: UIColor, accent: UIColor, border: UIColor, shadow: UIColor, secondaryAction: UIColor, icon: UIColor?, iconBackground: UIColor?, destructive: UIColor, error: UIColor, warning: UIColor, unselected: UIColor) {
        self.baseBackground = baseBackground
        self.midBackground = midBackground
        self.subCellBackground = subCellBackground
        self.paperBackground = paperBackground
        self.popoverBackground = popoverBackground
        self.chromeBackground = chromeBackground
        self.overlayBackground = overlayBackground
        self.keyboardBarSearchFieldBackground = keyboardBarSearchFieldBackground
        
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.tertiaryText = tertiaryText
        self.disabledText = disabledText
        
        self.chromeText = chromeText

        self.link = link
        self.accent = accent
        
        self.border = border
        self.shadow = shadow
        
        self.icon = icon
        self.iconBackground = iconBackground
        
        self.linkToAccent = Gradient(startColor: link, endColor: accent)
        
        self.error = error
        self.warning = warning
        self.destructive = destructive
        self.secondaryAction = secondaryAction
        self.unselected = unselected
    }
}


@objc(WMFTheme)
public class Theme: NSObject {
    public let colors: Colors
    
    public let preferredStatusBarStyle: UIStatusBarStyle
    public let blurEffectStyle: UIBlurEffectStyle
    public let keyboardAppearance: UIKeyboardAppearance
    
    public static let light = Theme(colors: .light, preferredStatusBarStyle: .default, blurEffectStyle: .light, keyboardAppearance: .light, imageOpacity: 1, name: "standard", displayName: WMFLocalizedString("theme-default-display-name", value: "Default", comment: "Default theme name presented to the user"))
    
    public static let sepia = Theme(colors: .sepia, preferredStatusBarStyle: .default, blurEffectStyle: .light, keyboardAppearance: .light, imageOpacity: 1, name: "sepia", displayName: WMFLocalizedString("theme-sepia-display-name", value: "Sepia", comment: "Sepia theme name presented to the user"))
    
    public static let dark = Theme(colors: .dark, preferredStatusBarStyle: .lightContent, blurEffectStyle: .dark, keyboardAppearance: .dark, imageOpacity: 1, name: "dark", displayName: WMFLocalizedString("theme-dark-display-name", value: "Dark", comment: "Dark theme name presented to the user"))
    
    public static let darkDimmed = Theme(colors: .dark, preferredStatusBarStyle: .lightContent, blurEffectStyle: .dark, keyboardAppearance: .dark, imageOpacity: 0.65, name: "dark-dimmed", displayName: WMFLocalizedString("dark-theme-display-name", value: "Dark", comment: "Dark theme name presented to the user"))
    
    
    public static let widget = Theme(colors: .widget, preferredStatusBarStyle: .default, blurEffectStyle: .light, keyboardAppearance: .light, imageOpacity: 1, name: "", displayName: "")
    
    public static let widgetiOS9 = Theme(colors: .widgetiOS9, preferredStatusBarStyle: .lightContent, blurEffectStyle: .dark, keyboardAppearance: .dark, imageOpacity: 1, name: "", displayName: "")

    
    fileprivate static let themesByName = [Theme.light.name: Theme.light, Theme.dark.name: Theme.dark, Theme.sepia.name: Theme.sepia, Theme.darkDimmed.name: Theme.darkDimmed]
    
    @objc(withName:)
    public class func withName(_ name: String?) -> Theme? {
        guard let name = name else {
            return nil
        }
        return themesByName[name]
    }
    
    public static let standard = Theme.light
    public let imageOpacity: CGFloat
    public let name: String
    public let displayName: String
    
    init(colors: Colors, preferredStatusBarStyle: UIStatusBarStyle, blurEffectStyle: UIBlurEffectStyle, keyboardAppearance: UIKeyboardAppearance, imageOpacity: CGFloat, name: String, displayName: String) {
        self.colors = colors
        self.preferredStatusBarStyle = preferredStatusBarStyle
        self.blurEffectStyle = blurEffectStyle
        self.keyboardAppearance = keyboardAppearance
        self.imageOpacity = imageOpacity
        self.name = name
        self.displayName = displayName
    }
    
    public func withDimmingEnabled(_ isDimmingEnabled: Bool) -> Theme {
        guard let baseName = name.components(separatedBy: "-").first else {
            return self
        }
        let adjustedName = isDimmingEnabled ? "\(baseName)-dimmed" : baseName
        return Theme.withName(adjustedName) ?? self
    }
}

@objc(WMFThemeable)
public protocol Themeable : NSObjectProtocol {
    @objc(applyTheme:)
    func apply(theme: Theme) //this might be better as a var theme: Theme { get set } - common VC superclasses could check for viewIfLoaded and call an update method in the setter. This would elminate the need for the viewIfLoaded logic in every applyTheme:
}
