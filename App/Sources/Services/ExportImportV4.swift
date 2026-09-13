import Foundation
import SwiftData
import MuscuEngine

/// Entites ajoutees au modele v4 : lieux, recurrences, modeles et
/// annotations de bibliotheque.
///
/// Deux entites v4 sont volontairement ABSENTES de l'export :
/// - `NotificationRecord`, qui reflete l'etat du centre de notifications de
///   CET appareil ; le restaurer ailleurs decrirait des rappels inexistants ;
/// - `CalendarLink`, qui pointe vers des evenements du calendrier local ;
///   importe ailleurs, il autoriserait Muscu a modifier des evenements qu'il
///   n'a pas crees.
/// Les deux se reconstruisent d'eux-memes apres un import.
extension ExportImport {
    // MARK: - DTO

    struct PlaceDTO: Codable {
        var id: UUID
        var name: String
        var kindRaw: String
        var isDefault: Bool
        var notes: String
        var inventory: [EquipmentAvailability]
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
    }

    struct ScheduleDTO: Codable {
        var id: UUID
        var programId: UUID?
        var name: String
        var isEnabled: Bool
        var weekdays: [Int]
        var startDate: Date
        var endDate: Date?
        var pausedWeekOffsets: [Int]
        var hour: Int
        var minute: Int
        var placeId: UUID?
        var remindersEnabled: Bool
        var reminderLeadMinutes: Int
        var reminderDayOfHour: Int?
        var reminderDayOfMinute: Int?
        var reminderComebackAfterDays: Int
        var reminderSoundEnabled: Bool
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
    }

    struct TemplateDTO: Codable {
        var id: UUID
        var name: String
        var scopeRaw: String
        var notes: String
        var payload: TemplatePayload?
        var version: Int
        var isArchived: Bool
        var isFavorite: Bool
        var lastUsedAt: Date?
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
    }

    struct LibraryEntryDTO: Codable {
        var exerciseId: String
        var isFavorite: Bool
        var tags: [String]
        var lastUsedAt: Date?
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
    }

    struct CollectionDTO: Codable {
        var id: UUID
        var name: String
        var notes: String
        var exerciseIds: [String]
        var createdAt: Date
        var updatedAt: Date
        var deletedAt: Date?
    }

    // MARK: - Modèle -> DTO

    static func dto(from place: PlaceProfile) -> PlaceDTO {
        PlaceDTO(
            id: place.id,
            name: place.name,
            kindRaw: place.kindRaw,
            isDefault: place.isDefault,
            notes: place.notes,
            inventory: place.inventory.items,
            createdAt: place.createdAt,
            updatedAt: place.updatedAt,
            deletedAt: place.deletedAt
        )
    }

    static func dto(from schedule: PlanningSchedule) -> ScheduleDTO {
        ScheduleDTO(
            id: schedule.id,
            programId: schedule.programId,
            name: schedule.name,
            isEnabled: schedule.isEnabled,
            weekdays: schedule.weekdays.sorted(),
            startDate: schedule.startDate,
            endDate: schedule.endDate,
            pausedWeekOffsets: schedule.pausedWeekOffsets.sorted(),
            hour: schedule.hour,
            minute: schedule.minute,
            placeId: schedule.placeId,
            remindersEnabled: schedule.remindersEnabled,
            reminderLeadMinutes: schedule.reminderLeadMinutes,
            reminderDayOfHour: schedule.reminderDayOfHour,
            reminderDayOfMinute: schedule.reminderDayOfMinute,
            reminderComebackAfterDays: schedule.reminderComebackAfterDays,
            reminderSoundEnabled: schedule.reminderSoundEnabled,
            createdAt: schedule.createdAt,
            updatedAt: schedule.updatedAt,
            deletedAt: schedule.deletedAt
        )
    }

