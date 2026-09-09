import SwiftUI
import UIKit

struct CrisisResourcesView: View {
    private let helplines: [(region: String, name: String, contact: String, telURL: String?)] = [
        ("US", "988 Suicide & Crisis Lifeline", "Call or text 988", "tel:988"),
        ("US", "Crisis Text Line", "Text HOME to 741741", nil),
        ("India", "iCall (TISS)", "+91 9152987821", "tel:+919152987821"),
        ("India", "Vandrevala Foundation", "1860-2662-345", "tel:18602662345"),
        ("UK", "Samaritans", "116 123", "tel:116123")
    ]

    var body: some View {
        List {
            Section {
                Text("If you or someone else is in immediate danger, call your local emergency number right now.")
                    .font(.subheadline.bold())
                    .foregroundStyle(.red)
            }

            Section("Helplines") {
                ForEach(helplines, id: \.name) { line in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(line.name).font(.headline)
                        Text("\(line.region) · \(line.contact)").font(.subheadline)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let url = line.telURL, let telURL = URL(string: url) {
                            UIApplication.shared.open(telURL)
                        }
                    }
                }
            }

            Section("Grounding Exercise") {
                Text("Try 5-4-3-2-1: name 5 things you can see, 4 you can touch, 3 you can hear, 2 you can smell, 1 you can taste.")
            }
        }
        .navigationTitle("Crisis Resources")
    }
}
