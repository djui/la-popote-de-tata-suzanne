# La Popote: changes in the i18n redeploy (site3 vs site/SPEC.md)

Source: the bundle crawled on 2026-11-09 from `/recettes` (`index-H_E_LjbS.js`, 86 chunks plus `styles-D5jsV4Kn.css`). It is byte-identical in file names and hashes to the earlier `scratchpad/site2/` download. The comparison baseline is `scratchpad/site/` and its SPEC.md.

## TL;DR
- The headline change is i18n (FR/EN). The routes, Supabase tables, RPCs, storage buckets and the 5 server-function ids are unchanged.
- The data model gains 2 columns: `profiles.preferred_language` and `ingredient_categories.name_en`.
- **FAQ "Questions fréquentes" and "Nous contacter" are NOT new.** They were already in the old bundle (SPEC C.7 items 11–12), with the same 5 Q/A pairs and the same mailto. Only their text now goes through i18n.
- The auth flow is unchanged apart from a FR|EN toggle on the page.

## 1. i18n architecture
- i18next and react-i18next. All resources are **bundled statically** in `dist-VLWV7hRS.js` via `import.meta.glob('../locales/{fr,en}/*.json')`. Nothing is loaded at runtime: no `/locales/...` fetch and no HTTP backend.
- There are 15 namespaces: admin, auth, common, cooking, errors (empty), faq, home, household, menu, profile, recipeForm, recipes, shopping, story, terms. That makes 582 keys.
  - Keys are `text_<10 hex>`, plus `terms:fullText` (the full CGU in markdown) and `terms:precedence`.
  - There are no plural keys (`_one`/`_other`).
  - 10 strings use `{{var}}` interpolation: count, name, email, meal, date.
- Init options: `lng:'fr', fallbackLng:'fr', supportedLngs:['fr','en'], defaultNS:'common', initAsync:false, interpolation.escapeValue:false, returnNull:false`.
- Helper `t(key)`: if the key is missing, it returns `''` when the key contains `:`, otherwise the input.
- **Display-value map (`Kk`, 1151 entries)** maps a *source string* (French or English) to a key. `displayValue(s)` / `iA(s)` translate it at runtime. It is used for:
  - route `<title>` and meta description/og tags. These stay French in `head()`; a MutationObserver rewrites them and keeps the original in `data-fr`.
  - recipe-category labels. Capitalised variants such as `Apéro` map to the lowercase value keys.
  - **server-returned error messages from the AI server fns**, which are still French. These are the new strings: `Trop de demandes, réessaie dans un instant.`, `Crédits IA épuisés.`, `Tata Suzanne fait une pause, réessaie demain !`, `Ta photo était difficile à lire…`, `Je n'ai pas trouvé de recette dans ce texte…`.
  - iOS: translate server `error` strings through `fr_to_en.json`.
- DB enum values stay French in the DB and are translated only for display. This covers categories, seasons, units (`c. à soupe`→`tbsp`), meal types (`déjeuner`→`Lunch`) and shopping categories (`fruits & légumes`→`Fruit & veg`).
- Locale-aware formatting:
  - `Intl` number and date formats use `en-GB` / `fr-FR`.
  - Menu dates use the date-fns `enGB` / `fr` locales.
  - Relative comment times use `Intl.RelativeTimeFormat(lang)`.
  - Title and tag sort uses `localeCompare(…, lang)`. Ingredient search still compares with `'fr'`.
- `document.documentElement.lang` follows the language. The SSR HTML is always `lang="fr"`.
- Hard-coded strings left untranslated (bugs to copy or fix):
  - `la photo` in the "Analyser la photo" button for a single photo. The plural uses `common:text_42b5241708`.
  - The toggle's aria-label `Langue`/`Language` and the button labels `FR`, `EN`, `Français`, `English`.
  - The terms page subtitle `La Popote de Tata Suzanne`.

## 2. Language toggle (`index-*.js` export `a`; component `vn`)
- UI: `FR | EN` ghost buttons; the active one is `font-extrabold text-primary` with `aria-pressed`. It is rendered top-right on:
  - `/` (home), `/auth`, `/profil` (above the h1), `/histoire`, `/conditions`, `/video`
  - the cook-mode header (`/recettes/$id/cuisiner`)
- On click `setLanguage(lng)`:
  1. It increments an in-memory counter `userChangedCount`.
  2. It sets `localStorage['popote_lang']=lng` and calls `i18n.changeLanguage(lng)`.
  3. If the user is signed in (`auth.getUser()`), it runs `profiles.update({preferred_language:lng}).eq('id',uid)`. On error it toasts `profile:text_da4f647350` (`Impossible d'enregistrer` / `Could not save`).
