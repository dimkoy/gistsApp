//
//  PersistenceManager.swift
//  GitHubGist
//
//  Created by Dmitriy on 27/03/2017.
//  Copyright © 2017 Dmitriy. All rights reserved.
//

import Foundation

enum Path: String {
    case Public = "Public"
}

class PersistenceManager {
    class func saveArray<T: NSCoding>(arrayToSave: [T], path: Path) -> Bool {
        let file = documentsDirectory().appendingPathComponent(path.rawValue)
        return NSKeyedArchiver.archiveRootObject(arrayToSave, toFile: file)
    }
    
    class func loadArray<T: NSCoding>(path: Path) -> [T]? {
        let file = documentsDirectory().appendingPathComponent(path.rawValue)
        let result = NSKeyedUnarchiver.unarchiveObject(withFile: file)
        return result as? [T]
    }
    
    class private func documentsDirectory() -> NSString {
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        let documentDirectory = paths[0] as NSString
        return documentDirectory
    }
}
