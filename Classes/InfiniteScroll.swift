//
//  InfiniteScroll.swift
//  InfiniteScrollViewDemoSwift
//
//  Created by pronebird on 2/23/19.
//  Copyright © 2019 pronebird. All rights reserved.
//

import UIKit

private let InfiniteScrollAnimationDuration = 0.35

enum InfiniteScrollDirection {
    case vertical, horizontal
}

protocol InfiniteIndicatorViewProtocol {
    func startAnimating()
    func stopAnimating()
}

extension UIActivityIndicatorView: InfiniteIndicatorViewProtocol {}

class InfiniteScroll<ScrollViewType: UIScrollView>: NSObject, UIScrollViewDelegate {
    typealias IndicatorView = UIView & InfiniteIndicatorViewProtocol
    
    /// The scroll view associated with the infinite scroll instance
    private(set) weak var scrollView: ScrollViewType?
    
    /// A flag that indicates whether loading is in progress.
    private var isLoading = false
    
    /// Flag used to return user back to top of scroll view when loading initial content.
    private var scrollToTopWhenFinished = false
    
    /// The content inset adjustment by infinite scroll class
    private var contentInsetAdjustment = UIEdgeInsets.zero
    
    /// Called for updates
    var didBeginUpdating: ((ScrollViewType, _ finish: @escaping () -> Void) -> Void)?
    
    /// Called after infinite scroll animations finished
    var didFinishUpdating: ((ScrollViewType) -> Void)?
    
    /// Control when the infinite scroll should not appear
    var shouldBeginUpdating: (() -> Bool)?
    
    /// The direction that the infinite scroll is working in.
    var scrollDirection: InfiniteScrollDirection
    
    /// Indicator view margin (top and bottom)
    var indicatorMargins: UIEdgeInsets
    
    /// Trigger offset
    var triggerOffset: CGFloat = 0
    
    /// Flag that indicates whether infinite scroll is animating
    var isAnimatingInfiniteScroll: Bool {
        return self.isLoading
    }
    
    /// Infinite indicator view
    ///
    ///  You can set your own custom view instead of default activity indicator,
    ///  make sure it implements methods below.
    var indicatorView: IndicatorView? {
        set {
            setIndicatorView(newValue)
        }
        get {
            return internalIndicatorView
        }
    }
    
    private var internalIndicatorView: IndicatorView
    
    /// Infinite scroll activity indicator style (default: UIActivityIndicatorViewStyleGray on iOS, UIActivityIndicatorViewStyleWhite on tvOS)
    var indicatorViewStyle: UIActivityIndicatorViewStyle {
        didSet {
            updateActivityIndicatorStyle()
        }
    }
    
    private var contentOffsetObserver: NSKeyValueObservation?
    private var contentSizeObserver: NSKeyValueObservation?
    
    init(scrollView: ScrollViewType, scrollDirection: InfiniteScrollDirection = .vertical) {
        self.scrollView = scrollView
        self.scrollDirection = scrollDirection
        
        switch scrollDirection {
        case .horizontal:
            indicatorMargins = UIEdgeInsets(top: 11, left: 0, bottom: 11, right: 0)
        case .vertical:
            indicatorMargins = UIEdgeInsets(top: 0, left: 11, bottom: 0, right: 11)
        }
        
        #if os(tvOS)
            indicatorViewStyle = .white
            internalIndicatorView = UIActivityIndicatorView(activityIndicatorStyle: indicatorViewStyle)
        #else
            indicatorViewStyle = .gray
            internalIndicatorView = UIActivityIndicatorView(activityIndicatorStyle: indicatorViewStyle)
        #endif
        
        super.init()
        
        scrollView.panGestureRecognizer.addTarget(self, action: #selector(handlePanGesture))
        
        contentOffsetObserver = scrollView.observe(\.contentOffset, options: [.new], changeHandler: { [weak self] (scrollView, change) in
            if let contentOffset = change.newValue {
                self?.contentOffsetDidChange(contentOffset)
            }
        })
        
        contentSizeObserver = scrollView.observe(\.contentSize, options: .new, changeHandler: { [weak self] (scrollView, change) in
            if let contentSize = change.newValue {
                self?.contentSizeDidChange(contentSize)
            }
        })
    }
    
    deinit {
        self.scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(handlePanGesture))
        self.indicatorView?.removeFromSuperview()        
    }
    
