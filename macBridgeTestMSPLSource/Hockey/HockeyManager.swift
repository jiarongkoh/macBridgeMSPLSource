//
//  HockeyClient.swift
//  HockeyUploadTest
//
//  Created by Koh Jia Rong on 2019/5/9.
//  Copyright © 2019 Koh Jia Rong. All rights reserved.
//

import Foundation

enum ErrorResponse: Int {
    case CrashErrorUnknown = 0,
    CrashAPIReceivedEmptyResponse,
    CrashAPIErrorWithStatusCode,
    CrashAPIAppVersionRejected
}

@objcMembers
class HockeyManager: NSObject {
    
    //MARK:- Attributes
    var session = URLSession.shared

    let fileManager = FileManager.default
    let keychain = KeychainSwift()

    var crashFiles = [String]()
    var approvedCrashReports = [String: Bool]()
    var settingsFile = ""
    
    override init() {
        super.init()
        
        settingsFile = (NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? "") + "/\(CRASH_SETTINGS)"
        loadSettings()
    }
    
    //MARK:- Settings and Metadata
    
    func loadSettings() {
        NSLog("Loading settings")

        if !fileManager.fileExists(atPath: settingsFile) {
            NSLog("Settings file does not exist.")
            return
        }
        
        ///Extract values from keychain
        ///Hockey has extraction of default username and email to pre-populate the fields
        
        ///Extract all approved crash reports that were not successfully sent previously from plist
        var format = PropertyListSerialization.PropertyListFormat.xml
        var dictionary: [String: AnyObject] = [:]
        
        if let plistXML = fileManager.contents(atPath: settingsFile) {
            do {
                dictionary = try PropertyListSerialization.propertyList(from: plistXML, options: .mutableContainersAndLeaves, format: &format) as! [String: AnyObject]
                approvedCrashReports = dictionary[HOCKEY_CRASH_APPROVED_REPORTS] as? [String : Bool] ?? [:]
            } catch {
                print(error.localizedDescription)
            }
        }
    }
    
    func saveSettings() {
        NSLog("Saving settings...")
        
        let dictionaryToSave: [String: AnyObject] = [HOCKEY_CRASH_APPROVED_REPORTS: approvedCrashReports as AnyObject]
        let data = NSDictionary(dictionary: dictionaryToSave)
        data.write(toFile: settingsFile, atomically: true)
    }
    
    func storeMetaDataForCrashReport(with filename: String) {
        
        //TODO: Update metadata information, ie username, userid, email
        let username = fileManager.homeDirectoryForCurrentUser.lastPathComponent
        let email = "hui@edison.tech"
        keychain.set(username, forKey: keyFor(metadata: .userId, with: filename))
        keychain.set(username, forKey: keyFor(metadata: .username, with: filename))
        keychain.set(email, forKey: keyFor(metadata: .email, with: filename))
    }
    
    //MARK:- Manage Crash Reports
    
    ///Store crash report and user's metadata
    func approveCrashReport(with filename: String) {
        approvedCrashReports[filename] = false
        storeMetaDataForCrashReport(with: filename)
        saveSettings()
    }
    
    ///Main function to manage the crash reports
    func handleCrashReports() {
        //Map crashReports from plist that have not been uploaded successfully, ie bool = false
        crashFiles = approvedCrashReports.filter{($0.value == false)}.map({ (filename, _) -> String in
            return filename
        })
            
        sendNextCrashReport()
        
        //CrashFiles that were successfully uploaded to HockeyApp, but deletion failed
        let undeletedCrashFiles = approvedCrashReports.filter{($0.value == true)}.map({ (filename, _) -> String in
            return filename
        })

        undeletedCrashFiles.forEach { (filename) in
            cleanCrashReport(with: filename)
        }
    }
    
    ///Remove crash log file and metadata from Documents directory and keychain
    func cleanCrashReport(with filename: String) {
        if filename.isEmpty {
            return
        }
        
        // Remove uploaded crash log from Documents directory
        let fileManager = FileManager.default
        do {
            try fileManager.removeItem(atPath: filename)
            
            //Remove metadata from keychain
            keychain.delete(keyFor(metadata: .userId, with: filename))
            keychain.delete(keyFor(metadata: .email, with: filename))
            keychain.delete(keyFor(metadata: .username, with: filename))
            
            //Remove from array
            crashFiles = crashFiles.filter{$0 != filename}
            approvedCrashReports.removeValue(forKey: filename)
            
            saveSettings()
            
        } catch let error {
            print("Error deleting crash log: ", error)
        }
    }
    
    func sendNextCrashReport() {
        if crashFiles.isEmpty {
            return
        }
        
        if let filename = crashFiles.first, let content = NSData(contentsOfFile: filename) {
            if content.length > 0 {
                sendCrashReport(with: filename)
            } else {
                cleanCrashReport(with: filename)
            }
        }
    }
    
