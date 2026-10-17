import Cocoa
import FlutterMacOS
import AVFoundation

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let window = mainFlutterWindow,
       let controller = window.contentViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.easyviolin.easy_violin/audio_decoder",
        binaryMessenger: controller.engine.binaryMessenger
      )
      
      channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "decodeAudioFile" || call.method == "decodeToWav" {
          guard let args = call.arguments as? [String: Any],
                let flutterData = args["audioBytes"] as? FlutterStandardTypedData else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing audioBytes", details: nil))
            return
          }
          let targetRate = (args["targetSampleRate"] as? Double) ?? 22050.0
          
          DispatchQueue.global(qos: .userInitiated).async {
            do {
              let data = flutterData.data
              let ext: String
              if data.count >= 4 && data.starts(with: [0x52, 0x49, 0x46, 0x46]) {
                ext = "wav"
              } else if (data.count >= 3 && data.starts(with: [0x49, 0x44, 0x33])) ||
                        (data.count >= 2 && data[0] == 0xFF && (data[1] & 0xE0) == 0xE0) {
                ext = "mp3"
              } else if data.count >= 2 && data[0] == 0xFF && (data[1] & 0xF0) == 0xF0 {
                ext = "aac"
              } else if data.count >= 8 && data[4...7] == Data([0x66, 0x74, 0x79, 0x70]) {
                ext = "m4a"
              } else if data.count >= 4 && data.starts(with: [0x66, 0x4C, 0x61, 0x43]) {
                ext = "flac"
              } else if data.count >= 4 && data.starts(with: [0x4F, 0x67, 0x67, 0x53]) {
                ext = "ogg"
              } else {
                ext = "mp3"
              }

              let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("easy_violin_dec_\(UUID().uuidString).\(ext)")
              try data.write(to: tempUrl)
              defer { try? FileManager.default.removeItem(at: tempUrl) }
              
              let audioFile = try AVAudioFile(forReading: tempUrl)
              let srcFormat = audioFile.processingFormat
              let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: targetRate,
                channels: 1,
                interleaved: false
              )!
              
              guard let formatConverter = AVAudioConverter(from: srcFormat, to: targetFormat) else {
                DispatchQueue.main.async {
                  result(FlutterError(code: "CONV_INIT_FAILED", message: "Cannot create AVAudioConverter", details: nil))
                }
                return
              }
              
              let frameCount = AVAudioFrameCount(audioFile.length)
              guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frameCount) else {
                DispatchQueue.main.async {
                  result(FlutterError(code: "BUFFER_FAILED", message: "Cannot allocate srcBuffer", details: nil))
                }
                return
              }
              try audioFile.read(into: srcBuffer)
              
              let ratio = targetRate / srcFormat.sampleRate
              let outputCapacity = AVAudioFrameCount(Double(srcBuffer.frameLength) * ratio + 4096)
              guard let dstBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
                DispatchQueue.main.async {
                  result(FlutterError(code: "BUFFER_FAILED", message: "Cannot allocate dstBuffer", details: nil))
                }
                return
              }
              
              var error: NSError?
              var allRead = false
              formatConverter.convert(to: dstBuffer, error: &error) { inNumPackets, outStatus in
                if allRead {
                  outStatus.pointee = .noDataNow
                  return nil
                }
                allRead = true
                outStatus.pointee = .haveData
                return srcBuffer
              }
              
              if let error = error {
                DispatchQueue.main.async {
                  result(FlutterError(code: "CONV_ERROR", message: error.localizedDescription, details: nil))
                }
                return
              }
              
              guard let channelData = dstBuffer.floatChannelData?[0] else {
                DispatchQueue.main.async {
                  result(FlutterError(code: "NO_DATA", message: "No float channel data", details: nil))
                }
                return
              }
              
              let sampleCount = Int(dstBuffer.frameLength)
              let byteCount = sampleCount * MemoryLayout<Float>.size
              let floatData = Data(bytes: channelData, count: byteCount)
              let typedData = FlutterStandardTypedData(float32: floatData)
              
              DispatchQueue.main.async {
                result(typedData)
              }
            } catch {
              DispatchQueue.main.async {
                result(FlutterError(code: "DECODE_ERROR", message: error.localizedDescription, details: nil))
              }
            }
          }
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
    super.applicationDidFinishLaunching(notification)
  }
}
