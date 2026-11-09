# Brief for feature builders (La Popote iOS)

Native SwiftUI port (iOS 26+, Swift 6 strict concurrency) of https://la-popote-de-tata-suzanne.lovable.app,
sharing its Supabase backend. The repo is /Users/uwe/dev/github.com/djui/la-popote-de-tata-suzanne.

Read first:
- docs/spec/SPEC.md: the reverse-engineered functional spec of the website (exact French copy, queries,
  business rules). Your feature must match it (copy, behaviour, data writes). Grep it by section.
- Popote/Core/*: AppStore (an @Observable @MainActor store, injected with `@Environment(AppStore.self)`),
  offline snapshot plus outbox (AppStore+Offline.swift), Models.swift, Quantity.swift (scaling and formatting),
  PhotoCache.swift (`RecipePhotoView(path:category:)`), ServerFunctions.swift (`store.serverFunctions.call(id, data:)`),
  Backend.swift (`store.client` is the SupabaseClient, supabase-swift 2.x).
- Popote/DesignSystem/Theme.swift: Palette, AppFont (Fraunces display, Nunito body, Dancing Script),
  button styles `.popotePrimary`, `.popotePrimaryCompact`, `.popoteSecondary`, `.popoteCard()`,
  `.popoteBackground()`, `ChipView`, `Wordmark`.
- Popote/App/RootView.swift + PopoteApp.swift: tabs, Router (deep links), SyncStatusButton (put it in toolbars).

Design direction: keep the website's identity (cream and navy, Fraunces headings, Nunito text, navy gradient
tiles, the lemon) but use modern iOS 26 idioms: NavigationStack with large titles, native List/ScrollView,
toolbar items (which render as Liquid Glass automatically), sheets instead of dialogs, swipe actions,
context menus, `.searchable`, `ContentUnavailableView` for empty states, haptics (`.sensoryFeedback`),
Dynamic Type friendly (use AppFont with relativeTo), VoiceOver labels. Every screen must look right in
light AND dark mode (only use Palette colours or semantic system colours). iPad must not break (use readable
max widths).

Strings: the UI is French by default with an English localization added later from a String Catalog. Write the
French copy exactly as in SPEC.md, using `Text("…")` / `Button("…")` literals (LocalizedStringKey) or
`String(localized: "…")` for non-view strings, so Xcode extracts them. Don't hardcode English.

Offline: reads come from AppStore's in-memory mirror (never fetch for display if the store already has
the data). For writes that must work offline (favorites, ratings, menu, shopping list) use the existing
optimistic store methods / outbox. For online-only actions (comments, reports, recipe create/edit/delete,
AI import, household admin) check `store.isOnline`, disable the control when offline, and show a short
explanation. Never block the UI on the network. Show errors inline or as a lightweight banner, in French.

Rules for working in parallel with the other builders:
- Only create or edit files inside YOUR folders (listed in your task). If you truly need a change in
  Popote/Core or another shared file, keep it minimal and additive (prefer a new extension file in your
  folder, e.g. `Features/Menu/AppStore+Menu.swift`), and list it in your final report.
- The placeholder views RecipesTab/MenuTab/ShoppingTab/ProfileTab/TermsView/StoryView, plus the stubs in
  Popote/Services and Widgets/, are owned by whoever's task names them. Replace them in place.
- Build with your own derived-data path so builds don't collide:
  `cd /Users/uwe/dev/github.com/djui/la-popote-de-tata-suzanne && xcodegen generate --quiet && xcodebuild -project Popote.xcodeproj -scheme Popote -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build/dd-<yourname> build 2>&1 | grep -E "error:|BUILD" | head -40`
  If the only errors are in another builder's files, wait about a minute and retry. Don't fix their files.
- Add unit tests for pure logic in PopoteTests/<YourArea>Tests.swift (Swift Testing). Run them with `test`
  instead of `build`.
- Do NOT git commit, push, or run the app on a simulator; the lead does that.
- Finish with a build that has zero errors in your files, and report: files created/changed, any shared-file
  changes, what is deliberately not done, and anything you are unsure about.
