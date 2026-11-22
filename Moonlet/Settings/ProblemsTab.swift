import SwiftUI

struct ProblemsTab: View {
    let problems: [Problem]

    var body: some View {
        if problems.isEmpty {
            ContentUnavailableView(
                "No problems",
                systemImage: "checkmark.circle",
                description: Text("Every wallpaper, playlist, stream, and pack loaded cleanly.")
            )
        } else {
            List(problems) { problem in
                VStack(alignment: .leading, spacing: 4) {
                    Text(problem.location)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(problem.message)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
    }
}
