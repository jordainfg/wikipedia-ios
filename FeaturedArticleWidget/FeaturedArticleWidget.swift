import UIKit
import NotificationCenter
import WMF

class FeaturedArticleWidget: UIViewController, NCWidgetProviding {
    let collapsedArticleView = ArticleRightAlignedImageCollectionViewCell()
    let expandedArticleView = ArticleFullWidthImageCollectionViewCell()

    var isExpanded = true
    
    var currentArticleKey: String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.translatesAutoresizingMaskIntoConstraints = false

        let tapGR = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        view.addGestureRecognizer(tapGR)

        collapsedArticleView.saveButton.addTarget(self, action: #selector(saveButtonPressed), for: .touchUpInside)
        collapsedArticleView.frame = view.bounds
        view.addSubview(collapsedArticleView)

        expandedArticleView.saveButton.addTarget(self, action: #selector(saveButtonPressed), for: .touchUpInside)
        expandedArticleView.frame = view.bounds
        view.addSubview(expandedArticleView)
        
        updateView()
        updateViewAlpha()
    }
    
    var isEmptyViewHidden = true {
        didSet {
            collapsedArticleView.isHidden = !isEmptyViewHidden
            expandedArticleView.isHidden = !isEmptyViewHidden
        }
    }
    
    var dataStore: MWKDataStore? {
        return SessionSingleton.sharedInstance()?.dataStore
    }
    
    var article: WMFArticle? {
        guard let featuredContentGroup = dataStore?.viewContext.newestGroup(of: .featuredArticle),
            let articleURL = featuredContentGroup.content?.first as? URL else {
                return nil
        }
        return dataStore?.fetchArticle(with: articleURL)
    }
    
    func widgetPerformUpdate(completionHandler: @escaping (NCUpdateResult) -> Void) {
        guard let article = self.article,
            let articleKey = article.key else {
                isEmptyViewHidden = false
                completionHandler(.failed)
                return
        }
        
        guard articleKey != currentArticleKey else {
            completionHandler(.noData)
            return
        }
        
        currentArticleKey = articleKey
        isEmptyViewHidden = true

        let theme:Theme
        
        if #available(iOSApplicationExtension 10.0, *) {
            theme = Theme.widget
        } else {
            theme = Theme.widgetiOS9
        }
        
        collapsedArticleView.configure(article: article, displayType: .relatedPages, index: 0, count: 1, shouldAdjustMargins: false, shouldShowSeparators: false, theme: theme, layoutOnly: false)
        collapsedArticleView.titleFontFamily = .systemBold
        collapsedArticleView.titleTextStyle = .body
        collapsedArticleView.updateFonts(with: traitCollection)
        collapsedArticleView.tintColor = theme.colors.link
        collapsedArticleView.saveButton.saveButtonState = article.savedDate == nil ? .longSave : .longSaved

        expandedArticleView.configure(article: article, displayType: .pageWithPreview, index: 0, count: 1, theme: theme, layoutOnly: false)
        expandedArticleView.tintColor = theme.colors.link
        expandedArticleView.saveButton.saveButtonState = article.savedDate == nil ? .longSave : .longSaved
        
        updateView()
        completionHandler(.newData)
    }
    
    func updateViewAlpha() {
        expandedArticleView.alpha = isExpanded ? 1 : 0
        collapsedArticleView.alpha =  isExpanded ? 0 : 1
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        let viewUpdates = {
            self.updateViewAlpha()
        }
        
        guard coordinator.isAnimated else {
            viewUpdates()
            return
        }
        
        coordinator.animate(alongsideTransition: { (context) in
            viewUpdates()
        }) { (context) in }
    }
    
    func updateView() {
        var maximumSize = CGSize(width: view.bounds.size.width, height: UIViewNoIntrinsicMetric)
        if let context = extensionContext {
            if #available(iOSApplicationExtension 10.0, *) {
                context.widgetLargestAvailableDisplayMode = .expanded
                isExpanded = context.widgetActiveDisplayMode == .expanded
                maximumSize = context.widgetMaximumSize(for: context.widgetActiveDisplayMode)
            } else {
                isExpanded = true
                maximumSize = UIScreen.main.bounds.size
            }
        }
        updateView(maximumSize: maximumSize, isExpanded: isExpanded)
    }
    
    func updateView(maximumSize: CGSize, isExpanded: Bool) {
        let sizeThatFits: CGSize
        if isExpanded {
            sizeThatFits = expandedArticleView.sizeThatFits(CGSize(width: maximumSize.width, height:UIViewNoIntrinsicMetric), apply: true)
            expandedArticleView.frame = CGRect(origin: .zero, size:sizeThatFits)
        } else {
            collapsedArticleView.imageViewDimension = maximumSize.height - 30 //hax
            sizeThatFits = collapsedArticleView.sizeThatFits(CGSize(width: maximumSize.width, height:UIViewNoIntrinsicMetric), apply: true)
            collapsedArticleView.frame = CGRect(origin: .zero, size:sizeThatFits)
        }
        preferredContentSize = CGSize(width: maximumSize.width, height: sizeThatFits.height)
    }
    
    @available(iOSApplicationExtension 10.0, *)
    func widgetActiveDisplayModeDidChange(_ activeDisplayMode: NCWidgetDisplayMode, withMaximumSize maxSize: CGSize) {
        isExpanded = activeDisplayMode == .expanded
        updateView(maximumSize: maxSize, isExpanded: isExpanded)
    }
    
    func saveButtonPressed() {
        guard let article = self.article, let articleKey = article.key else {
            return
        }
        let isSaved = dataStore?.savedPageList.toggleSavedPage(forKey: articleKey) ?? false
        expandedArticleView.saveButton.saveButtonState = isSaved ? .longSaved : .longSave
        collapsedArticleView.saveButton.saveButtonState = isSaved ? .longSaved : .longSave
    }

    func handleTapGesture(_ tapGR: UITapGestureRecognizer) {
        guard tapGR.state == .recognized else {
            return
        }
        guard let article = self.article, let articleURL = article.url else {
            return
        }

        let URL = articleURL as NSURL?
        let URLToOpen = URL?.wmf_wikipediaScheme ?? NSUserActivity.wmf_baseURLForActivity(of: .explore)

        self.extensionContext?.open(URLToOpen)
    }
    
}
