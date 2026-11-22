# Moonlet: Live Wallpaper and Ambient Music for macOS

Date: 2026-11-22
Status: Draft, awaiting review

## 1. Summary

Moonlet is a personal macOS menu bar app. It plays a live wallpaper behind the
desktop icons on every screen and plays ambient music alongside it. It is built
for one user on one machine (Apple M2 laptop, macOS 27.2, Xcode 27, Swift 6.4).
Claude writes the code layer by layer, and the user reviews each layer. See
section 11.

## 2. Requirements

| Area | Requirement |
|---|---|
| Visuals | Three wallpaper types: looping video, Metal shader, web page (local HTML or URL) |
| Music | Local audio files as playlists, internet radio streams, per-wallpaper soundtracks |
| Audio rule | A wallpaper's soundtrack replaces the selected playlist or stream. Wallpapers without one keep the selection. |
| Controls | Menu bar icon for quick actions, plus a settings window for the library |
| Displays | Same wallpaper on every connected screen. Audio plays once. |
| Visual pausing | Visuals pause when the wallpaper is covered, and when the screen locks or the Mac sleeps |
| Music pausing | Music pauses while another app plays audio, and when the screen locks or the Mac sleeps. Music keeps playing when visuals pause. |
| Rotation | Manual pick, or a pack that rotates on a timer or by time of day |
| Library | A watched folder on disk is the source of truth. Drag-to-import in the settings window writes into that folder. |
| Interaction | None. Wallpapers never receive mouse or keyboard input. Clicks pass through to Finder. |
| Language | Swift, SwiftUI, AppKit |

### 2.1 Defaults and non-goals

- Personal build only. Not distributed, not on the App Store.
- Minimum target: macOS 26.
- Launches at login.
- Desktop icons stay visible on top of the wallpaper.
- No pausing on battery or in Low Power Mode.
- No lock screen or login screen wallpaper. macOS has no public API for those.
- No media key or Now Playing integration, so the keyboard play/pause key stays
  with Spotify or Music.
- No mouse or audio reactivity in wallpapers.
- No wallpaper spanning across screens, and no different wallpaper per screen.

### 2.2 App icon

The icon is a central planet with one circular orbit ring around it, and a
small moon sitting on the ring. The menu bar version is a monochrome template
image of the same shape.

Both are drawn in code. `tools/RenderIcon` writes the app icon set, and
`make icon` regenerates it. `MenuBarIcon` draws the 18-point template image at
runtime. A tilted-ring variant was tried in Layer 9 and dropped in favor of the
flat ring.

## 3. Approach

Moonlet puts one borderless window on each screen at the desktop window level
(`CGWindowLevelForKey(.desktopWindow)`), below the desktop icon level. Each
window has:

- `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]`
- `ignoresMouseEvents = true`
- No shadow, opaque, full screen frame

The window hosts one of three renderers:

- Video: `AVPlayerLayer`
- Metal: `MTKView`
- Web: `WKWebView`

SwiftUI builds the menu bar (`MenuBarExtra`) and the settings window. AppKit
owns the desktop windows.

Rejected alternatives:

- Calling `NSWorkspace.setDesktopImageURL` repeatedly: cannot play smooth video
  or shaders.
- Hooking the system Aerial wallpaper extension: private API, breaks between
  macOS releases, video only.

## 4. Components

```
Library ───┐                           ┌─> DesktopWindowController (per screen) ─> Renderer
Scheduler ─┼─> AppState (@Observable) ─┤
Monitors ──┘                           └─> AudioController
MenuBar / Settings UI <──> AppState
```

Monitors and the scheduler report events to `AppState`. `AppState` tells the
renderers and the audio what to do. Renderers and audio never talk to each
other directly.

