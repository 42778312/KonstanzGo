import AppIntents
import KGCore

/// A stop to pick in a widget's edit menu: favourites first, then every stop (plan X3.1).
struct StopEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Haltestelle"
    static let defaultQuery = StopQuery()

    var id: Int
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct StopQuery: EntityStringQuery {
    func entities(for identifiers: [Int]) async throws -> [StopEntity] {
        identifiers.compactMap { id in
            WidgetData.timetable?.station(id: id).map { StopEntity(id: $0.id, name: $0.shortName) }
        }
    }

    func entities(matching string: String) async throws -> [StopEntity] {
        let all = WidgetData.timetable?.stations ?? []
        return all.filter { $0.shortName.localizedCaseInsensitiveContains(string) }
            .prefix(30).map { StopEntity(id: $0.id, name: $0.shortName) }
    }

    func suggestedEntities() async throws -> [StopEntity] {
        let favorites = ((try? WidgetData.user?.favorites()) ?? []).compactMap { favorite -> StopEntity? in
            if case let .station(id, name, _) = favorite.target { return StopEntity(id: id, name: name) }
            return nil
        }
        let ids = Set(favorites.map(\.id))
        let rest = (WidgetData.timetable?.stations ?? []).filter { !ids.contains($0.id) }
            .sorted { $0.shortName < $1.shortName }.map { StopEntity(id: $0.id, name: $0.shortName) }
        return favorites + rest
    }

    func defaultResult() async -> StopEntity? {
        WidgetData.defaultStation.map { StopEntity(id: $0.id, name: $0.shortName) }
    }
}
