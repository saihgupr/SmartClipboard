import Foundation

final class PasteTargetStore {
    static let shared = PasteTargetStore()
    var pid: pid_t?
    var bundleID: String?
    private init() {}
}