| Component | Responsibility |
|---|---|
| `AppShell` | SwiftUI `App`. `LSUIElement` is set, so there is no Dock icon. Hosts the `MenuBarExtra` and the settings window. Registers launch at login with `SMAppService.mainApp`. |
| `AppState` | Holds the current wallpaper or pack, the music selection, the volume, and the two pause-reason sets: music and visuals. Persists state to `UserDefaults`. Main actor. |
| `DesktopWindowController` | Owns one desktop-level window per `NSScreen`. Rebuilds the windows on `NSApplication.didChangeScreenParametersNotification`. |
| `WallpaperRenderer` | Protocol with `load`, `play`, `pause`, and `tearDown`. Implemented by `VideoRenderer`, `MetalRenderer`, and `WebRenderer`. |
| `Library` | Scans the library folder, parses manifests, watches for file changes with FSEvents, and performs imports. |
| `Scheduler` | Runs the active pack. Tells `AppState` which wallpaper to show next. |
| `AudioController` | Applies the audio rule. Plays playlists with `AVQueuePlayer`, streams with `AVPlayer`, and soundtracks with `AVQueuePlayer` plus `AVPlayerLooper`. Handles fades. |
| `PlaybackMonitor` | Watches the Core Audio process list. Publishes `otherAudioActive: Bool` and the name of the app playing. |
| `VisibilityMonitor` | Checks window coverage and each desktop window's occlusion. Publishes a covered flag per screen. |

### 4.1 Sharing across screens

- `VideoRenderer` drives one `AVPlayerLayer` per screen from a single shared
  `AVPlayer`, so each video decodes once.
- `MetalRenderer` compiles each shader once and shares the `MTLDevice`,
  `MTLLibrary`, and pipeline state across screens. Each screen has its own
  `MTKView`.
- `WebRenderer` needs one `WKWebView` per screen. Web views cannot be shared.

### 4.2 Testability

Each monitor is a small class with one published output. Each class that waits
on time takes a clock as an init parameter. Tests pass fake monitors and a fake
clock. The app passes the real ones.

## 5. Library folder format

The library folder defaults to `~/Moonlet` and can be changed in settings.
Plain files are the source of truth. The settings window only reads and writes
these files.

```
~/Moonlet/
  wallpapers/
    rain-window/   wallpaper.json, rain.mp4, rain.m4a
    aurora/        wallpaper.json, aurora.metal
    clock/         wallpaper.json, index.html
  packs/           workday.json, evenings.json
  music/           focus/*.mp3, sleep/*.flac
  streams.json
```

### 5.1 Wallpapers

Each wallpaper is one subfolder of `wallpapers/`. The folder name is the
wallpaper's ID. Each folder has a `wallpaper.json`:

```json
{
  "name": "Rain on Window",
  "type": "video",
  "source": "rain.mp4",
  "soundtrack": "rain.m4a",
  "volume": 0.8
}
```

| Field | Required | Values |
|---|---|---|
| `name` | yes | Display name |
| `type` | yes | `video`, `metal`, or `web` |
| `source` | yes | A file in the folder. For `web`, it may also be an `http` or `https` URL. |
| `soundtrack` | no | A file in the folder, or `"video"` to use the video's own audio track |
| `volume` | no | 0 to 1, default 1. Scales the soundtrack against the master volume. |
| `renderScale` | no | 0.25 to 1, default 1. Metal wallpapers render at this fraction of the screen's resolution and are scaled up, which cuts GPU work and memory for soft or heavy shaders. Ignored by video and web wallpapers. |
| `image` | no | Metal only. A `.png`, `.jpg`, or `.heic` file in the folder that the shader can sample. See section 5.2. |

Supported files:

- Video: `.mp4`, `.mov` (H.264 or HEVC)
- Audio: `.mp3`, `.m4a`, `.aac`, `.flac`, `.wav`
- Shaders: `.metal`
- Shader images: `.png`, `.jpg`, `.jpeg`, `.heic`
- Web: `.html`

Without a `soundtrack`, a video plays muted, and the selected playlist or
stream keeps playing.

A local web page loads with `loadFileURL(_:allowingReadAccessTo:)`, scoped to
its wallpaper folder.

