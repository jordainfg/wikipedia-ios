import Foundation

internal let WMFReadingListUpdateKey = "WMFReadingListUpdateKey"

public enum ReadingListError: Error, Equatable {
    case listExistsWithTheSameName(name: String)
    case unableToCreateList
    case generic
    case unableToDeleteList
    case unableToUpdateList
    case unableToAddEntry
    case unableToRemoveEntry
    case listWithProvidedNameNotFound(name: String)
    
    public var localizedDescription: String {
        switch self {
        // TODO: WMFAlertManager can't display this string
        case .generic:
            return WMFLocalizedString("reading-list-generic-error", value: "An unexpected error occurred while updating your reading lists.", comment: "An unexpected error occurred while updating your reading lists.")
        case .listExistsWithTheSameName(let name):
            let format = WMFLocalizedString("reading-list-exists-with-same-name", value: "A reading list already exists with the name %1$@", comment: "Informs the user that a reading list exists with the same name.")
            return String.localizedStringWithFormat(format, name)
        case .listWithProvidedNameNotFound(let name):
            let format = WMFLocalizedString("reading-list-with-provided-name-not-found", value: "A reading list with the name %1$@ was not found. Please make sure you have the correct name.", comment: "Informs the user that a reading list with the name they provided was not found.")
            return String.localizedStringWithFormat(format, name)
        case .unableToCreateList:
            return WMFLocalizedString("reading-list-unable-to-create", value: "An unexpected error occured while creating your reading list. Please try again later.", comment: "Informs the user that an error occurred while creating their reading list.")
        case .unableToDeleteList:
            return WMFLocalizedString("reading-list-unable-to-delete", value: "An unexpected error occured while deleting your reading list. Please try again later.", comment: "Informs the user that an error occurred while deleting their reading list.")
        case .unableToUpdateList:
            return WMFLocalizedString("reading-list-unable-to-update", value: "An unexpected error occured while updating your reading list. Please try again later.", comment: "Informs the user that an error occurred while updating their reading list.")
        case .unableToAddEntry:
            return WMFLocalizedString("reading-list-unable-to-add-entry", value: "An unexpected error occured while adding an entry to your reading list. Please try again later.", comment: "Informs the user that an error occurred while adding an entry to their reading list.")
        case .unableToRemoveEntry:
            return WMFLocalizedString("reading-list-unable-to-remove-entry", value: "An unexpected error occured while removing an entry from your reading list. Please try again later.", comment: "Informs the user that an error occurred while removing an entry from their reading list.")
        }
    }
    
    public static func ==(lhs: ReadingListError, rhs: ReadingListError) -> Bool {
        return lhs.localizedDescription == rhs.localizedDescription //shrug
    }
}

@objc(WMFReadingListsController)
public class ReadingListsController: NSObject {
    internal weak var dataStore: MWKDataStore!
    internal let apiController = ReadingListsAPIController()
    private let operationQueue = OperationQueue()
    private var updateTimer: Timer?
    
    @objc init(dataStore: MWKDataStore) {
        self.dataStore = dataStore
        operationQueue.maxConcurrentOperationCount = 1
        super.init()
    }
    
    // User-facing actions. Everything is performed on the main context
    
    public func createReadingList(named name: String, description: String? = nil, with articles: [WMFArticle] = []) throws -> ReadingList {
        assert(Thread.isMainThread)
        let name = name.precomposedStringWithCanonicalMapping
        let moc = dataStore.viewContext
        let existingListRequest: NSFetchRequest<ReadingList> = ReadingList.fetchRequest()
        existingListRequest.predicate = NSPredicate(format: "canonicalName MATCHES %@", name)
        existingListRequest.fetchLimit = 1
        let result = try moc.fetch(existingListRequest).first
        guard result == nil else {
            throw ReadingListError.listExistsWithTheSameName(name: name)
        }
        
        guard let list = moc.wmf_create(entityNamed: "ReadingList", withKeysAndValues: ["canonicalName": name, "readingListDescription": description]) as? ReadingList else {
            throw ReadingListError.unableToCreateList
        }
        
        list.isUpdatedLocally = true
        
        try add(articles: articles, to: list)
        
        if moc.hasChanges {
            try moc.save()
        }
        
        update()
        
        return list
    }
    
