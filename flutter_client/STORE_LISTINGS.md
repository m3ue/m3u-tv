# M3U TV store listings

Source of truth for the copy pasted into App Store Connect, Google Play Console and Microsoft Partner Center. Update this file first, then copy into the stores, so the listings never live only in a store dashboard again.

Last reviewed against: **v1.3.0** (2026-11-10). Store artwork is generated separately by `scripts/generate-store-assets.sh` (headers and banners) and `scripts/generate-screenshots.sh` (screenshots).

## Rules for every listing

- **No em or en dashes.** Use a plain hyphen, a colon or a comma.
- **Every listing says the app has no content.** Both Apple and Google reject "IPTV player" apps that look like they supply streams. Keep the "does not include any channels or content" line in every description.
- **Apple only:**
  - Never mention **AIOStreams** (Apple reviewers use it as a rejection keyword).
  - Never mention other platforms (Android, Google TV, Windows, Linux). Guideline 2.3.10 forbids it, and the old copy did it.
  - Say "Xtream API", never "Xtream Codes" (the name of a service that was shut down for piracy).
  - Leave "IPTV" and "Xtream" out of the keywords field. Both are fine in context in the description.
  - Screenshots, previews and header art come only from the demo server (Blender open movies, public-domain films, generated test channels): the `tvos*`, `ios*`, `ipados*` and `macos*` sets in `screenshots/app-screenshots/`. Never real studio posters, network logos or provider channel names. Apple rejected v1.2.3 under 5.2.1 for exactly this.
  - The Support URL must be a real support page, not an issue tracker (rejected under 1.5).
- **Trakt:** the app syncs **watch history** only. Don't claim watchlist or collection sync.
- **CarPlay and Android Auto:** write them exactly so (Apple's and Google's names), and keep each to its own store: CarPlay only in the iOS listing and Apple notes, Android Auto only on Google Play.
- **Sports:** never name a sports data provider, league or team in any listing or release note (ESPN, NFL, Premier League and so on), since those are trademarks. Say the channels are the user's own, and keep Sports screenshots off the Apple listings unless they come from the demo server, which has no Sports yet.

## Shared details

| Field | Value |
| --- | --- |
| App name | M3U TV |
| Developer / publisher | sparkison (Shaun Parkison and contributors) |
| Website / marketing URL | https://m3ue.sparkison.dev/tv |
| Privacy policy URL | https://m3ue.sparkison.dev/privacy/ |
| Support URL | https://m3ue.sparkison.dev/support |
| Issue tracker | https://github.com/m3ue/m3u-tv/issues |
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

Name and subtitle are set once for the whole app. Promotional text, keywords and description are set per platform (tvOS, iOS/iPadOS and macOS). macOS shares the bundle ID with iOS and tvOS, so it is a platform added to the same App Store Connect app (Universal Purchase), not a separate listing.

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
New: settings and Home layouts set up from your server, SIMKL sync, online subtitles, and audio and subtitle sync. Your server, built for the big screen.
```

#### Keywords (100)

```
epg,playlist,guide,live,player,dvr,simkl,catchup,multiview,trakt,movies,series,selfhosted,sports
```

#### Description (4000)

```
M3U TV is the Apple TV app for M3U Editor, the open-source, self-hosted platform for managing your IPTV playlists, guides and media. Connect it to your own M3U Editor server and your live channels, movies and series come together in one fast interface designed around the Siri Remote.

M3U TV does not include any channels, playlists or content. You need your own M3U Editor server and your own lawful sources.

HOME
• Continue Watching with Up Next episodes, so you can pick up right where you left off.
• Optional Spotlight home: a full-screen hero with artwork and title logos above your rows.
• Favorites and quick rows for Live TV, movies and series. Choose which screen the app opens on.
• Reorder the nav and Home rows, and hide the sections you don't use.

LIVE TV AND GUIDE
• A multi-day timeline guide built for the Siri Remote, with an optional live preview player.
• On Now and Upcoming views with station logos.
• Guide previews carry into full screen without restarting the stream.
• Catchup playback with seeking on channels that support it.
• Multiview: watch several channels at once.
• Pause live TV, and pick back up at the live point after a longer break.
• Custom channel sorting, favorites-first ordering and grid or list layouts.

SPORTS
• See each day's games with live scores, for the leagues your server is set up for.
• Find which of your own channels is showing a game, and start it in one press.
• Game details with the score by period, key moments and team stats.
• Follow your teams, with My Teams and a Sports row on Home.
• Needs M3U Editor 0.14.1 or later with Sports turned on.

