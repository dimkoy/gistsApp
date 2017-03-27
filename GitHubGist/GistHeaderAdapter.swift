//
//  GistHeaderAdapter.swift
//  GitHubGist
//
//  Created by Dmitriy on 27/03/2017.
//  Copyright © 2017 Dmitriy. All rights reserved.
//

import Foundation
import Alamofire

class GistHeaderAdapter: RequestAdapter {
    
    func adapt(_ urlRequest: URLRequest) throws -> URLRequest {
        var urlRequest = urlRequest
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        
        return urlRequest
    }
}
