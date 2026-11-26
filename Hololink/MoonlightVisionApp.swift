//

import SwiftUI

struct MoonlightVisionApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            AppContentView()
                .environmentObject(appDelegate.mainViewModel)
                .frame(minWidth: Constants.contentWindowWidth, maxWidth: .infinity, minHeight: Constants.contentWindowHeight, maxHeight: .infinity)
        }
        .windowResizability(.contentSize)
        .windowStyle(.plain)
    }
}

@main
struct MainWrapper {
    static func main() -> Void {          
        SDLMainWrapper.setMainReady();
        MoonlightVisionApp.main()
    }
}
