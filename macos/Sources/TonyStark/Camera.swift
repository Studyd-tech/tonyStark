import AppKit
import AVFoundation
import HandTracking
import GestureCore

struct CameraFrame {
    let image: CGImage?
    let hands: [TrackedHand]
    let time: Double
}

final class Camera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let queue = DispatchQueue(label: "tonystark.camera", qos: .userInitiated)
    private let session = AVCaptureSession()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var handTracker: MediaPipeTracker?
    private var generation = 0
    private var lastFrame = 0.0
    var onFrame: ((CameraFrame) -> Void)?
    var onStatus: ((String) -> Void)?
    var onFailure: ((String) -> Void)?

    static var devices: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                         mediaType: .video, position: .unspecified).devices
    }

    func start(deviceID: String) {
        generation += 1
        let token = generation
        AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                guard allowed else {
                    self.onFailure?("Camera access is off. Enable Tony Stark in System Settings → Privacy & Security → Camera, then return here and start the camera.")
                    return
                }
                self.queue.async { self.configure(deviceID: deviceID, token: token) }
            }
        }
    }

    private func configure(deviceID: String, token: Int) {
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        session.sessionPreset = .vga640x480
        do {
            guard let framework = Bundle.main.privateFrameworksURL,
                  let resources = Bundle.main.resourceURL else {
                throw NSError(domain: "HandTracking", code: 1, userInfo: [NSLocalizedDescriptionKey: "Open the built Tony Stark.app bundle to load the 3D hand tracker."])
            }
            handTracker = try MediaPipeTracker(libraryPath: framework.appendingPathComponent("libmediapipe.dylib").path,
                                              modelPath: resources.appendingPathComponent("hand_landmarker.task").path)
            guard let device = Self.devices.first(where: { $0.uniqueID == deviceID }) else {
                throw NSError(domain: "Camera", code: 1, userInfo: [NSLocalizedDescriptionKey: "Selected camera is unavailable."])
            }
            let input = try AVCaptureDeviceInput(device: device)
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.setSampleBufferDelegate(self, queue: queue)
            guard session.canAddInput(input), session.canAddOutput(output) else {
                throw NSError(domain: "Camera", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not configure the camera."])
            }
            session.addInput(input); session.addOutput(output)
            // Keep the capture in sensor coordinates. Preview and landmarks both mirror once.
            if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
            session.commitConfiguration()
            session.startRunning()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.onStatus?("Camera ready · 3D hand tracking. Calibrate aiming, then hold one pointing finger to arm.")
            }
        } catch {
            session.commitConfiguration()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.onFailure?(error.localizedDescription)
            }
        }
    }

    func stop() {
        generation += 1
        queue.async { self.session.stopRunning(); self.handTracker = nil }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFrame > 1.0 / 24, let pixel = CMSampleBufferGetImageBuffer(buffer) else { return }
        lastFrame = now
        let hands: [TrackedHand]
        do {
            hands = try handTracker?.detect(pixelBuffer: pixel, time: now) ?? []
        } catch {
            DispatchQueue.main.async { [weak self] in self?.onFailure?("3D hand tracking failed: \(error.localizedDescription)") }
            return
        }
        let ci = CIImage(cvPixelBuffer: pixel)
        let image = context.createCGImage(ci, from: ci.extent)
        let frame = CameraFrame(image: image, hands: hands, time: now)
        DispatchQueue.main.async { [weak self] in self?.onFrame?(frame) }
    }
}

final class CameraPreview: NSView {
    var frameData: CameraFrame? { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.06, alpha: 1).setFill(); bounds.fill()
        guard let frame = frameData, let image = frame.image, let cg = NSGraphicsContext.current?.cgContext else { return }
        let scale = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
        let rect = CGRect(x: (bounds.width - CGFloat(image.width) * scale) / 2,
                          y: (bounds.height - CGFloat(image.height) * scale) / 2,
                          width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        cg.saveGState()
        cg.translateBy(x: rect.maxX, y: rect.maxY)
        cg.scaleBy(x: -1, y: -1)
        cg.draw(image, in: CGRect(origin: .zero, size: rect.size))
        cg.restoreGState()
        for (index, hand) in frame.hands.enumerated() {
            drawHand(hand.image, in: rect, color: index == 0 ? .systemCyan : .systemMint, showIndex: frame.hands.count == 1)
        }
    }

    private func drawHand(_ joints: [String: Point], in rect: CGRect, color: NSColor, showIndex: Bool) {
        color.withAlphaComponent(0.75).setStroke()
        for finger in [["wrist", "thumbCMC", "thumbMP", "thumbIP", "thumbTip"],
                       ["wrist", "indexMCP", "indexPIP", "indexDIP", "indexTip"],
                       ["wrist", "middleMCP", "middlePIP", "middleDIP", "middleTip"],
                       ["wrist", "ringMCP", "ringPIP", "ringDIP", "ringTip"],
                       ["wrist", "littleMCP", "littlePIP", "littleDIP", "littleTip"]] {
            let path = NSBezierPath(); path.lineWidth = 1.5
            for i in 1..<finger.count {
                if let a = joints[finger[i-1]], let b = joints[finger[i]] {
                    path.move(to: NSPoint(x: rect.minX + a.x * rect.width, y: rect.minY + a.y * rect.height))
                    path.line(to: NSPoint(x: rect.minX + b.x * rect.width, y: rect.minY + b.y * rect.height))
                }
            }
            path.stroke()
        }
        color.setFill()
        for p in joints.values {
            NSBezierPath(ovalIn: NSRect(x: rect.minX + p.x * rect.width - 3,
                                       y: rect.minY + p.y * rect.height - 3, width: 6, height: 6)).fill()
        }
        if showIndex, let tip = joints["indexTip"] {
            let position = NSPoint(x: rect.minX + tip.x * rect.width, y: rect.minY + tip.y * rect.height)
            NSColor.systemYellow.setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: position.x - 9, y: position.y - 9, width: 18, height: 18))
            ring.lineWidth = 2; ring.stroke()
            ("INDEX" as NSString).draw(at: NSPoint(x: min(rect.maxX - 44, position.x + 12), y: max(rect.minY, position.y - 16)),
                                      withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold), .foregroundColor: NSColor.systemYellow])
        }
    }
}
