# La Popote de Tata Suzanne: functional spec (reverse-engineered)

Source: the production client bundle of https://la-popote-de-tata-suzanne.lovable.app, read statically and never executed. Anything marked **(inferred)** is a deduction, not something read directly from code. Server code (server-fn handlers, DB triggers, RLS, RPC bodies, AI prompts) is not in the client bundle, so it is described only by how the client uses it.

## 0.1 Stack
- TanStack Start + TanStack Router (file routes) + React + TanStack Query. UI is shadcn/radix, lucide icons, sonner toasts, and dnd-kit (menu and aisle ordering). Tailwind v4.
- Supabase project `pwlrzjmqagwlvncfvfel` (`https://pwlrzjmqagwlvncfvfel.supabase.co`, publishable key `sb_publishable_9ixRQH2cuoWUzbKG3mj4YQ_T_J0zG_T`). Session is persisted in localStorage with auto refresh.
- Server functions: `POST /_serverFn/<sha256 id>` with a seroval-JSON body `{data}`, header `x-tsr-serverFn: true`, and `Authorization: Bearer <supabase access_token>` added by a global client middleware. See C.11 and A.14.
- `/api/broadcast` belongs to supabase realtime-js internals. The app never calls it (C.11).

## 0.2 Route map

| Path | Auth | Section |
|---|---|---|
| `/` | public | C.5 |
| `/auth` | public | C.6 |
| `/conditions`, `/histoire`, `/video` | public | C.10, A.15 |
| `/recettes` | auth | B.2 |
| `/recettes/nouvelle` | auth | **N** |
| `/recettes/$id` | auth | A.2 |
| `/recettes/$id/cuisiner?p=` | auth | A.3 |
| `/recettes/$id/modifier` | auth | A.4 |
| `/mes-recettes` | auth | B.3 |
| `/menu` (the "meal plan") | auth | B.4 |
| `/courses` | auth | B.5 |
| `/profil` (includes household "Ma famille" and "Mon magasin") | auth | C.7, B.6 |
| `/invitation/$code` | auth | C.8, B.7 |
| `/admin/ingredients`, `/admin/signalements` | auth + client-side admin check | C.9 |

There is **no** `/meal-plan` or `/household` route. `meal-plan-*.js` and `household-*.js` are shared helper modules. Authenticated routes sit under a pathless `_authenticated` layout whose `beforeLoad` runs `auth.getUser()` and redirects to `/auth`. They are also wrapped in a terms-acceptance gate (C.3).

## 0.3 Data model index (columns as seen from the client; details in the referenced sections)

| Table | Columns used | Main ops / where |
|---|---|---|
| `recipes` | id, title, categories text[], seasons text[], servings, prep_time_min, cook_time_min, difficulty, tags text[], notes, source_inspiration, source_url, is_private, rights_certified_at, photo_url, photo_thumb_url (storage paths), source_image_urls text[], created_at, created_by (FK `recipes_created_by_fkey` → profiles), rating_avg, rating_count | A.1, A.5, B.1.4, N |
| `recipe_ingredients` | id, recipe_id, position, raw_text, name, quantity, unit, shopping_category, optional, ingredient_id (set by the DB, inferred) | deleted and re-inserted on every save (A.5) |
| `recipe_steps` | id, recipe_id, position, instruction | deleted and re-inserted (A.5) |
| `ingredients` | id, name, display_name, plural_name, aliases, category_id, seasons, verified, source, pending_ai | B.1.5, C.9 (admin validates and merges), A.13 |
| `ingredient_categories` | id, name, color, icon, sort_order | aisles (B.5) |
| `households` | id, name, default_servings | B.1.1, B.6 |
| `household_members` | user_id, role, joined_at | B.6 |
| `household_invitations` | id, household_id, email, code, expires_at, created_at | B.6, C.7 |
| `household_category_orders` | household_id, category_id, sort_order (upsert onConflict `household_id,category_id`) | B.6.3 |
| `household_ingredient_overrides` | ingredient_id, category_id (written via RPC `set_ingredient_category`) | B.5 |
| `meal_plan_entries` | id, date, meal_type (`déjeuner` / `dîner`), recipe_id?, custom_title?, servings, position | B.4, A.7 |
| `shopping_list_items` | id, week_start, name, quantity, unit, ingredient_id, item_key, source, source_recipe_ids, checked, checked_at, checked_by, in_stock, created_at | B.5 |
| `recipe_favorites` | recipe_id, user_id, created_at | A.13, B.1.6 |
| `recipe_ratings` | recipe_id, user_id, stars (upsert onConflict `recipe_id,user_id`) | A.8 |
| `recipe_comments` | id, recipe_id, user_id, parent_id, content, edited, deleted, created_at | A.11 |
| `content_reports` | id, recipe_id, recipe_title, user_id, reason (`droits d'auteur` / `contenu inapproprié` / `erreur`), details, resolved, created_at | A.12, C.9 |
| `profiles` | id, first_name | C.7 |
| `terms_acceptances` | user_id, terms_version (`1.0`), accepted_at | A.9, C.3 |
| `user_roles` | user_id, role (`admin`) | C.7, C.9 |
| `ai_usage_logs` | id, recipe_id (back-filled after save) | N.8, A.14 |

RPCs called from the client: `get_invitation(_code)`, `accept_invitation(_code)`, `my_invitations()`, `remove_household_member(_user_id)`, `leave_household()`, `set_ingredient_category(_ingredient,_category)`, `recipe_favorite_count(_recipe_id)`, `recipe_favorite_names(_recipe_id)`, `merge_ingredients(...)`.
Realtime (postgres_changes): `recipe_comments` (filtered by recipe), `meal_plan_entries`, `shopping_list_items`, `ingredients`, `household_ingredient_overrides`.
Storage: a single private bucket `recipe-photos`, path `{uid}/{plats|sources}/{uuid}.{ext}`, displayed through 1-hour signed URLs (A.15).

## 0.4 Server functions

| id | Purpose | Input `{data:…}` | Output |
|---|---|---|---|
| `0aa253b0d610fbe837a4ec9ad4f338f5ca37a75a618338b85c58fafac32aa5ad` | photo(s) → recipe (AI vision) | `{images: dataURL[] (≤6, webp ≤0.5MB)}` | `{recipe, dishPhotos?, error?, logId}` |
| `e4fe9f8721a74c14b325e4d6c34321d86241473f65a7b0dc9296ad046a4caf33` | text → recipes | `{text ≤15000}` | `{recipes[], error?, logId}` |
| `a2b48a88e43523c600947bf17d04c7894e27a6228277bbd569d884062a5ba4ef` | URL → recipes | `{url}` | `{recipes[], error?, logId, image?, site?}` |
| `789c6d723c3130a983ec35993e4ec23d1f75a48585adf43e2a4f87361d9321b5` | enrich/categorize ingredients flagged `pending_ai` (inferred) | `{ids: string[]}` | ignored |
| `27301031363e284184ead21ac910c33ebfbe9159435c975f26319c6a65fade88` | delete account | `{confirmation:'SUPPRIMER', keepRecipes:boolean}` | see C.7 |

All are `method: POST`. The AI output JSON schema is in N.6.

## Contents
- Part C: root/head, routes, app shell, home, auth, profile, invitation, admin, legal pages, server-fn transport, design tokens
- Part N: new-recipe wizard and AI import
- Part A: recipe detail, cook mode, edit, persistence, enums, ratings/comments/favorites/reports, scaling and formatting, storage/photo pipeline, RecipeForm
- Part B: recipe list and filters, Mon livre de cuisine, weekly menu, shopping list, household, invitations

---
# Part C: routes, shell, auth, profile, legal pages, admin, server-fn transport, design tokens

Sources: index-ysFXFbDw.js (route tree at bytes ~247000–262650), route-DI0dhos1.js, AppShell-DabPYfTk.js, Logo-GNW7qNWP.js, routes-DU16t_sC.js, auth-DBiMU1xP.js, terms-Dmm63a7x.js, household-DNKBWHf4.js, meal-plan-aaED2QKP.js, profil-CAUNkA7w.js, AcceptButton-CCl_ukBP.js, invitation._code-DqW3Ur5c.js, conditions-CoI6eRoy.js, histoire-CBJe7j0X.js, video-CO0eg8Cu.js, admin.ingredients-BpvuNd4D.js, admin.signalements-CaCt57vb.js, useServerFn-DAeLR-zp.js, ingredients-Ba4c7mUu.js (TanStack Start client runtime), styles-6qR1Ax3b.css.

## C.1 Root document / head

- `<html lang="fr">`. Root meta: charset utf-8; viewport `width=device-width, initial-scale=1, viewport-fit=cover`; title `La Popote de Tata Suzanne`; `theme-color` = `#1D3256`; description `Les recettes de famille, partagées entre tous.`; `og:type=website`; `twitter:card=summary_large_image`.
- Links: stylesheet `/assets/styles-6qR1Ax3b.css`; icon `/favicon.png` (image/png); manifest `/manifest.webmanifest` (PWA); apple-touch-icon `/icon-192.png`; preconnect fonts.googleapis.com and fonts.gstatic.com (crossorigin); Google Fonts CSS: `family=Fraunces:opsz,wght@9..144,600;9..144,800&family=Dancing+Script:wght@600;700&family=Nunito:wght@400;600;700&display=swap`.
- Root component: QueryClientProvider (TanStack Query) + `<Outlet/>` + Sonner `<Toaster position="top-center">` (classNames: toast `bg-background text-foreground border-border shadow-lg`, description `text-muted-foreground`, action `bg-primary text-primary-foreground`, cancel `bg-muted text-muted-foreground`). All toasts use the `toast` export from the index chunk (Sonner).
- Auth listener: `supabase.auth.onAuthStateChange`; on `SIGNED_IN` / `SIGNED_OUT` / `USER_UPDATED` it calls `router.invalidate()`; on SIGNED_OUT it calls `queryClient.clear()`, otherwise `queryClient.invalidateQueries()`.
- Router: `createRouter({routeTree, context:{queryClient: new QueryClient()}, scrollRestoration:true, defaultPreloadStaleTime:0})`, hydrated with `hydrateRoot(document, <StrictMode>…)`.
- 404 component (notFound): big `404`, h2 `Page introuvable`, p `Cette page n'existe pas ou a été déplacée.`, link to `/` `Retour à l'accueil`.
- Error component: h1 `La page n'a pas pu se charger`, p `Une erreur s'est produite. Réessaie ou reviens à l'accueil.`, buttons `Réessayer` (router.invalidate + reset) and `<a href="/">Accueil</a>`. The error is reported to `window.__lovableEvents.captureException` / `window.__lovableReportRuntimeError` (Lovable telemetry, optional).

## C.2 Route list

Public routes (no guard):

| Path | Chunk | Head title | Meta description |
|---|---|---|---|
| `/` | routes-*.js | `La Popote de Tata Suzanne — les recettes de famille` | `Les recettes de famille, partagées entre tous : prends-les en photo, planifie la semaine, fais les courses.` |
| `/auth` | auth-*.js | `Connexion — La Popote de Tata Suzanne` | `Les recettes de famille, partagées entre tous.` |
| `/conditions` | conditions-*.js | `Conditions générales d’utilisation — La Popote de Tata Suzanne` | `Conditions d’utilisation, partage des recettes et protection de tes données. Version 1.0 du 4 novembre 2026.` |
| `/histoire` | histoire-*.js | `L'histoire de Tata Suzanne — La Popote` (og:type article) | `Tata Suzanne, c'est Marion : des magazines découpés, des post-it partout, et l'envie de tout réunir pour partager.` |
| `/video` | video-*.js | `La Popote de Tata Suzanne en vidéo` (og:type video.other) | `Découvre en vidéo La Popote de Tata Suzanne : une photo de recette, et ton menu et tes courses s'organisent tout seuls.` |

Pathless layout `/_authenticated` (route-DI0dhos1.js = `<AppShell><Outlet/></AppShell>`). Guard: `beforeLoad: async () => { const {data} = await supabase.auth.getUser(); if (!data.user) throw redirect({to:'/auth'}); return {user: data.user} }`. Children:

| Path | Chunk | Title | Description | Loader |
|---|---|---|---|---|
| `/courses` | courses-*.js | `Liste de courses — La Popote de Tata Suzanne` | `Ta liste de courses générée depuis le menu, rangée par rayon.` | – |
| `/menu` | menu-*.js (the "meal-plan" screen; meal-plan-*.js is a helper lib) | `Menu de la semaine — La Popote de Tata Suzanne` | `Planifie déjeuners et dîners de la semaine en glissant tes recettes.` | ensureQueryData(recipes list query `ye` from recipe-data) |
| `/mes-recettes` | mes-recettes-*.js | `Mon livre de cuisine — La Popote de Tata Suzanne` | `Les recettes que tu as ajoutées à la base commune, avec leurs notes.` | recipes list |
| `/profil` | profil-*.js | `Profil — La Popote de Tata Suzanne` | `Ton compte, ta famille et tes préférences.` | – |
| `/admin/ingredients` | admin.ingredients-*.js | `Ingrédients à vérifier — La Popote de Tata Suzanne` | `Valider, corriger et fusionner les ingrédients ajoutés automatiquement.` | – |
| `/admin/signalements` | admin.signalements-*.js | `Signalements — La Popote de Tata Suzanne` | `Examiner les contenus signalés par la tablée.` | – |
| `/invitation/$code` | invitation._code-*.js | `Invitation — La Popote de Tata Suzanne` | `Rejoins un foyer pour partager menu et liste de courses.` | – |
| `/recettes/` | recettes.index-*.js | `Recettes — La Popote de Tata Suzanne` | `Cherchez dans la base commune de recettes par titre, ingrédient, saison ou temps.` | recipes list |
| `/recettes/nouvelle` | recettes.nouvelle-*.js | `Nouvelle recette — La Popote de Tata Suzanne` | `Ajoute une recette en photo ou à la main.` | – |
| `/recettes/$id/` | recettes._id.index-*.js | `Recette — La Popote de Tata Suzanne` | `Ingrédients, étapes et portions ajustables.` | ensureQueryData(recipe detail `be(id)`) |
| `/recettes/$id/cuisiner` | recettes._id.cuisiner-*.js | `Mode cuisine — La Popote de Tata Suzanne` | `La recette pas à pas, en grand, avec minuteurs.` | recipe detail. `validateSearch`: `p` = integer 1..99 (portions), otherwise `{}` |
| `/recettes/$id/modifier` | recettes._id.modifier-*.js | `Modifier la recette — La Popote de Tata Suzanne` | `Modifiez les ingrédients, étapes et informations de la recette.` | recipe detail |

All child routes also set og:title/og:description to the same values, `og:type=website`, `twitter:card=summary`.
Admin routes have no router guard: the component checks `me.isAdmin` (see C.8).
Nothing in the bundle defines `/meal-plan` or `/household` routes. `household-*.js` and `meal-plan-*.js` are shared helper modules.

## C.3 App shell (AppShell-*.js), used by every authenticated route

- Nav items, in order: `{to:'/recettes', label:'Recettes', icon: lucide book-open}`, `{to:'/menu', label:'Menu', icon: calendar-days}`, `{to:'/courses', label:'Courses', icon: shopping-basket}`, `{to:'/profil', label:'Profil', icon: user}`.
- Desktop (md+): fixed left `aside` w-56, `border-r bg-nav p-4`. At the top it links to `/recettes` with the logo image (h-11 w-11) and the inline wordmark (`La Popote` in script + ` de Tata Suzanne`). Items: `rounded-xl px-3 py-2.5 text-muted-foreground hover:bg-accent`, active `bg-accent text-foreground`, icon h-5.
- Mobile (<md): sticky top header `border-b bg-background/90 backdrop-blur` with the logo image h-8 and the text `La Popote de Tata Suzanne` (font-script text-2xl text-primary). Fixed bottom nav `grid-cols-4 border-t bg-nav pb-[env(safe-area-inset-bottom)]`, items with icon h-6 + label text-xs, active `text-primary`. Content has `pb-24` on mobile and `md:pl-56` on desktop.
- `main`: `mx-auto px-4 py-5 md:px-8 md:py-8`. Max width is `max-w-[1500px]` when the pathname is `/menu`, otherwise `max-w-5xl`.
- Footer inside main: link `/conditions` `Conditions générales d'utilisation`.
- **Terms gate** (wraps the children): it runs the query `['terms-acceptance']` (staleTime 0): `terms_acceptances.select('accepted_at').eq('user_id', uid).eq('terms_version','1.0').maybeSingle()` → boolean. The query throws `Non connecté` if there is no user.
  - While pending it shows `Chargement…`.
  - If the result is true it renders the children.
  - Otherwise it shows a non-dismissable Dialog (Escape and outside clicks are blocked, the close button is hidden):
    - title `Les conditions de la tablée`
    - description `Accepte la version 1.0 pour continuer à utiliser la Popote.`
    - link `Lire les conditions générales d'utilisation` (to `/conditions`, opens in a new tab)
    - checkbox `J'ai lu et j'accepte les conditions générales d'utilisation`
    - on query error: `Impossible de vérifier ton acceptation. Réessaie.`
    - button `Accepter et continuer`, disabled until the box is checked. It inserts `terms_acceptances {user_id, terms_version:'1.0'}` and ignores error code `23505` (duplicate). On failure the toast is `L'acceptation n'a pas pu être enregistrée`.
    - ghost button `Se déconnecter`: cancelQueries, clear, signOut, navigate `/auth` (replace).
- `CategoryTile` component (exported `n`): props `{icon,label,onClick,active,size='md',tone=''}`. It renders a `.tile` square (`rounded-2xl`, `group-active:scale-95`; on md+ `aspect-auto min-h-16` showing the label instead of the icon). Active state is `ring-4 ring-foreground/80`. The icon is h-12 (h-8 when size sm) with strokeWidth 1.4, and the label sits under the tile on mobile. Every category `tone` is the empty string in recipes-*.js, so tone has no visual effect today.

## C.4 Logo (Logo-*.js)

- Asset `/assets/logo-popote-0Wr8eWUh.png` (562×792, `alt=""`, object-contain).
- `LogoMark({className='h-10 w-10'})` is the image alone.
- `LogoStacked` (export `t`): the image at h-20, then a block rotated `-rotate-[12deg]`, font-script, text-primary, leading-[0.95], with two lines `La Popote` (`-translate-x-5 text-5xl`) and `de Tata Suzanne` (`-translate-x-4 text-5xl`).
- `Wordmark({short})`: when short it is `La Popote` (font-script text-primary). Otherwise it is font-display with `La Popote` (script, primary) followed by ` de Tata Suzanne` (`ml-1.5 text-foreground`).

## C.5 Home `/` (routes-*.js)

- Layout: `mx-auto flex min-h-screen max-w-md flex-col px-6 py-10`.
- h1 holds the stacked logo.
- Tagline (centered, text-lg, muted): `Les recettes de famille,` ⏎ `partagées entre tous.` ⏎ `Une photo et c'est rangé : ajuste les portions, planifie la semaine.`
- A grid-cols-3 shows the first 6 recipe categories from recipes-*.js, each as a `.tile` square with its icon (h-10, stroke 1.4) and the label below in text-sm font-semibold. These tiles are not clickable.
- Feature list with text-primary icons: camera `Lecture automatique des recettes en photo`; calendar-days `Menus de la semaine`; shopping-basket `Liste de courses par rayon`.
- CTA (lg button, full width, rounded-xl) linking `/recettes`: `Ouvrir mes recettes`. If the user is signed out, the `_authenticated` guard sends them to `/auth`.
- Footer links: `L'histoire de Tata Suzanne` (`/histoire`) and `Conditions générales d'utilisation` (`/conditions`).

