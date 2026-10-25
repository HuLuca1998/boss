import Foundation
@main struct RecoveryPolicyTests {
 static func main()throws {
  var p=RecoveryPolicy();p.observe(token:"a",now:0)
  for _ in 0..<100 {p.observe(token:"a",now:40)}
  assert(!p.locked && p.hits.count==1)
  p.observe(token:"b",now:59);assert(p.locked)
  let data=try JSONEncoder().encode(p);p=try JSONDecoder().decode(RecoveryPolicy.self,from:data);assert(p.locked)
  p.observe(token:"c",now:1000);assert(p.locked,"Lock cannot expire on its own")
  p.unlock();p.observe(token:"b",now:1001);assert(!p.locked,"Re-reading the held popup after manual resume must not recount it")
  p.observe(token:"d",now:1002);assert(!p.locked);p.observe(token:"e",now:1063);assert(!p.locked)
  p.observe(token:"f",now:1064);assert(p.locked)
  print("PASS: rolling 60-second/two-event lock, duplicate event/popup observations, durable lock and manual-only unlock")
 }
}
