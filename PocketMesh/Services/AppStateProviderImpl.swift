#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import PocketMeshServices

/// Platform-based implementation of AppStateProvider.
///
/// On iOS, checks UIApplication.shared.applicationState to determine if app is in foreground.
/// On macOS, the app is always considered in foreground (macOS apps don't background the same way).
/// MainActor-isolated with async getter to allow cross-actor access.
@MainActor
public final class AppStateProviderImpl: AppStateProvider {

    public init() {}

    nonisolated public var isInForeground: Bool {
        get async {
            #if canImport(UIKit)
            await MainActor.run {
                UIApplication.shared.applicationState != .background
            }
            #else
            true
            #endif
        }
    }
}
