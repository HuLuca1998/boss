import Foundation
@main struct HuntRetryTests {
    static func main(){
        var retry=HuntRetryPolicy()
        assert(retry.eligible("boss",now:100))
        assert(retry.deferTarget("boss",now:100)==60)
        assert(!retry.eligible("boss",now:159))
        assert(retry.eligible("other",now:100),"One failure must not block other bosses")
        assert(retry.eligible("boss",now:160),"Expired deferral must retry")
        assert(retry.deferTarget("boss",now:160)==60)
        for _ in 0..<20 {_ = retry.deferTarget("boss",now:200)}
        assert(retry.deferTarget("boss",now:200)==60,"Repeated failure must keep a 60-second retry")
        retry.succeeded("boss");assert(retry.eligible("boss",now:200));assert(retry.deferTarget("boss",now:200)==60)
        print("PASS: timeout defers only one target, other targets continue, automatic retry, fixed 60-second retry, reset after success")
    }
}