### 5.2 Metal shader contract

The author writes one fragment function named `wallpaper`. Moonlet prepends a
header that defines the full-screen vertex shader and this struct:

```metal
struct Uniforms {
    float time;        // seconds of playing time, excludes paused time
    float2 resolution; // drawable size in pixels
};
```

The fragment function signature is:

```metal
fragment float4 wallpaper(VertexOut in [[stage_in]],
                          constant Uniforms& u [[buffer(0)]]);
```

`VertexOut` provides `float2 uv` in the 0 to 1 range. Moonlet compiles the
combined source at runtime with `MTLDevice.makeLibrary(source:options:)`.

When the manifest sets `image`, Moonlet loads it once with mipmaps and binds
it at `texture(0)`. A shader that wants it adds a parameter:

```metal
constexpr sampler linear(filter::linear, mip_filter::linear);

fragment float4 wallpaper(VertexOut in [[stage_in]],
                          constant Uniforms& u [[buffer(0)]],
                          texture2d<float> image [[texture(0)]]) {
    return image.sample(linear, in.uv);
}
```

The image is loaded with a bottom-left origin, so `in.uv` samples it upright.
The shader handles aspect ratio itself, using `image.get_width()` and
`image.get_height()`. Saving a new version of the image reloads it.

### 5.3 Packs

Each file in `packs/` is one pack. Wallpapers are referenced by ID.

Time-of-day pack:

```json
{ "name": "Workday", "mode": "timeOfDay",
  "slots": [{ "from": "07:00", "wallpaper": "aurora" },
            { "from": "19:00", "wallpaper": "rain-window" }] }
```

The active slot is the one with the latest `from` time at or before now. Times
before the first slot use the last slot, so the schedule wraps around midnight.

Timer pack:

```json
{ "name": "Evenings", "mode": "timer", "intervalMinutes": 30,
  "order": "shuffle", "wallpapers": ["aurora", "clock", "rain-window"] }
```

`order` is `shuffle` or `sequential`, and defaults to `sequential`. Shuffle
never repeats the same wallpaper twice in a row. `intervalMinutes` must be at
least 1.

Picking a single wallpaper from the menu stops the active pack. The active pack
is saved and resumes on launch. A timer pack restarts its rotation on launch.

`PackScheduler` checks the active pack every 15 seconds and on wake from sleep,
so a time-of-day pack switches within 15 seconds of its slot, even after the
Mac slept through it.

### 5.4 Music and streams

- Each subfolder of `music/` is a playlist, named after the folder. The tracks
  play in filename order, or shuffled.
- `streams.json` is an array of `{ "name": string, "url": string }`. Supported
  streams: HTTP MP3, HTTP AAC, and HLS.

### 5.5 Import

Files dropped on the settings window are copied, not moved:

- A video, `.metal`, or `.html` file creates `wallpapers/<slug>/` with the file
  and a generated `wallpaper.json`. The slug is the file name in lowercase,
  with spaces turned into hyphens, plus `-2`, `-3`, and so on if it is taken.
- An audio file is copied into a playlist folder the user picks, or a new one.

### 5.6 Invalid files

- `Library` skips a broken manifest. It lists the file and the parse error in
  the settings window's Problems list.
- If a pack references a missing wallpaper ID, the scheduler skips that entry,
  and the Problems list flags it.
- If a pack has no valid entries, it does nothing, and the Problems list flags
  it.

## 6. Audio behavior

### 6.1 Effective source

```
effective source = current wallpaper's soundtrack ?? music selection
```

The music selection is one playlist or one stream, or none. `AppState`
persists it.

- Soundtracks loop without a gap.
- Playlists use repeat-all, with a shuffle toggle.
- Streams play live.

### 6.2 Switching sources

When the effective source changes, the old source fades out and the new
source fades in at the same time, over 1.5 seconds. Fading them one after the
other would leave about 3 seconds of near silence.

When the user leaves a wallpaper with a soundtrack, the playlist resumes at the
track and position where it stopped. A stream rejoins live.

