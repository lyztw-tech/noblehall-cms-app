import Foundation
import SwiftData

struct CachedAddTaskFormData: Sendable {
    let projectUUID: String
    let members: [ProjectMemberDto]
    let groups: [ProjectGroupDto]
    let categories: [DropdownOptionItemDto]
}

@MainActor
enum AddTaskFormCache {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func save(
        projectCode: String,
        projectUUID: String,
        members: [ProjectMemberDto],
        groups: [ProjectGroupDto],
        categories: [DropdownOptionItemDto],
        context: ModelContext
    ) throws {
        let membersJSON = try encoder.encode(members)
        let groupsJSON = try encoder.encode(groups)
        let categoriesJSON = try encoder.encode(categories)
        let pc = projectCode
        if let row = try context.fetch(
            FetchDescriptor<CachedAddTaskFormMeta>(predicate: #Predicate<CachedAddTaskFormMeta> { $0.projectCode == pc })
        ).first {
            row.projectUUID = projectUUID
            row.membersJSON = membersJSON
            row.groupsJSON = groupsJSON
            row.categoriesJSON = categoriesJSON
            row.cachedAt = Date()
        } else {
            context.insert(
                CachedAddTaskFormMeta(
                    projectCode: projectCode,
                    projectUUID: projectUUID,
                    membersJSON: membersJSON,
                    groupsJSON: groupsJSON,
                    categoriesJSON: categoriesJSON
                )
            )
        }
        try context.save()
    }

    static func load(projectCode: String, context: ModelContext) throws -> CachedAddTaskFormData? {
        let pc = projectCode
        guard let row = try context.fetch(
            FetchDescriptor<CachedAddTaskFormMeta>(predicate: #Predicate<CachedAddTaskFormMeta> { $0.projectCode == pc })
        ).first else { return nil }
        return CachedAddTaskFormData(
            projectUUID: row.projectUUID,
            members: try decoder.decode([ProjectMemberDto].self, from: row.membersJSON),
            groups: try decoder.decode([ProjectGroupDto].self, from: row.groupsJSON),
            categories: try decoder.decode([DropdownOptionItemDto].self, from: row.categoriesJSON)
        )
    }

    static func preload(projectCode: String, spaceId: String, context: ModelContext) async throws {
        async let proj = ProjectAPI.projectDetail(projectCode: projectCode, spaceId: spaceId)
        async let mem = QualityTaskAPI.allProjectMembers(projectCode: projectCode, spaceId: spaceId)
        async let grp = QualityTaskAPI.listProjectGroups(projectCode: projectCode, spaceId: spaceId)
        let (project, members, groupsRes) = try await (proj, mem, grp)
        var categories: [DropdownOptionItemDto] = []
        if let cats = try? await QualityTaskAPI.categoryOptions(projectId: project.id, spaceId: spaceId) {
            categories = cats.options
        }
        try save(
            projectCode: projectCode,
            projectUUID: project.id,
            members: members,
            groups: groupsRes.data,
            categories: categories,
            context: context
        )
    }
}
