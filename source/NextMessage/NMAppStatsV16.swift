import Foundation
import UIKit
import SQLite3

private let nmV16Domain = "com.nextsolution.nextmessage"
private let nmV16Changed = "com.nextsolution.nextmessage/preferences.changed"
private let nmV16ButtonTag = 761600

private struct NMV16AppStats {
    var conversations = 0
    var messages = 0
    var firstMessage: Date?
    var latestMessage: Date?
    var error: String?
}

private final class NMV16FloatingButton: UIButton {
    var tapHandler: (() -> Void)?
    private var startCenter = CGPoint.zero
    private let gradient = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = frame.width / 2
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.38
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 7)

        gradient.colors = [
            UIColor(red: 1.0, green: 0.32, blue: 0.37, alpha: 1).cgColor,
            UIColor(red: 0.43, green: 0.37, blue: 1.0, alpha: 1).cgColor,
            UIColor(red: 0.04, green: 0.80, blue: 0.72, alpha: 1).cgColor
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.cornerRadius = frame.width / 2
        layer.insertSublayer(gradient, at: 0)

        setImage(UIImage(systemName: "chart.bar.doc.horizontal.fill"), for: .normal)
        tintColor = .white
        imageEdgeInsets = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)
        accessibilityLabel = "Next Message information"
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragged(_:))))
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        gradient.cornerRadius = bounds.width / 2
        layer.cornerRadius = bounds.width / 2
    }

    @objc private func tapped() { tapHandler?() }

    @objc private func dragged(_ recognizer: UIPanGestureRecognizer) {
        guard let container = superview else { return }
        switch recognizer.state {
        case .began:
            startCenter = center
        case .changed:
            let translation = recognizer.translation(in: container)
            center = CGPoint(x: startCenter.x + translation.x, y: startCenter.y + translation.y)
        case .ended, .cancelled:
            let safe = container.safeAreaInsets
            let half = bounds.width / 2
            let targetX = center.x < container.bounds.midX ? safe.left + half + 10 : container.bounds.width - safe.right - half - 10
            let targetY = min(max(center.y, safe.top + half + 10), container.bounds.height - safe.bottom - half - 10)
            UIView.animate(withDuration: 0.25,
                           delay: 0,
                           usingSpringWithDamping: 0.82,
                           initialSpringVelocity: 0) {
                self.center = CGPoint(x: targetX, y: targetY)
            }
        default:
            break
        }
    }
}

private final class NMV16AppCardController: UIViewController {
    private let card = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let conversationsValue = UILabel()
    private let messagesValue = UILabel()
    private let firstValue = UILabel()
    private let latestValue = UILabel()
    private let statusLabel = UILabel()
    private let refreshButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let strip = CAGradientLayer()
    private var tiles: [UIView] = []

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
        card.layer.shadowRadius = 30
        card.layer.shadowOffset = CGSize(width: 0, height: 16)
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

        titleLabel.text = "Next Message"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        card.addSubview(titleLabel)

