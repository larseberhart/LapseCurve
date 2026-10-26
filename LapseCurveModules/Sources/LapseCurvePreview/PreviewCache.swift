import Foundation

/// Bounded actor-isolated in-memory LRU cache for encoded preview images.
public actor PreviewCache {
    private struct Entry {
        let image: PreviewImage
        let cost: Int
        var accessSequence: UInt64
    }

    private let maximumEntryCount: Int
    private let maximumMemoryCostBytes: Int
    private let diskCacheDirectory: URL?
    private let maximumDiskCostBytes: Int
    private var entries: [PreviewCacheKey: Entry] = [:]
    private var currentMemoryCostBytes = 0
    private var accessSequence: UInt64 = 0

    /// Creates a cache with bounded memory and optional discardable disk storage.
    public init(
        maximumEntryCount: Int = 128,
        maximumMemoryCostBytes: Int = 128 * 1024 * 1024,
        diskCacheDirectory: URL? = nil,
        maximumDiskCostBytes: Int = 512 * 1024 * 1024
    ) {
        self.maximumEntryCount = max(0, maximumEntryCount)
        self.maximumMemoryCostBytes = max(0, maximumMemoryCostBytes)
        self.diskCacheDirectory = diskCacheDirectory ?? Self.defaultDiskCacheDirectory()
        self.maximumDiskCostBytes = max(0, maximumDiskCostBytes)
    }

    /// Looks up an image in memory or disk and refreshes its LRU access position.
    public func image(for key: PreviewCacheKey) -> PreviewImage? {
        if var entry = entries[key] {
            accessSequence &+= 1
            entry.accessSequence = accessSequence
            entries[key] = entry
            touchDiskEntry(for: key)
            return entry.image
        }

        guard let diskURL = diskURL(for: key),
              let diskData = try? Data(contentsOf: diskURL),
              let diskImage = try? PropertyListDecoder().decode(PreviewImage.self, from: diskData) else {
            return nil
        }
        insertMemory(diskImage, for: key)
        touchDiskEntry(for: key)
        return diskImage
    }

    /// Inserts an image into bounded memory and, when configured, disk storage.
    public func insert(_ image: PreviewImage, for key: PreviewCacheKey) {
        insertMemory(image, for: key)
        guard maximumDiskCostBytes > 0,
              let diskURL = diskURL(for: key) else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: diskURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let encodedImage = try encoder.encode(image)
            try encodedImage.write(to: diskURL, options: .atomic)
            evictDiskEntriesIfNeeded()
        } catch {
            return
        }
    }

    private func insertMemory(_ image: PreviewImage, for key: PreviewCacheKey) {
        guard maximumEntryCount > 0,
              maximumMemoryCostBytes > 0,
              image.data.count <= maximumMemoryCostBytes else {
            return
        }
        if let existingEntry = entries.removeValue(forKey: key) {
            currentMemoryCostBytes -= existingEntry.cost
        }
        accessSequence &+= 1
        let cost = image.data.count
        entries[key] = Entry(image: image, cost: cost, accessSequence: accessSequence)
        currentMemoryCostBytes += cost

        while entries.count > maximumEntryCount || currentMemoryCostBytes > maximumMemoryCostBytes {
            guard let leastRecentlyUsedKey = entries.min(by: {
                $0.value.accessSequence < $1.value.accessSequence
            })?.key,
            let removedEntry = entries.removeValue(forKey: leastRecentlyUsedKey) else {
                break
            }
            currentMemoryCostBytes -= removedEntry.cost
        }
    }

    private func diskURL(for key: PreviewCacheKey) -> URL? {
        diskCacheDirectory?.appendingPathComponent(key.diskFileName).appendingPathExtension("preview-cache")
    }

    private func touchDiskEntry(for key: PreviewCacheKey) {
        guard let diskURL = diskURL(for: key),
              FileManager.default.fileExists(atPath: diskURL.path) else {
            return
        }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: diskURL.path)
    }

    private func evictDiskEntriesIfNeeded() {
        guard let diskCacheDirectory, maximumDiskCostBytes > 0,
              let fileURLs = try? FileManager.default.contentsOfDirectory(
                at: diskCacheDirectory,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
            return
        }

        var fileEntries = fileURLs.compactMap { url -> (url: URL, size: Int, modified: Date)? in
            guard url.pathExtension == "preview-cache",
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize,
                  let modified = values.contentModificationDate else {
                return nil
            }
            return (url, size, modified)
        }
        var totalSize = fileEntries.reduce(0) { $0 + $1.size }
        fileEntries.sort { $0.modified < $1.modified }
        while totalSize > maximumDiskCostBytes, let oldest = fileEntries.first {
            try? FileManager.default.removeItem(at: oldest.url)
            totalSize -= oldest.size
            fileEntries.removeFirst()
        }
    }

    private static func defaultDiskCacheDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LapseCurve/FramePreviews", isDirectory: true)
    }

    /// Number of entries currently retained.
    public var count: Int { entries.count }

    /// Estimated encoded image memory cost currently retained.
    public var memoryCostBytes: Int { currentMemoryCostBytes }

        /// Number of disk entries currently retained, when disk caching is configured.
        public var diskEntryCount: Int {
                guard let diskCacheDirectory,
                            let fileURLs = try? FileManager.default.contentsOfDirectory(
                                at: diskCacheDirectory,
                                includingPropertiesForKeys: nil,
                                options: [.skipsHiddenFiles]
                            ) else {
                        return 0
                }
                return fileURLs.filter { $0.pathExtension == "preview-cache" }.count
        }

        /// Encoded disk cache cost currently retained.
        public var diskCostBytes: Int {
                guard let diskCacheDirectory,
                            let fileURLs = try? FileManager.default.contentsOfDirectory(
                                at: diskCacheDirectory,
                                includingPropertiesForKeys: [.fileSizeKey],
                                options: [.skipsHiddenFiles]
                            ) else {
                        return 0
                }
                return fileURLs.reduce(0) { total, url in
                        guard url.pathExtension == "preview-cache",
                                    let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                                return total
                        }
                        return total + size
                }
        }
}