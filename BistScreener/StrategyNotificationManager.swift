import Foundation
import UserNotifications

struct StrategyApprovalCommand: Codable {
    enum Kind: String, Codable {
        case approve
        case reject
        case approveAll
        case rejectAll
        case openStrategy
    }

    let kind: Kind
    let actionID: UUID?
    let createdAt: Date
}

@MainActor
final class StrategyNotificationManager {
    static let shared = StrategyNotificationManager()

    static let actionApproveID = "STRATEGY_APPROVE"
    static let actionRejectID = "STRATEGY_REJECT"
    static let actionApproveAllID = "STRATEGY_APPROVE_ALL"
    static let actionRejectAllID = "STRATEGY_REJECT_ALL"

    static let categorySingle = "STRATEGY_PENDING_SINGLE"
    static let categorySummary = "STRATEGY_PENDING_SUMMARY"

    static let payloadActionID = "strategy_action_id"
    static let payloadSymbol = "strategy_symbol"

    private let center = UNUserNotificationCenter.current()
    private let commandQueueKey = "strategy.notification.command.queue.v1"

    private init() {}

    func configureCenter(delegate: UNUserNotificationCenterDelegate?) {
        center.delegate = delegate
        registerCategories()
    }

    func requestAuthorizationIfNeeded() {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            guard settings.authorizationStatus == .notDetermined else { return }
            self.center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    private func registerCategories() {
        let approve = UNNotificationAction(
            identifier: Self.actionApproveID,
            title: "Onayla",
            options: [.foreground]
        )
        let reject = UNNotificationAction(
            identifier: Self.actionRejectID,
            title: "Reddet",
            options: [.foreground]
        )

        let approveAll = UNNotificationAction(
            identifier: Self.actionApproveAllID,
            title: "Tümünü Onayla",
            options: [.foreground]
        )
        let rejectAll = UNNotificationAction(
            identifier: Self.actionRejectAllID,
            title: "Tümünü Reddet",
            options: [.destructive, .foreground]
        )

        let single = UNNotificationCategory(
            identifier: Self.categorySingle,
            actions: [approve, reject],
            intentIdentifiers: [],
            options: []
        )

        let summary = UNNotificationCategory(
            identifier: Self.categorySummary,
            actions: [approveAll, rejectAll],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([single, summary])
    }

    func syncPendingActions(_ pendingActions: [LiveStrategyPendingAction]) {
        let actionRequestIDs = Set(pendingActions.map { "strategy.pending.\($0.id.uuidString)" })
        let summaryID = "strategy.pending.summary"

        center.getPendingNotificationRequests { [weak self] requests in
            guard let self else { return }
            let existing = Set(requests.map(\.identifier))

            let removable = existing.filter { id in
                if id == summaryID { return pendingActions.isEmpty }
                if id.hasPrefix("strategy.pending.") { return !actionRequestIDs.contains(id) }
                return false
            }
            if !removable.isEmpty {
                self.center.removePendingNotificationRequests(withIdentifiers: Array(removable))
            }

            if pendingActions.isEmpty {
                self.center.removeDeliveredNotifications(withIdentifiers: [summaryID])
                return
            }

            for action in pendingActions {
                let requestID = "strategy.pending.\(action.id.uuidString)"
                guard !existing.contains(requestID) else { continue }

                let content = UNMutableNotificationContent()
                content.title = action.kind == .buy ? "AL Onayı Bekliyor" : "SAT Onayı Bekliyor"
                content.body = "\(action.symbol) • \(action.note)"
                content.sound = .default
                content.categoryIdentifier = Self.categorySingle
                content.userInfo = [
                    Self.payloadActionID: action.id.uuidString,
                    Self.payloadSymbol: action.symbol
                ]

                let req = UNNotificationRequest(identifier: requestID, content: content, trigger: nil)
                self.center.add(req)
            }

            if pendingActions.count > 1 {
                let content = UNMutableNotificationContent()
                content.title = "Strateji Onay Kuyruğu"
                content.body = "\(pendingActions.count) işlem onay bekliyor."
                content.sound = .default
                content.categoryIdentifier = Self.categorySummary
                let req = UNNotificationRequest(identifier: summaryID, content: content, trigger: nil)
                self.center.add(req)
            } else {
                self.center.removePendingNotificationRequests(withIdentifiers: [summaryID])
                self.center.removeDeliveredNotifications(withIdentifiers: [summaryID])
            }
        }
    }

    func handleNotificationResponse(_ response: UNNotificationResponse) {
        let actionIdentifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        let actionID = (userInfo[Self.payloadActionID] as? String).flatMap(UUID.init(uuidString:))

        let command: StrategyApprovalCommand
        switch actionIdentifier {
        case Self.actionApproveID:
            command = StrategyApprovalCommand(kind: .approve, actionID: actionID, createdAt: Date())
        case Self.actionRejectID:
            command = StrategyApprovalCommand(kind: .reject, actionID: actionID, createdAt: Date())
        case Self.actionApproveAllID:
            command = StrategyApprovalCommand(kind: .approveAll, actionID: nil, createdAt: Date())
        case Self.actionRejectAllID:
            command = StrategyApprovalCommand(kind: .rejectAll, actionID: nil, createdAt: Date())
        default:
            command = StrategyApprovalCommand(kind: .openStrategy, actionID: nil, createdAt: Date())
        }

        enqueue(command)
        NotificationCenter.default.post(name: .strategyApprovalCommandQueued, object: nil)
    }

    func drainQueuedCommands() -> [StrategyApprovalCommand] {
        let commands = readQueuedCommands()
        UserDefaults.standard.removeObject(forKey: commandQueueKey)
        return commands
    }

    private func enqueue(_ command: StrategyApprovalCommand) {
        var commands = readQueuedCommands()
        commands.append(command)
        if commands.count > 100 {
            commands.removeFirst(commands.count - 100)
        }
        guard let data = try? JSONEncoder().encode(commands) else { return }
        UserDefaults.standard.set(data, forKey: commandQueueKey)
    }

    private func readQueuedCommands() -> [StrategyApprovalCommand] {
        guard let data = UserDefaults.standard.data(forKey: commandQueueKey),
              let commands = try? JSONDecoder().decode([StrategyApprovalCommand].self, from: data) else {
            return []
        }
        return commands
    }
}
