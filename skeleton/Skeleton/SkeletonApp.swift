import SwiftUI

@main
struct SkeletonApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.green)
                Text("构建链路 OK")
                    .font(.title3.weight(.semibold))
                Text("xcodegen → xcodebuild → ipa")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}