    /// Marks that reading lists were deleted locally and updates associated objects. Doesn't delete them from the NSManagedObjectContext - that should happen only with confirmation from the server that they were deleted.
    ///
    /// - Parameters:
    ///   - readingLists: the reading lists to delete
    internal func markLocalDeletion(for readingLists: [ReadingList]) throws {
        for readingList in readingLists {
            readingList.isDeletedLocally = true
            readingList.isUpdatedLocally = true
            for entry in readingList.entries ?? [] {
                entry.isDeletedLocally = true
                entry.isUpdatedLocally = true
            }
            let articles = readingList.articles ?? []
            readingList.articles = []
            for article in articles {
                article.readingListsDidChange()
            }
        }
    }
    
    /// Marks that reading lists were deleted locally and updates associated objects. Doesn't delete them from the NSManagedObjectContext - that should happen only with confirmation from the server that they were deleted.
    ///
    /// - Parameters:
    ///   - readingLists: the reading lists to delete
    internal func markLocalDeletion(for readingListEntries: [ReadingListEntry]) throws {
        for entry in readingListEntries {
            entry.isDeletedLocally = true
            entry.isUpdatedLocally = true
            if let moc = entry.managedObjectContext, let key = entry.articleKey, let article = dataStore.fetchArticle(withKey: key, in: moc), let list = entry.list {
                list.removeFromArticles(article)
                article.readingListsDidChange()
            }
            entry.list?.updateCountOfEntries()
        }
    }
    
