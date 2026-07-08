import XCTest
@testable import SwitchboardLocal

@MainActor
final class LocalModelTests: XCTestCase {

    private var temporaryDirectory: URL!

    override func setUp() async throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    private func makeModel(directoryName: String? = nil) -> LocalModel {
        LocalModel(
            huggingFaceRepoID: "mlx-community/Fixture-Model-4bit",
            displayName: "Fixture Model",
            storageDirectory: temporaryDirectory,
            directoryName: directoryName
        )
    }

    func testInitialStateIsNotDownloadedWhenNothingOnDisk() {
        XCTAssertEqual(makeModel().state, .notDownloaded)
    }

    func testInitialStateIsDownloadedWhenCompletionMarkerExists() throws {
        let modelDirectory = temporaryDirectory.appendingPathComponent("mlx-community_Fixture-Model-4bit")
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent(".complete").path, contents: nil)

        XCTAssertEqual(makeModel().state, .downloaded)
    }

    func testModelDirectorySanitizesRepositoryID() {
        XCTAssertEqual(
            makeModel().modelDirectory,
            temporaryDirectory.appendingPathComponent("mlx-community_Fixture-Model-4bit")
        )
    }

    func testModelDirectoryHonorsDirectoryNameOverride() {
        XCTAssertEqual(
            makeModel(directoryName: "LegacyDirectory").modelDirectory,
            temporaryDirectory.appendingPathComponent("LegacyDirectory")
        )
    }

    func testDownloadIsIgnoredWhenAlreadyDownloaded() throws {
        let modelDirectory = temporaryDirectory.appendingPathComponent("mlx-community_Fixture-Model-4bit")
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent(".complete").path, contents: nil)

        let model = makeModel()
        model.download()

        XCTAssertEqual(model.state, .downloaded)
    }

    func testDeleteRemovesModelDirectoryAndResetsState() throws {
        let modelDirectory = temporaryDirectory.appendingPathComponent("mlx-community_Fixture-Model-4bit")
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: modelDirectory.appendingPathComponent(".complete").path, contents: nil)

        let model = makeModel()
        model.delete()

        XCTAssertEqual(model.state, .notDownloaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: modelDirectory.path))
    }

    func testReassemblePartFilesConcatenatesInOrderAndRemovesParts() throws {
        let directory = temporaryDirectory.appendingPathComponent("parts")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("alpha".utf8).write(to: directory.appendingPathComponent("model.safetensors.part1"))
        try Data("beta".utf8).write(to: directory.appendingPathComponent("model.safetensors.part2"))

        try LocalModel.reassemblePartFiles(in: directory)

        let reassembled = try Data(contentsOf: directory.appendingPathComponent("model.safetensors"))
        XCTAssertEqual(String(decoding: reassembled, as: UTF8.self), "alphabeta")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("model.safetensors.part1").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("model.safetensors.part2").path))
    }
}
