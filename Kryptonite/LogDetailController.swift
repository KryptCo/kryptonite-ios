//
//  LogDetailController.swift
//  Kryptonite
//
//  Created by Alex Grinman on 5/29/17.
//  Copyright © 2017 KryptCo. All rights reserved.
//

import Foundation
import PGPFormat

class CommitLogDetailController:UIViewController {
    
    @IBOutlet weak var commitHashLabel:UILabel!
    @IBOutlet weak var messageLabel:UILabel!

    @IBOutlet weak var treeLabel:UILabel!
    @IBOutlet weak var parentLabel:UILabel!

    @IBOutlet weak var authorLabel:UILabel!
    @IBOutlet weak var comitterLabel:UILabel!
    @IBOutlet weak var authorTimeLabel:UILabel!
    @IBOutlet weak var commitTimeLabel:UILabel!

    @IBOutlet weak var signatureLabel:UILabel!

    var commitLog:CommitSignatureLog?
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let log = commitLog else {
            return
        }
        
        self.title = "Git Commit"
        
        // hash
        let hash = log.commitHash
        
        if hash.characters.count >= 7 {
            commitHashLabel.text = hash.substring(to: hash.index(hash.startIndex, offsetBy: 7))
        } else {
            commitHashLabel.text = hash
        }
        
        // labels
        messageLabel.text = log.commit.messageString
        treeLabel.text = log.commit.tree
        parentLabel.text = log.commit.parent ?? "first commit"
        
        let (author, authorDate) = log.commit.author.userIdAndDateString
        authorLabel.text = author
        authorTimeLabel.text = authorDate

        let (committer, committerDate) = log.commit.committer.userIdAndDateString
        comitterLabel.text = committer
        commitTimeLabel.text = committerDate
        
        signatureLabel.text = try? AsciiArmorMessage(message: PGPFormat.Message(base64: log.signature), blockType: ArmorMessageBlock.signature, comment: Properties.pgpMessageComment).toString()
    }
}


typealias TagCommitLogPair = (TagSignatureLog, CommitSignatureLog?)
class TagLogDetailController:UIViewController {
    
    // tag
    
    @IBOutlet weak var tagLabel:UILabel!
    @IBOutlet weak var messageLabel:UILabel!
    
    @IBOutlet weak var typeLabel:UILabel!
    @IBOutlet weak var taggerLabel:UILabel!
    @IBOutlet weak var tagCreatedLabel:UILabel!
    @IBOutlet weak var signatureLabel:UILabel!

    
    // commit
    @IBOutlet weak var commitView:UIView!

    @IBOutlet weak var commitHashLabel:UILabel!
    @IBOutlet weak var commitMessageLabel:UILabel!
    
    @IBOutlet weak var treeLabel:UILabel!
    @IBOutlet weak var parentLabel:UILabel!
    
    @IBOutlet weak var authorLabel:UILabel!
    @IBOutlet weak var comitterLabel:UILabel!
    @IBOutlet weak var authorTimeLabel:UILabel!
    @IBOutlet weak var commitTimeLabel:UILabel!
    
    @IBOutlet weak var commitSignatureLabel:UILabel!
    
    var tagCommitLogPair:TagCommitLogPair?
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "Git Tag"

        guard let (tagLog, commitLog) = tagCommitLogPair else {
            commitView.alpha = 0
            return
        }
        
        // set the tag log part
        tagLabel.text = tagLog.tag.tag
        typeLabel.text = tagLog.tag.type.uppercased()
        
        let (tagUserID, tagDate) = tagLog.tag.tagger.userIdAndDateString
        taggerLabel.text = tagUserID
        tagCreatedLabel.text = tagDate
        signatureLabel.text = try? AsciiArmorMessage(message: PGPFormat.Message(base64: tagLog.signature), blockType: ArmorMessageBlock.signature, comment: Properties.pgpMessageComment).toString()
        
        // set the commit log part
        guard let log = commitLog else {
            return
        }
        // hash
        let hash = log.commitHash
        
        if hash.characters.count >= 7 {
            commitHashLabel.text = hash.substring(to: hash.index(hash.startIndex, offsetBy: 7))
        } else {
            commitHashLabel.text = hash
        }
        
        // labels
        commitMessageLabel.text = log.commit.messageString
        treeLabel.text = log.commit.tree
        parentLabel.text = log.commit.parent ?? "first commit"
        
        let (author, authorDate) = log.commit.author.userIdAndDateString
        authorLabel.text = author
        authorTimeLabel.text = authorDate
        
        let (committer, committerDate) = log.commit.committer.userIdAndDateString
        comitterLabel.text = committer
        commitTimeLabel.text = committerDate
        
        commitSignatureLabel.text = try? AsciiArmorMessage(message: PGPFormat.Message(base64: log.signature), blockType: ArmorMessageBlock.signature, comment: Properties.pgpMessageComment).toString()
    }
}