- Initial language:
  - SSR and pre-hydration render in French. `useI18n().currentLanguage` returns `'fr'` until hydrated.
  - On mount: `changeLanguage(normalize(localStorage.popote_lang))`, where `normalize = v==='en'?'en':'fr'`. **There is no device or `navigator.language` detection**, so the default is French.
- Sync with `profiles`, via `supabase.auth.onAuthStateChange`. On `INITIAL_SESSION`, `SIGNED_IN` or `USER_UPDATED` (in a microtask, with a user):
  - If the event is `SIGNED_IN` **and** the user toggled during this page session (counter > 0), it **pushes** the local language: `profiles.update({preferred_language: current})`.
  - Otherwise it **pulls**: `profiles.select('preferred_language').eq('id',uid).maybeSingle()`. If there is no error, the row exists, the request is the latest, and no toggle happened meanwhile, it runs `changeLanguage(normalize(row.preferred_language))` and writes localStorage.
  - Null or any non-`en` value is treated as `fr`.
- Sign-up does not send a language: the `signUp` data is still `{invite_code, first_name, terms_version:'1.0', terms_accepted}`. The DB default for `preferred_language` is unknown (presumably null or `'fr'`).

## 3. Data model / backend
| Change | Detail |
|---|---|
| `profiles.preferred_language` (new, text `'fr'`/`'en'`) | read/written by the client as above |
| `ingredient_categories.name_en` (new) | categories query is now `select('id,name,name_en,color,icon,sort_order')`; label = `lang==='en' && name_en || name` (profile "Mon magasin" list, Courses aisles, admin ingredient aisle select) |
| Tables | unchanged (20): ai_usage_logs, content_reports, household_category_orders, household_ingredient_overrides, household_invitations, household_members, households, ingredient_categories, ingredients, meal_plan_entries, profiles, recipe_comments, recipe_favorites, recipe_ingredients, recipe_ratings, recipe_steps, recipes, shopping_list_items, terms_acceptances, user_roles |
| RPCs | unchanged: accept_invitation, get_invitation, merge_ingredients, my_invitations, recipe_favorite_count, recipe_favorite_names, set_ingredient_category (+ leave_household, remove_household_member as in SPEC) |
| Server fns | **same 5 ids**, same payloads (`{images}`, `{text}`, `{url}`, `{ids}`, `{confirmation:'SUPPRIMER',keepRecipes}`); no language parameter is sent, so AI output stays French |
| Aisles | still DB rows, and the icon map is unchanged (21 lucide keys: apple, carrot, leaf, croissant, milk, cheese, egg, beef, drumstick, ham, fish, wheat, archive, package, candy, soup, flame, snowflake, cup-soda, spray-can, shopping-basket). Aisle names such as "Herbes aromatiques" and their `name_en` **are not in the bundle**. An anonymous REST read of `ingredient_categories` returns `[]` (RLS), so get them with an authenticated query. The AI schema's `shopping_category` enum (9 legacy values) is unchanged. |

## 4. Routes
Unchanged: `/`, `/auth`, `/recettes/`, `/recettes/nouvelle`, `/recettes/$id/`, `/recettes/$id/cuisiner`, `/recettes/$id/modifier`, `/menu`, `/courses`, `/mes-recettes`, `/profil`, `/histoire`, `/conditions`, `/invitation/$code`, `/video`, `/admin/ingredients`, `/admin/signalements`. There is a new tiny `ClientOnly-*.js` (useSyncExternalStore hydration guard).

## 5. FAQ and contact (unchanged content, now i18n; `profil-*.js`)
- Contact: `mailto:gregoiremart1@gmail.com?subject=%5BMa%20Cuisine%5D%20Question%20ou%20retour`
  - The decoded subject is `[Ma Cuisine] Question ou retour`.
  - There is **no body**, and the subject is not localized.
- CGU contact link (`/conditions`, `[[CONTACT]]` placeholders, 3 in each language): `mailto:gregoiremart1@gmail.com?subject=%5BMa%20Cuisine%5D%20Question%20sur%20les%20CGU`.

