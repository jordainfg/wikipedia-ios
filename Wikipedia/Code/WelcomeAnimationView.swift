import Foundation

public class WelcomeAnimationView : UIView {
    
    // Reminder - these transforms are on WelcomeAnimationView 
    // so they can scale proportionally to the view size.
    
    var wmf_proportionalHorizontalOffset: CGFloat{
        return CGFloat(0.35).wmf_denormalizeUsingReference(self.frame.width)
    }
    var wmf_proportionalVerticalOffset: CGFloat{
        return CGFloat(0.35).wmf_denormalizeUsingReference(self.frame.height)
    }
    
    
    var wmf_rightTransform: CATransform3D{
        return CATransform3DMakeTranslation(wmf_proportionalHorizontalOffset, 0, 0)
    }
    var wmf_leftTransform: CATransform3D{
        return CATransform3DMakeTranslation(-wmf_proportionalHorizontalOffset, 0, 0)
    }
    var wmf_lowerTransform: CATransform3D{
        return CATransform3DMakeTranslation(0.0, wmf_proportionalVerticalOffset, 0)
    }
    
    
    let wmf_scaleZeroTransform = CATransform3DMakeScale(0, 0, 1)

    var wmf_scaleZeroAndLeftTransform: CATransform3D{
        return CATransform3DConcat(self.wmf_scaleZeroTransform, wmf_leftTransform)
    }
    var wmf_scaleZeroAndRightTransform: CATransform3D{
        return CATransform3DConcat(self.wmf_scaleZeroTransform, wmf_rightTransform)
    }
    var wmf_scaleZeroAndLowerLeftTransform: CATransform3D{
        return CATransform3DConcat(wmf_scaleZeroAndLeftTransform, wmf_lowerTransform)
    }
    var wmf_scaleZeroAndLowerRightTransform: CATransform3D {
          return CATransform3DConcat(wmf_scaleZeroAndRightTransform, wmf_lowerTransform)
    }
}
