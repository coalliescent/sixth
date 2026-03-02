#if !TESTING
import AppKit

class StationListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let closeButton = NSButton()
    private let refreshButton = NSButton()
    private let sortControl = NSSegmentedControl(labels: ["Recent", "Added", "A–Z"], trackingMode: .selectOne, target: nil, action: nil)
    private let emptyLabel = NSTextField(labelWithString: "No stations found")
    private let loadingSpinner = NSProgressIndicator()
    private var stations: [Station] = []       // current display order
    private var recentOrder: [Station] = []    // original API order

    var currentStationToken: String?
    var onStationSelected: ((Station) -> Void)?
    var onClose: (() -> Void)?
    var onRefresh: (() -> Void)?

    override func loadView() {
        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 360, height: 460))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        self.view = effect
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        // Refresh button (upper left)
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
        refreshButton.isBordered = false
        refreshButton.contentTintColor = .lightGray
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.target = self
        refreshButton.action = #selector(refreshTapped)
        view.addSubview(refreshButton)

        // Sort segmented control
        sortControl.selectedSegment = 0
        sortControl.controlSize = .small
        sortControl.translatesAutoresizingMaskIntoConstraints = false
        sortControl.target = self
        sortControl.action = #selector(sortChanged)
        view.addSubview(sortControl)

        // Table view
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("StationColumn"))
        column.width = 340
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.rowHeight = 44
        tableView.style = .plain
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        // Close button (floats above table, added after scrollView for z-order)
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeButton.isBordered = false
        closeButton.contentTintColor = .lightGray
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.wantsLayer = true
        closeButton.shadow = NSShadow()
        closeButton.layer?.shadowColor = NSColor.black.cgColor
        closeButton.layer?.shadowOpacity = 0.6
        closeButton.layer?.shadowOffset = CGSize(width: 0, height: -1)
        closeButton.layer?.shadowRadius = 3
        view.addSubview(closeButton)

        // Loading spinner (visible by default until stations arrive)
        loadingSpinner.style = .spinning
        loadingSpinner.controlSize = .small
        loadingSpinner.translatesAutoresizingMaskIntoConstraints = false
        loadingSpinner.startAnimation(nil)
        view.addSubview(loadingSpinner)

        NSLayoutConstraint.activate([
            refreshButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            refreshButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            refreshButton.widthAnchor.constraint(equalToConstant: 20),
            refreshButton.heightAnchor.constraint(equalToConstant: 20),

            closeButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 94),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),

            sortControl.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            sortControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            scrollView.topAnchor.constraint(equalTo: sortControl.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingSpinner.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            loadingSpinner.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])
    }

    func showLoading() {
        stations = []
        recentOrder = []
        tableView.reloadData()
        emptyLabel.isHidden = true
        loadingSpinner.isHidden = false
        loadingSpinner.startAnimation(nil)
    }

    func update(stations: [Station]) {
        loadingSpinner.stopAnimation(nil)
        loadingSpinner.isHidden = true
        self.recentOrder = stations.filter { $0.isQuickMix != true }
        applySortOrder()
    }

    private func applySortOrder() {
        switch sortControl.selectedSegment {
        case 0:
            // Recent (most recently played first)
            let playedTokens = UserDefaults.standard.stringArray(forKey: "recentlyPlayedStations") ?? []
            let tokenOrder = Dictionary(uniqueKeysWithValues: playedTokens.enumerated().map { ($1, $0) })
            stations = recentOrder.sorted { a, b in
                let ai = tokenOrder[a.stationToken]
                let bi = tokenOrder[b.stationToken]
                switch (ai, bi) {
                case (.some(let x), .some(let y)): return x < y
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return false
                }
            }
        case 2:
            // A-Z
            stations = recentOrder.sorted { $0.stationName.localizedCaseInsensitiveCompare($1.stationName) == .orderedAscending }
        default:
            // Added (API order)
            stations = recentOrder
        }
        tableView.reloadData()
        emptyLabel.isHidden = !stations.isEmpty
    }

    @objc private func sortChanged() {
        applySortOrder()
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return stations.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let station = stations[row]
        let isCurrent = station.stationToken == currentStationToken

        let cell = NSTextField(labelWithString: station.stationName)
        cell.font = .systemFont(ofSize: 13)
        cell.textColor = isCurrent ? .systemCyan : .white
        cell.lineBreakMode = .byTruncatingTail

        let container = NSView()
        container.wantsLayer = true
        cell.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(cell)

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "radio", accessibilityDescription: nil)
        icon.contentTintColor = .lightGray
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 4
        icon.layer?.masksToBounds = true
        icon.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(icon)

        if let artUrlStr = station.artUrl {
            ImageCache.shared.image(for: artUrlStr) { loadedImage in
                guard let loadedImage = loadedImage else { return }
                icon.image = loadedImage
                icon.contentTintColor = nil
            }
        }

        if isCurrent {
            cell.textColor = .systemCyan
        }

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32),

            cell.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            cell.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            cell.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = NSTableRowView()
        rowView.isEmphasized = false
        return rowView
    }

    // MARK: - Actions

    @objc private func rowDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0 && row < stations.count else { return }
        onStationSelected?(stations[row])
    }

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func refreshTapped() {
        onRefresh?()
    }
}
#endif
