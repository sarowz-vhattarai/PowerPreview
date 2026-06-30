import XCTest
@testable import PowerPreviewCore

final class MediaScannerTests: XCTestCase {
    private var temporaryFolder: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PowerPreviewTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryFolder)
        temporaryFolder = nil
        try super.tearDownWithError()
    }

    func testScanKeepsSupportedMediaAndSortsLikeFinder() throws {
        try touch("clip10.mkv")
        try touch("clip2.mp4")
        try touch("image1.jpg")
        try touch("notes.txt")
        try touch(".hidden.png")

        let items = try MediaScanner().scan(folder: temporaryFolder)

        XCTAssertEqual(items.map(\.displayName), ["clip2.mp4", "clip10.mkv", "image1.jpg"])
        XCTAssertEqual(items.map(\.kind), [.video, .video, .image])
    }

    func testSupportedMediaDetectionIsCaseInsensitive() throws {
        XCTAssertEqual(SupportedMedia.kind(for: URL(fileURLWithPath: "/tmp/photo.HEIC")), .image)
        XCTAssertEqual(SupportedMedia.kind(for: URL(fileURLWithPath: "/tmp/movie.WEBM")), .video)
        XCTAssertNil(SupportedMedia.kind(for: URL(fileURLWithPath: "/tmp/readme.md")))
    }

    private func touch(_ name: String) throws {
        let url = temporaryFolder.appendingPathComponent(name)
        try Data().write(to: url)
    }
}
