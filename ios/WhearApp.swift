import SwiftUI
import FirebaseCore
import UIKit

// MARK: - AppDelegate (Firebase + UIKit setup)

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        setupAppearance()
        return true
    }

    private func setupAppearance() {
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor.white
        navAppearance.shadowColor = .clear
        navAppearance.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        ]
        navAppearance.largeTitleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        ]
        UINavigationBar.appearance().standardAppearance   = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance    = navAppearance
        UITabBar.appearance().isHidden                    = true
        UITableView.appearance().backgroundColor          = UIColor.white
        UITableViewCell.appearance().backgroundColor      = UIColor.white
    }
}

// MARK: - App entry point

@main
struct WhearApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