    internal func processLocalUpdates(in moc: NSManagedObjectContext) throws {
        let taskGroup = WMFTaskGroup()
        let listsToCreateOrUpdateFetch: NSFetchRequest<ReadingList> = ReadingList.fetchRequest()
        listsToCreateOrUpdateFetch.predicate = NSPredicate(format: "isUpdatedLocally == YES")
        let listsToUpdate =  try moc.fetch(listsToCreateOrUpdateFetch)
        var createdReadingLists: [Int64: ReadingList] = [:]
        var updatedReadingLists: [Int64: ReadingList] = [:]
        var deletedReadingLists: [Int64: ReadingList] = [:]
        for localReadingList in listsToUpdate {
            guard let readingListName = localReadingList.name else {
                moc.delete(localReadingList)
                continue
            }
            guard let readingListID = localReadingList.readingListID?.int64Value else {
                if localReadingList.isDeletedLocally {
                    moc.delete(localReadingList)
                } else {
                    taskGroup.enter()
                    self.apiController.createList(name: readingListName, description: localReadingList.readingListDescription, completion: { (readingListID, creationError) in
                        defer {
                            taskGroup.leave()
                        }
                        guard let readingListID = readingListID else {
                            DDLogError("Error creating reading list: \(String(describing: creationError))")
                            return
                        }
                        createdReadingLists[readingListID] = localReadingList
                    })
                }
                continue
            }
            if localReadingList.isDeletedLocally {
                taskGroup.enter()
                self.apiController.deleteList(withListID: readingListID, completion: { (deleteError) in
                    defer {
                        taskGroup.leave()
                    }
                    guard deleteError == nil else {
                        DDLogError("Error deleting reading list: \(String(describing: deleteError))")
                        return
                    }
                    deletedReadingLists[readingListID] = localReadingList
                })
            } else {
                taskGroup.enter()
                self.apiController.updateList(withListID: readingListID, name: readingListName, description: localReadingList.readingListDescription, completion: { (updateError) in
                    defer {
                        taskGroup.leave()
                    }
                    guard updateError == nil else {
                        DDLogError("Error deleting reading list: \(String(describing: updateError))")
                        return
                    }
                    updatedReadingLists[readingListID] = localReadingList
                })
            }
        }
        
        taskGroup.wait()
        
        for (readingListID, localReadingList) in createdReadingLists {
            localReadingList.readingListID = NSNumber(value: readingListID)
            localReadingList.isUpdatedLocally = false
        }
        
        for (_, localReadingList) in updatedReadingLists {
            localReadingList.isUpdatedLocally = false
        }
        
        for (_, localReadingList) in deletedReadingLists {
            moc.delete(localReadingList)
        }
        
        
        let entriesToCreateOrUpdateFetch: NSFetchRequest<ReadingListEntry> = ReadingListEntry.fetchRequest()
        entriesToCreateOrUpdateFetch.predicate = NSPredicate(format: "isUpdatedLocally == YES")
        let localReadingListEntriesToUpdate =  try moc.fetch(entriesToCreateOrUpdateFetch)
        
        var createdReadingListEntries: [Int64: ReadingListEntry] = [:]
        var deletedReadingListEntries: [Int64: ReadingListEntry] = [:]
        
        for localReadingListEntry in localReadingListEntriesToUpdate {
            guard let articleKey = localReadingListEntry.articleKey, let articleURL = URL(string: articleKey), let project = articleURL.wmf_site?.absoluteString, let title = articleURL.wmf_title else {
                moc.delete(localReadingListEntry)
                continue
            }
            guard let readingListID = localReadingListEntry.list?.readingListID?.int64Value else {
                continue
            }
            guard let readingListEntryID = localReadingListEntry.readingListEntryID?.int64Value else {
                if localReadingListEntry.isDeletedLocally {
                    moc.delete(localReadingListEntry)
                } else {
                    taskGroup.enter()
                    self.apiController.addEntryToList(withListID: readingListID, project:project, title: title, completion: { (readingListEntryID, createError) in
                        defer {
                            taskGroup.leave()
                        }
                        guard let readingListEntryID = readingListEntryID else {
                            DDLogError("Error creating reading list entry: \(String(describing: createError))")
                            return
                        }
                        createdReadingListEntries[readingListEntryID] = localReadingListEntry
                    })
                }
                continue
            }
            if localReadingListEntry.isDeletedLocally {
                taskGroup.enter()
                self.apiController.removeEntry(withEntryID: readingListEntryID, fromListWithListID: readingListID, completion: { (deleteError) in
                    defer {
                        taskGroup.leave()
                    }
                    guard deleteError == nil else {
                        DDLogError("Error deleting reading list entry: \(String(describing: deleteError))")
                        return
                    }
                    deletedReadingListEntries[readingListEntryID] = localReadingListEntry
                })
            } else {
                // there's no "updating" of an entry currently
                localReadingListEntry.isUpdatedLocally = false
            }
        }
        
        taskGroup.wait()
        
        for (readingListEntryID, localReadingListEntry) in createdReadingListEntries {
            localReadingListEntry.readingListEntryID = NSNumber(value: readingListEntryID)
            localReadingListEntry.isUpdatedLocally = false
        }
        
        for (_, localReadingListEntry) in deletedReadingListEntries {
            moc.delete(localReadingListEntry)
        }
    }
    
