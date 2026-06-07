import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(GlanceHoldStrings.text(.aboutTitle))
                .font(.title3)
                .fontWeight(.semibold)

            Text(GlanceHoldStrings.text(.aboutSubtitle))
                .font(.headline)

            Text(GlanceHoldStrings.text(.aboutCalibrationBody))
                .foregroundStyle(.secondary)

            Text(GlanceHoldStrings.text(.aboutPrivacyBody))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 420, minHeight: 260)
        .padding()
    }
}

#Preview {
    ContentView()
}
