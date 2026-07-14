import Foundation

enum AppCacheStorage {
  static let schemaVersion = 1
  static let rootComponents = ["tunedIn", "Cache"]
  static let fileProtection = FileProtectionType.complete
  static let protectedWriteOptions: Data.WritingOptions = [.atomic, .completeFileProtection]

  static func liveBaseDirectory(fileManager: FileManager = .default) throws -> URL {
    try fileManager.url(
      for: .cachesDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
  }

  static func prepareStructuredDirectory(
    environment: AppEnvironment,
    baseDirectory: URL,
    fileManager: FileManager = .default
  ) throws -> URL {
    try prepareEnvironmentDirectory(
      category: "Structured",
      environment: environment,
      baseDirectory: baseDirectory,
      fileManager: fileManager
    )
  }

  static func prepareMediaDirectory(
    environment: AppEnvironment,
    baseDirectory: URL,
    fileManager: FileManager = .default
  ) throws -> URL {
    try prepareEnvironmentDirectory(
      category: "Media",
      environment: environment,
      baseDirectory: baseDirectory,
      fileManager: fileManager
    )
  }

  static func structuredStoreURL(in directory: URL) -> URL {
    directory.appending(path: "ServerSnapshots.store", directoryHint: .notDirectory)
  }

  static func resetDirectory(
    _ directory: URL,
    fileManager: FileManager = .default
  ) throws {
    if fileManager.fileExists(atPath: directory.path) {
      try fileManager.removeItem(at: directory)
    }
    try prepareDirectory(directory, fileManager: fileManager)
  }

  static func prepareDirectory(
    _ directory: URL,
    fileManager: FileManager = .default
  ) throws {
    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    var protectedDirectory = directory
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try protectedDirectory.setResourceValues(values)
    try fileManager.setAttributes(
      [.protectionKey: fileProtection],
      ofItemAtPath: directory.path
    )
  }

  static func writeProtected(
    _ data: Data,
    to url: URL,
    fileManager: FileManager = .default
  ) throws {
    try data.write(to: url, options: protectedWriteOptions)
    var protectedURL = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try protectedURL.setResourceValues(values)
    try fileManager.setAttributes(
      [.protectionKey: fileProtection],
      ofItemAtPath: url.path
    )
  }

  private static func prepareEnvironmentDirectory(
    category: String,
    environment: AppEnvironment,
    baseDirectory: URL,
    fileManager: FileManager
  ) throws -> URL {
    let categoryDirectory = cacheRoot(in: baseDirectory)
      .appending(path: category, directoryHint: .isDirectory)
    try prepareDirectory(categoryDirectory, fileManager: fileManager)
    let environmentDirectory = categoryDirectory
      .appending(path: environment.rawValue, directoryHint: .isDirectory)

    for entry in try fileManager.contentsOfDirectory(
      at: categoryDirectory,
      includingPropertiesForKeys: nil
    ) where entry.lastPathComponent != environment.rawValue {
      try fileManager.removeItem(at: entry)
    }

    try prepareDirectory(environmentDirectory, fileManager: fileManager)
    return environmentDirectory
  }

  private static func cacheRoot(in baseDirectory: URL) -> URL {
    rootComponents.reduce(baseDirectory) { directory, component in
      directory.appending(path: component, directoryHint: .isDirectory)
    }
    .appending(path: "v\(schemaVersion)", directoryHint: .isDirectory)
  }
}
