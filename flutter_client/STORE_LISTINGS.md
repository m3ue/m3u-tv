# M3U TV store listings

Source of truth for the copy pasted into App Store Connect, Google Play Console and Microsoft Partner Center. Update this file first, then copy into the stores, so the listings never live only in a store dashboard again.

Last reviewed against: **v1.2.3** (2026-10-20). Store artwork is generated separately by `scripts/generate-store-assets.sh`.

## Rules for every listing

- **No em or en dashes.** Use a plain hyphen, a colon or a comma.
- **Every listing says the app has no content.** Both Apple and Google reject "IPTV player" apps that look like they supply streams. Keep the "does not include any channels or content" line in every description.
- **Apple only:**
  - Never mention **AIOStreams** (Apple reviewers use it as a rejection keyword).
  - Never mention other platforms (Android, Google TV, Windows, Linux). Guideline 2.3.10 forbids it, and the old copy did it.
  - Say "Xtream API", never "Xtream Codes" (the name of a service that was shut down for piracy).
  - Leave "IPTV" out of the keywords field. It is fine once, in context, in the description.
- **Trakt:** the app syncs **watch history** only. Don't claim watchlist or collection sync.

## Shared details

| Field | Value |
| --- | --- |
| App name | M3U TV |
| Developer / publisher | sparkison (Shaun Parkison and contributors) |
| Website / marketing URL | https://m3ue.sparkison.dev/tv |
| Privacy policy URL | https://m3ue.sparkison.dev/privacy/ |
| Support URL | https://github.com/m3ue/m3u-tv/issues |
| Source code | https://github.com/m3ue/m3u-tv |
| License | GPL-3.0 |
| Copyright | © 2026 Shaun Parkison and contributors |
| Languages in app | English, German, Spanish, French, Simplified Chinese |

## Categories

| Store | Field | Value | Why |
| --- | --- | --- | --- |
| Apple App Store | Primary category | Entertainment | Where Infuse, Channels and other TV clients live. |
| Apple App Store | Secondary category | Photo & Video | Where VLC and other media players live. |
| Google Play | App or game | App | |
| Google Play | Category | Video Players & Editors | Where VLC, MX Player and Kodi live. Better search placement than Entertainment. |
| Google Play | Tags (up to 5) | Video player, TV guide, Live TV, Movies & TV shows, Media streaming | Pick the closest matches from Play's fixed tag list. |
| Microsoft Store | Category | Entertainment | Already set for the live listing. Keep it as is. |
| Microsoft Store | Subcategory | None | |

---

## Apple App Store

Name and subtitle are set once for the whole app. Promotional text, keywords and description are set per platform (tvOS and iOS/iPadOS).

### Name (30)

```
M3U TV
```

### Subtitle (30)

```
Self-hosted live TV and movies
```

### tvOS

#### Promotional text (170)

```
New: an optional Rich Home with a full-screen spotlight, a redesigned remote-first TV guide with live preview, and Multiview. Your own server, built for the big screen.
```

#### Keywords (100)

```
epg,xtream,playlist,guide,live,player,dvr,recorder,catchup,multiview,trakt,movies,series,selfhosted
```

#### Description (4000)

```
M3U TV is the Apple TV app for m3u editor, the open-source, self-hosted platform for managing your IPTV playlists, guides and media. Connect it to your own m3u editor server and your live channels, movies and series come together in one fast interface designed around the Siri Remote.

M3U TV does not include any channels, playlists or content. You need your own m3u editor server and your own lawful sources.

HOME
• Continue Watching with Up Next episodes, so you can pick up right where you left off.
• Optional Rich Home: a full-screen spotlight with artwork and title logos above your rows.
• Favorites and quick rows for Live TV, movies and series. Choose which screen the app opens on.

LIVE TV AND GUIDE
• A multi-day timeline guide built for the Siri Remote, with an optional live preview player.
• On Now and Upcoming views with station logos.
• Catchup playback with seeking on channels that support it.
• Multiview: watch several channels at once.
• Custom channel sorting, favorites-first ordering and grid or list layouts.

DVR
• Record a single airing or a whole series straight from the guide or search.
• Watch, cancel and delete recordings, and see storage usage at a glance.
• Automatic commercial skipping on recordings that support it.

MOVIES AND SERIES
• Detail pages with cast, filmographies, trailers, ratings and related titles.
• A season and episode browser with Up Next.
• Skip Intro and Skip Credits prompts powered by TheIntroDB (optional).
• Sort by recently added, recently updated, title and more.
• Request new movies and shows through your server.

SEARCH
• One search across channels, guide listings, movies and series.

PLAYBACK
• Native mpv playback with an automatic AVKit fallback.
• Audio and subtitle track selection, plus multichannel audio.
• A built-in Logs and Diagnostics screen for troubleshooting.

MADE FOR YOUR HOUSEHOLD
• Multiple viewers, each with their own history and favorites.
• Trakt watch history sync.
• Quick setup: pair your Apple TV by scanning a QR code with your phone.
• Adjustable display scale, remote button mapping and navigation sounds.

OPEN SOURCE
M3U TV and m3u editor are open source. Bring your own server, your own playlists and your own sources.
```

