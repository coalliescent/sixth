#if !TESTING
import AppKit

class StationListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let backButton = NSButton()
    private let sortControl = NSSegmentedControl(labels: ["Recent", "Added", "A–Z"], trackingMode: .selectOne, target: nil, action: nil)
    private let emptyLabel = NSTextField(labelWithString: "No stations found")
    private var stations: [Station] = []       // current display order
    private var recentOrder: [Station] = []    // original API order

    var currentStationToken: String?
    var onStationSelected: ((Station) -> Void)?
    var onBack: (() -> Void)?

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 300))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.15, alpha: 1).cgColor
        self.view = container
        self.preferredContentSize = NSSize(width: 360, height: 300)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        // Header
        let headerLabel = NSTextField(labelWithString: "Stations")
        headerLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        headerLabel.textColor = .white
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerLabel)

        backButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")
        backButton.isBordered = false
        backButton.contentTintColor = .white
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.target = self
        backButton.action = #selector(backTapped)
        view.addSubview(backButton)

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
        tableView.backgroundColor = NSColor(white: 0.15, alpha: 1)
        tableView.rowHeight = 44
        tableView.style = .plain
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            backButton.widthAnchor.constraint(equalToConstant: 20),
            backButton.heightAnchor.constraint(equalToConstant: 20),

            headerLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            headerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            sortControl.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 8),
            sortControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            scrollView.topAnchor.constraint(equalTo: sortControl.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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

    func update(stations: [Station]) {
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

    @objc private func backTapped() {
        onBack?()
    }
}
#endif