        subtitleLabel.text = "Messages linked to active conversations"
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.68)
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        card.addSubview(subtitleLabel)

        tiles = [
            makeTile(title: "CONVERSATIONS", valueLabel: conversationsValue, icon: "bubble.left.and.bubble.right.fill"),
            makeTile(title: "MESSAGES", valueLabel: messagesValue, icon: "message.fill"),
            makeTile(title: "FIRST MESSAGE", valueLabel: firstValue, icon: "calendar.badge.clock"),
            makeTile(title: "LATEST MESSAGE", valueLabel: latestValue, icon: "clock.fill")
        ]
        tiles.forEach(card.addSubview)

        statusLabel.text = "Reading Messages database…"
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.62)
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        card.addSubview(statusLabel)

        configureButton(refreshButton, title: "Refresh", background: UIColor(red: 0.15, green: 0.58, blue: 0.96, alpha: 1))
        refreshButton.addTarget(self, action: #selector(refreshTapped), for: .touchUpInside)
        card.addSubview(refreshButton)

        configureButton(closeButton, title: "Close", background: UIColor.white.withAlphaComponent(0.11))
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        card.addSubview(closeButton)
        loadStats()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        card.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        card.alpha = 0
        UIView.animate(withDuration: 0.32,
                       delay: 0,
                       usingSpringWithDamping: 0.78,
                       initialSpringVelocity: 0) {
            self.card.transform = .identity
            self.card.alpha = 1
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = min(view.bounds.width - 28, 420)
        let height = min(CGFloat(550), view.bounds.height - view.safeAreaInsets.top - view.safeAreaInsets.bottom - 24)
        card.frame = CGRect(x: (view.bounds.width - width) / 2,
                            y: max(view.safeAreaInsets.top + 12, (view.bounds.height - height) / 2),
                            width: width,
                            height: height)
        strip.frame = CGRect(x: 24, y: 18, width: width - 48, height: 6)
        titleLabel.frame = CGRect(x: 24, y: 40, width: width - 48, height: 36)
        subtitleLabel.frame = CGRect(x: 24, y: 76, width: width - 48, height: 22)
        let gap: CGFloat = 12
        let tileWidth = (width - 48 - gap) / 2
        let tileHeight: CGFloat = 118
        tiles[0].frame = CGRect(x: 24, y: 116, width: tileWidth, height: tileHeight)
        tiles[1].frame = CGRect(x: 24 + tileWidth + gap, y: 116, width: tileWidth, height: tileHeight)
        tiles[2].frame = CGRect(x: 24, y: 246, width: tileWidth, height: tileHeight)
        tiles[3].frame = CGRect(x: 24 + tileWidth + gap, y: 246, width: tileWidth, height: tileHeight)
        statusLabel.frame = CGRect(x: 24, y: 378, width: width - 48, height: 42)
        refreshButton.frame = CGRect(x: 24, y: height - 108, width: width - 48, height: 50)
        closeButton.frame = CGRect(x: 24, y: height - 52, width: width - 48, height: 42)
    }

    private func makeTile(title: String, valueLabel: UILabel, icon: String) -> UIView {
        let tile = UIView()
        tile.backgroundColor = UIColor.white.withAlphaComponent(0.075)
        tile.layer.cornerRadius = 20
        tile.layer.cornerCurve = .continuous
        tile.layer.borderWidth = 0.8
        tile.layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = UIColor(red: 0.30, green: 0.86, blue: 0.79, alpha: 1)
        iconView.frame = CGRect(x: 14, y: 14, width: 24, height: 24)
        tile.addSubview(iconView)

        let heading = UILabel(frame: CGRect(x: 46, y: 12, width: 100, height: 28))
        heading.text = title
        heading.textColor = UIColor.white.withAlphaComponent(0.58)
        heading.font = .systemFont(ofSize: 10, weight: .bold)
        heading.adjustsFontSizeToFitWidth = true
        heading.minimumScaleFactor = 0.70
        tile.addSubview(heading)

        valueLabel.frame = CGRect(x: 14, y: 48, width: 150, height: 56)
        valueLabel.text = "—"
        valueLabel.textColor = .white
        valueLabel.font = .systemFont(ofSize: 22, weight: .bold)
        valueLabel.numberOfLines = 2
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.58
        tile.addSubview(valueLabel)
        return tile
    }

    private func configureButton(_ button: UIButton, title: String, background: UIColor) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        button.backgroundColor = background
        button.layer.cornerRadius = 16
        button.layer.cornerCurve = .continuous
    }

    @objc private func refreshTapped() { loadStats() }
    @objc private func closeTapped() { dismiss(animated: true) }

    private func loadStats() {
        refreshButton.isEnabled = false
        refreshButton.alpha = 0.55
        statusLabel.text = "Reading Messages database…"
        DispatchQueue.global(qos: .userInitiated).async {
            let stats = NMV16Database.readAppStats()
            DispatchQueue.main.async { self.apply(stats) }
        }
    }

    private func apply(_ stats: NMV16AppStats) {
        conversationsValue.text = NumberFormatter.localizedString(from: NSNumber(value: stats.conversations), number: .decimal)
        messagesValue.text = NumberFormatter.localizedString(from: NSNumber(value: stats.messages), number: .decimal)
        firstValue.text = formatted(stats.firstMessage)
        latestValue.text = formatted(stats.latestMessage)
        if let error = stats.error {
            statusLabel.text = error
            statusLabel.textColor = UIColor(red: 1.0, green: 0.48, blue: 0.52, alpha: 1)
        } else {
            statusLabel.text = "Counts exclude deleted messages and reaction records"
            statusLabel.textColor = UIColor.white.withAlphaComponent(0.62)
        }
        refreshButton.isEnabled = true
        refreshButton.alpha = 1
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "Not available" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private enum NMV16Database {
    static func readAppStats() -> NMV16AppStats {
        var result = NMV16AppStats()
        guard let database = openDatabase() else {
            result.error = "Unable to open the Messages database."
            return result
        }
        defer { sqlite3_close(database) }

        let columns = tableColumns(database, table: "message")
        var conditions = ["m.date > 0"]
        if columns.contains("is_deleted") { conditions.append("IFNULL(m.is_deleted,0)=0") }
        if columns.contains("associated_message_type") { conditions.append("IFNULL(m.associated_message_type,0)=0") }
        let filter = conditions.joined(separator: " AND ")
        let sql = """
        SELECT COUNT(DISTINCT cmj.chat_id),
               COUNT(DISTINCT cmj.message_id),
               MIN(m.date), MAX(m.date)
        FROM chat_message_join cmj
        JOIN message m ON m.ROWID = cmj.message_id
        WHERE \(filter);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            result.error = "Messages database schema could not be read."
            return result
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            result.error = "No linked Messages data was returned."
            return result
        }

        result.conversations = Int(sqlite3_column_int64(statement, 0))
        result.messages = Int(sqlite3_column_int64(statement, 1))
        result.firstMessage = appleDate(sqlite3_column_double(statement, 2))
        result.latestMessage = appleDate(sqlite3_column_double(statement, 3))
        return result
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

    private static func tableColumns(_ database: OpaquePointer, table: String) -> Set<String> {
        var values = Set<String>()
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(\(table));", -1, &statement, nil) == SQLITE_OK,
              let statement else { return values }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if let pointer = sqlite3_column_text(statement, 1) {
                values.insert(String(cString: pointer))
            }
        }
        return values
    }

    private static func appleDate(_ rawValue: Double) -> Date? {
        guard rawValue > 0 else { return nil }
        var seconds = rawValue
        if seconds > 10_000_000_000 { seconds /= 1_000_000_000 }
        return Date(timeIntervalSince1970: seconds + 978_307_200)
    }
}

private final class NMV16Runtime {
    static let shared = NMV16Runtime()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        Unmanaged.passUnretained(self).toOpaque(),
                                        nmV16PreferenceChanged,
                                        nmV16Changed as CFString,
                                        nil,
                                        .deliverImmediately)
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            self?.refreshAllWindows()
        }
        DispatchQueue.main.async {
            self.refreshAllWindows()
            NMConversationRuntime.shared.refreshAllTables()
        }
    }

    func refresh(controller: UIViewController) {
        attach(to: controller.viewIfLoaded?.window)
        if let view = controller.viewIfLoaded { registerTables(in: view) }
    }

    func refreshAllWindows() {
        guard Bundle.main.bundleIdentifier == "com.apple.MobileSMS" else { return }
        for scene in UIApplication.shared.connectedScenes {
            guard let scene = scene as? UIWindowScene else { continue }
            scene.windows.forEach { attach(to: $0) }
        }
        UIApplication.shared.windows.forEach { attach(to: $0) }
        NMConversationRuntime.shared.refreshAllTables()
    }

    private func registerTables(in view: UIView) {
        if let table = view as? UITableView { NMConversationRuntime.shared.register(tableView: table) }
        view.subviews.forEach(registerTables)
    }

    private func attach(to window: UIWindow?) {
        guard let window, !window.isHidden else { return }
        let enabled = boolValue("enabled", fallback: true)
        let showButton = boolValue("floatingInfoButton", fallback: true)
        if !enabled || !showButton {
            window.viewWithTag(nmV16ButtonTag)?.removeFromSuperview()
            return
        }
        if let existing = window.viewWithTag(nmV16ButtonTag) as? NMV16FloatingButton {
            window.bringSubviewToFront(existing)
            return
        }

        let size: CGFloat = 60
        let safe = window.safeAreaInsets
        let button = NMV16FloatingButton(frame: CGRect(x: window.bounds.width - safe.right - size - 16,
                                                       y: window.bounds.height - safe.bottom - size - 90,
                                                       width: size,
                                                       height: size))
        button.tag = nmV16ButtonTag
        button.autoresizingMask = [.flexibleLeftMargin, .flexibleTopMargin]
        button.tapHandler = { [weak self, weak window] in self?.presentCard(from: window) }
        window.addSubview(button)
        window.bringSubviewToFront(button)
    }

    private func presentCard(from window: UIWindow?) {
        if boolValue("haptics", fallback: true) { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        guard let root = window?.rootViewController else { return }
        let presenter = topController(root)
        guard !(presenter is NMV16AppCardController) else { return }
        let controller = NMV16AppCardController()
        controller.modalPresentationStyle = .overFullScreen
        controller.modalTransitionStyle = .crossDissolve
        presenter.present(controller, animated: true)
    }

    private func topController(_ controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController { return topController(presented) }
        if let navigation = controller as? UINavigationController, let visible = navigation.visibleViewController { return topController(visible) }
        if let tab = controller as? UITabBarController, let selected = tab.selectedViewController { return topController(selected) }
        return controller
    }

    private func preferenceObject(_ key: String) -> Any? {
        if let value = CFPreferencesCopyValue(key as CFString,
                                              nmV16Domain as CFString,
                                              kCFPreferencesCurrentUser,
                                              kCFPreferencesAnyHost) { return value }
        let paths = [
            "/var/mobile/Library/Preferences/\(nmV16Domain).plist",
            "/private/var/mobile/Library/Preferences/\(nmV16Domain).plist",
            "/var/jb/var/mobile/Library/Preferences/\(nmV16Domain).plist",
            "/bootstrap/var/mobile/Library/Preferences/\(nmV16Domain).plist"
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

private func nmV16PreferenceChanged(center: CFNotificationCenter?,
                                    observer: UnsafeMutableRawPointer?,
                                    name: CFNotificationName?,
                                    object: UnsafeRawPointer?,
                                    userInfo: CFDictionary?) {
    DispatchQueue.main.async { NMV16Runtime.shared.refreshAllWindows() }
}

@_cdecl("NMStartSwiftRuntimeV16")
public func NMStartSwiftRuntimeV16() {
    guard Bundle.main.bundleIdentifier == "com.apple.MobileSMS" else { return }
    NMV16Runtime.shared.start()
}

@_cdecl("NMRefreshSwiftControllerV16")
public func NMRefreshSwiftControllerV16(_ pointer: UnsafeMutableRawPointer?) {
    guard Bundle.main.bundleIdentifier == "com.apple.MobileSMS", let pointer else { return }
    let controller = Unmanaged<UIViewController>.fromOpaque(pointer).takeUnretainedValue()
    NMV16Runtime.shared.refresh(controller: controller)
}
