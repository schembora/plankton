//
//  GuideGrid.swift
//  Plankton
//
//  The programme grid, laid out by UIKit.
//

import JellyfinAPI
import SwiftUI
import UIKit

/// Fixed geometry for the grid, shared between the layout and its cells.
enum GuideMetrics {
    static let minuteWidth: CGFloat = 4
    static let channelWidth: CGFloat = 92
    static let headerHeight: CGFloat = 30
    static let rowHeight: CGFloat = 64
    static let slot: TimeInterval = 30 * 60
    static let window: TimeInterval = 6 * 60 * 60

    static var contentWidth: CGFloat { CGFloat(window / 60) * minuteWidth }
    static var slotCount: Int { Int(window / slot) }

    /// Where the grid's left edge sits for a given moment: the half hour on or
    /// before it, so the columns read as the times people expect.
    ///
    /// Programmes that began earlier are not dropped, they are clipped to it.
    static func gridStart(for date: Date) -> Date {
        let floored = (date.timeIntervalSinceReferenceDate / slot).rounded(.down) * slot
        return Date(timeIntervalSinceReferenceDate: floored)
    }
}

/// What the grid draws, resolved once so the layout and the cells agree.
struct GuideModel {

    var channels: [BaseItemDto] = []
    var listings: [String: [BaseItemDto]] = [:]
    var start: Date = .now

    /// Where the present moment falls. Separate from `start`, which is pinned
    /// to the half hour, so the line can move between relayouts.
    var now: Date = .now

    var selectedProgrammeID: String?
    var startingChannelID: String?

    var end: Date { start.addingTimeInterval(GuideMetrics.window) }

    func programmes(on channel: BaseItemDto) -> [BaseItemDto] {
        guard let all = channel.id.flatMap({ listings[$0] }) else { return [] }
        return all.filter { ($0.endDate ?? end) > start && ($0.startDate ?? start) < end }
    }

    func x(for date: Date) -> CGFloat {
        max(0, CGFloat(date.timeIntervalSince(start) / 60) * GuideMetrics.minuteWidth)
    }

    /// Clamped to the window at both ends, so a programme that began before the
    /// grid did still fills the space it occupies inside it.
    func width(of programme: BaseItemDto) -> CGFloat {
        let from = max(programme.startDate ?? start, start)
        let to = min(programme.endDate ?? end, end)
        return CGFloat(max(to.timeIntervalSince(from) / 60, 5)) * GuideMetrics.minuteWidth - 2
    }
}

/// A programme grid with a channel column and a time axis that stay put.
///
/// UIKit rather than SwiftUI because the two things this needs are things a
/// `ScrollView` won't give up: control of its own content insets, and
/// supplementary views pinned to an edge while the rest scrolls in two
/// directions. In SwiftUI both have to be imitated by translating overlays
/// against the scroll offset, and the offset isn't knowable until something
/// scrolls — so the headers start in the wrong place and settle later.
struct GuideGrid: UIViewRepresentable {

