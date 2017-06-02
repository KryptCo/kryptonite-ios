//
//  ApproveController.swift
//  Kryptonite
//
//  Created by Alex Grinman on 10/23/16.
//  Copyright © 2016 KryptCo. All rights reserved.
//

import UIKit
import AVFoundation

class ApproveController:UIViewController {
    
    @IBOutlet weak var contentView:UIView!
    
    @IBOutlet weak var resultView:UIView!
    @IBOutlet weak var resultViewHeight:NSLayoutConstraint!
    @IBOutlet weak var resultLabel:UILabel!

    
    @IBOutlet weak var deviceLabel:UILabel!
    @IBOutlet weak var commandLabel:UILabel!
    
    @IBOutlet weak var checkBox:M13Checkbox!
    @IBOutlet weak var arcView:UIView!

    @IBOutlet weak var swipeDownRejectGesture:UIGestureRecognizer!

    var rejectColor = UIColor.reject
    
    var heightCover:CGFloat = 234.0
    
    var request:Request?
    var session:Session?
    
    var isEnabled = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        contentView.layer.shadowColor = UIColor.black.cgColor
        contentView.layer.shadowOffset = CGSize(width: 0, height: 0)
        contentView.layer.shadowOpacity = 0.2
        contentView.layer.shadowRadius = 3
        contentView.layer.masksToBounds = false
        
        checkBox.animationDuration = 1.0
        
        resultViewHeight.constant = 0
        resultLabel.alpha = 0
        
        if let session = session {
            deviceLabel.text = session.pairing.displayName.uppercased()
        }
        
        if let sshSign = request?.sign {
            commandLabel.text = sshSign.display
        } else if let gitSign = request?.gitSign {
            commandLabel.text = gitSign.commit.display
        } else {
            commandLabel.text = "Unknown"
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIView.animate(withDuration: 1.3) {
            self.view.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        }

    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        arcView.spinningArc(lineWidth: checkBox.checkmarkLineWidth, ratio: 0.5)
        //arcView.timeoutProgress(lineWidth: checkBox.checkmarkLineWidth, seconds: Properties.requestTimeTolerance)
        AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
    }
    
    

    
    
    //MARK: Response
    @IBAction func approveOnce() {
        if #available(iOS 10.0, *) {
            UIImpactFeedbackGenerator(style: UIImpactFeedbackStyle.heavy).impactOccurred()
        }
        
        guard let request = request, let session = session, isEnabled else {
            log("no valid request or session", .error)
            return
        }
        
        isEnabled = false
        
        do {
            let resp = try Silo.shared.lockResponseFor(request: request, session: session, signatureAllowed: true)
            try TransportControl.shared.send(resp, for: session)
            
            if let errorMessage = resp.sign?.error {
                isEnabled = true
                self.dismissResponseFailed(errorMessage: errorMessage)
                return
            }
            
        } catch (let e) {
            isEnabled = true
            log("send error \(e)", .error)
            self.showWarning(title: "Error", body: "Could not approve request. \(e)")
            return
        }
        
        swipeDownRejectGesture.isEnabled = false

        self.resultLabel.text = "Allow once".uppercased()
        
        UIView.animate(withDuration: 0.3, animations: {
            
            self.resultLabel.alpha = 1.0
            self.arcView.alpha = 0
            self.resultViewHeight.constant = self.heightCover
            self.view.layoutIfNeeded()
            
            
        }) { (_) in
            
            self.checkBox.toggleCheckState(true)
                dispatchAfter(delay: 2.0) {
                    self.animateDismiss(allowed: true)
                }
        }

