import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    ClipboardImageChannel.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

/// Answers the Dart side's `writeImage` call by putting the PNG on the
/// general pasteboard; the channel name is owned by the Dart seam in
/// `clipboard_image_writer_io.dart`.
enum ClipboardImageChannel {
  static let name = "top.npcserver.slimm/clipboard_image"

  static func register(with messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: name, binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "writeImage" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard let data = (call.arguments as? FlutterStandardTypedData)?.data,
          let image = NSImage(data: data)
        else {
          result(FlutterError(code: "write_failed", message: "The image could not be copied.", details: nil))
          return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        result(pasteboard.writeObjects([image]) ? nil : FlutterError(
          code: "write_failed", message: "The image could not be copied.", details: nil))
      }
  }
}
