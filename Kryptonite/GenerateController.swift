//
//  GenerateController.swift
//  Kryptonite
//
//  Created by Alex Grinman on 9/26/16.
//  Copyright © 2016 KryptCo, Inc. All rights reserved.
//

import Foundation
import UIKit

class GenerateController:UIViewController {
    
    @IBOutlet weak var animationView:UIView!

    var keyType:KeyType!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
                
        SwiftSpinner.useContainerView(animationView)
        SwiftSpinner.show("", animated: true)
        
        // destroy the existing keypair before re-generating
        KeyManager.destroyKeyPair()
        
        let startTime = Date()

        dispatchAsync {
            do {
                
                try KeyManager.generateKeyPair(type: self.keyType)

                let elapsed = Date().timeIntervalSince(startTime)
                
                Analytics.postEvent(category: "keypair", action: "generate", label: self.keyType.rawValue, value: UInt(elapsed))
                
                let kp = try KeyManager.sharedInstance().keyPair
                let pk = try kp.publicKey.export().toBase64()
                
                log("Generated public key: \(pk)")
                
                if elapsed >= 3.0 {
                    dispatchMain {
                        SwiftSpinner.hide()
                        self.performSegue(withIdentifier: "showSetup", sender: nil)
                    }
                    return
                }
                
                dispatchAfter(delay: 3.0 - elapsed, task: {
                    dispatchMain {
                        SwiftSpinner.hide()
                        self.performSegue(withIdentifier: "showSetup", sender: nil)
                    }
                })

            } catch (let e) {
                self.showWarning(title: "Error", body: "Cryptography: error generating key pair. \(e)", then: {
                    dispatchMain {
                        SwiftSpinner.hide()
                        self.dismiss(animated: true, completion: nil)
                    }
                })
            }
        }
    }
    
}