DVR
• Record a single airing or a whole series straight from the guide or search.
• Watch, cancel and delete recordings, and see storage usage at a glance.
• Your whole recordings library, with status filters and sorting.
• Automatic commercial skipping on recordings that support it.

MOVIES AND SERIES
• Detail pages with cast, filmographies, trailers, ratings and related titles.
• A season and episode browser with Up Next, plus an episode picker right in the player.
• Artwork while movies and episodes load.
• Skip Intro and Skip Credits prompts powered by TheIntroDB (optional).
• Sort by recently added, recently updated, title and more.
• Request new movies and shows through your server, and pick which service handles it when there's more than one.

SEARCH
• One search across channels, guide listings, movies and series.

PLAYBACK
• Native mpv playback with an automatic AVKit fallback.
• Audio and subtitle track selection, plus multichannel audio.
• Audio and subtitle sync, saved for each channel, movie or series.
• Search for subtitles online for movies and episodes.
• A built-in Logs and Diagnostics screen for troubleshooting.

MADE FOR YOUR HOUSEHOLD
• Multiple viewers, each with their own history and favorites.
• Keep several playlists on one device, from one server or more, each with its own favorites and guide.
• Trakt and SIMKL watch history sync, from the device or from your server.
• Settings and Home layouts your server can set up for every device, as defaults or locked.
• Quick setup: pair your Apple TV by scanning a QR code with your phone, and add several playlists in one go.
• Adjustable display scale, remote button mapping and navigation sounds.

OPEN SOURCE
M3U TV and M3U Editor are open source. Bring your own server, your own playlists and your own sources.
```

#### Apple TV Privacy Policy (plain text)

Required for tvOS: the App Store on Apple TV can't open links, so it shows this text instead of the privacy policy URL. A plain-text copy of [the docs privacy page](https://m3ue.sparkison.dev/privacy/), trimmed to what applies on Apple TV. Keep the two in sync.

```
M3U TV PRIVACY POLICY
Last updated: November 10, 2026

M3U TV is a client for your own self-hosted M3U Editor server. It is not a hosted service, and the developer does not operate a backend that stores your content or personal data.

INFORMATION THE APP STORES OR SENDS

Server connection details. The server URL, username and password you enter are stored only on your Apple TV, in the Keychain, and are sent only to the server you configure. They are never sent to the developer or any third party.

Data sent to your own server. To work, the app sends the following to your server, and only to your server: viewing progress and watch history, favorites, followed sports teams, viewer profiles, DVR schedules, and basic device details (device name, platform, app version and a random ID the app generates on first launch). If you choose "Upload to server" on the Logs and Diagnostics screen, recent diagnostic logs are also sent to your server so its administrator can troubleshoot. None of this is sent to the developer.

Push notifications. If notifications are enabled, the app registers a device token with Firebase Cloud Messaging (Google) so your server can deliver notifications, such as recording updates. The token is used only for message delivery.

WHAT THE DEVELOPER DOES NOT COLLECT

The app contains no analytics, crash reporting, advertising or tracking. The developer does not collect usage statistics, viewing history or any other personal data.

OPTIONAL THIRD-PARTY SERVICES

These are contacted only when you use the related feature:
• Trakt (trakt.tv): if you connect a Trakt account, your watch history is synced with Trakt. Access tokens are stored in the Keychain, and you can disconnect at any time in Settings. Trakt privacy policy: trakt.tv/privacy
• SIMKL (simkl.com): if you connect a SIMKL account, your watch history is synced with SIMKL. Access tokens are stored in the Keychain, and you can disconnect at any time in Settings. SIMKL privacy policy: simkl.com/privacy
• TheIntroDB (theintrodb.org): when Skip Intro and Skip Credits are enabled, the app sends the public TMDB or IMDb ID, season and episode number of what you are watching to look up intro and credits timestamps. No personal information is sent. You can turn this off in Settings.
• OpenSubtitles (through its public Stremio add-on, opensubtitles-v3.strem.io): when you choose Search online in the player's subtitle menu, the app sends the public IMDb ID, season and episode number of what you are watching to find subtitles. No personal information is sent. You can turn this off, or choose another subtitle source, in Settings.
• GitHub (github.com): the app reads M3U TV's public release information from GitHub to show release notes and tell you when a new version is out. Nothing about you is sent beyond what any web request includes.

Artwork and metadata are provided by your own server, which may source them from TMDB. Your server's privacy practices are controlled by whoever operates it.

DATA RETENTION AND CONTROL

Log out, disconnect Trakt or SIMKL, or delete the app to remove all data stored on your Apple TV. Data on your own server, such as watch history, registered devices and uploaded logs, is controlled by that server's administrator and can be deleted there.

