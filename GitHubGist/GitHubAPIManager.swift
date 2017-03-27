//
//  GitHubAPIManager.swift
//  GitHubGist
//
//  Created by Dmitriy on 27/03/2017.
//  Copyright © 2017 Dmitriy. All rights reserved.
//

import Foundation
import Locksmith
import Alamofire

enum GitHubAPIManagerError: Error {
    case network(error: Error)
    case apiProvidedError(reason: String)
    case authCouldNot(reason: String)
    case authLost(reason: String)
    case objectSerialization(reason: String)
}

enum GistRouter: URLRequestConvertible {
    static let baseURLString = "https://api.github.com"
    
    case getPublic()
    case getMyStarred()
    case getMine()
    case getAtPath(String)
    case isStarred(String)
    case star(String)
    case unstar(String)
    case delete(String)
    case create([String: Any])
    
    func asURLRequest() throws -> URLRequest {
        
        var method: HTTPMethod {
            switch self {
            case .getPublic, .getAtPath, .getMyStarred, .getMine, .isStarred:
                return .get
            case .star:
                return .put
            case .unstar, .delete:
                return .delete
            case .create:
                return .post
            }
        }
        
        let url: URL = {
            let relativePath: String
            switch self {
            case .getAtPath(let path):
                // already have full URL, so just return it
                return URL(string: path)!
            case .getPublic():
                relativePath = "gists/public"
            case .getMyStarred():
                relativePath = "gists/starred"
            case .getMine():
                relativePath = "gists"
            case .isStarred(let id):
                relativePath = "gists/\(id)/star"
            case .star(let id):
                relativePath = "gists/\(id)/star"
            case .unstar(let id):
                relativePath = "gists/\(id)/star"
            case .delete(let id):
                relativePath = "gists/\(id)"
            case .create:
                relativePath = "gists"
            }
            
            var url = URL(string: GistRouter.baseURLString)!
            url.appendPathComponent(relativePath)
            return url
        }()
        
        let params: ([String: Any]?) = {
            switch self {
            case .getPublic, .getAtPath, .getMyStarred, .getMine, .isStarred, .star, .unstar, .delete:
                return nil
            case .create(let params):
                return (params)
            }
        }()
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue
        
        // set OAuth token if we have one
        if let token = GitHubAPIManager.sharedInstance.OAuthToken {
            urlRequest.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let encoding = JSONEncoding.default
        return try encoding.encode(urlRequest, with: params)
    }
}


class GitHubAPIManager {
    static let sharedInstance = GitHubAPIManager()
    
    let clientID: String = ""
    let clientSecret: String = ""
    
    var isLoadingOAuthToken = false
    
    // handler for the OAuth process
    var OAuthTokenCompletionHandler:((Error?) -> Void)?
    
    var OAuthToken: String? {
        set {
            guard let newValue = newValue else {
                let _ = try? Locksmith.deleteDataForUserAccount(userAccount: "github")
                return
            }
            guard let _ = try? Locksmith.updateData(data: ["token": newValue], forUserAccount: "github") else {
                let _ = try? Locksmith.deleteDataForUserAccount(userAccount: "github")
                return
            }
        }
        get {
            // try lo load from keychain
            let dictionary = Locksmith.loadDataForUserAccount(userAccount: "github")
            return dictionary?["token"] as? String
        }
    }
    
    
    func printPublicGists() -> Void {
        Alamofire.request(GistRouter.getPublic())
            .responseString { response in
                if let receivedString = response.result.value {
                    print(receivedString)
                }
        }
    }
    
    func fetchPublicGists(pageToLoad: String?, completionHandler: @escaping(Result<[Gist]>, String?) -> Void) {
        if let urlString = pageToLoad {
            fetchGists(GistRouter.getAtPath(urlString), completionHandler: completionHandler)
        }
        else {
            fetchGists(GistRouter.getPublic(), completionHandler: completionHandler)
        }
    }
    
    func fetchMyStarredGists(pageToLoad: String?, completionHandler: @escaping(Result<[Gist]>, String?) -> Void) {
        if let urlString = pageToLoad {
            fetchGists(GistRouter.getAtPath(urlString), completionHandler: completionHandler)
        }
        else {
            fetchGists(GistRouter.getMyStarred(), completionHandler: completionHandler)
        }
    }
    
    func fetchMyGists(pageToLoad: String?, completionHandler: @escaping(Result<[Gist]>, String?) -> Void) {
        if let urlString = pageToLoad {
            fetchGists(GistRouter.getAtPath(urlString), completionHandler: completionHandler)
        }
        else {
            fetchGists(GistRouter.getMine(), completionHandler: completionHandler)
        }
    }
    
    
    
    func fetchGists(_ urlRequest: URLRequestConvertible, completionHandler: @escaping(Result<[Gist]>, String?) -> Void) {
        Alamofire.request(urlRequest)
            .responseJSON { response in
                
                if let urlResponse = response.response,
                    let authError = self.checkUnauthorized(urlResponse: urlResponse) {
                    completionHandler(.failure(authError), nil)
                    return
                }
                
                let result = self.gistArrayFromResponse(response)
                let next = self.parseNextPageFromHeaders(response: response.response)
                completionHandler(result, next)
        }
    }
    
