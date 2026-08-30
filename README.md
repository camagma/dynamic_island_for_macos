# DynamicIslandMac

Small macOS overlay for MacBooks with a notch.

It opens on hover and shows the basics: time, current audio, calendar events, Gmail, and clipboard preview.

## Run

Open `DynamicIslandMac.xcodeproj` in Xcode and run the `DynamicIslandMac` target. macOS may ask for Calendar and Automation permissions.

Automation is used for supported audio apps and browser title detection.

## Features

- Current time and date
- Audio source, track title, progress, and controls where supported
- Scrollable calendar events for the next 7 days
- Mini month calendar
- Gmail notification center with paged inbox loading
- Clipboard preview
- Low Power Mode
- Menu bar diagnostics
- Notch size presets and manual calibration

## Gmail Setup

Gmail support uses OAuth. An API key alone will not work.

1. Create a project in Google Cloud Console.
2. Enable the Gmail API.
3. Configure the OAuth consent screen.
4. Add your Gmail account in Test users.
5. Create an OAuth client and copy the Client ID and Client Secret.
6. Use OAuth Playground with this scope:

```text
https://www.googleapis.com/auth/gmail.readonly
```

7. Exchange the code for tokens and copy the Refresh Token.
8. Save the credentials locally:

```bash
defaults write local.dynamicisland.mac GmailAPI.isEnabled -bool true
defaults write local.dynamicisland.mac GmailAPI.clientID "YOUR_CLIENT_ID"
defaults write local.dynamicisland.mac GmailAPI.clientSecret "YOUR_CLIENT_SECRET"
defaults write local.dynamicisland.mac GmailAPI.refreshToken "YOUR_REFRESH_TOKEN"
```

Restart the app after saving credentials.

New inbox emails are checked in the background and open the island for 5 seconds. Gmail can also be refreshed from the island or the menu bar.

## Notes

- The island is a floating overlay window, not a real system notch integration.
- Audio controls and progress work best with Apple Music and Spotify.
- Browser audio is detected from tab titles where macOS automation allows it.
- Gmail inbox messages load 5 at a time.
- Low Power Mode slows background polling and disables the live audio progress timer.
- Diagnostics are refreshed only when the menu bar menu opens.
- Notch size and presets are available from the menu bar icon.