    internal func locallyCreate(_ readingListEntries: [APIReadingListEntry], with readingListsByEntryID: [Int64: ReadingList]? = nil, in moc: NSManagedObjectContext) throws {
        guard readingListEntries.count > 0 else {
            return
        }
        let group = WMFTaskGroup()
        var remoteEntriesToCreateLocallyByArticleKey: [String: APIReadingListEntry] = [:]
        var requestedArticleKeys: Set<String> = []
        var articleSummariesByArticleKey: [String: [String: Any]] = [:]
        for remoteEntry in readingListEntries {
            let isDeleted = remoteEntry.deleted ?? false
            guard !isDeleted else {
                continue
            }
            guard let articleURL = remoteEntry.articleURL, let articleKey = articleURL.wmf_articleDatabaseKey else {
                continue
            }
            remoteEntriesToCreateLocallyByArticleKey[articleKey] = remoteEntry
            guard !requestedArticleKeys.contains(articleKey) else {
                continue
            }
            requestedArticleKeys.insert(articleKey)
            group.enter()
            URLSession.shared.wmf_fetchSummary(with: articleURL, completionHandler: { (result, response, error) in
                guard let result = result else {
                    group.leave()
                    return
                }
                articleSummariesByArticleKey[articleKey] = result
                group.leave()
            })
        }
        
        group.wait()
        
        
        let articles = try moc.wmf_createOrUpdateArticleSummmaries(withSummaryResponses: articleSummariesByArticleKey)
        var articlesByKey: [String: WMFArticle] = [:]
        for article in articles {
            guard let articleKey = article.key else {
                continue
            }
            articlesByKey[articleKey] = article
        }
        
        var finalReadingListsByEntryID: [Int64: ReadingList]
        if let readingListsByEntryID = readingListsByEntryID {
            finalReadingListsByEntryID = readingListsByEntryID
        } else {
            finalReadingListsByEntryID = [:]
            var readingListsByReadingListID: [Int64: ReadingList] = [:]
            let localReadingListsFetch: NSFetchRequest<ReadingList> = ReadingList.fetchRequest()
            localReadingListsFetch.predicate = NSPredicate(format: "readingListID IN %@", readingListEntries.flatMap { $0.listId } )
            let localReadingLists = try moc.fetch(localReadingListsFetch)
            for localReadingList in localReadingLists {
                guard let localReadingListID = localReadingList.readingListID?.int64Value else {
                    continue
                }
                readingListsByReadingListID[localReadingListID] = localReadingList
            }
            for readingListEntry in readingListEntries {
                guard let listId = readingListEntry.listId, let readingList = readingListsByReadingListID[listId] else {
                    DDLogError("Missing list for reading list entry: \(readingListEntry)")
                    assert(false)
                    continue
                }
                finalReadingListsByEntryID[readingListEntry.id] = readingList
            }
        }
        
        for remoteEntry in readingListEntries {
            guard let articleURL = remoteEntry.articleURL, let articleKey = articleURL.wmf_articleDatabaseKey, let article = articlesByKey[articleKey], let readingList = finalReadingListsByEntryID[remoteEntry.id] else {
                continue
            }
            guard let entry = NSEntityDescription.insertNewObject(forEntityName: "ReadingListEntry", into: moc) as? ReadingListEntry else {
                continue
            }
            entry.update(with: remoteEntry)
            entry.list = readingList
            entry.articleKey = article.key
            entry.displayTitle = article.displayTitle
            if article.savedDate == nil {
                article.savedDate = entry.createdDate as Date?
            }
            readingList.addToArticles(article)
            article.readingListsDidChange()
            readingList.updateCountOfEntries()
        }
    }
    
    public func delete(readingLists: [ReadingList]) throws {
        let moc = dataStore.viewContext
        
        try markLocalDeletion(for: readingLists)
        
        if moc.hasChanges {
            try moc.save()
        }
        
        update()
    }
    
    public func add(articles: [WMFArticle], to readingList: ReadingList) throws {
        guard articles.count > 0 else {
            return
        }
        assert(Thread.isMainThread)
        let moc = dataStore.viewContext
        let existingKeys = Set(readingList.articleKeys)
        
        for article in articles {
            guard let key = article.key, !existingKeys.contains(key) else {
                continue
            }
            guard let entry = moc.wmf_create(entityNamed: "ReadingListEntry", withValue: key, forKey: "articleKey") as? ReadingListEntry else {
                return
            }
            entry.isUpdatedLocally = true
            let url = URL(string: key)
            entry.displayTitle = url?.wmf_title
            entry.list = readingList
            readingList.addToArticles(article)
            // try article.removeFromDefaultReadingList()
            article.readingListsDidChange()
        }
        
        readingList.updateCountOfEntries()
        
        if moc.hasChanges {
            try moc.save()
        }
        update()
    }


    internal let isSyncEnabledKey = "WMFIsReadingListSyncEnabled"

    @objc public var isSyncEnabled: Bool {
        assert(Thread.isMainThread)
        return dataStore.viewContext.wmf_numberValue(forKey: isSyncEnabledKey)?.boolValue ?? false
    }
    
    @objc public func setSyncEnabled(_ isSyncEnabled: Bool, shouldDeleteLocalLists: Bool, shouldDeleteRemoteLists: Bool) {
        DispatchQueue.main.async {
            guard isSyncEnabled != self.isSyncEnabled else {
                return
            }
            self.dataStore.viewContext.wmf_setValue(NSNumber(value: isSyncEnabled), forKey: self.isSyncEnabledKey)
            if isSyncEnabled {
                let op = ReadingListsEnableSyncOperation(readingListsController: self, shouldDeleteLocalLists: shouldDeleteLocalLists, shouldDeleteRemoteLists: shouldDeleteRemoteLists)
                self.operationQueue.addOperation(op)
            } else {
                let op = ReadingListsDisableSyncOperation(readingListsController: self, shouldDeleteLocalLists: shouldDeleteLocalLists, shouldDeleteRemoteLists: shouldDeleteRemoteLists)
                self.operationQueue.addOperation(op)
            }
            self.sync()
        }
    }
    
