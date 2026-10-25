import SwiftUI

struct SettingsView:View {
    @ObservedObject var model:AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var page=0
    private var otherPopups:[PopupRecord] {
        var seen=Set<Int>()
        return model.popupHistory.filter{![1023,1017,1004,1137,1183,1103].contains($0.viewId) && seen.insert($0.viewId).inserted}
    }
    var body:some View {
        VStack(alignment:.leading,spacing:20){
            HStack{Text("设置").font(.title2.bold());Spacer();Button("完成"){dismiss()}.keyboardShortcut(.cancelAction)}
            HStack(spacing:12){Button("辅助功能"){page=0}.tint(page==0 ? .teal : .gray);Button("弹窗处理"){page=1}.tint(page==1 ? .teal : .gray);Spacer()}.buttonStyle(.bordered).controlSize(.large)
            ScrollView {
                VStack(alignment:.leading,spacing:20){
                    if page==0 {
                        Text("辅助功能").font(.headline)
                        Toggle("键盘控制：方向键 / WASD / ESC 返回",isOn:Binding(get:{model.keyboardEnabled},set:{enabled in Task{await model.setKeyboard(enabled)}})).disabled(!model.connected || model.snapshot == nil || model.keyboardWorking || model.working)
                        Text("只在游戏前台生效；输入文字时暂停。ESC 每按一次返回一层，支持已适配的页面和普通关闭弹窗。").font(.caption).foregroundStyle(.secondary)
                        Text(model.keyboardInputAllowed ? "输入监控已授权" : "输入监控未授权，键盘控制暂不可用").font(.caption).foregroundStyle(model.keyboardInputAllowed ? Color.secondary : Color.orange)
                        if !model.keyboardInputAllowed {Button("授权键盘控制"){model.requestKeyboardAccess()}}
                        Divider()
                        Toggle("区域 BOSS：有钥匙且已刷新时自动攻略",isOn:$model.areaBossEnabled)
                        Toggle("区域 BOSS：使用钥匙开启击败后的宝箱",isOn:$model.areaBossBoxEnabled)
                        Text("只使用对应BOSS钥匙，不购买钥匙，也不使用替代道具；数量变化写入事件记录。").font(.caption).foregroundStyle(.secondary)
                        Divider()
                        Toggle("世界 / 联盟聊天红包自动领取",isOn:$model.redPacketEnabled)
                        Text("发现、领取结果和经服务器核验的金额，可在事件记录中查看。").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("弹窗处理").font(.headline)
                        Toggle("连接服务器失败：自动确认重连",isOn:$model.autoReconnect)
                        Toggle("异地登录：自动确认",isOn:$model.replacedConfirmEnabled)
                        Text("60秒内第二次异地登录，暂停自动攻击与自动重连，需手动继续；关闭勾选不解除保护。").font(.caption).foregroundStyle(.secondary)
                        if model.recoveryLocked {Button("手动恢复重连"){model.unlockRecovery()}}
                        Divider()
                        Toggle("挂机收益：自动领取",isOn:$model.idleRewardEnabled)
                        Toggle("点击空白处关闭：自动处理（含恭喜获得）",isOn:$model.blankCloseEnabled)
                        Toggle("收益与空白关闭仅在自动攻略期间处理",isOn:$model.popupOnlyWhileHunting)
                        Text("收益通过游戏原有领取按钮处理；标有点击空白处关闭、且使用普通关闭逻辑的弹窗保留约2秒后关闭。每个弹窗只尝试一次，处理和关闭结果写入弹窗历史。").font(.caption).foregroundStyle(.secondary)
                        if !model.popupHandlingAvailable {Text("弹窗处理等待新版游戏脚本连接。").font(.caption).foregroundStyle(.orange)}
                        Divider()
                        Text("其他已收录弹窗").font(.headline)
                        ForEach(otherPopups,id:\.viewId){record in
                            VStack(alignment:.leading,spacing:4){Toggle(record.displayTitle,isOn:.constant(record.supportsBlankClose && model.blankCloseEnabled)).disabled(true);Text("\(record.viewName) · \(record.viewId) · \(record.supportsBlankClose ? "由空白关闭统一开关管理" : [1005,1125,1279].contains(record.viewId) ? "游戏自行展示或关闭，无需点击" : "已记录，尚未适配自动操作")").font(.caption).foregroundStyle(.secondary)}
                        }
                        Text("新弹窗会继续记录；只有已确认操作方式的类型才能启用自动处理。").font(.caption).foregroundStyle(.secondary)
                    }
                }.toggleStyle(.checkbox).padding(4).frame(maxWidth:.infinity,alignment:.leading)
            }
            Text("设置自动保存 · 弹窗详细数据在「事件记录 → 弹窗历史」查看").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width:700,height:620).preferredColorScheme(.dark)
    }
}
