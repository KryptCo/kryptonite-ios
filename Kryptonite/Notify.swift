//
//  Notify.swift
//  Kryptonite
//
//  Created by Alex Grinman on 2/2/17.
//  Copyright © 2017 KryptCo. All rights reserved.
//

import Foundation
import UIKit

import UserNotifications
import JSON

class Notify {
    private static var _shared:Notify?
    static var shared:Notify {
        if let sn = _shared {
            return sn
        }
        _shared = Notify()
        return _shared!
    }
    
    init() {}
    
    var pushedNotifications:[String:Int] = [:]
    var noteMutex = Mutex()
    
    func present(request:Request, for session:Session) {
        
        let noteTitle = "Request from \(session.pairing.displayName)"
        
        var noteSubtitle:String
        var noteBody:String
        if let signRequest = request.sign {
            noteSubtitle = "SSH Login"
            noteBody = signRequest.display
        } else if let gitSignRequest = request.gitSign {
            noteSubtitle = gitSignRequest.git.subtitle + " Signature"
            noteBody = gitSignRequest.git.shortDisplay
        } else {
            noteSubtitle = ""
            noteBody = "Unknown"
        }

        
        if #available(iOS 10.0, *) {
            
            // check if request exists in pending notifications
            UNUserNotificationCenter.current().getPendingNotificationRequests(completionHandler: { (noteRequests) in
                for noteRequest in noteRequests {
                    guard   let requestObject = noteRequest.content.userInfo["request"] as? JSON.Object,
                        let deliveredRequest = try? Request(json: requestObject)
                        else {
                            continue
                    }
                    
                    // return if it's already there
                    if deliveredRequest.id == request.id {
                        return
                    }
                }
                
                // then, check if request exists in delivered notifications
                UNUserNotificationCenter.current().getDeliveredNotifications(completionHandler: { (notes) in
                    
                    for note in notes {
                        guard   let requestObject = note.request.content.userInfo["request"] as? JSON.Object,
                            let deliveredRequest = try? Request(json: requestObject)
                            else {
                                continue
                        }
                        
                        // return if it's already there
                        if deliveredRequest.id == request.id {
                            return
                        }
                    }
                    
                    // otherwise, no notificiation so display it:
                    let content = UNMutableNotificationContent()
                    content.title = noteTitle
                    content.subtitle = noteSubtitle
                    content.body = noteBody
                    content.sound = UNNotificationSound.default()
                    content.userInfo = ["session_display": session.pairing.displayName, "session_id": session.id, "request": request.object]
                    content.categoryIdentifier = Policy.authorizeCategoryIdentifier
                    content.threadIdentifier = request.id
                    
                    let noteId = request.id
                    log("pushing note with id: \(noteId)")
                    let request = UNNotificationRequest(identifier: noteId, content: content, trigger: nil)
                    
                    UNUserNotificationCenter.current().add(request) {(error) in
                        log("error firing notification: \(String(describing: error))")
                    }
                    
                })


            })

            
        } else {
            let notification = UILocalNotification()
            notification.alertTitle = noteTitle
            notification.alertBody = noteBody
            notification.soundName = UILocalNotificationDefaultSoundName
            notification.category = Policy.authorizeCategory.identifier
            notification.userInfo = ["session_display": session.pairing.displayName, "session_id": session.id, "request": request.object]
            
            UIApplication.shared.presentLocalNotificationNow(notification)
        }
    }
    
    func presentApproved(request:Request, for session:Session) {
        
        
        let noteTitle = "Approved request from \(session.pairing.displayName)"
        
        var noteSubtitle:String
        var noteBody:String
        if let signRequest = request.sign {
            noteSubtitle = "SSH Login"
            noteBody = signRequest.display
        } else if let gitSignRequest = request.gitSign {
            noteSubtitle = gitSignRequest.git.subtitle + " Signature"
            noteBody = gitSignRequest.git.shortDisplay
        } else {
            noteSubtitle = ""
            noteBody = "Unknown"
        }

        
        if #available(iOS 10.0, *) {
            
            let noteId = RequestNotificationIdentifier(request: request, session:session)
            
            let content = UNMutableNotificationContent()
            content.title = noteTitle
            content.subtitle = noteSubtitle
            content.body = noteBody
            content.categoryIdentifier = Policy.autoAuthorizedCategoryIdentifier
            content.sound = UNNotificationSound.default()
            content.userInfo = ["session_display": session.pairing.displayName, "session_id": session.id, "request": request.object]

            
            // check grouping index for same notification
            var noteIndex = 0
            noteMutex.lock()
            if let idx = pushedNotifications[noteId] {
                noteIndex = idx
            }
            noteMutex.unlock()
            
            let prevRequestIdentifier = noteId.with(count: noteIndex)
            
            // check if delivered notifications cleared
            UNUserNotificationCenter.current().getDeliveredNotifications(completionHandler: { (notes) in
                
                // if notifications clear, reset count
                if notes.filter({ $0.request.identifier == prevRequestIdentifier}).isEmpty {
                    self.pushedNotifications.removeValue(forKey: noteId)
                    noteIndex = 0
                }
                // otherwise remove previous, update note body
                else {
                    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [prevRequestIdentifier])
                    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [prevRequestIdentifier])
                    content.body = "\(content.body) (\( noteIndex + 1))"
                    content.sound = UNNotificationSound(named: "")

                    
                }
                self.noteMutex.unlock()
                
                log("pushing note with id: \(noteId)")
                let request = UNNotificationRequest(identifier: noteId.with(count: noteIndex+1), content: content, trigger: nil)
                
                UNUserNotificationCenter.current().add(request) {(error) in
                    log("error firing notification: \(String(describing: error))")
                    self.noteMutex.lock {
                        self.pushedNotifications[noteId] = noteIndex+1
                    }
                }
            })


            
        } else {
            let notification = UILocalNotification()
            notification.alertTitle = noteTitle
            notification.alertBody = noteBody
            notification.soundName = UILocalNotificationDefaultSoundName
            notification.category = Policy.autoAuthorizedCategoryIdentifier
            
            UIApplication.shared.presentLocalNotificationNow(notification)
        }

    }
    
    
    func presentError(message:String, session:Session) {
        
        if UserRejectedError.isRejected(errorString: message) {
            return
        }
        
        let noteTitle = "Failed approval for \(session.pairing.displayName)"
        let noteBody = message
        
        if #available(iOS 10.0, *) {
            let content = UNMutableNotificationContent()
            content.title = noteTitle
            content.body = noteBody
            content.sound = UNNotificationSound.default()
            
            let request = UNNotificationRequest(identifier: "\(session.id)_\(message.hash)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        } else {
            let notification = UILocalNotification()
            notification.alertTitle = noteTitle
            notification.alertBody = noteBody
            notification.soundName = UILocalNotificationDefaultSoundName
            
            UIApplication.shared.presentLocalNotificationNow(notification)
        }
        
    }

}

extension Request {
    var notificationIdentifer:String {
        if let sign = self.sign {
            return sign.display
        } else if let gitSign = self.gitSign {
            return gitSign.git.shortDisplay
        } else {
            return self.id
        }
    }
}
typealias RequestNotificationIdentifier = String
extension RequestNotificationIdentifier {
    init(request:Request, session:Session) {
        self = "\(session.id)_\(request.notificationIdentifer)"
    }
    
    func with(count:Int) -> String {
        return "\(self)_\(count)"
    }
}






