public struct Tag {
    let readingList: ReadingList
    let index: Int
    let indexPath: IndexPath
    
    var isLast: Bool {
        return index == 2
    }
}

class TagCollectionViewCell: CollectionViewCell {
    static let reuseIdentifier = "TagCollectionViewCell"
    private let label = UILabel()
    let margins = UIEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)
    private let maxWidth: CGFloat = 150
    
    override func setup() {
        contentView.addSubview(label)
        layer.cornerRadius = 3
        clipsToBounds = true
        super.setup()
    }

    func configure(with tag: Tag, for count: Int, theme: Theme) {
        guard tag.index <= 2, let name = tag.readingList.name else {
            return
        }
        label.text = (tag.isLast ? "+\(count - 2)" : name).uppercased()
        apply(theme: theme)
        updateFonts(with: traitCollection)
        setNeedsLayout()
    }
    
    var semanticContentAttributeOverride: UISemanticContentAttribute = .unspecified {
        didSet {
            label.semanticContentAttribute = semanticContentAttributeOverride
        }
    }
    
    override func updateFonts(with traitCollection: UITraitCollection) {
        super.updateFonts(with: traitCollection)
        label.setFont(with: .system, style: .footnote, traitCollection: traitCollection)
    }
    
    override func sizeThatFits(_ size: CGSize, apply: Bool) -> CGSize {
        let availableWidth = (size.width == UIViewNoIntrinsicMetric ? maxWidth : size.width) - margins.left - margins.right

        var origin = CGPoint(x: margins.left, y: margins.top)

        let tagLabelFrame = label.wmf_preferredFrame(at: origin, fitting: availableWidth, alignedBy: semanticContentAttributeOverride, apply: true)
        origin.y += tagLabelFrame.height
        origin.y += margins.bottom

        return CGSize(width: tagLabelFrame.size.width + margins.left
             + margins.right, height: origin.y)
    }
    
    override func updateBackgroundColorOfLabels() {
        super.updateBackgroundColorOfLabels()
        label.backgroundColor = labelBackgroundColor
    }
}

extension TagCollectionViewCell: Themeable {
    func apply(theme: Theme) {
        label.textColor = theme.colors.secondaryText
        setBackgroundColors(theme.colors.midBackground, selected: theme.colors.baseBackground)
        updateSelectedOrHighlighted()
    }
}
