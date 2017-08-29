import WMF

extension UIViewController {
    class func wmf_viewControllerFromReferencePanelsStoryboard() -> Self {
        return self.wmf_viewControllerFromStoryboardNamed("WMFReferencePanels")
    }
}

@objc protocol WMFReferencePageViewAppearanceDelegate : NSObjectProtocol {
    func referencePageViewControllerWillAppear(_ referencePageViewController: WMFReferencePageViewController)
    func referencePageViewControllerWillDisappear(_ referencePageViewController: WMFReferencePageViewController)
}

class WMFReferencePageViewController: UIPageViewController, UIPageViewControllerDataSource, Themeable {
    var lastClickedReferencesIndex:Int = 0
    var lastClickedReferencesGroup = [WMFReference]()
    
    weak internal var appearanceDelegate: WMFReferencePageViewAppearanceDelegate?
    
    var theme = Theme.standard
    
    func apply(theme: Theme) {
        self.theme = theme
        backgroundView.apply(theme: theme)
        guard viewIfLoaded != nil else {
            return
        }
    }

    fileprivate lazy var pageControllers: [UIViewController] = {
        var controllers:[UIViewController] = []
        
        for reference in self.lastClickedReferencesGroup {
            let panel = WMFReferencePanelViewController.wmf_viewControllerFromReferencePanelsStoryboard()
            panel.apply(theme: self.theme)
            panel.reference = reference
            controllers.append(panel)
        }
        
        return controllers
    }()
    
    lazy var backgroundView: WMFReferencePageBackgroundView = {
        return WMFReferencePageBackgroundView()
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        dataSource = self
        
        let direction:UIPageViewControllerNavigationDirection = UIApplication.shared.wmf_isRTL ? .forward : .reverse
        
        let initiallyVisibleController = pageControllers[lastClickedReferencesIndex]
        
        setViewControllers([initiallyVisibleController], direction: direction, animated: true, completion: nil)
        
        addBackgroundView()

        if let scrollView = view.wmf_firstSubviewOfType(UIScrollView.self) {
            scrollView.clipsToBounds = false
        }
        
        apply(theme: theme)
    }
    
    fileprivate func addBackgroundView() {
        view.addSubview(backgroundView)
        view.sendSubview(toBack: backgroundView)
        backgroundView.mas_makeConstraints { make in
            _ = make?.top.bottom().leading().and().trailing().equalTo()(self.view)
        }
    }
    
    internal func firstPanelView() -> UIView? {
        guard let viewControllers = viewControllers, let firstVC = viewControllers.first as? WMFReferencePanelViewController else {
            return nil
        }
        return firstVC.containerView
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        appearanceDelegate?.referencePageViewControllerWillAppear(self)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        appearanceDelegate?.referencePageViewControllerWillDisappear(self)
    }
    
    func presentationCount(for pageViewController: UIPageViewController) -> Int {
        return pageControllers.count
    }
    
    func presentationIndex(for pageViewController: UIPageViewController) -> Int {
        guard let viewControllers = viewControllers, let currentVC = viewControllers.first, let presentationIndex = pageControllers.index(of: currentVC) else {
            return 0
        }
        return presentationIndex
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let index = pageControllers.index(of: viewController) else {
            return nil
        }
        return index >= pageControllers.count - 1 ? nil : pageControllers[index + 1]
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let index = pageControllers.index(of: viewController) else {
            return nil
        }
        return index == 0 ? nil : pageControllers[index - 1]
    }
    
    override func willTransition(to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator) {
        super.willTransition(to: newCollection, with: coordinator)
        self.presentingViewController?.dismiss(animated: false, completion: nil)
    }
    
}