#### Apple TV Privacy Policy (plain text)

Required for tvOS: the App Store on Apple TV can't open links, so it shows this text instead of the privacy policy URL. A plain-text copy of [the docs privacy page](https://m3ue.sparkison.dev/privacy/), trimmed to what applies on Apple TV. Keep the two in sync.

```
M3U TV PRIVACY POLICY
Last updated: October 20, 2026

M3U TV is a client for your own self-hosted m3u editor server. It is not a hosted service, and the developer does not operate a backend that stores your content or personal data.

INFORMATION THE APP STORES OR SENDS

Server connection details. The server URL, username and password you enter are stored only on your Apple TV, in the Keychain, and are sent only to the server you configure. They are never sent to the developer or any third party.

Data sent to your own server. To work, the app sends the following to your server, and only to your server: viewing progress and watch history, favorites, viewer profiles, DVR schedules, and basic device details (device name, platform, app version and a random ID the app generates on first launch). If you choose "Upload to server" on the Logs and Diagnostics screen, recent diagnostic logs are also sent to your server so its administrator can troubleshoot. None of this is sent to the developer.

Push notifications. If notifications are enabled, the app registers a device token with Firebase Cloud Messaging (Google) so your server can deliver notifications, such as recording updates. The token is used only for message delivery.

WHAT THE DEVELOPER DOES NOT COLLECT

The app contains no analytics, crash reporting, advertising or tracking. The developer does not collect usage statistics, viewing history or any other personal data.

OPTIONAL THIRD-PARTY SERVICES

These are contacted only when you use the related feature:
• Trakt (trakt.tv): if you connect a Trakt account, your watch history is synced with Trakt. Access tokens are stored in the Keychain, and you can disconnect at any time in Settings. Trakt privacy policy: trakt.tv/privacy
• TheIntroDB (theintrodb.org): when Skip Intro and Skip Credits are enabled, the app sends the public TMDB or IMDb ID, season and episode number of what you are watching to look up intro and credits timestamps. No personal information is sent. You can turn this off in Settings.

Artwork and metadata are provided by your own server, which may source them from TMDB. Your server's privacy practices are controlled by whoever operates it.

DATA RETENTION AND CONTROL

Log out, disconnect Trakt or delete the app to remove all data stored on your Apple TV. Data on your own server, such as watch history, registered devices and uploaded logs, is controlled by that server's administrator and can be deleted there.

CHILDREN

The app is not directed at children under 13 and does not knowingly collect personal information from children.

CHANGES AND CONTACT

Changes to this policy are reflected in the "Last updated" date. The full policy is at m3ue.sparkison.dev/privacy. Questions: hello@sparkison.dev
```

### iOS and iPadOS

#### Promotional text (170)

```
New: an optional Rich Home with a full-screen spotlight, a redesigned TV guide with live preview, and Multiview. Your self-hosted library, on iPhone and iPad.
```

#### Keywords (100)

```
epg,xtream,playlist,guide,live,player,dvr,recorder,catchup,multiview,trakt,movies,series,selfhosted
```

#### Description (4000)