Music starts only after the first wallpaper is shown, so a wallpaper with a
soundtrack never briefly plays the playlist first. If no wallpaper is shown
within 5 seconds, music starts anyway.

### 6.3 Video soundtracks

For `"soundtrack": "video"`, `LoopingChannel` builds an audio-only
`AVMutableComposition` from the video file's audio track, so the video is not
decoded a second time. Audio and visuals stay independent, so
music continues while the visuals are paused. A small drift between the two is
acceptable.

### 6.4 Music pause reasons

Music plays only when the music pause-reason set is empty.

| Reason | Set when | Cleared when |
|---|---|---|
| `user` | The user presses pause | The user presses play |
| `otherAudio` | Another app has output audio for 3 continuous seconds | No other app has output audio for 5 continuous seconds |
| `system` | The screen locks, the display sleeps, or the Mac sleeps | Unlock or wake |

- An automatic pause fades out over 1 second.
- An automatic resume fades in over 2 seconds.
- Pressing play while `otherAudio` is set overrides it until the other audio
  stops. The next time another app starts playing, `otherAudio` applies again.
- The menu shows the active reason, for example "Paused: Safari is playing".
- A `user` pause is persisted across launches.

### 6.5 Detecting other playback

`PlaybackMonitor` uses the Core Audio process objects available since macOS
14.2:

- It listens to `kAudioHardwarePropertyProcessObjectList` on the system object
  to learn when audio processes appear and disappear.
- For each process object, it reads `kAudioProcessPropertyPID` and
  `kAudioProcessPropertyBundleID`.
- It polls `kAudioProcessPropertyIsRunningOutput` on every process object once
  per second. Layer 0 found that property listeners on this flag never fire on
  macOS 27.2, while polling catches every change.
- It ignores Moonlet's own PID, and every bundle ID in the ignore list.
- It ignores Moonlet's own WebKit helpers, whose app name starts with
  "Moonlet ", such as "Moonlet Graphics and Media".
- `otherAudioActive` is true when any remaining process is running output.
  Processes without a bundle ID, such as `afplay`, count.
- No permission prompt is needed.

**Default ignore list:**

| Bundle ID | Why |
|---|---|
| `systemsoundserverd` | Plays system sounds. A single sound held the output for 3 seconds in Layer 0. |
| `com.vorssaint.utils` | A utility app that mirrors other apps' output |

The ignore list is editable in settings.

**Naming the app that plays.** Browsers play audio from helper processes, so
the monitor maps each process to a display name for the menu:

1. If `NSRunningApplication(processIdentifier:)` has a name ending in
   " Graphics and Media", strip that suffix. Safari's
   `com.apple.WebKit.GPU` helper becomes "Safari".
2. Otherwise, if the bundle ID ends in `.helper`, strip it and look up the app
   with `NSRunningApplication.runningApplications(withBundleIdentifier:)`.
   `com.google.Chrome.helper` becomes "Google Chrome".
3. Otherwise, use the running application's name, then the bundle ID, then
   "Another app".

**Measured release times.** This is how long each app kept the output running
after its audio stopped, in Layer 0:

| App | Release time |
|---|---|
| Spotify | Under 1 second after pause |
| VLC | Under 1 second after playback ends |
| Safari | About 8 seconds after playback ends |
| Chrome | Releases on its own. Exact delay not measured. |

With the 5-second resume delay, music resumes about 13 seconds after Safari
stops. The delays stay at 3 seconds and 5 seconds.

The poll runs on a background queue. The monitor hops to the main actor before
publishing.

### 6.6 Streams failing

When a stream stalls or fails:

1. Moonlet retries after 2, 5, and 15 seconds.
2. After the third failure, it stops and shows the error in the menu.

It does not fall back to a playlist.

### 6.7 Output device

Audio follows the macOS default output device. Moonlet does not pick a device.

## 7. Visual behavior

### 7.1 Visual pause reasons

