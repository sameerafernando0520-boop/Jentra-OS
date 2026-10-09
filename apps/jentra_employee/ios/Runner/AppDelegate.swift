import Flutter
import UIKit
import PhotosUI
import ImageIO

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if #available(iOS 14, *), let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "EmployeePhotoPicker") {
      EmployeePhotoPicker.register(with: registrar)
    }
  }
}

// PHPicker shares only a selected image and needs no library-wide permission.
@available(iOS 14, *)
final class EmployeePhotoPicker: NSObject, FlutterPlugin, PHPickerViewControllerDelegate {
  private weak var registrar: FlutterPluginRegistrar?
  private var pending: FlutterResult?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = EmployeePhotoPicker()
    instance.registrar = registrar
    let channel = FlutterMethodChannel(name: "com.jentra.employee/profile-photo", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "choosePhoto" else { result(FlutterMethodNotImplemented); return }
    guard pending == nil else {
      result(FlutterError(code: "PHOTO_PICKER_BUSY", message: "A photo selector is already open.", details: nil)); return
    }
    guard #available(iOS 14, *), let presenter = registrar?.viewController else {
      result(FlutterError(code: "PHOTO_PICKER_FAILED", message: "Photo selection needs iOS 14 or later.", details: nil)); return
    }
    var configuration = PHPickerConfiguration()
    configuration.filter = .images
    configuration.selectionLimit = 1
    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = self
    pending = result
    presenter.present(picker, animated: true)
  }

  @available(iOS 14, *)
  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard let callback = pending else { return }
    pending = nil
    guard let provider = results.first?.itemProvider else { callback(nil); return }
    guard provider.hasItemConformingToTypeIdentifier("public.image") else {
      callback(FlutterError(code: "PHOTO_PICKER_FAILED", message: "Choose a readable photo.", details: nil)); return
    }
    provider.loadFileRepresentation(forTypeIdentifier: "public.image") { url, _ in
      guard let url = url,
            let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
        DispatchQueue.main.async { callback(FlutterError(code: "PHOTO_PICKER_FAILED", message: "The photo could not be read.", details: nil)) }; return
      }
      let sourceBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
      guard sourceBytes > 0, sourceBytes <= 8 * 1024 * 1024,
            width.intValue > 0, height.intValue > 0,
            width.intValue <= 8192, height.intValue <= 8192,
            width.intValue * height.intValue <= 20 * 1000 * 1000 else {
        DispatchQueue.main.async { callback(FlutterError(code: "PHOTO_TOO_LARGE", message: "Choose a smaller photo.", details: nil)) }; return
      }
      guard CGImageSourceGetCount(source) == 1,
            let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceThumbnailMaxPixelSize: 1024,
              kCGImageSourceCreateThumbnailWithTransform: true
            ] as CFDictionary) else {
        DispatchQueue.main.async { callback(FlutterError(code: "PHOTO_PICKER_FAILED", message: "Choose a still image.", details: nil)) }; return
      }
      let image = UIImage(cgImage: pixels)
      // Render a small upright square. The provider filename/EXIF never enters storage.
      let side = min(image.size.width, image.size.height)
      guard side > 0 else { DispatchQueue.main.async { callback(nil) }; return }
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      format.opaque = true
      let renderer = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format)
      let thumbnail = renderer.image { context in
        UIColor.white.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        let ratio = 256 / side
        image.draw(in: CGRect(x: (256 - image.size.width * ratio) / 2,
                              y: (256 - image.size.height * ratio) / 2,
                              width: image.size.width * ratio, height: image.size.height * ratio))
      }
      guard let jpeg = thumbnail.jpegData(compressionQuality: 0.85) else {
        DispatchQueue.main.async { callback(FlutterError(code: "PHOTO_PICKER_FAILED", message: "The photo could not be prepared.", details: nil)) }; return
      }
      DispatchQueue.main.async { callback(FlutterStandardTypedData(bytes: jpeg)) }
    }
  }
}
