import UIKit

final class WMFAltTextExperimentModalSheetView: WMFComponentView {

    // MARK: Properties

    weak var viewModel: WMFAltTextExperimentModalSheetViewModel?
    weak var delegate: WMFAltTextExperimentModalSheetDelegate?

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private lazy var stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.setContentHuggingPriority(.required, for: .vertical)
        stackView.setContentCompressionResistancePriority(.required, for: .vertical)
        stackView.alignment = .fill
        stackView.spacing = padding
        stackView.axis = .vertical
        return stackView
    }()

    private lazy var headerStackView:  UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.setContentHuggingPriority(.required, for: .vertical)
        stackView.setContentCompressionResistancePriority(.required, for: .vertical)
        stackView.distribution = .equalSpacing
        stackView.alignment = .fill
        stackView.axis = .horizontal
        return stackView
    }()
    
    private lazy var imageFileNameStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.setContentHuggingPriority(.required, for: .vertical)
        stackView.setContentCompressionResistancePriority(.required, for: .vertical)
        stackView.axis = .horizontal
        return stackView
    }()
    
    private lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentHuggingPriority(.required, for: .vertical)
        imageView.setContentCompressionResistancePriority(.required, for: .vertical)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(tappedImage))
        imageView.addGestureRecognizer(tapGestureRecognizer)
        return imageView
    }()
    
    lazy var fileNameButton: UIButton = {
        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(tappedFileName), for: .touchUpInside)
        return button
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.required, for: .vertical)
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }()

    private lazy var textView: UITextView = {
        let textfield = UITextView(frame: .zero)
        textfield.translatesAutoresizingMaskIntoConstraints = false
        textfield.layer.cornerRadius = 10
        return textfield
    }()

    private lazy var placeholder: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    lazy var nextButton: UIButton = {
        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(tappedNext), for: .touchUpInside)
        return button
    }()

    private let basePadding: CGFloat = 8
    private let padding: CGFloat = 16

    // MARK: Lifecycle

    public init(frame: CGRect, viewModel: WMFAltTextExperimentModalSheetViewModel, delegate: WMFAltTextExperimentModalSheetDelegate?) {
        self.viewModel = viewModel
        self.delegate = delegate
        super.init(frame: frame)
        textView.delegate = self
        setup()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Methods

    public override func appEnvironmentDidChange() {
        super.appEnvironmentDidChange()
        configure()
    }

    func updateColors() {
        backgroundColor = theme.midBackground
        titleLabel.textColor = theme.text
        textView.backgroundColor = theme.paperBackground
        fileNameButton.setTitleColor(theme.link, for: .normal)
        nextButton.setTitleColor(theme.link, for: .normal)
        nextButton.setTitleColor(theme.secondaryText, for: .disabled)
        placeholder.textColor = theme.secondaryText
        textView.textColor = theme.text
    }

    func configure() {
        updateColors()
        updateNextButtonState()
        updatePlaceholderVisibility()

        titleLabel.text = viewModel?.localizedStrings.title
        nextButton.setTitle(viewModel?.localizedStrings.buttonTitle, for: .normal)
        
        fileNameButton.setTitle(viewModel?.altTextViewModel.filename, for: .normal)
        
        placeholder.text = viewModel?.localizedStrings.textViewPlaceholder
        
        textView.font = WMFFont.for(.callout, compatibleWith: traitCollection)

        titleLabel.font = WMFFont.for(.boldTitle3, compatibleWith: traitCollection)
        nextButton.titleLabel?.font = WMFFont.for(.semiboldHeadline, compatibleWith: traitCollection)
        placeholder.font = WMFFont.for(.callout, compatibleWith: traitCollection)
    }

    func setup() {
        configure()

        textView.addSubview(placeholder)

        headerStackView.addArrangedSubview(titleLabel)
        headerStackView.addArrangedSubview(nextButton)
        
        imageFileNameStackView.addArrangedSubview(imageView)
        imageFileNameStackView.addArrangedSubview(fileNameButton)

        stackView.addArrangedSubview(headerStackView)
        stackView.addArrangedSubview(imageFileNameStackView)
        stackView.addArrangedSubview(textView)

        scrollView.addSubview(stackView)
        addSubview(scrollView)

        NSLayoutConstraint.activate([

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.contentLayoutGuide.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: padding),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -padding),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: basePadding),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -padding),
            
            imageView.heightAnchor.constraint(equalToConstant: 65),
            imageView.widthAnchor.constraint(equalToConstant: 65),

            textView.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: stackView.trailingAnchor),
            textView.heightAnchor.constraint(equalToConstant: 125),

            nextButton.heightAnchor.constraint(equalToConstant:44),

            placeholder.topAnchor.constraint(equalTo: textView.topAnchor, constant: basePadding),
            placeholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: basePadding)
        ])
        
        if let imageURLString = viewModel?.altTextViewModel.imageThumbURL,
           let imageURL = URL(string: imageURLString) {
            viewModel?.populateUIImage(for: imageURL) { [weak self] error in
                self?.imageView.image = self?.viewModel?.uiImage
            }
        }
        
    }

    private func updateNextButtonState() {
        nextButton.isEnabled = !textView.text.isEmpty
    }

    private func updatePlaceholderVisibility() {
        placeholder.isHidden = !textView.text.isEmpty
    }
    
    @objc func tappedNext() {
        guard let altText = textView.text,
              !altText.isEmpty else {
            return
        }
        
        nextButton.isEnabled = false
        delegate?.didTapNext(altText: altText)
    }
    
    @objc func tappedImage() {
        // TODO: Go to gallery view
    }
    
    @objc func tappedFileName() {
        // TODO: Go to commons web view
    }
}

extension WMFAltTextExperimentModalSheetView: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updateNextButtonState()
        updatePlaceholderVisibility()
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        placeholder.isHidden = true
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        updatePlaceholderVisibility()
    }
}