    func imageFrom(_ urlString: String, completionHandler: @escaping(UIImage?, Error?) -> Void) {
        let _ = Alamofire.request(urlString)
            .response { dataResponse in
                guard let data = dataResponse.data else {
                    completionHandler(nil, dataResponse.error)
                    return
                }
                
                let image = UIImage(data: data)
                completionHandler(image, nil)
        }
    }
    
    func clearCache() -> Void {
        let cache = URLCache.shared
        cache.removeAllCachedResponses()
    }
    
    func hasOAuthToken() -> Bool {
        if let token = self.OAuthToken {
            return !token.isEmpty
        }
        return false
    }
    
    func URLToStartOAuth2Login() -> URL? {
        let authPath: String = "https://github.com/login/oauth/authorize" +
        "?client_id=\(clientID)&scope=gist&state=TEST_STATE"
        return URL(string: authPath)
    }
    
    func processOAuthStep1Response(_ url: URL) {
        // extract code from URL
        guard let code = extractCodeFromAuthStep1Response(url) else {
            self.isLoadingOAuthToken = false
            let error = GitHubAPIManagerError.authCouldNot(reason: "Could not obtain an OAuth token")
            self.OAuthTokenCompletionHandler?(error)
            return
        }
        swapAuthCodeForToken(code: code)
    }
    
    func swapAuthCodeForToken(code: String) {
        let getTokenPath = "https://github.com/login/oauth/access_token"
        let tokenParams = [ "client_id": clientID, "client_secret": clientSecret, "code": code ]
        let jsonHeader = [ "Accept": "application/json" ]
        
        Alamofire.request(getTokenPath, method: .post, parameters: tokenParams, encoding: URLEncoding.default, headers: jsonHeader)
            .responseJSON { response in
                //print(response)
                guard response.result.error == nil else {
                    print(response.result.error!)
                    self.isLoadingOAuthToken = false
                    let errorMessage = response.result.error?.localizedDescription ?? "Could not obtain an OAuth token"
                    let error = GitHubAPIManagerError.authCouldNot(reason: errorMessage)
                    self.OAuthTokenCompletionHandler?(error)
                    return
                }
                guard let value = response.result.value else {
                    print("no string received in response when swapping oauth code for token")
                    self.isLoadingOAuthToken = false
                    let error = GitHubAPIManagerError.authCouldNot(reason: "Could not obtain an OAuth token")
                    self.OAuthTokenCompletionHandler?(error)
                    return
                }
                guard let jsonResult = value as? [String: String] else {
                    print("no data received or data not JSON")
                    self.isLoadingOAuthToken = false
                    let error = GitHubAPIManagerError.authCouldNot(reason: "Could not obtain an OAuth token")
                    self.OAuthTokenCompletionHandler?(error)
                    return
                }
                
                self.OAuthToken = self.parseOAuthTokenResponse(jsonResult)
                self.isLoadingOAuthToken = false
                
                if self.hasOAuthToken() {
                    self.OAuthTokenCompletionHandler?(nil)
                }
                else {
                    let error = GitHubAPIManagerError.authCouldNot(reason: "Could not obtain an OAuth token")
                    self.OAuthTokenCompletionHandler?(error)
                }
        }
    }
    
    func extractCodeFromAuthStep1Response(_ url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var code: String?
        
        guard let queryItems = components?.queryItems else {
            return nil
        }
        for queryItem in queryItems {
            if queryItem.name.lowercased() == "code" {
                code = queryItem.value
                break
            }
        }
        return code
    }
    
    func parseOAuthTokenResponse(_ json: [String:String]) -> String? {
        var token: String?
        
        for (key, value) in json {
            switch key {
            case "access_token":
                token = value
            case "scope":
                print("SET SCOPE")
            case "token_type":
                print("CHECK IF BEARER")
            default:
                print("got more than expected from the OAuth token exchange")
                print(key)
            }
        }
        return token
    }
    
    func checkUnauthorized(urlResponse: HTTPURLResponse) -> (Error?) {
        if urlResponse.statusCode == 401 {
            self.OAuthToken = nil
            return GitHubAPIManagerError.authLost(reason: "Not logged in")
        }
        return nil
    }
    
    func isAPIOnline(completionHandler: @escaping(Bool) -> Void) {
        Alamofire.request(GistRouter.baseURLString)
            .validate(statusCode: 200..<300)
            .response { response in
                guard response.error == nil else {
                    // no internet connection or GitHub API is down
                    completionHandler(false)
                    return
                }
                completionHandler(true)
        }
    }
    
    func deleteGist(_ gistId: String, completionHandler: @escaping (Error?) -> Void) {
        Alamofire.request(GistRouter.delete(gistId))
            .response { response in
                if let urlResponse = response.response,
                    let authError = self.checkUnauthorized(urlResponse: urlResponse) {
                    completionHandler(authError)
                    return
                }
                if let error = response.error {
                    print(error)
                }
                self.clearCache()
                completionHandler(response.error)
        }
    }
    
