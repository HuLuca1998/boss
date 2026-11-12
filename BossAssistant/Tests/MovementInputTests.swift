import Foundation
@main struct MovementInputTests {
    static func main(){
        var held:Set<UInt16>=[]
        var reads=0
        func sample(_ enabled:Bool=true,_ bundle:String?="com.yzlm.game")->[Int]{
            MovementInput.keys(enabled:enabled,frontmostBundle:bundle){ key in reads+=1;return held.contains(key) }
        }
        for (native,expected) in MovementInput.bindings {
            held=[native];assert(sample()==[expected],"Failed native key \(native)")
        }
        held=[18,38,19,40,20,37,12];assert(sample()==[49,50,51,81],"Skill aliases deduplicate")
        held=[13,124];assert(sample()==[38,39],"Mixed WASD/arrow diagonal")
        held=[13,126];assert(sample()==[38],"Same direction must be deduplicated")
        held.remove(13);assert(sample()==[38],"Releasing W must preserve held Up")
        held=[];assert(sample().isEmpty,"Release must stop")
        held=[0,1,2,13];reads=0
        for bundle in ["com.openai.codex","com.apple.Terminal","local.luca.HeroBossAssistant",nil] {
            assert(sample(true,bundle).isEmpty)
        }
        assert(reads==0,"Must not read any key outside focused game")
        assert(sample(false).isEmpty && reads==0,"Disabled mode must not read keys")
        var movement=MovementContinuity()
        func move(_ keys:[Int],_ time:Double,_ delay:Int=80,_ active:Bool=true)->[Int] {
            movement.update(keys:keys,active:active,now:time,delayMilliseconds:delay)
        }
        assert(move([37],0)==[37])
        assert(move([37,39],0.04)==[39],"Newest direction wins")
        assert(move([37],0.08)==[37],"Releasing newest restores held direction")
        assert(move([],0.12)==[37])
        assert(move([39],0.16)==[39],"Switch during release window has no stop")
        assert(move([],0.20)==[39])
        assert(move([],0.281).isEmpty,"Release expires")
        assert(move([38,39],1)==[38,39])
        assert(move([39],1.04)==[39],"Partial release does not retain unwanted diagonal")
        assert(move([],1.08,0).isEmpty,"Zero disables grace")
        assert(move([37],2)==[37])
        assert(move([],2.04,300,false).isEmpty,"Focus loss bypasses grace")
        assert(move([],2.08).isEmpty,"Focus restoration must not revive direction")
        assert(move([49,50,51,81],2.2)==[49,50,51,81])
        assert(move([],2.24).isEmpty,"Combat keys never receive movement release delay")
        assert(move([27],3)==[27])
        assert(move([],3.04).isEmpty,"ESC never delayed")
        assert(move([38],4)==[38])
        assert(move([],4.04,300)==[38])
        assert(move([],4.2,0).isEmpty,"Setting change applies during release")
        assert(MovementContinuity.delay(-10)==0 && MovementContinuity.delay(500)==300)
        print("PASS: opposite-key priority, release delay, zero, diagonal, focus loss, ESC and live setting changes")
        print("PASS: all eight keys, mixed diagonal, shared direction release, foreground-only sampling, disabled mode")
    }
}
