import Foundation

// The foreground guard runs before any keyboard state is read.
enum MovementInput {
    static let bindings:[(UInt16,Int)]=[(123,37),(124,39),(125,40),(126,38),(0,37),(2,39),(1,40),(13,38),(53,27)]
    static func keys(enabled:Bool,frontmostBundle:String?,isDown:(UInt16)->Bool)->[Int] {
        guard enabled,frontmostBundle == "com.yzlm.game" else{return []}
        return Array(Set(bindings.compactMap{native,game in isDown(native) ? game : nil})).sorted()
    }
}
