import Foundation

@main struct GameCachePolicyTests {
    static func reject(line:Int = #line,_ body:()throws->Void){do{try body();fatalError("Expected rejection at line \(line)")}catch{}}
    static func tree(_ entries:[(String,String,String)])->Data {
        // DCC pads the entire object to four bytes and appends eight metadata bytes per entry.
        var body=Data()
        // Header is padded independently; all offsets then remain four-byte aligned.
        for (mode,name,id) in entries {
            body.append(Data("\(mode) \(name)\0".utf8))
            var i=id.startIndex
            while i<id.endIndex {let j=id.index(i,offsetBy:2);body.append(UInt8(id[i..<j],radix:16)!);i=j}
            while body.count%4 != 0{body.append(0)}
            body.append(Data(repeating:0,count:8))
        }
        var data=Data("tree \(body.count)\0".utf8)
        while data.count%4 != 0{data.append(0)}
        data.append(body);return data
    }
    static func main()throws {
        let fm=FileManager.default
        let base=fm.temporaryDirectory.appendingPathComponent("game-cache-tests-"+UUID().uuidString).resolvingSymlinksInPath()
        try fm.createDirectory(at:base,withIntermediateDirectories:true);defer{try? fm.removeItem(at:base)}
        let root=String(repeating:"a",count:40),js=String(repeating:"b",count:40)
        func put(_ id:String,_ data:Data)throws {
            let url=try GameCachePolicy.objectURL(id,base:base)
            try fm.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try data.write(to:url)
        }
        try JSONSerialization.data(withJSONObject:["root":root]).write(to:base.appendingPathComponent("head.json"))
        try put(root,tree([("40000","js",js)]))
        for profile in GameCacheProfile.supported {
            try put(js,tree([("100644",profile.script,profile.objectID)]))
            let selection=try GameCachePolicy.resolve(base:base)
            assert(selection.profile==profile)
            let compiled=try GameCachePolicy.compiled(selection:selection,base:base)
            assert(compiled[0].lastPathComponent==profile.script+".arm64.cache")
            let resources=URL(fileURLWithPath:CommandLine.arguments[1])
            let original=try Data(contentsOf:resources.appendingPathComponent(profile.resource+".bin"))
            let source=try GameCachePolicy.source(original:original,profile:profile)
            assert(!GameCachePolicy.isInjected(original,source:source))
            let patched=source.replacingOccurrences(of:GameCachePolicy.needle,with:",(function(){/* yzlm-native-boss-v2 */})();"+GameCachePolicy.needle)
            assert(GameCachePolicy.isInjected(Data(patched.utf8),source:source))
            assert(!GameCachePolicy.isInjected(Data(("tamper"+patched).utf8),source:source))
            assert(!GameCachePolicy.isInjected(Data("yzlm-native-boss-v2".utf8),source:source))
            reject{_ = try GameCachePolicy.source(original:Data(original.dropLast()),profile:profile)}
        }
        let p=GameCacheProfile.supported[1]
        try put(js,tree([("100644","Main-unknown.js",p.objectID)]));reject{_ = try GameCachePolicy.resolve(base:base)}
        try put(js,tree([("100644",p.script,String(repeating:"c",count:40))]));reject{_ = try GameCachePolicy.resolve(base:base)}
        try put(js,tree(GameCacheProfile.supported.map{("100644",$0.script,$0.objectID)}));reject{_ = try GameCachePolicy.resolve(base:base)}
        try put(js,tree([("100644",p.script,p.objectID),("100644",p.script,p.objectID)]));reject{_ = try GameCachePolicy.resolve(base:base)}
        let valid=tree([("40000","js",js)])
        for count in 0..<valid.count {reject{_ = try GameCachePolicy.entries(Data(valid.prefix(count)))}}
        reject{_ = try GameCachePolicy.entries(tree([("40000","..",js)]))}
        reject{_ = try GameCachePolicy.objectURL("../../escape",base:base)}
        try put(js,tree([("100644",p.script,p.objectID)]))
        let path=try GameCachePolicy.objectURL(p.objectID,base:base)
        try fm.createDirectory(at:path.deletingLastPathComponent(),withIntermediateDirectories:true)
        try fm.createSymbolicLink(at:path,withDestinationURL:URL(fileURLWithPath:"/tmp/outside-cache"))
        reject{_ = try GameCachePolicy.resolve(base:base)}
        if CommandLine.arguments.count>2 {
            let current=try GameCachePolicy.resolve(base:URL(fileURLWithPath:CommandLine.arguments[2]))
            print("Read-only live resolution: \(current.profile.script), root \(current.root)")
        }
        print("PASS: both supported hot updates, exact current tree selection, original hashes, patched identity, version mismatch, ambiguity, malformed trees, traversal and symlink rejection")
    }
}