    private func processUpdatesForUserWithSyncDisabled() {
        assert(Thread.isMainThread)
        let op = ReadingListsLocalOnlySyncOperation(readingListsController: self)
        operationQueue.addOperation(op)
    }
    
    @objc public func start() {
        guard updateTimer == nil else {
            return
        }
        assert(Thread.isMainThread)
        updateTimer = Timer.scheduledTimer(timeInterval: 15, target: self, selector: #selector(update), userInfo: nil, repeats: true)
        sync()
    }
    
    @objc public func stop() {
        assert(Thread.isMainThread)
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    @objc public func backgroundUpdate(_ completion: @escaping () -> Void) {
        if isSyncEnabled {
            let update = ReadingListsUpdateOperation(readingListsController: self)
            operationQueue.addOperation(update)
            operationQueue.addOperation(completion)
        } else {
            completion()
        }
    }
    
    @objc private func _update() {
        if isSyncEnabled {
            let update = ReadingListsUpdateOperation(readingListsController: self)
            operationQueue.addOperation(update)
        } else {
            processUpdatesForUserWithSyncDisabled()
        }
    }
    
    @objc private func update() {
        assert(Thread.isMainThread)
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(_update), object: nil)
        perform(#selector(_update), with: nil, afterDelay: 0.5)
    }
    
    @objc private func _sync() {
        if isSyncEnabled {
            let sync = ReadingListsSyncOperation(readingListsController: self)
            operationQueue.addOperation(sync)
        } else {
            processUpdatesForUserWithSyncDisabled()
        }
    }
    
    @objc private func sync() {
        assert(Thread.isMainThread)
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(_update), object: nil)
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(_sync), object: nil)
        perform(#selector(_sync), with: nil, afterDelay: 0.5)
    }
    
    public func remove(articles: [WMFArticle], readingList: ReadingList) throws {
        assert(Thread.isMainThread)
        let moc = dataStore.viewContext
        
        let articleKeys = articles.flatMap { $0.key }
        for article in articles {
            readingList.removeFromArticles(article)
            article.readingListsDidChange()
        }
        
        let entriesRequest: NSFetchRequest<ReadingListEntry> = ReadingListEntry.fetchRequest()
        entriesRequest.predicate = NSPredicate(format: "list == %@ && articleKey IN %@", readingList, articleKeys)
        let entriesToDelete = try moc.fetch(entriesRequest)
        for entry in entriesToDelete {
            entry.isDeletedLocally = true
            entry.isUpdatedLocally = true
        }

        readingList.updateCountOfEntries()

        if moc.hasChanges {
            try moc.save()
        }
        update()
    }
    
    public func remove(entries: [ReadingListEntry]) throws {
        assert(Thread.isMainThread)
        let moc = dataStore.viewContext
        try markLocalDeletion(for: entries)
        if moc.hasChanges {
            try moc.save()
        }
        update()
    }
    
    @objc public func save(_ article: WMFArticle) {
        assert(Thread.isMainThread)
        do {
            let moc = dataStore.viewContext
            if article.savedDate == nil {
                article.savedDate = Date()
            }
            try article.addToDefaultReadingList()
            if moc.hasChanges {
                try moc.save()
            }
            update()
        } catch let error {
            DDLogError("Error adding article to default list: \(error)")
        }
    }
    
    @objc public func addArticleToDefaultReadingList(_ article: WMFArticle) throws {
        try article.addToDefaultReadingList()
    }
    
    @objc public func unsave(_ article: WMFArticle) {
        do {
            guard let moc = article.managedObjectContext else {
                return
            }
            article.savedDate = nil
            guard let key = article.key else {
                return
            }
            let entryFetchRequest: NSFetchRequest<ReadingListEntry> = ReadingListEntry.fetchRequest()
            entryFetchRequest.predicate = NSPredicate(format: "articleKey == %@", key)
            let entries = try moc.fetch(entryFetchRequest)
            try markLocalDeletion(for: entries)
        } catch let error {
            DDLogError("Error removing article from default list: \(error)")
        }
    }
    
    
    @objc public func removeArticlesWithURLsFromDefaultReadingList(_ articleURLS: [URL]) {
        assert(Thread.isMainThread)
        do {
            let moc = dataStore.viewContext
            for url in articleURLS {
                guard let article = dataStore.fetchArticle(with: url) else {
                    continue
                }
                unsave(article)
            }
            if moc.hasChanges {
                try moc.save()
            }
            update()
        } catch let error {
            DDLogError("Error removing all articles from default list: \(error)")
        }
    }
    
    @objc public func unsaveAllArticles()  {
        assert(Thread.isMainThread)
        do {
            let moc = dataStore.viewContext
            try moc.wmf_batchProcessObjects(matchingPredicate: NSPredicate(format: "savedDate != NULL"), handler: { (article: WMFArticle) in
                print("unsaving \(article.key!)")
                unsave(article)
            })
            update()
        } catch let error {
            DDLogError("Error removing all articles from default list: \(error)")
        }
    }
    
    
    /// Fetches n articles with lead images for a given reading list.
    ///
    /// - Parameters:
    ///   - readingList: reading list that the articles belong to.
    ///   - limit: number of articles with lead images to fetch.
    /// - Returns: array of articles with lead images.
    public func articlesWithLeadImages(for readingList: ReadingList, limit: Int) throws -> [WMFArticle] {
        assert(Thread.isMainThread)
        let moc = dataStore.viewContext
        let request: NSFetchRequest<WMFArticle> = WMFArticle.fetchRequest()
        request.predicate = NSPredicate(format: "ANY readingLists == %@ && imageURLString != NULL", readingList)
        request.sortDescriptors = [NSSortDescriptor(key: "savedDate", ascending: false)]
        request.fetchLimit = limit
        return try moc.fetch(request)
    }
    
    internal func createOrUpdate(remoteReadingLists: [APIReadingList], inManagedObjectContext moc: NSManagedObjectContext) throws -> Date {
        var sinceDate: Date = Date.distantPast

        // Arrange remote lists by ID and name for merging with local lists
        var remoteReadingListsByID: [Int64: APIReadingList] = [:]
        var remoteReadingListsByName: [String: APIReadingList] = [:]
        for remoteReadingList in remoteReadingLists {
            if let date = DateFormatter.wmf_iso8601().date(from: remoteReadingList.updated),
                date.compare(sinceDate) == .orderedDescending {
                sinceDate = date
            }
            remoteReadingListsByID[remoteReadingList.id] = remoteReadingList
            remoteReadingListsByName[remoteReadingList.name.precomposedStringWithCanonicalMapping] = remoteReadingList
        }
        
        let localReadingListsFetch: NSFetchRequest<ReadingList> = ReadingList.fetchRequest()
        let canonicalNames = Array(remoteReadingListsByName.keys).map { $0.precomposedStringWithCanonicalMapping }
        localReadingListsFetch.predicate = NSPredicate(format: "readingListID IN %@ || canonicalName IN %@", Array(remoteReadingListsByID.keys), canonicalNames)
        let localReadingLists = try moc.fetch(localReadingListsFetch)
        for localReadingList in localReadingLists {
            var remoteReadingList: APIReadingList?
            if let localReadingListID = localReadingList.readingListID?.int64Value {
                // remove from the dictionary because we will create any lists left in the dictionary
                remoteReadingList = remoteReadingListsByID.removeValue(forKey: localReadingListID)
                if let remoteReadingListName = remoteReadingList?.name {
                    remoteReadingListsByName.removeValue(forKey: remoteReadingListName)
                }
            }
            
            if remoteReadingList == nil {
                if let localReadingListName = localReadingList.name?.precomposedStringWithCanonicalMapping {
                    remoteReadingList = remoteReadingListsByName.removeValue(forKey: localReadingListName)
                    if let remoteReadingListID = remoteReadingList?.id {
                        // remove from the dictionary because we will create any lists left in this dictionary
                        remoteReadingListsByID.removeValue(forKey: remoteReadingListID)
                    }
                }
            }

            guard let remoteReadingListForUpdate = remoteReadingList else {
                DDLogError("Fetch produced a list without a matching id or name: \(localReadingList)")
                assert(false)
                continue
            }
            
            let isDeleted = remoteReadingListForUpdate.deleted ?? false
            if isDeleted {
                try markLocalDeletion(for: [localReadingList])
                moc.delete(localReadingList) // object can be removed since we have the server-side update
            } else {
                localReadingList.update(with: remoteReadingListForUpdate)
            }
        }
        
        
        // create any list that wasn't matched by ID or name
        for (_, remoteReadingList) in remoteReadingListsByID {
            let isDeleted = remoteReadingList.deleted ?? false
            guard !isDeleted else {
                continue
            }
            guard let localList = NSEntityDescription.insertNewObject(forEntityName: "ReadingList", into: moc) as? ReadingList else {
                continue
            }
            localList.update(with: remoteReadingList)
        }
        
        return sinceDate
    }
    
    internal func createOrUpdate(remoteReadingListEntries: [APIReadingListEntry], for readingListID: Int64? = nil, inManagedObjectContext moc: NSManagedObjectContext) throws -> Date {
        var sinceDate: Date = Date.distantPast

        // Arrange remote list entries by ID and key for merging with local lists
        var remoteReadingListEntriesByID: [Int64: APIReadingListEntry] = [:]
        var remoteReadingListEntriesByListIDAndArticleKey: [Int64: [String: APIReadingListEntry]] = [:]
        var allArticleKeys: Set<String> = []
        for remoteReadingListEntry in remoteReadingListEntries {
            if let date = DateFormatter.wmf_iso8601().date(from: remoteReadingListEntry.updated),
                date.compare(sinceDate) == .orderedDescending {
                sinceDate = date
            }
            guard let listID = remoteReadingListEntry.listId ?? readingListID, let articleKey = remoteReadingListEntry.articleKey else {
                DDLogError("missing id or article key for remote entry: \(remoteReadingListEntry)")
                assert(false)
                continue
            }

            remoteReadingListEntriesByID[remoteReadingListEntry.id] = remoteReadingListEntry
            allArticleKeys.insert(articleKey)
            remoteReadingListEntriesByListIDAndArticleKey[listID, default: [:]][articleKey] = remoteReadingListEntry
        }

        let localReadingListEntryFetch: NSFetchRequest<ReadingListEntry> = ReadingListEntry.fetchRequest()
        localReadingListEntryFetch.predicate = NSPredicate(format: "readingListEntryID IN %@ || (list.readingListID IN %@ && articleKey IN %@)", Array(remoteReadingListEntriesByID.keys), Array(remoteReadingListEntriesByListIDAndArticleKey.keys), allArticleKeys)
        let localReadingListEntries = try moc.fetch(localReadingListEntryFetch)
        for localReadingListEntry in localReadingListEntries {
            var remoteReadingListEntry: APIReadingListEntry?
            if let localReadingListEntryID = localReadingListEntry.readingListEntryID?.int64Value {
                remoteReadingListEntry = remoteReadingListEntriesByID.removeValue(forKey: localReadingListEntryID)
                if let remoteReadingListKey = remoteReadingListEntry?.articleKey, let remoteReadingListID = remoteReadingListEntry?.listId {
                    remoteReadingListEntriesByListIDAndArticleKey[remoteReadingListID]?.removeValue(forKey: remoteReadingListKey)
                }
            }
            
            if let localReadingListEntryArticleKey = localReadingListEntry.articleKey, let localReadingListEntryListID = localReadingListEntry.list?.readingListID?.int64Value {
                let remoteReadingListEntryForListAndKey = remoteReadingListEntriesByListIDAndArticleKey[localReadingListEntryListID]?.removeValue(forKey: localReadingListEntryArticleKey)
                if let remoteReadingListID = remoteReadingListEntryForListAndKey?.id, remoteReadingListEntry == nil {
                    remoteReadingListEntry = remoteReadingListEntryForListAndKey
                    remoteReadingListEntriesByID.removeValue(forKey: remoteReadingListID)
                }
            }
            
            guard let remoteReadingListEntryForUpdate = remoteReadingListEntry else {
                DDLogError("Fetch produced a list entry without a matching id or name: \(localReadingListEntry)")
                continue
            }
            
            let isDeleted = remoteReadingListEntryForUpdate.deleted ?? false
            if isDeleted {
                try markLocalDeletion(for: [localReadingListEntry]) // updates associated objects
                moc.delete(localReadingListEntry) // object can be removed since we have the server-side update
            } else {
                localReadingListEntry.update(with: remoteReadingListEntryForUpdate)
            }
        }

        // create any list that wasn't matched by ID or name
        try locallyCreate(Array(remoteReadingListEntriesByID.values), in: moc)

        return sinceDate
    }
}


fileprivate extension NSManagedObjectContext {
    var wmf_defaultReadingList: ReadingList {
        guard let defaultReadingList = wmf_fetch(objectForEntityName: "ReadingList", withValue: NSNumber(value: true), forKey: "isDefault") as? ReadingList else {
            DDLogError("Missing default reading list")
            #if DEBUG //allow this to pass on test 
            assert(false)
            #endif
            return wmf_create(entityNamed: "ReadingList", withValue: NSNumber(value: true), forKey: "isDefault") as! ReadingList
        }
        return defaultReadingList
    }
}

public extension NSManagedObjectContext {
    @objc func wmf_fetchDefaultReadingList() -> ReadingList? {
        return  wmf_fetch(objectForEntityName: "ReadingList", withValue: NSNumber(value: true), forKey: "isDefault") as? ReadingList
    }
}

internal extension WMFArticle {
    func fetchReadingListEntries() throws -> [ReadingListEntry] {
        guard let moc = managedObjectContext, let key = key else {
            return []
        }
        let entryFetchRequest: NSFetchRequest<ReadingListEntry> = ReadingListEntry.fetchRequest()
        entryFetchRequest.predicate = NSPredicate(format: "articleKey == %@", key)
        return try moc.fetch(entryFetchRequest)
    }
    