    var model: GuideModel
    let onRefresh: () async -> Void
    let onSelectProgramme: (BaseItemDto, BaseItemDto) -> Void
    let onSelectChannel: (BaseItemDto) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, onRefresh: onRefresh, onSelectProgramme: onSelectProgramme, onSelectChannel: onSelectChannel)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let view = UICollectionView(frame: .zero, collectionViewLayout: GuideLayout())
        view.backgroundColor = .clear
        view.dataSource = context.coordinator
        view.delegate = context.coordinator

        // The whole reason this is UIKit: the grid begins where it's put,
        // rather than wherever the navigation bar and search field decide.
        view.contentInsetAdjustmentBehavior = .never
        view.contentInset = .zero

        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.refreshPulled), for: .valueChanged)
        view.refreshControl = refresh

        context.coordinator.register(on: view)
        return view
    }

    func updateUIView(_ view: UICollectionView, context: Context) {
        context.coordinator.update(model: model, on: view)
        context.coordinator.onRefresh = onRefresh
        context.coordinator.onSelectProgramme = onSelectProgramme
        context.coordinator.onSelectChannel = onSelectChannel
    }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {

        private var model: GuideModel
        var onRefresh: () async -> Void
        var onSelectProgramme: (BaseItemDto, BaseItemDto) -> Void
        var onSelectChannel: (BaseItemDto) -> Void

        private static let programmeCell = "programme"
        private static let channelKind = "channel"
        private static let timeKind = "time"
        private static let cornerKind = "corner"

        init(
            model: GuideModel,
            onRefresh: @escaping () async -> Void,
            onSelectProgramme: @escaping (BaseItemDto, BaseItemDto) -> Void,
            onSelectChannel: @escaping (BaseItemDto) -> Void
        ) {
            self.model = model
            self.onRefresh = onRefresh
            self.onSelectProgramme = onSelectProgramme
            self.onSelectChannel = onSelectChannel
        }

        func register(on view: UICollectionView) {
            view.register(HostCell.self, forCellWithReuseIdentifier: Self.programmeCell)
            for kind in [Self.channelKind, Self.timeKind, Self.cornerKind] {
                view.register(HostSupplementary.self, forSupplementaryViewOfKind: kind, withReuseIdentifier: kind)
            }
        }

        func update(model: GuideModel, on view: UICollectionView) {
            let channelsChanged = self.model.channels.map(\.id) != model.channels.map(\.id)
            self.model = model
            (view.collectionViewLayout as? GuideLayout)?.model = model

            if channelsChanged {
                view.reloadData()
            } else {
                view.collectionViewLayout.invalidateLayout()
                for cell in view.visibleCells {
                    guard let cell = cell as? HostCell, let path = view.indexPath(for: cell) else { continue }
                    configure(cell, at: path)
                }
            }

            if !(view.refreshControl?.isRefreshing ?? false) {
                view.refreshControl?.endRefreshing()
            }
        }

        @objc func refreshPulled(_ control: UIRefreshControl) {
            Task {
                await onRefresh()
                control.endRefreshing()
            }
        }

        // MARK: - Data

        func numberOfSections(in collectionView: UICollectionView) -> Int {
            model.channels.count
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            guard section < model.channels.count else { return 0 }
            return model.programmes(on: model.channels[section]).count
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: Self.programmeCell,
                for: indexPath
            ) as! HostCell
            configure(cell, at: indexPath)
            return cell
        }

        private func configure(_ cell: HostCell, at indexPath: IndexPath) {
            guard indexPath.section < model.channels.count else { return }

            let programmes = model.programmes(on: model.channels[indexPath.section])
            guard indexPath.item < programmes.count else { return }

            let programme = programmes[indexPath.item]
            let isSelected = programme.id != nil && programme.id == model.selectedProgrammeID
            cell.host(GuideProgrammeCell(programme: programme, isSelected: isSelected))
        }

        func collectionView(
            _ collectionView: UICollectionView,
            viewForSupplementaryElementOfKind kind: String,
            at indexPath: IndexPath
        ) -> UICollectionReusableView {
            let view = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: kind,
                for: indexPath
            ) as! HostSupplementary

            switch kind {
            case Self.channelKind:
                let channel = model.channels[indexPath.section]
                view.host(
                    GuideChannelCell(
                        channel: channel,
                        isStarting: channel.id == model.startingChannelID
                    ) { [weak self] in
                        self?.onSelectChannel(channel)
                    }
                )
            case Self.timeKind:
                view.host(GuideTimeAxis(start: model.start))
            default:
                view.host(GuideCorner())
            }
            return view
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            collectionView.deselectItem(at: indexPath, animated: false)

            guard indexPath.section < model.channels.count else { return }
            let channel = model.channels[indexPath.section]

            let programmes = model.programmes(on: channel)
            guard indexPath.item < programmes.count else { return }

            onSelectProgramme(channel, programmes[indexPath.item])
        }
    }
}