```
M3U TV is the iPhone and iPad app for m3u editor, the open-source, self-hosted platform for managing your IPTV playlists, guides and media. Connect it to your own m3u editor server and your live channels, movies and series come together in one fast, touch-friendly app. It's also available on Apple TV, built around the Siri Remote.

M3U TV does not include any channels, playlists or content. You need your own m3u editor server and your own lawful sources.

HOME
• Continue Watching with Up Next episodes, so you can pick up right where you left off.
• Optional Rich Home: a full-screen spotlight with artwork and title logos above your rows.
• Favorites and quick rows for Live TV, movies and series. Choose which screen the app opens on.

LIVE TV AND GUIDE
• A multi-day timeline guide with an optional live preview player.
• On Now and Upcoming views with station logos.
• Catchup playback with seeking on channels that support it.
• Multiview: watch several channels at once.
• Custom channel sorting, favorites-first ordering and grid or list layouts.

DVR
• Record a single airing or a whole series straight from the guide or search.
• Watch, cancel and delete recordings, and see storage usage at a glance.
• Automatic commercial skipping on recordings that support it.

MOVIES AND SERIES
• Detail pages with cast, filmographies, trailers, ratings and related titles.
• A season and episode browser with Up Next.
• Skip Intro and Skip Credits prompts powered by TheIntroDB (optional).
• Sort by recently added, recently updated, title and more.
• Request new movies and shows through your server.

SEARCH
• One search across channels, guide listings, movies and series.

PLAYBACK
• Native mpv playback with an automatic AVKit fallback.
• Audio and subtitle track selection, plus multichannel audio on iPhone and iPad.
• A built-in Logs and Diagnostics screen for troubleshooting.

MADE FOR YOUR HOUSEHOLD
• Multiple viewers, each with their own history and favorites.
• Trakt watch history sync.
• A notification center for alerts from your server, with per-channel subscriptions.
• Adjustable display scale.

OPEN SOURCE
M3U TV and m3u editor are open source. Bring your own server, your own playlists and your own sources.
```

---

## Google Play (Android, Android TV, Google TV)

### App name (30)

```
M3U TV
```

### Short description (80)

```
Self-hosted Live TV, guide, DVR, VOD and AIOStreams client for m3u editor
```

### Full description (4000)

```
M3U TV is the Android TV, Google TV and Android app for m3u editor, the open-source, self-hosted platform for managing your IPTV playlists, guides and media. Connect it to your own m3u editor server and your live channels, movies, series and AIOStreams catalogs come together in one fast, D-pad first interface, with full touch support on phones and tablets.

M3U TV does not include any channels, playlists or content. You need your own m3u editor server and your own lawful sources.

HOME
• Continue Watching with Up Next episodes, so you can pick up right where you left off.
• Optional Rich Home: a full-screen spotlight with artwork and title logos above your rows.
• Favorites and quick rows for Live TV, movies and series. Choose which screen the app opens on.

LIVE TV AND GUIDE
• A multi-day timeline guide built for D-pad remotes, with an optional live preview player.
• On Now and Upcoming views with station logos.
• Catchup playback with seeking on channels that support it.
• Multiview: watch several channels at once.
• Custom channel sorting, favorites-first ordering and grid or list layouts.
• Works with Xtream API and standard M3U playlists served by m3u editor.

DVR
• Record a single airing or a whole series straight from the guide or search.
• Watch, cancel and delete recordings, and see storage usage at a glance.
• Automatic commercial skipping on recordings that support it.

MOVIES AND SERIES
• Detail pages with cast, filmographies, trailers, ratings and related titles.
• A season and episode browser with Up Next.
• Skip Intro and Skip Credits prompts powered by TheIntroDB (optional).
• Sort by recently added, recently updated, title and more.
• Request new movies and shows through your server.

AIOSTREAMS
• Browse and search your AIOStreams catalogs right next to your own library.
• Full movie and series detail pages, Continue Watching and Up Next for catalog titles.

SEARCH
• One search across channels, guide listings, movies, series and catalogs.

PLAYBACK
• ExoPlayer (Media3) with an automatic mpv fallback for streams ExoPlayer can't play.
• Audio and subtitle track selection, plus multichannel audio.
• Optional automatic frame rate matching on Android TV.
• A built-in Logs and Diagnostics screen for troubleshooting.

MADE FOR YOUR HOUSEHOLD
• Multiple viewers, each with their own history and favorites.
• Trakt watch history sync.
• A notification center for alerts from your server, with per-channel subscriptions.
• Quick setup: pair your TV by scanning a QR code with your phone.
• Adjustable display scale, remote button mapping and navigation sounds.
• Available in English, German, Spanish, French and Simplified Chinese.

PLATFORMS
• Android TV and Google TV (D-pad remote), Android phones and tablets (touch).
• Also available on Apple TV, iPhone, iPad, Mac, Windows and Linux.

OPEN SOURCE
M3U TV and m3u editor are open source. Bring your own server, your own playlists and your own sources.
```

