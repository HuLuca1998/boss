import Foundation

// Only an explicit user stop clears requested. Recovery events preserve the task.
struct HuntContinuity {
    enum PauseReason:String {case manual,away,connection,unavailable,stalled,maintenance,account}
    static let retryInterval:TimeInterval=60
    private(set) var requested=false
    private(set) var area:Int?
    private(set) var retryAt:TimeInterval=0
    private(set) var reason:PauseReason?
    private(set) var movementHeld=false
    mutating func start(area:Int){requested=true;self.area=area;retryAt=0;reason=nil;movementHeld=false}
    mutating func stop(){requested=false;area=nil;retryAt=0;reason=nil;movementHeld=false}
    mutating func pause(_ reason:PauseReason,now:TimeInterval,restartDelay:Bool=false){
        guard requested else{return}
        if self.reason != reason || restartDelay {retryAt=max(retryAt,now+Self.retryInterval)}
        self.reason=reason
    }
    mutating func manualInput(pressed:Bool,now:TimeInterval){
        guard requested else{return}
        if pressed || movementHeld {retryAt=max(retryAt,now+Self.retryInterval);reason = .manual}
        movementHeld=pressed
    }
    @discardableResult mutating func requestResume()->Bool {
        guard requested, !movementHeld else{return false}
        retryAt=0;return true
    }
    func remaining(now:TimeInterval)->Int {max(0,Int(ceil(retryAt-now)))}
    func canResume(now:TimeInterval)->Bool {requested && !movementHeld && now>=retryAt}
    mutating func resumed(){guard requested else{return};reason=nil;retryAt=0}
}

// Observe the game's own clock; never alter timers or force an engine frame.
struct HuntProgress {
    private var scene:String?
    private var gameTime:Double?
    private var advancedAt:TimeInterval?
    mutating func observe(_ snapshot:Snapshot,now:TimeInterval){
        guard let location=snapshot.location,location.kind=="wild",location.ready,let time=location.gameTime,time.isFinite else{
            scene=nil;gameTime=nil;advancedAt=nil;return
        }
        let key="\(snapshot.areaId):\(snapshot.fieldId):\(location.sceneType)"
        if key != scene || time != gameTime {advancedAt=now}
        scene=key;gameTime=time
    }
    func stalled(now:TimeInterval)->Bool {advancedAt.map{now-$0>=15} ?? false}
}