Visuals render only when the visual pause-reason set for a screen is empty.

| Reason | Set when | Cleared when |
|---|---|---|
| `covered` | The screen's wallpaper has been covered for 1 continuous second | Any part becomes visible. Resume is immediate. |
| `system` | The screen locks, the display sleeps, or the Mac sleeps | Unlock or wake |

Granularity:

- Video pauses only when every screen is paused, because one `AVPlayer` drives
  all screens.
- Metal and web pause per screen.

### 7.2 What pause does per renderer

| Renderer | Pause | Resume |
|---|---|---|
| Video | `AVPlayer.pause()`. Freezes on the last frame. | `play()` from the same position |
| Metal | `MTKView.isPaused = true` | `isPaused = false`. `time` continues from where it froze. |
| Web | `setAllMediaPlaybackSuspended(true)`, and the web view is hidden. Layer 6b found that WebKit only throttles itself when the window is fully occluded, which a window filling the usable area does not do: a covered Clock page still used about 6% CPU. Hiding the view brought it to about 3.3%, against about 2% for a paused video or shader. | `setAllMediaPlaybackSuspended(false)`, and the view is shown again. |

### 7.3 Detecting "covered"

Layer 0 showed that occlusion state alone is not enough. A fullscreen app and a
window filling the screen both left the desktop window "visible". So the
coverage check is the main signal, and occlusion is a second one.

A screen counts as covered when either signal says so:

1. **Coverage check.** `VisibilityMonitor` polls
   `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)`
   every second, so a pause lands within about 2 seconds. It looks at windows at layer 0 (normal app windows) that
   do not belong to Moonlet and have alpha above 0. If one window covers at
   least 95% of the screen's `visibleFrame`, the screen counts as covered.
   Layer 0 measured 100% for a fullscreen app and 98% to 100% for a window
   filling the screen.
2. **Occlusion.** It listens to `NSWindow.didChangeOcclusionStateNotification`.
   When `occlusionState` lacks `.visible`, the screen counts as covered. This
   catches the lock screen and some Space switches.

Extra rules from Layer 0:

- Every Space switch flips occlusion to hidden and back within about 0.2
  seconds. The 1-second covered delay in section 7.1 filters these flips out.
- On `NSWorkspace.activeSpaceDidChangeNotification`, the monitor runs the
  coverage check at once, instead of waiting for the next 2-second poll.
- CG window bounds use a top-left origin on the primary screen. The monitor
  converts each `NSScreen.visibleFrame` before comparing.

Window bounds and layers do not need Screen Recording permission.

**Lock and sleep.** The `com.apple.screenIsLocked` and
`com.apple.screenIsUnlocked` distributed notifications fired on lock and
unlock in Layer 0. These notifications, plus the `NSWorkspace` sleep and wake
notifications, set and clear the `system` reason.

### 7.4 Wallpaper lifecycle

```
loading -> playing <-> paused -> tornDown
loading -> failed
```

Switching wallpapers:

1. The new renderer loads behind the current one.
2. On its first frame, the two crossfade over 0.6 seconds.
3. Moonlet tears down the old renderer.

If loading fails, the current wallpaper stays. The menu shows the error, and
the Problems list records it.

### 7.5 Live shader editing

`MetalRenderer` watches its own wallpaper folder. When the `.metal` source
text changes:

1. `MetalRenderer` recompiles it.
2. On success, it swaps in the new pipeline state without resetting `time`.
3. On failure, the last working shader keeps running. The Problems list
   shows the compiler message. A `#line 1 "<file>"` directive after the
   header makes the compiler report the user's own line numbers.

If the selected wallpaper failed to load, the next library change retries
it, so a new shader can be fixed by saving again without re-picking it.

### 7.6 Web wallpapers

- Each screen gets its own `WKWebView`. A local page loads with read access
  to its wallpaper folder only.
- The crossfade waits for the page to finish loading, up to 10 seconds.
- A load failure is reported to the Problems list and clears on the next
  successful load.