    private func updateActivityIndicatorStyle() {
        if let activityIndicator = internalIndicatorView as? UIActivityIndicatorView {
            activityIndicator.activityIndicatorViewStyle = indicatorViewStyle
        }
    }
    
    private func setIndicatorView(_ indicatorView: IndicatorView?) {
        let oldIndicatorView = internalIndicatorView
        
        guard oldIndicatorView !== indicatorView else { return }
        
        let newIndicatorView = indicatorView ?? UIActivityIndicatorView(activityIndicatorStyle: indicatorViewStyle)
        
        internalIndicatorView = newIndicatorView
        
        oldIndicatorView.removeFromSuperview()
        scrollView?.addSubview(newIndicatorView)
    }
    
    private func indicatorRowFrame() -> CGRect {
        guard let scrollView = scrollView else { return .zero }
        
        let contentSize = scrollView.contentSize
        
        switch scrollDirection {
        case .horizontal:
            return CGRect(
                x: contentSize.width,
                y: 0,
                width: internalIndicatorView.bounds.width + indicatorMargins.left + indicatorMargins.right,
                height: contentSize.height
            )
            
        case .vertical:
            return CGRect(
                x: 0,
                y: contentSize.height,
                width: contentSize.width,
                height: internalIndicatorView.bounds.height + indicatorMargins.top + indicatorMargins.bottom
            )
        }
    }
    
    private func layoutIndicatorView() {
        let frame = indicatorRowFrame()
        let center = CGPoint(x: frame.midX, y: frame.midY)
        
        if !self.internalIndicatorView.center.equalTo(center) {
            self.internalIndicatorView.center = center
        }
    }
    
