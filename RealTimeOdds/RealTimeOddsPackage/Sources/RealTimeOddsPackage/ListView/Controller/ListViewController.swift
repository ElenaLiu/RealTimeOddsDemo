import Combine
import UIKit

public final class ListViewController: UIViewController {
    // MARK: - UI Components
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let messageLabel = UILabel()
    private let fpsLabel = UILabel()
    private let statusLabel = UILabel()
    
    // MARK: - Dependencies
    private let viewModel: ListViewViewModel
    private var disposebags = Set<AnyCancellable>()
    
    // MARK: - Data Management
    private typealias SectionID = Int
    private typealias DataSource = UITableViewDiffableDataSource<SectionID, MatchOddsItem>
    private typealias Snapshot = NSDiffableDataSourceSnapshot<SectionID, MatchOddsItem>
    private lazy var dataSource = makeDataSource()
    private var itemsByID: [Int: MatchOddsItem] = [:]
    private var hasRenderedInitialSnapshot = false
    
    // MARK: - FPS Monitoring
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var frameCount = 0

    // MARK: - Formatters
    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Initialization
    public init(viewModel: ListViewViewModel = ListViewViewModel()) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindViewModel()
        setupFPSMonitoring()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.load()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewModel.stop()
        stopFPSMonitoring()
    }

    // MARK: - UI Setup
    private func setupUI() {
        title = "Real-Time Odds"
        view.backgroundColor = .systemGroupedBackground

        configureTableView()
        setupConstraints()
        configureActivityIndicator()
        configureMessageLabel()
        configureFPSLabel()
        configureStatusLabel()
    }

    // MARK: - ViewModel Binding
    private func bindViewModel() {
        bindItems()
        bindLoadingState()
        bindErrorMessage()
        bindStreamStatus()
    }
    
    private func bindItems() {
        viewModel.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                self?.updateSnapshot(with: items)
            }
            .store(in: &disposebags)
    }
    
    private func bindLoadingState() {
        viewModel.$isLoading
            .receive(on: RunLoop.main)
            .sink { [weak self] isLoading in
                self?.updateLoadingState(isLoading)
            }
            .store(in: &disposebags)
    }
    
    private func bindErrorMessage() {
        viewModel.$errorMessage
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                self?.showMessage(message)
            }
            .store(in: &disposebags)
    }
    
    private func bindStreamStatus() {
        viewModel.$streamStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.updateStatusLabel(status)
            }
            .store(in: &disposebags)
    }

    // MARK: - Data Updates
    private func updateSnapshot(with items: [MatchOddsItem]) {
        let shouldHighlight = hasRenderedInitialSnapshot
        let previousItems = shouldHighlight ? itemsByID : [:]
        itemsByID = items.toDictionary(by: \.id)

        var snapshot = Snapshot()
        snapshot.appendSections([0])
        snapshot.appendItems(items, toSection: 0)

        dataSource.apply(snapshot, animatingDifferences: shouldHighlight) { [weak self] in
            guard let self else { return }
            if shouldHighlight {
                self.highlightChangedCells(previousItems: previousItems)
            } else {
                self.hasRenderedInitialSnapshot = true
            }
        }

        if !shouldHighlight {
            hasRenderedInitialSnapshot = true
        }
    }

    // MARK: - Data Source
    private func makeDataSource() -> DataSource {
        DataSource(tableView: tableView) { [weak self] tableView, indexPath, item in
            guard let self = self,
                  let cell = tableView.dequeueReusableCell(
                    withIdentifier: MatchOddsCell.reuseIdentifier,
                    for: indexPath
                  ) as? MatchOddsCell else {
                return UITableViewCell()
            }

            cell.configure(with: item, dateFormatter: self.dateFormatter)
            return cell
        }
    }

    // MARK: - UI Configuration
    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.separatorStyle = .singleLine
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.register(MatchOddsCell.self, forCellReuseIdentifier: MatchOddsCell.reuseIdentifier)
        tableView.dataSource = dataSource
        tableView.refreshControl = createRefreshControl()
        tableView.backgroundColor = .clear
    }
    
    private func setupConstraints() {
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureActivityIndicator() {
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func configureMessageLabel() {
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .systemRed
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.isHidden = true
        view.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            messageLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    // MARK: - State Management
    private func updateLoadingState(_ isLoading: Bool) {
        let shouldShowIndicator = isLoading && 
                                  dataSource.snapshot().itemIdentifiers.isEmpty && 
                                  !(tableView.refreshControl?.isRefreshing ?? false)

        if shouldShowIndicator {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }

        if !isLoading {
            tableView.refreshControl?.endRefreshing()
        }
    }

    private func showMessage(_ message: String?) {
        messageLabel.text = message
        messageLabel.isHidden = (message == nil)
    }

    private func createRefreshControl() -> UIRefreshControl {
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        return refreshControl
    }

    @objc private func handleRefresh() {
        viewModel.refresh()
    }

    // MARK: - Cell Animation
    private func highlightChangedCells(previousItems: [Int: MatchOddsItem]) {
        guard !previousItems.isEmpty else { return }
        
        for cell in tableView.visibleCells {
            guard let indexPath = tableView.indexPath(for: cell),
                  let currentItem = dataSource.itemIdentifier(for: indexPath),
                  let matchCell = cell as? MatchOddsCell else { continue }

            let previousItem = previousItems[currentItem.id]
            matchCell.applyOddsChange(previous: previousItem, current: currentItem)
        }
    }
    
    private func configureStatusLabel() {
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .systemBlue
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        statusLabel.textAlignment = .center
        statusLabel.layer.cornerRadius = 4
        statusLabel.layer.masksToBounds = true
        statusLabel.text = "Unknown"
        view.addSubview(statusLabel)
        
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            statusLabel.widthAnchor.constraint(equalToConstant: 100),
            statusLabel.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    private func updateStatusLabel(_ status: String) {
        statusLabel.text = "\(status)"
        switch status {
        case "Connected":
            statusLabel.textColor = .systemGreen
        case "Connecting", "Reconnecting":
            statusLabel.textColor = .systemYellow
        case "Stopped":
            statusLabel.textColor = .systemRed
        default:
            statusLabel.textColor = .systemBlue
        }
    }

    // MARK: - FPS Monitoring
    private func configureFPSLabel() {
        fpsLabel.translatesAutoresizingMaskIntoConstraints = false
        fpsLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        fpsLabel.textColor = .systemGreen
        fpsLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        fpsLabel.textAlignment = .center
        fpsLabel.layer.cornerRadius = 4
        fpsLabel.layer.masksToBounds = true
        fpsLabel.text = "FPS: --"
        fpsLabel.isHidden = true
        view.addSubview(fpsLabel)
        
        NSLayoutConstraint.activate([
            fpsLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            fpsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            fpsLabel.widthAnchor.constraint(equalToConstant: 60),
            fpsLabel.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    private func setupFPSMonitoring() {
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkTick))
        displayLink?.add(to: .main, forMode: .common)
        fpsLabel.isHidden = false
    }
    
    private func stopFPSMonitoring() {
        displayLink?.invalidate()
        displayLink = nil
        fpsLabel.isHidden = true
    }
    
    @objc private func displayLinkTick(_ displayLink: CADisplayLink) {
        frameCount += 1
        
        if lastTimestamp == 0 {
            lastTimestamp = displayLink.timestamp
            return
        }
        
        let elapsed = displayLink.timestamp - lastTimestamp
        if elapsed >= 1.0 {
            let fps = Double(frameCount) / elapsed
            fpsLabel.text = String(format: "FPS: %.0f", fps)
            
            if fps >= 55 {
                fpsLabel.textColor = .systemGreen
            } else if fps >= 45 {
                fpsLabel.textColor = .systemYellow
            } else {
                fpsLabel.textColor = .systemRed
            }
            
            frameCount = 0
            lastTimestamp = displayLink.timestamp
        }
    }
}
