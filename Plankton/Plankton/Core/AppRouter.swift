//
//  AppRouter.swift
//  Plankton
//
//  App-wide navigation state, so something outside the view tree can open an item.
//

import Foundation
import JellyfinAPI
import Observation

/// A media item to navigate to.
///
/// `ItemDetailView` refetches by ID on appear, so an ID and type are all a
/// destination needs — the same trick Continue Watching uses to land on a
/// series. `item` is carried when the caller already had the full record (a
/// tap in the grid), purely so the detail page paints immediately instead of
/// showing an empty hero until the refetch lands.
struct MediaRoute: Hashable, Identifiable {

    let itemID: String
    let type: BaseItemKind
    let name: String?
    var item: BaseItemDto?

    var id: String { itemID }

    init(itemID: String, type: BaseItemKind, name: String? = nil) {
        self.itemID = itemID
        self.type = type
        self.name = name
    }

    /// Route to an item already in hand.
    init?(item: BaseItemDto) {
        guard let id = item.id, let type = item.type else { return nil }
        self.itemID = id
        self.type = type
        self.name = item.name
        self.item = item
    }

    /// What `ItemDetailView` should be handed: the real item when there is
    /// one, otherwise a stub carrying the ID and type it needs to load itself.
    var detailItem: BaseItemDto {
        if let item { return item }
        var stub = BaseItemDto()
        stub.id = itemID
        stub.type = type
        stub.name = name
        return stub
    }

    // Identity is the item, not the payload: the same item routed to from a
    // grid tap and from a Spotlight result must land on the same page, and
    // `BaseItemDto` isn't `Hashable` to begin with.
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.itemID == rhs.itemID }

    func hash(into hasher: inout Hasher) { hasher.combine(itemID) }
}

/// A destination within the Downloads tab.
enum DownloadsRoute: Hashable {
    case series(groupID: String, name: String)
}

/// Owns which tab is showing and what is pushed on top of it.
///
/// Navigation is otherwise expressed with destination-closure `NavigationLink`s,
/// which only the view tree can trigger. Spotlight results and App Intents run
/// outside it, so the paths they drive live here instead — created alongside the
/// other services and injected the same way.
@Observable
final class AppRouter {

    enum Tab: Hashable {
        case home, library, downloads, settings
    }

    var selectedTab: Tab = .home
    var libraryPath: [MediaRoute] = []
    var downloadsPath: [DownloadsRoute] = []

    /// Opens an item that was chosen from outside the app.
    ///
    /// Offline, the Library tab is disabled and the detail page has no server
    /// to load from, so a downloaded item is shown through the Downloads tab
    /// instead: its series if it belongs to one, otherwise the grid, where the
    /// movie's own tile is already waiting.
    /// - Parameters:
    ///   - isOffline: whether the server is currently unreachable.
    ///   - downloadedSeries: the item's series grouping when it's downloaded
    ///     and part of a show, from `DownloadedMedia.seriesGroupID`.
    func open(_ route: MediaRoute, isOffline: Bool, downloadedSeries: (groupID: String, name: String)? = nil) {
        guard isOffline else {
            selectedTab = .library
            libraryPath = [route]
            return
        }

        selectedTab = .downloads
        downloadsPath = downloadedSeries.map { [.series(groupID: $0.groupID, name: $0.name)] } ?? []
    }
}
