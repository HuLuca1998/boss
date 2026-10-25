import Foundation
import Network

struct BridgeFailure: LocalizedError { let message:String; var errorDescription:String? { message } }
// All access and Network callbacks are confined to DispatchQueue.main.
@MainActor final class Bridge {
    private var listener:NWListener?
    private var game:NWConnection?
    private var connections:[UUID:NWConnection]=[:]
    private var authenticated:Set<UUID>=[]
    private var pending:[Int:(Result<Data,Error>)->Void]=[:]
    private var sequence=0
    var onChange:((Bool)->Void)?
    var onReady:((UInt16)->Void)?
    var onError:((String)->Void)?
    let token:String
    private(set) var port:UInt16=0
    var connected:Bool { game != nil }
    init(token:String) { self.token=token }
    func start(port preferred:UInt16) throws {
        let options=NWProtocolWebSocket.Options();options.autoReplyPing=true;options.maximumMessageSize=1_048_576
        let parameters=NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(options,at:0)
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback),port:NWEndpoint.Port(rawValue:preferred)!)
        let listener=try NWListener(using:parameters)
        self.listener=listener
        listener.stateUpdateHandler={ [weak self] state in
            DispatchQueue.main.async {
            if case .ready=state, let self, let port=listener.port?.rawValue { self.port=port;self.onReady?(port) }
            if case .failed(let error)=state { self?.onError?(error.localizedDescription) }
            }
        }
        listener.newConnectionHandler={ [weak self] c in DispatchQueue.main.async { self?.accept(c) } }
        listener.start(queue:.main)
    }
    private func accept(_ c:NWConnection) {
        let id=UUID();connections[id]=c
        c.stateUpdateHandler={ [weak self,weak c] state in
            DispatchQueue.main.async {
            guard let self,let c else{return}
            switch state {
            case .ready:self.receive(c,id)
            case .failed,.cancelled:
                self.connections[id]=nil;self.authenticated.remove(id)
                if self.game === c { self.game=nil;self.onChange?(false);self.failPending("游戏连接已断开") }
            default:break
            }
            }
        }
        c.start(queue:.main)
        DispatchQueue.main.asyncAfter(deadline:.now()+5){[weak self,weak c] in
            if self?.authenticated.contains(id) != true { c?.cancel() }
        }
    }
    private func receive(_ c:NWConnection,_ id:UUID) {
        c.receiveMessage{[weak self,weak c] data,context,complete,error in
            DispatchQueue.main.async {
            guard let self,let c else{return}
            if error != nil { c.cancel();return }
            if let metadata=context?.protocolMetadata(definition:NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata, metadata.opcode == .close {c.cancel();return}
            if let data, !data.isEmpty {
                guard let json=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else {c.cancel();return}
                if !self.authenticated.contains(id) {
                    guard json["hello"] as? String == "yzlm-native-boss-v2",json["token"] as? String == self.token else {c.cancel();return}
                    self.game?.cancel();self.authenticated.insert(id);self.game=c;self.onChange?(true)
                } else if let rid=json["id"] as? Int,let callback=self.pending.removeValue(forKey:rid) {
                    if let error=json["error"] as? String {callback(.failure(BridgeFailure(message:error)))}
                    else if let result=json["result"],let bytes=try? JSONSerialization.data(withJSONObject:result) {callback(.success(bytes))}
                    else {callback(.failure(BridgeFailure(message:"游戏返回的数据不完整")))}
                }
            }
            self.receive(c,id)
            }
        }
    }
    func request(_ op:String,fields:[String:Any]=[:]) async throws -> Data {
        guard let game else {throw BridgeFailure(message:"游戏尚未连接，请先注入脚本")}
        sequence+=1;let id=sequence
        var message=fields;message["op"]=op;message["id"]=id
        let data=try JSONSerialization.data(withJSONObject:message)
        return try await withCheckedThrowingContinuation { continuation in
            pending[id]={continuation.resume(with:$0)}
            let context=NWConnection.ContentContext(identifier:"boss-command",metadata:[NWProtocolWebSocket.Metadata(opcode:.text)])
            game.send(content:data,contentContext:context,isComplete:true,completion:.contentProcessed{[weak self] error in
                DispatchQueue.main.async { if let error {self?.pending.removeValue(forKey:id)?(.failure(error))} }
            })
            DispatchQueue.main.asyncAfter(deadline:.now()+12){[weak self] in self?.pending.removeValue(forKey:id)?(.failure(BridgeFailure(message:"游戏响应超时，请确认已进入角色界面")))}
        }
    }
    func failPending(_ message:String){let callbacks=Array(pending.values);pending.removeAll();callbacks.forEach{$0(.failure(BridgeFailure(message:message)))}}
}
