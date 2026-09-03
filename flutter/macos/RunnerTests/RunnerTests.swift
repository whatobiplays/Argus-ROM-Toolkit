import Cocoa
import FlutterMacOS
import XCTest
@testable import argus

class RunnerTests: XCTestCase {

  func testBookmarkOptionsRetainFutureWriteCapability() {
    let options = MacOSLibraryFolderPicker.bookmarkCreationOptions

    XCTAssertTrue(options.contains(.withSecurityScope))
    XCTAssertFalse(options.contains(.securityScopeAllowOnlyReadAccess))
  }

  func testFolderPickerReturnsSelectedDirectoryAndOpaqueAuthorization() {
    let selectedURL = URL(fileURLWithPath: "/tmp/Argus Library")
    let panel = TestFolderPickerPanel(response: .OK, url: selectedURL)
    let engine = FlutterEngine(
      name: "RunnerTests",
      project: nil,
      allowHeadlessExecution: true
    )
    let picker = MacOSLibraryFolderPicker(
      binaryMessenger: engine.binaryMessenger,
      panelFactory: { panel },
      bookmarkDataProvider: { url in
        XCTAssertEqual(url, selectedURL)
        return Data([0xde, 0xad])
      }
    )

    var result: Any?
    var wasCalled = false
    picker.handle(
      call: FlutterMethodCall(methodName: "pickLibraryFolder", arguments: nil)
    ) {
      wasCalled = true
      result = $0
    }

    let response = result as? [String: Any]
    XCTAssertTrue(wasCalled)
    XCTAssertEqual(response?["path"] as? String, selectedURL.path)
    XCTAssertEqual(
      (response?["authorization"] as? FlutterStandardTypedData)?.data,
      Data([0xde, 0xad])
    )
    XCTAssertTrue(panel.canChooseDirectories)
    XCTAssertFalse(panel.canChooseFiles)
    XCTAssertFalse(panel.allowsMultipleSelection)
    XCTAssertFalse(panel.canCreateDirectories)
  }

  func testFolderPickerReturnsNilWhenThePanelIsCancelled() {
    let panel = TestFolderPickerPanel(response: .cancel, url: nil)
    let engine = FlutterEngine(
      name: "RunnerTests",
      project: nil,
      allowHeadlessExecution: true
    )
    let picker = MacOSLibraryFolderPicker(
      binaryMessenger: engine.binaryMessenger,
      panelFactory: { panel },
      bookmarkDataProvider: { _ in Data([0xde]) }
    )

    var result: Any?
    var wasCalled = false
    picker.handle(
      call: FlutterMethodCall(methodName: "pickLibraryFolder", arguments: nil)
    ) {
      wasCalled = true
      result = $0
    }

    XCTAssertTrue(wasCalled)
    XCTAssertTrue(result == nil || result is NSNull)
  }

  func testFolderPickerSanitizesBookmarkCreationFailure() {
    let selectedURL = URL(fileURLWithPath: "/tmp/Argus Library")
    let panel = TestFolderPickerPanel(response: .OK, url: selectedURL)
    let engine = FlutterEngine(
      name: "RunnerTests",
      project: nil,
      allowHeadlessExecution: true
    )
    let picker = MacOSLibraryFolderPicker(
      binaryMessenger: engine.binaryMessenger,
      panelFactory: { panel },
      bookmarkDataProvider: { _ in
        throw NSError(domain: "private", code: 17)
      }
    )

    var result: Any?
    picker.handle(
      call: FlutterMethodCall(methodName: "pickLibraryFolder", arguments: nil)
    ) {
      result = $0
    }

    let error = result as? FlutterError
    XCTAssertEqual(error?.code, "MACOS_FOLDER_AUTHORIZATION_UNAVAILABLE")
    XCTAssertNil(error?.message)
    XCTAssertNil(error?.details)
  }

}

private final class TestFolderPickerPanel: MacOSLibraryFolderPickerPanel {
  var canChooseDirectories = false
  var canChooseFiles = true
  var allowsMultipleSelection = true
  var canCreateDirectories = true
  let url: URL?
  private let response: NSApplication.ModalResponse

  init(response: NSApplication.ModalResponse, url: URL?) {
    self.response = response
    self.url = url
  }

  func begin(completionHandler: @escaping (NSApplication.ModalResponse) -> Void) {
    completionHandler(response)
  }
}
