import Foundation
import ImageIO
import PDFKit
import SwiftData
import UIKit

struct PlanAssetCacheStats: Sendable {
    let drawingCount: Int
    let drawingsWithImageCount: Int
    let totalPointCount: Int
    let imageBytes: Int64
    let metadataBytes: Int64

    var totalBytes: Int64 { imageBytes + metadataBytes }
}

struct CachedPlanBundle: Sendable {
    let drawingName: String
    let points: [QualityTaskRoomPointDto]
    let image: UIImage?
    let markerReferenceSize: CGSize
}

@MainActor
enum PlanAssetCache {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static var rootDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appending(path: "plan-assets", directoryHint: .isDirectory)
    }

    /// App 啟動／進入專案後：下載全部品質平面圖檔與座標點至本機暫存。
    static func preloadAll(
        projectCode: String,
        spaceId: String,
        context: ModelContext,
        force: Bool = false
    ) async {
        let store = PlanAssetPreloadStore.shared
        if store.isRunning, !force { return }

        do {
            let drawings = try await QualityTaskAPI.allQualityDrawings(
                projectCode: projectCode,
                spaceId: spaceId
            )
            store.begin(total: drawings.count)
            var done = 0
            for item in drawings {
                try await cacheOne(
                    projectCode: projectCode,
                    spaceId: spaceId,
                    listItem: item,
                    context: context
                )
                done += 1
                store.updateProgress(done: done, total: drawings.count)
                try context.save()
            }
            try await AddTaskFormCache.preload(projectCode: projectCode, spaceId: spaceId, context: context)
            await repairCachedPNGs(projectCode: projectCode, context: context)
            try context.save()
            let stats = try stats(projectCode: projectCode, context: context)
            store.noteImagesCached(count: stats.drawingsWithImageCount)
            if stats.drawingCount > 0, stats.drawingsWithImageCount == 0 {
                if stats.imageBytes > 0 {
                    store.finish(error: "平面圖已下載但無法轉為離線圖檔，請再按「重新下載暫存」。")
                } else {
                    store.finish(error: "平面圖圖檔均未能下載，請確認連線與登入狀態後重試。")
                }
            } else if stats.drawingsWithImageCount < stats.drawingCount {
                store.finish(error: "部分平面圖尚無離線圖檔（\(stats.drawingsWithImageCount)/\(stats.drawingCount)），可再按「重新下載暫存」。")
            } else {
                store.finish(error: nil)
            }
        } catch {
            store.finish(error: error.localizedDescription)
        }
    }

    static func listDrawingItems(projectCode: String, context: ModelContext) throws -> [QualityDrawingListItemDto] {
        try rows(projectCode: projectCode, context: context)
            .map { row in
                QualityDrawingListItemDto(
                    id: row.qualityDrawingId,
                    drawing: QualityDrawingRefDto(id: row.qualityDrawingId, name: row.drawingName),
                    taskCount: row.pointCount,
                    taskCountByStatus: nil
                )
            }
            .sorted { $0.drawing.name.localizedStandardCompare($1.drawing.name) == .orderedAscending }
    }

    static func loadBundle(
        projectCode: String,
        qualityDrawingId: String,
        context: ModelContext
    ) throws -> CachedPlanBundle? {
        let pc = projectCode
        let qid = qualityDrawingId
        guard let row = try context.fetch(
            FetchDescriptor<CachedPlanAsset>(
                predicate: #Predicate<CachedPlanAsset> { $0.projectCode == pc && $0.qualityDrawingId == qid }
            )
        ).first else { return nil }
        let points = try decoder.decode([QualityTaskRoomPointDto].self, from: row.pointsJSON)
        let loaded = loadUIImageFromRow(row)
        let image = loaded?.0
        let rw = row.markerReferenceWidth
        let rh = row.markerReferenceHeight
        let storedRef: CGSize
        if let loaded {
            storedRef = loaded.1
        } else if rw > 0, rh > 0 {
            storedRef = CGSize(width: rw, height: rh)
        } else {
            storedRef = .zero
        }
        let refSize = FloorPlanRasterDecoder.effectiveMarkerReferenceSize(points: points, stored: storedRef)
        return CachedPlanBundle(
            drawingName: row.drawingName,
            points: points,
            image: image,
            markerReferenceSize: refSize
        )
    }

    static func hasOfflinePlan(projectCode: String, qualityDrawingId: String, context: ModelContext) -> Bool {
        let pc = projectCode
        let qid = qualityDrawingId
        var desc = FetchDescriptor<CachedPlanAsset>(
            predicate: #Predicate<CachedPlanAsset> { $0.projectCode == pc && $0.qualityDrawingId == qid }
        )
        desc.fetchLimit = 1
        return ((try? context.fetch(desc))?.isEmpty) == false
    }

    static func stats(projectCode: String, context: ModelContext) throws -> PlanAssetCacheStats {
        let rows = try rows(projectCode: projectCode, context: context)
        var imageBytes: Int64 = 0
        var metadataBytes: Int64 = 0
        var points = 0
        var withImage = 0
        for row in rows {
            imageBytes += row.imageByteCount
            metadataBytes += Int64(row.pointsJSON.count)
            points += row.pointCount
            if rowHasCachedImage(row) { withImage += 1 }
        }
        return PlanAssetCacheStats(
            drawingCount: rows.count,
            drawingsWithImageCount: withImage,
            totalPointCount: points,
            imageBytes: imageBytes,
            metadataBytes: metadataBytes
        )
    }

    /// 下載平面圖二進位（預載與連線時補寫快取共用）。
    static func downloadImageData(file: DrawingFileDto?, spaceId: String) async -> Data? {
        guard let file else { return nil }
        var candidates: [URL] = []
        let (primary, fallback) = planImageURLs(for: file)
        if let p = primary { candidates.append(p) }
        if let f = fallback, !candidates.contains(where: { $0.absoluteString == f.absoluteString }) {
            candidates.append(f)
        }
        if let thumb = file.thumbnailUrl, let u = URLResolver.absoluteAssetURL(thumb) {
            if !candidates.contains(where: { $0.absoluteString == u.absoluteString }) {
                candidates.append(u)
            }
        }
        for url in candidates {
            if let data = try? await APIClient.shared.fetchBinary(url: url, spaceId: spaceId),
               isValidPlanBinary(data) {
                return data
            }
        }
        return nil
    }

    /// 已有 `.plan` 但缺 PNG 或解碼失敗時，從本機檔重產 PNG。
    static func repairCachedPNGs(projectCode: String, context: ModelContext) async {
        guard let rows = try? rows(projectCode: projectCode, context: context) else { return }
        for row in rows {
            if loadUIImageFromRow(row) != nil { continue }
            guard let rel = row.imageRelativePath else { continue }
            let planURL = fileURL(relativePath: rel)
            guard let data = try? Data(contentsOf: planURL), !data.isEmpty else { continue }
            if let written = await writePlanImageFiles(
                projectCode: row.projectCode,
                qualityDrawingId: row.qualityDrawingId,
                imageData: data
            ), written.displayable {
                row.markerReferenceWidth = written.markerReferenceWidth
                row.markerReferenceHeight = written.markerReferenceHeight
            }
        }
    }

    /// 連線瀏覽或預載成功後寫入圖檔（含 PNG），供離線顯示。
    static func persistImageData(
        projectCode: String,
        qualityDrawingId: String,
        imageData: Data,
        context: ModelContext
    ) async throws {
        let key = cacheKey(projectCode: projectCode, qualityDrawingId: qualityDrawingId)
        guard isValidPlanBinary(imageData) else { return }

        let k = key
        let existingMatch = try context.fetch(
            FetchDescriptor<CachedPlanAsset>(predicate: #Predicate<CachedPlanAsset> { $0.cacheKey == k })
        ).first
        if let row = existingMatch {
            removePlanFiles(
                projectCode: projectCode,
                qualityDrawingId: qualityDrawingId,
                relativePath: row.imageRelativePath
            )
        }

        let written = await writePlanImageFiles(
            projectCode: projectCode,
            qualityDrawingId: qualityDrawingId,
            imageData: imageData
        )

        if let row = try context.fetch(
            FetchDescriptor<CachedPlanAsset>(predicate: #Predicate<CachedPlanAsset> { $0.cacheKey == k })
        ).first {
            if let written {
                row.imageRelativePath = written.relativePath
                row.imageByteCount = written.byteCount
                row.markerReferenceWidth = written.markerReferenceWidth
                row.markerReferenceHeight = written.markerReferenceHeight
            }
            row.cachedAt = Date()
        } else if let written {
            context.insert(
                CachedPlanAsset(
                    cacheKey: key,
                    projectCode: projectCode,
                    qualityDrawingId: qualityDrawingId,
                    drawingName: qualityDrawingId,
                    imageRelativePath: written.relativePath,
                    imageByteCount: written.byteCount,
                    pointsJSON: try encoder.encode([QualityTaskRoomPointDto]()),
                    pointCount: 0,
                    markerReferenceWidth: written.markerReferenceWidth,
                    markerReferenceHeight: written.markerReferenceHeight
                )
            )
        }
        try context.save()
    }

    static func loadPoints(
        projectCode: String,
        qualityDrawingId: String,
        context: ModelContext
    ) throws -> [QualityTaskRoomPointDto]? {
        let pc = projectCode
        let qid = qualityDrawingId
        guard let row = try context.fetch(
            FetchDescriptor<CachedPlanAsset>(
                predicate: #Predicate<CachedPlanAsset> { $0.projectCode == pc && $0.qualityDrawingId == qid }
            )
        ).first else { return nil }
        return try decoder.decode([QualityTaskRoomPointDto].self, from: row.pointsJSON)
    }

    static func loadImageData(
        projectCode: String,
        qualityDrawingId: String,
        context: ModelContext
    ) throws -> Data? {
        let pc = projectCode
        let qid = qualityDrawingId
        guard let rel = try context.fetch(
            FetchDescriptor<CachedPlanAsset>(
                predicate: #Predicate<CachedPlanAsset> { $0.projectCode == pc && $0.qualityDrawingId == qid }
            )
        ).first?.imageRelativePath else { return nil }
        return try? Data(contentsOf: fileURL(relativePath: rel))
    }

    static func formattedByteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Private

    private struct WrittenPlanImage: Sendable {
        let relativePath: String
        let byteCount: Int64
        let markerReferenceWidth: Double
        let markerReferenceHeight: Double
        let displayable: Bool
    }

    private static func cacheOne(
        projectCode: String,
        spaceId: String,
        listItem: QualityDrawingListItemDto,
        context: ModelContext
    ) async throws {
        let drawingId = listItem.id
        let key = cacheKey(projectCode: projectCode, qualityDrawingId: drawingId)

        async let detailTask = QualityTaskAPI.drawingDetail(
            projectCode: projectCode,
            qualityDrawingId: drawingId,
            spaceId: spaceId
        )
        async let pointsTask = QualityTaskAPI.roomPoints(
            projectCode: projectCode,
            qualityDrawingId: drawingId,
            spaceId: spaceId
        )
        let (detail, points) = try await (detailTask, pointsTask)
        let pointsData = try encoder.encode(points)

        var written: WrittenPlanImage?
        var imageData = await downloadImageData(file: detail.drawing.file, spaceId: spaceId)
        if imageData == nil {
            try await Task.sleep(nanoseconds: 500_000_000)
            imageData = await downloadImageData(file: detail.drawing.file, spaceId: spaceId)
        }
        if let imageData {
            written = await writePlanImageFiles(
                projectCode: projectCode,
                qualityDrawingId: drawingId,
                imageData: imageData
            )
        }

        let k = key
        let existing = try context.fetch(
            FetchDescriptor<CachedPlanAsset>(predicate: #Predicate<CachedPlanAsset> { $0.cacheKey == k })
        )
        if let row = existing.first {
            if let written {
                if let oldPath = row.imageRelativePath, oldPath != written.relativePath {
                    try? FileManager.default.removeItem(at: fileURL(relativePath: oldPath))
                }
                row.imageRelativePath = written.relativePath
                row.imageByteCount = written.byteCount
                row.markerReferenceWidth = written.markerReferenceWidth
                row.markerReferenceHeight = written.markerReferenceHeight
            }
            row.drawingName = detail.drawing.name
            row.pointsJSON = pointsData
            row.pointCount = points.count
            row.cachedAt = Date()
        } else {
            context.insert(
                CachedPlanAsset(
                    cacheKey: key,
                    projectCode: projectCode,
                    qualityDrawingId: drawingId,
                    drawingName: detail.drawing.name,
                    imageRelativePath: written?.relativePath,
                    imageByteCount: written?.byteCount ?? 0,
                    pointsJSON: pointsData,
                    pointCount: points.count,
                    markerReferenceWidth: written?.markerReferenceWidth ?? 0,
                    markerReferenceHeight: written?.markerReferenceHeight ?? 0
                )
            )
        }
    }

    private static func rowHasCachedImage(_ row: CachedPlanAsset) -> Bool {
        loadUIImageFromRow(row) != nil
    }

    private static func fileURL(relativePath: String) -> URL {
        rootDirectory.appending(path: relativePath)
    }

    private static func diskPNGURL(projectCode: String, qualityDrawingId: String) -> URL {
        fileURL(relativePath: "\(projectCode)/\(qualityDrawingId).png")
    }

    private static func uiImageFromData(_ data: Data) -> UIImage? {
        if let img = UIImage(data: data) { return img }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func writePNG(image: UIImage, projectCode: String, qualityDrawingId: String) {
        let url = diskPNGURL(projectCode: projectCode, qualityDrawingId: qualityDrawingId)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = image.pngData() else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func isValidPlanBinary(_ data: Data) -> Bool {
        guard data.count > 64 else { return false }
        if data.starts(with: [0x25, 0x50, 0x44, 0x46]) { return true }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return true }
        if data.starts(with: [0xFF, 0xD8]) { return true }
        if data.starts(with: [0x3C, 0x21]) || data.starts(with: [0x7B]) { return false }
        return UIImage(data: data) != nil || PDFDocument(data: data) != nil
    }

    private static func removePlanFiles(
        projectCode: String,
        qualityDrawingId: String,
        relativePath: String?
    ) {
        if let rel = relativePath {
            try? FileManager.default.removeItem(at: fileURL(relativePath: rel))
        }
        try? FileManager.default.removeItem(at: diskPNGURL(projectCode: projectCode, qualityDrawingId: qualityDrawingId))
    }

    private static func writePlanImageFiles(
        projectCode: String,
        qualityDrawingId: String,
        imageData: Data
    ) async -> WrittenPlanImage? {
        guard isValidPlanBinary(imageData) else { return nil }
        let rel = "\(projectCode)/\(qualityDrawingId).plan"
        let fileURL = fileURL(relativePath: rel)
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try imageData.write(to: fileURL, options: .atomic)
        } catch {
            return nil
        }

        var markerW: Double = 0
        var markerH: Double = 0
        if let decoded = await FloorPlanRasterDecoder.decodeOffMainThread(from: imageData) {
            writePNG(image: decoded.image, projectCode: projectCode, qualityDrawingId: qualityDrawingId)
            markerW = Double(decoded.markerReferenceSize.width)
            markerH = Double(decoded.markerReferenceSize.height)
        } else if let raster = uiImageFromData(imageData) {
            writePNG(image: raster, projectCode: projectCode, qualityDrawingId: qualityDrawingId)
            markerW = Double(raster.size.width * raster.scale)
            markerH = Double(raster.size.height * raster.scale)
        }

        let pngURL = diskPNGURL(projectCode: projectCode, qualityDrawingId: qualityDrawingId)
        let displayable = FileManager.default.fileExists(atPath: pngURL.path)
            && (try? Data(contentsOf: pngURL))?.isEmpty == false

        return WrittenPlanImage(
            relativePath: rel,
            byteCount: Int64(imageData.count),
            markerReferenceWidth: markerW,
            markerReferenceHeight: markerH,
            displayable: displayable
        )
    }

    private static func materializeRaster(
        from imageData: Data,
        projectCode: String,
        qualityDrawingId: String
    ) -> (CGFloat, CGFloat)? {
        if let decoded = FloorPlanRasterDecoder.decode(from: imageData) {
            writePNG(image: decoded.image, projectCode: projectCode, qualityDrawingId: qualityDrawingId)
            return (decoded.markerReferenceSize.width, decoded.markerReferenceSize.height)
        }
        if let raster = uiImageFromData(imageData) {
            writePNG(image: raster, projectCode: projectCode, qualityDrawingId: qualityDrawingId)
            let w = raster.size.width * raster.scale
            let h = raster.size.height * raster.scale
            return (w, h)
        }
        return nil
    }

    private static func loadUIImageFromRow(_ row: CachedPlanAsset) -> (UIImage, CGSize)? {
        let pngURL = diskPNGURL(projectCode: row.projectCode, qualityDrawingId: row.qualityDrawingId)
        if let data = try? Data(contentsOf: pngURL), let img = uiImageFromData(data), !data.isEmpty {
            let ref = storedMarkerSize(row: row, image: img)
            return (img, ref)
        }
        guard let rel = row.imageRelativePath else { return nil }
        let planURL = fileURL(relativePath: rel)
        guard let data = try? Data(contentsOf: planURL), !data.isEmpty else { return nil }
        if materializeRaster(from: data, projectCode: row.projectCode, qualityDrawingId: row.qualityDrawingId) != nil,
           let pngData = try? Data(contentsOf: pngURL),
           let img = uiImageFromData(pngData) {
            return (img, storedMarkerSize(row: row, image: img))
        }
        if let img = uiImageFromData(data) {
            writePNG(image: img, projectCode: row.projectCode, qualityDrawingId: row.qualityDrawingId)
            return (img, storedMarkerSize(row: row, image: img))
        }
        return nil
    }

    private static func storedMarkerSize(row: CachedPlanAsset, image: UIImage) -> CGSize {
        if row.markerReferenceWidth > 0, row.markerReferenceHeight > 0 {
            return CGSize(width: row.markerReferenceWidth, height: row.markerReferenceHeight)
        }
        return CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    private static func planImageURLs(for file: DrawingFileDto?) -> (URL?, URL?) {
        guard let file else { return (nil, nil) }
        let full = URLResolver.absoluteAssetURL(file.url)
        let thumb = URLResolver.absoluteAssetURL(file.thumbnailUrl)
        let primary = full ?? thumb
        let fallback: URL?
        if let f = full, let t = thumb, f.absoluteString != t.absoluteString {
            fallback = (primary?.absoluteString == f.absoluteString) ? t : f
        } else {
            fallback = nil
        }
        return (primary, fallback)
    }

    private static func rows(projectCode: String, context: ModelContext) throws -> [CachedPlanAsset] {
        let pc = projectCode
        return try context.fetch(
            FetchDescriptor<CachedPlanAsset>(predicate: #Predicate<CachedPlanAsset> { $0.projectCode == pc })
        )
    }

    private static func cacheKey(projectCode: String, qualityDrawingId: String) -> String {
        "\(projectCode)|\(qualityDrawingId)"
    }

    // MARK: - 快取生命週期（登出／設定清除）

    /// 刪除所有 `CachedPlanAsset` 列並移除對應 `.plan`／`.png` 檔。
    static func deleteAllRowsAndAssociatedDiskFiles(context: ModelContext) throws {
        let all = try context.fetch(FetchDescriptor<CachedPlanAsset>())
        for row in all {
            removePlanFiles(
                projectCode: row.projectCode,
                qualityDrawingId: row.qualityDrawingId,
                relativePath: row.imageRelativePath
            )
            context.delete(row)
        }
    }

    /// 僅刪除指定專案之平面圖列與檔案。
    static func deleteAllRowsAndDiskFiles(forProjectCode projectCode: String, context: ModelContext) throws {
        for row in try rows(projectCode: projectCode, context: context) {
            removePlanFiles(
                projectCode: row.projectCode,
                qualityDrawingId: row.qualityDrawingId,
                relativePath: row.imageRelativePath
            )
            context.delete(row)
        }
    }

    /// 清空 `Caches/plan-assets` 目錄（處理孤立檔或登出後重置）。
    static func deleteEntireDiskCacheDirectory() {
        let root = rootDirectory
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
}
