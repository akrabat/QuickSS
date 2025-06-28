import Cocoa
import Foundation

let version = "1.0.0"

// MARK: - Error Types

enum ScreenshotError: Error, LocalizedError {
    case unableToGetWindowList
    case noActiveWindowFound
    case screencaptureCommandFailed(status: Int32)
    case processExecutionFailed(Error)
    case invalidArguments(String)
    case conflictingOptions(String)
    
    var errorDescription: String? {
        switch self {
        case .unableToGetWindowList:
            return "Unable to retrieve the list of windows"
        case .noActiveWindowFound:
            return "No active window found to capture"
        case .screencaptureCommandFailed(let status):
            return "Screenshot capture failed with exit code \(status)"
        case .processExecutionFailed(let error):
            return "Failed to execute screenshot command: \(error.localizedDescription)"
        case .invalidArguments(let message):
            return "Invalid arguments: \(message)"
        case .conflictingOptions(let message):
            return "Conflicting options: \(message)"
        }
    }
}

// MARK: - Helper Functions

func printHelp() {
    print("""
QuickSS v\(version) - Capture screenshot of the active window

USAGE:
    quickss [OPTIONS]

OPTIONS:
    --file <filename>   Specify custom filename for the screenshot
    --clipboard         Copy screenshot to clipboard instead of saving to file
    -h, --help          Show this help message

EXAMPLES:
    quickss
    quickss --file "my-screenshot.png"
    quickss --file "/path/to/custom/screenshot.png"
    quickss --clipboard

The screenshot will be saved to ~/Downloads/ by default.
""")
}

func parseArguments() throws -> (customFilename: String?, shouldShowHelp: Bool, toClipboard: Bool) {
    let args = CommandLine.arguments
    var customFilename: String? = nil
    var shouldShowHelp = false
    var toClipboard = false
    
    var i = 1
    while i < args.count {
        let arg = args[i]
        
        if arg == "-h" || arg == "--help" {
            shouldShowHelp = true
            break
        } else if arg == "--file" {
            guard i + 1 < args.count else {
                throw ScreenshotError.invalidArguments("--file requires a filename argument")
            }
            customFilename = args[i + 1]
            i += 1
        } else if arg == "--clipboard" {
            toClipboard = true
        } else {
            throw ScreenshotError.invalidArguments("Unknown argument '\(arg)'. Use -h or --help for usage information")
        }
        
        i += 1
    }
    
    // Validate conflicting options
    if toClipboard && customFilename != nil {
        throw ScreenshotError.conflictingOptions("--clipboard and --file cannot be used together")
    }
    
    return (customFilename, shouldShowHelp, toClipboard)
}

func getScreenshotFilePath(customFilename: String?) -> URL {
    if let customFilename = customFilename {
        return URL(fileURLWithPath: customFilename)
    } else {
        // Default timestamp-based filename
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let downloadsURL = homeURL.appendingPathComponent("Downloads")
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let timestamp = formatter.string(from: Date())
        let filename = "Screenshot \(timestamp).png"
        return downloadsURL.appendingPathComponent(filename)
    }
}

// MARK: - Screenshot Functions

func getActiveWindowID() throws -> CGWindowID {
    guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        throw ScreenshotError.unableToGetWindowList
    }

    // Find the first window in layer 0 as this is the active window
    for windowInfo in windowList {
        guard let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
              let windowLayer = windowInfo[kCGWindowLayer as String] as? Int,
              let title = windowInfo[kCGWindowName as String] as? String,
              let ownerName = windowInfo[kCGWindowOwnerName as String] as? String
        else {
            continue
        }
        
        if windowLayer == 0 {
            print("Capturing window ID: \(windowID) [\(ownerName): '\(title)']")
            return windowID
        }
    }
    
    throw ScreenshotError.noActiveWindowFound
}

@MainActor
func takeActiveWindowScreenshot(windowID: CGWindowID, screenshotURL: URL?) async throws {
    // Run `screencapture` to capture the window
    let task = Process()
    task.launchPath = "/usr/sbin/screencapture"
    if let screenshotURL = screenshotURL {
        // Save to file
        task.arguments = ["-x", "-l", String(windowID), screenshotURL.path]
    } else {
        // Copy to clipboard
        task.arguments = ["-x", "-l", String(windowID), "-c"]
    }
    
    do {
        try task.run()
        task.waitUntilExit()
        
        guard task.terminationStatus == 0 else {
            throw ScreenshotError.screencaptureCommandFailed(status: task.terminationStatus)
        }
        
        if screenshotURL != nil {
            print("Screenshot saved to: \(screenshotURL!.path)")
        } else {
            print("Screenshot copied to clipboard")
        }
        
    } catch let error as ScreenshotError {
        throw error
    } catch {
        throw ScreenshotError.processExecutionFailed(error)
    }
}

// MARK: - Main Execution

func main() async {
    do {
        let (customFilename, shouldShowHelp, toClipboard) = try parseArguments()

        if shouldShowHelp {
            printHelp()
            exit(0)
        }

        let windowID = try getActiveWindowID()
        let screenshotURL = toClipboard ? nil : getScreenshotFilePath(customFilename: customFilename)
        try await takeActiveWindowScreenshot(windowID: windowID, screenshotURL: screenshotURL)
        exit(0)
        
    } catch {
        print("Error: \(error.localizedDescription)")
        exit(1)
    }
}

// Entry point
Task { @MainActor in
    await main()
}

RunLoop.main.run()
