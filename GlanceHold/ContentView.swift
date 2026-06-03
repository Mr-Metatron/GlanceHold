import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("GlanceHold")
                .font(.title)
                .fontWeight(.semibold)

            Text("Project scaffold ready.")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 420, minHeight: 260)
        .padding()
    }
}

#Preview {
    ContentView()
}
