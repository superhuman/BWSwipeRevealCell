//
//  BWSwipeCell.swift
//  BWSwipeCell
//
//  Created by Kyle Newsome on 2015-10-20.
//  Copyright © 2015 Kyle Newsome. All rights reserved.
//

import Foundation
import UIKit

//Defines the interaction type of the table cell
public enum BWSwipeCellType: Int {
    case swipeThrough = 0 // swipes with finger and animates through
    case springRelease // resists pulling and bounces back
    case slidingDoor // swipe to a stopping position where underlying buttons can be revealed
}

public enum BWSwipeCellRevealDirection {
    case none
    case both
    case right
    case left
}

public enum BWSwipeCellState {
    case normal
    case pastThresholdLeft
    case pastThresholdRight
}

@objc public protocol BWSwipeCellDelegate: NSObjectProtocol {
    @objc optional func swipeCellShouldStartSwiping(_ cell: BWSwipeCell) -> Bool
    @objc optional func swipeCellDidStartSwiping(_ cell: BWSwipeCell)
    @objc optional func swipeCellDidSwipe(_ cell: BWSwipeCell)
    @objc optional func swipeCellWillRelease(_ cell: BWSwipeCell)
    @objc optional func swipeCellDidCompleteRelease(_ cell: BWSwipeCell)
    @objc optional func swipeCellDidChangeState(_ cell: BWSwipeCell)
}

open class BWSwipeCell:UITableViewCell {
    
    // The interaction type for this table cell
    open var type:BWSwipeCellType = .springRelease
    
    // The allowable swipe direction(s)
    open var revealDirection: BWSwipeCellRevealDirection = .both
    
    // The current state of the cell (either normal or past a threshold)
    open fileprivate(set) var state: BWSwipeCellState = .normal
    
    // The point at which pan elasticity starts, and `state` changes. Defaults to the height of the `UITableViewCell` (i.e. when it form a perfect square)
    open lazy var threshold: CGFloat = {
        return self.frame.height
    }()
    
    // A number between 0 and 1 to indicate progress toward reaching threshold in the current swiping direction. Useful for changing UI gradually as the user swipes.
    open var progress: CGFloat {
        get {
            let progress = abs(self.contentView.frame.origin.x) / self.threshold
            return (progress > 1) ? 1 : progress
        }
    }
    
    // Should we allow the cell to be pulled past the threshold at all? (.SwipeThrough cells will ignore this)
    open var shouldExceedThreshold: Bool = true
    
    // Control how much elastic resistance there is past threshold, if it can be exceeded. Default is `0.7` and `1.0` would mean no elastic resistance
    open var panElasticityFactor: CGFloat = 0.7
    
    // Length of the animation on release
    open var animationDuration: Double = 0.2
    
    // BWSwipeCell Delegate
    open weak var delegate: BWSwipeCellDelegate?
    
    open lazy var handleReleaseAnimationCleanup: () -> () = { [weak self] in
        guard let this = self else { return }
        
        this.delegate?.swipeCellDidCompleteRelease?(this)
        this.cleanUp()
    }
    
    open lazy var handleAnimateCellSpringRelease: () -> () = { [weak self] in
        guard let this = self else { return }
        this.contentView.frame = this.contentView.bounds
    }

    open lazy var handleAnimateCellSlidingDoor: () -> () = { [weak self] in
        guard let this = self else { return }
        
        let pointX = this.contentView.frame.origin.x
        if pointX > 0 {
            this.contentView.frame.origin.x = this.threshold
        } else if pointX < 0 {
            this.contentView.frame.origin.x = -this.threshold
        }
    }

    open lazy var handleAnimateCellSwipeThrough: () -> () = { [weak self] in
        guard let this = self else { return }
        let direction:CGFloat = (this.contentView.frame.origin.x > 0) ? 1 : -1
        this.contentView.frame.origin.x = direction * (this.contentView.bounds.width + this.threshold)
    }
    
    // MARK: - Swipe Cell Functions
    
    open func initialize() {
        self.selectionStyle = .none
        self.contentView.backgroundColor = UIColor.white
        let panGestureRecognizer: UIPanGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(BWSwipeCell.handlePanGesture(_:)))
        panGestureRecognizer.delegate = self
        self.addGestureRecognizer(panGestureRecognizer)
        
