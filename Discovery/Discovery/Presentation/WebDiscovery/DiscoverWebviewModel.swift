//
//  DiscoverWebviewModel.swift
//  Discovery
//
//  Created by SaeedBashir on 12/16/23.
//

import Foundation
import Core
import WebKit
import SwiftUI
import Swinject

public class DiscoveryWebviewModel: ObservableObject {
    @Published var courseDetails: CourseDetails?
    @Published private(set) var showProgress = false
    @Published var showError: Bool = false
    var errorMessage: String? {
        didSet {
            withAnimation {
                showError = errorMessage != nil
            }
        }
    }
    
    let router: DiscoveryRouter
    let config: ConfigProtocol
    let connectivity: ConnectivityProtocol
    private let interactor: DiscoveryInteractorProtocol
    private let analytics: DiscoveryAnalytics
    var request: URLRequest?
    private let storage: CoreStorage
    var sourceScreen: LogistrationSourceScreen
    
    var userloggedIn: Bool {
        return !(storage.user?.username?.isEmpty ?? true)
    }
    
    public init(
        router: DiscoveryRouter,
        config: ConfigProtocol,
        interactor: DiscoveryInteractorProtocol,
        connectivity: ConnectivityProtocol,
        analytics: DiscoveryAnalytics,
        storage: CoreStorage,
        sourceScreen: LogistrationSourceScreen = .default
    ) {
        self.router = router
        self.config = config
        self.interactor = interactor
        self.connectivity = connectivity
        self.analytics = analytics
        self.storage = storage
        self.sourceScreen = sourceScreen
    }
    
    @MainActor
    func getCourseDetail(courseID: String) async throws -> CourseDetails? {
        return try await interactor.getCourseDetails(courseID: courseID)
    }
    
    @MainActor
    func enrollTo(courseID: String) async {
        do {
            guard userloggedIn else {
                router.showRegisterScreen(sourceScreen: .discovery)
                return
            }
            
            showProgress = true
            if courseDetails == nil {
                courseDetails = try await getCourseDetail(courseID: courseID)
            }
            
            if courseDetails?.isEnrolled ?? false || courseState == .alreadyEnrolled {
                showProgress = false
                showCourseDetails()
                return
            }
            
            analytics.courseEnrollClicked(courseId: courseID, courseName: courseDetails?.courseTitle ?? "")
            _ = try await interactor.enrollToCourse(courseID: courseID)
            analytics.courseEnrollSuccess(courseId: courseID, courseName: courseDetails?.courseTitle ?? "")
            courseDetails?.isEnrolled = true
            showProgress = false
            NotificationCenter.default.post(name: .onCourseEnrolled, object: courseID)
            showCourseDetails()
        } catch let error {
            showProgress = false
            if error.isInternetError || error is NoCachedDataError {
                errorMessage = CoreLocalization.Error.slowOrNoInternetConnection
            } else {
                errorMessage = CoreLocalization.Error.unknownError
            }
        }
    }
    
    private var courseState: CourseState? {
        guard courseDetails?.isEnrolled == false else { return nil }
        
        if let enrollmentStart = courseDetails?.enrollmentStart, let enrollmentEnd = courseDetails?.enrollmentEnd {
            let enrollmentsRange = DateInterval(start: enrollmentStart, end: enrollmentEnd)
            if enrollmentsRange.contains(Date()) {
                return .enrollOpen
            } else {
                return .enrollClose
            }
        } else {
            return .enrollOpen
        }
    }
}

extension DiscoveryWebviewModel: WebViewNavigationDelegate {
    public func webView(
        _ webView: WKWebView,
        shouldLoad request: URLRequest,
        navigationAction: WKNavigationAction
    ) -> Bool {
        guard let URL = request.url else { return false }
        
        if let urlAction = urlAction(from: URL),
           handleNavigation(url: URL, urlAction: urlAction) {
            return true
        }
        
        let capturedLink = navigationAction.navigationType == .linkActivated
        let outsideLink = (request.mainDocumentURL?.host != self.request?.url?.host)
        var externalLink = false
        
        if let queryParameters = request.url?.queryParameters,
            let externalLinkValue = queryParameters["external_link"] as? String,
           externalLinkValue.caseInsensitiveCompare("true") == .orderedSame {
            externalLink = true
        }
        
        if let url = request.url, outsideLink || capturedLink || externalLink, UIApplication.shared.canOpenURL(url) {
            DispatchQueue.main.async { [weak self] in
                self?.router.presentAlert(
                    alertTitle: DiscoveryLocalization.Alert.leavingAppTitle,
                    alertMessage: DiscoveryLocalization.Alert.leavingAppMessage,
                    positiveAction: CoreLocalization.Webview.Alert.continue,
                    onCloseTapped: {
                        self?.router.dismiss(animated: true)
                    }, okTapped: {
                        UIApplication.shared.open(url, options: [:])
                    }, type: .default(positiveAction: CoreLocalization.Webview.Alert.continue)
                )
            }
            return true
        }
        
        return false
    }
    
    private func urlAction(from url: URL) -> WebviewActions? {
        guard url.isValidAppURLScheme,
                let url = WebviewActions(rawValue: url.appURLHost) else { return nil }
        return url
    }
    
    private  func handleNavigation(url: URL, urlAction: WebviewActions) -> Bool {
        switch urlAction {
        case .courseEnrollment:
            if let urlData = parse(url: url), let courseID = urlData.courseId {
                Task {
                    await enrollTo(courseID: courseID)
                }
            }
        case .courseDetail:
            guard let pathID = detailPathID(from: url) else { return false }
            router.showWebDiscoveryDetails(
                pathID: pathID,
                discoveryType: .courseDetail(pathID),
                sourceScreen: sourceScreen
            )
        case .enrolledCourseDetail:
            return showCourseDetails()
            
        case .programDetail:
            guard let pathID = programDetailPathId(from: url) else { return false }
            router.showWebDiscoveryDetails(
                pathID: pathID,
                discoveryType: .programDetail(pathID),
                sourceScreen: sourceScreen
            )
            
        default:
            break
        }
        
        return true
    }
    
    private func detailPathID(from url: URL) -> String? {
        guard url.isValidAppURLScheme,
              let path = url.queryParameters?[URLParameterKeys.pathId] as? String,
              url.appURLHost == WebviewActions.courseDetail.rawValue else { return nil }
        
        return path
    }
    
    private func parse(url: URL) -> (courseId: String?, emailOptIn: Bool)? {
        guard url.isValidAppURLScheme else { return nil }
        
        let courseId = url.queryParameters?[URLParameterKeys.courseId] as? String
        let emailOptIn = (url.queryParameters?[URLParameterKeys.emailOptIn] as? String).flatMap {Bool($0)}
        
        return (courseId, emailOptIn ?? false)
    }
    
    private func programDetailPathId(from url: URL) -> String? {
        guard url.isValidAppURLScheme,
              let path = url.queryParameters?[URLParameterKeys.pathId] as? String,
              url.appURLHost == WebviewActions.programDetail.rawValue else { return nil }
        
        return path
    }
    
    @discardableResult private func showCourseDetails() -> Bool {
        guard let courseDetails = courseDetails else { return false }
        
        router.showCourseScreens(
            courseID: courseDetails.courseID,
            isActive: nil,
            courseStart: courseDetails.courseStart,
            courseEnd: courseDetails.courseEnd,
            enrollmentStart: courseDetails.enrollmentStart,
            enrollmentEnd: courseDetails.enrollmentEnd,
            title: courseDetails.courseTitle
        )
        
        return true
    }
}