## C.6 Auth `/auth` (auth-*.js)

- State: `mode` = `'in'` (default) or `'up'`; fields email, firstName, inviteCode, password; `termsAccepted`, `loading`, `signupDone`.
- Layout: `mx-auto flex min-h-screen max-w-sm flex-col justify-center px-6`, stacked logo, then the tagline `Les recettes de famille,` ⏎ `partagées entre tous.`
- Form fields, in order (shadcn Label + Input):
  - signup only: `Code d'invitation` (id invite, required, autocomplete off)
  - signup only: `Prénom` (id fn, required)
  - `Email` (type email, required)
  - `Mot de passe` (type password, required, minLength 6)
  - signup only: Checkbox + `J'ai lu et j'accepte les ` + link `conditions générales d'utilisation` (to `/conditions`, target _blank)
- Submit button (lg, full width, rounded-xl): `Se connecter` or `Créer mon compte`. It is disabled while loading, and in signup mode until the terms box is checked.
- Toggle (underlined muted text): `Pas encore de compte ? S'inscrire` / `Déjà un compte ? Se connecter`.
- Below the form: link `Conditions générales d'utilisation` (`/conditions`) and a script-font link `Mais qui est Tata Suzanne ?` (`/histoire`).
- **Sign in**: `supabase.auth.signInWithPassword({email, password})`. On error the toast is `Oups, email ou mot de passe incorrect`. On success it navigates `/recettes`.
- **Sign up**:
  - It first validates the zod schema `z.object({terms_version: z.literal('1.0'), terms_accepted: z.literal(true)})` on `{terms_version:'1.0', terms_accepted}`. If that fails the toast is `Accepte les conditions générales pour créer ton compte`.
  - Then it calls:
    ```js
    supabase.auth.signUp({ email, password, options: {
      emailRedirectTo: window.location.origin + '/recettes',
      data: { invite_code: inviteCode.trim(), first_name: firstName.trim(), terms_version: '1.0', terms_accepted: <bool> } } })
    ```
  - On error, if the message matches `/invitation|database error/i` the toast is `Ce code d'invitation n'est pas valide`. Otherwise the raw `error.message` is shown.
  - (inferred) The invite code is checked server-side by a DB trigger on auth.users insert. The trigger raises an error, which surfaces as "Database error saving new user". The same trigger probably creates `profiles.first_name`, the `terms_acceptances` row, and a personal household.
  - On success the form is replaced with a card: `Jette un œil à ta boîte mail pour confirmer ton compte, puis reviens te connecter.`
- There is no password reset, magic link, or OAuth anywhere in the bundle (no `resetPasswordForEmail` or `updateUser`). The password cannot be changed in the app.
- Sign out happens in three places:
  - Profil button `Se déconnecter`: `supabase.auth.signOut()` then navigate `/auth`.
  - The terms gate (see C.3).
  - After account deletion.

## C.7 Profil `/profil` (profil-*.js)

