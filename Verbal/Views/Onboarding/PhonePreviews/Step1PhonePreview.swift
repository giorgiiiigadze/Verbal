import SwiftUI

struct Step1PhonePreview: View {
    var body: some View {
        Text("Step 1")
            .font(.title2.weight(.semibold))
            .foregroundStyle(Color(.mainText))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.homeBackground))
    }
}