    //MARK:- Networking
    
    ///Networking function to upload the crash log file to HockeyApp via HockeyApp's API
    func sendCrashReport(with filename: String) {
        NSLog("Uploading \(filename) to HockeyApp...")

        DispatchQueue.global(qos: .background).async {
            //Setup API URL
            let urlString = HOCKEY_API_PATH + HOCKEY_API_ID + HOCKEY_API_PATH_FOR_CUSTOM_CRASH
            guard let url = URL(string: urlString) else {return}
            
            //Setup crashlog file data
            let fileData = NSData(contentsOfFile: filename)
            
            //Setup userID and contact parameters
            let userId = self.keychain.get(self.keyFor(metadata: .userId, with: filename)) ?? ""
            let email = self.keychain.get(self.keyFor(metadata: .email, with: filename)) ?? ""
            let parameters = ["userID": userId, //Reflected under the "User" column on HockeyApp's console
                              "contact": email] //Reflected under the "Contact" column on HockeyApp's console
            
            //Setup POST URLRequest with crashlog, userid and contact parameters
            var request = URLRequest(url: url)
            let boundary = "Boundary-\(UUID().uuidString)"
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = self.createBody(parameters: parameters, boundary: boundary, data: fileData! as Data, mimeType: "text/plain", filename: filename)
            
            //Perform network request
            let dataTask = self.session.dataTask(with: request) { (data, response, error) in
                if let response = response as? HTTPURLResponse {
                    let statusCode = response.statusCode
                    self.processUploadResultWithFilename(filename: filename, data: data, statusCode: statusCode, error: error)
                }
            }
            
            dataTask.resume()
        }
    }
    
    ///Handle networking request
    func processUploadResultWithFilename(filename: String, data: Data?, statusCode: Int, error: Error?) {
        var theError = error

        if theError == nil {
            if data == nil {
                theError = NSError(domain: CRASH_ERROR_DOMAIN, code: ErrorResponse.CrashAPIReceivedEmptyResponse.rawValue, userInfo: [NSLocalizedDescriptionKey : "Sending failed with an empty response!"])
                
            } else if (statusCode >= 200 && statusCode < 400) {
                NSLog("Upload \(filename) successful")
                
                //Update plist
                approvedCrashReports[filename] = true
                saveSettings()
                
                cleanCrashReport(with: filename)
                
                //property list serialization
                //delegate didFinishSendingCrashReport
                
                sendNextCrashReport()
            } else if statusCode == 400 {
                cleanCrashReport(with: filename)
                
                theError = NSError(domain: CRASH_ERROR_DOMAIN, code: ErrorResponse.CrashAPIAppVersionRejected.rawValue, userInfo: [NSLocalizedDescriptionKey : "The server rejected receiving crash reports for this app version!"])
                
            } else {
                 theError = NSError(domain: CRASH_ERROR_DOMAIN, code: ErrorResponse.CrashAPIErrorWithStatusCode.rawValue, userInfo: [NSLocalizedDescriptionKey : "Sending failed with status code: \(statusCode)"])
            }
            
        }
       
        if let theError = theError {
            //delegate didFailWithError:theError
            NSLog("Error: ", theError.localizedDescription)
        }
    }

    //MARK:- Helpers
    
    func getLastPathComponent(from filename: String) -> String {
        let filepathUrl = URL(string: filename)
        return filepathUrl?.lastPathComponent.replacingOccurrences(of: ".crash", with: "") ?? ""
    }
    
    //https://newfivefour.com/swift-form-data-multipart-upload-URLRequest.html
    func createBody(parameters: [String: String],
                    boundary: String,
                    data: Data,
                    mimeType: String,
                    filename: String) -> Data {
        let body = NSMutableData()
        
        let boundaryPrefix = "--\(boundary)\r\n"
        
        for (key, value) in parameters {
            body.appendString(boundaryPrefix)
            body.appendString("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.appendString("\(value)\r\n")
        }
        
        body.appendString(boundaryPrefix)
        body.appendString("Content-Disposition: form-data; name=\"log\"; filename=\"\(filename)\"\r\n")
        body.appendString("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.appendString("\r\n")
        body.appendString("--".appending(boundary.appending("--")))
        
        return body as Data
    }
    
    enum Metadata: String {
        case username,
        userId,
        email
    }
    
    func keyFor(metadata: Metadata, with filename: String) -> String {
        let lastPath = getLastPathComponent(from: filename)
        
        switch metadata {
        case .username:
            return "\(lastPath).\(CRASH_META_USERNAME)"
        case .userId:
            return "\(lastPath).\(CRASH_META_USERID)"
        case .email:
            return "\(lastPath).\(CRASH_META_EMAIL)"
        }
    }
}

@objc extension NSMutableData {
    @objc func appendString(_ string: String) {
        let data = string.data(using: String.Encoding.utf8, allowLossyConversion: false)
        append(data!)
    }
}
