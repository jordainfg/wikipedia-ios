import UIKit

protocol HintViewControllerDelegate: AnyObject {
    func hintViewControllerWillDisappear(_ hintViewController: HintViewController)
    func hintViewControllerHeightDidChange(_ hintViewController: HintViewController)
    func hintViewControllerViewTypeDidChange(_ hintViewController: HintViewController, newViewType: HintViewController.ViewType)
    func hintViewControllerDidPeformConfirmationAction(_ hintViewController: HintViewController)
    func hintViewControllerDidFailToCompleteDefaultAction(_ hintViewController: HintViewController)
}

class HintViewController: UIViewController {
    @IBOutlet weak var defaultView: UIView!
    @IBOutlet weak var defaultLabel: UILabel!
    @IBOutlet weak var defaultImageView: UIImageView!

    @IBOutlet weak var confirmationView: UIView!
    @IBOutlet weak var confirmationLabel: UILabel!
    @IBOutlet weak var confirmationImageView: UIImageView!
    @IBOutlet weak var confirmationAccessoryButton: UIButton!

    weak var delegate: HintViewControllerDelegate?

    var theme = Theme.standard

    enum ViewType {
        case `default`
        case confirmation
    }

    var viewType: ViewType = .default {
        didSet {
            switch viewType {
            case .default:
                confirmationView.isHidden = true
                defaultView.isHidden = false
            case .confirmation:
                confirmationView.isHidden = false
                defaultView.isHidden = true
            }
            delegate?.hintViewControllerViewTypeDidChange(self, newViewType: viewType)
        }
    }

    override var nibName: String? {
        return "HintViewController"
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureSubviews()
        apply(theme: theme)
        let isRTL = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
        confirmationAccessoryButton.imageView?.transform = isRTL ? CGAffineTransform(scaleX: -1, y: 1) : CGAffineTransform.identity
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        delegate?.hintViewControllerWillDisappear(self)
    }

    private var previousHeight: CGFloat = 0.0
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if previousHeight != view.frame.size.height {
            delegate?.hintViewControllerHeightDidChange(self)
        }
        previousHeight = view.frame.size.height
    }

    open func configureSubviews() {

    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        defaultLabel.font = UIFont.wmf_font(.mediumSubheadline, compatibleWithTraitCollection: traitCollection)
        confirmationLabel.font = UIFont.wmf_font(.mediumSubheadline, compatibleWithTraitCollection: traitCollection)
    }
}

extension HintViewController {
    @IBAction open func performDefaultAction(sender: Any) {

    }

    @IBAction open func performConfirmationAction(sender: Any) {

    }
}

extension HintViewController: Themeable {
    func apply(theme: Theme) {
        self.theme = theme
        guard viewIfLoaded != nil else {
            return
        }
        view.backgroundColor = theme.colors.hintBackground
        defaultLabel?.textColor = theme.colors.link
        confirmationLabel?.textColor = theme.colors.link
        confirmationAccessoryButton.tintColor = theme.colors.link
    }
}
