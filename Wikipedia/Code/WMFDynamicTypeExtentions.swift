import Foundation

extension UIButton {
    fileprivate func wmf_configureForDynamicType(){
        if #available(iOS 10.0, *) {
            guard let titleLabel = titleLabel else {
                return
            }
            titleLabel.adjustsFontForContentSizeCategory = true
            titleLabel.textAlignment = .center
            titleLabel.numberOfLines = 1
            titleLabel.clipsToBounds = false
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.minimumScaleFactor = 0.25
            titleLabel.adjustsFontSizeToFitWidth = true
        }
    }
}

extension UILabel {
    fileprivate func wmf_configureForDynamicType(){
        if #available(iOS 10.0, *) {
            self.adjustsFontForContentSizeCategory = true
        }
    }
}

extension UITextField {
    fileprivate func wmf_configureForDynamicType(){
        if #available(iOS 10.0, *) {
            self.adjustsFontForContentSizeCategory = true
        }
    }
}

extension UIView {
    func wmf_configureSubviewsForDynamicType() {
        if #available(iOS 10.0, *) {
            if self.isKind(of: UIButton.self) {
                (self as! UIButton).wmf_configureForDynamicType()
            }else if self.isKind(of: UILabel.self) {
                (self as! UILabel).wmf_configureForDynamicType()
            }else if self.isKind(of: UITextField.self) {
                (self as! UITextField).wmf_configureForDynamicType()
            }
            for subview in self.subviews {
                subview.wmf_configureSubviewsForDynamicType()
            }
        }
    }
}
