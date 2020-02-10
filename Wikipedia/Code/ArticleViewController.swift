import UIKit
import WMF

@objc(WMFArticleViewController)
class ArticleViewController: ViewController {    
    enum ViewState {
        case initial
        case loading
        case loaded
        case error
    }
    
    internal lazy var toolbarController: ArticleToolbarController = {
        return ArticleToolbarController(toolbar: toolbar, delegate: self)
    }()
    
    /// Article holds article metadata (displayTitle, description, etc) and user state (isSaved, viewedDate, viewedFragment, etc)
    internal let article: WMFArticle
    
    /// Use separate properties for URL and language since they're optional on WMFArticle and to save having to re-calculate them
    @objc public let articleURL: URL
    let articleLanguage: String

    public var visibleSectionAnchor: String? // TODO: Implement
    @objc public var loadCompletion: (() -> Void)?
    
    internal let schemeHandler: SchemeHandler
    internal let dataStore: MWKDataStore
  

    private let authManager: WMFAuthenticationManager = WMFAuthenticationManager.sharedInstance // TODO: DI?
    private let cacheController: CacheController
    
    private lazy var languageLinkFetcher: MWKLanguageLinkFetcher = MWKLanguageLinkFetcher()
    private lazy var fetcher: ArticleFetcher = ArticleFetcher()
    internal var references: References?

    private var leadImageHeight: CGFloat = 210
    
    @objc init?(articleURL: URL, dataStore: MWKDataStore, theme: Theme, forceCache: Bool = false) {
        guard
            let article = dataStore.fetchOrCreateArticle(with: articleURL),
            let cacheController = dataStore.articleCacheControllerWrapper.cacheController
        else {
            return nil
        }
        
        self.articleURL = articleURL
        self.articleLanguage = articleURL.wmf_language ?? Locale.current.languageCode ?? "en"
        self.article = article

        self.dataStore = dataStore
        self.schemeHandler = SchemeHandler.shared // TODO: DI?
        self.schemeHandler.forceCache = forceCache
        self.schemeHandler.cacheController = cacheController
        self.cacheController = cacheController
        
        super.init(theme: theme)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: WebView
    
    static let webProcessPool = WKProcessPool()
    
    lazy var messagingController: ArticleWebMessagingController = ArticleWebMessagingController(delegate: self)
    
    lazy var webViewConfiguration: WKWebViewConfiguration = {
        let configuration = WKWebViewConfiguration()
        configuration.processPool = ArticleViewController.webProcessPool
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: schemeHandler.scheme)
        return configuration
    }()
    
    lazy var webView: WKWebView = {
        return WKWebView(frame: view.bounds, configuration: webViewConfiguration)
    }()

    // MARK: Lead Image
    
    @objc func userDidTapLeadImage() {
        
    }
    
    func loadLeadImage(with leadImageURL: URL) {
        leadImageHeightConstraint.constant = leadImageHeight
        leadImageView.wmf_setImage(with: leadImageURL, detectFaces: true, onGPU: true, failure: { (error) in
            DDLogError("Error loading lead image: \(error)")
        }) {
            self.updateLeadImageMargins()
            self.updateArticleMargins()
        }
    }
    
    lazy var leadImageLeadingMarginConstraint: NSLayoutConstraint = {
        return leadImageView.leadingAnchor.constraint(equalTo: leadImageContainerView.leadingAnchor)
    }()
    
    lazy var leadImageTrailingMarginConstraint: NSLayoutConstraint = {
        return leadImageContainerView.trailingAnchor.constraint(equalTo: leadImageView.trailingAnchor)
    }()
    
    lazy var leadImageHeightConstraint: NSLayoutConstraint = {
        return leadImageContainerView.heightAnchor.constraint(equalToConstant: 0)
    }()
    
    lazy var leadImageView: UIImageView = {
        let imageView = NoIntrinsicContentSizeImageView(frame: .zero)
        imageView.isUserInteractionEnabled = true
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.accessibilityIgnoresInvertColors = true
        let tapGR = UITapGestureRecognizer(target: self, action: #selector(userDidTapLeadImage))
        imageView.addGestureRecognizer(tapGR)
        return imageView
    }()
    
    lazy var leadImageBorderHeight: CGFloat = {
        let scale = UIScreen.main.scale
        return scale > 1 ? 0.5 : 1
    }()
    
    lazy var leadImageContainerView: UIView = {

        let height: CGFloat = 10
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: height))
        containerView.clipsToBounds = true
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        let borderView = UIView(frame: CGRect(x: 0, y: height - leadImageBorderHeight, width: 1, height: leadImageBorderHeight))
        borderView.backgroundColor = UIColor(white: 0, alpha: 0.2)
        borderView.autoresizingMask = [.flexibleTopMargin, .flexibleWidth]
        
