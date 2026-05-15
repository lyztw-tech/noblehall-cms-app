import PDFKit
import UIKit

@MainActor
enum FloorPlanRasterDecoder {
    private static let pdfScale: CGFloat = 2

    static func decode(from data: Data, maxPixel: CGFloat = 3200) -> (image: UIImage, markerReferenceSize: CGSize)? {
        if let raster = UIImage(data: data) {
            let w = raster.size.width * raster.scale
            let h = raster.size.height * raster.scale
            guard w > 1, h > 1 else { return nil }
            return (raster, CGSize(width: w, height: h))
        }
        guard let doc = PDFDocument(data: data), let page = doc.page(at: 0) else { return nil }
        let rect = page.bounds(for: .mediaBox)
        guard rect.width > 1, rect.height > 1 else { return nil }
        let refW = rect.width * pdfScale
        let refH = rect.height * pdfScale
        let shrink = min(1, maxPixel / refW, maxPixel / refH)
        let renderScale = pdfScale * shrink
        let size = CGSize(width: rect.width * renderScale, height: rect.height * renderScale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.saveGState()
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: renderScale, y: -renderScale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
            ctx.cgContext.restoreGState()
        }
        return (img, CGSize(width: refW, height: refH))
    }

    /// 大型 PDF 解碼須在主執行緒（UIKit／PDFKit）；由 async 切入 MainActor，避免在背景閉包直接呼叫。
    static func decodeOffMainThread(from data: Data, maxPixel: CGFloat = 3200) async -> (image: UIImage, markerReferenceSize: CGSize)? {
        await MainActor.run {
            decode(from: data, maxPixel: maxPixel)
        }
    }

    /// 暫存未存 marker 尺寸時，依點位推算與後端一致的參考畫布大小。
    static func effectiveMarkerReferenceSize(
        points: [QualityTaskRoomPointDto],
        stored: CGSize
    ) -> CGSize {
        if stored.width > 1, stored.height > 1 { return stored }
        guard !points.isEmpty else { return CGSize(width: 1600, height: 1200) }
        let maxX = points.map(\.x).max() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        return CGSize(width: max(maxX * 1.1, 800), height: max(maxY * 1.1, 600))
    }

    /// 離線僅有座標、無圖檔時的灰色底圖（維持點位比例）。
    static func placeholderCanvas(markerReferenceSize: CGSize) -> UIImage {
        let w = max(markerReferenceSize.width, 400)
        let h = max(markerReferenceSize.height, 300)
        let size = CGSize(width: w, height: h)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(white: 0.93, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