        let backgroundView: UIView = UIView(frame: self.frame)
        backgroundView.backgroundColor = UIColor.white
        self.backgroundView = backgroundView
    }
    
    open func cleanUp() {
        self.state = .normal
    }
    
    open func handlePanGesture(_ panGestureRecognizer: UIPanGestureRecognizer) {
        let translation: CGPoint = panGestureRecognizer.translation(in: panGestureRecognizer.view)
        var panOffset: CGFloat = translation.x
        
        // If we have elasticity to consider, do some extra calculations for panOffset
        if self.type != .swipeThrough && abs(translation.x) > self.threshold {
            if self.shouldExceedThreshold {
                let offset: CGFloat = abs(translation.x)
                panOffset = offset - ((offset - self.threshold) * self.panElasticityFactor)
                panOffset *= translation.x < 0 ? -1.0 : 1.0
            } else {
                // If we don't allow exceeding the threshold
                panOffset = translation.x < 0 ? -self.threshold : self.threshold
            }
        }
        
        // Start, continue or complete the swipe gesture
        let actualTranslation: CGPoint = CGPoint(x: panOffset, y: translation.y)
        if panGestureRecognizer.state == .began && panGestureRecognizer.numberOfTouches > 0 {
            let newTranslation = CGPoint(x: self.contentView.frame.origin.x, y: 0)
            panGestureRecognizer.setTranslation(newTranslation, in: panGestureRecognizer.view)
            
            if self.shouldStartSwiping() {
                self.didStartSwiping()
                self.animateContentViewForPoint(newTranslation)
            } else {
                panGestureRecognizer.isEnabled = false
                panGestureRecognizer.isEnabled = true
            }
        }
        else {
            if panGestureRecognizer.state == .changed && panGestureRecognizer.numberOfTouches > 0 {
                self.animateContentViewForPoint(actualTranslation)
            }
            else {
                self.resetCellPosition()
            }
        }
    }
    
    open func shouldStartSwiping() -> Bool {        
        return self.delegate?.swipeCellShouldStartSwiping?(self) ?? true
    }
    
    open func didStartSwiping() {
        self.delegate?.swipeCellDidStartSwiping?(self)
    }
    
    open func animateContentViewForPoint(_ point: CGPoint) {
        if (point.x > 0 && self.revealDirection == .left) || (point.x < 0 && self.revealDirection == .right) || self.revealDirection == .both {
            self.contentView.frame = self.contentView.bounds.offsetBy(dx: point.x, dy: 0)
            let previousState = state
            if point.x >= self.threshold {
                self.state = .pastThresholdLeft
            }
            else if point.x < -self.threshold {
                self.state = .pastThresholdRight
            }
            else {
                self.state = .normal
            }
            
            if self.state != previousState {
                self.delegate?.swipeCellDidChangeState?(self)
            }
            self.delegate?.swipeCellDidSwipe?(self)
        }
        else {
            if (point.x > 0 && self.revealDirection == .right) || (point.x < 0 && self.revealDirection == .left) {
                self.contentView.frame = self.contentView.bounds.offsetBy(dx: 0, dy: 0)
            }
        }
    }
    
    open func resetCellPosition() {
        self.delegate?.swipeCellWillRelease?(self)
        if self.type == .springRelease || self.state == .normal {
            self.animateCellSpringRelease()
        } else if self.type == .slidingDoor {
            self.animateCellSlidingDoor()
        } else {
            self.animateCellSwipeThrough()
        }
    }
    
    // MARK: - Reset animations
    
    open func animateCellSpringRelease() {
        UIView.animate(withDuration: self.animationDuration,
            delay: 0,
            options: .curveEaseOut,
            animations: {
                self.handleAnimateCellSpringRelease()
            }, completion: { finished in
                self.handleReleaseAnimationCleanup()
            })
    }
    
    open func animateCellSlidingDoor() {
        UIView.animate(withDuration: self.animationDuration,
            delay: 0,
            options: .allowUserInteraction,
            animations: {
                self.handleAnimateCellSlidingDoor()
            },
            completion: { finished in
                self.handleReleaseAnimationCleanup()
            })
    }
    
    open func animateCellSwipeThrough() {
        UIView.animate(withDuration: self.animationDuration,
            delay: 0,
            options: UIViewAnimationOptions.curveLinear,
            animations: {
                self.handleAnimateCellSwipeThrough()
            },
            completion: { finished in
                self.handleReleaseAnimationCleanup()
            })
    }
    
    // MARK: - UITableViewCell Overrides
    
    public override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.initialize()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.initialize()
    }
    
    open override func prepareForReuse() {
        super.prepareForReuse()
        self.cleanUp()
    }
    
    open override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }
    
    open override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer.isKind(of: UIPanGestureRecognizer.self) && self.revealDirection != .none {
            let pan:UIPanGestureRecognizer = gestureRecognizer as! UIPanGestureRecognizer
            let translation: CGPoint = pan.translation(in: self.superview)
            return (fabs(translation.x) / fabs(translation.y) > 1) ? true : false
        }
        return false
    }
}
