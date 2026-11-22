<img width="256" height="256" alt="image" src="https://github.com/user-attachments/assets/9994310e-1e8f-4d96-9d1a-1b0f341b491d" />

# Moonlet

Moonlet is a live wallpaper and ambient music app for macOS that lives in your menu bar. Your desktop can be a looping video, a Metal shader, or a web page, and the music can be a playlist, internet radio, or a soundtrack that comes with the wallpaper. It stays out of your way: visuals pause when a window covers the desktop, and music fades out whenever another app starts playing sound. Everything lives in one plain folder (`~/Moonlet`), so adding a wallpaper is just dropping in a file, and packs can rotate wallpapers on a timer or by time of day.

## Download

Moonlet needs macOS 26 or later, on Apple silicon or Intel.

1. Download `Moonlet.zip` from the [latest release](https://github.com/aayushmau5/Moonlet/releases/latest), unzip it, and drag Moonlet into Applications.
2. Moonlet isn't notarized by Apple, so macOS blocks the first launch. Clear the download flag once in Terminal:

   ```sh
   xattr -dr com.apple.quarantine /Applications/Moonlet.app
   ```

   Or open Moonlet, then click **Open Anyway** in System Settings → Privacy & Security.
3. For example wallpapers, download `Moonlet-Examples.zip` from the same release and unzip it. If you don't have a `~/Moonlet` folder yet, move the unzipped `Moonlet` folder into your home folder.

## How it works

Moonlet puts a borderless window on every screen, tucked just below your desktop icons. Clicks pass straight through it, so the desktop works as usual. Inside that window it plays your wallpaper: videos through AVFoundation, shaders through Metal (compiled on the fly, so saving a `.metal` file updates the desktop instantly), and pages through WebKit.

The music side picks one source at a time. If the wallpaper has its own soundtrack, that plays. Otherwise your chosen playlist or radio station plays, with a short crossfade whenever it switches.

About once a second, Moonlet checks two things. First, whether any window is covering the desktop, and if so it stops drawing to save battery. Second, whether another app is playing sound, and if so it fades the music out until that app goes quiet. It also watches `~/Moonlet` for changes, so new or edited files show up without a restart.

## Build from source

You need an Apple silicon Mac on macOS 26 or later, Xcode 26 or later, and [Homebrew](https://brew.sh).

```sh
brew install xcodegen ffmpeg
git clone https://github.com/aayushmau5/Moonlet.git
cd Moonlet
make run
```

`make run` generates the Xcode project, builds a debug copy, and launches it. Moonlet shows up as a ring in the menu bar, with no Dock icon. `ffmpeg` is only needed for the example sounds and videos.

To install a release build into `/Applications`:

```sh
make install
```

You can then turn on "Launch at login" in Moonlet's settings.

### Example content

```sh
make examples
```

This copies 29 example wallpapers (shaders and web pages), 2 packs, and a "Nature" playlist of generated rain, waves, stream, wind, and fire sounds into `~/Moonlet`. It never overwrites anything already there.

```sh
make videos
```

This downloads a set of free nature clips from [Mixkit](https://mixkit.co) into `~/Moonlet`, and makes each one loop without a visible jump. The clips are covered by the Mixkit license, not this repository's license.

## Your library

Everything lives in `~/Moonlet`. You can move it in settings.

```
~/Moonlet/
  wallpapers/   one folder per wallpaper
  packs/        one JSON file per pack
  music/        one folder per playlist
  streams.json  internet radio stations
```

A wallpaper is a folder with a `wallpaper.json` and its files:

```json
{
  "name": "Rain on Glass",
  "type": "metal",
  "source": "rain-on-glass.metal",
  "soundtrack": "rain.m4a",
  "volume": 0.8
}
```

`type` is `video` (`.mp4` or `.mov`), `metal` (a `.metal` file), or `web` (an `.html` file or a URL). `soundtrack` is optional. A Metal shader defines one fragment function called `wallpaper`, and saving the file updates the desktop right away. A Metal wallpaper can also set `"image"` to a photo in its folder, and the shader samples it at `texture(0)` to animate or restyle it. See [`examples/wallpapers`](examples/wallpapers) for working shaders.

A pack switches wallpapers by time of day or on a timer:

```json
{ "name": "Workday", "mode": "timeOfDay",
  "slots": [{ "from": "07:00", "wallpaper": "aurora" },
            { "from": "19:00", "wallpaper": "rain-on-glass" }] }
```

`streams.json` is a list of stations:

```json
[{ "name": "Drone Zone", "url": "https://ice1.somafm.com/dronezone-128-mp3" }]
```

You can also drag files onto the Library tab in settings to import them. The full format is in [the design spec](docs/specs/2026-11-22-moonlet-design.md).

## Development

```sh
make test
```

This runs the unit tests. `make snapshots` renders the menu panel, the settings tabs, and your library's wallpapers to `build/snapshots` for a visual check. `make release` builds `Moonlet.zip` and `Moonlet-Examples.zip` into `build/release`, ready to attach to a GitHub release.

## License

Moonlet is licensed under the [Apache License 2.0](LICENSE).
