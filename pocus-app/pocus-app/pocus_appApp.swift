import SwiftUI
import FamilyControls

@main
struct pocus_appApp: App {
    @StateObject var viewModel = HomeViewModel() // Keep ViewModel alive across views

    var body: some Scene {
        WindowGroup {
            HomeView(viewModel: viewModel) // Inject the same ViewModel instance
                .onAppear {
                    viewModel.requestScreenTimeAuthorization()
                }
        }
    }
}
