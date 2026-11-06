import Foundation

enum GameInstallation {
    static let bundleID = "com.yzlm.game"
    static func info(at app:URL)throws->[String:Any] {
        let fm=FileManager.default
        let direct=[app.appendingPathComponent("Info.plist"),app.appendingPathComponent("Contents/Info.plist")]
        let wrapper=app.appendingPathComponent("Wrapper")
        let wrapped=(try? fm.contentsOfDirectory(at:wrapper,includingPropertiesForKeys:nil)) ?? []
        let candidates=direct+wrapped.filter{$0.pathExtension=="app"}.map{$0.appendingPathComponent("Info.plist")}
        for url in candidates where fm.fileExists(atPath:url.path) {
            let data=try Data(contentsOf:url)
            if let info=try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any],info["CFBundleIdentifier"] as? String==bundleID {return info}
        }
        throw GameCacheFailure(message:"无法读取勇者联盟安装信息：\(app.path)。请先正常打开游戏后重试；未进行注入")
    }
    static func validate(at app:URL)throws {
        let metadata=try info(at:app)
        guard let version=metadata["CFBundleShortVersionString"] as? String else{throw GameCacheFailure(message:"游戏安装信息缺少版本号：\(app.path)；未进行注入")}
        guard version=="1.16.3" else{throw GameCacheFailure(message:"游戏安装版本 \(version) 尚未适配（当前支持 1.16.3）：\(app.path)；未进行注入")}
    }
}
