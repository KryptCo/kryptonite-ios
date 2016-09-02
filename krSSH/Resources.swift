//
//  Resources.swift
//  Kryptonite
//
//  Created by Alex Grinman on 10/24/15.
//  Copyright © 2015 KryptCo. All rights reserved.
//

import Foundation
import UIKit

struct Resources {
    
    //MARK: Storyboards
    struct Storyboard {
        static let Main = UIStoryboard(name: "Main",   bundle: Bundle.main)
    }
    
    static func makeAppearences() {
        UINavigationBar.appearance().barTintColor = UIColor.app
        UINavigationBar.appearance().tintColor = UIColor.white

        UINavigationBar.appearance().titleTextAttributes = [
            NSForegroundColorAttributeName: UIColor.white,
            NSFontAttributeName: UIFont(name: "Avenir Next Ultra Light", size: 17)!
        ]

        UIButton.appearance().tintColor = UIColor.app
        UISwitch.appearance().tintColor = UIColor.app
        UISegmentedControl.appearance().tintColor = UIColor.app
        
        UIBarButtonItem.appearance().tintColor = UIColor.white
        
        // Custom Classes
        StyleFilledButton.appearance().backgroundColor = UIColor.app
        StyleFilledView.appearance().backgroundColor = UIColor.app
    }
}

func RGB(_ r:CGFloat, _ g:CGFloat, _ b:CGFloat, _ a:CGFloat = 1.0) -> UIColor {
    return UIColor(red: r/255.0, green: g/255.0, blue: b/255.0, alpha: a)
}

//MARK: Extensions

extension UIColor {
    
    convenience init(hex: Int) {
        let components = (
            R: CGFloat((hex >> 16) & 0xff) / 255,
            G: CGFloat((hex >> 08) & 0xff) / 255,
            B: CGFloat((hex >> 00) & 0xff) / 255
        )
        
        self.init(red: components.R, green: components.G, blue: components.B, alpha: 1)
    }
    
    static var app:UIColor {
        return UIColor(hex: 0x1FB18A)
    }
}



extension UIColor {
    convenience init(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt32()
        Scanner(string: hex).scanHexInt32(&int)
        let a, r, g, b: UInt32
        switch hex.characters.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
    
    static func colorFromString(string: String) -> UIColor {
        let hash: Int = string.hashValue
        let r: Int = (hash & 0xFF0000) >> 16
        let g: Int = (hash & 0x00FF00) >> 8
        let b: Int = (hash & 0x0000FF)
        return RGB(CGFloat(r), CGFloat(g), CGFloat(b), 1.0)
    }

}

//MARK: Navigation Bar

extension UINavigationItem {
    func setKrLogo() {
        
        let logo = UIImageView(image: UIImage(named: "nav-logo")?.withRenderingMode(UIImageRenderingMode.alwaysTemplate))
        
        logo.tintColor = UIColor.black.withAlphaComponent(0.2)
        logo.frame = CGRect(origin: CGPoint(x: 0, y: 0), size:CGSize(width: 25, height: 30))

    
        let title = UIView()
        title.addSubview(logo)
        self.titleView = title
        logo.center = title.center
    }

}


//MARK: Custom UI Class

class StyleFilledButton:UIButton {}
class StyleFilledView:UIView {}

extension UIView {
    
    func setBorder(color:UIColor = UIColor.app, cornerRadius:CGFloat = 0.0, borderWidth:CGFloat = 0.0) {
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = cornerRadius > 0

        layer.borderWidth = borderWidth
        layer.borderColor = color.cgColor
    }
}