        leadImageView.frame = CGRect(x: 0, y: 0, width: 1, height: height - leadImageBorderHeight)
        containerView.addSubview(leadImageView)
        containerView.addSubview(borderView)
        return containerView
    }()
    
    override func updateViewConstraints() {
        super.updateViewConstraints()
        updateLeadImageMargins()
    }
    
    func updateLeadImageMargins() {
        let imageSize = leadImageView.image?.size ?? .zero
        let isImageNarrow = imageSize.height < 1 ? false : imageSize.width / imageSize.height < 2
        var marginWidth: CGFloat = 0
        if isImageNarrow && tableOfContentsController.viewController.displayMode == .inline && !tableOfContentsController.viewController.isVisible {
            marginWidth = 32
        }
        leadImageLeadingMarginConstraint.constant = marginWidth
        leadImageTrailingMarginConstraint.constant = marginWidth
    }
    
    // MARK: Previewing
    
    public var articlePreviewingDelegate: ArticlePreviewingDelegate?
    
    // MARK: Layout
    
    override func scrollViewInsetsDidChange() {
        super.scrollViewInsetsDidChange()
        updateTableOfContentsInsets()
    }
    
    override func viewLayoutMarginsDidChange() {
        super.viewLayoutMarginsDidChange()
        updateArticleMargins()
    }
    
    private func updateArticleMargins() {
        messagingController.updateMargins(with: articleMargins, leadImageHeight: leadImageHeightConstraint.constant)
    }
    
    // MARK: Loading
    
    internal var state: ViewState = .initial {
        didSet {
            switch state {
            case .initial:
                break
            case .loading:
                fakeProgressController.start()
            case .loaded:
                fakeProgressController.stop()
            case .error:
                fakeProgressController.stop()
            }
        }
    }
    
    lazy private var fakeProgressController: FakeProgressController = {
        let progressController = FakeProgressController(progress: navigationBar, delegate: navigationBar)
        progressController.delay = 0.0
        return progressController
    }()
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        setup()
        super.viewDidLoad()
        setupToolbar() // setup toolbar needs to be after super.viewDidLoad because the superview owns the toolbar
        apply(theme: theme)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableOfContentsController.setup(with: traitCollection)
        toolbarController.update()
        loadIfNecessary()
        setupGestureRecognizerDependencies()
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        tableOfContentsController.update(with: traitCollection)
        toolbarController.update()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancelWIconPopoverDisplay()
        saveArticleScrollPosition()
    }
    
    // MARK: Theme
    
    lazy var themesPresenter: ReadingThemesControlsArticlePresenter = {
        return ReadingThemesControlsArticlePresenter(readingThemesControlsViewController: themesViewController, wkWebView: webView, readingThemesControlsToolbarItem: toolbarController.themeButton)
    }()
    
    private lazy var themesViewController: ReadingThemesControlsViewController = {
        return ReadingThemesControlsViewController(nibName: ReadingThemesControlsViewController.nibName, bundle: nil)
    }()
    
    override func apply(theme: Theme) {
        super.apply(theme: theme)
        guard viewIfLoaded != nil else {
            return
        }
        view.backgroundColor = theme.colors.paperBackground
        webView.scrollView.indicatorStyle = theme.scrollIndicatorStyle
        toolbarController.apply(theme: theme)
        tableOfContentsController.apply(theme: theme)
        if state == .loaded {
            messagingController.updateTheme(theme)
        }
    }
    
    // MARK: Sharing
    
    @objc public func shareArticleWhenReady() {
        // TODO: implement
    }
    
    // MARK: Overrideable functionality
    
    internal func handleLink(with title: String) {
        guard let host = articleURL.host,
            let newArticleURL = ArticleURLConverter.desktopURL(host: host, title: title) else {
                assertionFailure("Failure initializing new Article VC")
                //tonitodo: error state
                return
        }
        navigate(to: newArticleURL)
    }
    
    // MARK: Table of contents
    
    lazy var tableOfContentsController: ArticleTableOfContentsDisplayController = ArticleTableOfContentsDisplayController(articleView: webView, delegate: self, theme: theme)
    
    var tableOfContentsItems: [TableOfContentsItem] = [] {
        didSet {
            tableOfContentsController.viewController.reload()
        }
    }
    
    var previousContentOffsetYForTOCUpdate: CGFloat = 0
    
    func updateTableOfContentsHighlightIfNecessary() {
        guard tableOfContentsController.viewController.displayMode == .inline, tableOfContentsController.viewController.isVisible else {
            return
        }
        let scrollView = webView.scrollView
        guard abs(previousContentOffsetYForTOCUpdate - scrollView.contentOffset.y) > 15 else {
            return
        }
        guard scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating else {
            return
        }
        updateTableOfContentsHighlight()
    }
    
    func updateTableOfContentsHighlight() {
        previousContentOffsetYForTOCUpdate = webView.scrollView.contentOffset.y
        getVisibleSectionId { (sectionId) in
            self.tableOfContentsController.selectAndScroll(to: sectionId, animated: true)
        }
    }
    
    func updateTableOfContentsInsets() {
        let tocScrollView = tableOfContentsController.viewController.tableView
        let topOffsetY = 0 - tocScrollView.contentInset.top
        let wasAtTop = tocScrollView.contentOffset.y <= topOffsetY
        switch tableOfContentsController.viewController.displayMode {
        case .inline:
            tocScrollView.contentInset = webView.scrollView.contentInset
            tocScrollView.scrollIndicatorInsets = webView.scrollView.scrollIndicatorInsets
        case .modal:
            tocScrollView.contentInset = UIEdgeInsets(top: view.safeAreaInsets.top, left: 0, bottom: view.safeAreaInsets.bottom, right: 0)
            tocScrollView.scrollIndicatorInsets = tocScrollView.contentInset
        }
        guard wasAtTop else {
            return
        }
        tocScrollView.contentOffset = CGPoint(x: 0, y: topOffsetY)
    }
    
    // MARK: Scroll
    
    func scroll(to anchor: String, centered: Bool = false, animated: Bool, completion: (() -> Void)? = nil) {
        guard !anchor.isEmpty else {
            webView.scrollView.scrollRectToVisible(CGRect(x: 0, y: 1, width: 1, height: 1), animated: animated)
            completion?()
            return
        }
        webView.getScrollRectForHtmlElement(withId: anchor) { (rect) in
            assert(Thread.isMainThread)
            guard !rect.isNull else {
                completion?()
                return
            }
            let point = CGPoint(x: self.webView.scrollView.contentOffset.x, y: rect.origin.y)
            self.scroll(to: point, animated: animated, completion: completion)
        }
    }
    
    var scrollViewAnimationCompletions: [() -> Void] = []
    func scroll(to offset: CGPoint, centered: Bool = false, animated: Bool, completion: (() -> Void)? = nil) {
        assert(Thread.isMainThread)
        let scrollView = webView.scrollView
        guard !offset.x.isNaN && !offset.x.isInfinite && !offset.y.isNaN && !offset.y.isInfinite else {
            completion?()
            return
        }
        let overlayTop = self.webView.iOS12yOffsetHack + self.navigationBar.hiddenHeight
        let adjustmentY: CGFloat
        if centered {
            let overlayBottom = self.webView.scrollView.contentInset.bottom
            let height = self.webView.scrollView.bounds.height
            adjustmentY = -0.5 * (height - overlayTop - overlayBottom)
        } else {
            adjustmentY = overlayTop
        }
        let minY = 0 - scrollView.contentInset.top
        let maxY = scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom
        let boundedY = min(maxY,  max(minY, offset.y + adjustmentY))
        let boundedOffset = CGPoint(x: scrollView.contentOffset.x, y: boundedY)
        guard WMFDistanceBetweenPoints(boundedOffset, scrollView.contentOffset) >= 2 else {
            scrollView.flashScrollIndicators()
            completion?()
            return
        }
        guard animated else {
            scrollView.setContentOffset(boundedOffset, animated: false)
            completion?()
            return
        }
        /*
         Setting scrollView.contentOffset inside of an animation block
         results in a broken animation https://phabricator.wikimedia.org/T232689
         Calling [scrollView setContentOffset:offset animated:YES] inside
         of an animation block fixes the animation but doesn't guarantee
         the content offset will be updated when the animation's completion
         block is called.
         It appears the only reliable way to get a callback after the default
         animation is to use scrollViewDidEndScrollingAnimation
         */
        if let completion = completion {
            scrollViewAnimationCompletions.insert(completion, at: 0)
        }
        scrollView.setContentOffset(boundedOffset, animated: true)
    }
    
    override func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        super.scrollViewDidEndScrollingAnimation(scrollView)
        // call the first completion
        scrollViewAnimationCompletions.popLast()?()
    }
    
    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        super.scrollViewDidScroll(scrollView)
        updateTableOfContentsHighlightIfNecessary()
    }
    
    override func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
        super.scrollViewDidScrollToTop(scrollView)
        updateTableOfContentsHighlight()
    }
    
    override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        super.scrollViewWillBeginDragging(scrollView)
        dismissReferencesPopover()
    }
    
    // MARK: Article load
    
    var footerLoadGroup: DispatchGroup?
    var languageCount: Int = 0
    
    func loadIfNecessary() {
        guard state == .initial else {
            return
        }
        load()
    }
    
    func load() {
        state = .loading
        setupPageContentServiceJavaScriptInterface {
            self.loadPage()
        }
    }
    
    func loadPage() {
        if let leadImageURL = article.imageURL(forWidth: traitCollection.wmf_leadImageWidth) {
            loadLeadImage(with: leadImageURL)
        }
        guard let mobileHTMLURL = ArticleURLConverter.mobileHTMLURL(desktopURL: articleURL, endpointType: .mobileHTML, scheme: schemeHandler.scheme) else {
            showGenericError()
            state = .error
            return
        }
        
        footerLoadGroup = DispatchGroup()
        footerLoadGroup?.enter() // will leave on setup complete
        footerLoadGroup?.notify(queue: DispatchQueue.main) { [weak self] in
            self?.setupFooter()
            self?.footerLoadGroup = nil
        }
        
        let request = URLRequest(url: mobileHTMLURL)
        webView.load(request)
        
        guard let key = article.key else {
            showGenericError()
            state = .error
            return
        }
        footerLoadGroup?.enter()
        dataStore.articleSummaryController.updateOrCreateArticleSummaryForArticle(withKey: key) { (article, error) in
            self.footerLoadGroup?.leave()
        }
        footerLoadGroup?.enter()
        languageLinkFetcher.fetchLanguageLinks(forArticleURL: articleURL, success: { (links) in
            self.languageCount = links.count
            self.footerLoadGroup?.leave()
        }) { (error) in
            self.footerLoadGroup?.leave()
        }
        
        footerLoadGroup?.enter()
        fetcher.fetchReferences(with: articleURL) { (result, _) in
            DispatchQueue.main.async {
                switch result {
                case .success(let references):
                    self.references = references
                case .failure(let error):
                    DDLogError("Error fetching references for \(self.articleURL): \(error)")
                }
                self.footerLoadGroup?.leave()
            }
        }
    }
    
    func markArticleAsViewed() {
        article.viewedDate = Date()
        try? article.managedObjectContext?.save()
    }
    
    func saveArticleScrollPosition() {
        getVisibleSectionId { (sectionId) in
            guard let item = self.tableOfContentsItems.first(where: { $0.id == sectionId }) else {
                return
            }
            assert(Thread.isMainThread)
            self.article.viewedScrollPosition = Double(self.webView.scrollView.contentOffset.y)
            self.article.viewedFragment = item.anchor
            try? self.article.managedObjectContext?.save()

        }
    }
    
    // MARK: Gestures
    
    func setupGestureRecognizerDependencies() {
        guard let popGR = navigationController?.interactivePopGestureRecognizer else {
            return
        }
        webView.scrollView.panGestureRecognizer.require(toFail: popGR)
    }
    
    // MARK: Analytics
    
    internal lazy var editFunnel: EditFunnel = EditFunnel.shared
    internal lazy var shareFunnel: WMFShareFunnel? = WMFShareFunnel(article: article)
    internal lazy var readingListsFunnel = ReadingListsFunnel.shared
}

