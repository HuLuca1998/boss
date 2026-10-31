import Foundation
import Darwin
@main struct ExternalAPITests {
 @MainActor static func main(){
  let bridge=Bridge(token:"external-test-token")
  bridge.onReady={port in print("PORT \(port)");fflush(stdout)}
  bridge.onError={_ in exit(1)}
  do{try bridge.start(port:0)}catch{exit(2)}
  DispatchQueue.main.asyncAfter(deadline:.now()+25){exit(3)}
  dispatchMain()
 }
}