- Injected scripts hide scrollbars and mute every `<audio>` and `<video>`
  element. Web Audio API sound is not muted.
- Local pages live-reload when any file in their folder changes.
- CSS animations cost a lot in a web view. In Layer 4, a slow full-screen CSS
  `transform` animation used about 11% CPU in total, against 1.3% with no
  animation. Driving the same motion from JavaScript at 10 updates per second
  used about 4.5%. Sample pages use the JavaScript approach.

### 7.7 Startup

On launch, Moonlet restores:

- the last wallpaper or pack
- the music selection
- the volume
- the shuffle setting
- the `user` music pause, if it was set when Moonlet quit

## 8. User interface

### 8.1 Menu bar panel

The menu bar icon opens a small SwiftUI panel (`MenuBarExtra` with the
`.window` style) rather than a plain menu, because a plain menu cannot hold a
volume slider. It contains:

- Current wallpaper or pack name
- Wallpaper picker: wallpapers and packs, grouped
- Music: play/pause, the current track or stream name, and the pause reason
  when paused
- Music selection picker: playlists and streams, plus a shuffle toggle
- Volume slider
- Errors, when any are active
- Open Settings
- Quit

### 8.2 Settings window

- **Library:** the folder path, with a change button. A grid of wallpapers
  showing name, type, and soundtrack. A drop zone for import.
- **Packs:** the list of packs and their entries. Editing happens in the JSON
  files. The window only displays them.
- **Music:** playlists and streams.
- **Ignore list:** bundle IDs for `PlaybackMonitor`. The user can add one from
  a list of running apps.
- **Problems:** broken manifests, missing pack entries, shader compile errors,
  and stream failures.
- **General:** launch at login.

## 9. Project setup

- An Xcode app project named `Moonlet`, not a Swift package, because the menu
  bar app and login item need an app bundle.
- One app target and one unit test target.
- Swift 6 language mode, with strict concurrency. `AppState` and all UI are
  `@MainActor`. AVFoundation and Core Audio callbacks hop to the main actor
  before touching `AppState`.
- No App Sandbox, so Moonlet can read and watch the library folder freely.
- Signing: "Sign to Run Locally". No paid developer account needed.
- `make install` builds the Release configuration and copies it to
  `/Applications/Moonlet.app`. Launch at login is turned on from that installed
  copy, because a login item points at one specific copy of the app. The
  settings window warns when it runs from a development build.
- `Info.plist`: `LSUIElement = YES`.

## 10. Testing

### 10.1 Unit tests (Swift Testing)

- Parsing manifests, packs, and `streams.json`, including every invalid case in
  section 5.6.
- `Scheduler`: picking the slot for a given time, including wraparound at
  midnight. Timer rotation in sequential and shuffle order, with no repeats in
  a row.
- The effective-source rule, and resuming the playlist position.
- Music pause reasons: the 3-second and 5-second delays, the play-anyway
  override, and persisting a `user` pause. These tests use a fake
  `PlaybackMonitor` and a fake clock.
- Visual pause reasons: the 1-second covered delay, the immediate resume, and
  video pausing only when all screens are paused.
- The 95% coverage check, given a screen frame and a list of window rectangles.
- Classifying imported files and generating slugs, including name collisions.

### 10.2 Manual checklist

- [ ] The wallpaper sits under the desktop icons on every Space.
- [ ] Clicking and dragging on the desktop still work.
- [ ] Plugging a display in or out rebuilds the windows, showing the same
      wallpaper.
- [ ] A fullscreen app pauses the visuals. Activity Monitor shows low CPU and
      GPU use.
- [ ] A window covering the whole screen pauses the visuals.
- [ ] Music pauses for Safari video, Chrome video, Spotify, Music, and VLC,
      and resumes afterward.
- [ ] A muted Chrome tab that is still playing: record whether it pauses the
      music. Layer 0 did not test this.
- [ ] The menu names the app that is playing, for example "Safari" rather than
      "Safari Graphics and Media".
