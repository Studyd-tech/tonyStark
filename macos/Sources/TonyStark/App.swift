import AppKit
import AVFoundation
import GestureCore

private struct SavedCalibration: Codable {
    let cameraID: String
    let displayID: CGDirectDisplayID
    let desktopSignature: String
    let mapping: Calibration
    var id: String { "\(cameraID)|\(displayID)" }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var cameras: [String: Camera] = [:]
    private let control = DesktopControl()
    private let overlay = TargetOverlay()
    private var desktop = Desktop()
    private var machine = GestureMachine()
    private var filter = CursorFilter()
    private var cursorHold = CursorHold()
    private var saved: [SavedCalibration] = []
    private var activeRoute: SavedCalibration?
    private var selector = RouteSelector()
    private var observations: [String: (time: Double, hand: HandSample)] = [:]
    private var running = false
    private var startedAt = 0.0
    private var lastPoint: CGPoint?
    private var lastAim: Point?
    private var dragAnchor: Point?
    private var dragAim: Point?
    private var dragScreen: CGPoint?
    private var frames: [CalibrationFrame] = []
    private var cameraReady = false
    private var poseSeen: Pose?
    private var poseSeenAt = 0.0
    private var partialHand = false
    private var previewHandCount = 0
    private var twoHandGesture = TwoHandGesture()
    private var browserTabTarget: DesktopControl.BrowserTabTarget?
    private var tabCloseTask: Task<Void, Never>?
    private var browserCloseSequence = BrowserCloseSequence<DesktopControl.BrowserTabTarget>()
    private var twoHandCameraID: String?
    private var captureNote = ""
    private var cameraProblem = ""
    private var previewConfirmed = false
    private var liveEnabled = false
    private var calibrationCamera: [Point] = []
    private var calibrating = false
    private var captureDeadline: Double?
    private var timer: Timer?
    private var globalKeys: Any?
    private var localKeys: Any?
    private var screenObserver: NSObjectProtocol?
    private var cameraObservers: [NSObjectProtocol] = []
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private let preview = CameraPreview()
    private let cameraPicker = NSPopUpButton()
    private let displayPicker = NSPopUpButton()
    private let startButton = NSButton(title: "Start camera", target: nil, action: nil)
    private let liveToggle = NSButton(checkboxWithTitle: "Enable live Mac control", target: nil, action: nil)
    private let calibrateButton = NSButton(title: "Calibrate aiming", target: nil, action: nil)
    private let captureButton = NSButton(title: "Capture target (3 seconds)", target: nil, action: nil)
    private let guideTitle = NSTextField(wrappingLabelWithString: "")
    private let guideDetail = NSTextField(wrappingLabelWithString: "")
    private let guideFeedback = NSTextField(wrappingLabelWithString: "")
    private let guideProgress = NSProgressIndicator()
    private let backButton = NSButton(title: "Previous target", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel setup", target: nil, action: nil)
    private let statusLabel = NSTextField(wrappingLabelWithString: "Start in preview mode. Your camera stays off until you press Start camera.")
    private let gestureLabel = NSTextField(labelWithString: "DISARMED · PREVIEW")
    private let closeTabStatus = NSTextField(wrappingLabelWithString: "")
    private let permissionLabel = NSTextField(labelWithString: "")
    private let calibrationLabel = NSTextField(wrappingLabelWithString: "")
    private let sensitivity = NSSlider(value: 0.4, minValue: 0.25, maxValue: 0.65, target: nil, action: nil)
    private var devices: [AVCaptureDevice] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let data = UserDefaults.standard.data(forKey: "displayCalibrations") {
            saved = (try? JSONDecoder().decode([SavedCalibration].self, from: data)) ?? []
        }
        buildWindow()
        buildMenu()
        devices = Camera.devices
        cameraPicker.addItems(withTitles: devices.map(\.localizedName))
        if devices.isEmpty { cameraPicker.addItem(withTitle: "No camera found"); startButton.isEnabled = false }
        displayPicker.addItems(withTitles: desktop.ids.map(desktop.displayName))
        if let index = devices.firstIndex(where: { $0.uniqueID == saved.first?.cameraID }) { cameraPicker.selectItem(at: index) }
        restoreCalibration()
        globalKeys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.pause() }
        }
        localKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.pause(); return nil }
            if event.keyCode == 49, self?.calibrating == true, !event.isARepeat {
                self?.captureTarget(); return nil
            }
            return event
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.pause()
            self.stopCameras()
            self.desktop = Desktop()
            self.displayPicker.removeAllItems()
            self.displayPicker.addItems(withTitles: self.desktop.ids.map(self.desktop.displayName))
            self.restoreCalibration()
            self.statusLabel.stringValue = "Display arrangement changed. Check or repeat calibration before enabling control."
        }
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            cameraObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshCameras()
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        updateGuide()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func text(_ string: String, size: CGFloat = 13, bold: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: string)
        label.font = .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        return label
    }
    private func button(_ title: String, _ action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }
    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 790, height: 780),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Tony Stark · Mac Gesture Control"
        window.minSize = NSSize(width: 730, height: 600)
        window.isReleasedWhenClosed = false
        window.center()
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
        window.contentView!.addSubview(scroll)
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24)
        ])
        stack.addArrangedSubview(text("Let’s set up your gestures", size: 24, bold: true))
        stack.addArrangedSubview(text("Camera → four targets → practice → Mac control. Start with your laptop screen."))
        cameraPicker.target = self; cameraPicker.action = #selector(cameraChanged)
        displayPicker.target = self; displayPicker.action = #selector(displayChanged)
        startButton.target = self; startButton.action = #selector(toggleCamera)
        stack.addArrangedSubview(NSStackView(views: [text("Camera"), cameraPicker, startButton]))
        stack.addArrangedSubview(NSStackView(views: [text("Screen"), displayPicker, button("Forget this pair", #selector(forgetPair))]))
        buildGuide(in: stack)
        preview.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(preview)
        NSLayoutConstraint.activate([preview.widthAnchor.constraint(equalTo: stack.widthAnchor), preview.heightAnchor.constraint(equalToConstant: 200)])
        gestureLabel.font = .monospacedSystemFont(ofSize: 15, weight: .bold)
        gestureLabel.textColor = .systemCyan
        stack.addArrangedSubview(gestureLabel)
        closeTabStatus.isHidden = true
        closeTabStatus.textColor = .secondaryLabelColor
        stack.addArrangedSubview(closeTabStatus)
        liveToggle.target = self; liveToggle.action = #selector(changeLive)
        stack.addArrangedSubview(NSStackView(views: [liveToggle, button("Pause / Esc", #selector(pause))]))
        stack.addArrangedSubview(NSStackView(views: [button("Open Accessibility settings…", #selector(requestAccessibility)),
                                                   button("Show this app in Finder", #selector(revealApp))]))
        stack.addArrangedSubview(permissionLabel)
        calibrateButton.target = self; calibrateButton.action = #selector(beginCalibration)
        stack.addArrangedSubview(calibrateButton)
        stack.addArrangedSubview(calibrationLabel)
        stack.addArrangedSubview(text("Three-finger pinch: thumb + index + middle. Pinch sensitivity (higher is easier):"))
        sensitivity.widthAnchor.constraint(equalToConstant: 340).isActive = true
        stack.addArrangedSubview(sensitivity)
        let instructions = text("Point toward a calibrated screen to arm the pointer.\nClick: Aim at a window, then open your palm. Close that palm into a fist to minimize the selected window.\nScroll: Aim inside a page. Hold up your index and middle fingers, then move your hand up or down.\nClose tab: Select your browser window, show both open palms until CLOSE BOTH HANDS appears, then make two fists. Repeat palms → fists within three seconds to close that same window. The controller remembers the browser window you last selected.\nMission Control: Make two fists, then open both hands. With one hand, make a fist and hold your palm open for about a second.\nDrag: Aim at a window, pinch thumb + index + middle, then move your hand. Release to drop.\nEsc or Pause stops live control. Losing the hand disarms. A second camera can be assigned to the monitor.")
        stack.addArrangedSubview(instructions)
        statusLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(statusLabel)
        // Explicit widths let wrapping labels lay out consistently in AppKit stack views.
        for label in [calibrationLabel, instructions, statusLabel, closeTabStatus] {
            label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }
    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "hand.point.up.left.fill", accessibilityDescription: "Tony Stark")
        let menu = NSMenu()
        for (title, action, key) in [("Show controller", #selector(showWindow), ""), ("Pause control", #selector(pause), ""), ("Quit Tony Stark", #selector(quit), "q")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item)
        }
        statusItem.menu = menu
        let menuBar = NSMenu()
        let applicationMenu = NSMenuItem(title: "Tony Stark", action: nil, keyEquivalent: "")
        applicationMenu.submenu = menu.copy() as? NSMenu
        menuBar.addItem(applicationMenu)
        NSApp.mainMenu = menuBar
    }

    private func buildGuide(in stack: NSStackView) {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor
        card.layer?.cornerRadius = 12
        card.translatesAutoresizingMaskIntoConstraints = false
        let content = NSStackView()
        content.orientation = .vertical; content.alignment = .leading; content.spacing = 9
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content); stack.addArrangedSubview(card)
        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalTo: stack.widthAnchor),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        guideTitle.font = .systemFont(ofSize: 20, weight: .semibold)
        guideDetail.font = .systemFont(ofSize: 14)
        guideFeedback.font = .systemFont(ofSize: 13, weight: .medium)
        for label in [guideTitle, guideDetail, guideFeedback] {
            content.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        guideProgress.isIndeterminate = false; guideProgress.minValue = 0; guideProgress.maxValue = 4
        content.addArrangedSubview(guideProgress)
        guideProgress.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        captureButton.target = self; captureButton.action = #selector(advanceSetup)
        captureButton.bezelStyle = .rounded; captureButton.controlSize = .large
        backButton.target = self; backButton.action = #selector(previousTarget)
        cancelButton.target = self; cancelButton.action = #selector(cancelCalibration)
        content.addArrangedSubview(NSStackView(views: [captureButton, backButton, cancelButton]))
    }

    private var selectedCalibration: SavedCalibration? {
        availableCalibrations.first { $0.cameraID == selectedCameraID && $0.displayID == selectedDisplayID }
    }
    private var cornerName: String { ["upper left ↖", "upper right ↗", "lower right ↘", "lower left ↙"][min(3, calibrationCamera.count)] }

    private func updateGuide() {
        let now = ProcessInfo.processInfo.systemUptime
        let seen = now - poseSeenAt < 0.3 ? poseSeen : nil
        backButton.isHidden = !calibrating; cancelButton.isHidden = !calibrating
        backButton.isEnabled = calibrating && !calibrationCamera.isEmpty && captureDeadline == nil
        guideProgress.isHidden = !calibrating
        guideProgress.doubleValue = Double(calibrationCamera.count)
        captureButton.isEnabled = !devices.isEmpty
        let trusted = control.isTrusted
        liveToggle.state = liveEnabled ? .on : .off
        liveToggle.isEnabled = cameraReady && previewConfirmed && !availableCalibrations.isEmpty && !calibrating && trusted
        liveToggle.toolTip = trusted ? "Enable gestures after checking the pointing preview." : "macOS has not granted this running copy Accessibility access. Use the permission recovery instructions in the setup card."
        let poseFeedback: String
        if previewHandCount == 2 && now - poseSeenAt < 0.3 {
            poseFeedback = calibrating ? "Use one hand to capture this target." : "Two hands detected. Open both palms, then make two fists to close a browser tab."
        } else {
            switch seen {
            case .point: poseFeedback = "✓ Point detected. Keep your whole hand inside the camera preview."
            case .palm: poseFeedback = "Camera sees an open palm. Fold your middle, ring and little fingers; leave your index finger out."
            case .fist: poseFeedback = "Camera sees a fist. Extend just your index finger."
            case .pinch: poseFeedback = "Camera sees a pinch. Extend your index finger and fold the other fingers."
            case .twoFingers: poseFeedback = "Two fingers detected. To scroll, aim first, then hold both fingers up and move your hand vertically."
            case .other: poseFeedback = "Hand visible. Extend only your index finger; angle your hand so the camera can see it."
            case nil:
                poseFeedback = partialHand && now - poseSeenAt < 0.3
                    ? "Fingertip tracked, but the hand pose is uncertain. Show your wrist and knuckles too; turn your hand slightly so the camera can resolve the fingers."
                    : "No reliable hand pose yet. Keep your wrist and knuckles in view. If pointing straight hides the hand, tilt it slightly; a hidden finger cannot be tracked reliably."
            }
        }
        guideFeedback.textColor = seen == .point ? .systemGreen : .secondaryLabelColor
        if calibrating {
            guideTitle.stringValue = "Target \(calibrationCamera.count + 1) of 4 · \(cornerName)"
            guideDetail.stringValue = "Point toward the cyan circle on your screen. Keep your index finger extended and your other fingers folded. Press Space, then hold that pose through the countdown."
            captureButton.title = "Capture this target · Space"
            captureButton.isEnabled = captureDeadline == nil
            if let deadline = captureDeadline {
                let seconds = max(1, Int(ceil(deadline - now)))
                guideTitle.stringValue = "\(seconds)… hold your point steady"
                guideFeedback.stringValue = poseFeedback
                guideProgress.doubleValue = Double(calibrationCamera.count) + max(0, min(1, 1 - (deadline - now) / 3))
                captureButton.title = "Capturing…"
            } else {
                guideFeedback.stringValue = captureNote.isEmpty ? poseFeedback : captureNote + "\n" + poseFeedback
                if !captureNote.isEmpty { guideFeedback.textColor = captureNote.hasPrefix("✓") ? .systemGreen : .systemOrange }
            }
        } else if !running {
            guideTitle.stringValue = "Step 1 of 4 · Turn on your camera"
            guideDetail.stringValue = "Choose your camera above, then start it. If macOS asks to use the camera, choose Allow. Your windows stay still while you set up."
            guideFeedback.stringValue = cameraProblem.isEmpty ? "Next: we’ll check your pointing hand, then capture four screen targets." : cameraProblem
            let blocked = [.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .video))
            captureButton.title = blocked ? "Open Camera settings" : "Start camera"
        } else if !cameraReady {
            guideTitle.stringValue = "Step 1 of 4 · Waiting for the camera"
            guideDetail.stringValue = "If a camera permission dialog is open, click Allow. The preview will appear below when the camera is ready."
            guideFeedback.stringValue = "Camera starting…"; captureButton.title = "Waiting for camera…"
            captureButton.isEnabled = false
        } else if selectedCalibration == nil {
            guideTitle.stringValue = "Step 2 of 4 · Make a pointing hand"
            guideDetail.stringValue = "Hold up one hand, extend your index finger, and fold the other fingers. Keep your wrist and knuckles in the preview. The yellow INDEX ring marks your fingertip; the message below confirms the full 3D pose. Next, we’ll capture four targets."
            guideFeedback.stringValue = poseFeedback
            captureButton.title = "I’m ready — show the first target"
        } else if !previewConfirmed {
            guideTitle.stringValue = "Step 3 of 4 · Try your aim in preview"
            guideDetail.stringValue = "Calibration saved. Hold your pointing gesture for about a second, then aim around this screen. The cyan circle should follow. If it feels wrong, choose Calibrate aiming again below."
            guideFeedback.stringValue = poseFeedback
            captureButton.title = "The circle follows my finger — continue"
        } else if !trusted {
            guideTitle.stringValue = "Step 4 of 4 · Refresh window-control permission"
            guideDetail.stringValue = "macOS hasn’t authorized this running copy yet. Open Privacy & Security → Accessibility. If Tony Stark is already on, select its row, remove it with −, then add this app again with + and turn it on. Use Show this app in Finder below to find the current copy."
            guideFeedback.stringValue = "Your calibration is saved. After replacing the old entry, return here; this card will update when macOS recognizes access."
            captureButton.title = "Open Accessibility settings…"
        } else if !live {
            guideTitle.stringValue = "Step 4 of 4 · Ready to test on your Mac"
            guideDetail.stringValue = "Enable control, then hold a point to arm. Aim inside a normal window; pinch thumb + index + middle together and move your hand. Open the pinch to drop. Press Esc at any time to pause."
            guideFeedback.stringValue = "Hold your aim steady for two seconds to keep the target in place. Open your palm to click; close it to minimize. Return to a clear pointing pose for a moment to aim again."
            captureButton.title = "Enable live Mac control"
        } else {
            guideTitle.stringValue = "You’re ready · Live Mac control"
            guideDetail.stringValue = "Point → palm clicks. Close that palm to minimize. Raise two fingers and move your hand vertically to scroll. Two palms → two fists closes the active browser tab; repeat within three seconds to close the same window. Two fists → two palms opens Mission Control. Pinch three fingers to drag. Esc pauses control."
            guideFeedback.stringValue = poseFeedback
            captureButton.title = "Pause control"
        }
    }

    @objc private func advanceSetup() {
        if calibrating { captureTarget() }
        else if !running {
            if [.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .video)),
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                NSWorkspace.shared.open(url)
            } else { toggleCamera() }
        } else if !cameraReady { return }
        else if selectedCalibration == nil { beginCalibration() }
        else if !previewConfirmed { previewConfirmed = true }
        else if !control.isTrusted { requestAccessibility() }
        else if !live { liveToggle.state = .on; changeLive() }
        else { pause() }
        updateGuide()
    }

    @objc private func previousTarget() {
        guard calibrating, captureDeadline == nil, !calibrationCamera.isEmpty else { return }
        calibrationCamera.removeLast(); captureNote = "Previous capture removed. Let’s try this target again."
        showCalibrationTarget(); updateGuide()
    }

    private var selectedCameraID: String? {
        let index = cameraPicker.indexOfSelectedItem
        return devices.indices.contains(index) ? devices[index].uniqueID : nil
    }
    private var selectedDisplayID: CGDirectDisplayID? {
        let index = displayPicker.indexOfSelectedItem
        return desktop.ids.indices.contains(index) ? desktop.ids[index] : nil
    }
    private var availableCalibrations: [SavedCalibration] {
        saved.filter { route in
            route.desktopSignature == desktop.signature && desktop.ids.contains(route.displayID) &&
                devices.contains(where: { $0.uniqueID == route.cameraID })
        }
    }
    private var live: Bool { liveEnabled && control.isTrusted && !calibrating }
    private func restoreCalibration() {
        let selected = availableCalibrations.first { $0.cameraID == selectedCameraID && $0.displayID == selectedDisplayID }
        calibrationLabel.stringValue = selected == nil
            ? "This camera/display pair needs calibration. Calibrated pairs: \(availableCalibrations.count)."
            : "This camera/display pair is calibrated. Total pairs: \(availableCalibrations.count). Recalibrate if you or a camera move."
    }

    @objc private func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func requestAccessibility() { control.requestPermission() }
    @objc private func revealApp() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
    @objc private func cameraChanged() {
        let wasRunning = running
        pause(); stopCameras(); previewConfirmed = false; restoreCalibration()
        if wasRunning { startCameras() }
    }
    @objc private func displayChanged() { pause(); previewConfirmed = false; restoreCalibration(); updateGuide() }
    @objc private func forgetPair() {
        let cameraID = selectedCameraID, displayID = selectedDisplayID
        pause(); stopCameras()
        saved.removeAll { $0.cameraID == cameraID && $0.displayID == displayID }
        saveCalibrations(); restoreCalibration()
        statusLabel.stringValue = "Camera/display calibration removed. Restart cameras to use the remaining pairs."
    }
    private func saveCalibrations() {
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: "displayCalibrations") }
    }
    private func refreshCameras() {
        let previous = selectedCameraID
        pause(); stopCameras()
        devices = Camera.devices
        cameraPicker.removeAllItems(); cameraPicker.addItems(withTitles: devices.map(\.localizedName))
        if let index = devices.firstIndex(where: { $0.uniqueID == previous }) { cameraPicker.selectItem(at: index) }
        if devices.isEmpty { cameraPicker.addItem(withTitle: "No camera found") }
        startButton.isEnabled = !devices.isEmpty
        restoreCalibration()
        statusLabel.stringValue = "Camera connections changed. Select a camera and restart in preview mode."
    }
    private func stopCameras() {
        running = false
        cameraReady = false; poseSeen = nil; poseSeenAt = 0
        cameras.values.forEach { $0.stop() }; cameras.removeAll()
        observations.removeAll(); preview.frameData = nil; startButton.title = "Start cameras"
    }
    private func startCameras() {
        guard let selectedCameraID else { return }
        cameraProblem = ""; cameraReady = false; previewConfirmed = false
        running = true; startedAt = ProcessInfo.processInfo.systemUptime
        let ids = Set(availableCalibrations.map(\.cameraID) + [selectedCameraID])
        for id in ids {
            let source = Camera()
            source.onFrame = { [weak self] frame in self?.receive(frame, cameraID: id) }
            source.onStatus = { [weak self] status in
                guard let self, self.running else { return }
                if id == self.selectedCameraID { self.statusLabel.stringValue = status }
            }
            source.onFailure = { [weak self] message in
                guard let self, self.running else { return }
                if id == self.selectedCameraID {
                    self.pause(); self.stopCameras(); self.cameraProblem = message
                    self.statusLabel.stringValue = message; self.updateGuide()
                }
            }
            cameras[id] = source; source.start(deviceID: id)
        }
        startButton.title = "Stop cameras"
    }
    @objc private func toggleCamera() {
        if running {
            pause(); stopCameras(); statusLabel.stringValue = "Cameras stopped."
        } else {
            statusLabel.stringValue = "Requesting camera access…"; startCameras()
        }
    }
    @objc private func pause() {
        liveEnabled = false
        liveToggle.state = .off
        resetTwoHandGestures()
        resetInteraction()
        frames.removeAll()
        selector.reset(); observations.removeAll()
        if calibrating { cancelCalibration() }
        gestureLabel.stringValue = "DISARMED · PREVIEW"
        statusLabel.stringValue = "Mac control paused. Hold a point to arm the preview again."
    }
    @objc private func changeLive() {
        let wantsLive = liveToggle.state == .on
        guard wantsLive else { pause(); updateGuide(); return }
        // Validate before changing the session. The checkbox used to turn on,
        // call pause(), then bounce off when permission was missing.
        let blocker: String?
        if !running || !cameraReady { blocker = "Start the camera first." }
        else if !previewConfirmed { blocker = "Check the cyan circle in preview and finish the setup guide first." }
        else if availableCalibrations.isEmpty { blocker = "Calibrate aiming before enabling live control." }
        else if !control.isTrusted { blocker = "Window control is blocked for this copy. Replace the old Tony Stark entry in Accessibility settings, then return here." }
        else { blocker = nil }
        if let blocker {
            liveToggle.state = liveEnabled ? .on : .off
            statusLabel.stringValue = blocker; updateGuide(); return
        }
        resetInteraction()
        resetTwoHandGestures()
        liveEnabled = true
        liveToggle.state = .on
        statusLabel.stringValue = "Live control enabled. Hold a point to arm. Esc or the menu bar Pause stops control."
        updateGuide()
    }

    @objc private func beginCalibration() {
        guard running, cameraReady else { statusLabel.stringValue = "Start the camera before calibrating."; return }
        pause(); calibrating = true; calibrationCamera = []; previewConfirmed = false; captureNote = ""
        calibrateButton.isEnabled = false; captureButton.isEnabled = true
        showCalibrationTarget()
        updateGuide()
    }
    private func showCalibrationTarget() {
        guard let display = selectedDisplayID else { return }
        let index = calibrationCamera.count
        let corner = ["upper left", "upper right", "lower right", "lower left"][index]
        calibrationLabel.stringValue = "\(desktop.displayName(display)) · target \(index + 1)/4 · \(corner). Press Space to capture."
        overlay.show(at: desktop.calibrationTargets(for: display)[index], message: "\(index + 1)/4 · POINT HERE\n\(corner.uppercased())", live: false)
    }
    @objc private func captureTarget() {
        guard calibrating, captureDeadline == nil else { return }
        captureDeadline = ProcessInfo.processInfo.systemUptime + 3
        captureNote = ""
        captureButton.isEnabled = false
        updateGuide()
    }
    @objc private func cancelCalibration() {
        calibrating = false; captureDeadline = nil; calibrationCamera = []
        calibrateButton.isEnabled = true; captureButton.isEnabled = false
        overlay.hide(); restoreCalibration()
        updateGuide()
    }
    private func finishCapture(at now: Double) {
        captureDeadline = nil
        let median: Point
        switch CalibrationCapture.assess(frames, at: now) {
        case .success(let point): median = point
        case .failure(let problem):
            switch problem {
            case .handMissing: captureNote = "Let’s retry this target: keep your whole hand visible during the countdown."
            case .pointRequired: captureNote = "Let’s retry: extend only your index finger for the full countdown."
            case .keepStill: captureNote = "Let’s retry: your hand moved. Rest your elbow and hold the point steady."
            }
            statusLabel.stringValue = captureNote; showCalibrationTarget(); updateGuide(); return
        }
        calibrationCamera.append(median)
        if calibrationCamera.count < 4 {
            captureNote = "✓ Target \(calibrationCamera.count) saved. Move your point to the next cyan circle, then press Space."
            showCalibrationTarget(); updateGuide(); return
        }
        let destinations = [Point(0.12, 0.12), Point(0.88, 0.12), Point(0.88, 0.88), Point(0.12, 0.88)]
        guard let mapping = Calibration(camera: calibrationCamera, desktop: destinations), let cameraID = selectedCameraID, let displayID = selectedDisplayID else {
            calibrationCamera = []
            captureNote = "The four positions were too similar or crossed. Start again and move your hand farther toward each corner."
            showCalibrationTarget(); updateGuide()
            statusLabel.stringValue = captureNote; return
        }
        saved.removeAll { $0.cameraID == cameraID && $0.displayID == displayID }
        saved.append(SavedCalibration(cameraID: cameraID, displayID: displayID, desktopSignature: desktop.signature, mapping: mapping))
        saveCalibrations()
        cancelCalibration()
        statusLabel.stringValue = "Calibration saved. Test the cyan target in preview, then enable live Mac control."
    }

    private func tick() {
        let trusted = control.isTrusted
        permissionLabel.stringValue = trusted ? "Accessibility: allowed for this app" : "Window control blocked: macOS has not authorized this running copy."
        control.rememberFrontBrowser()
        permissionLabel.textColor = trusted ? .systemGreen : .systemOrange
        if liveEnabled && !trusted { pause(); statusLabel.stringValue = "Accessibility access was removed. Control paused." }
        let now = ProcessInfo.processInfo.systemUptime
        if let deadline = captureDeadline {
            if now >= deadline { finishCapture(at: now) }
            else {
                let count = Int(ceil(deadline - now))
                statusLabel.stringValue = "Capturing in \(count)… keep pointing at the target."
                if let display = selectedDisplayID {
                    overlay.show(at: desktop.calibrationTargets(for: display)[calibrationCamera.count], message: "\(count)… HOLD STILL\n\(calibrationCamera.count + 1)/4", live: false)
                }
            }
        }
        if running && !calibrating { handle(machine.expire(at: now), now: now) }
        updateGuide()
    }
    private func receive(_ frame: CameraFrame, cameraID: String) {
        guard running, frame.time >= startedAt, ProcessInfo.processInfo.systemUptime - frame.time < 0.25 else { return }
        if cameraID == selectedCameraID { preview.frameData = frame; cameraReady = true }
        let samples = frame.hands.map { hand in
            SpatialHandGeometry(image: hand.image, world: hand.world).sample(
                pinchThreshold: sensitivity.doubleValue,
                retainingPinch: frame.hands.count == 1 && machine.dragging && activeRoute?.cameraID == cameraID
            )
        }
        let sample = samples.count == 1 ? samples[0] : nil
        if cameraID == selectedCameraID {
            if calibrating { frames.append(CalibrationFrame(time: frame.time, hand: sample)) }
            poseSeen = sample?.pose; poseSeenAt = frame.time
            previewHandCount = frame.hands.count
            partialHand = sample == nil && frame.hands.count == 1
        }
        frames.removeAll { frame.time - $0.time > 0.8 }
        if calibrating {
            if cameraID == selectedCameraID {
                let pose = sample?.pose.rawValue.uppercased() ?? (partialHand ? "POSE UNCERTAIN" : "HAND NOT RESOLVED")
                gestureLabel.stringValue = "CALIBRATING · \(samples.count == 2 ? "USE ONE HAND" : pose) · 3D · PREVIEW"
            }
            return
        }
        if twoHandsTakePriority(samples.map { $0?.pose }, cameraID: cameraID, at: frame.time) {
            observations.removeValue(forKey: cameraID)
            return
        }
        if let sample { observations[cameraID] = (frame.time, sample) }
        else { observations.removeValue(forKey: cameraID) }
        if !machine.dragging, !machine.scrolling, sample?.pose == .point {
            let calibrations = availableCalibrations
            let onlyDisplay = desktop.ids.count == 1 && calibrations.count == 1
            let matches = calibrations.filter { route in
                guard let observation = observations[route.cameraID], frame.time - observation.time < 0.22,
                      observation.hand.pose == .point, let p = route.mapping.map(observation.hand.aim) else { return false }
                return onlyDisplay || ((-0.03...1.03).contains(p.x) && (-0.03...1.03).contains(p.y))
            }
            let selection = selector.update(matches: matches.map(\.id), at: frame.time,
                                            locked: cursorHold.isLocked, onlyDisplay: onlyDisplay)
            if selection != activeRoute?.id {
                resetInteraction()
                activeRoute = matches.first { $0.id == selection }
            }
            guard activeRoute != nil else {
                gestureLabel.stringValue = "POINT · \(live ? "LIVE" : "PREVIEW") · NO DISPLAY SELECTED"
                statusLabel.stringValue = matches.count > 1
                    ? "Pointing is ambiguous between screens or cameras. Reposition or recalibrate so each display has a distinct pointing region."
                    : matches.isEmpty ? "Aim inside a calibrated display region. If your hand is outside the camera view, control pauses."
                    : "Hold the point steady to select \(desktop.displayName(matches[0].displayID))…"
                return
            }
        }
        guard let route = activeRoute, route.cameraID == cameraID else {
            if activeRoute == nil { gestureLabel.stringValue = "DISARMED · \(sample?.pose.rawValue.uppercased() ?? "NO HAND") · \(live ? "LIVE" : "PREVIEW")" }
            return
        }
        cursorHold.observePose(sample?.pose, at: frame.time)
        let actions = machine.update(sample, at: frame.time)
        handle(actions, now: frame.time)
        if !machine.armed && sample?.pose == .point {
            statusLabel.stringValue = "Hold your pointing pose to arm the cursor on \(desktop.displayName(route.displayID))."
        }
        let mode: String
        if machine.scrolling { mode = "SCROLLING" }
        else if machine.dragging { mode = "GRABBING" }
        else if cursorHold.isLocked { mode = "TARGET HELD" }
        else { mode = machine.armed ? "ARMED" : "DISARMED" }
        gestureLabel.stringValue = "\(mode) · \(sample?.pose.rawValue.uppercased() ?? "NO HAND") · \(desktop.displayName(route.displayID)) · \(live ? "LIVE" : "PREVIEW")"
    }

    private func resetTwoHandGestures() {
        twoHandGesture = TwoHandGesture()
        browserTabTarget = nil
        tabCloseTask?.cancel()
        tabCloseTask = nil
        twoHandCameraID = nil
        browserCloseSequence.reset()
    }

    private func twoHandsTakePriority(_ poses: [Pose?], cameraID: String, at now: Double) -> Bool {
        let trackingPair = twoHandGesture.suppressesSingleHand(at: now)
        // Once a pair is seen, keep its camera even as the one-hand route resets.
        let commandCamera = trackingPair ? twoHandCameraID : activeRoute?.cameraID ?? selectedCameraID
        guard cameraID == commandCamera else { return trackingPair || poses.count == 2 }
        if twoHandCameraID != cameraID {
            resetTwoHandGestures()
            twoHandCameraID = cameraID
        }
        let wasReadyToClose = twoHandGesture.readyCommand == .closeTab
        let action = twoHandGesture.update(poses, at: now)
        let readyToClose = twoHandGesture.readyCommand == .closeTab
        if readyToClose && !wasReadyToClose {
            browserTabTarget = live ? control.browserTabTarget() : nil
            if let target = browserTabTarget {
                let closingWindow = browserCloseSequence.action(for: target, at: now) == .window
                setCloseTabStatus("\(target.name) selected. Close both hands to close \(closingWindow ? "this window and its tabs" : "the active tab").")
            } else {
                setCloseTabStatus(live
                    ? "Click the Chrome tab you want to close, then close both hands."
                    : "Gesture armed. Close both hands into fists.")
            }
        } else if wasReadyToClose && !readyToClose && action != .closeTab {
            browserTabTarget = nil
            setCloseTabStatus("Two fists weren’t recognized in time. Show both open palms and try again.")
        }
        guard twoHandGesture.suppressesSingleHand(at: now) else { return false }

        if !trackingPair {
            resetInteraction()
            selector.reset()
            observations.removeAll()
        }
        let hint: String
        if action == .closeTab {
            hint = "CLOSE TAB"
            finishTabClose()
        } else if action == .missionControl {
            hint = "MISSION CONTROL"
            handle([.missionControl], now: now)
        } else if poses.count < 2 {
            hint = "SHOW BOTH HANDS"
        } else if readyToClose {
            hint = "CLOSE BOTH HANDS"
        } else if twoHandGesture.readyCommand == .missionControl {
            hint = "OPEN BOTH PALMS"
        } else {
            hint = poses.map { $0?.rawValue.uppercased() ?? "UNCERTAIN" }.joined(separator: " + ")
        }
        let count = poses.count == 2 ? "TWO HANDS" : poses.count == 1 ? "ONE HAND" : "NO HANDS"
        gestureLabel.stringValue = "\(count) · \(hint) · \(live ? "LIVE" : "PREVIEW")"
        return true
    }

    private func finishTabClose() {
        defer { browserTabTarget = nil }
        guard live else {
            setCloseTabStatus("Gesture recognized in preview. Live control is required to close a tab.")
            return
        }
        guard tabCloseTask == nil else { return }
        guard let target = browserTabTarget ?? control.browserTabTarget() else {
            browserCloseSequence.reset()
            setCloseTabStatus("Gesture recognized. Click the Chrome tab you want to close and try again.")
            return
        }
        tabCloseTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            defer { if !Task.isCancelled { tabCloseTask = nil } }
            guard live else { return }
            let action = browserCloseSequence.action(for: target, at: ProcessInfo.processInfo.systemUptime)
            let failure = await control.closeBrowser(target, action: action)
            guard !Task.isCancelled else { return }
            if let failure {
                browserCloseSequence.reset()
                setCloseTabStatus(failure)
            } else {
                browserCloseSequence.recordSuccess(action, target: target, at: ProcessInfo.processInfo.systemUptime)
                setCloseTabStatus(action == .window
                    ? "Sent close-window command to \(target.name)."
                    : "Sent close-tab command to \(target.name). Repeat palms → fists within 3 seconds to close this window.")
            }
        }
    }

    private func setCloseTabStatus(_ message: String) {
        closeTabStatus.stringValue = "Close tab • \(message)"
        closeTabStatus.isHidden = false
    }

    private func resetInteraction() {
        _ = machine.reset(); control.release(); filter.reset(); overlay.hide()
        cursorHold.reset()
        control.clearSelection()
        lastPoint = nil; lastAim = nil; dragAnchor = nil; dragAim = nil; dragScreen = nil
        activeRoute = nil
    }

    private func aim(_ point: Point, at now: Double) {
        guard let route = activeRoute, let mapped = route.mapping.map(point), let r = desktop.bounds(of: route.displayID) else { return }
        let bounded = Point(min(1, max(0, mapped.x)), min(1, max(0, mapped.y)))
        let filtered = filter.update(bounded, at: now)
        let proposed = desktop.clamp(CGPoint(x: r.minX + filtered.x * (r.width - 1),
                                            y: r.minY + filtered.y * (r.height - 1)))
        let wasLocked = cursorHold.isLocked
        let held = cursorHold.update(Point(Double(proposed.x), Double(proposed.y)), at: now)
        let target = CGPoint(x: held.x, y: held.y)
        lastPoint = target
        if !wasLocked || !cursorHold.isLocked { lastAim = point }
        if !wasLocked && cursorHold.isLocked {
            statusLabel.stringValue = "Target held. Open your palm to click here. The cursor stays held until you return to a clear pointing pose."
        } else if wasLocked && !cursorHold.isLocked {
            statusLabel.stringValue = "Aiming again. Hold steady for two seconds to keep the target in place, then open your palm to click."
        }
        let mode = cursorHold.isLocked ? "TARGET HELD" : live ? "LIVE" : "PREVIEW"
        overlay.show(at: target, message: "\(desktop.displayName(route.displayID))\n\(mode)", live: live)
        if live { control.moveCursor(target) }
    }
    private func handle(_ actions: [GestureAction], now: Double) {
        for action in actions {
            switch action {
            case .armed:
                statusLabel.stringValue = "Armed for \(activeRoute.map { desktop.displayName($0.displayID) } ?? "display"). Point to aim, then open your palm to click."
            case .disarmed:
                control.release(); filter.reset(); overlay.hide()
                cursorHold.reset()
                control.clearSelection()
                lastPoint = nil; lastAim = nil; dragAnchor = nil; dragAim = nil; dragScreen = nil
                activeRoute = nil; selector.reset()
                gestureLabel.stringValue = "DISARMED · \(live ? "LIVE" : "PREVIEW")"
                statusLabel.stringValue = "Disarmed. Hold a pointing gesture to arm again."
            case .cursor(let point): aim(point, at: now)
            case .scrollStarted:
                control.clearSelection()
                guard let target = lastPoint else {
                    statusLabel.stringValue = "Point inside the page or window you want to scroll first."
                    continue
                }
                let isLive = live
                overlay.show(at: target, message: isLive ? "SCROLL" : "PREVIEW SCROLL", live: isLive)
                statusLabel.stringValue = "Move your hand up or down while both fingers are raised."
            case .scroll(let pixels):
                if live, let target = lastPoint { control.scroll(pixels, at: target) }
            case .scrollEnded:
                overlay.hide()
                filter.reset()
                statusLabel.stringValue = "Scroll ended. Point to aim again."
            case .click, .selectWindow:
                guard let target = lastPoint else {
                    statusLabel.stringValue = "Point at the spot you want to click first."
                    continue
                }
                let isLive = live
                let selectsWindow = action == .selectWindow
                if isLive { overlay.hide() }
                if isLive && !control.click(at: target, selectWindow: selectsWindow) {
                    statusLabel.stringValue = "Could not click. Check Accessibility access and release the mouse button if held."
                    continue
                }
                overlay.show(at: target, message: isLive ? "CLICK" : "PREVIEW CLICK", live: isLive)
                let clickMessage = isLive ? "Clicked at your last pointing position." : "Preview click at your last pointing position."
                statusLabel.stringValue = selectsWindow ? clickMessage + " Close your palm to minimize the selected window." : clickMessage
            case .minimizeSelectedWindow:
                if live {
                    if let reason = control.minimizeSelection() {
                        statusLabel.stringValue = reason
                    } else {
                        overlay.hide()
                        statusLabel.stringValue = "Minimized the selected window."
                    }
                } else {
                    if let target = lastPoint { overlay.show(at: target, message: "PREVIEW MINIMIZE", live: false) }
                    statusLabel.stringValue = "Preview minimize at your last pointing position."
                }
            case .missionControl:
                if live { control.missionControl() }
                statusLabel.stringValue = live ? "Opened Mission Control." : "PREVIEW: recognized your Mission Control gesture."
            case .grab(let anchor):
                guard let target = lastPoint, let lastAim else {
                    statusLabel.stringValue = "Point at a window before pinching."; continue
                }
                dragAnchor = anchor; dragAim = lastAim; dragScreen = target; filter.reset()
                cursorHold.reset()
                if live, let error = control.grab(at: target) { statusLabel.stringValue = error }
                else { statusLabel.stringValue = live ? "Window grabbed. Move your hand; open the pinch to drop." : "PREVIEW: grabbed target. Move your pinched hand to test the drag." }
            case .drag(let anchor):
                guard let route = activeRoute, let r = desktop.bounds(of: route.displayID),
                      let start = dragAnchor, let reference = dragAim, let screen = dragScreen,
                      let mappedStart = route.mapping.map(reference),
                      let mappedNow = route.mapping.map(Point(reference.x + anchor.x - start.x, reference.y + anchor.y - start.y)) else { continue }
                let filtered = filter.update(Point(mappedNow.x - mappedStart.x, mappedNow.y - mappedStart.y), at: now)
                let target = desktop.clamp(CGPoint(x: screen.x + filtered.x * r.width, y: screen.y + filtered.y * r.height))
                overlay.show(at: target, message: live ? "GRAB" : "PREVIEW GRAB", live: live)
                if live {
                    control.moveCursor(target)
                    if let error = control.drag(to: target) { statusLabel.stringValue = error }
                }
            case .release:
                control.release(); dragAnchor = nil; dragAim = nil; dragScreen = nil
                filter.reset(); overlay.hide(); lastPoint = nil; lastAim = nil
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        control.release(); cameras.values.forEach { $0.stop() }; timer?.invalidate()
        if let globalKeys { NSEvent.removeMonitor(globalKeys) }
        if let localKeys { NSEvent.removeMonitor(localKeys) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        cameraObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
