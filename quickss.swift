import Cocoa
import CoreImage
import Foundation
import UniformTypeIdentifiers

let version = "1.2.0"

// MARK: - Types

enum ScreenshotError: Error, LocalizedError {
    case unableToGetWindowList
    case noActiveWindowFound
    case screencaptureCommandFailed(status: Int32)
    case processExecutionFailed(Error)
    case invalidArguments(String)
    case conflictingOptions(String)
    case imageLoadingFailed(String)
    case filePathValidationFailed(String)
    case screenshotCancelled
    
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
        case .imageLoadingFailed(let message):
            return "Image loading failed: \(message)"
        case .filePathValidationFailed(let message):
            return "File validation failed: \(message)"
        case .screenshotCancelled:
            return "Screenshot cancelled by user"
        }
    }
}

struct Arguments {
    let customFilename: String?
    let shouldShowHelp: Bool
    let toClipboard: Bool
    let shouldResize: Bool
    let quietMode: Bool
    let interactiveMode: Bool
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
    --interactive       Interactive mode: select area/window to capture
    --no-resize         Keep original retina resolution (default is to resize for smaller files)
    -q, --quiet         Quiet mode: only output filename or clipboard message
    -h, --help          Show this help message

EXAMPLES:
    quickss
    quickss --file "my-screenshot.png"
    quickss --file "/path/to/custom/screenshot.png"
    quickss --interactive
    quickss --interactive --clipboard
    quickss --no-resize
    quickss --clipboard
    quickss --clipboard --no-resize

The screenshot will be saved to ~/Downloads/ by default.
""")
}

func parseArguments() throws -> Arguments {
    let args = CommandLine.arguments
    var customFilename: String? = nil
    var shouldShowHelp = false
    var toClipboard = false
    var shouldResize = true
    var quietMode = false
    var interactiveMode = false
    
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
        } else if arg == "--no-resize" {
            shouldResize = false
        } else if arg == "--quiet" || arg == "-q" {
            quietMode = true
        } else if arg == "--interactive" {
            interactiveMode = true
        } else {
            throw ScreenshotError.invalidArguments("Unknown argument '\(arg)'. Use -h or --help for usage information")
        }
        
        i += 1
    }
    
    // Validate conflicting options
    if toClipboard && customFilename != nil {
        throw ScreenshotError.conflictingOptions("--clipboard and --file cannot be used together")
    }
    
    return Arguments(
        customFilename: customFilename,
        shouldShowHelp: shouldShowHelp,
        toClipboard: toClipboard,
        shouldResize: shouldResize,
        quietMode: quietMode,
        interactiveMode: interactiveMode
    )
}

func validateFilePath(_ filePath: URL) throws {
    let fileManager = FileManager.default
    let parentDirectory = filePath.deletingLastPathComponent()
    
    // Check if parent directory exists and is a directory
    guard fileManager.fileExists(atPath: parentDirectory.path) else {
        throw ScreenshotError.filePathValidationFailed("Directory does not exist: \(parentDirectory.path)")
    }
    
    let resourceValues = try parentDirectory.resourceValues(forKeys: [.isDirectoryKey])
    guard resourceValues.isDirectory == true else {
        throw ScreenshotError.filePathValidationFailed("Path is not a directory: \(parentDirectory.path)")
    }
    
    // Check if parent directory is writable
    if !fileManager.isWritableFile(atPath: parentDirectory.path) {
        throw ScreenshotError.filePathValidationFailed("Directory is not writable: \(parentDirectory.path)")
    }
    
    // If file already exists, check if it's writable
    if fileManager.fileExists(atPath: filePath.path) {
        if !fileManager.isWritableFile(atPath: filePath.path) {
            throw ScreenshotError.filePathValidationFailed("File is not writable: \(filePath.path)")
        }
    }
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
        let filename = "\(timestamp) Screenshot.png"
        return downloadsURL.appendingPathComponent(filename)
    }
}

// MARK: - Image Processing Functions

func resizeImageIfRetina(cgImage: CGImage, screen: NSScreen?) -> CGImage {
    // Use the provided screen, fall back to main screen if none provided
    let targetScreen = screen ?? NSScreen.main
    guard let actualScreen = targetScreen else { return cgImage }
    
    let scaleFactor = actualScreen.backingScaleFactor
    guard scaleFactor > 1.0 else { return cgImage }

    // Resize using Lanczos filter
    let inputImage = CIImage(cgImage: cgImage)
    
    guard let lanczosFilter = CIFilter(name: "CILanczosScaleTransform") else {
        return cgImage
    }
    lanczosFilter.setValue(inputImage, forKey: kCIInputImageKey)
    lanczosFilter.setValue(1.0 / scaleFactor, forKey: kCIInputScaleKey)
    lanczosFilter.setValue(1.0, forKey: kCIInputAspectRatioKey)

    let context = CIContext()
    guard let outputImage = lanczosFilter.outputImage,
          let cgOutput = context.createCGImage(outputImage, from: outputImage.extent) else {
        return cgImage
    }

    return cgOutput
}

func processImage(tempURL: URL, outputURL: URL?, toClipboard: Bool, shouldResize: Bool, screen: NSScreen?) async throws {
    // Load the image
    guard let imageData = try? Data(contentsOf: tempURL) else {
        throw ScreenshotError.imageLoadingFailed("Failed to read temp image file from \(tempURL.path)")
    }
    
    guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil) else {
        throw ScreenshotError.imageLoadingFailed("Failed to create image source from data")
    }
    
    guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        throw ScreenshotError.imageLoadingFailed("Failed to create CGImage from image source")
    }
    
    // Resize if on retina display and resize is enabled
    let processedImage = shouldResize ? resizeImageIfRetina(cgImage: cgImage, screen: screen) : cgImage
    
    // Convert to PNG data
    let mutableData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(mutableData, UTType.png.identifier as CFString, 1, nil) else {
        throw ScreenshotError.imageLoadingFailed("Failed to create image destination")
    }
    
    CGImageDestinationAddImage(destination, processedImage, nil)
    CGImageDestinationFinalize(destination)
    
    if toClipboard {
        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(mutableData as Data, forType: .png)
    } else if let outputURL = outputURL {
        // Save to file
        try (mutableData as Data).write(to: outputURL)
    }
    
    // Clean up temp file - silently ignore errors as cleanup failure is non-critical
    try? FileManager.default.removeItem(at: tempURL)
}

// MARK: - Screenshot Functions

func getActiveWindowInfo(quietMode: Bool) throws -> (windowID: CGWindowID, screen: NSScreen?) {
    guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        throw ScreenshotError.unableToGetWindowList
    }

    // Find the first window in layer 0 as this is the active window
    for windowInfo in windowList {
        guard let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
              let windowLayer = windowInfo[kCGWindowLayer as String] as? Int,
              let title = windowInfo[kCGWindowName as String] as? String,
              let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
              let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any]
        else {
            continue
        }
        
        if windowLayer == 0 {
            if !quietMode {
                print("Capturing window ID: \(windowID) [\(ownerName): '\(title)']")
            }
            
            // Find the screen containing this window
            let windowBounds = CGRect(
                x: boundsDict["X"] as? CGFloat ?? 0,
                y: boundsDict["Y"] as? CGFloat ?? 0,
                width: boundsDict["Width"] as? CGFloat ?? 0,
                height: boundsDict["Height"] as? CGFloat ?? 0
            )
            
            let windowScreen = NSScreen.screens.first { screen in
                screen.frame.intersects(windowBounds)
            }
            
            return (windowID, windowScreen)
        }
    }
    
    throw ScreenshotError.noActiveWindowFound
}

@MainActor
func takeScreenshot(windowID: CGWindowID?, screenshotURL: URL?, shouldResize: Bool, screen: NSScreen?, quietMode: Bool) async throws {
    // Always capture to temp file first for processing
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("quickss_temp.png")
    
    let task = Process()
    task.launchPath = "/usr/sbin/screencapture"
    
    if let windowID = windowID {
        // we have a window ID, use it for capturing
        task.arguments = ["-x", "-l", String(windowID), tempURL.path]
    } else {
        // No window ID provided, use interactive mode
        task.arguments = ["-x", "-i", tempURL.path]
    }
    
    do {
        try task.run()
        task.waitUntilExit()
        
        guard task.terminationStatus == 0 else {
            throw ScreenshotError.screencaptureCommandFailed(status: task.terminationStatus)
        }
        
        // Check if temp file was created (user might have cancelled with escape)
        guard FileManager.default.fileExists(atPath: tempURL.path) else {
            throw ScreenshotError.screenshotCancelled
        }
        
        // Process the image (resize if retina and enabled) and save/copy as needed
        let toClipboard = screenshotURL == nil
        try await processImage(tempURL: tempURL, outputURL: screenshotURL, toClipboard: toClipboard, shouldResize: shouldResize, screen: screen)
        
        if let screenshotURL = screenshotURL {
            if quietMode {
                print(screenshotURL.path)
            } else {
                print("Screenshot saved to: \(screenshotURL.path)")
            }
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
        let options = try parseArguments()

        if options.shouldShowHelp {
            printHelp()
            exit(0)
        }

        let screenshotURL = options.toClipboard ? nil : getScreenshotFilePath(customFilename: options.customFilename)
        // Validate file path if not copying to clipboard
        if let screenshotURL = screenshotURL {
            try validateFilePath(screenshotURL)
        }
        
        if options.interactiveMode {
            // Interactive mode: use screencapture -i, no need to find active window
            try await takeScreenshot(windowID: nil, screenshotURL: screenshotURL, shouldResize: options.shouldResize, screen: nil, quietMode: options.quietMode)
        } else {
            // Standard mode: find the active window and capture it
            let (windowID, windowScreen) = try getActiveWindowInfo(quietMode: options.quietMode)
            try await takeScreenshot(windowID: windowID, screenshotURL: screenshotURL, shouldResize: options.shouldResize, screen: windowScreen, quietMode: options.quietMode)
        }
        
        exit(0)
        
    } catch let error as ScreenshotError {
        if case .screenshotCancelled = error {
            // User cancelled - exit silently with success code
            exit(0)
        }
        print("Error: \(error.localizedDescription)")
        exit(1)
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
