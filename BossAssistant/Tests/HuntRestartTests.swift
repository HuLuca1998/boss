import Foundation
@main struct HuntRestartTests {
    static func main(){
        let now=Date(timeIntervalSince1970:10000)
        var schedule=HuntRestartSchedule()
        schedule.start(now:now)
        assert(schedule.remaining(now:now)==7200)
        assert(schedule.remaining(now:now.addingTimeInterval(7199.1))==1)
        assert(schedule.remaining(now:now.addingTimeInterval(7200))==0)
        assert(schedule.remaining(now:now.addingTimeInterval(9000))==0)
        let saved=schedule.deadline
        schedule.start(now:now.addingTimeInterval(3600),savedDeadline:saved)
        assert(schedule.remaining(now:now.addingTimeInterval(3600))==3600)
        schedule.failed(now:now);assert(schedule.remaining(now:now)==60)
        schedule.restarted(now:now);assert(schedule.remaining(now:now)==7200)
        schedule.start(now:now.addingTimeInterval(9000),savedDeadline:saved)
        assert(schedule.remaining(now:now.addingTimeInterval(9000))==0)
        print("PASS: two-hour deadline, countdown rounding, persisted deadline, retry and reset")
    }
}
