import UIKit



@objc(WMFArticleCollectionViewCell)
open class ArticleCollectionViewCell: CollectionViewCell, SwipeableCell, BatchEditableCell {
    static let defaultMargins: UIEdgeInsets = UIEdgeInsets(top: 15, left: 13, bottom: 15, right: 13)
    static let defaultMarginsMultipliers: UIEdgeInsets = UIEdgeInsets(top: 1, left: 1, bottom: 1, right: 1)
    public var layoutMarginsMultipliers: UIEdgeInsets = ArticleCollectionViewCell.defaultMarginsMultipliers
    public var layoutMarginsAdditions: UIEdgeInsets = .zero
    
    @objc public let titleLabel = UILabel()
    @objc public let descriptionLabel = UILabel()
    @objc public let imageView = UIImageView()
    @objc public let saveButton = SaveButton()
    @objc public var extractLabel: UILabel?
    public let actionsView = ActionsView()
    public var alertIcon = UIImageView()
    public var alertLabel = UILabel()
    open var alertType: ReadingListAlertType?
    public var statusView = UIImageView() // the circle that appears next to the article name to indicate the article's status

    public var actions: [Action] {
        set {
            actionsView.actions = newValue
            updateAccessibilityElements()
        }
        get {
            return actionsView.actions
        }
    }

    private var kvoButtonTitleContext = 0
    
    open override func setup() {
        titleFontFamily = .georgia
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        statusView.clipsToBounds = true
        
        if #available(iOSApplicationExtension 11.0, *) {
            imageView.accessibilityIgnoresInvertColors = true
        }
        
        titleLabel.isOpaque = true
        descriptionLabel.isOpaque = true
        imageView.isOpaque = true
        saveButton.isOpaque = true
        
        contentView.addSubview(alertIcon)
        contentView.addSubview(alertLabel)
        contentView.addSubview(statusView)
        contentView.addSubview(saveButton)
        contentView.addSubview(imageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(descriptionLabel)

        saveButton.verticalPadding = 16
        saveButton.rightPadding = 16
        saveButton.leftPadding = 12
        saveButton.saveButtonState = .longSave
        saveButton.addObserver(self, forKeyPath: "titleLabel.text", options: .new, context: &kvoButtonTitleContext)
        
        super.setup()
    }
    
    
    // This method is called to reset the cell to the default configuration. It is called on initial setup and prepareForReuse. Subclassers should call super.
    override open func reset() {
        super.reset()
        layoutMarginsMultipliers = ArticleCollectionViewCell.defaultMarginsMultipliers
        titleFontFamily = .georgia
        titleTextStyle = .title1
        descriptionFontFamily = .system
        descriptionTextStyle  = .subheadline
        extractFontFamily = .system
        extractTextStyle  = .subheadline
        saveButtonFontFamily = .systemMedium
        saveButtonTextStyle  = .subheadline
        layoutMargins = ArticleCollectionViewCell.defaultMargins
        spacing = 5
        imageViewDimension = 70
        statusViewDimension = 6
        alertIconDimension = 12
        saveButtonTopSpacing = 5
        imageView.wmf_reset()
        resetSwipeable()
        isBatchEditing = false
        isBatchEditable = false
        actions = []
        isAlertLabelHidden = true
        isAlertIconHidden = true
        isStatusViewHidden = true
        updateFonts(with: traitCollection)
    }

    override open func updateBackgroundColorOfLabels() {
        super.updateBackgroundColorOfLabels()
        titleLabel.backgroundColor = labelBackgroundColor
        descriptionLabel.backgroundColor = labelBackgroundColor
        extractLabel?.backgroundColor = labelBackgroundColor
        saveButton.backgroundColor = labelBackgroundColor
        saveButton.titleLabel?.backgroundColor = labelBackgroundColor
        alertIcon.backgroundColor = labelBackgroundColor
        alertLabel.backgroundColor = labelBackgroundColor
    }
    
    deinit {
        saveButton.removeObserver(self, forKeyPath: "titleLabel.text", context: &kvoButtonTitleContext)
    }

