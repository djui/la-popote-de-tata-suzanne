<p align="center"><img src="docs/assets/icon.png" width="120" alt="La Popote app icon"></p>

# La Popote de Tata Suzanne — iOS

A native iPhone and iPad app (SwiftUI, iOS 26+) for [La Popote de Tata Suzanne](https://la-popote-de-tata-suzanne.lovable.app), a family recipe book. It uses the same accounts and data as the website, and keeps working offline.

- **Recipes**: search, filters by category and season, favorites, ratings, threaded comments, portion scaling with French quantity formatting.
- **New recipe**: from a photo of a book or notebook (AI import), pasted text, a web link, or typed by hand.
- **Cook mode**: step by step, tappable timers, Live Activity on the Lock Screen and in the Dynamic Island.
- **Menu**: lunch and dinner for the week, shared with the household.
- **Shopping list**: built from the menu, grouped by aisle in your shop's order, synced live between family members, exportable to Reminders.
- **Offline**: every recipe and photo is stored on the device. Changes made offline sync when you're back online.
- **Extras**: Home Screen and Lock Screen widget for today's menu, Spotlight search, Siri / App Shortcuts.
- Light and dark mode. French and English.

## Architecture

| | |
|---|---|
| UI | SwiftUI, Observation, Swift 6 strict concurrency, Liquid Glass via native components |
| Backend | The website's Supabase project via [`supabase-swift`](https://github.com/supabase/supabase-swift), using only its public key and the user's session. Row-level security applies unchanged. |
| AI import, account deletion | The website's TanStack Start server functions (`POST /_serverFn/<id>`, seroval-encoded), see `Popote/Core/ServerFunctions.swift` |
| Offline | In-memory store persisted as a JSON snapshot, an outbox of pending writes replayed in order, a photo cache on disk, and Realtime for the menu and shopping list (`Popote/Core`) |
| Widgets | WidgetKit plus ActivityKit extension (`Widgets/`), fed through an App Group |

`docs/spec/SPEC.md` is the functional spec of the website the app mirrors, reverse-engineered from its client bundle.

## Building

```bash
brew install xcodegen fastlane
xcodegen generate
open Popote.xcodeproj
```

Tests:

```bash
xcodebuild -project Popote.xcodeproj -scheme Popote -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

TestFlight (needs an App Store Connect API key in `~/.appstoreconnect`, see `fastlane/Fastfile`):

```bash
cd fastlane && fastlane beta
```

## Website

The companion site (landing page, privacy policy, support) lives in `docs/` and is served by GitHub Pages at <https://uwe.social/la-popote-de-tata-suzanne/>.

## License

The code is MIT licensed. The recipes, photos and the "La Popote de Tata Suzanne" name and logo belong to their authors and are not covered by this licence.
