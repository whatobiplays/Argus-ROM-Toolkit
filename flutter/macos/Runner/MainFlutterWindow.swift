import Cocoa
import FlutterMacOS

protocol MacOSLibraryFolderPickerPanel: AnyObject {
  var canChooseDirectories: Bool { get set }
  var canChooseFiles: Bool { get set }
  var allowsMultipleSelection: Bool { get set }
  var canCreateDirectories: Bool { get set }
  var url: URL? { get }
  func begin(completionHandler: @escaping (NSApplication.ModalResponse) -> Void)
}

private final class AppKitLibraryFolderPickerPanel: MacOSLibraryFolderPickerPanel {
  private let panel: NSOpenPanel

  init(panel: NSOpenPanel = NSOpenPanel()) {
    self.panel = panel
  }

  var canChooseDirectories: Bool {
    get { panel.canChooseDirectories }
    set { panel.canChooseDirectories = newValue }
  }

  var canChooseFiles: Bool {
    get { panel.canChooseFiles }
    set { panel.canChooseFiles = newValue }
  }

  var allowsMultipleSelection: Bool {
    get { panel.allowsMultipleSelection }
    set { panel.allowsMultipleSelection = newValue }
  }

  var canCreateDirectories: Bool {
    get { panel.canCreateDirectories }
    set { panel.canCreateDirectories = newValue }
  }

  var url: URL? { panel.url }

  func begin(completionHandler: @escaping (NSApplication.ModalResponse) -> Void) {
    panel.begin(completionHandler: completionHandler)
  }
}

final class MacOSLibraryFolderPicker {
  static let channelName = "argus/macos_library_folder_picker"

  static let bookmarkCreationOptions: URL.BookmarkCreationOptions = [
    .withSecurityScope,
  ]

  private let channel: FlutterMethodChannel
  private let panelFactory: () -> MacOSLibraryFolderPickerPanel
  private let bookmarkDataProvider: (URL) throws -> Data

  init(
    binaryMessenger: FlutterBinaryMessenger,
    panelFactory: @escaping () -> MacOSLibraryFolderPickerPanel = {
      AppKitLibraryFolderPickerPanel()
    },
    bookmarkDataProvider: @escaping (URL) throws -> Data = { url in
      try url.bookmarkData(
        options: MacOSLibraryFolderPicker.bookmarkCreationOptions,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
    }
  ) {
    self.panelFactory = panelFactory
    self.bookmarkDataProvider = bookmarkDataProvider
    channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
#if DEBUG
    if call.method == "createSecurityScopedBookmarkForTesting" {
      guard let path = call.arguments as? String else {
        result(
          FlutterError(
            code: "MACOS_FOLDER_AUTHORIZATION_UNAVAILABLE",
            message: nil,
            details: nil
          )
        )
        return
      }
      do {
        let bookmark = try bookmarkDataProvider(URL(fileURLWithPath: path))
        result(FlutterStandardTypedData(bytes: bookmark))
      } catch {
        result(
          FlutterError(
            code: "MACOS_FOLDER_AUTHORIZATION_UNAVAILABLE",
            message: nil,
            details: nil
          )
        )
      }
      return
    }
#endif

    guard call.method == "pickLibraryFolder" else {
      result(FlutterMethodNotImplemented)
      return
    }

    let panel = panelFactory()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.begin { response in
      guard response == .OK, let url = panel.url else {
        result(nil)
        return
      }
      do {
        let bookmark = try self.bookmarkDataProvider(url)
        result([
          "path": url.path,
          "authorization": FlutterStandardTypedData(bytes: bookmark),
        ])
      } catch {
        result(
          FlutterError(
            code: "MACOS_FOLDER_AUTHORIZATION_UNAVAILABLE",
            message: nil,
            details: nil
          )
        )
      }
    }
  }
}

class MainFlutterWindow: NSWindow {
  private var macosLibraryFolderPicker: MacOSLibraryFolderPicker?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    macosLibraryFolderPicker = MacOSLibraryFolderPicker(
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    super.awakeFromNib()
  }
}