CHILDREN

The app is not directed at children under 13 and does not knowingly collect personal information from children.

CHANGES AND CONTACT

Changes to this policy are reflected in the "Last updated" date. The full policy is at m3ue.sparkison.dev/privacy. Questions: hello@sparkison.dev
```

### iOS and iPadOS

#### Promotional text (170)

```
New: CarPlay, Picture in Picture and background audio with Lock Screen controls, plus online subtitles and audio sync. Your own server, on iPhone and iPad.
```

#### Keywords (100)

```
epg,playlist,guide,live,player,dvr,carplay,catchup,multiview,trakt,movies,series,selfhosted,sports
```

#### Description (4000)

```
M3U TV is the iPhone and iPad app for M3U Editor, the open-source, self-hosted platform for managing your IPTV playlists, guides and media. Connect it to your own M3U Editor server and your live channels, movies and series come together in one fast, touch-friendly app. It's also available on Apple TV, built around the Siri Remote.

M3U TV does not include any channels, playlists or content. You need your own M3U Editor server and your own lawful sources.

HOME
• Continue Watching with Up Next episodes, so you can pick up right where you left off.
• Optional Spotlight home: a full-screen hero with artwork and title logos above your rows.
• Favorites and quick rows for Live TV, movies and series. Choose which screen the app opens on.
• Reorder the nav and Home rows, and hide the sections you don't use.

LIVE TV AND GUIDE
• A multi-day timeline guide with an optional live preview player.
• On Now and Upcoming views with station logos.
• Guide previews carry into full screen without restarting the stream.
• Catchup playback with seeking on channels that support it.
• Multiview: watch several channels at once.
• Pause live TV, and pick back up at the live point after a longer break.
• Custom channel sorting, favorites-first ordering and grid or list layouts.

SPORTS
• See each day's games with live scores, for the leagues your server is set up for.
• Find which of your own channels is showing a game, and start it in one tap.
• Game details with the score by period, key moments and team stats.
• Follow your teams, with My Teams and a Sports row on Home.
• Needs M3U Editor 0.14.1 or later with Sports turned on.

DVR
• Record a single airing or a whole series straight from the guide or search.
• Watch, cancel and delete recordings, and see storage usage at a glance.
• Your whole recordings library, with status filters and sorting.
• Automatic commercial skipping on recordings that support it.

MOVIES AND SERIES
• Detail pages with cast, filmographies, trailers, ratings and related titles.
• A season and episode browser with Up Next, plus an episode picker right in the player.
• Artwork while movies and episodes load.
• Skip Intro and Skip Credits prompts powered by TheIntroDB (optional).
• Sort by recently added, recently updated, title and more.
• Request new movies and shows through your server, and pick which service handles it when there's more than one.

SEARCH
• One search across channels, guide listings, movies and series.

PLAYBACK
• Native mpv playback with an automatic AVKit fallback.
• Audio and subtitle track selection, plus multichannel audio on iPhone and iPad.
• Picture in Picture, and background audio: keep listening after leaving the app or locking your device, with playback controls on the Lock Screen and in Control Center.
• Audio and subtitle sync, saved for each channel, movie or series.
• Search for subtitles online for movies and episodes.
• A built-in Logs and Diagnostics screen for troubleshooting.

CARPLAY
• Listen to your favorite channels and Live TV categories from your car's screen.
• Pick a channel in the car with your iPhone locked, then open the app and it carries on playing there.
• Now Playing shows the channel's logo and what's on, with next and previous channel.

MADE FOR YOUR HOUSEHOLD
• Multiple viewers, each with their own history and favorites.
• Keep several playlists on one device, from one server or more, each with its own favorites and guide.
• Trakt and SIMKL watch history sync, from the device or from your server.
• Settings and Home layouts your server can set up for every device, as defaults or locked.
• A notification center for alerts from your server, with per-channel subscriptions.
• Adjustable display scale.

OPEN SOURCE
M3U TV and M3U Editor are open source. Bring your own server, your own playlists and your own sources.
```

### macOS

Same Apple rules as above: no AIOStreams, no other platforms beyond Apple's own, and screenshots only from the demo server (`macos*` set). Mac-only notes: there is no CarPlay, Picture in Picture or background audio on Mac, so leave those out; and never mention the GitHub DMG or link to GitHub releases anywhere in the Mac listing.

#### Promotional text (170)

```
Your own M3U Editor server on your Mac: live TV with a multi-day guide, DVR, movies and series, with native mpv playback and full keyboard navigation.
```

#### Keywords (100)

```
epg,playlist,guide,live,player,dvr,simkl,catchup,multiview,trakt,movies,series,selfhosted,sports
```

#### Description (4000)

```
M3U TV is the Mac app for M3U Editor, the open-source, self-hosted platform for managing your IPTV playlists, guides and media. Connect it to your own M3U Editor server and your live channels, movies and series come together in one fast app that works with a mouse, trackpad or keyboard. It's also available on iPhone, iPad and Apple TV.

