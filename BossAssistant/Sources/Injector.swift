import Foundation
import AppKit

final class Injector {
    let support:URL
    let cache:URL
    private var grantedURL:URL?
    init(support:URL){
        self.support=support
        cache=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/com.yzlm.game/Data/Library/Caches/appCache")
        if let data=try? Data(contentsOf:support.appendingPathComponent("CacheAccess.bookmark")) {
            var stale=false
            if let url=try? URL(resolvingBookmarkData:data,options:.withSecurityScope,relativeTo:nil,bookmarkDataIsStale:&stale),url.startAccessingSecurityScopedResource(){grantedURL=url}
        }
    }
    @MainActor private func authorizeCache()async throws {
        if (try? Data(contentsOf:cache.appendingPathComponent("head.json"))) != nil{return}
        let panel=NSOpenPanel();panel.title="授权游戏缓存";panel.message="请选择勇者联盟的 appCache 文件夹，用于备份、注入与还原当前版本脚本。";panel.prompt="授权此文件夹";panel.canChooseDirectories=true;panel.canChooseFiles=false;panel.allowsMultipleSelection=false;panel.canCreateDirectories=false;panel.directoryURL=cache
        let response=await withCheckedContinuation{continuation in panel.begin{continuation.resume(returning:$0)}}
        guard response == .OK,let url=panel.url else{throw BridgeFailure(message:"未授权游戏缓存，未执行注入")}
        guard url.resolvingSymlinksInPath().standardizedFileURL==cache.resolvingSymlinksInPath().standardizedFileURL else{throw BridgeFailure(message:"请选择游戏的 appCache 文件夹")}
        _=url.startAccessingSecurityScopedResource();grantedURL=url
        let data=try url.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil)
        try data.write(to:support.appendingPathComponent("CacheAccess.bookmark"),options:.atomic)
    }
    private func original(_ selection:GameCacheSelection)throws->Data {
        guard let url=Bundle.main.url(forResource:selection.profile.resource,withExtension:"bin") else{throw BridgeFailure(message:"当前游戏版本的原始脚本缺失，请重新安装首领助手")}
        let data=try Data(contentsOf:url)
        guard GameCachePolicy.hash(data)==selection.profile.originalHash else{throw BridgeFailure(message:"原始脚本校验失败，未修改游戏")}
        return data
    }
    var installed:Bool {
        guard let selection=try? GameCachePolicy.resolve(base:cache),let data=try? original(selection),
              let source=try? GameCachePolicy.source(original:data,profile:selection.profile),let current=try? Data(contentsOf:selection.target) else{return false}
        return GameCachePolicy.isInjected(current,source:source)
    }
    var cacheDescription:String {
        do{return "当前游戏脚本：\(try GameCachePolicy.resolve(base:cache).profile.script) · 已适配"}
        catch{return error.localizedDescription}
    }
    @MainActor private func quitGame()async throws {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier:"com.yzlm.game") {
            guard app.terminate() else{throw BridgeFailure(message:"游戏未能正常退出，请手动退出后再试")}
        }
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
    @MainActor private func replace(selection:GameCacheSelection,before:Data,after:Data,original:Data)async throws {
        let fm=FileManager.default
        let folder=support.appendingPathComponent("Backups/\(selection.profile.originalHash)")
        try fm.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let backup=folder.appendingPathComponent("OriginalCache.bin")
        if !fm.fileExists(atPath:backup.path){try original.write(to:backup,options:.atomic)}
        guard try GameCachePolicy.hash(Data(contentsOf:backup))==selection.profile.originalHash else{throw BridgeFailure(message:"当前版本备份校验失败，未修改游戏")}
        try await quitGame()
        var changed=false,saved=[(URL,Data)]()
        do {
            // Refuse a hot update that completed during normal shutdown.
            guard try GameCachePolicy.resolve(base:cache)==selection,
                  try Data(contentsOf:selection.target)==before else{throw BridgeFailure(message:"游戏缓存已变化，请重新操作；未改写缓存")}
            let compiled=try GameCachePolicy.compiled(selection:selection,base:cache)
            for file in compiled where fm.fileExists(atPath:file.path){saved.append((file,try Data(contentsOf:file)))}
            for (file,data) in saved {
                let destination=folder.appendingPathComponent(file.lastPathComponent)
                if !fm.fileExists(atPath:destination.path){try data.write(to:destination,options:.atomic)}
            }
            try after.write(to:selection.target,options:.atomic);changed=true
            try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:selection.target.path)
            guard try Data(contentsOf:selection.target)==after else{throw BridgeFailure(message:"脚本写入校验失败")}
            for file in compiled where fm.fileExists(atPath:file.path){try fm.removeItem(at:file)}
            try await openGame()
        } catch {
            if changed {
                do {
                    try before.write(to:selection.target,options:.atomic)
                    for (file,data) in saved{try data.write(to:file,options:.atomic)}
                } catch {throw BridgeFailure(message:"脚本操作失败且回滚未完成，请保留 Backups 备份并手动检查：\(error.localizedDescription)")}
            }
            try? await openGame()
            throw error
        }
    }
    @MainActor func inject(port:UInt16,token:String)async throws {
        let infoURL=URL(fileURLWithPath:"/Applications/game.app/Wrapper/game.app/Info.plist")
        guard let info=NSDictionary(contentsOf:infoURL),let version=info["CFBundleShortVersionString"] as? String,version=="1.16.3" else{throw BridgeFailure(message:"当前游戏安装版本尚未适配，未进行注入")}
        try await authorizeCache()
        let selection=try GameCachePolicy.resolve(base:cache),original=try original(selection)
        let source=try GameCachePolicy.source(original:original,profile:selection.profile)
        let before=try Data(contentsOf:selection.target)
        guard GameCachePolicy.hash(before)==selection.profile.originalHash || GameCachePolicy.isInjected(before,source:source) else{throw BridgeFailure(message:"当前主脚本与已适配版本不符，未修改游戏")}
        guard let url=Bundle.main.url(forResource:"Runtime",withExtension:"js") else{throw BridgeFailure(message:"应用脚本资源缺失")}
        var runtime=try String(contentsOf:url,encoding:.utf8)
        runtime=runtime.replacingOccurrences(of:"__CODEX_WS_URL__",with:"ws://127.0.0.1:\(port)/game").replacingOccurrences(of:"__CODEX_TOKEN__",with:token).replacingOccurrences(of:"__CODEX_SCRIPT_ID__",with:selection.profile.script)
        let patched=source.replacingOccurrences(of:GameCachePolicy.needle,with:","+runtime+GameCachePolicy.needle)
        try await replace(selection:selection,before:before,after:Data(patched.utf8),original:original)
    }
    @MainActor func restore()async throws {
        try await authorizeCache()
        let selection=try GameCachePolicy.resolve(base:cache),original=try original(selection)
        let source=try GameCachePolicy.source(original:original,profile:selection.profile),before=try Data(contentsOf:selection.target)
        guard GameCachePolicy.isInjected(before,source:source) else{throw BridgeFailure(message:"当前游戏版本未检测到本助手注入，未执行还原")}
        try await replace(selection:selection,before:before,after:original,original:original)
    }
}
