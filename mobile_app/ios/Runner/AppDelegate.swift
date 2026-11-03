import UIKit
import Flutter
import AVFoundation

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  var audioPlayer: AVAudioPlayer?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // 1. 设置 TrollStore 锁屏后台常驻 AVAudioSession
    setupBackgroundAudioKeepalive()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func setupBackgroundAudioKeepalive() {
    do {
      // 使用 .playback 模式，允许在锁屏和后台持续运行
      // .mixWithOthers 保证不打断用户平时用网易云/QQ音乐/听播客
      try AVAudioSession.sharedInstance().setCategory(
        .playback,
        mode: .default,
        options: [.mixWithOthers]
      )
      try AVAudioSession.sharedInstance().setActive(true)

      // 启动极低开销的纯静音音频循环，维持 iOS 运行状态永不休眠
      startSilentAudioLoop()
    } catch {
      print("[TrollStore-Audio] Failed to set audio session: \(error)")
    }
  }

  func startSilentAudioLoop() {
    let silentData = createSilentWavData()
    do {
      audioPlayer = try AVAudioPlayer(data: silentData)
      audioPlayer?.numberOfLoops = -1 // 无限循环
      audioPlayer?.volume = 0.01 // 极低音量静音
      audioPlayer?.prepareToPlay()
      audioPlayer?.play()
      print("[TrollStore-Audio] 后台静默保活已激活，锁屏长连接永不中断！")
    } catch {
      print("[TrollStore-Audio] Audio player init error: \(error)")
    }
  }

  // 内存动态构建 1 秒合法的标准 PCM 16-bit 单声道静音 WAV 数据 (无需外部资源文件)
  func createSilentWavData() -> Data {
    var data = Data()
    // RIFF chunk
    data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
    let sampleRate: UInt32 = 8000
    let durationSeconds: UInt32 = 1
    let numSamples = sampleRate * durationSeconds
    let dataSize: UInt32 = numSamples * 2 // 16-bit = 2 bytes per sample
    let fileSize: UInt32 = 36 + dataSize
    data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
    data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

    // fmt chunk
    data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
    let subchunk1Size: UInt32 = 16
    data.append(contentsOf: withUnsafeBytes(of: subchunk1Size.littleEndian) { Array($0) })
    let audioFormat: UInt16 = 1 // PCM
    data.append(contentsOf: withUnsafeBytes(of: audioFormat.littleEndian) { Array($0) })
    let numChannels: UInt16 = 1 // Mono
    data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
    let byteRate: UInt32 = sampleRate * 1 * 2
    data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
    let blockAlign: UInt16 = 2
    data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
    let bitsPerSample: UInt16 = 16
    data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

    // data chunk
    data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
    data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
    data.append(contentsOf: [UInt8](repeating: 0, count: Int(dataSize)))

    return data
  }
}
