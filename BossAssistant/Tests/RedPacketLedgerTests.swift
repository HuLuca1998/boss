import Foundation
@main struct RedPacketLedgerTests {
 static func packet(_ key:String,_ state:Int?,_ amount:Double?,attempt:Bool=true,currency:String="水晶")throws->PacketRecord {
  var value:[String:Any]=["key":key,"id":"90071992547409931234","channel":1000,"type":1,"seenAt":1000.0,"expires":9000.0,"status":"pending","attempted":attempt,"name":"聊天红包","currencyId":3,"currencyName":currency]
  if let state {value["serverStatus"]=state};if let amount {value["myAmount"]=amount}
  return try JSONDecoder().decode(PacketRecord.self,from:JSONSerialization.data(withJSONObject:value))
 }
 static func main()throws {
  var ledger=RedPacketLedger()
  _=ledger.merge([try packet("a",0,nil)])
  assert(ledger.confirmedCount==0 && ledger.totals.isEmpty)
  _=ledger.merge([try packet("a",1,12)])
  for _ in 0..<100 {_=ledger.merge([try packet("a",1,12)])}
  assert(ledger.confirmedCount==1 && ledger.autoCount==1 && ledger.totals["水晶"]==12)
  _=ledger.merge([try packet("a",nil,nil)]);assert(ledger.totals["水晶"]==12,"Cache eviction must not erase a verified reward")
  _=ledger.merge([try packet("b",1,5,attempt:false,currency:"协作币")]);assert(ledger.confirmedCount==2 && ledger.autoCount==1 && ledger.totals.count==2)
  ledger=try JSONDecoder().decode(RedPacketLedger.self,from:JSONEncoder().encode(ledger))
  assert(ledger.records.count==2 && ledger.totals["协作币"]==5)
  assert(ledger.readable().contains("12 水晶") && ledger.readable().contains("此前或手动"))
  print("PASS: durable per-packet ledger, pending excluded from totals, no duplicate awards, cache eviction retention, automatic/manual distinction and currency-separated amounts")
 }
}