        Analytics.postEvent(category: "signature", action: "foreground approve", label: "once")

    }
    
    @IBAction func approveThreeHours() {
        
        if #available(iOS 10.0, *) {
            UIImpactFeedbackGenerator(style: UIImpactFeedbackStyle.heavy).impactOccurred()
        }
        
        guard let request = request, let session = session, isEnabled else {
            log("no valid request or session", .error)
            return
        }
        
        isEnabled = false
        
        do {
            Policy.allow(session: session, for: Policy.Interval.threeHours)
            let resp = try Silo.shared.lockResponseFor(request: request, session: session, signatureAllowed: true)
            try TransportControl.shared.send(resp, for: session)
            
            if let errorMessage = resp.sign?.error {
                isEnabled = true
                self.dismissResponseFailed(errorMessage: errorMessage)
                return
            }
            
        } catch (let e) {
            isEnabled = true
            log("send error \(e)", .error)
            self.showWarning(title: "Error", body: "Could not approve request. \(e)")
            return
        }
        
        swipeDownRejectGesture.isEnabled = false

        self.resultLabel.text = "Allow for 3 hours".uppercased()
        
        UIView.animate(withDuration: 0.3, animations: {
            
            self.resultLabel.alpha = 1.0
            self.arcView.alpha = 0
            self.resultViewHeight.constant = self.heightCover
            self.view.layoutIfNeeded()
            
            
        }) { (_) in
            dispatchMain{ self.checkBox.toggleCheckState(true) }
            dispatchAfter(delay: 2.0) {
                self.animateDismiss(allowed: true)
            }
        }

        Analytics.postEvent(category: "signature", action: "foreground approve", label: "time", value: UInt(Policy.Interval.threeHours.rawValue))

    }
    
    @IBAction func dismissReject() {
        
        if #available(iOS 10.0, *) {
            UIImpactFeedbackGenerator(style: UIImpactFeedbackStyle.heavy).impactOccurred()
        }
        
        guard isEnabled else {
            return
        }
        
        isEnabled = false
        
        do {
            if let request = request, let session = session {
                let resp = try Silo.shared.lockResponseFor(request: request, session: session, signatureAllowed: false)
                try TransportControl.shared.send(resp, for: session)
            }
            
        } catch (let e) {
            log("send error \(e)", .error)
        }
        
        self.resultLabel.text = "Reject".uppercased()
        self.resultView.backgroundColor = rejectColor
        self.checkBox.secondaryCheckmarkTintColor = rejectColor
        self.checkBox.tintColor = rejectColor
        
        UIView.animate(withDuration: 0.3, animations: {
            self.resultLabel.alpha = 1.0
            self.arcView.alpha = 0
            self.resultViewHeight.constant = self.heightCover
            self.view.layoutIfNeeded()
            
        }) { (_) in
            self.checkBox.setCheckState(M13Checkbox.CheckState.mixed, animated: true)
            dispatchAfter(delay: 2.0) {
                self.animateDismiss()
            }
        }
        
        Analytics.postEvent(category: "signature", action: "foreground reject")
        
    }
    

    func dismissResponseFailed(errorMessage:String) {

        if #available(iOS 10.0, *) {
            UIImpactFeedbackGenerator(style: UIImpactFeedbackStyle.heavy).impactOccurred()
        }
        
        guard isEnabled else {
            return
        }
        
        isEnabled = false
        
        self.resultLabel.text = errorMessage.uppercased()
        self.resultView.backgroundColor = rejectColor
        self.checkBox.secondaryCheckmarkTintColor = rejectColor
        self.checkBox.tintColor = rejectColor
        
        UIView.animate(withDuration: 0.3, animations: {
            self.resultLabel.alpha = 1.0
            self.arcView.alpha = 0
            self.resultViewHeight.constant = self.heightCover
            self.view.layoutIfNeeded()
            
        }) { (_) in
            self.checkBox.setCheckState(M13Checkbox.CheckState.mixed, animated: true)
            dispatchAfter(delay: 2.0) {
                self.animateDismiss()
            }
        }
        
        let errorLabel = HostMistmatchError.isMismatchErrorString(err: errorMessage) ? "host mistmatch" : "crypto error"
        Analytics.postEvent(category: "signature", action: "failed foreground approve", label: errorLabel)
    }
    
    func animateDismiss(allowed:Bool = false) {
        UIView.animate(withDuration: 0.1) {
            self.view.backgroundColor = UIColor.clear
        }
        
        let presenting = self.presentingViewController
        self.dismiss(animated: true, completion: {
            presenting?.approveControllerDismissed(allowed: allowed)
        })
    }
}
