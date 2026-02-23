import Foundation

@MainActor
final class ScannerVMHolder: ObservableObject {
    @Published var vm: ScannerViewModel

    init(vm: ScannerViewModel) {
        self.vm = vm
    }
}
