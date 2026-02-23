import Foundation

struct ScannerConfig: Equatable {
    var defaultIndex: IndexOption
    var concurrencyLimit: Int
    var preset: TomorrowPreset
    var maxResults: Int

    init(
        defaultIndex: IndexOption,
        concurrencyLimit: Int,
        preset: TomorrowPreset,
        maxResults: Int
    ) {
        self.defaultIndex = defaultIndex
        self.concurrencyLimit = min(max(concurrencyLimit, 1), 16)
        self.preset = preset
        self.maxResults = max(0, maxResults)
    }

    @MainActor
    init(from settings: SettingsStore) {
        self.init(
            defaultIndex: settings.defaultIndex,
            concurrencyLimit: settings.concurrencyLimit,
            preset: settings.preset,          // ✅ SettingsStore’a ekleyeceğiz
            maxResults: settings.maxResults
        )
    }
}
