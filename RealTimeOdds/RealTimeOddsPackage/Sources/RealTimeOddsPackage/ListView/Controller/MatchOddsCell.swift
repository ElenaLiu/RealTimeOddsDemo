import UIKit

public final class MatchOddsCell: UITableViewCell {
    public static let reuseIdentifier = "MatchOddsCell"

    private enum Metric {
        static let containerCornerRadius: CGFloat = 20
        static let oddsCornerRadius: CGFloat = 4
        static let containerInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        static let contentInsets = UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        static let stackSpacing: CGFloat = 12
        static let subStackSpacing: CGFloat = 16
        static let oddsStackSpacing: CGFloat = 4
        static let highlightHoldDuration: TimeInterval = 2
        static let colorFadeDuration: TimeInterval = 0.8
        static let minimumChangeThreshold: Double = 0.005 //只有賠率差異超過 0.005 才會觸發 highlight，避免太頻繁閃爍
        static let minimumResetDelay: TimeInterval = 2
    }

    private enum Palette {
        static let defaultOddsText = UIColor.systemBlue
        static let defaultOddsBackground = UIColor.clear
        static let highlightText = UIColor.white
        static let increaseBackground = UIColor.systemGreen
        static let decreaseBackground = UIColor.systemRed
    }

    private let containerView = UIView()
    private let dateLabel = UILabel()
    private let homeTeamLabel = UILabel()
    private let awayTeamLabel = UILabel()
    private let vsLabel = UILabel()
    private let homeTitleLabel = UILabel()
    private let homeOddsLabel = UILabel()
    private let awayTitleLabel = UILabel()
    private let awayOddsLabel = UILabel()

    private var homeResetWorkItem: DispatchWorkItem?
    private var awayResetWorkItem: DispatchWorkItem?
    private var homeHighlightTimestamp: Date?
    private var awayHighlightTimestamp: Date?

