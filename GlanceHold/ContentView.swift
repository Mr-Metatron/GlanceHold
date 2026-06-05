import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("GlanceHold")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Monitoring is off")
                .font(.headline)

            Text("Enable monitoring when you are ready. Camera access is requested only after you start.")
                .foregroundStyle(.secondary)

            Text("GlanceHold uses the camera only on this Mac to tell whether you are facing the screen. Frames are not saved or uploaded.")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 420, minHeight: 260)
        .padding()
    }
}

#Preview {
    ContentView()
}
