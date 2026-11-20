// Where an iOS confirmation dialog opens for sources of different shapes and places
// (`ios/dialog/…`, new-website#649): a full-width button low in the window, a small button on
// the trailing side, and a tall column scrolled to its end (Paulo's settings column, whose
// Sign out button sets the dialog's flag). Each is presented by a step, as a button's action would.
import SwiftUI
import FixtureKit

public enum IOSOverlayFixtures {
    static let phone = CGSize(width: 375, height: 667)

    private static func dialogBinding(_ model: IOSPresentationModel) -> Binding<Bool> {
        Binding(get: { model.dialog }, set: { model.dialog = $0 })
    }

    /// The modifier on a full-width button near the bottom of the window.
    public static let dialogWideButton = Fixture(
        "ios/dialog/wide-button", size: phone,
        model: { IOSPresentationModel() },
        steps: [FixtureStep("present") { $0.dialog = true }]
    ) { model in
        VStack(spacing: 0) {
            Spacer()
            Button("Sign out") { model.dialog = true }
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 26))
                .confirmationDialog("Sign out?", isPresented: dialogBinding(model), titleVisibility: .visible) {
                    Button("Sign out", role: .destructive) {}
                } message: {
                    Text("Your plan and history stay saved. Sign in again any time.")
                }
                .probe("button")
            Text("Version 1.0 (1)").font(.footnote).padding(.top, 12).padding(.bottom, 120)
        }
        .padding(.horizontal, 16)
        .background(Color(white: 0.95).ignoresSafeArea())
        .probe("stack")
    }.platform(.iOS).capturesWindow()

    /// The modifier on a small button on the trailing side, in the lower half.
    public static let dialogTrailingButton = Fixture(
        "ios/dialog/trailing-button", size: phone,
        model: { IOSPresentationModel() },
        steps: [FixtureStep("present") { $0.dialog = true }]
    ) { model in
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button("Delete") { model.dialog = true }
                    .confirmationDialog("Delete it?", isPresented: dialogBinding(model), titleVisibility: .visible) {
                        Button("Delete", role: .destructive) {}
                    } message: {
                        Text("This can't be undone.")
                    }
                    .probe("button")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 200)
        }
        .background(Color.white.ignoresSafeArea())
        .probe("stack")
    }.platform(.iOS).capturesWindow()

    /// The modifier on a column taller than the window, scrolled to its end, the button at the
    /// column's foot (Paulo's settings column).
    public static let dialogTallColumn = Fixture(
        "ios/dialog/tall-column", size: phone,
        model: { IOSPresentationModel() },
        steps: [FixtureStep("present") { $0.dialog = true }]
    ) { model in
        ScrollView {
            VStack(spacing: 16) {
                ForEach(0..<10, id: \.self) { index in
                    Text("Row \(index)").frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .padding(.horizontal, 16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 26))
                }
                Button("Sign out") { model.dialog = true }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 26))
                    .probe("button")
                Text("Version 1.0 (1)").font(.footnote)
            }
            .padding(16)
            .confirmationDialog("Sign out?", isPresented: dialogBinding(model), titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {}
            } message: {
                Text("Your plan and history stay saved. Sign in again any time.")
            }
            .probe("column")
        }
        .defaultScrollAnchor(.bottom)
        .background(Color(white: 0.95).ignoresSafeArea())
        .probe("scroll")
    }.platform(.iOS).capturesWindow()

    public static let all: [Fixture] = [dialogWideButton, dialogTrailingButton, dialogTallColumn]
}
