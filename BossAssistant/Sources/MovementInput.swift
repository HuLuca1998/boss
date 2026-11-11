import Foundation

// The foreground guard runs before any keyboard state is read.
enum MovementInput {
    static let bindings:[(UInt16,Int)]=[(123,37),(124,39),(125,40),(126,38),(0,37),(2,39),(1,40),(13,38),(53,27)]
    static func keys(enabled:Bool,frontmostBundle:String?,isDown:(UInt16)->Bool)->[Int] {
        guard enabled,frontmostBundle == "com.yzlm.game" else{return []}
        return Array(Set(bindings.compactMap{native,game in isDown(native) ? game : nil})).sorted()
    }
}

// Resolve opposite keys before the client can turn their sum into a stop command.
struct MovementContinuity {
    static func delay(_ value:Int)->Int {min(300,max(0,value))}
    private var previous:Set<Int>=[]
    private var winners:[Int:Int]=[:]
    private var heldDirection:[Int]=[]
    private var releasedAt:TimeInterval?
    mutating func reset(){self=Self()}
    mutating func update(keys:[Int],active:Bool,now:TimeInterval,delayMilliseconds:Int)->[Int] {
        guard active else{reset();return []}
        let current=Set(keys)
        var direction:[Int]=[]
        for (axis,pair) in [[37,39],[38,40]].enumerated() {
            let down=pair.filter{current.contains($0)}
            let fresh=down.filter{!previous.contains($0)}
            // Simultaneous samples have no observable ordering: preserve the prior direction.
            if fresh.count==1 {winners[axis]=fresh[0]}
            if let winner=winners[axis],down.contains(winner){direction.append(winner)}
            else if let first=down.first {winners[axis]=first;direction.append(first)}
        }
        previous=current
        if !direction.isEmpty {heldDirection=direction;releasedAt=nil}
        else if !heldDirection.isEmpty {
            if releasedAt==nil {releasedAt=now}
            if now-(releasedAt ?? now)<Double(Self.delay(delayMilliseconds))/1000 {direction=heldDirection}
            else {heldDirection=[];releasedAt=nil}
        }
        if current.contains(27){direction.append(27)}
        return direction.sorted()
    }
}
