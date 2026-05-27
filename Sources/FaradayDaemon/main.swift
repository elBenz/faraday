import FaradayCore
import Foundation

let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
let baseDirectory = homeDirectory.appendingPathComponent(".faraday", isDirectory: true)
let persistence = JSONFaradayPersistence(baseDirectoryURL: baseDirectory)
let core = FaradayCore(persistence: persistence)

print("Faraday daemon core started")
print("State: \(core.readStatus().sessionState) | Enforcement: \(core.readStatus().enforcementMode)")
print("Persistence directory: \(baseDirectory.path)")
print("Press Ctrl+C to stop")

RunLoop.main.run()