private extension ArticleViewController {
    
    func setup() {
        setupWButton()
        setupSearchButton()
        addNotificationHandlers()
        setupWebView()
    }
    
    func addNotificationHandlers() {
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveArticleUpdatedNotification), name: NSNotification.Name.WMFArticleUpdated, object: article)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
    }
    
    @objc func didReceiveArticleUpdatedNotification(_ notification: Notification) {
        toolbarController.setSavedState(isSaved: article.isSaved)
    }
    
    @objc func applicationWillResignActive(_ notification: Notification) {
        saveArticleScrollPosition()
    }
    
    func setupSearchButton() {
        navigationItem.rightBarButtonItem = AppSearchBarButtonItem.newAppSearchBarButtonItem
    }
    
    func setupWebView() {
        view.wmf_addSubviewWithConstraintsToEdges(tableOfContentsController.stackView)
        view.widthAnchor.constraint(equalTo: tableOfContentsController.inlineContainerView.widthAnchor, multiplier: 3).isActive = true

        // Prevent flash of white in dark mode
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        scrollView = webView.scrollView // so that content insets are inherited
        scrollView?.delegate = self
        webView.scrollView.addSubview(leadImageContainerView)
            
        let leadingConstraint =  leadImageContainerView.leadingAnchor.constraint(equalTo: webView.leadingAnchor)
        let trailingConstraint =  webView.trailingAnchor.constraint(equalTo: leadImageContainerView.trailingAnchor)
        let topConstraint = webView.scrollView.topAnchor.constraint(equalTo: leadImageContainerView.topAnchor)
        let imageTopConstraint = leadImageView.topAnchor.constraint(equalTo:  leadImageContainerView.topAnchor)
        imageTopConstraint.priority = UILayoutPriority(rawValue: 999)
        let imageBottomConstraint = leadImageContainerView.bottomAnchor.constraint(equalTo: leadImageView.bottomAnchor, constant: leadImageBorderHeight)
        NSLayoutConstraint.activate([topConstraint, leadingConstraint, trailingConstraint, leadImageHeightConstraint, imageTopConstraint, imageBottomConstraint, leadImageLeadingMarginConstraint, leadImageTrailingMarginConstraint])
    }
    
    func setupPageContentServiceJavaScriptInterface(with completion: @escaping () -> Void) {
        guard let siteURL = articleURL.wmf_site else {
            DDLogError("Missing site for \(articleURL)")
            showGenericError()
            return
        }
        
        // Need user groups to let the Page Content Service know if the page is editable for this user
        authManager.getLoggedInUser(for: siteURL) { (result) in
            assert(Thread.isMainThread)
            switch result {
            case .success(let user):
                self.setupPageContentServiceJavaScriptInterface(with: user?.groups ?? [])
            case .failure(let error):
                self.alertManager.showErrorAlert(error, sticky: true, dismissPreviousAlerts: true)
            }
            completion()
        }
    }
    
    func setupPageContentServiceJavaScriptInterface(with userGroups: [String]) {
        let areTablesInitiallyExpanded = UserDefaults.wmf.wmf_isAutomaticTableOpeningEnabled
        messagingController.setup(with: webView, language: articleLanguage, theme: theme, layoutMargins: articleMargins, leadImageHeight: leadImageHeight, areTablesInitiallyExpanded: areTablesInitiallyExpanded, userGroups: userGroups)
    }
    
    func setupToolbar() {
        enableToolbar()
        toolbarController.apply(theme: theme)
        toolbarController.setSavedState(isSaved: article.isSaved)
        setToolbarHidden(false, animated: false)
    }
            
}

