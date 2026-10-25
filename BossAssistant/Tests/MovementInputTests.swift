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
        print("PASS: all eight keys, mixed diagonal, shared direction release, foreground-only sampling, disabled mode")
    }
}
