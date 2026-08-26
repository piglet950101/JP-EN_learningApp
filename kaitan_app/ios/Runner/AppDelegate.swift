import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Matches the channel name in lib/data/progress/progress_db.dart.
  private static let backupChannelName = "jp.or.kai.kaitan/backup"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerBackupChannel(with: engineBridge.binaryMessenger)
  }

  /// Marks a file so iOS leaves it out of iCloud and iTunes/Finder backups.
  ///
  /// progress.db carries the unlock flag alongside the learning record, and
  /// everything under Documents/ is backed up by default. Without this, a
  /// reinstall — or a restore onto a second device — brings the unlock back
  /// with it. Android is already closed off declaratively via
  /// allowBackup="false"; this is the iOS half of the same decision.
  private func registerBackupChannel(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: AppDelegate.backupChannelName, binaryMessenger: messenger)

    channel.setMethodCallHandler { call, result in
      guard call.method == "excludeFromBackup" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let path = args["path"] as? String
      else {
        result(FlutterError(code: "bad_args",
                            message: "expected a 'path' string", details: nil))
        return
      }
      guard FileManager.default.fileExists(atPath: path) else {
        // Nothing to flag yet; the next launch will catch it.
        result(false)
        return
      }
      var url = URL(fileURLWithPath: path)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      do {
        try url.setResourceValues(values)
        result(true)
      } catch {
        result(FlutterError(code: "exclude_failed",
                            message: error.localizedDescription, details: nil))
      }
    }
  }
}
