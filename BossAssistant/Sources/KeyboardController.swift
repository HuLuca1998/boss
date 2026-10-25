import AppKit
import CoreGraphics

// Poll movement keys while the game is frontmost; no event tap or global interception.
@MainActor final class KeyboardController {
    var enabled=false
    private var timer:Timer?
    private var lastKeys:[Int]=[]
    private var lastSent=Date.distantPast
    private let send:([Int])->Void
    private var lastDiagnostic=Date.distantPast
    private var lastAccessCheck=Date.distantPast
    var onAccessChange:((Bool)->Void)?
    init(send:@escaping ([Int])->Void) {
        self.send=send
        timer=Timer.scheduledTimer(withTimeInterval:0.04,repeats:true){[weak self] _ in
            Task{@MainActor in self?.tick()}
        }
    }
    private func tick() {
        let active=enabled && NSWorkspace.shared.frontmostApplication?.bundleIdentifier=="com.yzlm.game"
        let keys=MovementInput.keys(enabled:enabled,frontmostBundle:NSWorkspace.shared.frontmostApplication?.bundleIdentifier){ native in
            CGEventSource.keyState(.combinedSessionState,key:CGKeyCode(native))
        }
        if Date().timeIntervalSince(lastAccessCheck)>1 {
            lastAccessCheck=Date();onAccessChange?(CGPreflightListenEventAccess())
        }
        let support=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/HeroBossAssistant")
        if Date().timeIntervalSince(lastDiagnostic)>0.2 && FileManager.default.fileExists(atPath:support.appendingPathComponent("KeyboardProbe.enabled").path) {
            lastDiagnostic=Date()
            let status:[String:Any]=["enabled":enabled,"gameFocused":active,"frontmostBundle":NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "", "keys":keys,"listenAllowed":CGPreflightListenEventAccess(),"time":Date().timeIntervalSince1970]
            if let data=try? JSONSerialization.data(withJSONObject:status){try? data.write(to:support.appendingPathComponent("KeyboardInput.json"),options:.atomic)}
        }
        if keys != lastKeys || (!keys.isEmpty && Date().timeIntervalSince(lastSent)>0.25) {
            lastKeys=keys;lastSent=Date();send(keys)
        }
    }
    deinit{timer?.invalidate()}
}