    private lazy var oddsFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 3
        return formatter
    }()

    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        cancelPendingResets()
        resetOddsStyles(animated: false)
    }

    func configure(with item: MatchOddsItem, dateFormatter: DateFormatter) {
        updateDateLabel(with: item.match.startTime, formatter: dateFormatter)
        homeTeamLabel.text = item.match.teamA
        awayTeamLabel.text = item.match.teamB
        homeOddsLabel.text = formatOdds(item.odds?.teamAOdds)
        awayOddsLabel.text = formatOdds(item.odds?.teamBOdds)
        resetOddsStyles(animated: false)
    }

    func applyOddsChange(previous: MatchOddsItem?, current: MatchOddsItem) {
        homeOddsLabel.text = formatOdds(current.odds?.teamAOdds)
        awayOddsLabel.text = formatOdds(current.odds?.teamBOdds)

        highlightIfNeeded(
            label: homeOddsLabel,
            previousValue: previous?.odds?.teamAOdds,
            currentValue: current.odds?.teamAOdds,
            resetWorkItemKeyPath: \.homeResetWorkItem,
            highlightTimestampKeyPath: \.homeHighlightTimestamp,
            resetAction: { [weak self] animated in self?.resetHomeOdds(animated: animated) }
        )

        highlightIfNeeded(
            label: awayOddsLabel,
            previousValue: previous?.odds?.teamBOdds,
            currentValue: current.odds?.teamBOdds,
            resetWorkItemKeyPath: \.awayResetWorkItem,
            highlightTimestampKeyPath: \.awayHighlightTimestamp,
            resetAction: { [weak self] animated in self?.resetAwayOdds(animated: animated) }
        )
    }

    private func highlightIfNeeded(
        label: UILabel,
        previousValue: Double?,
        currentValue: Double?,
        resetWorkItemKeyPath: ReferenceWritableKeyPath<MatchOddsCell, DispatchWorkItem?>,
        highlightTimestampKeyPath: ReferenceWritableKeyPath<MatchOddsCell, Date?>,
        resetAction: @escaping (Bool) -> Void
    ) {
        guard let previousValue, let currentValue else {
            attemptResetIfAllowed(animated: false, highlightTimestampKeyPath: highlightTimestampKeyPath, resetAction: resetAction)
            return
        }

        guard abs(currentValue - previousValue) >= Metric.minimumChangeThreshold else {
            attemptResetIfAllowed(animated: false, highlightTimestampKeyPath: highlightTimestampKeyPath, resetAction: resetAction)
            return
        }

        self[keyPath: resetWorkItemKeyPath]?.cancel()
        self[keyPath: highlightTimestampKeyPath] = Date()
        label.textColor = Palette.highlightText
        label.backgroundColor = currentValue > previousValue ? Palette.increaseBackground : Palette.decreaseBackground

        let workItem = DispatchWorkItem { [weak self] in
            self?.attemptResetIfAllowed(animated: true, highlightTimestampKeyPath: highlightTimestampKeyPath, resetAction: resetAction)
        }
        self[keyPath: resetWorkItemKeyPath] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Metric.highlightHoldDuration, execute: workItem)
    }

    private func resetHomeOdds(animated: Bool) {
        update(label: homeOddsLabel, animated: animated)
    }

    private func resetAwayOdds(animated: Bool) {
        update(label: awayOddsLabel, animated: animated)
    }

    private func update(label: UILabel, animated: Bool) {
        let updates = {
            label.textColor = Palette.defaultOddsText
            label.backgroundColor = Palette.defaultOddsBackground
        }

        guard animated else {
            updates()
            return
        }

        UIView.transition(
            with: label,
            duration: Metric.colorFadeDuration,
            options: [.transitionCrossDissolve, .beginFromCurrentState, .allowAnimatedContent],
            animations: updates
        )
    }

    private func resetOddsStyles(animated: Bool) {
        resetHomeOdds(animated: animated)
        resetAwayOdds(animated: animated)
        homeHighlightTimestamp = nil
        awayHighlightTimestamp = nil
    }

    private func cancelPendingResets() {
        homeResetWorkItem?.cancel()
        homeResetWorkItem = nil
        awayResetWorkItem?.cancel()
        awayResetWorkItem = nil
        homeHighlightTimestamp = nil
        awayHighlightTimestamp = nil
    }

    private func configure() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        configureContainer()
        configureLabels()
        layoutContent()
    }

    private func configureContainer() {
        containerView.backgroundColor = .secondarySystemBackground
        containerView.layer.cornerRadius = Metric.containerCornerRadius
        containerView.layer.masksToBounds = true
        containerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metric.containerInsets.top),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Metric.containerInsets.left),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metric.containerInsets.right),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Metric.containerInsets.bottom)
        ])
    }

    private func configureLabels() {
        dateLabel.font = .preferredFont(forTextStyle: .subheadline)
        dateLabel.textAlignment = .center
        dateLabel.textColor = .label

        homeTeamLabel.font = .preferredFont(forTextStyle: .body)
        homeTeamLabel.textColor = .secondaryLabel
        homeTeamLabel.textAlignment = .center
        homeTeamLabel.lineBreakMode = .byTruncatingTail

        awayTeamLabel.font = .preferredFont(forTextStyle: .body)
        awayTeamLabel.textColor = .secondaryLabel
        awayTeamLabel.textAlignment = .center
        awayTeamLabel.lineBreakMode = .byTruncatingTail

        vsLabel.font = .preferredFont(forTextStyle: .headline)
        vsLabel.textColor = .label
        vsLabel.text = "VS"
        vsLabel.textAlignment = .center

        homeTitleLabel.font = .preferredFont(forTextStyle: .footnote)
        homeTitleLabel.textColor = .secondaryLabel
        homeTitleLabel.textAlignment = .center
        homeTitleLabel.text = "Home"

        awayTitleLabel.font = .preferredFont(forTextStyle: .footnote)
        awayTitleLabel.textColor = .secondaryLabel
        awayTitleLabel.textAlignment = .center
        awayTitleLabel.text = "Away"

        [homeOddsLabel, awayOddsLabel].forEach { label in
            label.font = .preferredFont(forTextStyle: .body)
            label.textAlignment = .center
            label.layer.cornerRadius = Metric.oddsCornerRadius
            label.layer.masksToBounds = true
        }
    }

    private func layoutContent() {
        let teamsStack = UIStackView(arrangedSubviews: [homeTeamLabel, vsLabel, awayTeamLabel])
        teamsStack.axis = .horizontal
        teamsStack.alignment = .center
        teamsStack.distribution = .equalCentering
        teamsStack.spacing = Metric.subStackSpacing

        let homeStack = createOddsStack(title: homeTitleLabel, odds: homeOddsLabel)
        let awayStack = createOddsStack(title: awayTitleLabel, odds: awayOddsLabel)
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let oddsRow = UIStackView(arrangedSubviews: [homeStack, spacer, awayStack])
        oddsRow.axis = .horizontal
        oddsRow.alignment = .center
        oddsRow.spacing = Metric.subStackSpacing

        let mainStack = UIStackView(arrangedSubviews: [dateLabel, teamsStack, oddsRow])
        mainStack.axis = .vertical
        mainStack.spacing = Metric.stackSpacing
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: containerView.topAnchor, constant: Metric.contentInsets.top),
            mainStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Metric.contentInsets.left),
            mainStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Metric.contentInsets.right),
            mainStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -Metric.contentInsets.bottom)
        ])
    }

    private func createOddsStack(title: UILabel, odds: UILabel) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: [title, odds])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = Metric.oddsStackSpacing
        stack.setContentHuggingPriority(.required, for: .horizontal)
        stack.setContentCompressionResistancePriority(.required, for: .horizontal)
        return stack
    }

    private func updateDateLabel(with date: Date, formatter: DateFormatter) {
        dateLabel.text = formatter.string(from: date)
    }

    private func formatOdds(_ value: Double?) -> String {
        guard let value else { return "-" }
        return oddsFormatter.string(from: NSNumber(value: value)) ?? "-"
    }

    private func attemptResetIfAllowed(
        animated: Bool,
        highlightTimestampKeyPath: ReferenceWritableKeyPath<MatchOddsCell, Date?>,
        resetAction: (Bool) -> Void
    ) {
        guard let timestamp = self[keyPath: highlightTimestampKeyPath] else {
            resetAction(animated)
            return
        }

        let elapsed = Date().timeIntervalSince(timestamp)
        guard elapsed >= Metric.minimumResetDelay else { return }

        self[keyPath: highlightTimestampKeyPath] = nil
        resetAction(animated)
    }
}
