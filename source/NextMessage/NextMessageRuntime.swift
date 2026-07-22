import Foundation
import UIKit
import ObjectiveC.runtime
import SQLite3

private let nmDomain = "com.nextsolution.nextmessage"
private let nmChangedNotification = "com.nextsolution.nextmessage/preferences.changed"
private let nmBackgroundTag = 741400
private let nmCardTag = 741401
private let nmAccentTag = 741402
private var nmListTableKey: UInt8 = 0
private let nmSwipeSelector = NSSelectorFromString("tableView:trailingSwipeActionsConfigurationForRowAtIndexPath:")
private let nmSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private typealias NMSwipeFunction = @convention(c) (AnyObject, Selector, UITableView, IndexPath) -> UISwipeActionsConfiguration?
private typealias NMCommitFunction = @convention(c) (AnyObject, Selector, UITableView, Int, IndexPath) -> Void
private typealias NMIndexFunction = @convention(c) (AnyObject, Selector, IndexPath) -> Void

private final class NMGradientView: UIView {
    private let gradient = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        gradient.colors = [
            UIColor(red: 0.018, green: 0.035, blue: 0.082, alpha: 1).cgColor,
            UIColor(red: 0.055, green: 0.052, blue: 0.145, alpha: 1).cgColor,
            UIColor(red: 0.018, green: 0.112, blue: 0.145, alpha: 1).cgColor
        ]
        gradient.locations = [0, 0.58, 1]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(gradient)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }
}

private struct NMConversationStats {
    var count: Int?
    var firstDate: Date?
    var identifier: String?
}

private final class NMDetailsController: UIViewController {
    var titleText = "Conversation"
    var identifierText = "Messages conversation"
    var countText = "Not available"
    var dateText = "Not available"
    var deleteHandler: (() -> Void)?
    var allowDelete = true

