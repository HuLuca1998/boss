import SwiftUI

struct EventHistoryView:View {
    @ObservedObject var model:AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var search=""
    @State private var category="全部"
    @State private var selected:UUID?
    @State private var selectedPacket:String?
    @State private var selectedPopup:String?
    @State private var page=0
    private var events:[EventRecord] {model.eventHistory.filter{(category=="全部" || $0.category==category) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.data.values.contains{$0.localizedCaseInsensitiveContains(search)})}}
    private var packets:[PacketRecord] {model.packetLedger.records.reversed().filter{search.isEmpty || $0.id.contains(search) || ($0.name ?? "").localizedCaseInsensitiveContains(search) || $0.channelName.contains(search) || $0.result.contains(search)}}
    var body:some View {
        VStack(alignment:.leading,spacing:14){
            HStack{Text("事件记录").font(.title2.bold());Spacer();Button("打开记录文件夹"){model.showLogs()};Button("完成"){dismiss()}.keyboardShortcut(.cancelAction)}
            TextField("搜索事件、红包ID或处理结果",text:$search).textFieldStyle(.roundedBorder).accessibilityLabel("搜索事件记录")
            VStack(alignment:.leading,spacing:12) {
                HStack(spacing:10){
                    ForEach(Array(["全部事件","红包明细","弹窗历史"].enumerated()),id:\.offset){index,title in
                        Button{page=index}label:{Text(title).fontWeight(page==index ? .semibold : .regular).frame(minWidth:100).padding(.vertical,7)}.buttonStyle(.bordered).tint(page==index ? .teal : .gray)
                    }
                    Spacer()
                }.fixedSize(horizontal:false,vertical:true)
                if page==0 {
                VStack(alignment:.leading){
                    Picker("类型",selection:$category){ForEach(["全部","连接","账号保护","红包","弹窗","攻略","操作"],id:\.self){Text($0)}}.pickerStyle(.segmented)
                    HSplitView {
                        List(events,selection:$selected){event in
                            VStack(alignment:.leading,spacing:5){HStack{Text(event.category).font(.caption).foregroundStyle(.secondary);Spacer();Text(event.time.formatted(date:.abbreviated,time:.standard)).font(.caption).foregroundStyle(.secondary)};Text(event.title).lineLimit(2)}.padding(.vertical,4).tag(event.id)
                        }.frame(minWidth:330)
                        if let event=model.eventHistory.first(where:{$0.id==selected}) {
                            ScrollView{VStack(alignment:.leading,spacing:16){Text(event.title).font(.headline);Text(event.time.formatted(date:.complete,time:.standard)).foregroundStyle(.secondary);detailRows(event.data.isEmpty ? ["事件类型":event.category,"说明":event.title] : event.data)}.padding().frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled)}.frame(minWidth:330)
                        } else {emptyDetail("选择一条事件查看详细数据")}
                    }
                    Text("显示最近最多3000条事件 · 完整记录保存在本机 · 新事件自动更新").font(.caption).foregroundStyle(.secondary)
                }.padding(.top,4)
                } else if page==1 {
                VStack(alignment:.leading,spacing:12){
                    Text("发现 \(model.packetLedger.records.count) 个 · 自动领取已核验 \(model.packetLedger.autoCount) 个").font(.headline)
                    Text(model.packetLedger.totals.isEmpty ? "暂无经服务器核验的领取金额" : "本角色已核验金额（含此前/手动）："+model.packetLedger.totals.sorted{$0.key<$1.key}.map{"\($0.key) \(String(format:"%g",$0.value))"}.joined(separator:"、")).font(.caption).foregroundStyle(.secondary)
                    HSplitView {
                        List(packets,id:\.key,selection:$selectedPacket){packet in
                            VStack(alignment:.leading,spacing:5){Text("\(packet.channelName) · \(packet.name ?? "聊天红包")");Text(packet.result).font(.caption).foregroundStyle(packet.confirmed ? Color.green : .secondary)}.padding(.vertical,4).tag(packet.key)
                        }.frame(minWidth:300)
                        if let packet=model.packetLedger.records.first(where:{$0.key==selectedPacket}) {
                            ScrollView{detailRows(["发现到请求":packet.requestDelayMs.map{"\(Int($0)) 毫秒"} ?? "尚未请求","红包ID":packet.id,"频道":packet.channelName,"类型":packet.name ?? "聊天红包","发现时间":Date(timeIntervalSince1970:packet.seenAt/1000).formatted(date:.abbreviated,time:.standard),"处理结果":packet.result,"本角色实际领取":packet.confirmed ? "\(String(format:"%g",packet.myAmount ?? 0)) \(packet.moneyName)" : "尚未核验","红包总额":packet.totalMoney.map{"\(String(format:"%g",$0)) \(packet.moneyName)"} ?? "未知","总份数":packet.totalNum.map{String($0)} ?? "未知","剩余份数":packet.remainingNum.map{String($0)} ?? "未知"]).padding().textSelection(.enabled)}.frame(minWidth:330)
                        } else {emptyDetail(packets.isEmpty ? "尚未发现红包；发现后会自动记录" : "选择一个红包查看领取数据")}
                    }
                    Text("已请求领取不代表领取成功；金额按货币分别统计，不重复累计。").font(.caption).foregroundStyle(.secondary)
                }.padding(.top,4)
                } else {
                VStack(alignment:.leading,spacing:12){
                    Text(model.popupRecordingActive ? "弹窗只读记录中 · 不执行点击或回调" : "弹窗记录等待新版脚本连接").font(.caption).foregroundStyle(.secondary)
                    HSplitView {
                        List(model.popupHistory.filter{search.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(search) || $0.title.localizedCaseInsensitiveContains(search) || $0.body.localizedCaseInsensitiveContains(search) || String($0.viewId).contains(search)},selection:$selectedPopup){record in
                            VStack(alignment:.leading,spacing:5){Text("\(record.phaseName) · \(record.displayTitle)").lineLimit(2);Text("\(record.viewName) · \(record.viewId)").font(.caption).foregroundStyle(.secondary);Text(Date(timeIntervalSince1970:record.capturedAt/1000).formatted(date:.abbreviated,time:.standard)).font(.caption).foregroundStyle(.secondary)}.padding(.vertical,4).tag(record.eventId)
                        }.frame(minWidth:300)
                        if let record=model.popupHistory.first(where:{$0.eventId==selectedPopup}) {
                            ScrollView{VStack(alignment:.leading,spacing:14){Text(record.displayTitle).font(.headline);if !record.body.isEmpty{Text(record.body)};Text("脱敏 JSON 数据").font(.caption).foregroundStyle(.secondary);Text(record.readableJSON).font(.system(size:11,design:.monospaced)).frame(maxWidth:.infinity,alignment:.leading)}.padding().textSelection(.enabled)}.frame(minWidth:360)
                        } else {emptyDetail("选择弹窗查看文案、按钮、场景与 JSON；暂无记录时等待弹窗自然出现")}
                    }
                    Text("按出现、变化、关闭记录 · 历史保存在本机弹窗历史.jsonl · 软件显示最近2000条").font(.caption).foregroundStyle(.secondary)
                }.padding(.top,4)
                }
            }
        }.padding(22).frame(minWidth:900,minHeight:600).preferredColorScheme(.dark)
    }
    private func emptyDetail(_ text:String)->some View {Text(text).foregroundStyle(.secondary).frame(minWidth:330,maxWidth:.infinity,maxHeight:.infinity)}
    private func detailRows(_ values:[String:String])->some View {
        VStack(alignment:.leading,spacing:14){ForEach(values.keys.sorted(),id:\.self){key in VStack(alignment:.leading,spacing:4){Text(key).font(.caption).foregroundStyle(.secondary);Text(values[key] ?? "").frame(maxWidth:.infinity,alignment:.leading)}}}.frame(maxWidth:.infinity,alignment:.leading)
    }
}
