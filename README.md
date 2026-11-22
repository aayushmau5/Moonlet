<img width="256" height="256" alt="image" src="https://github.com/user-attachments/assets/9994310e-1e8f-4d96-9d1a-1b0f341b491d" />

# Moonlet

Moonlet is a live wallpaper and ambient music app for macOS that lives in your menu bar. Your desktop can be a looping video, a Metal shader, or a web page, and the music can be a playlist, internet radio, or a soundtrack that comes with the wallpaper. It stays out of your way: visuals pause when a window covers the desktop, and music fades out whenever another app starts playing sound. Everything lives in one plain folder (`~/Moonlet`), so adding a wallpaper is just dropping in a file, and packs can rotate wallpapers on a timer or by time of day.

## How it works

Moonlet puts a borderless window on every screen, tucked just below your desktop icons. Clicks pass straight through it, so the desktop works as usual. Inside that window it plays your wallpaper: videos through AVFoundation, shaders through Metal (compiled on the fly, so saving a `.metal` file updates the desktop instantly), and pages through WebKit.

The music side picks one source at a time. If the wallpaper has its own soundtrack, that plays. Otherwise your chosen playlist or radio station plays, with a short crossfade whenever it switches.

About once a second, Moonlet checks two things. First, whether any window is covering the desktop, and if so it stops drawing to save battery. Second, whether another app is playing sound, and if so it fades the music out until that app goes quiet. It also watches `~/Moonlet` for changes, so new or edited files show up without a restart.
