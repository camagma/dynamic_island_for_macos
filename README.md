# DynamicIslandMac

A small macOS overlay inspired by Dynamic Island for MacBooks with a notch.

It shows time, audio, calendar events, notifications, and a clipboard preview when the island is opened.

## Run

Open `DynamicIslandMac.xcodeproj` in Xcode and run the `DynamicIslandMac` target.

macOS may ask for Calendar and Automation permissions. Automation is used to read and control supported audio apps.

## Notes

- The island is a floating overlay window, not a real system notch integration.
- Audio progress and controls work for Apple Music and Spotify.
- Browser audio is detected from supported tab titles where possible.
- Notch size can be adjusted from the menu bar icon.
