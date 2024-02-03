import Foundation

public final class WKGrowthTasksDataController {

    private var service = WKDataEnvironment.current.mediaWikiService
    let project: WKProject

    public init (project: WKProject) {
        self.project = project
    }

    // MARK: GET Methods

    // TODO: to get more tasks, send used IDS to `ggtexcludepageids` parameter
    // TODO: remove debug prints
    public func getGrowthAPITask(task: WKGrowthTaskType = .imageRecommendation, completion: @escaping (Result<[WKGrowthTask.Page], Error>) -> Void) {

        guard let service else {
            completion(.failure(WKDataControllerError.mediaWikiServiceUnavailable))
            return
        }
        var pages: [WKGrowthTask.Page] = []

        let parameters = [ "action": "query",
                           "generator": "growthtasks",
                           "formatversion": "2",
                           "format": "json",
                           "ggttasktypes": "\(task.rawValue)",
                           "ggtlimit": "10"
        ]

        guard let url = URL.mediaWikiAPIURL(project: project) else {
            completion(.failure(WKDataControllerError.failureCreatingRequestURL))
            return
        }

        let request = WKMediaWikiServiceRequest(url: url, method: .GET, parameters: parameters)
        service.performDecodableGET(request: request) { (result: Result<WKGrowthTaskAPIResponse, Error>) in

            switch result {
            case .success(let response):
                print(response)
                pages.append(contentsOf: self.getTaskPages(from: response))
                completion(.success(pages))
            case .failure(let error):
                print(error)
                completion(.failure(error))
            }
        }
    }

    public func getImageSuggestionData(pageIDs: [String], completion: @escaping (Result<[WKImageRecommendation.Page], Error>) -> Void) {

        let pipeEncodedPageIds = pageIDs.joined(separator: "|")
        var recommendationsPerPage: [WKImageRecommendation.Page] = []

        guard let service else {
            completion(.failure(WKDataControllerError.mediaWikiServiceUnavailable))
            return
        }

        let parameters = [ "action": "query",
                           "formatversion": "2",
                           "format": "json",
                           "prop":"growthimagesuggestiondata",
                           "pageids" : pipeEncodedPageIds,
                           "gisdtasktype": "image-recommendation"
        ]

        guard let url = URL.mediaWikiAPIURL(project: project) else {
            completion(.failure(WKDataControllerError.failureCreatingRequestURL))
            return
        }

        let request = WKMediaWikiServiceRequest(url: url, method: .GET, parameters: parameters)
        service.performDecodableGET(request: request) { (result: Result<WKImageRecommendationAPIResponse, Error>) in

            switch result {
            case .success(let response):
                print(response)
                recommendationsPerPage.append(contentsOf: self.getImageSuggestions(from: response))
                completion(.success(recommendationsPerPage))
            case .failure(let error):
                print(error)
                completion(.failure(error))
            }
        }
    }

    // MARK: Private methods

    fileprivate func getImageSuggestions(from response: WKImageRecommendationAPIResponse) -> [WKImageRecommendation.Page] {
        var recommendationsPerPage:[WKImageRecommendation.Page] = []

        for page in response.query.pages {

            let page = WKImageRecommendation.Page(
                pageid: page.pageid,
                title: page.title,
                growthimagesuggestiondata: getGrowthAPIImageSuggestions(for: page))

            recommendationsPerPage.append(page)
        }

        return recommendationsPerPage

    }

   fileprivate func getGrowthAPIImageSuggestions(for page: WKImageRecommendationAPIResponse.Page) -> [WKImageRecommendation.GrowthImageSuggestionData] {
        var suggestions: [WKImageRecommendation.GrowthImageSuggestionData] = []

        for item in page.growthimagesuggestiondata {
            let item = WKImageRecommendation.GrowthImageSuggestionData(
                titleNamespace: item.titleNamespace,
                titleText: item.titleText,
                images: getImageSuggestionData(from: item))

            suggestions.append(item)

        }
        return suggestions
    }

    fileprivate func getImageSuggestionData(from suggestion: WKImageRecommendationAPIResponse.GrowthImageSuggestionData) -> [WKImageRecommendation.ImageSuggestion] {
        var images: [WKImageRecommendation.ImageSuggestion] = []

        for image in suggestion.images {
            let imageSuggestion = WKImageRecommendation.ImageSuggestion(
                image: image.image,
                displayFilename: image.displayFilename,
                source: image.source,
                projects: image.projects,
                metadata: getMetadataObject(from: image.metadata))
            images.append(imageSuggestion)
        }

        return images
    }

    fileprivate func getMetadataObject(from image: WKImageRecommendationAPIResponse.ImageMetadata) -> WKImageRecommendation.ImageMetadata {
        let metadata = WKImageRecommendation.ImageMetadata(descriptionUrl: image.descriptionUrl, thumbUrl: image.thumbUrl, fullUrl: image.fullUrl, originalWidth: image.originalWidth, originalHeight: image.originalHeight, mediaType: image.mediaType, description: image.description, author: image.author, license: image.license, date: image.date, caption: image.caption, categories: image.categories, reason: image.reason, contentLanguageName: image.contentLanguageName)

        return metadata
    }

    fileprivate func getTaskPages(from response: WKGrowthTaskAPIResponse) -> [WKGrowthTask.Page] {
        var pages: [WKGrowthTask.Page] = []

        for page in response.query.pages {
            let page = WKGrowthTask.Page(
                pageid: page.pageid,
                title: page.title,
                tasktype: page.tasktype,
                difficulty: page.difficulty)
            pages.append(page)
        }
        return pages
    }
}

// MARK: Types

public enum WKGrowthTaskType: String {
    case imageRecommendation = "image-recommendation"
}