    private let card = UIView()
    private let titleLabel = UILabel()
    private let identifierLabel = UILabel()
    private let countLabel = UILabel()
    private let dateLabel = UILabel()
    private let deleteButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let strip = CAGradientLayer()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.72)

        card.backgroundColor = UIColor(red: 0.055, green: 0.086, blue: 0.165, alpha: 0.99)
        card.layer.cornerRadius = 30
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.5
        card.layer.shadowRadius = 28
        card.layer.shadowOffset = CGSize(width: 0, height: 14)
        view.addSubview(card)

        strip.colors = [
            UIColor(red: 1.0, green: 0.34, blue: 0.38, alpha: 1).cgColor,
            UIColor(red: 0.43, green: 0.38, blue: 1.0, alpha: 1).cgColor,
            UIColor(red: 0.05, green: 0.79, blue: 0.72, alpha: 1).cgColor
        ]
        strip.startPoint = CGPoint(x: 0, y: 0.5)
        strip.endPoint = CGPoint(x: 1, y: 0.5)
        strip.cornerRadius = 3
        card.layer.addSublayer(strip)

        configure(label: titleLabel, font: .systemFont(ofSize: 27, weight: .bold), color: .white)
        configure(label: identifierLabel, font: .systemFont(ofSize: 14, weight: .medium), color: UIColor.white.withAlphaComponent(0.68))
        configure(label: countLabel, font: .systemFont(ofSize: 18, weight: .semibold), color: .white)
        configure(label: dateLabel, font: .systemFont(ofSize: 18, weight: .semibold), color: .white)
        titleLabel.text = titleText
        identifierLabel.text = identifierText
        countLabel.text = "Messages\n\(countText)"
        dateLabel.text = "First message\n\(dateText)"

        [titleLabel, identifierLabel, countLabel, dateLabel].forEach(card.addSubview)

        deleteButton.setTitle("Delete Conversation", for: .normal)
        deleteButton.setTitleColor(.white, for: .normal)
        deleteButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        deleteButton.backgroundColor = UIColor(red: 0.91, green: 0.22, blue: 0.34, alpha: 1)
        deleteButton.layer.cornerRadius = 17
        deleteButton.layer.cornerCurve = .continuous
        deleteButton.isHidden = !allowDelete
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        card.addSubview(deleteButton)

        closeButton.setTitle("Close", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        closeButton.backgroundColor = UIColor.white.withAlphaComponent(0.11)
        closeButton.layer.cornerRadius = 17
        closeButton.layer.cornerCurve = .continuous
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        card.addSubview(closeButton)
    }

    private func configure(label: UILabel, font: UIFont, color: UIColor) {
        label.font = font
        label.textColor = color
        label.numberOfLines = 0
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        card.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        card.alpha = 0
        UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0) {
            self.card.transform = .identity
            self.card.alpha = 1
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = min(view.bounds.width - 34, 410)
        let height: CGFloat = allowDelete ? 438 : 370
        card.frame = CGRect(x: (view.bounds.width - width) / 2,
                            y: (view.bounds.height - height) / 2,
                            width: width,
                            height: height)
        strip.frame = CGRect(x: 24, y: 20, width: width - 48, height: 6)
        titleLabel.frame = CGRect(x: 24, y: 46, width: width - 48, height: 70)
        identifierLabel.frame = CGRect(x: 24, y: 112, width: width - 48, height: 42)
        countLabel.frame = CGRect(x: 24, y: 170, width: width - 48, height: 70)
        dateLabel.frame = CGRect(x: 24, y: 250, width: width - 48, height: 74)
        if allowDelete {
            deleteButton.frame = CGRect(x: 24, y: height - 108, width: width - 48, height: 52)
            closeButton.frame = CGRect(x: 24, y: height - 50, width: width - 48, height: 42)
        } else {
            closeButton.frame = CGRect(x: 24, y: height - 72, width: width - 48, height: 48)
        }
    }

    @objc private func deleteTapped() {
        let alert = UIAlertController(title: "Delete Conversation?",
                                      message: "This permanently removes the conversation from Messages.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            self.deleteHandler?()
            self.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}

private final class NMRuntime {
    static let shared = NMRuntime()

    private var enabled = true
    private var cardsEnabled = true
    private var glassEnabled = true
    private var detailsEnabled = true
    private var showCount = true
    private var showFirstDate = true
    private var deleteFromCard = true
    private var haptics = true
    private var animations = true
    private var cardOpacity: CGFloat = 0.96
    private var cornerRadius: CGFloat = 20
    private var started = false
    private var originalSwipeIMPs: [String: IMP] = [:]
    private var swizzledClasses = Set<String>()
    private let lock = NSLock()

    func start() {
        guard !started else { return }
        started = true
        reloadPreferences()
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        Unmanaged.passUnretained(self).toOpaque(),
                                        nmPreferenceCallback,
                                        nmChangedNotification as CFString,
                                        nil,
                                        .deliverImmediately)
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            self?.refreshAllWindows()
        }
        DispatchQueue.main.async { self.refreshAllWindows() }
    }

    func refresh(controller: UIViewController) {
        guard Bundle.main.bundleIdentifier == "com.apple.MobileSMS" else { return }
        reloadPreferences()
        if enabled {
            applyTheme(to: controller)
            for table in allTableViews(in: controller.view) where isConversationList(table, controller: controller) {
                objc_setAssociatedObject(table, &nmListTableKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                styleConversationList(table)
                installSwipeOverride(for: table)
            }
        } else {
            restore(controller: controller)
        }
    }

    private func reloadPreferences() {
        enabled = boolValue("enabled", fallback: true)
        cardsEnabled = boolValue("conversationCards", fallback: true)
        glassEnabled = boolValue("glassBackground", fallback: true)
        detailsEnabled = boolValue("detailsSwipe", fallback: true)
        showCount = boolValue("showMessageCount", fallback: true)
        showFirstDate = boolValue("showFirstDate", fallback: true)
        deleteFromCard = boolValue("deleteFromCard", fallback: true)
        haptics = boolValue("haptics", fallback: true)
        animations = boolValue("animations", fallback: true)
        cardOpacity = max(0.70, min(1.0, CGFloat(doubleValue("cardOpacity", fallback: 0.96))))
        cornerRadius = max(14, min(30, CGFloat(doubleValue("cornerRadius", fallback: 20))))
    }

    private func preferenceObject(_ key: String) -> Any? {
        if let value = CFPreferencesCopyValue(key as CFString,
                                              nmDomain as CFString,
                                              kCFPreferencesCurrentUser,
                                              kCFPreferencesAnyHost) {
            return value
        }
        if let value = UserDefaults(suiteName: nmDomain)?.object(forKey: key) {
            return value
        }
        let paths = [
            "/var/mobile/Library/Preferences/\(nmDomain).plist",
            "/private/var/mobile/Library/Preferences/\(nmDomain).plist",
            "/var/jb/var/mobile/Library/Preferences/\(nmDomain).plist"
        ]
        for path in paths {
            if let dict = NSDictionary(contentsOfFile: path), let value = dict[key] {
                return value
            }
        }
        return nil
    }

    private func boolValue(_ key: String, fallback: Bool) -> Bool {
        (preferenceObject(key) as? NSNumber)?.boolValue ?? fallback
    }

    private func doubleValue(_ key: String, fallback: Double) -> Double {
        (preferenceObject(key) as? NSNumber)?.doubleValue ?? fallback
    }

    private func refreshAllWindows() {
        reloadPreferences()
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                if enabled {
                    window.overrideUserInterfaceStyle = .dark
                } else {
                    window.overrideUserInterfaceStyle = .unspecified
                }
                if let root = window.rootViewController {
                    refreshTree(root)
                }
            }
        }
    }

    private func refreshTree(_ controller: UIViewController) {
        refresh(controller: controller)
        controller.children.forEach(refreshTree)
        if let presented = controller.presentedViewController {
            refreshTree(presented)
        }
    }

    private func applyTheme(to controller: UIViewController) {
        let className = NSStringFromClass(type(of: controller))
        let title = controller.title ?? controller.navigationItem.title ?? ""
        let relevant = className.localizedCaseInsensitiveContains("Conversation") ||
                       className.localizedCaseInsensitiveContains("Messages") ||
                       title == "Messages"
        guard relevant else { return }

        controller.view.window?.overrideUserInterfaceStyle = .dark
        if glassEnabled {
            var background = controller.view.viewWithTag(nmBackgroundTag)
            if background == nil {
                let gradient = NMGradientView(frame: controller.view.bounds)
                gradient.tag = nmBackgroundTag
                gradient.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                controller.view.insertSubview(gradient, at: 0)
                background = gradient
            }
            background?.frame = controller.view.bounds
        }

        if let bar = controller.navigationController?.navigationBar {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = UIColor(red: 0.025, green: 0.058, blue: 0.13, alpha: 0.92)
            appearance.titleTextAttributes = [.foregroundColor: UIColor.white,
                                              .font: UIFont.systemFont(ofSize: 17, weight: .bold)]
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white,
                                                   .font: UIFont.systemFont(ofSize: 34, weight: .bold)]
            bar.standardAppearance = appearance
            bar.scrollEdgeAppearance = appearance
            bar.compactAppearance = appearance
            bar.tintColor = UIColor(red: 0.34, green: 0.88, blue: 0.79, alpha: 1)
        }
    }

    private func restore(controller: UIViewController) {
        controller.view.window?.overrideUserInterfaceStyle = .unspecified
        removeTaggedViews(from: controller.view)
        for table in allTableViews(in: controller.view) {
            table.backgroundColor = .systemBackground
            table.separatorStyle = .singleLine
            objc_setAssociatedObject(table, &nmListTableKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            for cell in table.visibleCells {
                restore(cell: cell)
            }
        }
        if let bar = controller.navigationController?.navigationBar {
            let stock = UINavigationBarAppearance()
            stock.configureWithDefaultBackground()
            bar.standardAppearance = stock
            bar.scrollEdgeAppearance = stock
            bar.compactAppearance = stock
            bar.tintColor = nil
        }
    }

    private func removeTaggedViews(from view: UIView) {
        view.viewWithTag(nmBackgroundTag)?.removeFromSuperview()
        view.viewWithTag(nmCardTag)?.removeFromSuperview()
        view.viewWithTag(nmAccentTag)?.removeFromSuperview()
        view.subviews.forEach(removeTaggedViews)
    }

    private func allTableViews(in view: UIView) -> [UITableView] {
        var result: [UITableView] = []
        if let table = view as? UITableView { result.append(table) }
        for child in view.subviews { result.append(contentsOf: allTableViews(in: child)) }
        return result
    }

    private func isConversationList(_ table: UITableView, controller: UIViewController? = nil) -> Bool {
        let delegateName = table.delegate.map { NSStringFromClass(type(of: $0)) } ?? ""
        let dataSourceName = table.dataSource.map { NSStringFromClass(type(of: $0)) } ?? ""
        if delegateName.localizedCaseInsensitiveContains("ConversationList") ||
           dataSourceName.localizedCaseInsensitiveContains("ConversationList") {
            return true
        }
        let owner = controller ?? controllerForView(table)
        let ownerTitle = owner?.title ?? owner?.navigationItem.title ?? ""
        guard ownerTitle == "Messages" else { return false }
        let cells = table.visibleCells
        guard !cells.isEmpty else { return false }
        return cells.contains { cell in
            let name = NSStringFromClass(type(of: cell))
            return name.localizedCaseInsensitiveContains("Conversation") || labelTexts(in: cell.contentView).count >= 2
        }
    }

    private func controllerForView(_ view: UIView) -> UIViewController? {
        var responder: UIResponder? = view
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }

    private func styleConversationList(_ table: UITableView) {
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.clipsToBounds = false
        for cell in table.visibleCells { style(cell: cell) }
    }

    private func style(cell: UITableViewCell) {
        guard cardsEnabled else {
            restore(cell: cell)
            return
        }
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
        let card: UIView
        if let existing = cell.contentView.viewWithTag(nmCardTag) {
            card = existing
        } else {
            card = UIView()
            card.tag = nmCardTag
            card.isUserInteractionEnabled = false
            card.layer.borderWidth = 0.8
            card.layer.shadowColor = UIColor.black.cgColor
            card.layer.shadowOpacity = 0.24
            card.layer.shadowRadius = 11
            card.layer.shadowOffset = CGSize(width: 0, height: 5)
            cell.contentView.insertSubview(card, at: 0)

            let accent = UIView()
            accent.tag = nmAccentTag
            accent.isUserInteractionEnabled = false
            accent.backgroundColor = UIColor(red: 0.33, green: 0.84, blue: 0.77, alpha: 0.9)
            card.addSubview(accent)
        }
        card.frame = cell.contentView.bounds.insetBy(dx: 8, dy: 4)
        card.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        card.backgroundColor = UIColor(red: 0.065, green: 0.102, blue: 0.19, alpha: cardOpacity)
        card.layer.cornerRadius = cornerRadius
        card.layer.cornerCurve = .continuous
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.13).cgColor
        card.clipsToBounds = false
        if let accent = card.viewWithTag(nmAccentTag) {
            accent.frame = CGRect(x: 0, y: 11, width: 4, height: max(18, card.bounds.height - 22))
            accent.layer.cornerRadius = 2
        }
        if animations, card.alpha < 1 {
            UIView.animate(withDuration: 0.2) { card.alpha = 1 }
        } else {
            card.alpha = 1
        }
    }

    private func restore(cell: UITableViewCell) {
        cell.contentView.viewWithTag(nmCardTag)?.removeFromSuperview()
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
    }

    private func installSwipeOverride(for table: UITableView) {
        guard let delegate = table.delegate else { return }
        let delegateClass: AnyClass = type(of: delegate)
        let className = NSStringFromClass(delegateClass)

        lock.lock()
        if swizzledClasses.contains(className) {
            lock.unlock()
            return
        }
        swizzledClasses.insert(className)
        let method = class_getInstanceMethod(delegateClass, nmSwipeSelector)
        if let method {
            originalSwipeIMPs[className] = method_getImplementation(method)
        }
        lock.unlock()

        let block: @convention(block) (AnyObject, UITableView, IndexPath) -> UISwipeActionsConfiguration? = { [weak self] object, tableView, indexPath in
            guard let self else { return nil }
            let original = self.callOriginalSwipe(object: object,
                                                   className: className,
                                                   table: tableView,
                                                   indexPath: indexPath)
            guard self.enabled,
                  self.detailsEnabled,
                  self.isConversationList(tableView) else {
                return original
            }
            return self.customSwipeConfiguration(table: tableView,
                                                 indexPath: indexPath,
                                                 original: original)
        }
        let replacement = imp_implementationWithBlock(block)
        if let method {
            method_setImplementation(method, replacement)
        } else {
            "@@:@@".withCString { types in
                class_addMethod(delegateClass, nmSwipeSelector, replacement, types)
            }
        }
    }

    private func callOriginalSwipe(object: AnyObject,
                                   className: String,
                                   table: UITableView,
                                   indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        lock.lock()
        let imp = originalSwipeIMPs[className]
        lock.unlock()
        guard let imp else { return nil }
        let function = unsafeBitCast(imp, to: NMSwipeFunction.self)
        return function(object, nmSwipeSelector, table, indexPath)
    }

    private func customSwipeConfiguration(table: UITableView,
                                          indexPath: IndexPath,
                                          original: UISwipeActionsConfiguration?) -> UISwipeActionsConfiguration {
        let info = UIContextualAction(style: .normal, title: "Info") { [weak self, weak table] _, _, completion in
            guard let self, let table else {
                completion(false)
                return
            }
            self.presentDetails(table: table, indexPath: indexPath)
            completion(true)
        }
        info.backgroundColor = UIColor(red: 0.43, green: 0.38, blue: 1.0, alpha: 1)
        info.image = UIImage(systemName: "info.circle.fill")

        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self, weak table] _, _, completion in
            guard let self, let table else {
                completion(false)
                return
            }
            self.confirmDelete(table: table, indexPath: indexPath)
            completion(true)
        }
        delete.backgroundColor = UIColor(red: 0.91, green: 0.22, blue: 0.34, alpha: 1)
        delete.image = UIImage(systemName: "trash.fill")

        let retained = (original?.actions ?? []).filter {
            $0.style != .destructive && !($0.title ?? "").localizedCaseInsensitiveContains("delete")
        }
        let configuration = UISwipeActionsConfiguration(actions: [delete, info] + retained)
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    private func presentDetails(table: UITableView, indexPath: IndexPath) {
        guard let cell = table.cellForRow(at: indexPath),
              let presenter = controllerForView(table) else { return }
        let candidates = conversationCandidates(from: cell)
        let stats = queryStats(candidates: candidates)
        let details = NMDetailsController()
        details.modalPresentationStyle = .overFullScreen
        details.modalTransitionStyle = .crossDissolve
        details.titleText = candidates.first ?? "Conversation"
        details.identifierText = stats.identifier ?? candidates.dropFirst().first ?? "Messages conversation"
        details.countText = showCount ? stats.count.map(String.init) ?? "Not available" : "Hidden in Settings"
        details.dateText = showFirstDate ? readableDate(stats.firstDate) : "Hidden in Settings"
        details.allowDelete = deleteFromCard
        details.deleteHandler = { [weak self, weak table] in
            guard let self, let table else { return }
            self.performDelete(table: table, indexPath: indexPath)
        }
        feedback(warning: false)
        presenter.present(details, animated: true)
    }

    private func confirmDelete(table: UITableView, indexPath: IndexPath) {
        guard let presenter = controllerForView(table) else { return }
        let alert = UIAlertController(title: "Delete Conversation?",
                                      message: "This permanently removes the complete conversation.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self, weak table] _ in
            guard let self, let table else { return }
            self.performDelete(table: table, indexPath: indexPath)
        })
        presenter.present(alert, animated: true)
    }

    private func performDelete(table: UITableView, indexPath: IndexPath) {
        feedback(warning: true)
        let selector = NSSelectorFromString("tableView:commitEditingStyle:forRowAtIndexPath:")
        for object in [table.dataSource as AnyObject?, table.delegate as AnyObject?] {
            guard let object, object.responds(to: selector),
                  let method = class_getInstanceMethod(type(of: object), selector) else { continue }
            let function = unsafeBitCast(method_getImplementation(method), to: NMCommitFunction.self)
            function(object, selector, table, UITableViewCell.EditingStyle.delete.rawValue, indexPath)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { table.reloadData() }
            return
        }
        if let controller = controllerForView(table) {
            for name in ["_deleteConversationAtIndexPath:", "deleteConversationAtIndexPath:", "removeConversationAtIndexPath:"] {
                let privateSelector = NSSelectorFromString(name)
                guard controller.responds(to: privateSelector),
                      let method = class_getInstanceMethod(type(of: controller), privateSelector) else { continue }
                let function = unsafeBitCast(method_getImplementation(method), to: NMIndexFunction.self)
                function(controller, privateSelector, indexPath)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { table.reloadData() }
                return
            }
        }
    }

    private func feedback(warning: Bool) {
        guard haptics else { return }
        if warning {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        } else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func labelTexts(in view: UIView) -> [String] {
        var labels: [UILabel] = []
        collectLabels(in: view, result: &labels)
        labels.sort { lhs, rhs in
            if lhs.frame.minY == rhs.frame.minY { return lhs.frame.minX < rhs.frame.minX }
            return lhs.frame.minY < rhs.frame.minY
        }
        var seen = Set<String>()
        return labels.compactMap { label in
            let text = (label.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count > 1, text.count < 180, !seen.contains(text) else { return nil }
            seen.insert(text)
            return text
        }
    }

    private func collectLabels(in view: UIView, result: inout [UILabel]) {
        if let label = view as? UILabel { result.append(label) }
        for child in view.subviews { collectLabels(in: child, result: &result) }
    }

    private func conversationCandidates(from cell: UITableViewCell) -> [String] {
        labelTexts(in: cell.contentView)
    }

    private func queryStats(candidates: [String]) -> NMConversationStats {
        var database: OpaquePointer?
        let paths = ["/private/var/mobile/Library/SMS/sms.db", "/var/mobile/Library/SMS/sms.db"]
        for path in paths where database == nil {
            if sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
                if database != nil { sqlite3_close(database) }
                database = nil
            }
        }
        guard let database else { return NMConversationStats() }
        defer { sqlite3_close(database) }

        let sql = """
        SELECT COUNT(cmj.message_id), MIN(m.date), COALESCE(c.chat_identifier, c.guid, c.display_name)
        FROM chat c
        LEFT JOIN chat_message_join cmj ON cmj.chat_id = c.ROWID
        LEFT JOIN message m ON m.ROWID = cmj.message_id
        WHERE lower(c.chat_identifier)=lower(?) OR lower(c.guid)=lower(?) OR lower(c.display_name)=lower(?)
        GROUP BY c.ROWID ORDER BY MAX(m.date) DESC LIMIT 1
        """

        for candidate in candidates where candidate.count > 1 {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else { continue }
            defer { sqlite3_finalize(statement) }
            candidate.withCString { pointer in
                sqlite3_bind_text(statement, 1, pointer, -1, nmSQLiteTransient)
                sqlite3_bind_text(statement, 2, pointer, -1, nmSQLiteTransient)
                sqlite3_bind_text(statement, 3, pointer, -1, nmSQLiteTransient)
            }
            if sqlite3_step(statement) == SQLITE_ROW {
                let count = Int(sqlite3_column_int64(statement, 0))
                let rawDate = sqlite3_column_int64(statement, 1)
                let identifier: String?
                if let pointer = sqlite3_column_text(statement, 2) {
                    identifier = String(cString: pointer)
                } else {
                    identifier = nil
                }
                return NMConversationStats(count: count,
                                           firstDate: dateFromAppleValue(rawDate),
                                           identifier: identifier)
            }
        }
        return NMConversationStats()
    }

    private func dateFromAppleValue(_ value: Int64) -> Date? {
        guard value > 0 else { return nil }
        var raw = Double(value)
        if raw > 1_000_000_000_000 { raw /= 1_000_000_000 }
        if raw > 1_300_000_000 {
            return Date(timeIntervalSince1970: raw)
        }
        return Date(timeIntervalSince1970: raw + 978_307_200)
    }

    private func readableDate(_ date: Date?) -> String {
        guard let date else { return "Not available" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private let nmPreferenceCallback: CFNotificationCallback = { _, observer, _, _, _ in
    guard let observer else { return }
    let runtime = Unmanaged<NMRuntime>.fromOpaque(observer).takeUnretainedValue()
    DispatchQueue.main.async {
        runtime.refreshAllWindows()
    }
}

@_cdecl("NMStartSwiftRuntime")
public func NMStartSwiftRuntime() {
    guard Bundle.main.bundleIdentifier == "com.apple.MobileSMS" else { return }
    NMRuntime.shared.start()
}

@_cdecl("NMRefreshSwiftController")
public func NMRefreshSwiftController(_ controllerPointer: UnsafeMutableRawPointer?) {
    guard let controllerPointer else { return }
    let controller = Unmanaged<UIViewController>.fromOpaque(controllerPointer).takeUnretainedValue()
    NMRuntime.shared.refresh(controller: controller)
}