    func fetchDefaultListEntry() throws -> ReadingListEntry? {
        let readingListEntries = try fetchReadingListEntries()
        return readingListEntries.first(where: { (entry) -> Bool in
            return (entry.list?.isDefault?.boolValue ?? false) && !entry.isDeletedLocally
        })
    }
    
    func addToDefaultReadingList() throws {
        guard let moc = self.managedObjectContext else {
            return
        }
        
        guard try fetchDefaultListEntry() == nil else {
            return
        }
        
        let defaultReadingList = moc.wmf_defaultReadingList
        let defaultListEntry = NSEntityDescription.insertNewObject(forEntityName: "ReadingListEntry", into: moc) as? ReadingListEntry
        defaultListEntry?.articleKey = self.key
        defaultListEntry?.list = defaultReadingList
        defaultListEntry?.displayTitle = displayTitle
        defaultListEntry?.isUpdatedLocally = true
        defaultReadingList.addToArticles(self)
        defaultReadingList.updateCountOfEntries()
        readingListsDidChange()
    }
    
    func removeFromDefaultReadingList() throws {
        let entries = try fetchReadingListEntries()
        for entry in entries {
            guard let list = entry.list, list.isDefaultList else {
                return
            }
            entry.isDeletedLocally = true
            entry.isUpdatedLocally = true
            entry.list?.updateCountOfEntries()
            list.removeFromArticles(self)
            readingListsDidChange()
        }
    }
    
    func readingListsDidChange() {
        let readingLists = self.readingLists ?? []
        if readingLists.count == 0 && savedDate != nil {
            savedDate = nil
        } else if readingLists.count > 0 && savedDate == nil {
            savedDate = Date()
        }
    }
}

extension WMFArticle {
    @objc public var isInDefaultList: Bool {
        guard let readingLists = self.readingLists else {
            return false
        }
        return readingLists.filter { $0.isDefaultList }.count > 0
    }
    
    @objc public var isOnlyInDefaultList: Bool {
        return (readingLists ?? []).count == 1 && isInDefaultList
    }
}
