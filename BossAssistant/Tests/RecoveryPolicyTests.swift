import Foundation
@main struct RecoveryPolicyTests {
 static func main()throws {
  var p=RecoveryPolicy();p.observe(token:"a",now:0)
  for _ in 0..<100 {p.observe(token:"a",now:40)}
  assert(!p.locked && p.hits.count==1)
  p.observe(token:"b",now:59);assert(p.locked)
  let data=try JSONEncoder().encode(p);p=try JSONDecoder().decode(RecoveryPolicy.self,from:data);assert(p.locked)
  p.observe(token:"c",now:1000);assert(p.locked)
  assert(p.remaining(now:59)==3600)
  assert(!p.retryIfDue(now:3658));assert(p.retryIfDue(now:3659));assert(!p.locked)
  assert(!p.retryIfDue(now:9999))
  var legacy=try JSONDecoder().decode(RecoveryPolicy.self,from:Data("{\"hits\":[],\"seen\":[],\"locked\":true}".utf8))
  assert(!legacy.retryIfDue(now:5000));assert(legacy.retryAt==8600)
  assert(!legacy.retryIfDue(now:8599));assert(legacy.retryIfDue(now:8600))
  p.unlock();p.observe(token:"b",now:1001);assert(!p.locked,"Re-reading the held popup after manual resume must not recount it")
  p.observe(token:"d",now:1002);assert(!p.locked);p.observe(token:"e",now:1063);assert(!p.locked)
  p.observe(token:"f",now:1064);assert(p.locked)
  print("PASS: rolling 60-second/two-event lock, duplicate event/popup observations, durable one-hour lock, legacy migration, timed retry and manual unlock")
 }
}