---

## Microsoft Store (Windows)

### Product name

```
M3U TV
```

### Description (10000)

```
M3U TV is the Windows app for m3u editor, the open-source, self-hosted platform for managing your IPTV playlists, guides and media. Connect it to your own m3u editor server and your live channels, movies, series and AIOStreams catalogs come together in one fast interface that works with a mouse or a keyboard.

M3U TV does not include any channels, playlists or content. You need your own m3u editor server and your own lawful sources.

HOME
• Continue Watching with Up Next episodes, so you can pick up right where you left off.
• Optional Rich Home: a full-screen spotlight with artwork and title logos above your rows.
• Favorites and quick rows for Live TV, movies and series. Choose which screen the app opens on.

LIVE TV AND GUIDE
• A multi-day timeline guide with arrow-key navigation and an optional live preview player.
• On Now and Upcoming views with station logos.
• Catchup playback with seeking on channels that support it.
• Multiview: watch several channels at once.
• Custom channel sorting, favorites-first ordering and grid or list layouts.
• Works with Xtream API and standard M3U playlists served by m3u editor.

DVR
• Record a single airing or a whole series straight from the guide or search.
• Watch, cancel and delete recordings, and see storage usage at a glance.
• Automatic commercial skipping on recordings that support it.

MOVIES AND SERIES
• Detail pages with cast, filmographies, trailers, ratings and related titles.
• A season and episode browser with Up Next.
• Skip Intro and Skip Credits prompts powered by TheIntroDB (optional).
• Sort by recently added, recently updated, title and more.
• Request new movies and shows through your server.

AIOSTREAMS
• Browse and search your AIOStreams catalogs right next to your own library.
• Full movie and series detail pages, Continue Watching and Up Next for catalog titles.

SEARCH
• One search across channels, guide listings, movies, series and catalogs.

PLAYBACK
• Built-in libmpv playback that handles a wide range of formats and codecs.
• Audio and subtitle track selection, plus multichannel audio.
• Fullscreen with F11 or Alt+Enter, and volume control in the player.
• A built-in Logs and Diagnostics screen for troubleshooting.

MADE FOR YOUR HOUSEHOLD
• Multiple viewers, each with their own history and favorites.
• Trakt watch history sync.
• Adjustable display scale and navigation sounds.
• Available in English, German, Spanish, French and Simplified Chinese.

PLATFORMS
• Windows (mouse and keyboard).
• Also available on Android TV, Google TV, Android, Apple TV, iPhone, iPad, Mac and Linux.

OPEN SOURCE
M3U TV and m3u editor are open source. Bring your own server, your own playlists and your own sources.
```

### Product features (up to 20, 200 each)

```
Connects to your own self-hosted m3u editor server (no content included)
Multi-day timeline TV guide with an optional live preview player
On Now and Upcoming views with station logos
Catchup playback with seeking on supported channels
Multiview: watch several channels at once
Record single airings or whole series from the guide or search
Automatic commercial skipping on supported recordings
Continue Watching with Up Next episodes
Optional Rich Home with a full-screen spotlight
Movie and series detail pages with cast, trailers and related titles
Skip Intro and Skip Credits prompts powered by TheIntroDB
Browse and search AIOStreams catalogs alongside your library
One search across channels, guide listings, movies and series
Request new movies and shows through your server
Multiple viewers with their own history and favorites
Trakt watch history sync
libmpv playback with audio and subtitle track selection
Fullscreen with F11 or Alt+Enter, and full keyboard navigation
Built-in Logs and Diagnostics screen
English, German, Spanish, French and Simplified Chinese
```

### Search terms (7 terms, 30 characters each, 21 words in total)

```
IPTV player
M3U playlist
Xtream
EPG TV guide
Live TV
DVR recording
AIOStreams
```

### Short title (50)

```
M3U TV
```

### Sort title

Leave empty (it defaults to the product name).

### Voice title (255)

```
M three U TV
```

### Short description (1000)

Shown on Xbox and in some Store layouts in place of the full description.

```
The Windows app for m3u editor, the open-source, self-hosted IPTV and media platform. Watch live TV with a multi-day guide, catchup and Multiview, record with the DVR, and browse movies, series and AIOStreams catalogs with Continue Watching, Up Next and Trakt sync. M3U TV does not include any content: you need your own m3u editor server and your own lawful sources.
```

### Developed by (255)