// MARK: - Layout

/// Places every block by clock time, and keeps the column and the axis on the
/// edges they belong to.
///
/// Pinning is done here rather than by moving views around afterwards: the
/// layout is asked for attributes on every bounds change, so the pinned frames
/// are simply computed from the current offset and are never out of step with
/// the rows they label.
final class GuideLayout: UICollectionViewLayout {

    private static let gridlineKind = "gridline"
    private static let nowKind = "now"

    override init() {
        super.init()
        registerDecorations()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerDecorations()
    }

    private func registerDecorations() {
        register(GuideGridline.self, forDecorationViewOfKind: Self.gridlineKind)
        register(GuideNowLine.self, forDecorationViewOfKind: Self.nowKind)
    }

    var model = GuideModel() {
        didSet { invalidateLayout() }
    }

    private var cells: [IndexPath: UICollectionViewLayoutAttributes] = [:]

    /// Rows grow to fill the screen when there aren't enough channels to reach
    /// the bottom, rather than leaving the table hanging in empty space. They
    /// never shrink below their natural height, so a long line-up still
    /// scrolls instead of squeezing every channel into a sliver.
    private var rowHeight: CGFloat {
        guard let collectionView, !model.channels.isEmpty else { return GuideMetrics.rowHeight }

        let available = collectionView.bounds.height - GuideMetrics.headerHeight
        return max(GuideMetrics.rowHeight, available / CGFloat(model.channels.count))
    }

    override var collectionViewContentSize: CGSize {
        CGSize(
            width: GuideMetrics.channelWidth + GuideMetrics.contentWidth,
            height: GuideMetrics.headerHeight + CGFloat(model.channels.count) * rowHeight
        )
    }

    override func prepare() {
        super.prepare()
        cells = [:]

        for (section, channel) in model.channels.enumerated() {
            let y = GuideMetrics.headerHeight + CGFloat(section) * rowHeight

            for (item, programme) in model.programmes(on: channel).enumerated() {
                let path = IndexPath(item: item, section: section)
                let attributes = UICollectionViewLayoutAttributes(forCellWith: path)
                attributes.frame = CGRect(
                    x: GuideMetrics.channelWidth + model.x(for: programme.startDate ?? model.start),
                    y: y,
                    width: model.width(of: programme),
                    height: rowHeight
                )
                cells[path] = attributes
            }
        }
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard let collectionView else { return nil }

        let offset = collectionView.contentOffset
        var attributes = cells.values.filter { $0.frame.intersects(rect) }

        // Channel cells ride at the left edge, above the blocks passing under.
        for section in model.channels.indices {
            let path = IndexPath(item: 0, section: section)
            let cell = UICollectionViewLayoutAttributes(
                forSupplementaryViewOfKind: "channel",
                with: path
            )
            cell.frame = CGRect(
                x: max(0, offset.x),
                y: GuideMetrics.headerHeight + CGFloat(section) * rowHeight,
                width: GuideMetrics.channelWidth,
                height: rowHeight
            )
            cell.zIndex = 2
            if cell.frame.intersects(rect) { attributes.append(cell) }
        }

        let axis = UICollectionViewLayoutAttributes(
            forSupplementaryViewOfKind: "time",
            with: IndexPath(item: 0, section: 0)
        )
        axis.frame = CGRect(
            x: GuideMetrics.channelWidth,
            y: max(0, offset.y),
            width: GuideMetrics.contentWidth,
            height: GuideMetrics.headerHeight
        )
        axis.zIndex = 3
        attributes.append(axis)

        let corner = UICollectionViewLayoutAttributes(
            forSupplementaryViewOfKind: "corner",
            with: IndexPath(item: 0, section: 0)
        )
        corner.frame = CGRect(
            x: max(0, offset.x),
            y: max(0, offset.y),
            width: GuideMetrics.channelWidth,
            height: GuideMetrics.headerHeight
        )
        corner.zIndex = 4
        attributes.append(corner)

        // A rule on every half hour, so a block's width can be read as a
        // duration rather than guessed at. Hours are drawn stronger than the
        // half hours between them, which is what makes the columns countable.
        for index in 0...GuideMetrics.slotCount {
            let line = layoutAttributesForDecorationView(
                ofKind: Self.gridlineKind,
                at: IndexPath(item: index, section: 0)
            )
            guard let line else { continue }

            // Never under the pinned column, where it would show through the
            // channel cells' material.
            if line.frame.maxX > offset.x + GuideMetrics.channelWidth, line.frame.intersects(rect) {
                attributes.append(line)
            }
        }

        if let line = layoutAttributesForDecorationView(
            ofKind: Self.nowKind,
            at: IndexPath(item: 0, section: 0)
        ), line.frame.maxX > offset.x + GuideMetrics.channelWidth {
            attributes.append(line)
        }

        return attributes
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        cells[indexPath]
    }

