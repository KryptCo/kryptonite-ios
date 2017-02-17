//
//  AboutController.swift
//  Kryptonite
//
//  Created by Alex Grinman on 9/18/16.
//  Copyright © 2016 KryptCo, Inc. All rights reserved.
//

import UIKit
import LocalAuthentication
import MessageUI

class AboutController: KRBaseController {

    @IBOutlet weak var versionLabel:UILabel!
    @IBOutlet weak var analyticsSwitch:UISwitch!

    override func viewDidLoad() {
        super.viewDidLoad()

        analyticsSwitch.isOn = !Analytics.enabled
        
        if  let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            let hash = Bundle.main.infoDictionary?["GitHash"] as? String
        {
            let hashShort = hash.substring(to: hash.index(hash.startIndex, offsetBy: min(6, hash.characters.count)))
            self.versionLabel.text = "v\(version).\(build) - \(hashShort)"
        }
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func doneTapped() {
        dismiss(animated: true, completion: nil)
    }

    
    @IBAction func analyticsEnabledChanged(sender:UISwitch) {
        Analytics.set(disabled: sender.isOn)
    }
    
    @IBAction func trashTapped() {
        
        let sheet = UIAlertController(title: "Do you want to destroy your private and public key?", message: "Your private key will be gone forever and you will be asked to generate a new one. You will be unpaired from all devices.", preferredStyle: .actionSheet)
        
        sheet.addAction(UIAlertAction(title: "Delete key pair", style: UIAlertActionStyle.destructive, handler: { (action) in
            self.deleteKeyTapped()
        }))
        
        sheet.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.cancel, handler: { (action) in
        }))
        
        present(sheet, animated: true, completion: nil)
        
    }
    
    
    func deleteKeyTapped() {
        
        authenticate { (yes) in
            guard yes else {
                return
            }

            Analytics.postEvent(category: "keypair", action: "destroy")
            
            let _ = KeyManager.destroyKeyPair()
            KeyManager.clearMe()
            SessionManager.shared.destory()
            
            dispatchMain {
                self.dismiss(animated: true, completion: nil)
            }
        }
    }
    
    func authenticate(completion:@escaping (Bool)->Void) {
        let context = LAContext()
        let policy = LAPolicy.deviceOwnerAuthentication
        let reason = "Authentication is needed to delete your key pair"
        
        var err:NSError?
        guard context.canEvaluatePolicy(policy, error: &err) else {
            log("cannot eval policy: \(err?.localizedDescription ?? "unknown err")", .error)
            completion(true)
            
            return
        }
        
        
        dispatchMain {
            context.evaluatePolicy(policy, localizedReason: reason, reply: { (success, policyErr) in
                completion(success)
            })
            
        }
        
    }
    
    //MARK: Actions
    
    @IBAction func contactUsTapped() {
        
        guard MFMailComposeViewController.canSendMail() else {
            if let mailURL = URL(string: "mailto://\(Properties.contactUsEmail)") {
                UIApplication.shared.openURL(mailURL)
            }
            
            return
        }
        
        let mailDialogue = MFMailComposeViewController()
        mailDialogue.setToRecipients([Properties.contactUsEmail])
        
        mailDialogue.setSubject("Feedback for Kryptonite \(self.versionLabel.text ?? "")")
        
        // feedback device info
        var deviceInfo = "\n\n\n\n\n\n-----------\nDevice Info:\n"
        deviceInfo += "Model: \(UIDevice.current.model)\n"
        deviceInfo += "SystemVersion: \(UIDevice.current.systemVersion)\n"
        deviceInfo += "SystemName: \(UIDevice.current.systemName)\n"
        deviceInfo += "Identifier: \((try? KeychainStorage().get(key: KR_ENDPOINT_ARN_KEY)) ?? "unknown")\n"
        deviceInfo += "-----------"
        //
        mailDialogue.setMessageBody(deviceInfo, isHTML: false)
        mailDialogue.mailComposeDelegate = self
        
        present(mailDialogue, animated: true, completion: nil)
        
        
    }
    
    @IBAction func openSourceTapped() {
        if let url = URL(string: Properties.openSourceURL) {
            UIApplication.shared.openURL(url)
        }
    }
    
    @IBAction func privacyTapped() {
        if let url = URL(string: Properties.privacyPolicyURL) {
            UIApplication.shared.openURL(url)
        }
    }


    //MARK: Delegates
    public override func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        Resources.makeAppearences()
        
        controller.dismiss(animated: true, completion: nil)
    }


    
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}