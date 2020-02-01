//
//  UIAlerController+Helpers.swift
//  Video Lower Third
//
//  Created by Christophe Delhaze on 27/11/19.
//  Copyright © 2019 Christophe Delhaze. All rights reserved.
//

import UIKit

// MARK: - UIAlerController Helper

extension UIAlertController {
    
    /**
     Shows an alert view with a OK button using an optional title and an optional message in the specified viewcontroller.
        - Parameters:
            - title: The title of the alert
            - message: The message of the alert
            - viewController: The view controller that is presenting the alert view
     */
    static func showAlert(with title: String?, message: String?, in viewController: UIViewController) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        // Making sure that we always present while on the main thread
        if Thread.isMainThread {
            viewController.present(alert, animated: true)
        } else {
            DispatchQueue.main.async {
                viewController.present(alert, animated: true)
            }
        }
        
    }
    
}

