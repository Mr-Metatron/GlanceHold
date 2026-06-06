import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("GlanceHold")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Local camera attention signal")
                .font(.headline)

            Text("Calibrate your facing-screen pose before monitoring can use camera signals. Camera access starts only after you choose calibration or monitoring.")
                .foregroundStyle(.secondary)

            Text("Camera stays on this Mac. Frames are not saved or uploaded.")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 420, minHeight: 260)
        .padding()
    }
}

#Preview {
    ContentView()
}
