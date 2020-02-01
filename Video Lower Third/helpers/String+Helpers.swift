//
//  String+Helpers.swift
//  Video Lower Third
//
//  Created by Christophe Delhaze on 27/11/19.
//  Copyright © 2019 Christophe Delhaze. All rights reserved.
//

import UIKit

// MARK: - String Helpers

extension String {

    /**
     Estimates the width in pixels of a string using a specific font
        - Parameters:
            - font: The font to use to evaluate the width in pixels.
        - Returns: The width in pixel of the text using the specified font.
     */
    func width(usingFont font: UIFont) -> CGFloat {
        return size(usingFont: font).width
    }

    /**
     Estimates the height in pixels of a string using a specific font
        - Parameters:
            - font: The font to use to evaluate the height in pixels.
        - Returns: The height in pixel of the text using the specified font.
     */
    func height(usingFont font: UIFont) -> CGFloat {
        return size(usingFont: font).height
    }

    /**
     Estimates the size (width and height as a CGSize) in pixels of a string using a specific font
        - Parameters:
            - font: The font to use to evaluate the height in pixels.
        - Returns: The size in pixel of the text using the specified font.
     */
    func size(usingFont font: UIFont) -> CGSize {
        let fontAttributes = [NSAttributedString.Key.font: font]
        return self.size(withAttributes: fontAttributes)
    }
    
}
