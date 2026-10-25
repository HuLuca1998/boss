import Foundation

// A timed-out target is eligible again after 60 seconds; other targets continue.
struct HuntRetryPolicy {
    private var deferredUntil:[String:TimeInterval]=[:]
    mutating func deferTarget(_ id:String,now:TimeInterval)->TimeInterval {
        deferredUntil[id]=now+HuntContinuity.retryInterval
        return HuntContinuity.retryInterval
    }
    func eligible(_ id:String,now:TimeInterval)->Bool {(deferredUntil[id] ?? 0)<=now}
    mutating func succeeded(_ id:String){deferredUntil[id]=nil}
}