- [ ] A notification sound does not pause the music.
- [ ] Locking the screen and sleeping the Mac pause both music and visuals.
- [ ] Saving a `.metal` file reloads the shader. A broken save keeps the old
      shader and shows the error.
- [ ] A time-of-day pack switches at the slot boundary.
- [ ] Launch at login works after a restart.

## 11. Working process and build order

### 11.1 Process

Claude implements Moonlet. The user does not hand-code it. Internal work, such
as parsing and state logic, is folded into the visible layer that needs it, so
every layer ends with something the user can see or hear.

Each layer follows this loop:

1. **Plan.** Claude posts a short plan: what it builds, the files, the tests,
   and what the user will see. The user approves it before any code is
   written.
2. **Build.** Claude writes the unit tests for the layer's logic first, then
   the code.
3. **Check.** Claude builds with `xcodebuild`, runs the tests, launches the
   app, takes screenshots, and checks CPU use and logs.
4. **Review.** Claude stops and shows the evidence, plus a short list of
   things for the user to try. The user approves or asks for changes.
5. **Commit.** After approval, Claude commits on `main` using Conventional
   Commits, and updates this spec if anything changed.

Claude cannot hear audio or judge how the wallpaper looks and feels. Those
checks are always on the user's try-this list.

### 11.2 Layers

| # | Layer | Visible or audible result | Internal work included |
|---|---|---|---|
| 0 | Feasibility tests (throwaway) | A report on detecting other playback and covered windows | A command-line tool that prints which apps output audio. A test window that logs occlusion changes for fullscreen apps, full-screen windows, and Space switches. Both are deleted afterward. |
| 1 | Desktop window and video | One hardcoded video on every screen, under the icons, on all Spaces. Menu bar icon with Quit. | Xcode project, `AppState`, `DesktopWindowController`, `VideoRenderer` |
| 2 | Library and picker | Wallpapers from `~/Moonlet` appear in the menu. Switching crossfades. | Manifest parsing, FSEvents watching, unit tests |
| 3 | Metal | A shader renders on the desktop. Saving the `.metal` file reloads it. | `MetalRenderer`, shader header, compile error reporting |
| 4 | Web | Local pages and URLs render on the desktop | `WebRenderer` |
| 5 | Audio | Playlists, streams, and soundtracks play with fades. Music controls in the menu. | `AudioController`, effective-source rule, unit tests |
| 6 | Pause logic | A fullscreen app pauses the visuals. Spotify pauses the music. | `PlaybackMonitor`, `VisibilityMonitor`, pause reasons, fake-clock tests |
| 7 | Packs | A pack rotates by timer or time of day | `Scheduler`, unit tests |
| 8 | Settings window | Library grid, import, ignore list, Problems, launch at login | SwiftUI views |
| 9 | Icon and polish | The orbit icon in the menu bar and app bundle | Asset catalog |

Tooling for Layer 1, both already installed through Homebrew:

- XcodeGen generates the Xcode project from a `project.yml` file.
- `ffmpeg` generates the test media.

Layer 0 is done. Its findings are in sections 6.5 and 7.3.

## 12. Risks

| Risk | Mitigation |
|---|---|
| Some apps keep audio output running while silent, which would pause music forever | Default ignore list, plus the play-anyway override. Layer 0 found Vorssaint and system sounds. Music and muted tabs were not tested, so Layer 6 checks them. Firefox is out of scope. |
| Occlusion state misses covered windows | Confirmed in Layer 0. The coverage check in section 7.3 is the main signal. |
| WebKit throttling in covered windows is weaker than expected | Confirmed in Layer 6b. `WebRenderer` hides the web view while covered (section 7.2). |
| Animated web pages cost far more CPU than video or Metal | Section 7.6 records the measurements. Sample pages animate from JavaScript at 10 updates per second. |
| Strict concurrency friction with AVFoundation and Core Audio callbacks | Keep every callback a thin hop to the main actor. Keep the logic in testable main-actor types. |
