import UIKit

extension UIViewController {
    func findNavigationController() -> UINavigationController? {
        if let navigationController = self.navigationController {
            return navigationController
        }
        
        // Check if parent has a navigation controller
        if let parent = self.parent {
            return parent.findNavigationController()
        }
        
        // Check if presented view controller has a navigation controller
        if let presentedVC = self.presentedViewController {
            return presentedVC.findNavigationController()
        }
        
        // No navigation controller found
        return nil
    }
    
    // Add a method to recursively find a view controller of specific type
    func findViewController<T: UIViewController>(ofType type: T.Type) -> T? {
        if let vc = self as? T {
            return vc
        }
        
        // Check in children
        for child in children {
            if let found = child.findViewController(ofType: type) {
                return found
            }
        }
        
        // Check in presented controller
        if let presented = presentedViewController,
           let found = presented.findViewController(ofType: type) {
            return found
        }
        
        return nil
    }
} 