//
//  VibrantWarningView.swift
//  apturicovid
//
//  Created by Artjoms Spole on 21/05/2020.
//  Copyright © 2020 MAK IT. All rights reserved.
//

import UIKit

struct WarningViewParams {
    
    enum Allignment { case top, bottom, center }
    
    var cornerRadius: CGFloat = 0
    var alignment: Allignment = .center
    
    var imageSize: CGSize = CGSize(width: 50, height: 50)
    var imageViewInsets: UIEdgeInsets = .zero
    
    var textSize: CGFloat = 16
    var textAllignment: NSTextAlignment = .center
    
    var textViewInsets: UIEdgeInsets = .zero
    
    
}
/**
 View for displaying warning messages.
 
 View has rounded blur background with vibrant images and text views.
 */
class WarningView: UIView {
    
    var warningBlurEffectView :UIVisualEffectView!
    var vibrancyEffectView :UIVisualEffectView!
    
    private var text = ""
    private var preferedImage :UIImage?
    private var preferedEffect :UIBlurEffect?
    private var params = WarningViewParams()
    
    private override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    /**
     Main initializer for view
     - Parameter frame: Frame of view
     - Parameter text: Warning text
     - Parameter preferedEffect: Blur effect for both UIVisualEffectView view layers
     - Parameter image: Custom Warning image. If no image will be set, default one will be user instead.
     */
    convenience init(frame: CGRect,
                     text: String,
                     params: WarningViewParams,
                     preferedEffect: UIBlurEffect? = nil,
                     image: UIImage? = nil) {
        self.init(frame: frame)
        self.text = text
        self.preferedEffect = preferedEffect
        self.preferedImage = image
        self.params = params
        
        configureBlurView()
        addSubview(warningBlurEffectView)
        setupWarningBoxConstraints()
    }
    
    /// Setup blur views and vibrant elements
    private func configureBlurView(){
        
        let blurEffect = preferedEffect ?? UIBlurEffect(style: .extraLight)
        let vibrancyEffect = UIVibrancyEffect(blurEffect: blurEffect)
        
        warningBlurEffectView = UIVisualEffectView(effect: blurEffect)
        vibrancyEffectView = UIVisualEffectView(effect: vibrancyEffect)
        
        let warningImage = UIImageView(image: preferedImage ?? UIImage(systemName: "exclamationmark.circle"))
        warningImage.contentMode = .scaleToFill
        
        let warningText = UILabel()
        warningText.font = .systemFont(ofSize: params.textSize , weight: .medium)
        warningText.numberOfLines = 1
        warningText.minimumScaleFactor = 0.1
        warningText.adjustsFontSizeToFitWidth = true
        warningText.textAlignment = params.textAllignment
        warningText.text = text
        
        vibrancyEffectView.contentView.addSubview(warningText)
        vibrancyEffectView.contentView.addSubview(warningImage)
        
        warningBlurEffectView.contentView.addSubview(vibrancyEffectView!)
        warningBlurEffectView.layer.cornerRadius = params.cornerRadius
        warningBlurEffectView.clipsToBounds = true
    }
    
    /// Setup subview constraints
    private func setupWarningBoxConstraints(){
        
        [vibrancyEffectView,warningBlurEffectView].compactMap{$0}.forEach{
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
            $0.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
            $0.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
            $0.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        }
        
        
        // Image view contraints:
        let warningImage = vibrancyEffectView!.contentView.subviews.first(where: {$0 is UIImageView})!
        
        warningImage.translatesAutoresizingMaskIntoConstraints = false
        
        warningImage.topAnchor
            .constraint(equalTo: vibrancyEffectView.topAnchor,
                        constant: -params.imageViewInsets.top)
            .isActive = params.alignment == .top
        
        warningImage.centerYAnchor
            .constraint(equalTo: vibrancyEffectView.centerYAnchor,
                        constant: 0)
            .isActive = params.alignment == .center
        
        warningImage.bottomAnchor
            .constraint(equalTo: vibrancyEffectView.bottomAnchor,
                        constant: -params.imageViewInsets.bottom)
            .isActive = params.alignment == .bottom
        
        
        warningImage.leadingAnchor
            .constraint(equalTo: vibrancyEffectView.leadingAnchor,
                        constant: params.imageViewInsets.left)
            .isActive = true
        
        
        warningImage.widthAnchor
            .constraint(equalToConstant: params.imageSize.width)
            .isActive = true
        
        warningImage.heightAnchor
            .constraint(equalToConstant: params.imageSize.height)
            .isActive = true
        
        
        // Text view contraints:
        
        let warningText = vibrancyEffectView!.contentView.subviews.first(where: {$0 is UILabel})!
        
        warningText.translatesAutoresizingMaskIntoConstraints = false
        
        warningText.topAnchor
            .constraint(equalTo: vibrancyEffectView.topAnchor,
                        constant: -params.textViewInsets.top)
            .isActive = params.alignment == .top
        
        warningText.centerYAnchor
            .constraint(equalTo: vibrancyEffectView.centerYAnchor,
                        constant: 0)
            .isActive = params.alignment == .center
        
        warningText.bottomAnchor
            .constraint(equalTo: vibrancyEffectView.bottomAnchor,
                        constant: -params.textViewInsets.bottom)
            .isActive = params.alignment == .bottom
        
        
        warningText.leadingAnchor
            .constraint(equalTo: warningImage.trailingAnchor,
                        constant: params.textViewInsets.left)
            .isActive = true
        
        warningText.trailingAnchor
            .constraint(equalTo: warningBlurEffectView.trailingAnchor,
                        constant: -params.textViewInsets.right)
            .isActive = true
        
    }
}
