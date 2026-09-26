# Minority

A native menu bar app for recording your own one-hand or two-hand gestures and assigning actions to them. Gesture Manager shows a live 21-joint skeleton for each detected hand, in different colors, plus per-finger extension readouts. The preview starts horizontally inverted from the previous version; use **Mirror video horizontally** in Gesture Manager to switch its orientation.

## Build and launch

```sh
sh build-app.sh
open "build/Minority.app"
```

The build script creates `build/Minority.app`. On first use, allow camera access. To send actions to other apps, add Minority under System Settings → Privacy & Security → Accessibility.

The build script uses a valid code-signing identity from your Keychain (preferably Apple Development) instead of ad hoc signing. This keeps the app's Accessibility identity stable across rebuilds. If no identity is available, install an Apple Development certificate or set `GESTURE_CODESIGN_IDENTITY` to an existing valid identity. After switching from an older ad hoc build, remove the old Gesture Control entry in Accessibility settings, add `build/Minority.app`, enable it, and relaunch the app once. Subsequent builds should retain the permission.

## Create a gesture

1. Open **Gesture Manager** from the menu bar item.
2. Choose **One hand** or **Two hands**, then click **Record new gesture**. A three-second countdown gives you time to hold the starting pose.
3. Hold a static pose steadily or perform the gesture once, then click **Finish recording**. The recording also stops automatically after five seconds. The manager shows how many tracked frames were captured and lets you retry if tracking fails.
4. Use **Record 2 of 3** and **Record 3 of 3** to capture the same movement two more times. Each recording has its own countdown. Failed recordings do not count, and canceling a repetition keeps the completed examples. After at least three recordings, click **Test gesture**, wait for the three-second countdown, and perform it again. The test stays open for 15 seconds and shows whether it is waiting for a hand, comparing the movement, or confirming a match. No action is sent during the test. Save becomes available only after at least three recordings and a successful recognition test; otherwise, test again or record a clearer sample.
5. Enter a name, choose an action, and save it. For a keyboard action, click **Record shortcut** and press the key or combination you want.
6. Enable gesture control from the menu bar. You can select any saved gesture to rename it, change its action, disable it, add another recording, or delete it.

Actions available now are scroll down, scroll up, browser back, and a recorded keyboard shortcut. Matching uses local Vision hand landmarks, including detailed thumb and finger joint positions. An on-device few-shot matcher compares live motion with your saved examples using bounded dynamic time warping, searching durations from half to twice the recorded duration and allowing changes in timing within a movement, starting position, and movement size. New recordings retain 32 feature frames; older 16-frame recordings remain readable. Two-hand matching uses one shared timing alignment so both hands must reproduce their recorded coordination. Starting and final poses contribute extra weight to reduce incomplete or wrong-pose matches. Ambiguous matches between different saved gestures are ignored instead of triggering the wrong action. Two-hand templates require both hands to be visible; one-hand templates can match either tracked hand. Existing one-hand recordings remain usable. At least three recordings are required for detection, including for existing saved gestures. Incomplete gestures remain in the library with a progress indicator; use **Add another recording** to complete them. For best results, add 3–5 recordings of the same gesture with natural variations in speed and distance. Each recording is an additional example for that gesture; no model training or video storage is required. Recognition quality still depends on camera visibility and how distinct the saved gestures are. Adjust sensitivity in the manager if needed.

Turn on **Debug detection log** in Gesture Manager to open a live window of recognized saved gestures, their bound actions, and whether an action was sent. Debug recognition works even when gesture control is off or Accessibility is unavailable; no action is sent in those cases. The log keeps at most 100 entries in memory, can be cleared, and is never saved.

Saved gesture templates contain normalized hand shape and movement data and are stored at `~/Library/Application Support/Minority/gestures.json`. Camera frames and video are never stored or uploaded. Gesture control is off by default.

Run the focused tests with `swift test`.

New recordings include 15 joint bend angles (three per finger) and wrist-relative joint positions scaled by wrist-to-middle-knuckle length. Shape comparison uses Euclidean angle distance with a small normalized-position contribution. Camera aspect ratio is corrected before computing angles; normalization removes translation, scale, and rotation in the image plane, but does not compensate for arbitrary 3D viewpoint changes. Old templates retain their legacy feature comparison. Static poses retain 16 feature examples; moving gestures retain their DTW sequences.

Static poses require the same unambiguous gesture in five of the last seven evaluated camera frames. Dynamic movements require two of the last three complete DTW sequence matches, so short motions can finish without holding their endpoint for five matching windows. Tracking loss clears pending votes, and the existing cooldown and release requirement still apply. Points below 0.3 confidence are excluded; unavailable joint coordinates and angles carry validity masks and are excluded from comparison. A frame still needs the wrist, middle knuckle, at least nine valid angles and 24 normalized coordinates; losing one fingertip no longer discards the whole hand. Keep all fingers visible. No images or video are saved.

The Test session keeps one stable gesture identity throughout the replay, so repeated matches can satisfy temporal confirmation. Palm-driven recordings trim idle time using smoothed palm movement; finger jitter does not extend the capture. Matching those movements prioritizes the trajectory while allowing small incidental finger bends. Finger-only gestures and static poses retain full hand-shape comparison.
