import SwiftUI

struct AssetsTabRoot: View {
    @StateObject private var lockVM = AppLockViewModel()
    @State private var didAutoPrompt = false

    var body: some View {
        ZStack {
            TVTheme.bg.ignoresSafeArea()

            Group {
                if lockVM.isUnlocked {
                    AssetsView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    lockVM.lock()
                                } label: {
                                    Image(systemName: "lock.fill")
                                        .foregroundStyle(TVTheme.text)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Kilitle")
                            }
                        }
                } else {
                    LockView(vm: lockVM)
                }
            }
        }
        .navigationTitle("Varlıklarım")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(TVTheme.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            // ✅ sadece 1 kere otomatik FaceID iste
            guard !didAutoPrompt else { return }
            didAutoPrompt = true
            await lockVM.unlock()
        }
    }
}

private struct LockView: View {
    @ObservedObject var vm: AppLockViewModel

    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            TVCard {
                VStack(spacing: 14) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 42))
                        .foregroundStyle(TVTheme.subtext)

                    Text("Varlıklar Kilitli")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(TVTheme.text)

                    if let e = vm.errorText {
                        Text(e)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else {
                        Text("FaceID/TouchID ile giriş yap.")
                            .font(.footnote)
                            .foregroundStyle(TVTheme.subtext)
                    }

                    Button {
                        Task { await vm.unlock() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "faceid")
                            Text("Giriş Yap")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TVTheme.up)
                }
                .padding(.vertical, 6)
            }
            .padding(.horizontal, DS.s16)

            Spacer()
        }
        .padding(.bottom, 20)
    }
}
