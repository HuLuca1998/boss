import Foundation
@main struct HuntLocationTests {
    static func main()throws {
        func snapshot(kind:String?,ready:Bool=true,area:Int=7,teleport:Bool=false)throws->Snapshot {
            var value:[String:Any]=["areaId":area,"fieldId":21,"serverTime":1,"rows":[],"isTeleporting":teleport]
            if let kind {value["location"]=["kind":kind,"name":"当前场景","sceneType":kind == "dungeon" ? 2 : 1,"ready":ready]}
            return try JSONDecoder().decode(Snapshot.self,from:JSONSerialization.data(withJSONObject:value))
        }
        assert(HuntLocationGate.evaluate(try! snapshot(kind:"wild"),area:7) == .ready)
        assert(HuntLocationGate.evaluate(try! snapshot(kind:"dungeon"),area:7) == .away)
        assert(HuntLocationGate.evaluate(try! snapshot(kind:"wild",area:8),area:7) == .away)
        assert(HuntLocationGate.evaluate(try! snapshot(kind:"wild",ready:false),area:7) == .transition)
        assert(HuntLocationGate.evaluate(try! snapshot(kind:"loading"),area:7) == .transition)
        assert(HuntLocationGate.evaluate(try! snapshot(kind:"wild",teleport:true),area:7) == .transition)
        assert(HuntLocationGate.evaluate(try! snapshot(kind:nil),area:7) == .unsupported)
        // A long dungeon detour retains the original area and only a ready return resumes.
        let sequence=[try snapshot(kind:"wild")]+(0..<100).map{_ in try! snapshot(kind:"dungeon")}+[try snapshot(kind:"wild",ready:false),try snapshot(kind:"wild")]
        let states=sequence.map{HuntLocationGate.evaluate($0,area:7)}
        assert(states.first == .ready && states.last == .ready)
        assert(states.dropFirst().dropLast().filter{$0 == .ready}.isEmpty)
        print("PASS: original area, dungeon pause, different area, loading, teleport, legacy runtime, ready return after long detour")
    }
}