    static func dto(from template: SessionTemplate) -> TemplateDTO {
        TemplateDTO(
            id: template.id,
            name: template.name,
            scopeRaw: template.scopeRaw,
            notes: template.notes,
            payload: template.payloadData.flatMap { try? JSONDecoder().decode(TemplatePayload.self, from: $0) },
            version: template.version,
            isArchived: template.isArchived,
            isFavorite: template.isFavorite,
            lastUsedAt: template.lastUsedAt,
            createdAt: template.createdAt,
            updatedAt: template.updatedAt,
            deletedAt: template.deletedAt
        )
    }

    static func dto(from entry: ExerciseLibraryEntry) -> LibraryEntryDTO {
        LibraryEntryDTO(
            exerciseId: entry.exerciseId,
            isFavorite: entry.isFavorite,
            tags: entry.tags.sorted(),
            lastUsedAt: entry.lastUsedAt,
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt,
            deletedAt: entry.deletedAt
        )
    }

    static func dto(from collection: ExerciseCollection) -> CollectionDTO {
        CollectionDTO(
            id: collection.id,
            name: collection.name,
            notes: collection.notes,
            exerciseIds: collection.exerciseIds,
            createdAt: collection.createdAt,
            updatedAt: collection.updatedAt,
            deletedAt: collection.deletedAt
        )
    }

    // MARK: - DTO -> Modèle

    static func model(from dto: PlaceDTO) -> PlaceProfile {
        let place = PlaceProfile(
            id: dto.id,
            name: dto.name,
            kindRaw: dto.kindRaw,
            isDefault: dto.isDefault,
            notes: dto.notes,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            deletedAt: dto.deletedAt
        )
        place.inventory = EquipmentInventory(items: dto.inventory)
        return place
    }

    static func model(from dto: ScheduleDTO) -> PlanningSchedule {
        let schedule = PlanningSchedule(
            id: dto.id,
            programId: dto.programId,
            name: dto.name,
            isEnabled: dto.isEnabled,
            startDate: dto.startDate,
            endDate: dto.endDate,
            hour: dto.hour,
            minute: dto.minute,
            placeId: dto.placeId,
            // Les rappels sont TOUJOURS reimportes desactives : l'autorisation
            // de notifier appartient a l'appareil, pas au fichier.
            remindersEnabled: false,
            reminderLeadMinutes: dto.reminderLeadMinutes,
            reminderDayOfHour: dto.reminderDayOfHour,
            reminderDayOfMinute: dto.reminderDayOfMinute,
            reminderComebackAfterDays: dto.reminderComebackAfterDays,
            reminderSoundEnabled: dto.reminderSoundEnabled,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            deletedAt: dto.deletedAt
        )
        schedule.weekdays = Set(dto.weekdays)
        schedule.pausedWeekOffsets = Set(dto.pausedWeekOffsets)
        return schedule
    }

    static func model(from dto: TemplateDTO) -> SessionTemplate {
        SessionTemplate(
            id: dto.id,
            name: dto.name,
            scopeRaw: dto.scopeRaw,
            notes: dto.notes,
            payloadData: dto.payload.flatMap { try? JSONEncoder().encode($0) },
            version: dto.version,
            isArchived: dto.isArchived,
            isFavorite: dto.isFavorite,
            lastUsedAt: dto.lastUsedAt,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            deletedAt: dto.deletedAt
        )
    }

    static func model(from dto: LibraryEntryDTO) -> ExerciseLibraryEntry {
        let entry = ExerciseLibraryEntry(
            exerciseId: dto.exerciseId,
            isFavorite: dto.isFavorite,
            lastUsedAt: dto.lastUsedAt,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            deletedAt: dto.deletedAt
        )
        entry.tags = Set(dto.tags)
        return entry
    }

    static func model(from dto: CollectionDTO) -> ExerciseCollection {
        let collection = ExerciseCollection(
            id: dto.id,
            name: dto.name,
            notes: dto.notes,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            deletedAt: dto.deletedAt
        )
        collection.exerciseIds = dto.exerciseIds
        return collection
    }
}
