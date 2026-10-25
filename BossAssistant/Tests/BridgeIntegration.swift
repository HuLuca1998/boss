import Foundation
import Darwin
@main struct BridgeIntegration {
 @MainActor static func main() {
  let bridge=Bridge(token:"integration-test-token")
  bridge.onReady={port in print("PORT \(port)");fflush(stdout)}
  bridge.onError={message in fputs(message+"\n",stderr);exit(1)}
  bridge.onChange={connected in
   if connected {Task{@MainActor in
    do {let data=try await bridge.request("list");let value=try JSONSerialization.jsonObject(with:data) as? [String:Any];guard value?["areaId"] as? Int==6 else{exit(2)};print("PASS authenticated RPC");fflush(stdout);exit(0)}catch{fputs(String(describing:error),stderr);exit(3)}
   }}
  }
  do{try bridge.start(port:0)}catch{exit(4)}
  DispatchQueue.main.asyncAfter(deadline:.now()+15){exit(5)}
  dispatchMain()
 }
}