    private func beginIfNeeded(forceScroll: Bool) {
        guard !self.isLoading else { return }
        
        print("Begin.")
        
        if self.shouldBeginUpdating?() ?? true {
            startAnimating(forceScroll: forceScroll)
            
            self.perform(#selector(callDidBeginHandler), with: nil, afterDelay: 0.1, inModes: [.defaultRunLoopMode])
        }
    }
    
    @objc private func callDidBeginHandler() {
        guard let scrollView = scrollView else { return }
        
        self.didBeginUpdating?(scrollView, { [weak self] () -> Void in
            self?.finish()
        })
    }
    
    private func startAnimating(forceScroll: Bool) {
        guard let scrollView = scrollView else { return }
        
        let frame = indicatorRowFrame()
        var contentInsetAdjustment = UIEdgeInsets.zero
        
        // make a room to accommodate the indicator view
        switch scrollDirection {
        case .horizontal:
            contentInsetAdjustment.right = frame.width
            
        case .vertical:
            contentInsetAdjustment.bottom = frame.height
        }
        
        self.contentInsetAdjustment = contentInsetAdjustment
        self.isLoading = true
        
        // scroll to top if scroll view had no content before update
        self.scrollToTopWhenFinished = !scrollViewSubclassHasContent()

        self.internalIndicatorView.isHidden = false
        self.internalIndicatorView.startAnimating()
        
        layoutIndicatorView()
        
        setScrollViewContentInset(scrollView.contentInset + contentInsetAdjustment, animated: true) { (finished) in
            if finished {
                self.scrollToIndicatorViewIfNeeded(reveal: true, force: forceScroll)
            }
        }
        
        print("Start animating")
    }
    
    private func stopAnimating() {
        guard let scrollView = scrollView else { return }
        
        forceUpdateTableView()
        
        setScrollViewContentInset(scrollView.contentInset - self.contentInsetAdjustment, animated: true) { (finished) in
            // initiate scroll to the bottom if due to user interaction contentOffset.y
            // stuck somewhere between last cell and activity indicator
            if finished {
                if self.scrollToTopWhenFinished {
                    self.scrollToTop()
                } else {
                    self.scrollToIndicatorViewIfNeeded(reveal: false, force: false)
                }
            }
            
            // stop animating the indicator view
            self.internalIndicatorView.stopAnimating()
            self.internalIndicatorView.isHidden = true
            
            self.isLoading = false
            
            self.didFinishUpdating?(scrollView)
        }
        
        self.contentInsetAdjustment = .zero
        
        print("Stop animating")
    }
    
    private func scrollToIndicatorViewIfNeeded(reveal: Bool, force: Bool) {
        guard let scrollView = scrollView else { return }
        
        // do not interfere with a user
        guard !scrollView.isDragging else { return }
        
        // filter out calls from pan gesture
        guard isLoading else { return }
        
        forceUpdateTableView()
        
        let frame = indicatorRowFrame()
        let contentInsetWithoutAdjustment = self.contentInsetWithSafeAreaInsets() - self.contentInsetAdjustment
        var visibleBounds = scrollView.bounds
        
        switch scrollDirection {
        case .horizontal:
            visibleBounds.size.width -= contentInsetWithoutAdjustment.right
            
        case .vertical:
            visibleBounds.size.height -= contentInsetWithoutAdjustment.bottom
        }
        
        switch scrollDirection {
        case .horizontal:
            if frame.intersects(visibleBounds) || force {
                print("Scroll to infinite indicator view. Reveal: \(reveal)")
                
                scrollView.setContentOffset(
                    CGPoint(
                        x: reveal
                            ? frame.minX - scrollView.bounds.width + contentInsetWithoutAdjustment.right
                            : frame.maxX - scrollView.bounds.width + contentInsetWithoutAdjustment.right,
                        y: scrollView.contentOffset.y
                ), animated: true)
            }
            break
            
        case .vertical:
            if frame.intersects(visibleBounds) || force {
                print("Scroll to infinite indicator view. Reveal: \(reveal)")
                
                if let tableView = scrollView as? UITableView {
                    scrollToBottomOfTableView(tableView, reveal: reveal)
                } else {
                    scrollView.setContentOffset(
                        CGPoint(
                            x: scrollView.contentOffset.x,
                            y: reveal
                                ? frame.maxY - scrollView.bounds.height + contentInsetWithoutAdjustment.bottom
                                : frame.minY  - scrollView.bounds.height + contentInsetWithoutAdjustment.bottom
                    ), animated: true)
                }
                
            }
        }
    }
    
    private func scrollViewSubclassHasContent() -> Bool {
        guard let scrollView = scrollView else { return false }
        
        if let tableView = scrollView as? UITableView {
            switch scrollDirection {
            case .horizontal:
                return tableView.contentSize.width > 1
            case .vertical:
                return tableView.contentSize.height > 1
            }
        } else {
            switch scrollDirection {
            case .horizontal:
                return scrollView.contentSize.width > 0
            case .vertical:
                return scrollView.contentSize.height > 0
            }
        }
    }
    
    private func setScrollViewContentInset(_ contentInset: UIEdgeInsets, animated: Bool, completion: ((Bool) -> Void)? ) {
        print("Update content insets: \(contentInset)")
        if animated {
            UIView.animate(withDuration: InfiniteScrollAnimationDuration, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState], animations: {
                self.scrollView?.contentInset = contentInset
            }, completion: completion)
        } else {
            UIView.performWithoutAnimation {
                self.scrollView?.contentInset = contentInset
            }
            completion?(true)
        }
    }
    
    @objc private func handlePanGesture(_ gestureRecognizer: UIGestureRecognizer) {
        if case .ended = gestureRecognizer.state {
            scrollToIndicatorViewIfNeeded(reveal: true, force: false)
        }
    }
    
    private func actionablePoint() -> CGPoint {
        guard let scrollView = self.scrollView else { return .zero }
        
        let contentSize = scrollView.contentSize
        let contentInsetWithoutAdjustment = self.contentInsetWithSafeAreaInsets() - self.contentInsetAdjustment
        
        switch scrollDirection {
        case .vertical:
            let targetContentOffset = contentSize.height - scrollView.bounds.size.height - self.triggerOffset
            let targetContentOffsetWithSafeAreaOcclusion = targetContentOffset + contentInsetWithoutAdjustment.bottom
            
            return CGPoint(x: 0, y: targetContentOffsetWithSafeAreaOcclusion)
            
        case .horizontal:
            let targetContentOffset = contentSize.width - scrollView.bounds.size.width - self.triggerOffset
            let targetContentOffsetWithSafeAreaOcclusion = targetContentOffset + contentInsetWithoutAdjustment.right
            
            return CGPoint(x: targetContentOffsetWithSafeAreaOcclusion, y: 0)
        }
    }
    
