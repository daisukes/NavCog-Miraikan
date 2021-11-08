//
//  AppAboutView.swift
//  NavCogMiraikan
//
/*******************************************************************************
 * Copyright (c) 2021 © Miraikan - The National Museum of Emerging Science and Innovation
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *******************************************************************************/

import Foundation
import UIKit

class AppAboutView: BaseView {
    
    private let lblIcon8 = UILabel()
    
    override func setup() {
        super.setup()
        
        lblIcon8.text = "Free Icons Retreived from: https://icons8.com for TabBar."
        lblIcon8.numberOfLines = 0
        lblIcon8.lineBreakMode = .byWordWrapping
        lblIcon8.sizeToFit()
        addSubview(lblIcon8)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let szFit = CGSize(width: innerSize.width, height: lblIcon8.intrinsicContentSize.height)
        lblIcon8.frame = CGRect(x: insets.left,
                                y: insets.top,
                                width: innerSize.width,
                                height: lblIcon8.sizeThatFits(szFit).height)
    }
    
}