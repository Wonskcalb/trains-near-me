#if os(iOS)
import SNCFCore
import SwiftUI

/// First launch, and every launch until a token is saved: the app shows nothing without one, so it
/// explains why before showing an empty board. Each user brings their own free SNCF token, which
/// keeps everyone on their own 5 000-request daily quota.
struct OnboardingView: View {
    let done: () -> Void

    @State private var token = ""
    @State private var testing = false
    @State private var result: (works: Bool, message: String)?
    @State private var location = LocationFix.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Color.amber)
                    Text("Trains near me").font(.largeTitle.bold()).foregroundStyle(Color.ink)
                    Text("The next direct trains of your journeys, and everything leaving the station closest to you — in the app and in widgets.")
                        .foregroundStyle(Color.inkSecondary)
                }
                .padding(.top, 24)

                step(1, "Get your free SNCF key",
                     "SNCF hands out free personal keys for its train data. Fill in the form: the key arrives by email within minutes.") {
                    Link(destination: URL(string: "https://numerique.sncf.com/startup/api/token-developpeur/")!) {
                        Label("Request a key", systemImage: "arrow.up.right")
                            .font(.body.weight(.semibold))
                    }
                }

                step(2, "Paste it here", "It stays on this iPhone and is only sent to SNCF.") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Key", text: $token)
                            .font(.mono(14, weight: .medium))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color.raised, in: RoundedRectangle(cornerRadius: 12))
                        HStack(spacing: 10) {
                            Button("Check the key") { Task { await check() } }
                                .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || testing)
                            if testing { ProgressView().controlSize(.small) }
                            if let result {
                                Text(result.message)
                                    .font(.footnote)
                                    .foregroundStyle(result.works ? Color.soon : Color.caution)
                            }
                        }
                    }
                }

                step(3, "Allow your location", "Optional. Used only to find the station closest to you.") {
                    if location.status == .notDetermined {
                        Button("Allow location") { location.requestAuthorization() }
                    } else {
                        Label(location.isAuthorized ? "Allowed" : "Not allowed — change it later in iOS Settings",
                              systemImage: location.isAuthorized ? "checkmark.circle.fill" : "xmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(Color.inkSecondary)
                    }
                }

                Button(action: done) {
                    Text("Start")
                        .font(.headline)
                        .foregroundStyle(Color.ground)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Color.amber, in: RoundedRectangle(cornerRadius: 16))
                }
                .disabled(result?.works != true)
                .opacity(result?.works == true ? 1 : 0.4)

                Button("Later", action: done)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(Color.inkSecondary)

                Text("Not affiliated with SNCF. Train data © SNCF, via the SNCF open data API.")
                    .font(.footnote).foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color.ground.ignoresSafeArea())
        .tint(.amber)
    }

    private func check() async {
        testing = true
        result = await SettingsView.saveAndTest(token)
        testing = false
    }

    private func step<Content: View>(_ number: Int, _ title: LocalizedStringKey, _ detail: LocalizedStringKey,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(number, format: .number)
                    .font(.mono(13, weight: .bold)).foregroundStyle(Color.ground)
                    .frame(width: 22, height: 22)
                    .background(Color.amber, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(Color.ink)
                    Text(detail).font(.subheadline).foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content().padding(.leading, 32)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.ink.opacity(0.06), lineWidth: 1))
    }
}
#endif
