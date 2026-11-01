import Foundation

struct HuntRestartSchedule {
    static let interval:TimeInterval=2*60*60
    private var configuredInterval=Self.interval
    private(set) var deadline:Date?
    mutating func start(now:Date,savedDeadline:Date?=nil,interval:TimeInterval=HuntRestartSchedule.interval){configuredInterval=interval;deadline=savedDeadline ?? now.addingTimeInterval(interval)}
    func remaining(now:Date)->Int {max(0,Int(ceil((deadline ?? now).timeIntervalSince(now))))}
    mutating func restarted(now:Date){deadline=now.addingTimeInterval(configuredInterval)}
    mutating func failed(now:Date){deadline=now.addingTimeInterval(60)}
}
