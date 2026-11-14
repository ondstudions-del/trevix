import AVFoundation
import CoreImage
import Flutter
import UIKit
import Vision

/// Edición de video de TREVIX con AVFoundation: recorte a una proporción, matriz de color, superposiciones PNG que se
/// mueven según claves de tiempo, imagen de cierre al final y sustitución del sonido por una canción.
public class TrevixVideoPlugin: NSObject, FlutterPlugin {
  private var session: AVAssetExportSession?
  private var busy = false
  private var cancelled = false
  private var framesCancelled = false
  private let visionQueue = DispatchQueue(label: "trevix_video.faces")
  /// Brillo que tenía la pantalla antes del flash frontal.
  private var savedBrightness: CGFloat?

  /// Caras con Vision (en el teléfono): recuadro, ojos, nariz y boca en fracciones desde arriba a la izquierda.
  private func faces(_ a: [String: Any], _ result: @escaping FlutterResult) {
    var cgImage: CGImage?
    if let path = a["path"] as? String {
      cgImage = UIImage(contentsOfFile: path)?.cgImage
    } else if let gray = a["gray"] as? FlutterStandardTypedData, let w = (a["width"] as? NSNumber)?.intValue,
              let h = (a["height"] as? NSNumber)?.intValue, w > 0, h > 0, gray.data.count >= w * h,
              let provider = CGDataProvider(data: gray.data as CFData) {
      cgImage = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
    guard let image = cgImage else {
      DispatchQueue.main.async { result([]) }
      return
    }
    let request = VNDetectFaceLandmarksRequest()
    do {
      try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    } catch {
      DispatchQueue.main.async { result([]) }
      return
    }
    var out: [[String: Any]] = []
    for face in (request.results as? [VNFaceObservation]) ?? [] {
      let bb = face.boundingBox
      var m: [String: Any] = ["x": Double(bb.minX), "y": Double(1 - bb.maxY), "w": Double(bb.width), "h": Double(bb.height)]
      func center(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
        guard let region = region, region.pointCount > 0 else { return nil }
        var sx: CGFloat = 0
        var sy: CGFloat = 0
        for p in region.normalizedPoints {
          sx += p.x
          sy += p.y
        }
        let n = CGFloat(region.pointCount)
        return CGPoint(x: bb.minX + sx / n * bb.width, y: 1 - (bb.minY + sy / n * bb.height))
      }
      let marks = face.landmarks
      if let l = center(marks?.leftPupil) ?? center(marks?.leftEye), let r = center(marks?.rightPupil) ?? center(marks?.rightEye) {
        m["lx"] = Double(l.x)
        m["ly"] = Double(l.y)
        m["rx"] = Double(r.x)
        m["ry"] = Double(r.y)
      }
      if let n = center(marks?.nose) {
        m["nx"] = Double(n.x)
        m["ny"] = Double(n.y)
      }
      if let mouth = center(marks?.outerLips) {
        m["mx"] = Double(mouth.x)
        m["my"] = Double(mouth.y)
      }
      out.append(m)
    }
    DispatchQueue.main.async { result(out) }
  }

  /// Fotogramas exactos cada intervalMs, ya girados y con el lado mayor ≤ maxSide, como JPEG en dir.
  private func frames(_ a: [String: Any], _ result: @escaping FlutterResult) {
    guard let input = a["input"] as? String, let dir = a["dir"] as? String else {
      DispatchQueue.main.async { result(FlutterError(code: "frames", message: "Faltan las rutas.", details: nil)) }
      return
    }
    let interval = max(40, (a["intervalMs"] as? NSNumber)?.intValue ?? 200)
    let side = CGFloat(max(64, (a["maxSide"] as? NSNumber)?.intValue ?? 480))
    let asset = AVURLAsset(url: URL(fileURLWithPath: input))
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    generator.maximumSize = CGSize(width: side, height: side)
    let duration = Int(asset.duration.seconds * 1000)
    var out: [[String: Any]] = []
    var ms = 0
    while ms < duration && !framesCancelled {
      if let image = try? generator.copyCGImage(at: CMTime(value: CMTimeValue(ms), timescale: 1000), actualTime: nil),
         let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.8) {
        let path = (dir as NSString).appendingPathComponent("frame_\(ms).jpg")
        if (try? data.write(to: URL(fileURLWithPath: path))) != nil {
          out.append(["ms": ms, "path": path, "width": image.width, "height": image.height])
        }
      }
      ms += interval
    }
    DispatchQueue.main.async { result(out) }
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "trevix_video", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(TrevixVideoPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "brightness":
      let value = ((call.arguments as? [String: Any])?["value"] as? NSNumber)?.doubleValue
      DispatchQueue.main.async {
        if let value = value {
          if self.savedBrightness == nil { self.savedBrightness = UIScreen.main.brightness }
          UIScreen.main.brightness = CGFloat(max(0, min(1, value)))
        } else if let saved = self.savedBrightness {
          UIScreen.main.brightness = saved
          self.savedBrightness = nil
        }
        result(nil)
      }
    case "torchMax":
      // La cámara trasera ya tiene la linterna encendida (plugin camera): se sube al nivel máximo disponible.
      DispatchQueue.global(qos: .userInitiated).async {
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           device.hasTorch, device.isTorchActive || device.torchMode == .on {
          do {
            try device.lockForConfiguration()
            try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
            device.unlockForConfiguration()
          } catch {}
        }
        DispatchQueue.main.async { result(nil) }
      }
    case "render":
      if busy {
        result(FlutterError(code: "busy", message: "Ya se está procesando otro video.", details: nil))
        return
      }
      busy = true
      cancelled = false
      let args = call.arguments as? [String: Any] ?? [:]
      DispatchQueue.global(qos: .userInitiated).async { self.render(args, result) }
    case "frames":
      framesCancelled = false
      let args = call.arguments as? [String: Any] ?? [:]
      DispatchQueue.global(qos: .userInitiated).async { self.frames(args, result) }
    case "faces":
      let args = call.arguments as? [String: Any] ?? [:]
      visionQueue.async { self.faces(args, result) }
    case "progress":
      result(session.map { Double($0.progress) } ?? -1.0)
    case "cancel":
      cancelled = true
      framesCancelled = true
      session?.cancelExport()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private struct Overlay {
    let image: CIImage
    let t: [Double]
    let x: [Double]
    let y: [Double]
    let w: [Double]
    let r: [Double]
    let a: [Double]

    func at(_ ms: Double) -> (x: Double, y: Double, w: Double, r: Double, a: Double) {
      var i = 0
      while i < t.count - 1 && t[i + 1] <= ms { i += 1 }
      var j = i
      var f = 0.0
      if i < t.count - 1 && ms > t[i] {
        j = i + 1
        f = (ms - t[i]) / max(1, t[j] - t[i])
      }
      func lerp(_ v: [Double]) -> Double { v[i] + (v[j] - v[i]) * f }
      return (lerp(x), lerp(y), lerp(w), lerp(r), lerp(a))
    }
  }

  private func render(_ a: [String: Any], _ result: @escaping FlutterResult) {
    var still: URL?
    func fail(_ code: String, _ message: String) {
      if let still = still { try? FileManager.default.removeItem(at: still) }
      DispatchQueue.main.async {
        self.busy = false
        result(FlutterError(code: code, message: message, details: nil))
      }
    }
    guard var input = a["input"] as? String, let output = a["output"] as? String else {
      return fail("input", "Faltan las rutas del video.")
    }
    let maxW = CGFloat((a["maxWidth"] as? NSNumber)?.doubleValue ?? 1080)
    // Una imagen (historia de foto o texto con música) se convierte antes en un video de esa duración.
    let imageMs = (a["imageMs"] as? NSNumber)?.intValue ?? 0
    if imageMs > 0 {
      guard let url = Self.stillVideo(input, imageMs, maxW) else {
        return fail("input", "No se pudo leer la imagen.")
      }
      still = url
      input = url.path
    }
    let asset = AVURLAsset(url: URL(fileURLWithPath: input))
    guard let src = asset.tracks(withMediaType: .video).first else {
      return fail("input", "No se pudo leer el video.")
    }
    let videoDur = src.timeRange.duration
    let transform = src.preferredTransform
    let box = CGRect(origin: .zero, size: src.naturalSize).applying(transform)
    let srcW = abs(box.width)
    let srcH = abs(box.height)
    guard srcW > 0, srcH > 0, videoDur.seconds > 0 else {
      return fail("input", "No se pudo leer el video.")
    }

    var cropW = srcW
    var cropH = srcH
    let aspect = (a["aspect"] as? NSNumber)?.doubleValue ?? 0
    let contain = aspect > 0 && ((a["contain"] as? Bool) ?? false)
    let outW: CGFloat
    let outH: CGFloat
    if contain {
      // Marco de la proporción pedida con el original entero dentro (franjas negras donde no llega).
      outW = Self.even(maxW)
      outH = Self.even(maxW / CGFloat(aspect))
    } else {
      if aspect > 0 {
        if Double(srcW / srcH) > aspect { cropW = srcH * CGFloat(aspect) } else { cropH = srcW / CGFloat(aspect) }
      }
      let k = min(1, maxW / cropW)
      outW = Self.even(cropW * k)
      outH = Self.even(cropH * k)
    }

    let comp = AVMutableComposition()
    guard let cv = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
      return fail("render", "No se pudo preparar el video.")
    }
    do {
      try cv.insertTimeRange(CMTimeRange(start: src.timeRange.start, duration: videoDur), of: src, at: .zero)
    } catch {
      return fail("render", error.localizedDescription)
    }
    cv.preferredTransform = transform

    // Cierre: se alarga la última décima de segundo del video y en ese tramo se dibuja la imagen del cierre.
    var total = videoDur
    var outro: CIImage?
    let outroMs = (a["outroMs"] as? NSNumber)?.intValue ?? 0
    if let path = a["outroImage"] as? String, outroMs > 0, let image = CIImage(contentsOf: URL(fileURLWithPath: path)) {
      let tail = CMTimeMinimum(CMTime(value: 1, timescale: 10), videoDur)
      let outroDur = CMTime(value: CMTimeValue(outroMs), timescale: 1000)
      do {
        try cv.insertTimeRange(CMTimeRange(start: src.timeRange.start + videoDur - tail, duration: tail), of: src, at: videoDur)
        cv.scaleTimeRange(CMTimeRange(start: videoDur, duration: tail), toDuration: outroDur)
        total = videoDur + outroDur
        outro = contain ? Self.contain(image, outW, outH) : Self.cover(image, outW, outH)
      } catch {
        outro = nil
      }
    }

    if let audioPath = a["audio"] as? String {
      let song = AVURLAsset(url: URL(fileURLWithPath: audioPath))
      if let st = song.tracks(withMediaType: .audio).first {
        let start = CMTime(value: CMTimeValue((a["audioStartMs"] as? NSNumber)?.intValue ?? 0), timescale: 1000)
        let len = CMTimeMinimum(total, st.timeRange.duration - start)
        if len.seconds > 0, let ca = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
          try? ca.insertTimeRange(CMTimeRange(start: st.timeRange.start + start, duration: len), of: st, at: .zero)
        }
      }
    } else if (a["keepAudio"] as? Bool) ?? true, let sa = asset.tracks(withMediaType: .audio).first,
              let ca = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
      try? ca.insertTimeRange(CMTimeRange(start: sa.timeRange.start, duration: CMTimeMinimum(sa.timeRange.duration, videoDur)), of: sa, at: .zero)
    }