    override func layoutAttributesForDecorationView(
        ofKind elementKind: String,
        at indexPath: IndexPath
    ) -> UICollectionViewLayoutAttributes? {
        if elementKind == Self.nowKind {
            let line = UICollectionViewLayoutAttributes(
                forDecorationViewOfKind: elementKind,
                with: indexPath
            )
            line.frame = CGRect(
                x: GuideMetrics.channelWidth + model.x(for: model.now) - 1,
                y: GuideMetrics.headerHeight,
                width: 2,
                height: collectionViewContentSize.height - GuideMetrics.headerHeight
            )
            // Over the blocks, unlike the half hour rules: this one is the
            // answer to "how much have I missed", so it has to be findable.
            line.zIndex = 1
            return line
        }

        guard elementKind == Self.gridlineKind else { return nil }

        let slotWidth = CGFloat(GuideMetrics.slot / 60) * GuideMetrics.minuteWidth
        let attributes = UICollectionViewLayoutAttributes(
            forDecorationViewOfKind: elementKind,
            with: indexPath
        )
        attributes.frame = CGRect(
            x: GuideMetrics.channelWidth + CGFloat(indexPath.item) * slotWidth,
            y: GuideMetrics.headerHeight,
            width: 0.5,
            height: collectionViewContentSize.height - GuideMetrics.headerHeight
        )
        // Behind the blocks: a rule through a programme's title would be worse
        // than no rule at all.
        attributes.zIndex = -1
        attributes.alpha = indexPath.item.isMultiple(of: 2) ? 1 : 0.45
        return attributes
    }

    /// Pinned frames are recomputed from the offset, so every scroll is a
    /// relayout. That's what keeps them from drifting.
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        true
    }
}

// MARK: - Hosting

/// One vertical rule between two slots.
final class GuideGridline: UICollectionReusableView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.white.withAlphaComponent(0.22)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("GuideGridline is not loaded from a nib")
    }
}

/// The present moment, struck down the grid.
final class GuideNowLine: UICollectionReusableView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemRed
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("GuideNowLine is not loaded from a nib")
    }
}

/// A cell that draws a SwiftUI view, so the grid's contents stay SwiftUI even
/// though its layout doesn't.
final class HostCell: UICollectionViewCell {

    func host(_ content: some View) {
        contentConfiguration = UIHostingConfiguration { content }
            .margins(.all, 0)
    }
}

final class HostSupplementary: UICollectionReusableView {

    private var controller: UIHostingController<AnyView>?

    func host(_ content: some View) {
        let view = AnyView(content)

        if let controller {
            controller.rootView = view
            return
        }

        let new = UIHostingController(rootView: view)
        new.view.backgroundColor = .clear
        new.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(new.view)
        NSLayoutConstraint.activate([
            new.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            new.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            new.view.topAnchor.constraint(equalTo: topAnchor),
            new.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        controller = new
    }
}
