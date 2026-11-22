import SwiftUI
import Photos
import UIKit

@main
struct PhotoLibraryApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var full = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var add = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    @State private var picked = 0

    var body: some View {
        VStack(spacing: 20) {
            Text("Full access: \(name(full))")
            Text("Adding: \(name(add))")
            Button("Ask for full access") {
                Task { full = await PHPhotoLibrary.requestAuthorization(for: .readWrite); refresh() }
            }
            Button("Ask to add photos") {
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    Task { @MainActor in add = status; refresh() }
                }
            }
            if full == .limited {
                Button("Select more photos") {
                    let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
                    let root = scene?.windows.first?.rootViewController ?? UIViewController()
                    PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root) { ids in
                        Task { @MainActor in picked = ids.count }
                    }
                }
                Text("Newly picked: \(picked)")
            }
        }
    }

    private func refresh() {
        full = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        add = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    }

    private func name(_ status: PHAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "not asked"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorized: "authorized"
        case .limited: "limited"
        @unknown default: "unknown"
        }
    }
}