    func createNewGist(description: String, isPublic: Bool, files: [File], completionHandler: @escaping (Result<Bool>) -> Void) {
        let publicString = isPublic ? "true" : "false"
        
        var filesDictionary = [String: Any]()
        for file in files {
            if let name = file.filename, let content = file.content {
                filesDictionary[name] = ["content": content]
            }
        }
        
        let parameters: [String: Any] = [
            "description": description,
            "isPublic": publicString,
            "files": filesDictionary
        ]
        
        Alamofire.request(GistRouter.create(parameters))
            .response { response in
                if let urlResponse = response.response,
                    let authError = self.checkUnauthorized(urlResponse: urlResponse) {
                    completionHandler(.failure(authError))
                    return
                }
                guard response.error == nil else {
                    print(response.error!)
                    completionHandler(.failure(response.error!))
                    return
                }
                self.clearCache()
                completionHandler(.success(true))
        }
    }
    
    // MARK: Starring / Unstarring / Star status
    func isGistStarred(_ gistId: String, completionHandler: @escaping (Result<Bool>) -> Void) {
        Alamofire.request(GistRouter.isStarred(gistId))
            .validate(statusCode: [204])
            .response { response in
                if let urlResponse = response.response,
                    let authError = self.checkUnauthorized(urlResponse: urlResponse) {
                    completionHandler(.failure(authError))
                    return
                }
                // 204 if starred, 404 if not
                if let error = response.error {
                    print(error)
                    if response.response?.statusCode == 404 {
                        completionHandler(.success(false))
                        return
                    }
                    completionHandler(.failure(error))
                    return
                }
                completionHandler(.success(true))
        }
    }
    
    func starGist(_ gistId: String, completionHandler: @escaping (Error?) -> Void) {
        Alamofire.request(GistRouter.star(gistId))
            .response { response in
                if let urlResponse = response.response,
                    let authError = self.checkUnauthorized(urlResponse: urlResponse) {
                    completionHandler(authError)
                    return
                }
                if let error = response.error {
                    print(error)
                }
                completionHandler(response.error)
        }
    }
    
    func unstarGist(_ gistId: String, completionHandler: @escaping (Error?) -> Void) {
        Alamofire.request(GistRouter.unstar(gistId))
            .response { response in
                if let urlResponse = response.response,
                    let authError = self.checkUnauthorized(urlResponse: urlResponse) {
                    completionHandler(authError)
                    return
                }
                if let error = response.error {
                    print(error)
                }
                completionHandler(response.error)
        }
    }
    
    
    func printMyStarredGistsWithOAuth2() -> Void {
        Alamofire.request(GistRouter.getMyStarred())
            .responseString { response in
                guard let receivedString = response.result.value else {
                    print("didn't get a string in the response")
                    return
                }
                print(receivedString)
        }
    }
    
    func printMyStarredGistsWithBasicAuth() -> Void {
        Alamofire.request(GistRouter.getMyStarred())
            .responseString { response in
                guard let receivedString = response.result.value else {
                    print("didn't get a string in the response")
                    return
                }
                print(receivedString)
        }
    }
    
    private func gistArrayFromResponse(_ response: DataResponse<Any>) -> Result<[Gist]> {
        guard response.result.error == nil else {
            print(response.result.error!)
            return .failure(GitHubAPIManagerError.network(error: response.result.error!))
        }
        
        guard let jsonArray = response.result.value as? [[String: Any]] else {
            print("didn't get array of gists object as JSON from API")
            return .failure(GitHubAPIManagerError.objectSerialization(reason: "Didn't get JSON dictionary in response"))
        }
        
        // check for "message" errors in JSON
        if let jsonDictionary = response.result.value as? [String: Any],
            let errorMessage = jsonDictionary["message"] as? String {
            return .failure(GitHubAPIManagerError.apiProvidedError(reason: errorMessage))
        }
        
        let gists = jsonArray.flatMap { Gist(json: $0) }
        return .success(gists)
    }
    
    private func parseNextPageFromHeaders(response: HTTPURLResponse?) -> String? {
        
        guard let linkHeader = response?.allHeaderFields["Link"] as? String else {
            return nil
        }
        
        let components = linkHeader.characters.split { $0 == "," }.map { String($0) }
        for item in components {
            // see if its "next"
            let rangeOfNext = item.range(of: "rel=\"next\"", options: [])
            guard rangeOfNext != nil else {
                continue
            }
            
            // this is the "next" item, extract URL
            let rangeOfPaddedURL = item.range(of: "<(.*)>;", options: .regularExpression, range: nil, locale: nil)
            guard let range = rangeOfPaddedURL else {
                return nil
            }
            
            let nextURL = item.substring(with: range)
            
            // strip off the < and >;
            let start = nextURL.index(range.lowerBound, offsetBy: 1)
            let end = nextURL.index(range.upperBound, offsetBy: -2)
            let trimmedRange = start..<end
            
            return nextURL.substring(with: trimmedRange)
        }
        return nil
    }
}