| Key | FR | EN |
|---|---|---|
| faq:text_16664684bf (title) | Questions fréquentes | Frequently asked questions |
| faq:text_20b431ba6e / 6adf72211c | Comment ajouter une recette depuis une photo ou un livre ? → Dans Recettes, touche « Ajouter », choisis la catégorie puis prends une ou plusieurs photos. Les informations sont lues automatiquement ; vérifie les champs surlignés avant d'enregistrer. Tu peux aussi tout saisir à la main. | How do I add a recipe from a photo or cookbook? → In Recipes, tap ‘Add’, choose a category, then take one or more photos. The information is read automatically; check the highlighted fields before saving. You can also enter everything by hand. |
| faq:text_68dff4e82e / 6b777c19a0 | Comment fonctionne le partage avec ma famille ? → Dans Profil, section « Ma famille », copie un lien d'invitation et envoie-le. Une fois la personne inscrite, le menu et la liste de courses sont partagés et se mettent à jour en direct. | How does sharing with my family work? → In Profile, under ‘My household’, copy an invitation link and send it. Once they have signed up, the menu and shopping list are shared and update in real time. |
| faq:text_66ae686f52 / 7302c9c2c6 | Comment générer la liste de courses à partir du menu ? → Remplis le menu de la semaine, puis ouvre Courses et touche « Générer depuis le menu ». Les quantités sont adaptées au nombre de personnes et les ingrédients identiques sont regroupés. | How do I generate a shopping list from the menu? → Fill in your weekly menu, then open Shopping and tap ‘Generate from menu’. Quantities are adjusted for the servings and matching ingredients are grouped together. |
| faq:text_bb1b8e4607 / 827c28f042 | Puis-je changer les portions sur le menu sans modifier la recette ? → Oui. Le nombre de personnes réglé sur une case du menu ne concerne que ce repas ; la recette d'origine reste inchangée. | Can I change the servings on the menu without changing the recipe? → Yes. The servings you set in a menu slot only apply to that meal; the original recipe stays unchanged. |
| faq:text_3930f3343b / e94c4565f1 | Comment noter ou commenter une recette ? → Ouvre la fiche d'une recette : touche les étoiles pour donner une note de 1 à 5, et écris ton avis dans la section Commentaires en bas de page. | How do I rate or comment on a recipe? → Open a recipe: tap the stars to rate it from 1 to 5, and share your thoughts in the Comments section at the bottom of the page. |
| faq:text_f02ffb674a | Nous contacter | Contact us |
| faq:text_471b6bf4bc | Une question, une idée ou un souci ? Touche le bouton ci-dessous : ton application de messagerie s'ouvre avec l'e-mail déjà rédigé. | Have a question, an idea or a problem? Tap the button below: your email app opens with the email already drafted. |
| faq:text_904363825e | Envoyer un e-mail | Send an email |

## 6. Other behavioural changes
- **Terms `/conditions`**: the full text now comes from `terms:fullText` (FR or EN markdown, split into articles as before).
  - In EN, a notice `terms:precedence` is shown first: "This English version is provided for convenience. The French version prevails." The FR value is empty.
  - `terms_version` is still `'1.0'`.
- **Cook mode timer labels** (`recettes._id.cuisiner`): when lang is `en` there is a separate labeller.
  - It matches `/four|enfourn|oven|bake/`→`Oven`, `/repos|reposer|réserv|lever|pousser|refroidir|rest|cool/`→`Rest`, `/marin/`→`Marinade`, and `/cui|mijot|bouill|frire|dorer|cook|simmer|boil|fry/`→`Cooking`.
  - The label is `"<Label> — <ingredient>"` (no ingredient for Rest); otherwise it is `Step N`.
  - The French labeller is unchanged (`Cuisson du …`, `Étape N`).
- **Cook mode duration parsing** now also accepts the English units `hours?`, `hrs?` and `seconds?`. Number words and range words are still French only (`un…cinquante`, `à/et/-`).
- Toasts with interpolation are new or now parameterised:
  - `Ajouté au {{meal}} du {{date}}` (AddToMenuDialog)
  - `Liste générée : {{count}} articles` (Courses)
  - `{{count}} repas copiés`
  - `Répondre à {{name}}…` (comment reply placeholder)
  - `les {{count}} photos`
  - `{{count}} étoiles`
- New a11y strings for shadcn components: navigation, carousel and pagination labels (`Diapositive précédente`, `Page suivante`, …).
- The unused keys `recipes:text_1020d9085c` (Favoris / Favourites) and `recipes:text_556635f2ec` (Mon carnet) exist, possibly for future tabs.
- Profile page structure, household, invitations, account deletion, export, Mon magasin and admin links are all unchanged apart from the toggle and translated text.

## 7. Files
- `i18n.json`: 582 keys `{ns:key: {fr, en}}`.
- `fr_to_en.json`: 596 entries. That is 581 distinct FR key strings (no conflicting duplicates; the empty FR of `terms:precedence` is omitted) plus 15 capitalised category labels from the display map (`Apéro`→`Nibbles & drinks`, …).
