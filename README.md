# DynamicIslandMac

A small macOS overlay inspired by Dynamic Island for MacBooks with a notch.

It shows time, audio, calendar events, notifications, and a clipboard preview when the island is opened.

## Run

Open `DynamicIslandMac.xcodeproj` in Xcode and run the `DynamicIslandMac` target.

macOS may ask for Calendar and Automation permissions. Automation is used to read and control supported audio apps.

## Gmail Setup

Gmail notifications use the Gmail API with OAuth. API keys are not enough.

1. Create a project in Google Cloud Console.
2. Enable Gmail API for that project.
3. Configure OAuth consent screen and add your Gmail account as a test user.
4. Create an OAuth client and copy its Client ID and Client Secret.
5. Use OAuth Playground to authorize this scope:

```text
https://www.googleapis.com/auth/gmail.readonly
```

6. Exchange the authorization code for tokens and copy the Refresh Token.
7. Save the credentials locally:

```bash
defaults write local.dynamicisland.mac GmailAPI.isEnabled -bool true
defaults write local.dynamicisland.mac GmailAPI.clientID "YOUR_CLIENT_ID"
defaults write local.dynamicisland.mac GmailAPI.clientSecret "YOUR_CLIENT_SECRET"
defaults write local.dynamicisland.mac GmailAPI.refreshToken "YOUR_REFRESH_TOKEN"
```

Restart the app after saving credentials.

New inbox emails are checked in the background and open the island for 5 seconds. The Notification Center can also be refreshed manually from the menu bar or from the island.

## Notes

- The island is a floating overlay window, not a real system notch integration.
- Audio progress and controls work for Apple Music and Spotify.
- Browser audio is detected from supported tab titles where possible.
- Gmail polling can be enabled with local UserDefaults OAuth credentials.
- Gmail inbox pages load 5 messages at a time.
- Notch size can be adjusted from the menu bar icon.
