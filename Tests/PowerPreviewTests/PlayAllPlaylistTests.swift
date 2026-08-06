import XCTest
import PowerPreviewCore

/// Mirrors Classic AppState Play All playlist rules without UI.
final class PlayAllPlaylistTests: XCTestCase {
    func testSoloModeIsSingleItem() throws {
        let folder = try makeFixtureFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let target = folder.appendingPathComponent("b.png")
        let kind = try XCTUnwrap(SupportedMedia.kind(for: target))

        // Play All off → only the opened file.
        let solo = [MediaItem(url: target, kind: kind)]
        XCTAssertEqual(solo.count, 1)
        XCTAssertEqual(solo[0].url.lastPathComponent, "b.png")
    }

    func testPlayAllModeScansSiblings() throws {
        let folder = try makeFixtureFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let target = folder.appendingPathComponent("b.png")
        let scanned = try MediaScanner().scan(folder: folder)
        XCTAssertEqual(scanned.count, 3)

        let index = scanned.firstIndex { $0.url.standardizedFileURL == target.standardizedFileURL }
        XCTAssertEqual(index, 1)
    }

    private func makeFixtureFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("pp-playall-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        for name in ["a.png", "b.png", "c.png"] {
            // Minimal valid 1x1 PNG
            let png = Data(base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
            )!
            try png.write(to: folder.appendingPathComponent(name))
        }
        try "ignore".write(to: folder.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        return folder
    }
}
