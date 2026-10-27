import Foundation
@main struct BossSelectionTests {
    static func main()throws {
        var policy=BossSelection()
        let ids:Set<String>=["10021-501","10021-502","10022-501"]
        assert(policy.checked("10021-501",area:7))
        policy.set("10021-501",area:7,selected:false,knownIDs:ids)
        assert(!policy.checked("10021-501",area:7))
        assert(policy.checked("10022-501",area:7),"Same name/point in a different instance remains independent")
        assert(policy.checked("10021-501",area:8),"Area preferences are independent")
        policy.desiredParts=[1,4]
        assert(policy.permits("10021-502",area:7,parts:[3,4]))
        assert(!policy.permits("10021-502",area:7,parts:[5,6]))
        assert(!policy.permits("10021-501",area:7,parts:[1,2]),"Part match cannot override an unchecked boss")
        assert(!policy.matches(parts:nil),"Unknown drops must not pass an active part filter")
        policy.setVisible(["10021-502"],area:7,selected:false,knownIDs:ids)
        assert(policy.checked("10022-501",area:7),"Filtered bulk actions preserve hidden choices")
        policy.setVisible(ids,area:7,selected:false,knownIDs:ids)
        assert(ids.allSatisfy{!policy.checked($0,area:7)})
        assert(!policy.checked("new-boss",area:7),"Explicit selection does not silently include new bosses")
        let saved=try JSONEncoder().encode(policy),loaded=try JSONDecoder().decode(BossSelection.self,from:saved)
        assert(loaded.desiredParts==[1,4] && !loaded.checked("10021-502",area:7))
        policy.desiredParts=[];assert(policy.matches(parts:nil))
        if CommandLine.arguments.count>1 {
            let folder=URL(fileURLWithPath:CommandLine.arguments[1])
            let drops=try JSONDecoder().decode([String:BossDropInfo].self,from:Data(contentsOf:folder.appendingPathComponent("BossDrops.json")))
            assert(drops["10021-501"]?.parts==[1,2]);assert(drops["10021-501"]?.minLevel==60);assert(drops["10021-501"]?.maxLevel==66)
            assert(drops.count==303)
        }
        print("PASS: per-area/EID selection, explicit none, part union plus manual intersection, unknown-drop exclusion, visible-only bulk actions, new-boss safety, persistence and recovered drop preview")
    }
}
