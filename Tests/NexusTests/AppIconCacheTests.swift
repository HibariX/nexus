import Testing
@testable import Nexus

@Suite struct AppIconCacheTests {
    @Test func rasterizesToGridSize() async throws {
        let icon = try #require(await AppIconCache.shared.icon(forFile: #filePath))
        #expect(
            AppIconCache.renderedPixelSize
                == Int(AppIconCache.renderedPointSize * AppIconCache.displayScale)
        )
        #expect(icon.width == AppIconCache.renderedPixelSize)
        #expect(icon.height == AppIconCache.renderedPixelSize)
    }
}
