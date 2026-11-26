# Tony Stark · Mac gesture controller (experimental)

A native macOS companion to the Merlin visualizer. It uses a bundled MediaPipe model to estimate 21 hand landmarks in 3D locally, and Accessibility to move ordinary application windows. It does not use a server, microphone, screen recording, or an AI API. Camera frames are not recorded or uploaded.

Requires an Apple Silicon Mac, macOS 14+, Xcode Command Line Tools, Swift 6+, and Python 3 for the build-time asset download. The running app does not need Python. The existing browser visualizer still runs separately with its original npm commands.

## Build and launch

From the repository root:

```sh
cd macos
python3 scripts/fetch-tracker.py
swift test
bash scripts/build-app.sh
open "build/Tony Stark.app"
```

Launch the app bundle, rather than the raw Swift executable, so macOS can associate Camera and Accessibility permissions with its bundle identity. The build is locally ad-hoc signed. After a rebuild, macOS may require removing and re-adding the app under Accessibility. For a stable development signature, set `SIGN_IDENTITY` to a signing identity you own when running the build script.

If Accessibility shows Tony Stark switched on while the app reports that window control is blocked, the saved grant may belong to a previous ad-hoc build. In Privacy & Security → Accessibility, select the old Tony Stark row, remove it with **−**, then use **+** to add the current `macos/build/Tony Stark.app` and enable it. The app's **Show this app in Finder** button reveals the exact current copy. Authenticate in macOS yourself if requested. Return to the app; it checks permission automatically. If macOS still does not recognize the grant, quit and reopen that same app. Calibration remains saved. Avoid rebuilding again during this permission setup, since another ad-hoc build changes the code identity.

The live-control checkbox remains disabled until the camera, preview check, calibration, and permission are ready. Enabling it validates these requirements before changing the running session, and rejected requests keep their explanation visible.

The build script fetches the pinned MediaPipe 1.2.3 native library from its official PyPI wheel (with SHA-256 verification) and Google's versioned hand model, then bundles both for offline use. It signs the nested native library before signing the app. The app loads its C API directly; it does not install or launch Python packages. License and notice files are included in the app's Resources/MediaPipe folder.

## First setup

1. Follow the highlighted setup card at the top of the app. Select your camera and laptop screen, then choose **Start camera**. Allow Camera access when macOS asks. If access is denied, the guide offers **Open Camera settings** and lets you retry. Keep your wrist and knuckles visible with your index finger extended and the other fingers folded. The cyan skeleton shows the model's hand estimate; the yellow INDEX ring marks the fingertip. Live feedback confirms the full pose. Estimated 3D joints help recognize a finger aimed toward the camera, but severe occlusion can still prevent tracking. If the app only sees a fingertip, tilt your hand slightly so the wrist and knuckles are visible.
2. Choose **I’m ready — show the first target**. Point toward the cyan circle, press **Space** (or **Capture this target**), and hold still through the three-second countdown. Repeat for upper left, upper right, lower right, and lower left. The final 0.6 seconds must contain a steady pointing hand. Failed captures stay on the same target with a specific retry instruction. **Previous target** lets you redo the last capture; **Cancel setup** exits calibration. Keep the app focused so Space reaches it.
3. Test pointing in preview. The cyan target should follow your intended position on the selected screen. Choose **The circle follows my finger — continue** when it feels right. If it does not, choose **Calibrate aiming** to retry. Live control stays unavailable until you complete this preview check.
4. If an external monitor is connected, select that display and repeat calibration while pointing toward it. The same laptop camera can have a separate calibration for each display. If you instead have a webcam on the monitor, select that camera and calibrate it for the monitor. All cameras with a valid saved calibration run together when cameras are started; the dropdown selects the preview and calibration camera.
5. The final guide step offers **Open Accessibility settings…** if needed. Enable **Tony Stark**, return to the app, and choose **Enable live Mac control**. Hold a pointing gesture again to arm it.

The menu bar hand icon reopens the controller and provides Pause and Quit. **Esc** turns live control off; global Escape monitoring requires Accessibility access. Camera capture continues in preview until you stop the cameras or quit.

## Commands

| Gesture | Behavior |
| --- | --- |
| Hold an index-finger point toward a calibrated display | Arm after 0.75 seconds of visible pointing. With multiple camera/display pairs, hold for an additional 0.3 seconds to select the pair. |
| Point while armed | Move the target; in live mode, move the Mac pointer |
| Keep the pointing target steady for two seconds | Hold the cursor at that spot while forming a command. **TARGET HELD** appears. Small fingertip movements and briefly misread pointing during an open-palm transition do not move the target. |
| Return from a hand command to a clear index-finger point for about 0.4 seconds | Resume aiming. Opening your palm, moving your fingertip, or briefly misreading a point cannot release the hold. You do not need to point away from the target. |
| Hold up index and middle fingers, then move your hand vertically | Scroll at the last pointing position. Keep the other fingers folded. Move up to go down the page, and down to go back up. Lower the fingers to stop. |
| Point → open palm | Click at the last pointing position and remember the window there. |
| Close that palm into a fist | Minimize the window you selected if it is still focused. |
| Aim, then fist → palm → fist | Single left-click at the last pointing position. Hold the fist and palm briefly, then close again within about half a second. Preview shows the click at the target. |
| Two open palms → two fists | Close the active tab in the selected browser window (including Safari, Chrome, Firefox, Edge, and Brave). Show both open palms until **CLOSE BOTH HANDS** appears, then make two fists. The controller remembers the browser window you last selected and can bring it forward if Tony Stark is in front. |
| Repeat two palms → two fists within three seconds | Close that same browser window, including its remaining tabs. Changing browser windows, pausing control, or a failed close command clears the repeat. A later gesture closes another tab normally. |
| Clap twice quickly in the camera view | Open Mission Control. Start with both hands apart and bring them together twice, separating between claps. Complete the second clap within about 1.2 seconds of the first. **CLAP ONCE MORE** confirms the first clap. This uses visible hand motion, requires live control for the real action, and does not use the microphone. |
| Two fists → two open palms | Open Mission Control without arming the pointer. Keep both hands visible in the same camera. The status reads **OPEN BOTH PALMS** once the fists register. With two hands visible, pointing, clicking and dragging pause. |
| Make a fist, then hold an open palm | Open Mission Control after about a second with the palm open, allowing time to complete a click first. |
| Bring thumb, index and middle fingertips together | After 0.18 seconds, grab the window at the last pointing target |
| Move the pinched hand | Move that window using relative palm motion; the original camera/display mapping stays locked during the grab |
| Open the pinch | Drop after a short release dwell |
| Hand lost for 0.4 seconds | Release and disarm |
| Esc, menu bar Pause, or uncheck live control | Turn live control off and release |

