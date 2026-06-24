import Foundation

actor FolderWatcher {
    private var watchedPaths: [String: DispatchSourceFileSystemObject] = [:]
    private var processedFiles: Set<String> = []
    private let engine: VisionOCREngine

    init(engine: VisionOCREngine) {
        self.engine = engine
    }

    func watch(folder path: String) throws -> String {
        let expandedPath = (path as NSString).expandingTildeInPath

        guard FileManager.default.isDirectory(atPath: expandedPath) else {
            throw OCRError.fileNotFound(path: expandedPath)
        }

        if watchedPaths[expandedPath] != nil {
            return "Already watching: \(expandedPath)"
        }

        let fd = open(expandedPath, O_EVTONLY)
        guard fd >= 0 else {
            throw OCRError.recognitionFailed(reason: "Cannot open directory for watching")
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task {
                await self.scanNewFiles(in: expandedPath)
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        watchedPaths[expandedPath] = source

        Task {
            await scanNewFiles(in: expandedPath)
        }

        return "Watching folder: \(expandedPath)"
    }

    func stopWatching(folder path: String) {
        let expandedPath = (path as NSString).expandingTildeInPath
        if let source = watchedPaths.removeValue(forKey: expandedPath) {
            source.cancel()
        }
    }

    func getWatchedFolders() -> [String] {
        Array(watchedPaths.keys)
    }

    private func scanNewFiles(in directory: String) {
        let supportedExtensions = VisionOCREngine.supportedImageExtensions.union(["pdf"])

        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return
        }

        for file in files {
            let fullPath = "\(directory)/\(file)"
            let ext = (file as NSString).pathExtension.lowercased()

            guard supportedExtensions.contains(ext),
                  !processedFiles.contains(fullPath) else {
                continue
            }

            processedFiles.insert(fullPath)

            Task {
                do {
                    let result = try await engine.recognize(filePath: fullPath, pages: nil)
                    let outputPath = "\(fullPath).ocr.txt"
                    try result.text.write(toFile: outputPath, atomically: true, encoding: .utf8)
                } catch {
                    // silently skip failed files
                }
            }
        }
    }
}
