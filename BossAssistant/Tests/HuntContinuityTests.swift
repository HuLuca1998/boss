import Foundation
@main struct HuntContinuityTests {
    static func main()throws {
        var state=HuntContinuity()
        state.start(area:7);assert(state.requested && state.canResume(now:0))
        state.pause(.away,now:10);assert(state.requested && state.area==7)
        assert(!state.canResume(now:69));assert(state.canResume(now:70))
        state.resumed();assert(state.requested && state.reason==nil)
        // Held movement is not a user stop, including long holds and focus-loss release.
        state.manualInput(pressed:true,now:100);assert(!state.canResume(now:1000))
        state.manualInput(pressed:false,now:1000);assert(!state.canResume(now:1059));assert(state.canResume(now:1060))
        state.resumed()
        for index in 0..<100 {
            let now=Double(1100+index*70)
            state.pause(.connection,now:now,restartDelay:true)
            assert(state.requested && !state.canResume(now:now+59))
            assert(state.canResume(now:now+60));state.resumed()
        }
        state.pause(.manual,now:9000)
        assert(state.requestResume() && state.canResume(now:9001),"Continue skips the automatic delay")
        state.manualInput(pressed:true,now:9002)
        assert(!state.requestResume() && !state.canResume(now:9999),"Continue cannot override a held movement key")
        state.manualInput(pressed:false,now:9003)
        assert(state.requestResume() && state.canResume(now:9003))
        state.pause(.unavailable,now:10000);state.stop()
        assert(!state.requestResume(),"Continue cannot restart a manually stopped task")
        assert(!state.requested && !state.canResume(now:1000000),"Manual stop must prevent all future automatic resumption")
        state.pause(.away,now:1000001);state.resumed();assert(!state.requested)
        var retry=HuntRetryPolicy()
        assert(retry.deferTarget("boss",now:10)==60)
        assert(!retry.eligible("boss",now:69) && retry.eligible("other",now:10) && retry.eligible("boss",now:70))
        assert(retry.deferTarget("boss",now:70)==60,"Repeated failure still uses the requested 60-second retry")
        func snapshot(clock:Double,field:Int=22)throws->Snapshot {
            let value:[String:Any]=["areaId":7,"fieldId":field,"serverTime":1,"rows":[],"location":["kind":"wild","name":"红叶王庭Ⅱ","sceneType":1,"ready":true,"gameTime":clock]]
            return try JSONDecoder().decode(Snapshot.self,from:JSONSerialization.data(withJSONObject:value))
        }
        var progress=HuntProgress()
        progress.observe(try snapshot(clock:1000),now:0);assert(!progress.stalled(now:14));assert(progress.stalled(now:15))
        progress.observe(try snapshot(clock:2000),now:16);assert(!progress.stalled(now:16))
        progress.observe(try snapshot(clock:0,field:21),now:20);assert(!progress.stalled(now:20),"Map changes reset the observation clock")
        print("PASS: continuous intent, dungeon/reconnect recovery, long manual hold, release + 60 seconds, 100 retry cycles, explicit-stop-only cancellation, fixed 60-second target retry, read-only progress observation")
    }
}
