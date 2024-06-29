//
//  NavigationController.swift
//  simple-search
//
//  Created by Wayne Carter on 6/15/24.
//

import UIKit

class NavigationController: UINavigationController {
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    func animateAddingImageToRightButtonBarItem(_ imageView: UIImageView, from navigationItem: UINavigationItem, completion: (() -> Void)? = nil) {
        guard let imageViewSnapshot = imageView.snapshotView(afterScreenUpdates: false),
              let window = imageView.window
        else {
            completion?()
            return
        }
        
        // Postion the snapshot and add it to the window
        imageViewSnapshot.frame = window.convert(imageView.frame, from: imageView.superview)
        window.addSubview(imageViewSnapshot)
        
        // Hide the original imageView temporarily
        imageView.isHidden = true
        
        // Define the animation path
        let targetFrame: CGRect
        let finalPoint: CGPoint
        if let rightBarButtonItem = navigationItem.rightBarButtonItem,
           rightBarButtonItem.isHidden == false,
           let targetView = rightBarButtonItem.customView
        {
            targetFrame = window.convert(targetView.frame, from: targetView.superview)
            finalPoint = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        } else {
            targetFrame = window.convert(self.navigationBar.frame, from: self.navigationBar.superview)
            finalPoint = CGPoint(x: targetFrame.maxX - 50, y: targetFrame.midY)
        }
        
        // Animate the the product image flying into the target
        UIView.animate(withDuration: 0.5, animations: {
            // Move and scale down the snapshot
            imageViewSnapshot.center = finalPoint
            imageViewSnapshot.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
        }, completion: { _ in
            // Clean up
            imageViewSnapshot.removeFromSuperview()
            imageView.isHidden = false
            
            completion?()
        })
    }
}
