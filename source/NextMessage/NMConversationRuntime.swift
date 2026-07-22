import Foundation
import UIKit
import ObjectiveC.runtime
import SQLite3

private let nmConversationProxySelector = NSSelectorFromString("tableView:trailingSwipeActionsConfigurationForRowAtIndexPath:")
private var nmConversationProxyKey: UInt8 = 0
private let nmSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private struct NMConversationRecord {
    var rowID: Int64 = 0
    var title: String = "Conversation"
    var identifier: String = ""
    var messageCount: Int = 0
    var firstMessage: Date?
    var latestMessage: Date?
}

private final class NMConversationInfoController: UIViewController {
    var record = NMConversationRecord()

    private let card = UIView()
    private let titleLabel = UILabel()
    private let identifierLabel = UILabel()
    private let countLabel = UILabel()
    private let firstLabel = UILabel()
    private let latestLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let strip = CAGradientLayer()

    override func viewDidLoad() {
        super.viewDidLoad()
        modalPresentationStyle = .overFullScreen
        view.backgroundColor = UIColor.black.withAlphaComponent(0.72)

        card.backgroundColor = UIColor(red: 0.045, green: 0.070, blue: 0.145, alpha: 0.99)
        card.layer.cornerRadius = 30
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.15).cgColor
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.5
        card.layer.shadowRadius = 28
        card.layer.shadowOffset = CGSize(width: 0, height: 14)
        view.addSubview(card)

        strip.colors = [
            UIColor(red: 1.0, green: 0.32, blue: 0.37, alpha: 1).cgColor,
            UIColor(red: 0.43, green: 0.37, blue: 1.0, alpha: 1).cgColor,
            UIColor(red: 0.04, green: 0.80, blue: 0.72, alpha: 1).cgColor
        ]
        strip.startPoint = CGPoint(x: 0, y: 0.5)
        strip.endPoint = CGPoint(x: 1, y: 0.5)
        strip.cornerRadius = 3
        card.layer.addSublayer(strip)

        configure(titleLabel, size: 26, weight: .bold, color: .white)
        configure(identifierLabel, size: 13, weight: .medium, color: UIColor.white.withAlphaComponent(0.62))
        configure(countLabel, size: 19, weight: .bold, color: .white)
        configure(firstLabel, size: 17, weight: .semibold, color: .white)
        configure(latestLabel, size: 17, weight: .semibold, color: .white)

        titleLabel.text = record.title
        identifierLabel.text = record.identifier.isEmpty ? "Messages conversation" : record.identifier
        countLabel.text = "Total messages\n\(NumberFormatter.localizedString(from: NSNumber(value: record.messageCount), number: .decimal))"
        firstLabel.text = "First message\n\(formatted(record.firstMessage))"
        latestLabel.text = "Latest message\n\(formatted(record.latestMessage))"

        [titleLabel, identifierLabel, countLabel, firstLabel, latestLabel].forEach(card.addSubview)