M3U TV does not include any channels, playlists or content. You need your own M3U Editor server and your own lawful sources.

HOME
• Continue Watching with Up Next episodes, so you can pick up right where you left off.
• Optional Spotlight home: a full-screen hero with artwork and title logos above your rows.
• Favorites and quick rows for Live TV, movies and series. Choose which screen the app opens on.
• Reorder the nav and Home rows, and hide the sections you don't use.

LIVE TV AND GUIDE
• A multi-day timeline guide with arrow-key navigation and an optional live preview player.
• On Now and Upcoming views with station logos.
• Guide previews carry into full screen without restarting the stream.
• Catchup playback with seeking on channels that support it.
• Multiview: watch several channels at once.
• Pause live TV, and pick back up at the live point after a longer break.
• Custom channel sorting, favorites-first ordering and grid or list layouts.

SPORTS
• See each day's games with live scores, for the leagues your server is set up for.
• Find which of your own channels is showing a game, and start it in one click.
• Game details with the score by period, key moments and team stats.
• Follow your teams, with My Teams and a Sports row on Home.
• Needs M3U Editor 0.14.1 or later with Sports turned on.

DVR
• Record a single airing or a whole series straight from the guide or search.
• Watch, cancel and delete recordings, and see storage usage at a glance.
• Your whole recordings library, with status filters and sorting.
• Automatic commercial skipping on recordings that support it.

MOVIES AND SERIES
• Detail pages with cast, filmographies, trailers, ratings and related titles.
• A season and episode browser with Up Next, plus an episode picker right in the player.
• Artwork while movies and episodes load.
• Skip Intro and Skip Credits prompts powered by TheIntroDB (optional).
• Sort by recently added, recently updated, title and more.
• Request new movies and shows through your server, and pick which service handles it when there's more than one.

SEARCH
• One search across channels, guide listings, movies and series.

PLAYBACK
• Native mpv playback that handles a wide range of formats and codecs.
• Audio and subtitle track selection, plus multichannel audio.
• Full screen with F11, and volume control in the player.
• Audio and subtitle sync, saved for each channel, movie or series.
• Search for subtitles online for movies and episodes.
• A built-in Logs and Diagnostics screen for troubleshooting.

MADE FOR YOUR HOUSEHOLD
• Multiple viewers, each with their own history and favorites.
• Keep several playlists on one device, from one server or more, each with its own favorites and guide.
• Trakt and SIMKL watch history sync, from the device or from your server.
• Settings and Home layouts your server can set up for every device, as defaults or locked.
• Adjustable display scale and navigation sounds.

OPEN SOURCE
M3U TV and M3U Editor are open source. Bring your own server, your own playlists and your own sources.
```

---

## Google Play (Android, Android TV, Google TV)

### App name (30)

```
M3U TV
```

### Short description (80)

```
Self-hosted Live TV, guide, DVR, VOD and AIOStreams client for M3U Editor
```

### Full description (4000)

```
M3U TV is the Android TV, Google TV and Android app for M3U Editor, the open-source, self-hosted platform for managing your IPTV playlists, guides and media. Connect it to your own M3U Editor server and your live channels, movies, series and AIOStreams catalogs come together in one fast, D-pad first interface, with full touch support on phones and tablets.

M3U TV does not include any channels, playlists or content. You need your own M3U Editor server and your own lawful sources.

HOME
• Continue Watching with Up Next episodes, so you can pick up right where you left off.
• Optional Spotlight home: a full-screen hero with artwork and title logos above your rows.
• Favorites and quick rows, a choice of start screen, and a nav and Home you can reorder or trim.

LIVE TV AND GUIDE
• A multi-day timeline guide built for D-pad remotes, with a live preview that carries into full screen.
• Catchup playback with seeking on channels that support it.
• Multiview: watch several channels at once.
• Pause live TV, and pick back up at the live point after a longer break.
• Works with Xtream API and standard M3U playlists served by M3U Editor.

SPORTS
• See each day's games with live scores, for the leagues your server is set up for.
• Find which of your own channels is showing a game, and start it in one press.
• Game details with the score by period, key moments and team stats.
• Follow your teams, with My Teams and a Sports row on Home.
• Needs M3U Editor 0.14.1+ with Sports turned on.