Queries used (household-*.js):
- `me` (`['me']`): it calls `auth.getUser()`, then in parallel `profiles.select('first_name').eq('id',uid).maybeSingle()` and `user_roles.select('role').eq('user_id',uid)`. It returns `{id, email, firstName, isAdmin: roles.some(r=>r.role==='admin')}`.
- `household` (`['household']`):
  - `households.select('id,name,default_servings').maybeSingle()` (RLS scopes it to the user's household).
  - `household_members.select('user_id,role,joined_at').order('joined_at')`.
  - `profiles.select('id,first_name').in('id', memberIds)`.
  - It returns `{household, members:[{user_id, role, joined_at, first_name || '?'}]}`.
  - Initials helper: `(name ?? '?').trim().slice(0,2).toUpperCase() || '?'`.
- `household-settings` (meal-plan-*.js): `households.select('id,default_servings').maybeSingle()` returns `{id, default_servings ?? 4}`. Update: `households.update({default_servings:n}).eq('id', id)`.
- Realtime helper (household-*.js, `useRealtimeInvalidate(table, queryKey)`): it opens `supabase.channel(`${table}-${random}`)`, listens to `.on('postgres_changes', {event:'*', schema:'public', table}, …)`, and invalidates the queryKey after a 250 ms debounce. It removes the channel on unmount. (Other screens use it; admin.ingredients uses it on `ingredients`.)

Screen layout, top to bottom (each section is `rounded-2xl bg-card p-5`):
1. h1 `Profil`.
2. Card: `Connecté en tant que <email>`. Input placeholder/aria `Prénom`, saved on blur or Enter. It saves only if the trimmed value is non-empty and changed: `profiles.update({first_name}).eq('id', me.id)`. Toasts are `Prénom enregistré` / `Impossible d'enregistrer`, and it invalidates `me` and `household`. Helper text: `Affiché sur les recettes que tu partages : « Ajoutée par <prénom|…> ».`
3. Link card `/mes-recettes`: tile with book-open icon, `Mon livre de cuisine`, `Celles que tu as ajoutées, avec leurs notes.`
4. Link card `/histoire`: heart icon, `L'histoire de Tata Suzanne`, `Mais qui se cache derrière la Popote ?`
5. **Ma famille** section (users icon), h2 `Ma famille`:
   - Text: `<household.name> — le menu et la liste de courses sont partagés entre tous les membres.`
   - Pending invitations for me (`rpc('my_invitations')`, key `['my-invitations']`): a card with a primary border reading `<b>inviter</b> t'invite à rejoindre « household_name »`, plus an AcceptButton labelled `Rejoindre` that calls `rpc('accept_invitation', {_code})`. AcceptButton opens an AlertDialog: `Rejoindre ce foyer ?` / `Tu quitteras ton foyer actuel : son menu et sa liste de courses ne te seront plus visibles.` with buttons `Annuler` / `Rejoindre`.
   - Members list: initials avatar (rounded-full bg-primary), first name + ` (moi)` for the current user, role label `Propriétaire` (owner) or `Membre`. An owner sees a remove button (aria `Retirer <name>`, user-minus icon) on other members, which calls `rpc('remove_household_member', {_user_id})`.
   - RPC errors are toasted with the raw `error.message`. On success everything is invalidated.
   - `Inviter un membre`: an email input (placeholder `email@exemple.fr`) and a secondary button `Inviter` (mail icon). There is also an outline button `Copier un lien d'invitation` (copy icon). Both insert `household_invitations {household_id, email: email ? email.trim().toLowerCase() : null}.select('code').single()`, then copy `${origin}/invitation/${code}` to the clipboard.
     - Toasts: `Invitation créée pour <email>. Lien copié : envoyez-le-lui.` / `Lien d'invitation copié`; on error `Invitation impossible`.
     - Note: `Valable 7 jours. La personne invitée par email verra aussi l'invitation dans son Profil.` (inferred: `expires_at` defaults to now()+7 days in the DB).
   - Active invitations list (`['household-invitations']`: `household_invitations.select('id,code,email,expires_at').gt('expires_at', nowISO).order('created_at',{ascending:false})`). Each row shows the code in monospace, the email or `lien`, a copy button (toast `Lien copié`), and a delete button (aria `Annuler l'invitation`) that runs `household_invitations.delete().eq('id', id)`.
   - When there is more than one member: AlertDialog trigger `Quitter le foyer` (destructive ghost). The dialog says `Quitter « <name> » ?` / `Tu retrouveras un foyer personnel vide. Le menu et la liste partagés restent aux autres membres.` with buttons `Annuler` / `Quitter`, which calls `rpc('leave_household')`.
6. **Personnes par défaut** card: `Réglage du foyer, utilisé quand on ajoute une recette au menu.` Minus/Plus icon buttons (aria `Moins` / `Plus`) around the number. The range is 1..50, the update is optimistic, and on error the toast is `Impossible d'enregistrer`.
7. **Mon magasin** (store icon tile): `Glisse les rayons dans l'ordre de ton supermarché, le panier suivra.`
   - Ghost button `Par défaut` (rotate-ccw icon) runs `household_category_orders.delete().neq('category_id','')`, invalidates, and toasts `Ordre par défaut rétabli`.
   - A @dnd-kit sortable list of categories from the categories query (ingredients-*.js export `t`/`ca`; `.categories` carries `{id,name,color,icon}`). The pointer sensor activates at 5 px distance and the touch sensor after 150 ms delay with 6 px tolerance; the keyboard sensor is also enabled.
   - Each row is a grip icon, a colored square (`style.background = cat.color`) with the category icon, and the name.
   - On drop it upserts `household_category_orders` rows `[{category_id, sort_order:index}]` with `onConflict:'household_id,category_id'` (inferred: household_id is filled by a DB default or trigger). On error the toast is `Impossible d'enregistrer l'ordre`.
8. Admins only: link card `/admin/ingredients` (shield-check icon) `Ingrédients à vérifier` / `Valider ce que l'IA a rangé, fusionner les doublons.`
9. **Mes données** (border-y section, font-display h2 `Mes données`):
   - Outline button `Exporter mes recettes (JSON)` (download icon). It fetches `recipes.select('*,recipe_ingredients(*),recipe_steps(*)').eq('created_by', uid)`, strips `user_id, created_by, source_image_urls, photo_url, photo_thumb_url`, and downloads `mes-recettes-popote.json` containing `{application:'La Popote de Tata Suzanne', exported_at: ISO, recipes}` (pretty-printed with 2 spaces). Toasts: `Tes recettes sont exportées` / `Export impossible`.
   - Destructive ghost `Supprimer mon compte` opens a Dialog:
     - title `Supprimer mon compte`, description `Cette action est définitive. Tes données personnelles et tes photos privées seront effacées.`
     - fieldset legend `Tes recettes partagées` with radios `Supprimer aussi mes recettes` (default, keepRecipes=false) / `Les laisser à la communauté de façon anonyme` (keepRecipes=true)
     - label `Écris SUPPRIMER pour confirmer` + input
     - destructive button `Supprimer définitivement` (`Suppression…` while running), enabled only when the input is exactly `SUPPRIMER`; outline `Annuler`
     - Action: cancelQueries, then server fn `deleteAccount({data:{confirmation:'SUPPRIMER', keepRecipes}})`, then queryClient.clear(), signOut, navigate `/auth` replace. Toast `Ton compte a été supprimé`; on error `La suppression n’a pas pu être terminée. Réessaie.`
     - The client-side zod schema is `z.object({confirmation: z.literal('SUPPRIMER'), keepRecipes: z.boolean()})`.
10. Link `Conditions générales d'utilisation` (/conditions). Admins also get the link `Signalements de contenus` (/admin/signalements).
11. **Questions fréquentes** (circle-question-mark icon), a single collapsible Accordion with these Q/A pairs:
    - `Comment ajouter une recette depuis une photo ou un livre ?` → `Dans Recettes, touche « Ajouter », choisis la catégorie puis prends une ou plusieurs photos. Les informations sont lues automatiquement ; vérifie les champs surlignés avant d'enregistrer. Tu peux aussi tout saisir à la main.`
    - `Comment fonctionne le partage avec ma famille ?` → `Dans Profil, section « Ma famille », copie un lien d'invitation et envoie-le. Une fois la personne inscrite, le menu et la liste de courses sont partagés et se mettent à jour en direct.`
    - `Comment générer la liste de courses à partir du menu ?` → `Remplis le menu de la semaine, puis ouvre Courses et touche « Générer depuis le menu ». Les quantités sont adaptées au nombre de personnes et les ingrédients identiques sont regroupés.`
    - `Puis-je changer les portions sur le menu sans modifier la recette ?` → `Oui. Le nombre de personnes réglé sur une case du menu ne concerne que ce repas ; la recette d'origine reste inchangée.`
    - `Comment noter ou commenter une recette ?` → `Ouvre la fiche d'une recette : touche les étoiles pour donner une note de 1 à 5, et écris ton avis dans la section Commentaires en bas de page.`
12. **Nous contacter** (mail icon): `Une question, une idée ou un souci ? Touche le bouton ci-dessous : ton application de messagerie s'ouvre avec l'e-mail déjà rédigé.` The button `Envoyer un e-mail` is a link to `mailto:gregoiremart1@gmail.com?subject=%5BMa%20Cuisine%5D%20Question%20ou%20retour`.
13. Secondary button `Se déconnecter` (log-out icon).

## C.8 Invitation `/invitation/$code`

- Query `['invitation', code]` runs `rpc('get_invitation', {_code: code})` and takes the first row or null. Row fields used: `household_name, inviter, already_member, expired`.
- The card is `mx-auto max-w-md rounded-3xl bg-card p-8 text-center` with a tile icon (h-20).
- States:
  - `Chargement…`
  - no row: `Cette invitation n'existe pas.`
  - already a member: `Tu fais déjà partie de « X ».`
  - expired: `Cette invitation a expiré. Demandes-en une nouvelle à <inviter>.`
  - otherwise: `<b>inviter</b> t'invite à rejoindre <b>« X »</b> pour partager le menu et la liste de courses.` plus AcceptButton `Rejoindre le foyer` (same confirmation dialog as in C.7).
- Accepting calls `rpc('accept_invitation', {_code})`. On error it toasts `error.message`. On success it invalidates everything, toasts `Bienvenue dans « X » !`, and navigates `/menu`.
- Ghost button `Retour au profil` (/profil).
- Because the route sits under `_authenticated`, a signed-out visitor goes to `/auth` and loses the code: there is no redirect-back parameter.

## C.9 Admin

- Role check is client-side through `me.isAdmin` (`user_roles.role === 'admin'`). No `has_role` RPC is called from the client (inferred: RLS policies use one server-side).
- `/admin/ingredients`:
  - Data: the ingredients query (ingredients-*.js export `a`) plus categories. It subscribes to realtime on table `ingredients`.
  - Back link `Profil` (arrow-left), h1 `Ingrédients à vérifier`, text `Ajoutés par l'IA ou à la main, pas encore validés (<n>).` where n counts rows with `!verified`.
  - Empty state (dashed border): `Tout est rangé, rien à vérifier !`
  - Each row has a name input (aria `Nom`), a category select (aria `Rayon`), and a status label: `en attente de l'IA` (pending_ai), `rangé par l'IA` (source==='ia', sparkles icon) or `ajouté à la main`.
  - Button `Valider` runs `ingredients.update({display_name, name: display_name.toLowerCase(), category_id, verified:true, pending_ai:false}).eq('id')`. Toasts `<name> validé` / `Validation impossible`.
  - `Aussi : <aliases joined ', '>` is shown when there are aliases.
  - Merge input placeholder `Fusionner avec… (doublon)` shows the top 5 fuzzy matches (search function from ingredients-*.js) as secondary buttons. Clicking one calls `rpc('merge_ingredients', {_from: id, _into: target.id})`. Toasts `Fusionné dans <name>` / `Fusion impossible`.
  - Non-admins see `Cette page est réservée aux admins.`
- `/admin/signalements`:
  - Query `['content-reports']` (enabled only for admins): `content_reports.select('*').order('created_at',{ascending:false})`. Fields used: `id, recipe_id, recipe_title, reason, details, created_at, resolved`.
  - Link `Profil`, h1 `Signalements`. Error text `Impossible de charger les signalements.`; empty state `Aucun signalement.`
  - Each item shows a flag icon, the recipe_title, `<reason> · <date fr-CH>`, and details (pre-wrap). Buttons `Voir la recette` (/recettes/$id) and `Marquer comme traité` (`Traité` once resolved, then disabled), which runs `content_reports.update({resolved:true}).eq('id')`. Toasts `Signalement traité` / `Impossible de mettre à jour`.
  - States: loading `Chargement…`; non-admin `Cette page est réservée aux admins.`
  - The report zod schema in terms-*.js is `{recipe_id: uuid, reason: enum['droits d'auteur','contenu inapproprié','erreur'], details: string.trim().max(2000)}`.

## C.10 Legal and content pages

- **terms-*.js constants**:
  - `TERMS_VERSION = '1.0'`
  - Rights-certification text used by the recipe form, with schema `z.literal(true)`: `Je certifie avoir le droit de partager ce contenu : la photo du plat est la mienne et le texte est rédigé avec mes propres mots ou appartient au domaine familial. J'indique la source si la recette est inspirée d'un livre, d'un magazine ou d'un site.`
  - Personal-note schema: `z.string().trim().max(1000).nullable()`.
- **/conditions** renders an embedded Markdown string, split on `\n### `.
  - Header: logo + short wordmark linking `/`. h1 `Conditions générales d'utilisation`, script line `La Popote de Tata Suzanne`, then `Version 1.0, en vigueur depuis le 4 novembre 2026`.
  - Nav `Sommaire` (ordered list of anchors `#article-N`). Each article is a section with an h2; bullet lists become `ul.list-disc`.
  - Every `[[CONTACT]]` placeholder becomes a link `Envoyer un e-mail` to `mailto:gregoiremart1@gmail.com?subject=%5BMa%20Cuisine%5D%20Question%20sur%20les%20CGU`.
  - Footer link `Retour au Profil`.
  - Article headings (exact): `1. Objet`, `2. Un usage strictement privé et non commercial`, `3. Compte et foyer`, `4. Les contenus que tu partages`, `5. Droits d'auteur : ce qu'il faut savoir`, `6. Signalement et retrait`, `7. Notes et commentaires`, `8. Cuisine, santé et allergies`, `9. Intelligence artificielle`, `10. Données personnelles`, `11. Disponibilité`, `12. Responsabilité`, `13. Modification des conditions`, `14. Droit applicable et for`, `15. Contact`.
  - Summary of the content:
    - The app is private and non-commercial, published by "La famille Martin, Lausanne, Suisse", as a pilot for family and friends.
    - Users must be 16+ or have a parent's consent. Household members share the menu and shopping list.
    - Users keep ownership of their content and grant a free non-exclusive license limited to the Popote.
    - Uploaded book or magazine page photos are used only for AI analysis and stay private.
    - Reports go through the « Signaler » button.
    - AI comes from a third-party provider, used to extract recipes and categorize ingredients.
    - Data processing follows the Swiss LPD. On account deletion, recipes are deleted unless the user chooses to leave them anonymously.
    - The service is provided as-is. Swiss law applies, with courts of the canton of Vaud.
    - Closing line: `Merci de partager ta tablée avec nous. Et bon appétit !`
- **/histoire**:
  - Header: logo + short wordmark, linking to `/recettes` when there is a session (`auth.getSession`), otherwise `/`.
  - h1 `L'histoire de ` + script `Tata Suzanne`.
  - Sections (tile icon + font-display h2):
    - `Tata Suzanne, c'est qui ?` (chef-hat), with post-it notes `Gratin de Mamie, p. 42 !` (mustard, -4°) and `Penser au beurre…` (coral, +5°)
    - `Le joyeux bazar` (smartphone), with a sage post-it `Au final ? Beaucoup d'énergie dépensée, et une sacrée charge mentale.` (clipboard-list icon)
    - `L'idée de la Popote` (cooking-pot)
    - `Pas besoin d'être un chef` (sparkles)
    - `Et demain ?` (newspaper)
  - Closing: `Et bon appétit !` + script `Tata Suzanne`.
  - Buttons: `Découvrir les recettes` (/recettes) and, only when signed out, outline `Rejoindre la tablée` (/auth). Footer CGU link.
  - Post-it style: `rounded-sm p-4 shadow-[0_8px_18px_-10px_oklch(0.3_0.05_40/0.45)]`.
- **/video**: a single `<video controls playsInline preload="metadata">` whose src is the Lovable asset `/__l5e/assets-v1/ddc48e49-3997-4547-a935-78bb998dfaa0/tata-suzanne-teaser.mp4` (9,376,608 bytes, video/mp4). Below it: script link `Mais qui est Tata Suzanne ?` (/histoire) and lg button `Essayer gratuitement` (/auth).

## C.11 Server-function transport (TanStack Start client)

- Each server fn is created as `createServerFn({method:'POST'}).middleware([authMw]).handler(createClientRpc('<sha256 id>'))`. The client stub (`gi`) sets `url = '/_serverFn/' + id`.
- Known ids:
  - `27301031363e284184ead21ac910c33ebfbe9159435c975f26319c6a65fade88`: deleteAccount (profil)
  - `0aa253b0d610fbe837a4ec9ad4f338f5ca37a75a618338b85c58fafac32aa5ad`: photo→recipe
  - `e4fe9f8721a74c14b325e4d6c34321d86241473f65a7b0dc9296ad046a4caf33`: text→recipes
  - `a2b48a88e43523c600947bf17d04c7894e27a6228277bbd569d884062a5ba4ef`: URL→recipes
  - `789c6d723c3130a983ec35993e4ec23d1f75a48585adf43e2a4f87361d9321b5`: AI ingredient categorization, called with `{ids:[…]}` (ingredients-*.js)
- **Global function middleware** (index chunk, registered through `createStart(() => ({functionMiddleware:[authMw], requestMiddleware:[…]}))`):
  ```js
  createMiddleware({type:'function'}).client(async ({next}) => {
    const {data} = await supabase.auth.getSession();
    const token = data.session?.access_token;
    return next({ headers: token ? { Authorization: `Bearer ${token}` } : {} });
  })
  ```
  The per-fn middleware `r`/`_` (`createMiddleware({type:'function'})` with no client part) is the server-side `requireSupabaseAuth` (inferred). Its server code was stripped from the client bundle.
- **Request** (`ui`):
  - Headers: `x-tsr-serverFn: true`, `accept: application/x-tss-framed, application/x-ndjson, application/json`, plus middleware headers (Authorization).
  - POST: the body is `JSON.stringify(serovalToJSON({data, context?}))`, with `content-type: application/json`. For FormData input the body is the FormData itself, with the serialized context added under `__TSS_CONTEXT`.
  - GET (not used by this app): the payload goes into the query string as `?payload=<encoded JSON>`.
  - The client call shape is `fn({data:{…}})`, wrapped with `useServerFn` (which follows `redirect` throws).
- **Response** (`mi`):
  - Header `x-tss-raw: true` means the raw Response is returned.
  - If `x-tss-serialized` is present, the body is either `application/x-tss-framed; v=1` (streamed frames) or `application/json` deserialized with seroval plugins.
  - Plain JSON is returned as-is unless it encodes an error, in which case it is thrown.
  - A non-ok response throws `Error(await res.text())`.
- `/api/broadcast` appears only inside supabase realtime-js (client-*.js, byte ~27760). It is the library's HTTP broadcast endpoint, derived from the realtime URL. The app never calls it directly.
- Supabase client: URL `https://pwlrzjmqagwlvncfvfel.supabase.co`, publishable key `sb_publishable_9ixRQH2cuoWUzbKG3mj4YQ_T_J0zG_T`. The custom fetch sets `apikey` and drops an `Authorization: Bearer <publishable key>` header. Auth uses `persistSession:true, autoRefreshToken:true`, with localStorage storage (or the Lovable preview postMessage bridge when iframed).

## C.12 Design tokens (styles-6qR1Ax3b.css, Tailwind v4.3.4, shadcn-style)

Light `:root`:

| Token | Value |
|---|---|
| --radius | 1rem |
| --background | oklch(96.5% .018 85) |
| --foreground | oklch(28% .03 45) |
| --card / --popover | oklch(99% .01 85) |
| --card-foreground / --popover-foreground | oklch(28% .03 45) |
| --primary | oklch(32% .07 260) (navy; theme-color #1D3256) |
| --primary-foreground | oklch(99% .01 80) |
| --secondary | oklch(92% .025 85) |
| --secondary-foreground | oklch(30% .03 45) |
| --muted | oklch(93% .02 85) |
| --muted-foreground | oklch(50% .03 55) |
| --accent | oklch(90% .04 140) (sage tint) |
| --accent-foreground | oklch(32% .05 140) |
| --destructive | oklch(58% .21 25) |
| --destructive-foreground | oklch(99% 0 0) |
| --border / --input | oklch(88% .025 80) |
| --ring | oklch(32% .07 260) |
| --sage | oklch(66% .06 140) |
| --sage-foreground | oklch(99% .01 85) |
| --tile | oklch(36% .07 260) |
| --tile-strong | oklch(26% .06 262) |
| --tile-foreground | oklch(99% .01 80) |
| --warning | oklch(80% .14 80) |
| --warning-foreground | oklch(25% .03 60) |
| --nav | oklch(94.5% .024 85) |
| --shadow-tile | 0 10px 24px -12px color-mix(in oklab, var(--tile-strong) 70%, transparent) (fallback `0 10px 24px -12px var(--tile-strong)`) |
| --gradient-tile | linear-gradient(150deg, var(--tile), var(--tile-strong)) |
| --chart-1..5 | oklch(64.6% .222 41.116), oklch(60% .118 184.704), oklch(39.8% .07 227.392), oklch(82.8% .189 84.429), oklch(76.9% .188 70.08) |
| --sidebar-* | aliases of card/foreground/primary/accent/border/ring |

There is no `.dark` theme: only one unused `dark:border-destructive` utility exists. Instead, a scoped dark palette **`.cook-dark`** (used by cooking mode, inferred) sets:
- --background oklch(20% .03 262); --foreground oklch(95% .015 85)
- --card/--popover oklch(26% .035 262); their foregrounds oklch(95% .015 85)
- --primary oklch(85% .09 90) (warm yellow); --primary-foreground oklch(22% .03 262)
- --secondary oklch(31% .035 262); --muted oklch(30% .03 262); --muted-foreground oklch(75% .02 85)
- --accent oklch(35% .05 140); --accent-foreground oklch(95% .015 85)
- --border/--input oklch(34% .03 262); --ring oklch(85% .09 90)
- --tile oklch(45% .07 140); --tile-strong oklch(38% .06 140) (sage tiles); --gradient-tile is redefined to match

Fonts:
- `--font-sans` = "Nunito", ui-sans-serif, system-ui, sans-serif (body)
- `--font-display` = "Fraunces", Georgia, serif. Applied to `h1,h2,h3` in base with `font-optical-sizing:auto; letter-spacing:-.01em`, and available as `.font-display`.
- `.font-script` = "Dancing Script", cursive (brand wordmark and accents)
- Weights loaded: Fraunces 600/800, Dancing Script 600/700, Nunito 400/600/700.

Radii (derived from --radius = 1rem):
- `rounded-sm` = radius−4px
- `rounded-md` = radius−2px
- `rounded-lg` = radius
- `rounded-xl` = radius+4px
- `rounded-2xl` = radius+8px
- `rounded-3xl` = radius+12px

Custom utilities:
- `.tile { background-image: var(--gradient-tile); color: var(--tile-foreground); box-shadow: var(--shadow-tile) }`
- `.bg-nav` = var(--nav)
- `.bg-postit-sage` oklch(90% .05 140); `.bg-postit-coral` oklch(88% .07 35); `.bg-postit-mustard` oklch(91% .1 90)

Base styles: `body { background: var(--background); color: var(--foreground); font-family: var(--font-sans) }`; `* { border-color: var(--border) }`.

Shadows: Tailwind defaults (sm/md/lg/xl/2xl), plus --shadow-tile and the post-it shadow.

Keyframes / animations:
- `heart-pop` (scale 1 → 1.35 at 40% → 1), used as `.animate-heart-pop` (.35s ease-out)
- `caret-blink` (`.animate-caret-blink` 1.25s infinite)
- `accordion-down` / `accordion-up` (Radix height var)
- tw-animate `enter` / `exit`
- `spin`, `pulse`


---

# Part N: `/recettes/nouvelle`, the new-recipe wizard and AI import (recettes.nouvelle-*.js)

Authenticated route. The screen is a state machine driven by `step` ∈ `category` → `source` → (`photos` | `text` | `url`) → `review`. The selected category defaults to `plat`.

## N.1 Step `category`
- H1 `Quel type de recette ?`
- Grid (`grid-cols-3 gap-x-3 gap-y-5 sm:grid-cols-5`) of category tiles (AppShell's CategoryTile with `icon`, `label`, `tone`), one for each of the 18 recipe categories (see A.6). Clicking a tile sets the category and moves to `source`.

## N.2 Step `source`
- Back chip: `<icon> <Label> · changer` (text-primary), which returns to `category`.
- H1 `D'où vient ta recette ?`
- Three `.tile` buttons (1 column on mobile, 3 on sm), each a label plus a hint:
  - `Photo`: `Livre, carnet, magazine` (camera icon) → `photos`
  - `Coller un texte`: `WhatsApp, e-mail, SMS…` (clipboard-paste icon) → `text`
  - `Lien web`: `Site de recettes, blog` (link-2 icon) → `url`
- Ghost button `Saisir à la main` (keyboard icon). It opens `review` with `newRecipe(category)` and the AI highlight turned off.

## N.3 Step `text` (paste a text)
- `← Autre source` (back to `source`). H1 `Coller un texte`.
- Intro: `Une recette reçue par message ou par e-mail ? Copie-la puis colle-la ici, Tata Suzanne fait le tri.`
- Outline button `Coller depuis le presse-papiers`:
  - It reads `navigator.clipboard.readText()`. If that succeeds, the text fills the textarea (cut to 15 000 chars) and is parsed immediately.
  - If it fails, the textarea is revealed and a toast says `Colle ta recette dans la zone ci-dessous`.
- Textarea (autoFocus, 10 rows, maxLength 15000, placeholder `Colle ta recette ici`, aria-label `Texte de la recette`), with a counter `n / 15 000` (fr-FR number format). Before it is revealed, a link `Coller à la main` shows instead.
- Primary button: `Lire la recette` (sparkles icon). While working it reads `Lecture de la recette…` with a spinner. It is disabled when the text is empty or a parse is running.
- Logic (`parseText(text)`):
  1. If the text is essentially a single URL (one http(s) URL plus at most 40 other non-punctuation chars) and the URL passes the safety check, the screen switches to `url` and imports that URL instead.
  2. Otherwise it calls server fn **text→recipes** `e4fe9f87…af33` with `{data:{text: text.slice(0,15000)}}` and gets back `{recipes, error, logId}`.
  3. `logId` is stored. With 0 recipes: toast.error(`error ?? 'Lecture impossible'`), then `review` with a blank recipe. With more than 1: the "Plusieurs recettes trouvées" picker dialog. With exactly 1: it is merged into the blank and the screen goes to `review`.
  4. On exception: toast.error `Lecture impossible, réessaie dans un instant.`

## N.4 Step `url` (web link)
- `← Autre source`. H1 `Lien web`. Intro: `Colle le lien de la recette (site de cuisine, blog…).`
- A form with an `<Input type=url inputMode=url placeholder="https://…" aria-label="Lien de la recette">` and an outline button `Coller`, which reads the clipboard and extracts a URL from it. If there is nothing usable, a toast says `Colle le lien dans le champ`.
- Primary button `Importer la recette` (sparkles). While busy it reads `Lecture de la page…`.
- **URL safety check `isSafeUrl`** (client side, SSRF guard):
  - The scheme must be http or https, and the URL must have no userinfo.
  - Rejected hosts: `localhost`, `*.localhost`, `*.local`, `*.internal`, and hostnames with no dot.
  - Rejected IPv4 ranges: 10/8, 127/8, 0/8, ≥224, 169.254/16, 172.16–31, 192.168/16, 100.64–127 (CGNAT).
  - Rejected IPv6: `::1`, `::`, fc/fd, fe8–feb, and `::ffff:`.
  - Invalid URL message: `Ce lien ne semble pas valide. Vérifie qu'il commence par https://`
- **Duplicate check:** `supabase.from('recipes').select('id,title').eq('source_url', url).limit(1)`. If a row is found, a dialog opens:
  - Title `Déjà dans la Popote !`, body `Cette recette a déjà été importée : « <title> ».`
  - Buttons `Importer quand même` (ghost; re-runs with force) and `Ouvrir la recette` (goes to `/recettes/$id`).
- Then it calls server fn **URL→recipes** `a2b48a88…a4ef` with `{data:{url}}` and gets back `{recipes, error, logId, image?, site?}`.
  - If `recipes` is empty, the inline error box shows `error`.
  - If `image` is present, the client `fetch`es it to a blob, makes full and thumb versions, and uploads both to `recipe-photos/<uid>/plats/`. If that fails, it is only logged (`photo du plat`).
  - The base recipe gets `source_url`, `source_inspiration = site || null`, `photo_url`, and `photo_thumb_url`.
  - With more than 1 recipe the picker opens; with exactly 1 the screen goes to `review`.
- Error box (`rounded-2xl bg-card p-4 text-sm`): the message, plus an outline button `Coller un texte` that switches to `text` with the textarea revealed.
- Exception message: `Tata Suzanne n'arrive pas à lire cette page. Copie le texte de la recette et utilise « Coller un texte ».`

## N.5 Step `photos` (AI photo → recipe)
- `← Autre source`. H1 `Photographie la recette`. Intro: `Une ou plusieurs pages (jusqu'à 6). Les ingrédients et étapes seront lus automatiquement.`
- Two square tiles:
  - `Appareil photo`: a hidden `<input type=file accept="image/*" capture="environment">`.
  - `Galerie`: `<input type=file accept="image/jpeg,image/png,image/heic,image/heif,.heic,.heif" multiple>`.
  - Files are appended and the total is capped at **6**. Each gets an object-URL preview.
- Thumbnail grid (3 columns, aspect 3/4), each with a number badge and an `×` button (aria `Retirer`).
- A Progress bar (h-1.5) shows while busy and under 100 %.
- Primary button: `Analyser la photo` / `Analyser les N photos`. While busy it reads `Préparation des photos…` (progress below 100) and then `Lecture de la recette…`.
- Ghost button `Saisir à la main`.
- **Pipeline (`analyze`):**
  1. Each page photo goes through HEIC→JPEG if needed, then is compressed for the AI (1600 px, q 0.85, ≤0.5 MB, webp).
     - Progress: each file is worth `100/n`, and compression fills 60 % of that share.
  2. In parallel: (a) convert each compressed file to a data URL, and (b) upload each to `recipe-photos/<uid>/sources/<uuid>.webp`, keeping the paths as `source_image_urls`. Stale uploads from an earlier attempt are removed.
  3. Call server fn **photo→recipe** `0aa253b0…a5ad` with `{data:{images: dataURL[]}}` and get back `{recipe, dishPhotos, error, logId}`.
  4. Dish photo detections come from `recipe.dish_photos` when it is non-empty, otherwise from `dishPhotos`.
     - The main one is `is_main`, or else the one with the highest `confidence`.
     - The source page `pages[image_index]` is cropped to `box_2d` (0–1000 normalized `[ymin,xmin,ymax,xmax]`, 2 % padding).
     - The crop becomes full and thumb versions, which are uploaded to `plats/`. A failure is logged (`recadrage auto de la photo du plat`).
  5. If there is an error or no recipe, toast.error(`error ?? 'Analyse impossible'`) and go to `review` with a blank recipe (keeping the photo and sources).
     Otherwise the AI fields are mapped in:
     - title, servings, prep and cook minutes, seasons and tags
     - categories = unique([chosen, ...suggested_categories])
     - ingredients mapped to `{raw_text, name, quantity, unit, shopping_category, optional:false}`
     - steps (string[])
  6. `aiHighlight = true`; RecipeForm receives `pages` (the original files) and `detections`, so the user can re-crop or choose another dish photo.
  7. Any exception: toast.error `Échec de l'envoi des photos`.

## N.6 AI output JSON schema (sent as strict structured output, inferred; verbatim from the bundle)
```
{ type:object, additionalProperties:false,
  required:[title,servings,prep_time_min,cook_time_min,ingredients,steps,suggested_seasons,suggested_tags,suggested_categories,dish_photos],
  properties:{
    title: string|null, servings: integer|null, prep_time_min: integer|null, cook_time_min: integer|null,
    ingredients: [{ raw_text:string, name:string, quantity:number|null, unit:string|null,
       shopping_category: enum["fruits & légumes","crèmerie","boucherie","poissonnerie","épicerie","surgelés","boulangerie","boissons","autre"] }],
    steps: string[],
    suggested_seasons: enum["printemps","été","automne","hiver","toute l'année"][],
    suggested_tags: string[],
    suggested_categories: enum["apéro","entrée","soupe","salade","plat","pâtes","quiche / tarte","curry","légumes","sauce","dessert","gâteau","goûter","gaufre / tartines","pain / brioche","petit-déjeuner","boisson","repas de fête"][],
    dish_photos: [{ image_index:integer, box_2d:number[4], is_main:boolean, confidence:number }] } }
```
The text and URL functions return `recipes: AiRecipe[]`, so they can find several recipes in one input (inferred: same item schema).

## N.7 Multi-recipe picker dialog
- Title `Plusieurs recettes trouvées`, description `Laquelle veux-tu importer ?`
- One full-width outline button per recipe, labelled with its title or `Recette N`. Choosing one merges it into the base recipe and goes to `review`.

## N.8 Step `review`
- H1: `Vérifie la recette` if the content came from the AI or already has a title, otherwise `Nouvelle recette`.
- `RecipeForm` (see A.16) is passed:
  - `initial`
  - `highlightEmpty = aiHighlight || !!title`
  - `submitLabel 'Enregistrer la recette'`
  - `pages` and `detections` (photo flow only)
  - `initialPendingUploads = [full, thumb]` of the auto photo
- **On submit:**
  1. Near-duplicate title check against **all** recipes: `select('id,title')`, keeping those where `titleSimilarity(a,b) >= 0.75` (first 3).
     - If any match, a dialog opens: `Cette recette existe peut-être déjà`, with the description `La base commune contient une recette au titre très proche :`.
     - It lists links that open in a new tab, plus `Revenir à ma recette` (ghost) and `Enregistrer quand même`. A failure there shows toast.error `Enregistrement impossible`.
  2. `saveRecipe(values)` returns the new id.
  3. If there is a logId, run `ai_usage_logs.update({recipe_id:id}).eq('id',logId)` without waiting for it.
  4. Invalidate `['recipes']`, show toast.success `Recette enregistrée`, and navigate to `/recettes/$id`.
- On unmount, uploaded `sources` and `plats` paths that were never committed are removed from storage.


---

# Part A: Recipes (detail, cook mode, edit, form, photos, recipe logic)

Sources: `recettes._id.index-BsIdHppB.js`, `recettes._id.cuisiner-DGVQnWgE.js`, `recettes._id.modifier-DWWFckAb.js`, `RecipeForm-C0uLv9-N.js`, `recipe-data-CXYhg0wf.js`, `recipes-D9xc4VyU.js`, `RecipePhoto-D3FS0jZ6.js`, `Rating-C5z5D5WP.js`, `FavoriteButton-Bg8Lehzt.js`, `AddToMenuDialog-C5lzIQge.js`, `AcceptButton-CCl_ukBP.js`, `video-CO0eg8Cu.js`, `terms-Dmm63a7x.js`, `meal-plan-aaED2QKP.js`, `household-DNKBWHf4.js`, the app-specific tail of `ingredients-Ba4c7mUu.js`, and the route table in `index-ysFXFbDw.js`.

`schemas-B9pilnN2.js` contains only the Zod v4 library (it exports `string`, `object`, `literal`, `enum`, `boolean`). The app's Zod schemas are defined in `terms-*.js` and `profil-*.js` (see A.9).

---

## A.1 Route definitions (from index-*.js)

All three routes sit under the `/_authenticated` layout.

| Route | `<title>` / og:title | meta description | loader |
|---|---|---|---|
| `/_authenticated/recettes/$id/` | `Recette — La Popote de Tata Suzanne` | `Ingrédients, étapes et portions ajustables.` | `queryClient.ensureQueryData(recipeQuery(id))` |
| `/_authenticated/recettes/$id/cuisiner` | `Mode cuisine — La Popote de Tata Suzanne` | `La recette pas à pas, en grand, avec minuteurs.` | same |
| `/_authenticated/recettes/$id/modifier` | `Modifier la recette — La Popote de Tata Suzanne` | `Modifiez les ingrédients, étapes et informations de la recette.` | same |

Each route's head also sets `og:type=website` and `twitter:card=summary`.

The cook route has `validateSearch`: `p = Number(search.p)`. If `p` is an integer with 0 < p < 100, the search becomes `{p}`; otherwise it becomes `{}`. `p` is the number of servings. The meal-plan menu links to it with `to:'/recettes/$id/cuisiner', params:{id: entry.recipe_id}, search:{p: entry.servings}`, and the link has aria-label/title `Cuisiner`.

### Recipe query (shared): `recipeQuery(id)`

- queryKey `['recipe', id]`
- Query: `supabase.from('recipes').select('*, recipe_ingredients(*), recipe_steps(*), author:profiles!recipes_created_by_fkey(first_name)').eq('id', id).single()`
- Client-side, `recipe_ingredients` and `recipe_steps` are each sorted by `position` ascending.

### Recipes list query (shared, used for the list and the filters): `recipesQuery`

- queryKey `['recipes']`
- Query: `from('recipes').select('id,title,categories,seasons,prep_time_min,cook_time_min,photo_url,photo_thumb_url,tags,servings,created_at,created_by,rating_avg,rating_count,recipe_ingredients(name)').order('created_at',{ascending:false})`
- Each row is mapped to `{...row, ingredientNames: recipe_ingredients.map(i => i.name)}`.

### Current user query: `meQuery`

From `household-*.js`, queryKey `['me']`:

- `auth.getUser()`
- `profiles.select('first_name').eq('id', uid).maybeSingle()`
- `user_roles.select('role').eq('user_id', uid)`

It returns `{id, email, firstName, isAdmin: roles.some(r => r.role==='admin')}`.

**Edit/delete permission** (`canEdit`): `me && (recipe.created_by === me.id || me.isAdmin)`.

---

## A.2 `/recettes/$id`: recipe detail

**Purpose:** show one recipe with adjustable servings, rating, favorites, add to menu, cook mode, comments and reporting.

### Layout and elements, in order

1. **Back link** to `/recettes`: arrow-left icon followed by ` Recettes`.
2. **Two-column grid** on md screens: `[minmax(0,2fr)_minmax(0,3fr)]`.
   - **Photo:** `RecipePhoto path={photo_url} category={categories[0] ?? 'plat'}`, with classes `aspect-square w-full rounded-3xl` and a 24×24 fallback icon. The detail page uses the full image (`photo_url`), not the thumbnail.
   - **Title** `h1` (`text-3xl font-extrabold md:text-4xl`).
   - **FavoriteButton** (heart, top right).
   - **Favorite counter:** when the count is above 0, a popover trigger shows `❤️ {count}` (aria-label `Voir qui l'a en favori`). The popover opens on hover or click and shows `Ajoutée aux favoris par **{names}**`. Names are joined as `a, b et c`. While names load, it shows `Chargement…`.
   - `Ajoutée par {author.first_name || 'un membre'}`.
   - **Rating summary** (`Rating` `t` component):
     - When `count` > 0: a filled star, then `{avg formatted}`, then `· {count} avis`.
     - When `count` is 0: `Pas encore notée`.
     - The average is formatted as `Number(avg).toFixed(1).replace('.', ',')`, e.g. `4,5`.
   - **Badges:**
     - category labels (default variant)
     - seasons (secondary variant, capitalized)
     - when `prep_time_min != null`: clock icon + `{prep} min` (outline)
     - when `cook_time_min != null`: flame icon + `{cook} min` (outline)
   - **Actions:**
     - Primary large button, a Link to `/recettes/$id/cuisiner` (no `p`): chef-hat icon + ` 👩‍🍳 Cuisiner`.
     - `AddToMenuDialog` (A.7), whose default trigger is `Ajouter au menu`.
     - When canEdit:
       - secondary `Modifier` (pencil icon) linking to `/recettes/$id/modifier`
       - ghost destructive `Supprimer` (trash icon), which opens an AlertDialog:
         - title `Supprimer cette recette ?`
         - description `Cette action est définitive.`
         - buttons `Annuler` / `Supprimer`
   - When `is_private`: `🔒 Recette privée : visible seulement par le foyer de l'auteur`.
   - **"Ma note" card:** label `Ma note`, then the interactive star input (A.8).
3. **Ingredients card** (`rounded-3xl bg-card p-5`).
   - `h2` `Ingrédients`.
   - Servings stepper pill with − / users-icon + N / + buttons (aria `Moins` / `Plus`). The minimum is 1, there is no maximum, and the initial value is `recipe.servings ?? 4`.
   - List with `divide-y`. Each line shows the scaled quantity in a `w-24 font-semibold text-primary` column, then the name. Optional ingredients get the suffix ` (facultatif)` in muted text. Formatting is described in A.10.
4. **"Préparation" section:** `h2` `Préparation`, then an ordered list. Each step has a round numbered `tile` badge and `instruction` text.
5. **Notes** (only if `notes` is set): card with `h3` `Notes` and the text.
6. **Source** (only if `source_inspiration || source_url`):
   - `h3` `Source / inspiration`
   - `source_inspiration` (pre-wrap)
   - When `source_url` matches `^https?://`, a link `Voir la recette d'origine ↗` with `target=_blank rel="noopener noreferrer nofollow"`.
7. **Report dialog** (`fo`). See A.12.
8. **Comments** in `<div id="commentaires" class="scroll-mt-20">`. Cook mode deep-links here with `hash:'commentaires'`. See A.11.

### Actions and their data effects

- **Rate:** optimistic `setQueryData(['my-rating', id], stars)`, then `setRating(id, stars)`. On failure the toast is `Note non enregistrée`. Afterwards it invalidates `['my-rating', id]`, `['recipe', id]`, `['recipes']` and `['comments', id]` (comments show each author's stars).
- **Delete:** `deleteRecipe(id)` (A.5). On failure the toast is `Suppression impossible`. On success it invalidates `['recipes']`, shows the toast `Recette supprimée` and navigates to `/recettes`.

---

## A.3 `/recettes/$id/cuisiner`: cook mode

This is a full-screen overlay (`fixed inset-0 z-[60] overflow-y-auto`). Dark mode is on by default: the class `cook-dark` is applied while `dark` is true, and the initial state is `true`.

### Header (sticky)

- Close button, an X (aria `Quitter le mode cuisine`), which navigates to `/recettes/$id`.
- The title (clamped to one line).
- The text `🔆 Écran maintenu allumé`, shown when the wake lock is active. It is inline on sm+ screens and under the header on mobile.
- A theme toggle: a sun icon when dark (aria `Thème clair`), a moon icon when light (aria `Thème sombre`).

### Layout

The grid has `max-w-6xl`. Ingredients and steps stack on narrow screens, and on landscape md or lg screens they sit side by side as `[2fr 3fr]`, with ingredients on the left. On mobile, the steps come first (order-1).

### Ingredients panel

- `h2` `Ingrédients`.
- Large servings stepper: aria `Moins de personnes` / `Plus de personnes`. The minimum is 1, and the initial value is `search.p ?? recipe.servings ?? 4`.
- Each ingredient is a toggle button (`aria-pressed`). Tapping strikes it through (`line-through opacity-40`). The text is `text-xl`, with the quantity column `w-28 font-bold text-primary`.
- When at least one ingredient is struck: an outline button with the rotate-ccw icon and ` Tout décocher`, which clears all strikes.

### Steps panel

- **Empty state:** `Cette recette n'a pas encore d'étapes.`
- **Progress:** `Étape {n} / {total}`, a progress bar (`role=progressbar`), and a toggle button with the list-ordered icon. The toggle reads `Toutes les étapes` in step-by-step view and `Pas à pas` in all-steps view.

**Step-by-step view**

- The current step is shown in `text-2xl md:text-3xl`.
- Detected durations become inline timer chips (A.3.1).
- A **"Pour cette étape"** card lists the ingredients matched in the step text (A.3.2) as pills: bold scaled quantity, then the name.
- Navigation: `Précédente` (chevron-left, disabled on step 0) and `Suivante`, which becomes `Terminer` on the last step.
- **Swipe navigation:** a horizontal touch with |dx| > 60 px and |dx| > 1.5·|dy| moves forward (left swipe) or back (right swipe). Swipes are disabled in all-steps view and on the finish screen.

**All-steps view**

- Every step is a card. The current one has `ring-2 ring-primary`.
- Tapping the `Étape N` label jumps to that step and returns to step-by-step view.
- A large `Terminer` button sits at the bottom.

**Finish screen** (`ye`), shown when moving past the last step:

- `🍽️`, then `Bon appétit !` in `font-script text-5xl text-primary`.
- A card with `Ça t'a plu ?` and the star input. Saving shows the toast `Merci pour ta note !`, or `Note non enregistrée` on error. It then invalidates `['recipes']` and the recipe query.
- When canEdit: a link to `/recettes/$id/modifier` with the camera icon and ` Ajouter une photo de mon plat`.
- A link to `/recettes/$id#commentaires` with the message-circle icon and ` Laisser un commentaire`.
- Both links clear the saved cooking session first.
- Ghost button `Revoir la dernière étape` (back to the steps) and primary `Terminer`, which clears the session and navigates to `/recettes/$id`.

### A.3.1 Timer detection in step text (`P`)

The parser is a regex with flags `giu`. Number words map as follows: `un/une`=1, `deux`=2 … `dix`=10, `quinze`=15, `vingt`=20, `trente`=30, `quarante`=40, `cinquante`=50. Numerals with `,` or `.` decimals are also accepted.

Units: `heures?|h|minutes?|mins?|mn|secondes?|secs?|s`. A unit starting with `h` is 3600 s. One starting with `mi` or `mn` is 60 s. Anything else is 1 s.

Patterns, tried in order:

1. `une demi-heure` (or `une demi heure`) → 1800 s.
2. `2 h 30` / `2h30min` → h·3600 + m·60.
3. `{n} heure(s) et demie` → n·3600 + 1800.
4. A range, `(entre )?A (à|a|-|–|et) B unit` → **two chips**, A and B.
5. `{n} {unit}` → a single value. The bare unit `s` is skipped when n is a word, not a numeral.

Other rules:

- A match must not be followed by a letter or digit, and must not be preceded by one.
- Values must satisfy 0 < v ≤ 172800 (48 h).
- Each chip is a `tile` pill with the timer icon and the formatted duration (`F`):
  - `1 h 05`, `1 h`, `5 min 30`, `5 min`, `45 s`.

### Timers

- Tapping a chip creates a timer `{id, label, total, endsAt: now+total·1000, remaining:null, done:false}`.
- It shows the toast `⏱ {label} : {duration}`. If `Notification.permission === "default"`, it requests permission.
- **Timer label** (`me`): a verb regex gives the step type:
  - `/cui(re|sson|ssez|s|t)|mijot|bouill|frire|frit|rôti|dorer/i` → `Cuisson`
  - `/four|enfourn/i` → `Four`
  - `/repos|reposer|réserv|lever|pousser|frigo|réfrigér|refroidir/i` → `Repos`
  - `/mariner|marinade/i` → `Marinade`
  - no match → `Étape {n}`

  When the type is not `Repos` and an ingredient matches the step, the first matched ingredient is appended with a partitive:
  - vowel or h start → `de l'`
  - name ending in s or x → `des `
  - otherwise → `du `

  Example: `Cuisson du poulet`.
- **Timer tray:** fixed to the bottom of the screen and scrolls horizontally. Each card is `min-w-56` and shows the label and the remaining time:
  - format `h:mm:ss` or `m:ss`, in tabular-nums, `text-3xl`
  - when done, `Terminé !` on a pulsing `bg-destructive` card
- Running timer controls:
  - pause/resume (aria `Pause` / `Reprendre`). Pausing stores `remaining` and nulls `endsAt`; resuming does the reverse.
  - `+1 min` adds 60 s.
  - X (aria `Annuler le minuteur`).
- Done timer control: `Arrêter`.
- A 500 ms tick drives the countdown. When a timer expires:
  - it is marked done
  - a system notification fires once: `new Notification('⏰ Minuteur terminé', {body: label})`, when permission is granted
  - the alarm plays: `navigator.vibrate([300,150,300])` plus three beeps (880/660/880 Hz, sine oscillator, gain 0.25 decaying over 0.22 s, spaced 0.25 s). It repeats every 1.5 s while any timer is done.

### Screen wake lock

1. Try `navigator.wakeLock.request('screen')`.
2. If that fails, fall back to lazily importing `src-CCkhSk8H.js` (a NoSleep.js-style library, inferred) and calling `.enable()`.
3. Re-acquire on `visibilitychange`, and once on the first `pointerdown`.

### Session persistence

- localStorage key: `popote-cuisine-{recipeId}`.
- Value: `{step, struck:[indices], servings, timers, savedAt}`. It is written on every change once the initial restore check is done.
- A saved session expires after 12 h (`432e5` ms).
- On open, if a saved session has `step > 0`, any struck items or any timers, a dialog appears:
  - title `Reprendre où tu en étais ?`
  - description `Tu t'étais arrêté·e à l'étape {n}.`
  - `Recommencer` clears the session.
  - `Reprendre` restores the step (clamped), the struck items, the timers, and the servings (servings only if no `p` search param was given).
  - Dismissing the dialog also clears the session.

### A.3.2 Ingredient-to-step matching (`B`)

1. Remove hyphenated imperative compounds from the step: `(é|e)pluche|presse|coupe|vide|casse|r(a|â)pe|ouvre` + `-word`.
2. Normalize the text: lowercase, strip diacritics (NFD), `œ`→`oe`, and replace non-alphanumerics with spaces.
3. Tokenize, then strip the plural suffix `(aux|eaux|s|x)$`.
4. For each ingredient name:
   - take the part before the first ` de|du|des|d|a|au|aux|ou|pour `
   - tokenize it and keep tokens longer than 2 characters
   - drop stop words: `de du des la le les d l a au et en frais fraiche`
   - drop adjectives: `petit petite gros grosse grand grande bio fraichement rape sec seche blanc rouge noir`
   - singularize the remaining tokens
5. An ingredient matches if any of its tokens is in the step token set.

---

## A.4 `/recettes/$id/modifier`: edit

- `h1` `Modifier`.
- The form is `RecipeForm` with `highlightEmpty=false` and `submitLabel='Enregistrer les modifications'`.
- `initial` is built from the recipe:
  - `title`
  - `categories: normalizeCategories(categories)`
  - `seasons, servings, prep_time_min, cook_time_min, difficulty, source_inspiration, source_url, is_private, tags, notes, photo_url, photo_thumb_url, source_image_urls`
  - `ingredients: recipe_ingredients.map({raw_text,name,quantity,unit,shopping_category,optional})`
  - `steps: recipe_steps.map(s => s.instruction)`
- On submit:
  1. `saveRecipe(values, id)`
  2. invalidate `['recipes']` and `['recipe', id]`
  3. toast `Recette mise à jour`
  4. navigate to `/recettes/$id`
- The route itself does not check ownership; only the detail page hides the button. Row Level Security (RLS) is presumably enforced server-side (inferred).

---

## A.5 Recipe persistence (`recipe-data-*.js`)

### `saveRecipe(values, id?)` (`C`)

1. `rightsCertifiedSchema.parse(values.rights_certified)`, which is `z.literal(true)`.
2. `sourceInspirationSchema.parse(values.source_inspiration ?? null)`, which is `z.string().trim().max(1000).nullable()`.
3. Add `photo_url`, `photo_thumb_url` and every `source_image_urls` path to the module-level `committedPaths` Set. Paths in this set are protected from orphan cleanup.
4. When editing, fetch the old photo: `recipes.select('photo_url,photo_thumb_url').eq('id', id).single()`.
5. Build the row:
   ```
   { title: title.trim(), categories, seasons, servings, prep_time_min, cook_time_min, difficulty, tags, notes,
     source_inspiration, ...(source_url===undefined ? {} : {source_url}), is_private: is_private ?? false,
     rights_certified_at: new Date().toISOString(), photo_url, photo_thumb_url, source_image_urls }
   ```
6. **Update:**
   - `recipes.update(row).eq('id', id)`
   - `recipe_ingredients.delete().eq('recipe_id', id)`
   - `recipe_steps.delete().eq('recipe_id', id)`
   - if `old.photo_url` changed, remove the old full and thumb objects from storage (errors are ignored)

   **Create:** `recipes.insert(row).select('id').single()`.
7. **Ingredients:**
   - keep only entries where `name.trim()` is non-empty
   - map each to `{...ing, name: trimmed, recipe_id, position: index}`
   - `recipe_ingredients.insert(rows).select('ingredient_id')`
   - pass the returned `ingredient_id`s to `enrichPendingIngredients(ids)` (A.13)

   The DB fills `ingredient_id` itself, probably with a trigger that matches or creates a row in `ingredients` (inferred).
8. **Steps:** keep non-empty steps after trimming, map each to `{instruction, recipe_id, position: index}`, then `recipe_steps.insert(rows)`.
9. Return the recipe id.

Notes:

- `created_by` is not sent; it is presumably defaulted to `auth.uid()` in the DB (inferred).
- `rating_avg` and `rating_count` are stored columns on `recipes`, presumably kept up to date by a trigger on `recipe_ratings` (inferred).

### `deleteRecipe(id)` (`v`)

1. `recipes.select('photo_url,photo_thumb_url,source_image_urls').eq('id', id).single()`
2. `recipes.delete().eq('id', id)`
3. Remove `[photo_url, photo_thumb_url, ...source_image_urls]` from storage. Errors are swallowed.

### `recipes` columns referenced in Part A

`id, title, categories (text[]), seasons (text[]), servings (int), prep_time_min, cook_time_min, difficulty (nullable, no UI), tags (text[]), notes, source_inspiration, source_url, is_private (bool), rights_certified_at (timestamptz), photo_url, photo_thumb_url, source_image_urls (text[]), created_at, created_by (FK → profiles via recipes_created_by_fkey), rating_avg, rating_count`

### `recipe_ingredients` columns

`id, recipe_id, position, raw_text, name, quantity (numeric|null), unit (text|null), shopping_category (text), optional (bool), ingredient_id (FK ingredients, set server-side)`

### `recipe_steps` columns

`id, recipe_id, position, instruction`

### Blank recipe (`newRecipe(category='plat')`)

```
{title:'', categories:[category], seasons:[], servings:4, prep_time_min:null, cook_time_min:null, difficulty:null,
 tags:[], notes:null, ingredients:[], steps:[], photo_url:null, photo_thumb_url:null, source_image_urls:[]}
```

---

## A.6 Enums (`recipes-*.js`)

### Recipe categories

The stored value is in lowercase with accents. Icons are lucide unless noted. Every `tone` is the empty string `''`; colour comes from the `.tile` CSS class.

| value | label | icon |
|---|---|---|
| `apéro` | Apéro | wine |
| `entrée` | Entrée | utensils-crossed |
| `soupe` | Soupe | soup |
| `salade` | Salade | salad |
| `plat` | Plat | cooking-pot |
| `pâtes` | Pâtes | wheat |
| `quiche / tarte` | Quiche / Tarte | chart-pie |
| `curry` | Curry | flame |
| `légumes` | Légumes | carrot |
| `sauce` | Sauce | custom inline SVG (a sauce boat or ladle shape, inferred) |
| `dessert` | Dessert | cake-slice |
| `gâteau` | Gâteau | cake |
| `goûter` | Goûter | cookie |
| `gaufre / tartines` | Gaufre / Tartines | sandwich |
| `pain / brioche` | Pain & brioche | croissant |
| `petit-déjeuner` | Petit-déjeuner | coffee |
| `boisson` | Boisson | cup-soda |
| `repas de fête` | Repas de fête | sparkles |

- `getCategory(v)` returns the matching entry, falling back to entry index 4 (`plat`).
- `normalizeCategories(arr)` maps the legacy value `accompagnement` to `légumes`, removes duplicates, drops unknown values, and returns them in the canonical order above.

### Other enums

- **Seasons:** `printemps, été, automne, hiver, toute l'année`.
- **Units** (dropdown): `g, kg, ml, cl, l, c. à soupe, c. à café, pièce, pincée, botte, sachet, tranche, gousse, verre`. A unit that is not in the list (for example from AI import) is appended to the options for that row.
- **Shopping categories** (`shopping_category`, "Rayon"): `fruits & légumes, crèmerie, boucherie, poissonnerie, épicerie, surgelés, boulangerie, boissons, autre`.
- **Meal types** (`meal-plan-*.js`): `{value:'déjeuner', label:'Déjeuner'}`, `{value:'dîner', label:'Dîner'}`.

### Category tile component (`AppShell` export `n`)

- A button with `aria-pressed`.
- The tile is `tile {tone} aspect-square rounded-2xl`.
- When active: `ring-4 ring-foreground/80`.
- On mobile it shows the icon (`h-12` md, `h-8` sm, strokeWidth 1.4) with the label below. On md+ screens it shows the label text inside the tile instead of the icon.

---

## A.7 Add to menu dialog (`AddToMenuDialog`)

- Default trigger: a secondary button with the calendar-plus icon and ` Ajouter au menu`.
- Dialog title: `Ajouter au menu`.
- **`Jour`:** a horizontal list of 14 days starting today. Each chip shows the short weekday (`fr-FR`, capitalized) and the day number. The selected chip is `bg-primary`.
- **`Repas`:** two buttons, `Déjeuner` and `Dîner`. The default is `dîner`.
- **`Personnes`:** a stepper (aria `Moins` / `Plus`), minimum 1. On open it is set to `household.default_servings`. The `household-settings` query is `households.select('id,default_servings').maybeSingle()` and falls back to 4.
- Submit button: `Ajouter`. On submit:
  1. `meal_plan_entries.select('id',{count:'exact',head:true}).eq('date', d).eq('meal_type', m)`. The resulting count becomes `position`.
  2. `meal_plan_entries.insert({date, meal_type, recipe_id, servings, position})`.
  3. Invalidate `['meal-plan', weekStart(date)]`. `weekStart` is the Monday of that week, as `YYYY-MM-DD` in local time.
  4. Toast `Ajouté au {meal_type} du {date formatted fr-FR weekday long, day numeric, month short}`.
- Error toast: `Impossible d'ajouter au menu`.

`date` is a local `YYYY-MM-DD` string. Neither `added_by` nor the household id is sent; both are presumably DB defaults (inferred).

---

## A.8 Ratings (`recipe_ratings`)

- **My rating:** queryKey `['my-rating', id]`. `recipe_ratings.select('stars').eq('recipe_id', id).eq('user_id', uid).maybeSingle()` returns `stars | null`.
- **Set a rating:** `recipe_ratings.upsert({recipe_id, user_id, stars}, {onConflict:'recipe_id,user_id'})`.
- **Clear a rating:** `recipe_ratings.delete().eq('recipe_id', id).eq('user_id', uid)`.
- **Star input:**
  - 5 buttons with aria `1 étoile` / `N étoiles`, `h-7 w-7`, filled `fill-primary` up to the hovered or current value.
  - When a value is set: a `Retirer ma note` link (X icon) that clears it.
- Stars range from 1 to 5 as integers. A unique index on (recipe_id, user_id) is implied by `onConflict`.

---

## A.9 Zod schemas (app-level)

These live in `terms-*.js`.

- `rightsCertified = z.literal(true)`
- `sourceInspiration = z.string().trim().max(1000).nullable()`
- `reportSchema = z.object({ recipe_id: z.string().uuid(), reason: z.enum(["droits d'auteur","contenu inapproprié","erreur"]), details: z.string().trim().max(2000) })`
- `termsSchema = z.object({ terms_version: z.literal('1.0'), terms_accepted: z.literal(true) })`
- `profil-*.js` also has `z.object({confirmation: z.literal('SUPPRIMER'), keepRecipes: z.boolean()})` for account deletion. That belongs to another part.

**Rights certification text** (checkbox label in RecipeForm, exact):

> Je certifie avoir le droit de partager ce contenu : la photo du plat est la mienne et le texte est rédigé avec mes propres mots ou appartient au domaine familial. J'indique la source si la recette est inspirée d'un livre, d'un magazine ou d'un site.

**Terms acceptance:**

- Query `['terms-acceptance']`: `terms_acceptances.select('accepted_at').eq('user_id', uid).eq('terms_version','1.0').maybeSingle()`, which returns a boolean.
- Insert: `{user_id, terms_version:'1.0'}`. Error code `23505` (duplicate) is ignored.

---

## A.10 Portion scaling and quantity formatting (`recipes-*.js`)

### Scaling

```
scale(q, baseServings, targetServings) = q == null ? null : (!baseServings || baseServings <= 0) ? q : q * target / base
```

The detail page uses `baseServings = recipe.servings`. Cook mode uses the same base.

### Number formatting (`fmtQty`)

1. `null` → `''`.
2. If q < 10 and the fractional part is within ±0.03 of 0.25, 0.333, 0.5, 0.667 or 0.75, the fraction is shown as `¼ ⅓ ½ ⅔ ¾`, with the integer part prepended when non-zero. Example: `1½`.
3. Otherwise, if q ≥ 100 it is rounded to an integer. Below 100 it is rounded to one decimal.
4. A decimal comma is used. Example: `2,5`.

### Line formatting (`formatIngredient(q, unit, name)`)

It returns `{qty, name}`.

- `qty`: the formatted number, plus ` {unit}` when the unit is set and is not `pièce`.
- **Unit plural:** when q ≥ 2, these units take a plural: `pincée→pincées, botte→bottes, sachet→sachets, tranche→tranches, gousse→gousses, verre→verres`. Metric units and spoon units do not change.
- **Name plural:** applies only when the unit is empty or `pièce` and q ≥ 2 (`pluralizeName`):
  - Names that never change: `maïs riz lait beurre sucre sel poivre farine huile eau crème levure persil basilic thym ciboulette chocolat miel vinaigre jus parmesan gruyère fromage râpé`.
  - The name is split at the first ` de|du|des|d'|d’|à|au|aux|en|pour|sans|avec …`. Only the head is pluralized, word by word. Words that are not first and are `bio|extra|maison|nature|bis`, or that contain digits, stay as they are.
  - French word plural rules:
    - irregular: `œil/oeil→yeux`, `ail→aulx`
    - words ending in `s/x/z` are unchanged
    - `eau/au/eu` → `+x`, except `landau, sarrau, bleu, pneu`, which take `+s`
    - `al` → `aux`, except `bal carnaval festival chacal régal`, which take `+s`
    - `chou bijou caillou genou hibou joujou pou` take `+x`
    - everything else takes `+s`
- Unit conversion is not applied on the recipe pages. The shopping list uses aggregation and normalization from `ingredients-*.js` (A.13).

---

## A.11 Comments (`recipe_comments`)

**Query** `['comments', recipeId]`, run in parallel:

- `recipe_comments.select('id,user_id,parent_id,content,edited,deleted,created_at').eq('recipe_id', id).order('created_at')`
- `recipe_ratings.select('user_id,stars').eq('recipe_id', id)`

It then loads names with `profiles.select('id,first_name').in('id', distinctUserIds)`. The result is `{comments, names: Map, stars: Map}`.

**Realtime:** `supabase.channel('comments-{id}-{rand}').on('postgres_changes', {event:'*', schema:'public', table:'recipe_comments', filter:'recipe_id=eq.{id}'}, refetch).subscribe()`. The channel is removed on unmount.

There is also a generic `useRealtimeInvalidate(table, queryKey)` helper in `household-*.js`. It opens a channel named `{table}-{rand}` on all changes to that table and invalidates the given key after a 250 ms debounce. It is used by other screens.

### UI

- **Header:** `Commentaires ({n})`, where n counts non-deleted comments. A sort select (aria `Trier les commentaires`) offers `Plus récents` (value `new`, the default; it reverses the order of top-level comments) and `Plus anciens` (`old`).
- **New comment form:**
  - textarea with placeholder `Partage ton avis, une astuce, une variante…`, maxLength 2000
  - counter `{len}/2000`
  - button `Publier`, disabled when the text is empty
  - Insert: `{recipe_id, content: trimmed, parent_id}`. `user_id` is presumably a DB default (inferred).
  - Error toast: `Publication impossible`.
- **Threads:**
  - Comments with `parent_id = null` are top-level. Replies are indented underneath (`ml-8 border-l pl-4`) in chronological order, one level deep. Only top-level comments get a reply button.
  - Pagination shows 10 top-level comments, and `Voir plus` adds 10 more.
  - A deleted comment is hidden unless it has replies, in which case it shows `Commentaire supprimé` (italic).
- **Empty state:** `Aucun commentaire pour l'instant. Soyez le premier !`
- **Comment item:**
  - avatar with the name's initials (first two characters, uppercased)
  - name, or `Membre`
  - badge `Auteur de la recette` when the commenter is the recipe author
  - the commenter's star rating (aria `{n} étoiles`)
  - relative time from `Intl.RelativeTimeFormat('fr', {numeric:'auto'})` (year, month, week, day, hour, minute), or `à l'instant` under a minute
  - ` · modifié` when edited
- **Own comments** have an `Options du commentaire` (⋯) dropdown with `Modifier` and `Supprimer`.
  - **Edit:** `update({content}).eq('id')` with buttons `Annuler` / `Enregistrer`. Error toast: `Modification impossible`. The `edited` flag is not sent by the client; it is presumably set by a trigger (inferred).
  - **Delete:** an AlertDialog titled `Supprimer ce commentaire ?` with `Cette action est définitive.` and `Annuler` / `Supprimer`.
    - If the comment has non-deleted replies: soft delete with `update({deleted:true, content:''})`.
    - Otherwise: hard delete with `delete().eq('id')`.
    - Error toast: `Suppression impossible`.
- **Reply:**
  - a `Répondre` link opens a textarea with placeholder `Répondre à {name}…`
  - buttons `Annuler` / `Répondre`
  - inserts with `parent_id`

---

## A.12 Content report (`content_reports`)

- Trigger: a ghost small button with the flag icon and `Signaler un contenu`.
- The dialog title is also `Signaler un contenu`; the description is the recipe title.
- `Motif` select:
  - `Droits d'auteur` (`droits d'auteur`, the default)
  - `Contenu inapproprié` (`contenu inapproprié`)
  - `Erreur` (`erreur`)
- `Précisions (facultatif)`: a textarea, maxLength 2000.
- Submit: `Envoyer le signalement`.
  1. Validate with `reportSchema`.
  2. `content_reports.insert({recipe_id, reason, details, user_id, recipe_title})`.
  3. Success toast `Signalement envoyé`, then close and clear the form. Error toast `Signalement impossible`.

---

## A.13 Favorites (`recipe_favorites`)

- **All my favorites:** queryKey `['favorites']`. `recipe_favorites.select('recipe_id,created_at')` returns a `Map(recipe_id → created_at)`. There is no user filter, so RLS presumably limits it to the current user (inferred).
- **Count:** `rpc('recipe_favorite_count', {_recipe_id})`, key `['favorite-count', id]`.
- **Names:** `rpc('recipe_favorite_names', {_recipe_id})`, which returns string[]. Key `['favorite-names', id]`. It is only fetched when the count is above 0.
- **Toggle:**
  1. Optimistic Map update and count ±1 (never below 0).
  2. Remove: `recipe_favorites.delete().eq('recipe_id', id)`. Add: `recipe_favorites.insert({recipe_id})`.
  3. On error: roll back and toast `Oups, ça n'a pas marché`. On success: toast `Retirée de tes favoris` or `Ajoutée à tes favoris ❤️`.
  4. Invalidate the count and names queries.
- **Button:**
  - round `bg-card/90`, `h-10` (md) or `h-8` (sm)
  - aria `Retirer des favoris` / `Ajouter aux favoris`, with `aria-pressed`
  - heart filled `fill-primary` when favorited
  - a pop animation (`animate-heart-pop`) on click
  - it stops event propagation so it works inside cards

### Ingredient helpers in `ingredients-*.js` (app code)

These are used across features.

**Name normalization (`norm`)**

- Lowercase and strip diacritics (NFD), with `œ→oe` and `æ→ae`.
- Words longer than 3 characters ending in `aux` become `…al`.
- Otherwise, words longer than 2 characters drop a final `s` or `x`.

**Tokenizing (`tokens`)**

`tokens(s) = s.split(/[^\p{L}\p{N}]+/u).filter(Boolean).map(norm)`. `key(s) = tokens(s).join(' ')`.

**Fuzzy match (`matches(query, text)`)**

Every query token must be a prefix of some text token. An empty query matches everything.

**Current season (`currentSeason(date)`)**

Months 3–5 are `printemps`, 6–8 `été`, 9–11 `automne`, and the rest `hiver`.

**Total time:** `totalTime = (prep ?? 0) + (cook ?? 0)`.

**Recipe filter (`filterRecipes(list, f, favMap)`)**

A recipe passes only if all of these hold:

- categories: some category in common
- favorites only: the recipe is in favMap
- seasons: the recipe has `toute l'année`, or a season in common
- maxTime: the total time is non-zero and ≤ maxTime
- tags: the recipe has all selected tags
- include: every included ingredient query matches some ingredient name
- exclude: no excluded ingredient query matches
- minRating: `rating_avg` ≥ minRating
- mineOf: `created_by === mineOf`
- q: matches against `title` plus the ingredient names

**Title similarity (`similarity(a, b)`)**

- Tokens are filtered to those longer than 2 characters or containing a digit, then joined.
- If either side is empty → 0. If they are equal → 1.
- Otherwise the result is a Sørensen–Dice coefficient on character bigrams: `2·common / (len1-1 + len2-1)`.
- **Duplicate threshold:** `0.75`. On save, the new-recipe flow loads `recipes.select('id,title')` and shows up to three recipes with similarity ≥ 0.75. That dialog is in `recettes.nouvelle`:
  - title `Cette recette existe peut-être déjà`
  - description `La base commune contient une recette au titre très proche :`
  - buttons `Revenir à ma recette` / `Enregistrer quand même`

**Shopping aggregation (`aggregate(items, defaultServings=4)`)**

Summary only; Part B covers it in full.

- Skip water, salt and pepper variants. Skip `huile*` and `vinaigre*`.
- Group key: `ingredient_id ?? key(name)` plus `|family`, or `|-` when there is no quantity.
- Units are converted to a family and a factor:
  - mass: g = 1, kg = 1000
  - volume: ml = 1, cl = 10, l = 1000
  - any other unit is its own family with factor 1
  - an empty unit is `pièce`
- Each quantity is multiplied by `meal_servings / recipe_servings`. The recipe servings fall back to defaultServings, then to 4.
- Rounding back to a display unit:
  - mass: ≥ 1000 → kg rounded to 0.1. ≥ 250 → g rounded to 50. ≥ 50 → g rounded to 10. Otherwise g rounded to 5, minimum 5.
  - volume: ≥ 1000 → l rounded to 0.1. ≥ 100 → cl, rounded to 5. Otherwise ml rounded to 5, minimum 5.
  - spoons: rounded up to the nearest ½, minimum ½.
  - countable units (`pièce gousse tranche sachet botte verre pincée`): `ceil(x - 0.05)`, minimum 1.
  - other units: rounded up to 0.1.
- `diffAuto(existing, computed)` updates or inserts rows by `item_key` and deletes stale rows where `source='auto'`.

**Quick-add parser (`parseQuick(text, units)`)**

It parses `^(\d+([.,]\d+)?)\s*(.*)$`, matches the longest unit followed by a space, then strips a leading `de ` or `d'`.

**Category icon map**

Ingredient category `icon` names map to lucide icons: `apple, carrot, leaf, croissant, milk, cheese, egg, beef, drumstick, ham, fish, wheat, archive, package, candy, soup, flame, snowflake, cup-soda, spray-can, shopping-basket`. The fallback is shopping-basket.

**Category query**

Queries `ingredient_categories.select('id,name,color,icon,sort_order')`, `household_category_orders.select('category_id,sort_order')` and `household_ingredient_overrides.select('ingredient_id,category_id')`.

Categories are sorted by the household's order first; categories the household has not ordered get `1000 + sort_order`.

Effective category: `overrides.get(ing.id) ?? ing.category_id`, or `'autre'` when there is no ingredient.

**Ingredient list query** `['ingredients']`

`ingredients.select('id,name,display_name,plural_name,aliases,category_id,seasons,verified,source,pending_ai').order('name')`

**Autocomplete (`searchIngredients(list, q, usageMap, limit=8)`)**

- Candidates are `name`, `display_name` and the aliases, after `key()`.
- Score 3 for an exact match, 2 for a prefix match, 1 for a word-prefix match.
- Sorted by usage count descending, then score, then `localeCompare('fr')`.

**Set category:** `rpc('set_ingredient_category', {_ingredient, _category})`.

**`enrichPendingIngredients(ids)` (`pa`)**

1. Remove duplicates from the ids.
2. `ingredients.select('id').in('id', ids).eq('pending_ai', true)`.
3. If any rows come back, call **server fn `789c6d723c3130a983ec35993e4ec23d1f75a48585adf43e2a4f87361d9321b5`** with `{data:{ids:[...]}}`. Errors are only logged to the console.

What the server function does is inferred: AI classification and normalization of newly created ingredients (category, display and plural names). Supporting evidence: the admin screen shows `en attente de l'IA` and `rangé par l'IA`, and `source='ia'`.

---

## A.14 Server function call shape

This applies to every `createServerFn` here.

- **Declaration:** `createServerFn({method:'POST'}).middleware([fnMiddleware]).handler(clientStub(id))`. The client stub is `fetch('/_serverFn/' + id)`.
- **Middleware:** the global function middleware (in `index-*.js`) adds `Authorization: Bearer {supabase session access_token}` when a session exists. The per-function middleware is a client-side stub of a server-only auth middleware (inferred).
- **Request:**
  - `POST /_serverFn/{sha256-like id}`
  - headers `x-tsr-serverFn: true`, `accept: application/x-tss-framed, application/x-ndjson, application/json`, `content-type: application/json`
  - body: `JSON.stringify(seroval.toJSON({data: <input>}))`, the TanStack serialization format
- **Response:** decoded through `x-tss-serialized`, either framed or JSON. The header `x-tss-raw: true` returns a raw Response.

Server functions referenced by the files in this part:

| id | where | input | output (as used) |
|---|---|---|---|
| `789c6d72…21b5` | ingredients-*.js (`pa`) | `{ids: string[]}` | ignored |
| `0aa253b0…a5ad` | recettes.nouvelle (photo import) | `{images: dataURL[]}` | `{recipe: AiRecipe \| null, dishPhotos?: Detection[], error?: string, logId}` |
| `e4fe9f87…af33` | recettes.nouvelle (text import) | `{text: string (≤15000)}` | `{recipes: AiRecipe[], error?, logId}` |
| `a2b48a88…a4ef` | recettes.nouvelle (URL import) | `{url: string}` | `{recipes: AiRecipe[], error?, logId, image?: url, site?: string}` |

`logId` refers to a row in `ai_usage_logs`. After a successful save, the client runs `ai_usage_logs.update({recipe_id: newId}).eq('id', logId)` without waiting for it. The AI JSON schema (AiRecipe and the `dish_photos` detection format) is defined in `recettes.nouvelle`.

---

## A.15 Storage and photo pipeline

- **Bucket:** `recipe-photos`. It is private: every image is shown through a signed URL.
- **Object path:** `{auth.uid}/{folder}/{crypto.randomUUID()}.{ext}`.
  - `folder` is `plats` (dish photos, full and thumb) or `sources` (photos of recipe pages used for AI import).
  - `ext` is `webp` for image/webp, `jpg` for image/jpeg, otherwise the subtype of the MIME type, or `img`.
  - Upload: `storage.from('recipe-photos').upload(path, file, {contentType: file.type})`.
  - If no user is signed in, it throws `Non connecté`.
- **DB storage:** `photo_url`, `photo_thumb_url` and `source_image_urls[]` store **storage paths, not URLs**.
- **Display (`RecipePhoto`):**
  - `useSignedUrl(path)`: queryKey `['signed-url', path]`, `storage.from('recipe-photos').createSignedUrl(path, 3600)` (valid 1 h), staleTime 3,000,000 ms (50 min).
  - The image is `<img loading=lazy decoding=async class="object-cover">` and fades from opacity 0 to 100 on load (300 ms).
  - Without a path, it shows the category icon on a `.tile` background. While a signed URL is loading, it shows an empty tile.
  - Lists use `photo_thumb_url ?? photo_url`. The detail page uses `photo_url`.
- **HEIC conversion (`heic2any`):**
  - Triggered when the type matches `/heic|heif/i` or the name ends in `.heic` / `.heif`.
  - The library is lazy-imported and called as `heic2any({blob, toType:'image/jpeg', quality:0.92})`.
  - The result is a File named with `.jpg`.
- **Compression (`browser-image-compression`, lazy-imported):**
  - common options `{maxWidthOrHeight, initialQuality, maxSizeMB, fileType:'image/webp', useWebWorker:true, preserveExif:false, onProgress?}`
  - **dish photo, full:** 1600 px, quality 0.8, max 0.3 MB, webp. Progress maps to 0–70 %.
  - **dish photo, thumb:** 400 px, quality 0.75, max 0.04 MB (≈40 KB), webp. Progress maps to 70–100 %.
  - **recipe page photo for AI:** 1600 px, quality 0.85, max 0.5 MB, webp. These are uploaded to `sources/` and also converted to data URLs (FileReader) for the AI call.
- **Auto-crop of the dish photo from AI detections (`cropBox(file, box_2d, pad=0.02)`):**
  - `box_2d = [ymin, xmin, ymax, xmax]`, normalized to 0–1000.
  - The crop is padded by 2 % of the width and height on each side and clamped to the image.
  - It is drawn on a canvas and exported as JPEG at quality 0.92, named `plat.jpg`.
  - The result is compressed to full and thumb and uploaded to `plats/`.
  - The main detection is the one with `is_main`; if none has it, the detection with the highest `confidence` is used.
- **Orphan cleanup:**
  - Every upload made during a form session is tracked.
  - When RecipeForm or the new-recipe page unmounts, paths not in `committedPaths` are removed from storage. RecipeForm waits 3 s before removing, and that wait is cancelled if a new form mounts.
  - Replacing a photo inside the form removes the previous uncommitted pair right away.
  - Saving an edit with a changed photo removes the old committed full and thumb pair.

### Video (`video-*.js`, a separate route component)

- A Lovable-hosted asset: `/__l5e/assets-v1/ddc48e49-3997-4547-a935-78bb998dfaa0/tata-suzanne-teaser.mp4`, 9,376,608 bytes, `video/mp4`, filename `tata-suzanne-teaser.mp4`.
- Rendered as `<video controls playsInline preload="metadata" class="max-h-[calc(100dvh-10rem)] rounded-2xl bg-foreground shadow-xl">`.
- Below it: a link to `/histoire` reading `Mais qui est Tata Suzanne ?` (`font-script text-2xl text-primary`), and a large button linking to `/auth` reading `Essayer gratuitement`.
- Recipes have no video support.

---

## A.16 RecipeForm (shared by the new and edit screens)

**Props:** `initial`, `highlightEmpty`, `submitLabel`, `onSubmit`, `pages?: File[]` (the photographed pages), `detections?: Detection[] | null`, `initialPendingUploads?: string[]`.

**Highlighting:** when `highlightEmpty` is true, a field is outlined with `border-warning ring-1 ring-warning/60` if it is:

- an empty title
- a null servings, prep or cook value
- an empty ingredient name
- a missing quantity where `raw_text` contains a digit
- an empty step
- an empty ingredient list or an empty step list

When any of the four key checks fails (title, servings, ingredient count, step count), a warning banner appears:

> Vérifie les champs surlignés : ils sont vides ou n'ont pas pu être lus sur la photo.

### Sections, in order

**1. Dish photo**

Without detections (manual entry or edit):

- A 28×28 tile button showing the RecipePhoto thumbnail, with a camera icon (or spinner) and ` Photo du plat`.
- It opens a hidden `<input type=file accept="image/*,.heic">`.
- A progress bar shows under the tile while uploading.

With detections (photo import):

- Label `Photo du plat` and a 36×36 preview.
- When the detection confidence is below 0.6: `Est-ce bien la photo du plat ?` (warning colour).
- When there are no detections: `Aucune photo de plat n'a été repérée sur tes pages.`
- Buttons:
  - `Ajuster le cadrage` (crop icon): reopens the cropper on the source page with the detection box preselected.
  - `Choisir une autre photo` (images icon): toggles a picker.
  - `Ajouter ma propre photo` (camera icon).
- Picker:
  - `Photos repérées sur tes pages`: thumbnails of each detection crop (unpadded). If a thumbnail is not available, it shows `Page {n}`. The selected one has `ring-primary`. Tapping one crops, compresses and uploads it.
  - `Ou trace une zone à la main sur une page`: page thumbnails. Tapping one opens the cropper on that full page.

**Crop dialog** (react-easy-crop):

- title `Recadre ta photo`
- aspect ratio buttons `Carré` (1), `Paysage` (4/3), `Portrait` (3/4)
- a `Zoom` range from 1 to 3 in steps of 0.05
- `Garder telle quelle` uploads the photo uncropped. `Valider` exports the crop as a canvas JPEG at quality 0.92.

Photo-related errors:

- `Oups, cette photo n'a pas pu être lue` (HEIC conversion or read failure)
- `Oups, le recadrage a échoué`
- `Oups, la photo n'a pas pu être envoyée`

The submit button is disabled while an upload is in progress.

**2. Title:** `Titre`, with placeholder `Ex. Gratin dauphinois`.

**3. Categories:** `Catégories (une ou plusieurs)`.

- A grid of category tiles: 4 columns, 6 on sm, 11 on lg, size sm.
- Tiles toggle on and off. Removing the last selected one shows the toast `Garde au moins une catégorie`.
- The selection is kept in canonical order.

**4. Numbers:** three inputs with `inputMode=numeric`:

- `Personnes` (`servings`)
- `Préparation (min)` (`prep_time_min`)
- `Cuisson (min)` (`cook_time_min`)

Parsing: an empty field becomes `null`, otherwise `Number(value.replace(',', '.'))`.

**5. Seasons:** `Saisons`, with toggle pills for the 5 seasons (capitalized).

**6. Ingredients:** `h2` `Ingrédients` and a button `+ Ajouter`. A new row is `{raw_text:null, name:'', quantity:null, unit:null, shopping_category:'autre', optional:false}`.

- Empty state: `Aucun ingrédient.` (dashed box).
- Each row:
  - `« {raw_text} »` in italic, when `raw_text` is present
  - quantity input `Qté` (decimal)
  - unit select with `—` meaning null, plus the unit list
  - name input `Ingrédient`
  - `Rayon` select with the shopping categories
  - checkbox ` Facultatif`
  - buttons `Monter` / `Descendre` (swap with the neighbour) and `Supprimer`

**7. Steps:** `h2` `Étapes` and `+ Ajouter`, which adds an empty string.

- Empty state: `Aucune étape.`
- Each step: a number badge, a textarea, and `Monter` / `Descendre` / `Supprimer`.

**8. Tags and notes**

- `Tags (séparés par des virgules)`: free text, split on `,`, trimmed, empties dropped.
- `Notes`: a textarea. An empty value becomes null.

**9. Source:** `Source / inspiration (facultatif)`, maxLength 1000, placeholder `Inspiré de Saveurs, déc. 2025`.

**10. Privacy checkbox**

- `🔒 Recette privée`
- `Visible seulement par toi et les membres de ton foyer.`

**11. Rights checkbox:** the certification text from A.9. It is required.

**12. Submit:** a sticky button (`bottom-20` on mobile, `md:bottom-4`) labelled `{submitLabel}`. It shows a spinner while saving and is disabled while saving, while uploading, or until the rights checkbox is checked.

### Validation on submit

- `Le titre est obligatoire`
- `Certifie tes droits avant de partager la recette`
- When saving throws: `Impossible d'enregistrer la recette`

---

## A.17 AcceptButton (household invite)

Included because it is in the scope list; it is used by the household and invitation screens.

- A small button `{label}` opens an AlertDialog.
- Title: `Rejoindre ce foyer ?`
- Description: `Tu quitteras ton foyer actuel : son menu et sa liste de courses ne te seront plus visibles.`
- Buttons: `Annuler` / `Rejoindre`, which calls `onConfirm`.


---

# Part B — Recettes list, Mon livre de cuisine, Menu (meal plan), Courses (shopping), Household, Invitations

Sources: `recettes.index-zoKTB33F.js`, `RecipeFilters-DdSyuBvF.js`, `mes-recettes-2kmj9-1C.js`, `FavoriteButton-Bg8Lehzt.js`, `Rating-C5z5D5WP.js`, `menu-CW9ADJoJ.js`, `meal-plan-aaED2QKP.js` (shared module, **not a route**), `AddToMenuDialog-C5lzIQge.js`, `courses-BM42X0jS.js`, `ingredients-Ba4c7mUu.js` (shared helpers), `household-DNKBWHf4.js` (shared module, **not a route**), `invitation._code-DqW3Ur5c.js`, `AcceptButton-CCl_ukBP.js`, `profil-CAUNkA7w.js` (household section, offsets ~21900–33600), `recipes-D9xc4VyU.js`, `recipe-data-CXYhg0wf.js`.

Important correction to the route list: the router (`index-*.js`) registers these paths: `/`, `/auth`, `/conditions`, `/histoire`, `/video`, `/courses`, `/menu`, `/mes-recettes`, `/profil`, `/invitation/$code`, `/recettes/`, `/recettes/nouvelle`, `/recettes/$id/`, `/recettes/$id/cuisiner`, `/recettes/$id/modifier`, `/admin/ingredients`, `/admin/signalements`, under a `/_authenticated` layout. **There is no `/meal-plan` or `/household` route.** The meal plan screen is `/menu` (chunk `menu-*.js`); `meal-plan-*.js` and `household-*.js` are shared data modules. Household management UI lives in `/profil` ("Ma famille" section).

Bottom/side navigation (AppShell): `Recettes` → `/recettes`, `Menu` → `/menu`, `Courses` → `/courses`, `Profil` → `/profil`. Unauthenticated users are redirected `{to:'/auth', replace:true}`.

Libraries used in these screens (only what the app uses):
- `core.esm-*.js` = **@dnd-kit/core** (DndContext, useDraggable, useDroppable, DragOverlay, PointerSensor/MouseSensor + TouchSensor, `pointerWithin`/collision detection) — used in `/menu`. `profil` additionally bundles **@dnd-kit/sortable** (SortableContext, useSortable, arrayMove, vertical list strategy, keyboard coordinate getter) for "Mon magasin".
- `courses-*.js` bytes ~1.5K–118K = bundled **framer-motion / motion** (`motion.div` with `layout`, `layoutId`, `LayoutGroup`) + **Radix Switch** (~132K–138K). App code starts at byte ~138 190.
- Toasts: sonner (`toast`, `toast.success`, `toast.error`, `toast.info`, toast with `action`).
- Data: TanStack Query (`queryOptions`, `useQuery`, `useSuspenseQuery`, optimistic `setQueryData`).

---

## 1. Shared data modules

### 1.1 `household-*.js`
- **`me` query** — `queryKey: ['me']`:
  - `supabase.auth.getUser()` → id, email
  - `profiles.select('first_name').eq('id', uid).maybeSingle()`
  - `user_roles.select('role').eq('user_id', uid)`
  - returns `{ id, email, firstName, isAdmin: roles.some(r => r.role === 'admin') }`
- **`household` query** — `queryKey: ['household']`:
  - `households.select('id,name,default_servings').maybeSingle()` (RLS limits this to the user's single household (inferred))
  - `household_members.select('user_id,role,joined_at').order('joined_at')`
  - `profiles.select('id,first_name').in('id', memberIds)`
  - returns `{ household, members: [{user_id, role, joined_at, first_name || '?'}] }`
- **initials(name)**: `(name ?? '?').trim().slice(0,2).toUpperCase() || '?'`.
- **Realtime hook `useRealtimeInvalidate(table, queryKey)`**: `supabase.channel(`${table}-${random}`).on('postgres_changes', {event:'*', schema:'public', table}, cb).subscribe()`. Each event debounces 250 ms, then `invalidateQueries({queryKey})`. Cleanup: `removeChannel`. Used for:
  - `/menu`: `meal_plan_entries` → `['meal-plan', weekStart]`
  - `/courses`: `shopping_list_items` → `['shopping', weekStart]`, `ingredients` → `['ingredients']`, `household_ingredient_overrides` → `['ingredient-categories']`
  - (also recettes/$id uses its own channel for comments — see Part A)

### 1.2 `meal-plan-*.js`
- Date helpers (local time, no timezone conversion):
  - `toISODate(d)` = `YYYY-MM-DD`
  - `parse(s)` = `new Date(y, m-1, d)`
  - `addDays(s, n)`
  - `weekStart(date)` = the Monday of that week (`(getDay()+6)%7`)
  - `weekDays(start)` = 7 ISO dates
  - `fmt(s, opts = {weekday:'long', day:'numeric', month:'short'})` → `toLocaleDateString('fr-FR', opts)`
- **Meal slots (enum `meal_type`)**: `[{value:'déjeuner', label:'Déjeuner'}, {value:'dîner', label:'Dîner'}]`. There are only 2 slots per day; there is no breakfast slot.
- **Week query** — `queryKey: ['meal-plan', weekStart]`:
  `meal_plan_entries.select('id,date,meal_type,recipe_id,custom_title,servings,position,added_by,recipes(title,categories,photo_url,photo_thumb_url)').gte('date', start).lte('date', start+6).order('position')`
- **Free-dish presets** (exact strings): `🥡 Restes`, `🥪 Sur le pouce`, `🥣 Soupe & tartines`, `🥗 Salade composée`, `🍕 Pizza / Livraison`, `🍽️ Resto / Sortie`, `🧺 Pique-nique`, `🎉 Apéro / Invités`.
- **household-settings query** — `['household-settings']`: `households.select('id,default_servings').maybeSingle()` → `{id ?? null, default_servings ?? 4}`.
- `updateDefaultServings(id, n)`: `households.update({default_servings:n}).eq('id', id)`.
- `insertMealEntry(row)`: `meal_plan_entries.insert(row)`.

### 1.3 `recipes-*.js` (constants used by lists and filters)
- **Categories** (value → label, lucide icon). Every `tone` is `''`.

  | value | label | icon |
  |---|---|---|
  | apéro | Apéro | wine |
  | entrée | Entrée | utensils-crossed |
  | soupe | Soupe | soup |
  | salade | Salade | salad |
  | plat | Plat | cooking-pot |
  | pâtes | Pâtes | wheat |
  | quiche / tarte | Quiche / Tarte | chart-pie |
  | curry | Curry | flame |
  | légumes | Légumes | carrot |
  | sauce | Sauce | custom inline SVG (sauce boat/ladle) |
  | dessert | Dessert | cake-slice |
  | gâteau | Gâteau | cake |
  | goûter | Goûter | cookie |
  | gaufre / tartines | Gaufre / Tartines | sandwich |
  | pain / brioche | Pain & brioche | croissant |
  | petit-déjeuner | Petit-déjeuner | coffee |
  | boisson | Boisson | cup-soda |
  | repas de fête | Repas de fête | sparkles |

  The icon mapping for wheat, soup, flame, carrot, croissant and cup-soda comes from `wheat-*.js` exports (inferred by name).
  - `getCategory(v)` falls back to index 4 (`plat`).
  - `normalizeCategories(list)` maps the legacy value `accompagnement` to `légumes`, removes duplicates, and keeps the canonical order.
- **Seasons**: `printemps`, `été`, `automne`, `hiver`, `toute l'année`.
- **Units**: `g`, `kg`, `ml`, `cl`, `l`, `c. à soupe`, `c. à café`, `pièce`, `pincée`, `botte`, `sachet`, `tranche`, `gousse`, `verre`.
- **Shopping categories (AI enum)**: `fruits & légumes`, `crèmerie`, `boucherie`, `poissonnerie`, `épicerie`, `surgelés`, `boulangerie`, `boissons`, `autre`.
- **Empty recipe draft**: `{title:'', categories:[cat='plat'], seasons:[], servings:4, prep_time_min:null, cook_time_min:null, difficulty:null, tags:[], notes:null, ingredients:[], steps:[], photo_url:null, photo_thumb_url:null, source_image_urls:[]}`.
- **Scaling**: `scale(q, baseServings, target) = q == null ? null : (!base || base <= 0 ? q : q * target / base)`.
- **Quantity formatting**:
  - Values below 10 snap to the fraction glyphs ¼ ⅓ ½ ⅔ ¾ (tolerance 0.03), e.g. `1½`.
  - Otherwise values ≥ 100 are rounded to an integer, and smaller values to 1 decimal.
  - The decimal separator is a comma.
- **Unit/name pluralisation** `formatQty(q, unit, name)` → `{qty, name}`:
  - Units `pincée`/`botte`/`sachet`/`tranche`/`gousse`/`verre` become plural when q ≥ 2.
  - The unit `pièce` is not displayed.
  - When there is no unit (or `pièce`) and q ≥ 2, the ingredient name is pluralised with French rules:
    - The head noun is pluralised before ` de|du|des|d'|à|au|aux|en|pour|sans|avec …`.
    - Invariant words: maïs, riz, lait, beurre, sucre, sel, poivre, farine, huile, eau, crème, levure, persil, basilic, thym, ciboulette, chocolat, miel, vinaigre, jus, parmesan, gruyère, fromage râpé.
    - Irregular forms: œil/oeil → yeux, ail → aulx.
    - `-eau/-au/-eu` take `+x`, except landau, sarrau, bleu and pneu.
    - `-al` becomes `-aux`, except bal, carnaval, festival, chacal and régal.
    - chou, bijou, caillou, genou, hibou, joujou and pou take `+x`.
    - Words ending in s, x or z are unchanged.
    - Words containing a digit, and the qualifiers bio/extra/maison/nature/bis, are not pluralised.

### 1.4 `recipe-data-*.js` — list query
`queryKey: ['recipes']` (suspense):
`recipes.select('id,title,categories,seasons,prep_time_min,cook_time_min,photo_url,photo_thumb_url,tags,servings,created_at,created_by,rating_avg,rating_count,recipe_ingredients(name)').order('created_at', {ascending:false})`. Each row is mapped to `{...row, ingredientNames: recipe_ingredients.map(i => i.name)}`.

All recipes are visible to all users ("base commune"). Recipes are shared globally; only menu and shopping data are per household.

### 1.5 `ingredients-*.js` helpers (also contains the TanStack Start client runtime)
- **Text normalisation `norm(token)`**:
  - lowercase, NFD with diacritics stripped, œ → oe, æ → ae
  - singularise: `-aux` → `-al` (when length > 3); a trailing `s` or `x` is dropped (when length > 2)
  - `tokens(s)` = split on non-letter/digit characters, then `norm` each token
  - `Z(s)` = tokens joined with spaces
- **`matchesQuery(q, text)`**: every query token must be a prefix of some token in the text. An empty query matches.
- **`currentSeason(date)`**: months 3–5 → printemps, 6–8 → été, 9–11 → automne, otherwise hiver.
- **`totalTime(r)`** = `(prep_time_min ?? 0) + (cook_time_min ?? 0)`.
- **`filterRecipes(recipes, f, favoritesMap)`** — a recipe is excluded when any of these fail:
  - categories: the recipe has at least one selected category
  - favorites: the recipe is in favourites
  - seasons: the recipe's seasons include `toute l'année` or at least one selected season
  - maxTime: the total time is non-zero and ≤ max (a recipe with time 0 is excluded)
  - tags: the recipe has all selected tags
  - include: every term matches some ingredient name
  - exclude: no term matches any ingredient name
  - minRating: `rating_avg ?? 0 ≥ minRating`
  - mineOf: `created_by === userId`
  - q: matches `title` plus all ingredient names
- **`titleSimilarity(a, b)`**: Dice coefficient on character bigrams of normalised tokens (only tokens longer than 2 characters, or tokens containing a digit). Threshold `Xi = 0.75` (used in Part A for duplicate detection).
- **Ingredient query** `['ingredients']`:
  `ingredients.select('id,name,display_name,plural_name,aliases,category_id,seasons,verified,source,pending_ai').order('name')`.
- **Categories query** `['ingredient-categories']` runs three queries in parallel:
  - `ingredient_categories.select('id,name,color,icon,sort_order')`
  - `household_category_orders.select('category_id,sort_order')`
  - `household_ingredient_overrides.select('ingredient_id,category_id')`

  It returns `{categories, overrides: Map(ingredient_id → category_id)}`. Categories are sorted by `householdOrder.get(id) ?? (1000 + sort_order)`, so household-ordered aisles come first and the rest follow in global order.
- **Category icon map** (`ingredient_categories.icon` → lucide icon):
  - Icon keys: `apple`, `carrot`, `leaf`, `croissant`, `milk`, `cheese`, `egg`, `beef`, `drumstick`, `ham`, `fish`, `wheat`, `archive`, `package`, `candy`, `soup`, `flame`, `snowflake`, `cup-soda`, `spray-can`, `shopping-basket`.
  - Fallback: `shopping-basket`.
  - The aisle tile background is `ingredient_categories.color` (inline style).
- **`resolveCategoryId(ingredient, overrides)`** = `overrides.get(ing.id) ?? ing.category_id`. When there is no ingredient the result is `'autre'`, which suggests the "Autre" category's id is literally `autre` (inferred).
- **`searchIngredients(list, text, freqMap, limit=8)`**:
  - Scores each candidate against `name`, `display_name` and `aliases` (all normalised): exact match = 3, prefix = 2, word prefix = 1.
  - Sort order: purchase frequency desc, then score desc, then `name.localeCompare(…, 'fr')`.
- **`classifyPending(ids)`**:
  - `ingredients.select('id').in('id', ids).eq('pending_ai', true)`
  - for any hits, calls server fn `789c6d723c3130a983ec35993e4ec23d1f75a48585adf43e2a4f87361d9321b5` (POST, function middleware) with `{data:{ids}}`. This is AI auto-classification of newly created ingredients (inferred).
- **`setIngredientCategory(ingredientId, categoryId)`** → `rpc('set_ingredient_category', {_ingredient, _category})`. This presumably upserts a `household_ingredient_overrides` row (inferred; overrides are invalidated afterwards).
- **`parseFreeText(text, units)`**:
  - Regex `^(\d+(?:[.,]\d+)?)\s*(.*)$`; the quantity accepts a comma decimal separator.
  - The longest unit that prefixes the rest followed by a space becomes the unit, and a leading `de `/`d'` is stripped.
  - No leading number → `{name: text, quantity: null, unit: null}`.
- **Shopping aggregation and diff** — see §4.3.

### 1.6 Favorites (`FavoriteButton-*.js`)
- Query `['favorites']`: `recipe_favorites.select('recipe_id,created_at')` → `Map(recipe_id → created_at)` (RLS restricts to the current user (inferred)).
- `rpc('recipe_favorite_count', {_recipe_id})` → `['favorite-count', id]`; `rpc('recipe_favorite_names', {_recipe_id})` → `['favorite-names', id]`. These are used on the recipe page (Part A).
- Name-list formatting: `a, b et c`.
- **Toggle** (optimistic, updates both the map and the count):
  - Unfavourite: `recipe_favorites.delete().eq('recipe_id', id)`. Toast: `Retirée de tes favoris`.
  - Favourite: `insert({recipe_id: id})`. Toast: `Ajoutée à tes favoris ❤️`.
  - On error the map is rolled back and the toast `Oups, ça n'a pas marché` is shown.
- **Button**:
  - Round button, size `sm` = h-8 or `md` = h-10.
  - aria-label `Retirer des favoris` / `Ajouter aux favoris`, plus `aria-pressed`.
  - Heart icon is `fill-primary` when active and replays the `animate-heart-pop` animation on each click.
  - Stops pointer/touch propagation so it works inside draggable cards and links.

### 1.7 Rating display (`Rating-*.js`)
- With count > 0: star icon (`fill-primary`), the average formatted, then `· {count} avis`.
- With count = 0: `Pas encore notée`.
- The input widget (5 stars, aria `{n} étoile(s)`, `Retirer ma note`) is used on the recipe page (Part A).

---

## 2. `/recettes` — Recipe list (`recettes.index`)
- Data: suspense `['recipes']` and `['me']`.
- Header:
  - h1 `Recettes`
  - Button (Link) `+ Ajouter` → `/recettes/nouvelle`
- `<RecipeFilters … userId={me.id}>` (§2.1)
- Count line: `{n} recette` / `{n} recettes`
- **Grid**: 2 columns, 3 at sm, 4 at lg. Each card is a Link to `/recettes/$id`:
  - `RecipePhoto` (square; uses `photo_thumb_url ?? photo_url`; falls back to the category icon of `categories[0] ?? 'plat'`)
  - FavoriteButton (sm, top-right)
  - Title (2-line clamp)
  - Category labels joined with ` · `
  - Clock icon with `{total} min`, shown only when total > 0
  - Users icon with servings, shown when not null
  - Rating (small)
- **Empty state** (chef-hat tile, plus button `+ Ajouter une recette` → `/recettes/nouvelle`):
  - Database empty: `La base de recettes est encore vide` / `Prends une recette en photo, on s'occupe du reste.`
  - No match: `Rien ne correspond… pour l'instant !` / `Essaie d'enlever un filtre, ou ajoute cette recette à ton livre de cuisine.`

### 2.1 RecipeFilters (shared by `/recettes` and the `/menu` recipe picker)
- **State** default:
  - `{q:'', categories:[], seasons:[], maxTime:null, tags:[], include:[], exclude:[]}`
  - optional keys: `favorites`, `minRating`, `mineOf`
  - sort default `recent`
  - Filter state is in-component React state only; it is not persisted and not in the URL.
- **Search input**:
  - search icon; placeholder `Titre ou ingrédient…`
  - clear button (aria `Effacer`)
  - h-12, or h-10 in compact mode
- **Horizontal chip row**:
  - one chip per category (label)
  - `Mes favoris ❤️`
  - `👤 Ajoutées par moi` (only if a userId was passed, which is not the case in `/menu`)
  - `🌿 De saison`: active when seasons = [currentSeason]; toggles it
- **Buttons**:
  - `Filtres` / `Filtres ({count})`: toggles the advanced panel. The count = categories + seasons + tags + include + exclude + (maxTime ? 1 : 0) + (minRating ? 1 : 0) + (favorites ? 1 : 0).
  - `Tout effacer` (when count > 0): resets everything but keeps `q` and `mineOf`.
- **Sort select** (aria `Trier`):

  | value | label | behaviour |
  |---|---|---|
  | `recent` | Plus récentes | query order: created_at desc |
  | `alpha` | A → Z | `localeCompare` fr |
  | `time` | Plus rapides | total time asc; 0 is treated as 9999 |
  | `rating` | Mieux notées | rating_avg desc |
  | `favorited` | Ajoutées récemment aux favoris | favourite created_at desc |

- **Advanced panel**:
  - `Saison`: chips for the first 4 seasons, capitalised
  - `Temps total max`: chips `≤ 15 min`, `≤ 30 min`, `≤ 45 min`, `≤ 60 min`, `≤ 90 min`
  - `Note minimum`: `3★ et +`, `4★ et +`, `4,5★ et +`
  - `Tags`: one chip per distinct tag across all recipes, sorted fr; shown only if tags exist
  - `Contient`: tag-input, placeholder `ex. tomate`
  - `Sans`: tag-input, placeholder `ex. champignon`

  Tag-input behaviour: Enter or `,` adds a value, so does blur; values show as removable chips (aria `Retirer {v}`).
- All filters are applied client-side over the full `['recipes']` list (§1.5 `filterRecipes`).

---

## 3. `/mes-recettes` — "Mon livre de cuisine"
- Back link `← Profil` → `/profil`.
- Header:
  - h1 `Mon livre de cuisine`
  - Button `+ Ajouter` → `/recettes/nouvelle`
- **Tabs** (role=tablist, pill style):
  - `Mes recettes ({n})`: recipes with `created_by === me.id`
  - `Mes favoris ({n})`: favourites sorted by favourite date desc
- **Empty states**:
  - Favourites tab: `Pas encore de favoris. Tape sur le cœur d'une recette pour la retrouver ici !`
  - Mine tab: `Ton livre de cuisine est encore tout neuf. Ajoute ta première recette !`
- **List rows**:
  - Link containing: RecipePhoto 16×16, title, category labels joined with ` · `, small Rating
  - FavoriteButton (sm)
  - If the user is the creator or an admin:
    - edit icon (aria `Modifier`) → `/recettes/$id/modifier`
    - delete icon (aria `Supprimer`) with an AlertDialog. Title `Supprimer « {title} » ?`, description `Elle disparaîtra de la base commune pour tout le monde.`, buttons `Annuler` / `Supprimer`.
- **Delete action**: `deleteRecipe(id)` from recipe-data (see Part A), then invalidate `['recipes']`.
  - Success toast: `Recette supprimée`
  - Error toast: `Suppression impossible`

---

## 4. `/menu` — Weekly meal plan
### 4.1 Structure
- The week runs Monday → Sunday (`weekStart`). The state `start` defaults to the current week's Monday.
- Each day has two slots, `déjeuner` and `dîner`. A cell key is `cell|{YYYY-MM-DD}|{meal_type}`.
- A cell holds 0..n entries, ordered by `position`.
- **Entry columns**: `id, date, meal_type, recipe_id (nullable), custom_title (nullable, ≤120 chars), servings (int ≥1), position (int), added_by (uuid; presumably DB default auth.uid() (inferred)), household_id (implicit via RLS/default (inferred))`.
- `default_servings` comes from `households` (fallback 4).

### 4.2 UI
- Header row:
  - h1 `Menu`
  - `Vider la semaine` (eraser icon; disabled when the week is empty)
  - `Copier la semaine précédente` (copy icon)
- Week navigator:
  - `‹` (aria `Semaine précédente`) and `›` (aria `Semaine suivante`), stepping ±7 days
  - centre label `{d MMM} – {d MMM}` (fr-FR, `day:numeric, month:short`)
  - `Cette semaine` button when not on the current week
- **Mobile / below xl**: one card per day.
  - The current day gets `ring-2 ring-primary`.
  - Title is the capitalised `fmt(date)`, e.g. "lundi 3 nov.".
  - Two drop cells per day (grid 2 columns at sm), labelled `Déjeuner` / `Dîner`.
- **xl**: an 8-column grid.
  - Corner cell, then 7 day headers (`weekday:short, day:numeric`); today's header is `bg-primary`.
  - Then for each slot: a vertical rotated label plus 7 compact cells.
  - Desktop cell ids carry the suffix `|d`, which is stripped on drop.
- **Cell**:
  - dashed border; highlighted when a dragged item is over it
  - optional uppercase slot label
  - entries
  - button with notebook-pen icon and text `Plat libre` (sr-only in compact mode); title `Ajouter un plat libre (restes, resto…)`. Opens the free-dish dialog.
- **Entry card** (bg-accent):
  - photo thumbnail, or a notebook icon tile for a free dish
  - title: a Link to `/recettes/$id` (fallback `Recette`), or the italic `custom_title`
  - "added by" initials badge, shown only when the household has ≥2 members. Title `Ajouté par {first_name ?? 'un ancien membre'}`.
  - drag handle (aria `Glisser`); in compact mode the whole header row is the handle
  - `−` (aria `Moins de personnes`), `{n} p.`, `+` (aria `Plus de personnes`)
  - For a recipe: link `👩‍🍳` (aria/title `Cuisiner`) → `/recettes/$id/cuisiner?p={servings}`
  - Trash (aria `Retirer`)
  - Temporary optimistic entries (id `tmp-…`) are not draggable.
- **Help text**: `Glisse une recette dans une case. Maintenez Alt (ou gardez le doigt appuyé avant de bouger) pour dupliquer ; glissez hors du menu ou sur la poubelle pour retirer.`
- **Recipe picker**:
  - Desktop (lg+): a sticky bottom `aside` with a horizontal strip of draggable recipe cards (w-60, the whole card is the drag handle).
  - Mobile: a floating button `📖 Recettes` (bottom-right) opens a bottom sheet (70vh). The sheet has title `Glisse une recette` and a close button (aria `Fermer`). It hides while dragging.
  - Each sheet item has: thumbnail, title, FavoriteButton, a `+` button (aria `Ajouter {title} au menu`) that opens AddToMenuDialog, and a grip handle (aria `Glisser {title}`).
  - Both pickers embed RecipeFilters in compact mode.
  - Empty states: `Aucune recette. ` + link `Ajouter une recette` → `/recettes/nouvelle`; or `Aucune recette ne correspond.`
- **Drag overlay** (portal to body): thumbnail plus title. While duplicating it shows a badge `+ copie`.
- **Trash drop zone** (only while dragging an entry and not copying): a floating pill `🗑 Retirer du menu`. It turns red when hovered.
- **Free-dish dialog** `Un plat sans recette`:
  - input (maxLength 120), placeholder `Qu'est-ce que tu as prévu ? ex. Haricots verts et poulet`
  - preset chips (§1.2)
  - stepper `Pour [−] n [+] personne(s)`, minimum 1, default = default_servings
  - submit `Ajouter au menu` (disabled when empty)
- **Clear-week AlertDialog**:
  - Title: `Vider la semaine ?`
  - Description: `Tous les repas du {range} seront retirés du menu (les recettes restent dans ton livre de cuisine).`
  - Buttons: `Annuler` / `Vider`

### 4.3 Drag & drop logic (dnd-kit)
- **Sensors**: pointer with distance 6; touch with delay 200 ms and tolerance 15. Auto-scroll threshold y = 0.15.
- **Draggable ids**:
  - `recipe|{scope}|{recipeId}` with data `{kind:'recipe', recipeId, title, category, photo}`; scope is `side` or `drawer`
  - `entry|{id}` with data `{kind:'entry', entry}`
- **Copy mode** is on when:
  - the Alt key is held (keydown/keyup listeners), or
  - on touch, the finger stays put (moved < 10 px) for 450 ms after drag start. This also calls `navigator.vibrate(30)`.
- **onDragEnd**:
  - Entry dropped on nothing or on `trash`, not copying → delete the entry.
  - Recipe dropped on a cell → `insert({date, meal_type, recipe_id, servings: default_servings, position: cellCount})`. Optimistic tmp row, then invalidate.
  - Entry with copy → `insert({date, meal_type, recipe_id, custom_title, servings, position: cellCount})`.
  - Entry move (different cell) → `update({date, meal_type, position: cellCount}).eq('id')`.
  - Positions within a cell are not reordered; a dropped item is always appended to the end.
- **Mutations** (all optimistic via `setQueryData(['meal-plan', start])`):
  - **servings ±**: `update({servings}).eq('id')`, ignored if < 1
  - **remove**: `delete().eq('id')`
  - **free dish**: `insert({date, meal_type, custom_title, servings, position})`
  - **clear week**: `delete().gte('date', start).lte('date', start+6)`. Toast `Semaine vidée`.
  - **copy previous week**:
    - select `date,meal_type,recipe_id,custom_title,servings,position` for [start−7, start−1]
    - none → toast `La semaine précédente est vide`
    - else insert each row with `date + 7` and `position + currentWeekEntryCount`. Toast `{n} repas copiés`.
  - Any error → toast `La modification n'a pas pu être enregistrée`, then invalidate `['meal-plan']`.

### 4.4 AddToMenuDialog (used from the recipe page and the mobile picker)
- Default trigger: secondary button `Ajouter au menu` (calendar-plus icon). Dialog title `Ajouter au menu`.
- `Jour`: a horizontal list of 14 day buttons starting today (`weekday:short`, plus the day number). The selected day is styled primary.
- `Repas`: two buttons `Déjeuner` / `Dîner`; default `dîner`.
- `Personnes`: stepper (aria `Moins` / `Plus`, minimum 1). Resets to the household default_servings when opened.
- Button `Ajouter`, which:
  1. counts `meal_plan_entries.select('id', {count:'exact', head:true}).eq('date', d).eq('meal_type', m)` to get the position
  2. inserts `{date, meal_type, recipe_id, servings, position: count}`
  3. invalidates `['meal-plan', weekStart(d)]`
- Success toast: `Ajouté au {meal_type} du {fmt(date)}`, e.g. "Ajouté au dîner du lundi 3 nov.". Error toast: `Impossible d'ajouter au menu`.

---

## 5. `/courses` — Shopping list
### 5.1 Data
- **Period**: the `Du` (start) and `au` (end) date inputs default to today and today+6. Note: the start defaults to today, not to Monday.
- The list is keyed by `week_start = weekStart(start)`, i.e. the Monday of the start date. The two inputs constrain each other: if start > end, then end = start, and vice versa.
- `Cette semaine` resets the period (shown when it is not the default).
- **Header**: h1 `Courses`, and the range text `Du {d MMM} au {d MMM}`.
- **List query** `['shopping', weekStart]`:
  `shopping_list_items.select('id,name,item_key,quantity,unit,ingredient_id,checked,in_stock,source,source_recipe_ids,added_by,checked_at').eq('week_start', ws).order('created_at')`
- **Item columns**:
  - `week_start` (date)
  - `name`, `item_key` (aggregation key; auto items only)
  - `quantity` (numeric | null), `unit` (text | null)
  - `ingredient_id` (nullable FK → ingredients)
  - `checked` (bool), `checked_at` (timestamptz), `checked_by` (uuid)
  - `in_stock` (bool)
  - `source` (`'auto' | 'manuel'`)
  - `source_recipe_ids` (uuid[])
  - `added_by` (uuid; DB default (inferred))
  - `created_at`
  - household scoping via RLS/default (inferred)
- **Frequency query** `['shopping-frequency']`: `shopping_list_items.select('ingredient_id').eq('checked', true).not('ingredient_id', 'is', null).limit(1000)` → `Map(ingredient_id → count)`.
- **Recipe titles** `['recipe-titles']`: `recipes.select('id,title')` → Map.
- **Housekeeping on mount**: `shopping_list_items.delete().eq('checked', true).lt('checked_at', now − 7 days)`.
- Realtime is described in §1.1.

### 5.2 Generation from the menu ("Générer depuis le menu")
1. Fetch `meal_plan_entries.select('recipe_id,servings,recipes(servings,recipe_ingredients(name,quantity,unit,ingredient_id))').gte('date', start).lte('date', end)`. Free dishes (no `recipe_id`) are skipped.
2. Flatten to rows `{recipe_id, recipe_servings, meal_servings, name, quantity, unit, ingredient_id}`. If there are none, show toast.info `Aucune recette au menu sur ces jours`.
3. **Aggregate** (`ra(rows, defaultServings=household.default_servings ?? 4)`):
   - **Skip pantry basics**:
     - exact matches: eau, eau froide, eau chaude, eau tiède, sel, gros sel, sel fin, fleur de sel, poivre, poivre noir, poivre blanc, sel et poivre, sel poivre
     - anything equal to or starting with `huile` or `vinaigre`
   - **Key**: `(ingredient_id ?? normalizedName) + '|' + (quantity != null ? unitFamily : '-')`.
   - **Unit family / factor**:
     - g = mass ×1, kg = mass ×1000
     - ml = vol ×1, cl = vol ×10, l = vol ×1000
     - any other unit is its own family ×1
     - no unit = family `pièce`
   - **Scale factor** = `meal_servings / (recipe_servings > 0 ? recipe_servings : default > 0 ? default : 4)`. The total accumulates `quantity × factor × unitFactor`. Rows with a null quantity produce a quantity-less item.
   - The name is taken from the first occurrence (trimmed). The recipe ids are collected as a set.
   - **Rounding / display unit**:

     | family | total | displayed as |
     |---|---|---|
     | mass | ≥ 1000 | kg rounded to 0.1 |
     | mass | ≥ 250 | g, nearest 50 |
     | mass | ≥ 50 | g, nearest 10 |
     | mass | below 50 | g, nearest 5, minimum 5 |
     | vol | ≥ 1000 | l, 0.1 |
     | vol | ≥ 100 | cl, nearest 5 cl |
     | vol | below 100 | ml, nearest 5, minimum 5 |
     | c. à soupe / c. à café | any | ceiling to 0.5, minimum 0.5 |
     | pièce, gousse, tranche, sachet, botte, verre, pincée | any | ceiling(x − 0.05), minimum 1 |
     | other | any | ceiling to 0.1 |

   - Output: `{key, name, quantity, unit, ingredient_id, source_recipe_ids}`.
4. **Diff vs existing** (`ia(existing, aggregated)`): only existing items with `source === 'auto'` and an `item_key` take part.
   - Matching key → **update**.
   - New key → **insert**.
   - Leftover auto items → **delete**.
   - Manual items are never touched. Checked and in_stock flags of updated auto items are preserved, because they are not in the update payload.
5. **Writes**:
   - `delete().in('id', toDelete)`
   - one `update({name, quantity, unit, ingredient_id, source_recipe_ids}).eq('id')` per updated item
   - `insert([{name, quantity, unit, ingredient_id, source_recipe_ids, item_key: key, week_start, source:'auto'}])`
   - `name` = the ingredient's `display_name` when linked, else the raw name.
6. Toasts: `Liste générée : {n} articles` on success; on error `La génération a échoué`. The button shows `Génération…` while running.

### 5.3 Manual add
- Input (rounded-full h-12), placeholder and aria `Que veux-tu acheter ?`. Submit `+` (aria `Ajouter`).
- **Autocomplete dropdown** (shown while text is typed):
  - up to 8 `searchIngredients` results, each with the aisle-coloured icon, the `display_name`, and `souvent acheté` if the purchase frequency > 0
  - if there is no exact name/alias match, a final row `+ Ajouter « {parsed name} »`
- **Quick-add chips** (input empty): ingredients bought ≥2 times and not currently on the list, sorted by frequency, top 8, shown as `+ {display_name}`.
- **Add logic**:
  1. Parse `"200 g de farine"` → `{qty:200, unit:'g', name:'farine'}`.
  2. Resolve the ingredient: either the picked one, or the first search result whose name/display/alias normalises equal to the parsed name.
  3. Insert `{week_start, name: ing?.display_name ?? parsed.name, quantity, unit, ingredient_id: ing?.id ?? null, source:'manuel'}`, then `.select('ingredient_id').single()`.
  4. If no ingredient was matched client-side but the DB returned an `ingredient_id` (a trigger auto-creates or links the ingredient (inferred)), invalidate `['ingredients']` and call `classifyPending([id])` (AI server fn), then invalidate again.
  - Error toast: `Ajout impossible`.

### 5.4 List rendering
- **Sections**:
  - `À acheter · {n} article(s) restant(s)`: unchecked and not in stock.
  - The items are grouped by aisle (`resolveCategoryId(ingredient, overrides)`, default `autre`), in household aisle order (§1.5). Empty aisles are hidden.
  - Each aisle has an uppercase small heading (the category name) and a grid of 3/4/6 columns.
- **Item tile**:
  - square button with the aisle colour background, the aisle icon, the name (2-line clamp), and the formatted qty+unit (`formatQty`)
  - motion `layout`/`layoutId=id` spring animation (stiffness 420, damping 34)
  - top-left initials badge `Ajouté par {name}` when the household has >1 member
  - top-right `…` button (aria `Détails {name}`) opens the details dialog
- **Tile actions**:
  - **Tap** toggles checked; optimistic `update` via `ke`:
    - checking sets `{checked:true, checked_at: now, checked_by: me.id}`; toast `{name} acheté`
    - unchecking sets `{checked:false, checked_at:null}`; toast `{name} remis dans la liste`
    - both toasts last 4 s and carry an action `Annuler` that restores the previous `checked` / `checked_at`
  - **Long-press** (550 ms, non-mouse) or **right-click** opens "change aisle". Only for items with an `ingredient_id`.
- **`Acheté récemment · {n}`** section: checked, not in stock, sorted by `checked_at` desc.
  - Tiles are muted, struck through, and show a check icon.
  - Button `🗑 Vider` deletes all checked items (`delete().in('id', ids)`).
- **`Déjà en stock ({n})`**: `in_stock` items shown as pill buttons that open the details dialog.
- **Empty list**: dashed box with basket icon and text `Le panier est vide, Tata Suzanne serait fière de toi !`.
- **Share button** `Partager la liste` (disabled if nothing is left to buy). It builds this text:
  ```
  🛒 Courses du {range}

  {AISLE NAME UPPERCASE}
  • {name} — {qty unit}
  ```
  - On coarse-pointer devices with `navigator.share` it calls `navigator.share({text})`.
  - Otherwise it copies to the clipboard and shows toast `Liste copiée`.
- **Details dialog** (title = item name):
  - `Vient de`: a list of recipe titles from `source_recipe_ids`; else `Ajouté à la main` (source manuel) or `—`
  - quantity input (decimal, placeholder `Quantité`, comma accepted)
  - unit select (`—` plus the 14 units)
  - Switch `Déjà en stock (exclu de la liste)`
  - `Changer de rayon` (if `ingredient_id`)
  - `🗑 Supprimer` → `delete().eq('id')`
  - `Enregistrer` → `update({quantity, unit, in_stock})`
- **Change aisle dialog** `Changer de rayon : {name}`:
  - 2-column grid of all categories (colour icon + name); the current one is highlighted
  - Pick → `rpc('set_ingredient_category', {_ingredient, _category})`, then invalidate the ingredients and categories queries
  - Toast `Rayon mis à jour` on success; `Impossible de changer le rayon` on error
  - This is a household-level override and does not change the global category (inferred from the separate overrides table).
- **Update error** (any optimistic edit): toast `Modification impossible`, then refetch.

---

## 6. Household ("Ma famille", inside `/profil`)
### 6.1 Profil screen layout (household-relevant parts)
- h1 `Profil`.
- `Connecté en tant que {email}`.
- First-name input (placeholder `Prénom`), saved on blur or Enter via `profiles.update({first_name}).eq('id', me.id)`.
  - Toasts: `Prénom enregistré` / `Impossible d'enregistrer`.
  - Hint: `Affiché sur les recettes que tu partages : « Ajoutée par {prénom|…} ».`
- Link card `Mon livre de cuisine` — `Celles que tu as ajoutées, avec leurs notes.` → `/mes-recettes`.
- Link card `L'histoire de Tata Suzanne` — `Mais qui se cache derrière la Popote ?` → `/histoire`.
- **Ma famille** section (§6.2).
- **`Personnes par défaut`** — `Réglage du foyer, utilisé quand on ajoute une recette au menu.`
  - Stepper −/+, range 1..50.
  - Optimistic update of `['household-settings']`, then `households.update({default_servings}).eq('id')`.
- **`Mon magasin`** (§6.3).
- Admins only: card `Ingrédients à vérifier` — `Valider ce que l'IA a rangé, fusionner les doublons.` → `/admin/ingredients`.
- (Account deletion / export sections; Part A.)
- Link `Conditions générales d'utilisation` → `/conditions`.
- Admins only: link `Signalements de contenus` → `/admin/signalements`.
- Button `Se déconnecter` → `auth.signOut()` → `/auth`.

### 6.2 Ma famille
- Title `Ma famille` (users icon). Subtitle: `{household.name} — le menu et la liste de courses sont partagés entre tous les membres.`
- **Pending invitations for me**: `rpc('my_invitations')` → rows `{code, inviter, household_name}` (exact columns inferred from usage).
  - Each is shown as a bordered card: `**{inviter}** t'invite à rejoindre « {household_name} »`, plus an AcceptButton labelled `Rejoindre`.
- **Members list**:
  - initials avatar, then `{first_name}` (with ` (moi)` for the current user)
  - role label `Propriétaire` (role `owner`) or `Membre` (any other role; likely `member` (inferred))
  - Owners see a remove button (aria `Retirer {name}`) for other members → `rpc('remove_household_member', {_user_id})`
- **Invite**:
  - Label `Inviter un membre`.
  - Email input (placeholder `email@exemple.fr`) plus submit `Inviter` (mail icon).
  - Button `Copier un lien d'invitation` (copy icon).
  - `household_invitations.insert({household_id, email: lowercased email | null}).select('code').single()`. The code is generated server-side (DB default (inferred)); its format is not visible in the client.
  - The link `${origin}/invitation/${code}` is copied to the clipboard.
  - Toasts:
    - email invite: `Invitation créée pour {email}. Lien copié : envoyez-le-lui.`
    - link invite: `Lien d'invitation copié`
    - error: `Invitation impossible`
  - No email is sent by the client.
  - Hint: `Valable 7 jours. La personne invitée par email verra aussi l'invitation dans son Profil.` The 7-day `expires_at` is set by a DB default (inferred).
- **Active invitations** `['household-invitations']`: `household_invitations.select('id,code,email,expires_at').gt('expires_at', now).order('created_at', {ascending:false})`.
  - Each row shows the monospace code and `email ?? 'lien'`.
  - Copy button (aria `Copier`) shows toast `Lien copié`.
  - Cancel button (aria `Annuler l'invitation`) → `household_invitations.delete().eq('id')`.
- **Leave** (only if the household has >1 member): button `Quitter le foyer` opens an AlertDialog:
  - Title: `Quitter « {name} » ?`
  - Description: `Tu retrouveras un foyer personnel vide. Le menu et la liste partagés restent aux autres membres.`
  - Buttons: `Annuler` / `Quitter` → `rpc('leave_household')`
- RPC errors show a toast with `error.message`. On success all queries are invalidated.
- **Household model** (inferred from the UI copy):
  - Every user always has exactly one household; a personal one is created automatically, probably by a signup trigger.
  - Joining another household replaces the current one.
  - `households(id, name, default_servings)`
  - `household_members(household_id, user_id, role 'owner'|…, joined_at)`

### 6.3 Mon magasin (aisle order)
- Text: `Mon magasin` — `Glisse les rayons dans l'ordre de ton supermarché, le panier suivra.`
- A sortable vertical list (dnd-kit sortable) of all `ingredient_categories`, in the current household order.
  - Each row shows a grip icon, the coloured icon tile and the name.
  - Sensors: pointer (distance 5), touch (delay 150, tolerance 6), keyboard.
- **On drop**: `arrayMove`, then `household_category_orders.upsert(list.map((c, i) => ({category_id: c.id, sort_order: i})), {onConflict:'household_id,category_id'})`. `household_id` is filled by a DB default or trigger (inferred).
  - Error toast: `Impossible d'enregistrer l'ordre`.
- **`↺ Par défaut`**: `household_category_orders.delete().neq('category_id', '')`, which deletes every row of the household. Toast `Ordre par défaut rétabli`.

---

## 7. `/invitation/$code`
- Query `['invitation', code]`: `rpc('get_invitation', {_code: code})` → first row or null. Fields used: `household_name`, `inviter`, `already_member`, `expired`.
- Card with a users icon tile. States:
  - loading: `Chargement…`
  - not found: `Cette invitation n'existe pas.`
  - already member: `Tu fais déjà partie de « {household_name} ».`
  - expired: `Cette invitation a expiré. Demandes-en une nouvelle à {inviter}.`
  - valid: `**{inviter}** t'invite à rejoindre **« {household_name} »** pour partager le menu et la liste de courses.` plus an AcceptButton labelled `Rejoindre le foyer`
- **AcceptButton** is an AlertDialog:
  - Title: `Rejoindre ce foyer ?`
  - Description: `Tu quitteras ton foyer actuel : son menu et sa liste de courses ne te seront plus visibles.`
  - Buttons: `Annuler` / `Rejoindre`
- On confirm: `rpc('accept_invitation', {_code})`.
  - Error: toast `error.message`.
  - Success: invalidate all queries, toast `Bienvenue dans « {household_name} » !`, navigate to `/menu`.
- Footer: ghost button `Retour au profil` → `/profil`.
- The route is presumably under `/_authenticated`, so a logged-out visitor goes to `/auth` first (inferred; check whether a redirect back is preserved — Part A auth).

---

## 8. Table / RPC summary for this part

| Table | Operations |
|---|---|
| `meal_plan_entries` | select (week, with `recipes(title,categories,photo_url,photo_thumb_url)` embed; prev-week copy; generation with `recipes(servings,recipe_ingredients(name,quantity,unit,ingredient_id))`); head count by date+meal_type; insert `{date,meal_type,recipe_id?,custom_title?,servings,position}`; update `{servings}` / `{date,meal_type,position}`; delete by id / by date range |
| `shopping_list_items` | select by `week_start` order `created_at`; frequency select; insert manual / auto (`item_key`, `source`); update `{checked,checked_at,checked_by}`, `{quantity,unit,in_stock}`, `{name,quantity,unit,ingredient_id,source_recipe_ids}`; delete by id, by ids, by stale checked (>7 days) |
| `households` | select `id,name,default_servings` (`maybeSingle`); update `default_servings` |
| `household_members` | select `user_id,role,joined_at` order `joined_at` |
| `household_invitations` | insert `{household_id,email}` → `code`; select `id,code,email,expires_at` where `expires_at > now` order `created_at desc`; delete by id |
| `household_category_orders` | select `category_id,sort_order`; upsert onConflict `household_id,category_id`; delete all (`neq category_id ''`) |
| `household_ingredient_overrides` | select `ingredient_id,category_id` (written via RPC `set_ingredient_category` (inferred)) |
| `ingredient_categories` | select `id,name,color,icon,sort_order` |
| `ingredients` | select `id,name,display_name,plural_name,aliases,category_id,seasons,verified,source,pending_ai` order `name`; select `id` where `pending_ai` |
| `recipe_favorites` | select `recipe_id,created_at`; insert `{recipe_id}`; delete by `recipe_id` |
| `profiles` | select `first_name` / `id,first_name`; update `first_name` |
| `user_roles` | select `role` by `user_id` (`admin`) |
| `recipes` | list select (§1.4), `id,title` for titles |

RPCs used in this part:
- `get_invitation(_code)`
- `accept_invitation(_code)`
- `my_invitations()`
- `remove_household_member(_user_id)`
- `leave_household()`
- `set_ingredient_category(_ingredient, _category)`
- `recipe_favorite_count(_recipe_id)`
- `recipe_favorite_names(_recipe_id)`

Server function used in this part: `789c6d723c3130a983ec35993e4ec23d1f75a48585adf43e2a4f87361d9321b5`. It is POST, called with `{data:{ids:string[]}}`, and classifies pending AI ingredients (inferred).

Realtime: postgres_changes on `meal_plan_entries`, `shopping_list_items`, `ingredients` and `household_ingredient_overrides` (with a 250 ms debounced invalidate).