    open override func safeAreaInsetsDidChange() {
        if #available(iOSApplicationExtension 11.0, *) {
            super.safeAreaInsetsDidChange()
        }
        if swipeState == .open {
            swipeTranslation = swipeTranslationWhenOpen
        }
        setNeedsLayout()
    }

    var actionsViewInsets: UIEdgeInsets {
        if #available(iOSApplicationExtension 11.0, *) {
            return safeAreaInsets
        } else {
            return UIEdgeInsets.zero
        }
    }
    
    public final var statusViewDimension: CGFloat = 0 {
        didSet {
            setNeedsLayout()
        }
    }
    
    public final var alertIconDimension: CGFloat = 0 {
        didSet {
            setNeedsLayout()
        }
    }
    
    public var isStatusViewHidden: Bool = true {
        didSet {
            statusView.isHidden = isStatusViewHidden
            setNeedsLayout()
        }
    }
    
    public var isAlertLabelHidden: Bool = true {
        didSet {
            alertLabel.isHidden = isAlertLabelHidden
            setNeedsLayout()
        }
    }
    
    public var isAlertIconHidden: Bool = true {
        didSet {
            alertIcon.isHidden = isAlertIconHidden
            setNeedsLayout()
        }
    }
    
    open override func sizeThatFits(_ size: CGSize, apply: Bool) -> CGSize {
        let size = super.sizeThatFits(size, apply: apply)
        if apply {
            let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
            let batchEditSelectViewWidth = abs(batchEditingTranslation)
            
            var batchEditX = batchEditingTranslation > 0 ? layoutMargins.left : -layoutMargins.left
            if isRTL {
                if (traitCollection.verticalSizeClass == .regular && traitCollection.horizontalSizeClass == .regular) || traitCollection.verticalSizeClass == .compact && traitCollection.horizontalSizeClass == .compact {
                    batchEditX = size.width - batchEditSelectViewWidth
                } else {
                    batchEditX = size.width - batchEditSelectViewWidth + layoutMargins.left
                }
            }
            batchEditSelectView?.frame = CGRect(x: batchEditX, y: 0, width: batchEditSelectViewWidth, height: size.height)
            batchEditSelectView?.layoutIfNeeded()
            
            let actionsViewWidth = isRTL ? max(0, swipeTranslation) : -1 * min(0, swipeTranslation)
            let x = isRTL ? 0 : size.width - actionsViewWidth
            actionsView.frame = CGRect(x: x, y: 0, width: actionsViewWidth, height: size.height)
            actionsView.layoutIfNeeded()
        }
        return size
    }
    
    // MARK - View configuration
    // These properties can mutate with each use of the cell. They should be reset by the `reset` function. Call setsNeedLayout after adjusting any of these properties
    
    public var titleFontFamily: WMFFontFamily?
    public var titleTextStyle: UIFontTextStyle?
    
    public var descriptionFontFamily: WMFFontFamily?
    public var descriptionTextStyle: UIFontTextStyle?
    
    public var extractFontFamily: WMFFontFamily?
    public var extractTextStyle: UIFontTextStyle?
    
    public var saveButtonFontFamily: WMFFontFamily?
    public var saveButtonTextStyle: UIFontTextStyle?
    
    public var imageViewDimension: CGFloat! //used as height on full width cell, width & height on right aligned
    public var spacing: CGFloat!
    public var saveButtonTopSpacing: CGFloat!
    
    @objc public var isImageViewHidden = false {
        didSet {
            imageView.isHidden = isImageViewHidden
            setNeedsLayout()
        }
    }
    
    @objc public var isSaveButtonHidden = false {
        didSet {
            saveButton.isHidden = isSaveButtonHidden
            setNeedsLayout()
        }
    }

    open override func updateFonts(with traitCollection: UITraitCollection) {
        super.updateFonts(with: traitCollection)
        titleLabel.setFont(with:titleFontFamily, style: titleTextStyle, traitCollection: traitCollection)
        descriptionLabel.setFont(with:descriptionFontFamily, style: descriptionTextStyle, traitCollection: traitCollection)
        extractLabel?.setFont(with:extractFontFamily, style: extractTextStyle, traitCollection: traitCollection)
        saveButton.titleLabel?.setFont(with:saveButtonFontFamily, style: saveButtonTextStyle, traitCollection: traitCollection)
        alertLabel.setFont(with: .systemSemiBold, style: .caption2, traitCollection: traitCollection)
    }
    
    // MARK - Semantic content
    
    fileprivate var _articleSemanticContentAttribute: UISemanticContentAttribute = .unspecified
    fileprivate var _effectiveArticleSemanticContentAttribute: UISemanticContentAttribute = .unspecified
    open var articleSemanticContentAttribute: UISemanticContentAttribute {
        set {
            _articleSemanticContentAttribute = newValue
            updateEffectiveArticleSemanticContentAttribute()
            setNeedsLayout()
        }
        get {
            return _effectiveArticleSemanticContentAttribute
        }
    }

    // for items like the Save Button that are localized and should match the UI direction
    public var userInterfaceSemanticContentAttribute: UISemanticContentAttribute {
        return traitCollection.layoutDirection == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
    }
    
    fileprivate func updateEffectiveArticleSemanticContentAttribute() {
        if _articleSemanticContentAttribute == .unspecified {
            let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
            _effectiveArticleSemanticContentAttribute = isRTL ? .forceRightToLeft : .forceLeftToRight
        } else {
            _effectiveArticleSemanticContentAttribute = _articleSemanticContentAttribute
        }
        let alignment = _effectiveArticleSemanticContentAttribute == .forceRightToLeft ? NSTextAlignment.right : NSTextAlignment.left
        titleLabel.textAlignment = alignment
        titleLabel.semanticContentAttribute = _effectiveArticleSemanticContentAttribute
        descriptionLabel.semanticContentAttribute = _effectiveArticleSemanticContentAttribute
        descriptionLabel.textAlignment = alignment
        extractLabel?.semanticContentAttribute = _effectiveArticleSemanticContentAttribute
        extractLabel?.textAlignment = alignment
    }
    
    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        updateEffectiveArticleSemanticContentAttribute()
        super.traitCollectionDidChange(previousTraitCollection)
    }
    
    // MARK - Accessibility
    
    open override func updateAccessibilityElements() {
        var updatedAccessibilityElements: [Any] = []
        var groupedLabels = [titleLabel, descriptionLabel]
        if let extract = extractLabel {
            groupedLabels.append(extract)
        }

        updatedAccessibilityElements.append(LabelGroupAccessibilityElement(view: self, labels: groupedLabels, actions: actions))
        
        if !isSaveButtonHidden {
            updatedAccessibilityElements.append(saveButton)
        }
        
        accessibilityElements = updatedAccessibilityElements
    }
    
    // MARK - KVO
    
    open override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if context == &kvoButtonTitleContext {
            setNeedsLayout()
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    // MARK: - Swipeable
    var swipeState: SwipeState = .closed {
        didSet {
            if swipeState != .closed && actionsView.superview == nil {
                contentView.addSubview(actionsView)
                contentView.backgroundColor = backgroundView?.backgroundColor
                clipsToBounds = true
            } else if swipeState == .closed && actionsView.superview != nil {
                actionsView.removeFromSuperview()
                contentView.backgroundColor = .clear
                clipsToBounds = false
            }
        }
    }
    
    public var swipeTranslation: CGFloat = 0 {
        didSet {
            assert(!swipeTranslation.isNaN && swipeTranslation.isFinite)
            let isArticleRTL = articleSemanticContentAttribute == .forceRightToLeft
            if isArticleRTL {
                layoutMarginsAdditions.left = 0 - swipeTranslation
                layoutMarginsAdditions.right = swipeTranslation
            } else {
                layoutMarginsAdditions.right = 0 - swipeTranslation
                layoutMarginsAdditions.left = swipeTranslation
            }
            setNeedsLayout()
        }
    }

    private var batchEditingTranslation: CGFloat = 0 {
        didSet {
            defer {
                let isOpen = batchEditingTranslation > 0
                if isOpen, let batchEditSelectView = batchEditSelectView {
                    contentView.addSubview(batchEditSelectView)
                    batchEditSelectView.clipsToBounds = true
                }
                setNeedsLayout()
            }
            let isArticleRTL = articleSemanticContentAttribute == .forceRightToLeft
            let isDeviceRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
            let marginAddition = batchEditingTranslation / 1.5
            
            if isDeviceRTL && isArticleRTL {
                layoutMarginsAdditions.left = marginAddition
            } else if isDeviceRTL || isArticleRTL {
                layoutMarginsAdditions.right = marginAddition
            } else {
                layoutMarginsAdditions.left = marginAddition
            }
        }
    }

    public var swipeTranslationWhenOpen: CGFloat {
        let maxWidth = actionsView.maximumWidth
        let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
        return isRTL ? actionsViewInsets.left + maxWidth : 0 - maxWidth - actionsViewInsets.right
    }

    // MARK: Prepare for reuse
    
    func resetSwipeable() {
        swipeTranslation = 0
        swipeState = .closed
    }
    
    // MARK: - BatchEditableCell
    
    public var batchEditSelectView: BatchEditSelectView?

    public var isBatchEditable: Bool = false {
        didSet {
            if isBatchEditable && batchEditSelectView == nil {
                batchEditSelectView = BatchEditSelectView()
                batchEditSelectView?.isSelected = isSelected
            } else if !isBatchEditable && batchEditSelectView != nil {
                batchEditSelectView?.removeFromSuperview()
                batchEditSelectView = nil
            }
        }
    }
    
    public var isBatchEditing: Bool = false {
        didSet {
            if isBatchEditing {
                isBatchEditable = true
                batchEditingTranslation = BatchEditSelectView.fixedWidth
                batchEditSelectView?.isSelected = isSelected
            } else {
                batchEditingTranslation = 0
            }
        }
    }
    
    override open var isSelected: Bool {
        didSet {
            batchEditSelectView?.isSelected = isSelected
        }
    }
}