DVR
• Record a single airing or a whole series straight from the guide or search.
• Your whole recordings library, with status filters, sorting and storage usage at a glance.
• Automatic commercial skipping on recordings that support it.

MOVIES AND SERIES
• Detail pages with cast, filmographies, trailers, ratings and related titles.
• A season and episode browser with Up Next, plus an episode picker right in the player.
• Skip Intro and Skip Credits prompts powered by TheIntroDB (optional).
• Sort by recently added, recently updated, title and more.
• Request new movies and shows through your server, from the service you choose.

AIOSTREAMS
• Browse and search your AIOStreams catalogs next to your library, with full detail pages and Continue Watching.

SEARCH
• One search across channels, guide listings, movies, series and catalogs.

PLAYBACK
• ExoPlayer (Media3) with an automatic mpv fallback, or mpv first for movies and series.
• True HDR playback on supported TVs and devices, and picture-in-picture on phones and tablets.
• Background audio on phones and tablets, with notification and lock screen controls.
• Audio and subtitle track selection and sync, online subtitle search, and multichannel audio.
• Optional automatic frame rate matching on Android TV.
• Remote Play, Pause, Stop, Next and Previous buttons in the player.
• A built-in Logs and Diagnostics screen for troubleshooting.

ANDROID AUTO
• Your favorite channels and Live TV categories on your car's screen, with logos and what's on now.
• Pick a channel in the car, then open the app on your phone and it carries on there.

MADE FOR YOUR HOUSEHOLD
• Multiple viewers, each with their own history and favorites.
• Keep several playlists on one device, from one server or more, each with its own favorites and guide.
• Trakt and SIMKL watch history sync, from the device or from your server.
• Settings and Home layouts set up from your server.
• A notification center for alerts from your server.
• Quick setup: pair by scanning a QR code with your phone, even several playlists at once.
• Adjustable display scale, remote button mapping and navigation sounds.
• Available in English, German, Spanish, French and Simplified Chinese.

PLATFORMS
• Android TV and Google TV (D-pad remote), Android phones and tablets (touch).
• Also available on Apple TV, iPhone, iPad, Mac, Windows and Linux.

OPEN SOURCE
M3U TV and M3U Editor are open source. Bring your own server, your own playlists and your own sources.
```

### App content > Foreground service permissions

Required since v1.3.0, which declares `FOREGROUND_SERVICE_MEDIA_PLAYBACK` for background audio (`PlaybackService`). Play Console blocks the release until this is filled in. It covers the whole listing, Android TV included, even though TVs never start the service. Redo it only if the app starts using another foreground service type.

- **Permission:** Media playback
- **Video:** an unlisted YouTube or shared Google Drive link to a 30 to 60 second phone recording (see the script below).

**Describe the feature:**

```
M3U TV plays live TV and on-demand video from the user's own media server. With the Background audio setting on (the default on phones and tablets, and changeable in Settings > Playback), playback continues after the user leaves the app, locks the screen, or closes the picture-in-picture window. The media playback foreground service keeps that playback running and shows the system media notification with play, pause, seek and channel controls.
```

**What happens if the task is interrupted or deferred:**

```
Audio the user started would stop as soon as they leave the app, and they would lose the stream and its media controls. The playback is started by the user and is expected to keep going.
```

**Is it started by the user:** Yes. It only runs while media the user started is playing, and stops when they stop playback or close the player.

**Video script:**

1. Start a live channel on the phone.
2. Press Home: the player drops into picture-in-picture. Close the picture-in-picture window.
3. Audio keeps playing. Pull down the notification shade to show the media notification.
4. Pause and play from the notification, then skip to the next channel.
5. Open Settings > Playback, turn Background audio off, and show that leaving the player now stops playback.

### Android Auto

New in v1.3.0. The app declares itself an Android Auto media app (`CarMediaService` and the `com.google.android.gms.car.application` meta-data), but Google Play only offers it in cars once Android Auto is added to the release:

1. **Test and release > Advanced settings > Form factors:** add **Android Auto** and accept its terms.
2. Upload the release to a track. Android Auto releases get an extra review against the car app quality guidelines (driver distraction, no video in the car), which can take longer than a normal review.
3. The reviewers use the App access notes below, which say to sign in on the phone first.

---

## Microsoft Store (Windows)

### Product name

```
M3U TV
```

### Description (10000)

```
M3U TV is the Windows app for M3U Editor, the open-source, self-hosted platform for managing your IPTV playlists, guides and media. Connect it to your own M3U Editor server and your live channels, movies, series and AIOStreams catalogs come together in one fast interface that works with a mouse or a keyboard.

