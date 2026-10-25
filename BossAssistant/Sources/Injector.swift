import Foundation
import AppKit
import CryptoKit

final class Injector {
    let support:URL
    let target:URL
    private var grantedURL:URL?
    let originalHash="4085b2c2f223e255fe5b8fa62379d02d2843671ce6def362694304a099af37a0"
    init(support:URL){self.support=support;target=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/com.yzlm.game/Data/Library/Caches/appCache/objects/9b/ca89d68d4700faff8d14ff2748cb746b6e4848")
        if let data=try? Data(contentsOf:support.appendingPathComponent("CacheAccess.bookmark")) {
            var stale=false
            if let url=try? URL(resolvingBookmarkData:data,options:.withSecurityScope,relativeTo:nil,bookmarkDataIsStale:&stale),url.startAccessingSecurityScopedResource(){grantedURL=url}
        }
    }
    @MainActor func authorizeCache()async throws {
        if (try? Data(contentsOf:target,options:.mappedIfSafe)) != nil {return}
        let bookmark=support.appendingPathComponent("CacheAccess.bookmark")
        if let saved=try? Data(contentsOf:bookmark) {
            var stale=false
            if let url=try? URL(resolvingBookmarkData:saved,options:.withSecurityScope,relativeTo:nil,bookmarkDataIsStale:&stale),url.startAccessingSecurityScopedResource(){grantedURL=url;if (try? Data(contentsOf:target,options:.mappedIfSafe)) != nil{return}}
        }
        let folder=target.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let panel=NSOpenPanel();panel.title="授权游戏缓存";panel.message="请选择勇者联盟的 appCache 文件夹，用于备份、注入与还原脚本。仅访问这个缓存目录。";panel.prompt="授权此文件夹";panel.canChooseDirectories=true;panel.canChooseFiles=false;panel.allowsMultipleSelection=false;panel.canCreateDirectories=false;panel.directoryURL=folder
        let response=await withCheckedContinuation{continuation in panel.begin{continuation.resume(returning:$0)}}
        guard response == .OK,let url=panel.url else{throw BridgeFailure(message:"未授权游戏缓存，未执行注入")}
        guard url.resolvingSymlinksInPath().standardizedFileURL==folder.resolvingSymlinksInPath().standardizedFileURL else{throw BridgeFailure(message:"请选择游戏的 appCache 文件夹，而不是其他目录")}
        _=url.startAccessingSecurityScopedResource();grantedURL=url
        let data=try url.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil);try data.write(to:bookmark,options:.atomic)
        guard (try? Data(contentsOf:target,options:.mappedIfSafe)) != nil else{throw BridgeFailure(message:"macOS仍未允许访问游戏缓存，请在系统设置中检查首领助手的数据访问权限")}
    }
    var installed:Bool {guard let d=try? Data(contentsOf:target),let s=String(data:d,encoding:.utf8) else{return false};return s.contains("yzlm-native-boss-v2")}
    private func resource(_ name:String,_ ext:String)throws->URL {guard let u=Bundle.main.url(forResource:name,withExtension:ext) else{throw BridgeFailure(message:"应用资源缺失，请重新安装首领助手")};return u}
    private func hash(_ d:Data)->String{SHA256.hash(data:d).map{String(format:"%02x",$0)}.joined()}
    private var compiled:[URL]{let dir=target.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("codecache");return ["Main-40920.js.arm64.cache","Main-40920.js.arm64.meta"].map{dir.appendingPathComponent($0)}}
    @MainActor private func quitGame()async throws {
        let apps=NSRunningApplication.runningApplications(withBundleIdentifier:"com.yzlm.game")
        for app in apps {guard app.terminate() else{throw BridgeFailure(message:"游戏未能正常退出，请手动退出后再试")}}
        for _ in 0..<50 {
            if NSRunningApplication.runningApplications(withBundleIdentifier:"com.yzlm.game").isEmpty{return}
            try await Task.sleep(nanoseconds:200_000_000)
        }
        throw BridgeFailure(message:"游戏仍在退出中，未改写缓存，请稍后重试")
    }
    @MainActor func openGame()async throws {
        let cfg=NSWorkspace.OpenConfiguration();cfg.activates=false
        _ = try await NSWorkspace.shared.openApplication(at:URL(fileURLWithPath:"/Applications/game.app"),configuration:cfg)
    }
    @MainActor func inject(port:UInt16,token:String)async throws {
        let infoURL=URL(fileURLWithPath:"/Applications/game.app/Wrapper/game.app/Info.plist")
        if let info=NSDictionary(contentsOf:infoURL),let version=info["CFBundleShortVersionString"] as? String,version != "1.16.3" {throw BridgeFailure(message:"游戏已更新至\(version)，当前脚本仅适配1.16.3，未进行注入")}
        try await authorizeCache()
        let fm=FileManager.default
        guard fm.fileExists(atPath:target.path) else{throw BridgeFailure(message:"没有找到适配的游戏缓存。请先正常进入游戏一次；当前支持1.16.3版本")}
        let original=try Data(contentsOf:resource("OriginalCache","bin"));guard hash(original)==originalHash else{throw BridgeFailure(message:"原始脚本校验失败，未进行注入")}
        let before=try Data(contentsOf:target)
        let oldText=String(data:before,encoding:.utf8) ?? ""
        guard hash(before)==originalHash || oldText.contains("yzlm-boss-bridge-v1") || oldText.contains("yzlm-native-boss-v2") else{throw BridgeFailure(message:"缓存版本发生变化，需重新适配；未修改游戏")}
        let key:[UInt8]=[0x8f,0xbf,0x3b,0x77,0x8f,0xc9,0x86,0xd8,0x12,0xa8,0x4c,0x9e,0xbd,0x4a,0xba,0x2d]
        let raw=Array(original);let decoded=Data(raw[12..<(raw.count-20)].enumerated().map{$0.element ^ key[$0.offset%16]})
        guard let source=String(data:decoded,encoding:.utf8) else{throw BridgeFailure(message:"原始脚本无法解码")}
        let needle=",__toCommonJS(Main_exports)})();"
        guard source.components(separatedBy:needle).count==2 else{throw BridgeFailure(message:"脚本入口不匹配，未进行注入")}
        var runtime=try String(contentsOf:resource("Runtime","js"),encoding:.utf8)
        runtime=runtime.replacingOccurrences(of:"__CODEX_WS_URL__",with:"ws://127.0.0.1:\(port)/game").replacingOccurrences(of:"__CODEX_TOKEN__",with:token)
        let patched=source.replacingOccurrences(of:needle,with:","+runtime+needle)
        let backup=support.appendingPathComponent("Backups");try fm.createDirectory(at:backup,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let originalBackup=backup.appendingPathComponent("OriginalCache.bin")
        if !fm.fileExists(atPath:originalBackup.path){try original.write(to:originalBackup,options:.atomic)}
        try await quitGame()
        for file in compiled where fm.fileExists(atPath:file.path){
            let saved=backup.appendingPathComponent(file.lastPathComponent)
            if !fm.fileExists(atPath:saved.path){try fm.copyItem(at:file,to:saved)}
        }
        do {
            try Data(patched.utf8).write(to:target,options:.atomic);try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:target.path)
            for file in compiled where fm.fileExists(atPath:file.path){try fm.removeItem(at:file)}
            try await openGame()
        } catch {
            try? before.write(to:target,options:.atomic)
            try? await openGame()
            throw error
        }
    }
    @MainActor func restore()async throws {
        try await authorizeCache()
        let original=try Data(contentsOf:resource("OriginalCache","bin"));guard hash(original)==originalHash else{throw BridgeFailure(message:"备份校验失败")}
        guard installed else{throw BridgeFailure(message:"当前缓存未检测到本应用注入，未执行还原")}
        try await quitGame();try original.write(to:target,options:.atomic)
        for file in compiled where FileManager.default.fileExists(atPath:file.path){try FileManager.default.removeItem(at:file)}
        try await openGame()
    }
}