        closeButton.setTitle("Close", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        closeButton.backgroundColor = UIColor.white.withAlphaComponent(0.11)
        closeButton.layer.cornerRadius = 17
        closeButton.layer.cornerCurve = .continuous
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        card.addSubview(closeButton)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        card.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        card.alpha = 0
        UIView.animate(withDuration: 0.30,
                       delay: 0,
                       usingSpringWithDamping: 0.80,
                       initialSpringVelocity: 0) {
            self.card.transform = .identity
            self.card.alpha = 1
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = min(view.bounds.width - 30, 410)
        let height: CGFloat = 440
        card.frame = CGRect(x: (view.bounds.width - width) / 2,
                            y: (view.bounds.height - height) / 2,
                            width: width,
                            height: height)
        strip.frame = CGRect(x: 24, y: 18, width: width - 48, height: 6)
        titleLabel.frame = CGRect(x: 24, y: 42, width: width - 48, height: 66)
        identifierLabel.frame = CGRect(x: 24, y: 104, width: width - 48, height: 40)
        countLabel.frame = CGRect(x: 24, y: 154, width: width - 48, height: 66)
        firstLabel.frame = CGRect(x: 24, y: 232, width: width - 48, height: 64)
        latestLabel.frame = CGRect(x: 24, y: 306, width: width - 48, height: 64)
        closeButton.frame = CGRect(x: 24, y: height - 62, width: width - 48, height: 46)
    }

    private func configure(_ label: UILabel, size: CGFloat, weight: UIFont.Weight, color: UIColor) {
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.numberOfLines = 0
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.68
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "Not available" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}

private final class NMConversationDelegateProxy: NSObject, UITableViewDelegate {
    weak var originalDelegate: UITableViewDelegate?
    weak var tableView: UITableView?

    init(originalDelegate: UITableViewDelegate?, tableView: UITableView) {
        self.originalDelegate = originalDelegate
        self.tableView = tableView
        super.init()
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == nmConversationProxySelector { return true }
        return super.responds(to: aSelector) || (originalDelegate?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if originalDelegate?.responds(to: aSelector) == true {
            return originalDelegate
        }
        return super.forwardingTarget(for: aSelector)
    }

    @objc(tableView:trailingSwipeActionsConfigurationForRowAtIndexPath:)
    func nmTrailingActions(_ tableView: UITableView, indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard NMConversationRuntime.shared.isEnabled,
              NMConversationRuntime.shared.swipeEnabled else { return nil }

        let info = UIContextualAction(style: .normal, title: "Info") { _, _, completion in
            NMConversationRuntime.shared.presentConversationInfo(tableView: tableView, indexPath: indexPath)
            completion(true)
        }
        info.backgroundColor = UIColor(red: 0.26, green: 0.39, blue: 0.95, alpha: 1)
        info.image = UIImage(systemName: "info.circle.fill")
        let configuration = UISwipeActionsConfiguration(actions: [info])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }
}

final class NMConversationRuntime {
    static let shared = NMConversationRuntime()

    var isEnabled: Bool { boolValue("enabled", fallback: true) }
    var swipeEnabled: Bool { boolValue("conversationSwipeInfo", fallback: true) }

    func register(tableView: UITableView) {
        guard Bundle.main.bundleIdentifier == "com.apple.MobileSMS" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.updateProxy(for: tableView)
        }
    }

    func refreshAllTables() {
        guard Bundle.main.bundleIdentifier == "com.apple.MobileSMS" else { return }
        for scene in UIApplication.shared.connectedScenes {
            guard let scene = scene as? UIWindowScene else { continue }
            for window in scene.windows {
                self.walk(view: window)
            }
        }
    }

    private func walk(view: UIView) {
        if let table = view as? UITableView {
            updateProxy(for: table)
        }
        view.subviews.forEach(walk)
    }

    private func updateProxy(for tableView: UITableView) {
        let existing = objc_getAssociatedObject(tableView, &nmConversationProxyKey) as? NMConversationDelegateProxy
        guard isEnabled, swipeEnabled, isConversationList(tableView) else {
            if let existing {
                if tableView.delegate === existing {
                    tableView.delegate = existing.originalDelegate
                }
                objc_setAssociatedObject(tableView, &nmConversationProxyKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
            return
        }

        if let existing {
            if tableView.delegate !== existing {
                existing.originalDelegate = tableView.delegate
                tableView.delegate = existing
            }
            return
        }

        let proxy = NMConversationDelegateProxy(originalDelegate: tableView.delegate, tableView: tableView)
        objc_setAssociatedObject(tableView, &nmConversationProxyKey, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        tableView.delegate = proxy
    }

    private func isConversationList(_ tableView: UITableView) -> Bool {
        guard tableView.window != nil else { return false }
        guard let controller = controllerForView(tableView) else { return false }
        let className = NSStringFromClass(type(of: controller)).lowercased()
        let title = (controller.title ?? controller.navigationItem.title ?? "").lowercased()

        if className.contains("transcript") || className.contains("details") || className.contains("compose") {
            return false
        }
        if className.contains("conversationlist") || className.contains("messageslist") {
            return true
        }
        if title == "messages" || title == "all messages" || title == "known senders" || title == "unknown senders" {
            return true
        }
        return tableView.visibleCells.contains { cell in
            let name = NSStringFromClass(type(of: cell)).lowercased()
            return name.contains("conversation") && !name.contains("transcript")
        }
    }

    func presentConversationInfo(tableView: UITableView, indexPath: IndexPath) {
        if boolValue("haptics", fallback: true) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        let hint = conversationHint(tableView: tableView, indexPath: indexPath)
        let title = visibleConversationTitle(tableView: tableView, indexPath: indexPath)
        let fallbackIndex = max(0, indexPath.row)

        DispatchQueue.global(qos: .userInitiated).async {
            let record = NMConversationDatabase.record(hint: hint, title: title, fallbackIndex: fallbackIndex)
            DispatchQueue.main.async {
                guard let root = tableView.window?.rootViewController else { return }
                let presenter = self.topController(root)
                let controller = NMConversationInfoController()
                controller.record = record
                controller.modalPresentationStyle = .overFullScreen
                controller.modalTransitionStyle = .crossDissolve
                presenter.present(controller, animated: true)
            }
        }
    }

    private func conversationHint(tableView: UITableView, indexPath: IndexPath) -> String? {
        var objects: [NSObject] = []
        if let cell = tableView.cellForRow(at: indexPath) { objects.append(cell) }
        if let dataSource = tableView.dataSource as? NSObject { objects.append(dataSource) }
        if let delegate = (objc_getAssociatedObject(tableView, &nmConversationProxyKey) as? NMConversationDelegateProxy)?.originalDelegate as? NSObject {
            objects.append(delegate)
        }

        let zeroArgumentSelectors = ["conversation", "_conversation", "chat", "_chat", "conversationItem", "item", "representedObject"]
        for object in objects {
            for selectorName in zeroArgumentSelectors {
                if let model = performObject(object, selectorName: selectorName),
                   let value = identifier(from: model, depth: 0) {
                    return value
                }
            }
            if let direct = identifier(from: object, depth: 0) { return direct }
        }
        return nil
    }

    private func identifier(from object: AnyObject, depth: Int) -> String? {
        guard depth < 3, let object = object as? NSObject else { return nil }
        if let string = object as? NSString, string.length > 0 { return string as String }

        let stringSelectors = ["chatIdentifier", "identifier", "guid", "uniqueIdentifier", "displayName", "name"]
        for selectorName in stringSelectors {
            if let value = performObject(object, selectorName: selectorName) as? NSString,
               value.length > 0 {
                return value as String
            }
        }

        let nestedSelectors = ["chat", "conversation", "handle", "recipient", "item"]
        for selectorName in nestedSelectors {
            if let nested = performObject(object, selectorName: selectorName),
               let value = identifier(from: nested, depth: depth + 1) {
                return value
            }
        }
        return nil
    }

    private func performObject(_ object: NSObject, selectorName: String) -> AnyObject? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector), let unmanaged = object.perform(selector) else { return nil }
        return unmanaged.takeUnretainedValue() as AnyObject
    }

    private func visibleConversationTitle(tableView: UITableView, indexPath: IndexPath) -> String? {
        guard let cell = tableView.cellForRow(at: indexPath) else { return nil }
        var labels: [UILabel] = []
        collectLabels(in: cell.contentView, output: &labels)
        let candidates = labels.compactMap { label -> String? in
            let value = label.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard value.count > 1 else { return nil }
            guard !value.lowercased().contains("message") || labels.count == 1 else { return nil }
            return value
        }
        return candidates.first
    }

    private func collectLabels(in view: UIView, output: inout [UILabel]) {
        if let label = view as? UILabel { output.append(label) }
        view.subviews.forEach { collectLabels(in: $0, output: &output) }
    }

    private func controllerForView(_ view: UIView) -> UIViewController? {
        var responder: UIResponder? = view
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }

    private func topController(_ controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController { return topController(presented) }
        if let navigation = controller as? UINavigationController, let visible = navigation.visibleViewController {
            return topController(visible)
        }
        if let tab = controller as? UITabBarController, let selected = tab.selectedViewController {
            return topController(selected)
        }
        return controller
    }

    private func preferenceObject(_ key: String) -> Any? {
        if let value = CFPreferencesCopyValue(key as CFString,
                                              "com.nextsolution.nextmessage" as CFString,
                                              kCFPreferencesCurrentUser,
                                              kCFPreferencesAnyHost) {
            return value
        }
        let paths = [
            "/var/mobile/Library/Preferences/com.nextsolution.nextmessage.plist",
            "/private/var/mobile/Library/Preferences/com.nextsolution.nextmessage.plist",
            "/var/jb/var/mobile/Library/Preferences/com.nextsolution.nextmessage.plist",
            "/bootstrap/var/mobile/Library/Preferences/com.nextsolution.nextmessage.plist"
        ]
        for path in paths {
            if let dictionary = NSDictionary(contentsOfFile: path), let value = dictionary[key] { return value }
        }
        return nil
    }

    private func boolValue(_ key: String, fallback: Bool) -> Bool {
        (preferenceObject(key) as? NSNumber)?.boolValue ?? fallback
    }
}

private enum NMConversationDatabase {
    static func record(hint: String?, title: String?, fallbackIndex: Int) -> NMConversationRecord {
        guard let database = openDatabase() else {
            return NMConversationRecord(title: title ?? "Conversation", identifier: hint ?? "Database unavailable")
        }
        defer { sqlite3_close(database) }

        let filter = messageFilter(database)
        if let hint, !hint.isEmpty,
           let record = queryRecord(database, filter: filter, match: hint, offset: nil) {
            return record
        }
        if let title, !title.isEmpty,
           let record = queryRecord(database, filter: filter, match: title, offset: nil) {
            return record
        }
        if let record = queryRecord(database, filter: filter, match: nil, offset: fallbackIndex) {
            return record
        }
        return NMConversationRecord(title: title ?? "Conversation", identifier: hint ?? "No linked messages")
    }

    private static func queryRecord(_ database: OpaquePointer,
                                    filter: String,
                                    match: String?,
                                    offset: Int?) -> NMConversationRecord? {
        var sql = """
        SELECT c.ROWID,
               COALESCE(NULLIF(c.display_name,''), NULLIF(c.chat_identifier,''), NULLIF(c.guid,''), 'Conversation'),
               COALESCE(NULLIF(c.chat_identifier,''), NULLIF(c.guid,''), ''),
               COUNT(DISTINCT cmj.message_id), MIN(m.date), MAX(m.date)
        FROM chat c
        JOIN chat_message_join cmj ON cmj.chat_id = c.ROWID
        JOIN message m ON m.ROWID = cmj.message_id
        WHERE \(filter)
        """
        if match != nil {
            sql += " AND (c.chat_identifier = ?1 OR c.guid = ?1 OR c.display_name = ?1)"
        }
        sql += " GROUP BY c.ROWID ORDER BY MAX(m.date) DESC"
        if let offset {
            sql += " LIMIT 1 OFFSET \(max(0, offset))"
        } else {
            sql += " LIMIT 1"
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        if let match {
            sqlite3_bind_text(statement, 1, match, -1, nmSQLiteTransient)
        }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        var record = NMConversationRecord()
        record.rowID = sqlite3_column_int64(statement, 0)
        record.title = text(statement, column: 1) ?? "Conversation"
        record.identifier = text(statement, column: 2) ?? ""
        record.messageCount = Int(sqlite3_column_int64(statement, 3))
        record.firstMessage = appleDate(sqlite3_column_double(statement, 4))
        record.latestMessage = appleDate(sqlite3_column_double(statement, 5))
        return record
    }

    private static func openDatabase() -> OpaquePointer? {
        let candidates = [
            "/var/mobile/Library/SMS/sms.db",
            "/private/var/mobile/Library/SMS/sms.db",
            "/var/jb/var/mobile/Library/SMS/sms.db",
            "/bootstrap/var/mobile/Library/SMS/sms.db"
        ]
        guard let path = candidates.first(where: FileManager.default.fileExists(atPath:)) else { return nil }
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            return nil
        }
        return database
    }

    static func messageFilter(_ database: OpaquePointer, alias: String = "m") -> String {
        let columns = tableColumns(database, table: "message")
        var conditions = ["\(alias).date > 0"]
        if columns.contains("is_deleted") { conditions.append("IFNULL(\(alias).is_deleted,0)=0") }
        if columns.contains("associated_message_type") { conditions.append("IFNULL(\(alias).associated_message_type,0)=0") }
        return conditions.joined(separator: " AND ")
    }

    static func tableColumns(_ database: OpaquePointer, table: String) -> Set<String> {
        var columns = Set<String>()
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(\(table));", -1, &statement, nil) == SQLITE_OK,
              let statement else { return columns }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if let value = text(statement, column: 1) { columns.insert(value) }
        }
        return columns
    }

    static func text(_ statement: OpaquePointer, column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: pointer)
    }

    static func appleDate(_ rawValue: Double) -> Date? {
        guard rawValue > 0 else { return nil }
        var seconds = rawValue
        if seconds > 10_000_000_000 { seconds /= 1_000_000_000 }
        return Date(timeIntervalSince1970: seconds + 978_307_200)
    }
}

@_cdecl("NMRegisterSwiftTableView")
public func NMRegisterSwiftTableView(_ tablePointer: UnsafeMutableRawPointer?) {
    guard Bundle.main.bundleIdentifier == "com.apple.MobileSMS", let tablePointer else { return }
    let tableView = Unmanaged<UITableView>.fromOpaque(tablePointer).takeUnretainedValue()
    NMConversationRuntime.shared.register(tableView: tableView)
}

@_cdecl("NMRefreshSwiftConversationTables")
public func NMRefreshSwiftConversationTables() {
    NMConversationRuntime.shared.refreshAllTables()
}