The pinch sensitivity slider adjusts how close the three fingertips must be. Increasing it makes pinching easier. It is normalized to hand size, with additional hysteresis during a grab.

## Displays, cameras, and physical pointing

Gesture recognition uses **estimated 3D hand shape**, including joint angles and finger extension. A finger directed toward the lens no longer needs to look long in the image to count as extended. This replaces the native prototype's earlier 2D-only Vision classifier. Missing or invalid hand estimates never become synthetic pointing detections; the app pauses instead.

Screen targeting still uses **calibrated 2D fingertip regions**, not measured camera depth or a reconstructed pointing ray to a physical screen. It learns how your visible fingertip positions map onto each screen through a four-point projective transform. Moving your chair, changing your arm posture, or moving a camera can invalidate that relationship. It does not infer attention, gaze, or speech.

A point must match exactly one calibrated camera/display region. With one display and one saved camera/display pair, the app picks that pair immediately and keeps the pointer at the screen edge when you aim slightly beyond it. If the laptop and monitor calibrations overlap, or both webcams see a pointing hand in valid regions, the controller clears the selection and reports ambiguity. Recalibrate with more distinct hand positions or use **Forget this pair** to remove an overlapping camera/display assignment. Being outside the laptop region does **not** automatically select the external display. If the camera cannot see your hand, it cannot read the command. This limitation needs testing with your physical desk arrangement; accurate physical ray pointing would require additional geometry/depth estimation and calibration.

Display bounds come from macOS, so monitors above, below, or to either side use their configured global coordinates. Normal pointing stays on its selected display. A grabbed window can move onto another connected display while the source camera stays locked. Coordinates in gaps between displays clamp to the nearest actual screen. Display/camera connection changes pause live control. Display layout changes invalidate saved calibrations for the previous arrangement.

Mission Control is a system-wide macOS action. The gesture opens it, but does not rearrange its thumbnails or Spaces. The app moves regular windows through Accessibility; it does not drag browser tabs, files, or arbitrary UI items, and does not move full-screen windows. Some applications may refuse Accessibility window moves. These cases produce a status message.

## Verification

```sh
swift test
bash scripts/build-app.sh
```

Automated tests cover activation, continuous dwell, Mission Control transitions, pinch/release, tracking loss, calibration, filtering, and display/camera route selection. They also rotate a 3D pointing hand through the camera axis, check that a real fist stays distinct, and load the native inference library against blank frames. They do not open Mission Control or move real windows. For real-image integration checks, set `TONYSTARK_POINTING_IMAGE` and `TONYSTARK_TWO_HAND_IMAGE` to local paths for MediaPipe's public `pointing_up.jpg` and `right_hands.jpg` fixtures before running `swift test`.

Hardware acceptance checks after granting permissions:

- Preview: check pointing, fist, palm, and three-finger pinch in your actual lighting. Make sure an unintended hand pose does not activate a command.
- In preview, clap twice with both hands visible; check for **CLAP ONCE MORE**, then **DOUBLE CLAP · MISSION CONTROL**. One clap, keeping hands together, and ordinary palm/fist commands must not count as a double clap. Repeat in live mode to open Mission Control. Avoid hiding a hand behind the other at contact: missing detections do not count as claps.
- Aim at a small Dock or toolbar item, hold steady for two seconds until **TARGET HELD** appears, then open your palm. Keep it open and move your hand: the cursor and click should stay on the item. Return to an index-only point for about 0.4 seconds to resume aiming. Repeat near the screen edge and across calibrated displays.
- Calibrate both displays; point between them and verify the named target display. Overlapping regions must show ambiguity with no live movement.
- Live: aim inside an ordinary window, pinch, move, and release. The window should stay still while forming/releasing the pinch. Try moving a window across the display boundary.
- Aim at an item in a Finder window. Make a fist, briefly open your palm, then close it again. The item should receive one left-click. Hold the palm open after a fist to open Mission Control instead. Press Esc to close Mission Control or pause live control.
- Remove the hand, press Esc, and disconnect a camera/display during a grab. The grab must release and live control must pause on connection changes.
- With two cameras, test each source separately, then both. When both see a valid pointing gesture, selection should pause rather than switch unpredictably.
