//
//  ViewController.swift
//  GitHubGist
//
//  Created by Dmitriy on 27/03/2017.
//  Copyright © 2017 Dmitriy. All rights reserved.
//

import UIKit
import PINRemoteImage
import SafariServices
import Alamofire
import BRYXBanner

class MainController: UITableViewController {

  
    
    let manager = GitHubAPIManager.sharedInstance
    var gists = [Gist]()
    
    var nextPageURLString: String?
    var isLoading = false
    var dateFormatter = DateFormatter()
    
    var errorBanner: Banner?
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        loadInitialData()
        
    }
    
    func loadGists(urlToLoad: String?) {
        isLoading = true
        
        let completionHandler: (Result<[Gist]>, String?) -> Void = { (result, nextPage) in
            self.isLoading = false
            self.nextPageURLString = nextPage
            
            // tell refresh control it can stop showing up now
            if self.refreshControl != nil,
                self.refreshControl!.isRefreshing {
                self.refreshControl?.endRefreshing()
            }
            
            guard result.error == nil else {
                self.handleLoadGistsError(result.error!)
                return
            }
            
            guard let fetchedGists = result.value else {
                print("no gists fetched")
                return
            }
            if urlToLoad == nil {
                // empty out the gists because we're not loading another page
                self.gists = []
            }
            self.gists += fetchedGists
            
            let path: Path = [.Public][0]
            let success = PersistenceManager.saveArray(arrayToSave: self.gists, path: path)
            if !success {
                self.showOfflineSaveFailedBanner()
            }
            
            let now = Date()
            let updateString = "Last Updated at " + self.dateFormatter.string(from: now)
            self.refreshControl?.attributedTitle = NSAttributedString(string: updateString)
            
            self.tableView.reloadData()
        }
        
        manager.fetchPublicGists(pageToLoad: urlToLoad, completionHandler: completionHandler)
        
    }
    
    func loadInitialData() {
        isLoading = true
        manager.OAuthTokenCompletionHandler = { error in
            guard error == nil else {
                print(error!)
                self.isLoading = false
                
                switch error! {
                case GitHubAPIManagerError.network(let innerError as NSError):
                    // check domain
                    if innerError.domain != NSURLErrorDomain {
                        break
                    }
                    // check code
                    if innerError.code == NSURLErrorNotConnectedToInternet {
                        let path: Path = [.Public][0]
                        if let archived: [Gist] = PersistenceManager.loadArray(path: path) {
                            self.gists = archived
                        }
                        else {
                            self.gists = []
                        }
                        self.tableView.reloadData()
                        
                        self.showNotConnectedBanner()
                        return
                    }
                default:
                    break
                    
                }
                return
            }
            
            self.loadGists(urlToLoad: nil)
        }
        
        
        self.loadGists(urlToLoad: nil)
    }
    
    
    
    
    func handleLoadGistsError(_ error: Error) {
        print(error)
        nextPageURLString = nil
        
        isLoading = false
        
        switch error {
        case GitHubAPIManagerError.authLost:
            return
        case GitHubAPIManagerError.network(let innerError as NSError):
            // check domain
            if innerError.domain != NSURLErrorDomain {
                break
            }
            // check code
            if innerError.code == NSURLErrorNotConnectedToInternet {
                showNotConnectedBanner()
                return
            }
        default:
            break
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        
        // add refresh control for pull to refresh
        if self.refreshControl == nil {
            self.refreshControl = UIRefreshControl()
            self.refreshControl?.attributedTitle = NSAttributedString(string: "Pull to refresh")
            self.refreshControl?.addTarget(self, action: #selector(refresh(sender:)), for: .valueChanged)
            
            self.dateFormatter.dateStyle = .short
            self.dateFormatter.timeStyle = .long
        }
        
        super.viewWillAppear(animated)
    }
    
    
    override func viewWillDisappear(_ animated: Bool) {
        if let existingBanner = self.errorBanner {
            existingBanner.dismiss()
        }
        super.viewWillDisappear(animated)
    }
    
    func insertNewObject(_ sender: Any) {
        let createVC = CreateGistViewController(nibName: nil, bundle: nil)
        self.navigationController?.pushViewController(createVC, animated: true)
    }
    
    func showNotConnectedBanner() {
        if let existingBanner = self.errorBanner {
            existingBanner.dismiss()
        }
        self.errorBanner = Banner(title: "No Internet Connection", subtitle: "Could not load gists. " + " Try again when you're connected to the internet", image: nil, backgroundColor: .red)
        self.errorBanner?.dismissesOnSwipe = true
        self.errorBanner?.show(duration: nil)
    }
    
    func showOfflineSaveFailedBanner() {
        if let existingBanner = self.errorBanner {
            existingBanner.dismiss()
        }
        self.errorBanner = Banner(title: "Could not save gists to view offline", subtitle: "You iOS device is almost out of free space.\n" + "You will only be able to see gists when you have an internet connection.", image: nil, backgroundColor: .orange)
        self.errorBanner?.dismissesOnSwipe = true
        self.errorBanner?.show(duration: nil)
    }
    
    
    
    
    // MARK: - Pull to Refresh
    
    func refresh(sender: Any) {
        manager.isLoadingOAuthToken = false
        manager.clearCache()
        
        nextPageURLString = nil
        loadInitialData()
    }
    
    
    
    
    // MARK: - Table View
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return gists.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        self.navigationItem.leftBarButtonItem = self.editButtonItem
        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(insertNewObject(_:)))
        self.navigationItem.rightBarButtonItem = addButton
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        
        let gist = gists[indexPath.row]
        cell.textLabel?.text = gist.gistDescription
        cell.detailTextLabel?.text = gist.ownerLogin
        
        if let urlString = gist.ownerAvatarURL, let url = URL(string: urlString) {
            
            cell.imageView?.pin_setImage(from: url, placeholderImage: UIImage(named: "place1.png")) { result in
                if let cellToUpdate = self.tableView?.cellForRow(at: indexPath) {
                    cellToUpdate.setNeedsLayout()
                }
            }
        }
        else {
            cell.imageView?.image = UIImage(named: "place1.png")
        }
        
        if !isLoading {
            let rowsLoaded = gists.count
            let rowsRemaining = rowsLoaded - indexPath.row
            let rowsToLoadFromBottom = 5
            
            if rowsRemaining <= rowsToLoadFromBottom {
                if let nextPage = nextPageURLString {
                    self.loadGists(urlToLoad: nextPage)
                }
            }
        }
        
        return cell
    }
    
    
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            
            let gistToDelete = gists[indexPath.row]
            guard let idToDelete = gistToDelete.id else {
                return
            }
            
            gists.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .fade)
            
            // delete from API
            manager.deleteGist(idToDelete) { error in
                if let error = error {
                    print(error)
                }
                // put it back
                self.gists.insert(gistToDelete, at: indexPath.row)
                tableView.insertRows(at: [indexPath], with: .right)
                // tell user that it didn't work
                let alertController = UIAlertController(title: "Could not delet gist", message: "Sorry, your gist couldn't be deleted. Maybe GitHub is " + "down or you don't have an internet connection.", preferredStyle: .alert)
                let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
                alertController.addAction(okAction)
                // show alert
                self.present(alertController, animated: true, completion: nil)
            }
        }
        else if editingStyle == .insert {
            
        }
    }
    
}

