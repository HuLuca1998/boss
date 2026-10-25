import SwiftUI

struct AboutUpdateView:View {
    @ObservedObject var updater=UpdateController.shared
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            Text("首领助手").font(.title2.bold())
            Text("当前版本 \(updater.currentVersion) · Apple Silicon · macOS 14+").foregroundStyle(.secondary)
            HStack{
                Button(updater.checking ? "正在检查…" : "检查更新"){Task{await updater.check()}}.disabled(updater.checking || updater.installing)
                if updater.available {Button("一键更新到 \(updater.latest!.version)"){Task{await updater.install()}}.buttonStyle(.borderedProminent).disabled(updater.installing || !updater.canInstall)}
                Link("发布页面",destination:URL(string:"https://github.com/\(UpdatePolicy.repository)/releases")!)
            }
            Text(updater.phase).font(.callout)
            if let message=updater.lastInstallMessage{Text(message).font(.caption).foregroundStyle(.secondary)}
            if updater.installing {
                ProgressView(value:updater.progress)
                if updater.downloaded>0 {Text("\(ByteCountFormatter.string(fromByteCount:updater.downloaded,countStyle:.file)) / \(ByteCountFormatter.string(fromByteCount:updater.total,countStyle:.file))").font(.caption).foregroundStyle(.secondary)}
                if updater.phase.hasPrefix("正在下载"){Button("取消下载"){updater.cancel()}}
            }
            if let error=updater.error{Text(error).foregroundStyle(.orange).textSelection(.enabled)}
            if let checked=updater.checkedAt{Text("上次检查：\(checked.formatted(date:.abbreviated,time:.standard))").font(.caption).foregroundStyle(.secondary)}
            Text("更新会重开助手，保留设置、事件记录和攻略任务，不自动重启游戏。游戏脚本如有变化，请使用主界面的重新注入功能。").font(.caption).foregroundStyle(.secondary)
            if !updater.canInstall{Text("请先将助手放到可写入的应用程序目录，再使用一键更新。").font(.caption).foregroundStyle(.orange)}
            Divider()
            Text("更新说明").font(.headline)
            ForEach(Array((updater.available ? updater.pending : Array(updater.releases.prefix(1))).prefix(5))){release in
                VStack(alignment:.leading,spacing:6){Text(release.tag_name).font(.headline);Text(release.body ?? "暂无说明").font(.callout).textSelection(.enabled)}
            }
        }.frame(maxWidth:.infinity,alignment:.leading).task{if updater.checkedAt==nil{await updater.check()}}
    }
}
