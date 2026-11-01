import Foundation

struct HuntRestartSchedule {
    static let interval:TimeInterval=2*60*60
    private(set) var deadline:Date?
    mutating func start(now:Date,savedDeadline:Date?=nil){deadline=savedDeadline ?? now.addingTimeInterval(Self.interval)}
    func remaining(now:Date)->Int {max(0,Int(ceil((deadline ?? now).timeIntervalSince(now))))}
    mutating func restarted(now:Date){deadline=now.addingTimeInterval(Self.interval)}
    mutating func failed(now:Date){deadline=now.addingTimeInterval(60)}
}