M3U TV does not include any channels, playlists or content. You need your own M3U Editor server and your own lawful sources.

HOME
• Continue Watching with Up Next episodes, so you can pick up right where you left off.
• Optional Spotlight home: a full-screen hero with artwork and title logos above your rows.
• Favorites and quick rows for Live TV, movies and series. Choose which screen the app opens on.
• Reorder the nav and Home rows, and hide the sections you don't use.

LIVE TV AND GUIDE
• A multi-day timeline guide with arrow-key navigation and an optional live preview player.
• On Now and Upcoming views with station logos.
• Guide previews carry into full screen without restarting the stream.
• Catchup playback with seeking on channels that support it.
• Multiview: watch several channels at once.
• Pause live TV, and pick back up at the live point after a longer break.
• Custom channel sorting, favorites-first ordering and grid or list layouts.
• Works with Xtream API and standard M3U playlists served by M3U Editor.

SPORTS
• See each day's games with live scores, for the leagues your server is set up for.
• Find which of your own channels is showing a game, and start it in one click.
• Game details with the score by period, key moments and team stats.
• Follow your teams, with My Teams and a Sports row on Home.
• Needs M3U Editor 0.14.1 or later with Sports turned on.

DVR
• Record a single airing or a whole series straight from the guide or search.
• Watch, cancel and delete recordings, and see storage usage at a glance.
• Your whole recordings library, with status filters and sorting.
• Automatic commercial skipping on recordings that support it.

MOVIES AND SERIES
• Detail pages with cast, filmographies, trailers, ratings and related titles.
• A season and episode browser with Up Next, plus an episode picker right in the player.
• Artwork while movies and episodes load.
• Skip Intro and Skip Credits prompts powered by TheIntroDB (optional).
• Sort by recently added, recently updated, title and more.
• Request new movies and shows through your server, and pick which service handles it when there's more than one.

AIOSTREAMS
• Browse and search your AIOStreams catalogs right next to your own library.
• Full movie and series detail pages, Continue Watching and Up Next for catalog titles.

SEARCH
• One search across channels, guide listings, movies, series and catalogs.

PLAYBACK
• Built-in libmpv playback that handles a wide range of formats and codecs.
• Audio and subtitle track selection, plus multichannel audio.
• Fullscreen with F11 or Alt+Enter, and volume control in the player.
• Audio and subtitle sync, saved for each channel, movie or series.
• Search for subtitles online for movies and episodes.
• A built-in Logs and Diagnostics screen for troubleshooting.

MADE FOR YOUR HOUSEHOLD
• Multiple viewers, each with their own history and favorites.
• Keep several playlists on one device, from one server or more, each with its own favorites and guide.
• Trakt and SIMKL watch history sync, from the device or from your server.
• Settings and Home layouts your server can set up for every device, as defaults or locked.
• Adjustable display scale and navigation sounds.
• Available in English, German, Spanish, French and Simplified Chinese.

PLATFORMS
• Windows (mouse and keyboard).
• Also available on Android TV, Google TV, Android, Apple TV, iPhone, iPad, Mac and Linux.

OPEN SOURCE
M3U TV and M3U Editor are open source. Bring your own server, your own playlists and your own sources.
```

### Product features (up to 20, 200 each)

```
Connects to your own self-hosted M3U Editor server (no content included)
Multi-day timeline TV guide with an optional live preview player
Catchup playback with seeking on supported channels
Multiview: watch several channels at once
Record single airings or whole series, with commercial skipping on supported recordings
Each day's games with live scores and your channels showing them, plus following your teams
Continue Watching with Up Next episodes
Optional Spotlight home with a full-screen hero
Reorder the nav and Home rows, and hide what you don't use
Movie and series detail pages with cast, trailers and related titles
Skip Intro and Skip Credits prompts powered by TheIntroDB
Browse and search AIOStreams catalogs alongside your library
One search across channels, guide listings, movies and series
Request new movies and shows through your server, from the service you choose
Multiple viewers with their own history and favorites
Trakt and SIMKL watch history sync, from the device or from your server
Several playlists on one device, each with its own favorites and guide
libmpv playback with track selection, audio and subtitle sync, and online subtitle search
Fullscreen with F11 or Alt+Enter, and full keyboard navigation
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
The Windows app for M3U Editor, the open-source, self-hosted IPTV and media platform. Watch live TV with a multi-day guide, catchup and Multiview, follow each day's games with live scores, record with the DVR, and browse movies, series and AIOStreams catalogs with Continue Watching, Up Next and Trakt or SIMKL sync. M3U TV does not include any content: you need your own M3U Editor server and your own lawful sources.
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