    var matrix: [String: CIVector]?
    if let m = (a["colorMatrix"] as? [NSNumber])?.map({ CGFloat($0.doubleValue) }), m.count == 20 {
      matrix = [
        "inputRVector": CIVector(x: m[0], y: m[1], z: m[2], w: m[3]),
        "inputGVector": CIVector(x: m[5], y: m[6], z: m[7], w: m[8]),
        "inputBVector": CIVector(x: m[10], y: m[11], z: m[12], w: m[13]),
        "inputAVector": CIVector(x: m[15], y: m[16], z: m[17], w: m[18]),
        "inputBiasVector": CIVector(x: m[4] / 255, y: m[9] / 255, z: m[14] / 255, w: m[19] / 255),
      ]
    }

    var overlays: [Overlay] = []
    for item in (a["overlays"] as? [[String: Any]]) ?? [] {
      guard let path = item["image"] as? String, let image = CIImage(contentsOf: URL(fileURLWithPath: path)),
            let keys = item["keys"] as? [[String: Any]], !keys.isEmpty else { continue }
      func list(_ key: String, _ fallback: Double) -> [Double] { keys.map { ($0[key] as? NSNumber)?.doubleValue ?? fallback } }
      overlays.append(Overlay(image: image, t: list("ms", 0), x: list("x", 0.5), y: list("y", 0.5), w: list("width", 0.2),
                              r: list("rotation", 0), a: list("alpha", 1)))
    }