```
Shaun Parkison and contributors
```

### Copyright and trademark info (200)

```
© 2026 Shaun Parkison and contributors. Licensed under the GNU GPL v3.
```

### Additional license terms (10000)

```
M3U TV is free software released under the GNU General Public License v3.0. Full license text and source code: https://github.com/m3ue/m3u-tv
```

### Additional system requirements

- **Minimum hardware notes:** `An internet or local network connection to your own m3u editor server.`
- **Recommended hardware notes:** `A wired or 5 GHz Wi-Fi connection for HD and 4K streams.`

---

## Testing notes

Instructions for each store's reviewers. All stores use the same demo server, which serves only public-domain and freely licensed content. Never point a reviewer at a server with a commercial provider lineup: Apple and Google reject that as unauthorised content.

- **Server URL:** `https://api-tester-fcn5.onrender.com`
- **Username:** `testuser`
- **Password:** `testpass`

### Apple: App Review Information > Notes (4000)

Also fill in the separate "Sign-in required" username and password fields with the credentials above.

```
M3U TV is a client for m3u editor, an open-source, self-hosted media server (https://github.com/m3ue/m3u-editor). The app includes no content, playlists or streams. Users connect it to their own server and play only media they supply. A demo server with public-domain and freely licensed content is provided below.

Third-party services used via their public APIs: Trakt (optional watch history sync), TheIntroDB (optional skip intro timestamps), YouTube (trailer links open externally). Artwork and metadata are supplied by the user's server from TMDB.

Please use the following URL for the Server URL in settings: https://api-tester-fcn5.onrender.com
username: testuser
password: testpass
```

### Google Play: App content > App access

Choose "All or some functionality is restricted", then add one set of instructions:

- **Name:** `Demo server`
- **Username:** `testuser`
- **Password:** `testpass`
- **Any other information:**

```
M3U TV is a client for m3u editor, an open-source, self-hosted media server (https://github.com/m3ue/m3u-editor). The app includes no content. On first launch, enter https://api-tester-fcn5.onrender.com as the Server URL, then the username and password above. The demo server only serves public-domain and freely licensed content.
```

### Microsoft Store: Submission options > Notes for certification

```
M3U TV is a client for m3u editor, an open-source, self-hosted media server (https://github.com/m3ue/m3u-editor). The app includes no content, playlists or streams. Users connect it to their own server and play only media they supply.

To test, enter the following on the connection screen:
Server URL: https://api-tester-fcn5.onrender.com
Username: testuser
Password: testpass

The demo server only serves public-domain and freely licensed content. Optional third-party services used via their public APIs: Trakt (watch history sync), TheIntroDB (skip intro timestamps), YouTube (trailer links open in the browser).
```

---

## Release notes

Add a new subsection at the top for each release, built from the GitHub release notes. Per-store limits:

| Store | Field | Limit |
| --- | --- | --- |
| Apple App Store | What's New in This Version | 4000 |
| Google Play | Release notes | 500 |
| Microsoft Store | What's new in this version | 1500 |

The Apple notes follow the Apple rules above (no AIOStreams, no other platforms). Leave out desktop-only items such as fullscreen shortcuts.

### v1.2.3

#### Apple (tvOS, iOS and iPadOS)

```
• New optional Rich Home with a full-screen spotlight hero.
• Optional live preview player in the TV guide.
• Current and end times shown for what's playing.
• Trailer links on movie and series pages.
• Sort by recently added and recently updated.
• TheIntroDB Skip Intro prompts can now be turned off.
• Multichannel audio on iPhone and iPad.
• Smoother playback, refreshed notifications and many fixes.
```

#### Google Play

```
• New optional Rich Home with a full-screen spotlight hero.
• Optional live preview player in the TV guide.
• Current and end times shown for what's playing.
• Trailer links on movie and series pages.
• Sort by recently added and recently updated.
• TheIntroDB Skip Intro prompts can now be turned off.
• Faster, smoother mpv fallback playback and many fixes.
```

#### Microsoft Store

```
• New optional Rich Home with a full-screen spotlight hero.
• Optional live preview player in the TV guide.
• Fullscreen with F11 or Alt+Enter, plus a fullscreen toggle in the player.
• Current and end times shown for what's playing.
• Trailer links on movie and series pages.
• Sort by recently added and recently updated.
• TheIntroDB Skip Intro prompts can now be turned off.
• Smoother playback, refreshed notifications and many fixes.
```
