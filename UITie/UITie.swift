//
//  AsyncBind.swift
//  Signal
//
//  Created by Mikhail Vroubel on 07/02/2015.
//
//

import UIKit

@objc public class UITie : NSObject {
    public struct Consts {
        static let Get = "Get"
        static let Set = "Set"
        static let Write = "Write"
        static let Read = "Read"
        static let Bind = "Bind"
        static let Dot:Character = "."
        static let At = "@"
    }
    
    var tieKey:String
    var left:NSObject
    
    public init(tieKey:String, target:NSObject) {
        (self.tieKey, self.left) = (tieKey, target)
        super.init()
    }
    static var ties:[String:(NSObject,String,NSObject,String,Mapper) -> Void] = [
        Consts.Get: {left, leftKey, right, rightKey, map in
            if let x: AnyObject = map.to(right.valueForKeyPath(rightKey)) {
                left.setValue(x , forKeyPath: leftKey)
            }
        },
        Consts.Set: {right, rightKey, left, leftKey, map in // reverse args
            if let x: AnyObject = map.to(right.valueForKeyPath(rightKey)) {
                left.setValue(x , forKeyPath: leftKey)
            }
        },
        Consts.Write: {left, leftKey, right, rightKey, map in
            right.setValue(map.back(left.valueForKeyPath(leftKey)), forKeyPath: rightKey); ()
            weak var o = left.observeKeyPath(leftKey) { [weak right] x in
                right?.setValue(map.back(x), forKeyPath: rightKey); ()
            }
            right.observe {o?.cancel()}
        },
        Consts.Read: {right, rightKey, left, leftKey, map in // reverse args
            right.setValue(map.to(left.valueForKeyPath(leftKey)), forKeyPath: rightKey); ()
            weak var o = left.observeKeyPath(leftKey) { [weak right] x in
                right?.setValue(map.to(x), forKeyPath: rightKey); ()
            }
            right.observe {o?.cancel()}
        },
        Consts.Bind: {left, leftKey, right, rightKey, map in
            left.setValue(map.to(right.valueForKeyPath(rightKey)), forKeyPath: leftKey); ()
            weak var l = left.observeKeyPath(leftKey) { [weak right] x in
                right?.setValue(map.back(x), forKeyPath: rightKey); ()
            }
            weak var prev:NSObject?
            weak var r = right.observeKeyPath(rightKey) { [weak left] x in
                if x != prev {
                    prev = x
                    left?.setValue(map.to(x), forKeyPath: leftKey); ()
                }
            }
            _ = [left,right].map {
                $0.observe {
                    _ = [l,r].map {$0?.cancel()}
                }
            }
        }
    ]
    var tied = false;
    func tie(leftKey:String,rightKey:String, map:Mapper) {
        if (!tied) {
            if let right = self.left.source(rightKey, target: self.left) {
                tied = true;
                UITie.ties[self.tieKey]!(self.left, leftKey,right, rightKey, map)
            }
        }
    }
    public override func setValue(value: AnyObject?, forKeyPath keyPath: String) {
        let rightKeys = (value as! NSString).componentsSeparatedByString(Consts.At)
        let map = rightKeys.count == 2 ? Mapper.joinPath(rightKeys[0]) : Mapper()
        let rightKey = rightKeys.last!
        tie(keyPath, rightKey: rightKey, map: map)
        if (!tied) {
            left.observeKeyPath("tieSource", scope:self) {[weak self] _ in
                self!.tie(keyPath, rightKey: rightKey, map: map)
            }
            dispatch_async(dispatch_get_main_queue()) {
                self.tie(keyPath, rightKey: rightKey, map: map)
            }
        }
    }
}

extension NSObject {
    @IBOutlet weak var tieSource:NSObject? {
        get{
            return objc_getAssociatedObject(self, unsafeAddressOf(UITie.self)) as? NSObject
        } set {
            objc_setAssociatedObject(self, unsafeAddressOf(UITie.self), newValue, .OBJC_ASSOCIATION_ASSIGN)
        }
    }
    public func source(key:String, target:NSObject) -> NSObject? {
        return tieSource
    }
    public func Get ()-> UITie {
        return UITie(tieKey: UITie.Consts.Get, target: self)
    }
    public func Read ()-> UITie {
        return UITie(tieKey: UITie.Consts.Read, target: self)
    }
    public func Write ()-> UITie {
        return UITie(tieKey: UITie.Consts.Write, target: self)
    }
    public func Bind ()-> UITie {
        return UITie(tieKey: UITie.Consts.Bind, target: self)
    }
}

extension UIResponder {
    override public func source(key: String, target: NSObject) -> NSObject? {
        return (tieSource ?? nextResponder())?.source(key, target: target);
    }
}

extension UIViewController {
    override public func source(key: String, target: NSObject) -> NSObject? {
        return tieSource?.source(key, target: target) ?? self
    }
}

extension UITableViewCell {
    override public func source(key: String, target: NSObject) -> NSObject? {
        return tieSource?.source(key, target: target) ?? self
    }
}

extension UICollectionViewCell {
    override public func source(key: String, target: NSObject) -> NSObject? {
        return tieSource?.source(key, target: target) ?? self
    }
}