- **Minimum hardware notes:** `An internet or local network connection to your own M3U Editor server.`
- **Recommended hardware notes:** `A wired or 5 GHz Wi-Fi connection for HD and 4K streams.`

---

## Testing notes

Instructions for each store's reviewers. All stores use the same demo server, which serves only public-domain and freely licensed content. Never point a reviewer at a server with a commercial provider lineup: Apple and Google reject that as unauthorised content.

- **Server URL:** `https://api-tester-fcn5.onrender.com` (source: [m3u-api-tester](https://github.com/m3ue/m3u-api-tester); kept warm by an UptimeRobot ping every 5 minutes)
- **Username:** `testuser`
- **Password:** `testpass`

### Apple: App Review Information > Notes (4000)

Also fill in the separate "Sign-in required" username and password fields with the credentials above.

App Review Information is set per platform. For **macOS**, paste the same notes but drop the BACKGROUND AUDIO and CARPLAY sections, which don't apply on Mac.

```
M3U TV is a client for M3U Editor, an open-source, self-hosted media server (https://github.com/m3ue/m3u-editor). The app includes no content, playlists or streams. Users connect it to their own server and play only media they supply.

DEMO SERVER
A demo server is provided for review. It only serves Creative Commons licensed films from the Blender Foundation, public-domain classics and generated test channels. All artwork shown in the app and in our screenshots comes from these titles.

To sign in:
1. Launch the app. The Connection Settings screen opens.
2. Server URL: https://api-tester-fcn5.onrender.com (please include https://)
3. Username: testuser
4. Password: testpass
5. Select Connect.

Connecting usually takes a few seconds. If a server does not respond, the app now shows "Server is currently unavailable." after 30 seconds instead of loading indefinitely, and Connect can be selected again.

BACKGROUND AUDIO (iPhone and iPad)
Background audio is on by default (Settings > Playback > Background audio). Start any channel or movie, then leave the app: the video moves into Picture in Picture. Close it or lock the device and audio keeps playing, with controls on the Lock Screen and in Control Center.

CARPLAY (iPhone)
Sign in on the iPhone first, as above. Until then, CarPlay shows "Open M3U TV on your iPhone to sign in." Then open M3U TV in CarPlay:
1. Live TV lists the demo server's channel categories. Choose one, then a channel: it plays as audio, and the Now Playing screen shows the channel with play, pause and next and previous channel.
2. Favorites lists channels favorited in the app on the iPhone. It is empty until you favorite a channel there.
3. Opening the app on the iPhone while a channel plays in the car carries it on in the full-screen player.

Third-party services used via their public APIs: Trakt and SIMKL (optional watch history sync), TheIntroDB (optional skip intro timestamps), OpenSubtitles (optional subtitle search), YouTube (trailer links open externally).

Support: https://m3ue.sparkison.dev/support
```

### Google Play: App content > App access

Choose "All or some functionality is restricted", then add one set of instructions:

- **Name:** `Demo server`
- **Username:** `testuser`
- **Password:** `testpass`
- **Any other information:**

```
M3U TV is a client for M3U Editor, an open-source, self-hosted media server (https://github.com/m3ue/m3u-editor). The app includes no content. On first launch, enter https://api-tester-fcn5.onrender.com as the Server URL, then the username and password above. The demo server only serves public-domain and freely licensed content.

Android Auto: sign in on the phone first. M3U TV in Android Auto then shows Live TV (the demo server's channel categories) and Favorites (channels favorited in the app on the phone, empty until you favorite one).
```

### Microsoft Store: Submission options > Notes for certification

```
M3U TV is a client for M3U Editor, an open-source, self-hosted media server (https://github.com/m3ue/m3u-editor). The app includes no content, playlists or streams. Users connect it to their own server and play only media they supply.

To test, enter the following on the connection screen:
Server URL: https://api-tester-fcn5.onrender.com
Username: testuser
Password: testpass

The demo server only serves public-domain and freely licensed content. Optional third-party services used via their public APIs: Trakt and SIMKL (watch history sync), TheIntroDB (skip intro timestamps), OpenSubtitles (subtitle search), YouTube (trailer links open in the browser).
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

macOS: the first Mac App Store version has no What's New field. From the next release on, add an `#### Apple (macOS)` block: the Apple notes minus iPhone and iPad items (CarPlay, Picture in Picture, background audio), plus any desktop items such as fullscreen.

### v1.3.0

#### Apple (tvOS, iOS and iPadOS)

```
• CarPlay: listen to your favorite channels and Live TV from your car's screen, and carry on in the app on your iPhone.
• Picture in Picture and background audio on iPhone and iPad, with controls on the Lock Screen and in Control Center.
• Audio and subtitle sync, saved for each channel, movie or series.
• Search for subtitles online for movies and episodes.
• SIMKL watch history sync. Trakt and SIMKL also work alongside accounts connected on your server.
• Your server can now set up settings and Home layouts for every device. Needs M3U Editor 0.14.2 or later.
• Add several playlists in one pairing.
• Your whole DVR library, with status filters and sorting.
• Pick which service handles a request when your server has more than one.
• Continue Watching moves on to the next episode as soon as you finish one, and Up Next episodes can be skipped.
• Smaller display size options, and many fixes.
```

#### Google Play

```
• Android Auto: your favorite channels and Live TV in the car.
• Audio and subtitle sync, and online subtitle search.
• SIMKL sync, and Trakt and SIMKL alongside your server's accounts.
• Settings and Home layouts from your server (M3U Editor 0.14.2+).
• Full DVR library with filters and sorting.
• Remote Play, Pause, Stop, Next and Previous in the player.
• Choose ExoPlayer or mpv for movies and series.
```

#### Microsoft Store

```
• Audio and subtitle sync, saved for each channel, movie or series.
• Search for subtitles online for movies and episodes.
• SIMKL watch history sync. Trakt and SIMKL also work alongside accounts connected on your server.
• Your server can now set up settings and Home layouts for every device. Needs M3U Editor 0.14.2 or later.
• Add several playlists in one pairing.
• Your whole DVR library, with status filters and sorting.
• Pick which service handles a request when your server has more than one.
• Continue Watching moves on to the next episode as soon as you finish one, and Up Next episodes can be skipped.
• A notice when a new version is out, smaller display size options, and many fixes.
```

### v1.2.5

#### Apple (tvOS, iOS and iPadOS)

```
• New Sports screen: each day's games with live scores, game details, and which of your own channels is showing them. Needs M3U Editor 0.14.1 or later with Sports turned on.
• Follow your teams, with My Teams and a Sports row on Home.
• Keep several playlists on one device and switch between them.
• Navigation & Home: reorder the nav and Home rows, and hide the sections you don't use.
• New Storage page shows what the app keeps on your device and clears each part on its own.
• Guide previews now carry into full screen without restarting the stream.
• Sort movies and series by title.
• Smoother video on iPhone and iPad, performance improvements and many fixes.
```

#### Google Play

```
• New Sports screen: live scores and your channels showing each game. Needs M3U Editor 0.14.1+.
• Keep several playlists on one device.
• Reorder or hide nav and Home sections.
• New Storage page.
• Guide previews carry into full screen.
• Sort movies and series by title.
• Fixes the OK button on remotes like the Mi Box 3, and launch crashes on older phones and tablets.
```

#### Microsoft Store

```
• New Sports screen: each day's games with live scores, game details, and which of your own channels is showing them. Needs M3U Editor 0.14.1 or later with Sports turned on.
• Follow your teams, with My Teams and a Sports row on Home.
• Keep several playlists on one device and switch between them.
• Navigation & Home: reorder the nav and Home rows, and hide the sections you don't use.
• New Storage page shows what the app keeps on your device and clears each part on its own.
• Guide previews now carry into full screen without restarting the stream.
• Sort movies and series by title.
• Performance improvements and many fixes.
```

### v1.2.4

#### Apple (tvOS, iOS and iPadOS)

```
• New episode picker in the player: switch episodes or seasons without leaving playback.
• Movies and episodes now show their artwork while loading.
• Live channels stall less, plus a new option to buffer live streams before playing.
• If a server doesn't respond, connecting now shows an error you can retry instead of loading forever.
• Performance improvements and many fixes.
```

#### Google Play

```
• New episode picker in the player.
• Artwork while movies and episodes load.
• True HDR playback on supported Android TVs and devices.
• Picture-in-picture and edge-to-edge on phones and tablets.
• Live channels stall less on the mpv fallback player.
• An unresponsive server now shows an error you can retry instead of loading forever.
```

#### Microsoft Store

```
• New episode picker in the player: switch episodes or seasons without leaving playback.
• Movies and episodes now show their artwork while loading.
• Live channels stall less, plus a new option to buffer live streams before playing.
• Chinese text now uses Chinese fonts instead of Japanese glyph forms.
• If a server doesn't respond, connecting now shows an error you can retry instead of loading forever.
• Performance improvements and many fixes.
```

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
