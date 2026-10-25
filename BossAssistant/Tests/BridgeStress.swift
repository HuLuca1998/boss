import Foundation
import Darwin
@main struct BridgeStress {
    @MainActor static func main(){
        let bridge=Bridge(token:"stress-test-token")
        var started=false
        bridge.onReady={port in print("PORT \(port)");fflush(stdout)}
        bridge.onChange={connected in
            guard connected,!started else{return};started=true
            Task{@MainActor in
                let passed=await withTaskGroup(of:Bool.self,returning:Int.self){group in
                    for index in 0..<2000 {group.addTask {
                        do {
                            let data=try await bridge.request("echo",fields:["value":index])
                            let json=try JSONSerialization.jsonObject(with:data) as? [String:Int]
                            return json?["value"]==index
                        }catch{return false}
                    }}
                    var count=0;for await ok in group {if ok {count+=1}};return count
                }
                guard passed==2000 else{print("FAIL replies \(passed)");exit(1)}
                let disconnected=await withTaskGroup(of:Bool.self,returning:Int.self){group in
                    for _ in 0..<100 {group.addTask {
                        do{_=try await bridge.request("drop");return false}catch{return true}
                    }}
                    var count=0;for await ok in group {if ok {count+=1}};return count
                }
                guard disconnected==100 else{exit(2)}
                print("PASS 2000 concurrent matching replies and 100 pending disconnect failures without crash or duplicate completion");fflush(stdout);exit(0)
            }
        }
        do{try bridge.start(port:0)}catch{exit(3)}
        DispatchQueue.main.asyncAfter(deadline:.now()+30){exit(4)}
        dispatchMain()
    }
}