extension ArticleViewController {
    func presentEmbedded(_ viewController: UIViewController, style: WMFThemeableNavigationControllerStyle) {
        let nc = WMFThemeableNavigationController(rootViewController: viewController, theme: theme, style: style)
        present(nc, animated: true)
    }
}

extension ArticleViewController: ReadingThemesControlsResponding {
    func updateWebViewTextSize(textSize: Int) {
        messagingController.updateTextSizeAdjustmentPercentage(textSize)
    }
    
    func toggleSyntaxHighlighting(_ controller: ReadingThemesControlsViewController) {
        // no-op here, syntax highlighting shouldnt be displayed
    }
}

extension ArticleViewController: ImageScaleTransitionProviding {
    var imageScaleTransitionView: UIImageView? {
        return leadImageView
    }
    
    func prepareViewsForIncomingImageScaleTransition(with imageView: UIImageView?) {
        guard let imageView = imageView, let image = imageView.image else {
            return
        }

        leadImageView.image = image
        leadImageView.layer.contentsRect = imageView.layer.contentsRect

        view.layoutIfNeeded()
    }

}

extension ViewController {
    /// Allows for re-use by edit preview VC
    var articleMargins: UIEdgeInsets {
        var margins = navigationController?.view.layoutMargins ?? view.layoutMargins // view.layoutMargins is zero here so check nav controller first
        margins.top = 8
        margins.bottom = 0
        return margins
    }
}

//WMFLocalizedStringWithDefaultValue(@"button-read-now", nil, nil, @"Read now", @"Read now button text used in various places.")
//WMFLocalizedStringWithDefaultValue(@"button-saved-remove", nil, nil, @"Remove from saved", @"Remove from saved button text used in various places.")
//WMFLocalizedStringWithDefaultValue(@"edit-menu-item", nil, nil, @"Edit", @"Button label for text selection 'Edit' menu item")
//WMFLocalizedStringWithDefaultValue(@"share-menu-item", nil, nil, @"Share…", @"Button label for 'Share…' menu")