    /// Returns the accumulated value of contentInset which
    /// On iOS 11: contentInset + safeAreaInsets
    /// On iOS < 11: contentInset
    private func contentInsetWithSafeAreaInsets() -> UIEdgeInsets {
        guard let scrollView = scrollView else { return .zero }
        
        if #available(iOS 11.0, *) {
            // on iOS 11.0+ adjustedContentInset contains the accumulated value of:
            // contentInset + safeAreaInsets
            return scrollView.adjustedContentInset
        } else {
            // on iOS < 11 contentInset contains the accumulated value
            return scrollView.contentInset
        }
    }
    
    private func scrollToTop() {
        guard let scrollView = scrollView else { return }
        
        let contentInset = contentInsetWithSafeAreaInsets()
        var contentOffset = scrollView.contentOffset
        
        switch scrollDirection {
        case .horizontal:
            contentOffset.x = contentInset.left * -1
            
        case .vertical:
            contentOffset.y = contentInset.top * -1
        }
        
        scrollView.setContentOffset(contentOffset, animated: true)
    }
    
    private func scrollToBottomOfTableView(_ tableView: UITableView, reveal: Bool) {
        let lastSection = tableView.numberOfSections - 1
        let numRows = lastSection >= 0 ? tableView.numberOfRows(inSection: lastSection) : 0
        let lastRow = numRows - 1
        
        if lastSection >= 0 && lastRow >= 0 {
            let indexPath = IndexPath(row: lastRow, section: lastSection)
            let scrollPos: UITableViewScrollPosition = reveal ? .top : .bottom
            
            tableView.scrollToRow(at: indexPath, at: scrollPos, animated: true)
        } else {
            tableView.setContentOffset(.zero, animated: true)
        }
    }
    
    private func forceUpdateTableView() {
        // force table view to update its content size
        // see https://github.com/pronebird/UIScrollView-InfiniteScroll/issues/31
        if let tableView = scrollView as? UITableView {
            tableView.contentSize = tableView.sizeThatFits(
                CGSize(
                    width: tableView.frame.width,
                    height: CGFloat.greatestFiniteMagnitude
                )
            )
        }
    }
    
    private func contentOffsetDidChange(_ contentOffset: CGPoint) {
        guard let scrollView = self.scrollView else { return }
        
        // is user initiated?
        guard scrollView.isDragging else { return }
        
        let actionablePoint = self.actionablePoint()
        let velocity = scrollView.panGestureRecognizer.velocity(in: scrollView)
        
        switch scrollDirection {
        case .horizontal:
            if contentOffset.x > actionablePoint.x && velocity.x <= 0 {
                beginIfNeeded(forceScroll: false)
            }
            
        case .vertical:
            if contentOffset.y > actionablePoint.y && velocity.y <= 0 {
                beginIfNeeded(forceScroll: false)
            }
        }
    }
    
    private func contentSizeDidChange(_ contentSize: CGSize) {
        layoutIndicatorView()
    }
    
    func begin(forceScroll: Bool = false) {
        beginIfNeeded(forceScroll: forceScroll)
    }
    
    func finish() {
        guard self.isLoading else { return }
        
        stopAnimating()
    }
}

private extension UIEdgeInsets {
    static func + (lhs: UIEdgeInsets, rhs: UIEdgeInsets) -> UIEdgeInsets {
        return UIEdgeInsets(
            top: lhs.top + rhs.top,
            left: lhs.left + rhs.left,
            bottom: lhs.bottom + rhs.bottom,
            right: lhs.right + rhs.right
        )
    }
    static func - (lhs: UIEdgeInsets, rhs: UIEdgeInsets) -> UIEdgeInsets {
        return UIEdgeInsets(
            top: lhs.top - rhs.top,
            left: lhs.left - rhs.left,
            bottom: lhs.bottom - rhs.bottom,
            right: lhs.right - rhs.right
        )
    }
}