    let videoSeconds = videoDur.seconds
    let orientation = Self.orientation(transform)
    let frame = CGRect(x: 0, y: 0, width: outW, height: outH)
    let composition = AVMutableVideoComposition(asset: comp, applyingCIFiltersWithHandler: { req in
      if let outro = outro, req.compositionTime.seconds >= videoSeconds - 0.001 {
        req.finish(with: outro, context: nil)
        return
      }
      var img = req.sourceImage
      // Según la versión de iOS la imagen llega ya girada o tal como está guardada: si no tiene la forma del video
      // en pantalla, se aplica la orientación de la pista.
      if abs(img.extent.width - srcW) > 1 || abs(img.extent.height - srcH) > 1 { img = img.oriented(orientation) }
      if let matrix = matrix {
        // ColorFilter.matrix trabaja sobre los valores sRGB, no sobre la luz lineal de Core Image. Va antes del
        // encuadre para no teñir las franjas negras.
        img = img.applyingFilter("CILinearToSRGBToneCurve")
          .applyingFilter("CIColorMatrix", parameters: matrix)
          .applyingFilter("CISRGBToneCurveToLinear")
      }
      img = contain ? Self.contain(img, outW, outH) : Self.cover(img, outW, outH)
      let ms = req.compositionTime.seconds * 1000
      for o in overlays {
        let p = o.at(ms)
        if p.a <= 0.001 { continue }
        let ext = o.image.extent
        let s = CGFloat(p.w) * outW / ext.width
        let t = CGAffineTransform(translationX: -ext.midX, y: -ext.midY)
          .concatenating(CGAffineTransform(scaleX: s, y: s))
          .concatenating(CGAffineTransform(rotationAngle: CGFloat(p.r * .pi / 180)))
          .concatenating(CGAffineTransform(translationX: CGFloat(p.x) * outW, y: (1 - CGFloat(p.y)) * outH))
        var ov = o.image.transformed(by: t)
        if p.a < 0.999 {
          ov = ov.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(p.a))])
        }
        img = ov.composited(over: img)
      }
      req.finish(with: img.cropped(to: frame), context: nil)
    })
    composition.renderSize = CGSize(width: outW, height: outH)
    if !composition.frameDuration.isValid || composition.frameDuration.seconds <= 0 {
      composition.frameDuration = CMTime(value: 1, timescale: 30)
    }

    let stillFile = still
    func dropStill() {
      if let f = stillFile { try? FileManager.default.removeItem(at: f) }
    }
    DispatchQueue.main.async {
      if self.cancelled {
        self.busy = false
        dropStill()
        result(FlutterError(code: "cancelled", message: "Cancelado.", details: nil))
        return
      }
      guard let exp = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else {
        self.busy = false
        dropStill()
        result(FlutterError(code: "render", message: "No se pudo exportar el video.", details: nil))
        return
      }
      try? FileManager.default.removeItem(atPath: output)
      exp.outputURL = URL(fileURLWithPath: output)
      exp.outputFileType = .mp4
      exp.videoComposition = composition
      exp.shouldOptimizeForNetworkUse = true
      self.session = exp
      exp.exportAsynchronously {
        DispatchQueue.main.async {
          self.session = nil
          self.busy = false
          dropStill()
          switch exp.status {
          case .completed:
            result(output)
          case .cancelled:
            try? FileManager.default.removeItem(atPath: output)
            result(FlutterError(code: "cancelled", message: "Cancelado.", details: nil))
          default:
            try? FileManager.default.removeItem(atPath: output)
            result(FlutterError(code: "render", message: exp.error?.localizedDescription ?? "No se pudo exportar el video.", details: nil))
          }
        }
      }
    }
  }

  /// Escala la imagen para cubrir outW×outH (recortando al centro) con el origen en (0, 0).
  private static func cover(_ image: CIImage, _ outW: CGFloat, _ outH: CGFloat) -> CIImage {
    var img = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    let s = max(outW / img.extent.width, outH / img.extent.height)
    img = img.transformed(by: CGAffineTransform(scaleX: s, y: s))
    img = img.transformed(by: CGAffineTransform(translationX: -(img.extent.width - outW) / 2, y: -(img.extent.height - outH) / 2))
    return img.cropped(to: CGRect(x: 0, y: 0, width: outW, height: outH))
  }

  /// Encaja la imagen entera en outW×outH, centrada sobre negro, con el origen en (0, 0).
  private static func contain(_ image: CIImage, _ outW: CGFloat, _ outH: CGFloat) -> CIImage {
    var img = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    let s = min(outW / img.extent.width, outH / img.extent.height)
    img = img.transformed(by: CGAffineTransform(scaleX: s, y: s))
    img = img.transformed(by: CGAffineTransform(translationX: (outW - img.extent.width) / 2, y: (outH - img.extent.height) / 2))
    let frame = CGRect(x: 0, y: 0, width: outW, height: outH)
    return img.composited(over: CIImage(color: .black).cropped(to: frame)).cropped(to: frame)
  }

  /// Video H.264 que muestra la imagen durante ms (un fotograma por segundo basta: no se mueve).
  private static func stillVideo(_ path: String, _ ms: Int, _ maxW: CGFloat) -> URL? {
    guard let cg = UIImage(contentsOfFile: path)?.cgImage, cg.width > 0, cg.height > 0 else { return nil }
    let k = min(1, maxW / CGFloat(cg.width))
    let w = Int(even(CGFloat(cg.width) * k))
    let h = Int(even(CGFloat(cg.height) * k))
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("trevix_still_\(UUID().uuidString).mp4")
    guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
      kCVPixelBufferWidthKey as String: w,
      kCVPixelBufferHeightKey as String: h,
    ])
    guard writer.canAdd(input) else { return nil }
    writer.add(input)
    guard writer.startWriting() else { return nil }
    writer.startSession(atSourceTime: .zero)

    var buffer: CVPixelBuffer?
    let attrs = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
    guard CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32ARGB, attrs, &buffer) == kCVReturnSuccess, let pb = buffer else {
      writer.cancelWriting()
      return nil
    }
    CVPixelBufferLockBaseAddress(pb, [])
    if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: w, height: h, bitsPerComponent: 8,
                           bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
      ctx.setFillColor(UIColor.black.cgColor)
      ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
      ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    CVPixelBufferUnlockBaseAddress(pb, [])

    let total = max(ms, 100)
    var t = 0
    while t < total {
      while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
      if !adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(t), timescale: 1000)) { break }
      t += 1000
    }
    input.markAsFinished()
    writer.endSession(atSourceTime: CMTime(value: CMTimeValue(total), timescale: 1000))
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    if writer.status != .completed {
      try? FileManager.default.removeItem(at: url)
      return nil
    }
    return url
  }

  private static func even(_ v: CGFloat) -> CGFloat {
    max(2, (v / 2).rounded() * 2)
  }

  private static func orientation(_ t: CGAffineTransform) -> CGImagePropertyOrientation {
    switch (t.a, t.b, t.c, t.d) {
    case (0, 1, -1, 0): return .right
    case (0, -1, 1, 0): return .left
    case (-1, 0, 0, -1): return .down
    case (-1, 0, 0, 1): return .upMirrored
    case (1, 0, 0, -1): return .downMirrored
    case (0, 1, 1, 0): return .leftMirrored
    case (0, -1, -1, 0): return .rightMirrored
    default: return .up
    }
  }
}
