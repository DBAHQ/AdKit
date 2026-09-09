//
//  ContainerView.swift
//  AdKit
//

import UIKit

class ContainerView: UIView {
    
    // MARK: - Properties
    
    var edgeInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16) {
        didSet {
            setupConstraints()
        }
    }
    
    // MARK: - Views
    
    lazy var stackView = UIStackView()
    
    // MARK: - Constraints
    
    private lazy var leftConstraint = stackView.leftAnchor.constraint(equalTo: leftAnchor)
    private lazy var topConstraint = stackView.topAnchor.constraint(equalTo: topAnchor)
    private lazy var rightConstraint = stackView.rightAnchor.constraint(equalTo: rightAnchor)
    private lazy var bottomConstraint = stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
    
    // MARK: - Lifecycle
    
    override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)
        setupConstraints()
    }
    
    // MARK: - Setups
    
    private func setupConstraints() {
        if stackView.superview == nil {
            addSubview(stackView)
        }
        
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        leftConstraint.isActive = true
        topConstraint.isActive = true
        rightConstraint.isActive = true
        bottomConstraint.isActive = true
        
        leftConstraint.constant = edgeInsets.left
        topConstraint.constant = edgeInsets.top
        rightConstraint.constant = -edgeInsets.right
        bottomConstraint.constant = -edgeInsets.bottom
    }
    
    // MARK: - Set
    
    func setViews(_ views: [UIView]) {
        views.forEach { [weak self] (view) in
            self?.stackView.addArrangedSubview(view)
        }
    }
    
}
