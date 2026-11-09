// Generated from docs/spec/i18n/i18n.json (terms, story, faq namespaces). Long texts switch on AppLanguage.current.
import Foundation

struct LocalizedText: Sendable {
    let fr: String
    let en: String
    var current: String { AppLanguage.current == .en ? en : fr }
}

enum LegalTexts {
    static let contactMailto = URL(string: "mailto:gregoiremart1@gmail.com?subject=%5BMa%20Cuisine%5D%20Question%20ou%20retour")!
    static let termsMailto = URL(string: "mailto:gregoiremart1@gmail.com?subject=%5BMa%20Cuisine%5D%20Question%20sur%20les%20CGU")!
    static let contactAddress = "gregoiremart1@gmail.com"
    static let teaserVideo = Backend.webURL.appending(path: "__l5e/assets-v1/ddc48e49-3997-4547-a935-78bb998dfaa0/tata-suzanne-teaser.mp4")

    static let termsFR = #"""
# Conditions générales d'utilisation
## La Popote de Tata Suzanne

Version 1.0, en vigueur depuis le 4 novembre 2026

### 1. Objet

La Popote de Tata Suzanne (ci-après « la Popote ») est une application de partage de recettes, de planification de menus et de listes de courses. Elle est éditée à titre privé et non commercial par La famille Martin, Lausanne, Suisse (ci-après « l'éditeur »).

Les présentes conditions régissent l'utilisation de la Popote. En créant un compte, tu les acceptes sans réserve.

### 2. Un usage strictement privé et non commercial

La Popote est un projet pilote réservé à un cercle de famille et d'amis. Elle est gratuite, sans publicité et sans but lucratif.

Tu t'engages à l'utiliser uniquement pour ton usage personnel et familial. Il est interdit :
- de revendre, republier ou diffuser à l'extérieur de la Popote les recettes, photos ou commentaires d'autres utilisateurs sans leur accord ;
- d'utiliser la Popote à des fins commerciales ou publicitaires ;
- d'extraire massivement son contenu, manuellement ou par des moyens automatisés.

### 3. Compte et foyer

Tu dois avoir au moins 16 ans pour créer un compte, ou disposer de l'accord d'un parent.

Tu es responsable de la confidentialité de tes identifiants et de l'activité de ton compte. Les membres d'un même foyer partagent le menu de la semaine et la liste de courses : n'invite que des personnes de confiance.

### 4. Les contenus que tu partages

En ajoutant une recette, une photo, une note ou un commentaire, tu t'engages à ce que :
- les photos de plats soient les tiennes, ou que tu aies l'autorisation de leur auteur ;
- les instructions soient rédigées avec tes propres mots, ou proviennent de recettes familiales ou d'une source dont tu as le droit de partager le texte ;
- tu indiques la source quand une recette est inspirée d'un livre, d'un magazine, d'un blog ou d'un chef ;
- tes contenus ne soient ni illicites, ni injurieux, ni discriminatoires, et ne portent pas atteinte à la vie privée ou aux droits de quiconque.

Tu restes propriétaire de tes contenus. Tu accordes à l'éditeur une licence gratuite, non exclusive, limitée à la Popote et à sa durée de fonctionnement, pour les héberger, les afficher aux autres utilisateurs et les adapter techniquement (redimensionnement des images, calcul des quantités, etc.).

### 5. Droits d'auteur : ce qu'il faut savoir

Une liste d'ingrédients et une idée de recette ne sont en principe pas protégées. En revanche, le texte d'un livre ou d'un magazine, sa mise en page et ses photos le sont.

C'est pourquoi :
- les photos de pages de livres ou de magazines que tu téléverses servent uniquement à l'analyse automatique de la recette. Elles restent privées et ne sont jamais montrées aux autres utilisateurs ;
- il t'appartient de vérifier et reformuler le texte extrait avant de l'enregistrer ;
- ne partage pas des photos de plats trouvées sur internet.

Tu es seul responsable des contenus que tu publies. Tu garantis l'éditeur contre toute réclamation d'un tiers liée à un contenu que tu as partagé en violation des présentes conditions.

### 6. Signalement et retrait

Si tu estimes qu'un contenu porte atteinte à tes droits ou est inapproprié, utilise le bouton « Signaler » ou écris à [[CONTACT]].

L'éditeur examine chaque signalement dans les meilleurs délais. Il peut retirer ou modifier tout contenu, et suspendre ou supprimer un compte qui ne respecte pas ces conditions, sans préavis.

### 7. Notes et commentaires

Les notes et commentaires reflètent l'avis personnel de leurs auteurs. Reste bienveillant : on critique une recette, jamais une personne.

### 8. Cuisine, santé et allergies

Les recettes sont partagées par des cuisiniers amateurs. L'éditeur ne garantit ni leur exactitude, ni leur résultat, ni leurs valeurs nutritionnelles.

Les quantités ajustées automatiquement et les informations extraites par intelligence artificielle peuvent contenir des erreurs : vérifie-les avant de cuisiner.

En cas d'allergie, d'intolérance ou de régime particulier, vérifie toujours la composition des produits. Respecte les règles d'hygiène et de cuisson, en particulier pour les viandes, poissons, œufs et produits crus.

### 9. Intelligence artificielle

Les photos de recettes sont analysées par un modèle d'intelligence artificielle fourni par un prestataire tiers, uniquement pour extraire la recette et catégoriser les ingrédients. N'y fais pas figurer de données personnelles (noms, adresses, documents privés).

### 10. Données personnelles

L'éditeur traite le minimum de données nécessaires au fonctionnement de la Popote : adresse e-mail, prénom, composition du foyer, recettes, notes, commentaires, favoris, menus et listes de courses.

Ces données ne sont ni vendues, ni utilisées à des fins publicitaires. Elles sont hébergées par des prestataires techniques (hébergement, base de données, intelligence artificielle) qui peuvent être situés hors de Suisse, avec des garanties appropriées.

Conformément à la loi fédérale sur la protection des données (LPD), tu peux à tout moment consulter, corriger ou supprimer tes données, ou supprimer ton compte depuis ton Profil ou en écrivant à [[CONTACT]].

À la suppression de ton compte, tes données personnelles sont effacées. Les recettes que tu as partagées sont supprimées, sauf si tu choisis de les laisser à la communauté de façon anonyme.

### 11. Disponibilité

La Popote est un projet pilote, fourni « en l'état ». L'éditeur ne garantit pas sa disponibilité permanente et peut la modifier, la suspendre ou y mettre fin à tout moment. Pense à garder une copie de tes recettes précieuses.

### 12. Responsabilité

Dans les limites autorisées par la loi, l'éditeur décline toute responsabilité pour les dommages résultant de l'utilisation de la Popote, des contenus publiés par les utilisateurs ou d'une indisponibilité du service.

### 13. Modification des conditions

L'éditeur peut modifier ces conditions. La nouvelle version te sera présentée à ta prochaine connexion et devra être acceptée pour continuer à utiliser la Popote.

### 14. Droit applicable et for

Les présentes conditions sont soumises au droit suisse. Tout litige relève des tribunaux compétents du canton de Vaud.

### 15. Contact

[[CONTACT]]

Merci de partager ta tablée avec nous. Et bon appétit !

"""#

    static let termsEN = #"""
# Terms of use
## La Popote de Tata Suzanne

Version 1.0, effective from 4 November 2026

### 1. Purpose

La Popote de Tata Suzanne (hereinafter ‘La Popote’) is an app for sharing recipes, planning menus and creating shopping lists. It is published on a private, non-commercial basis by the Martin family, Lausanne, Switzerland (hereinafter ‘the publisher’).

These terms govern your use of La Popote. By creating an account, you accept them without reservation.

### 2. Strictly private, non-commercial use

La Popote is a pilot project reserved for a circle of family and friends. It is free, has no advertising and is not for profit.

You agree to use it solely for your own personal and family purposes. You must not:
- resell, republish or distribute other users’ recipes, photos or comments outside La Popote without their consent;
- use La Popote for commercial or advertising purposes;
- extract its content in bulk, whether manually or by automated means.

### 3. Account and household

You must be at least 16 years old to create an account, or have a parent’s consent.

You are responsible for keeping your login details confidential and for activity on your account. Members of the same household share the weekly menu and shopping list: only invite people you trust.

### 4. The content you share

When you add a recipe, photo, rating or comment, you agree to ensure that:
- photos of dishes are your own, or that you have the photographer’s permission;
- instructions are written in your own words, or come from family recipes or a source whose text you have the right to share;
- you acknowledge the source whenever a recipe is inspired by a book, magazine, blog or chef;
- your content is not unlawful, abusive or discriminatory, and does not infringe anyone’s privacy or rights.

You retain ownership of your content. You grant the publisher a free, non-exclusive licence, limited to La Popote and the period during which it operates, to host your content, display it to other users and make technical adaptations to it (resizing images, calculating quantities, etc.).

### 5. Copyright: what you need to know

A list of ingredients and the idea for a recipe are generally not protected by copyright. However, the text of a book or magazine, its layout and its photographs are protected.

For this reason:
- any photos of book or magazine pages you upload are used solely for automated recipe analysis. They remain private and are never shown to other users;
- you are responsible for checking and rewording the extracted text before saving it;
- do not share photos of dishes you have found on the internet.

You are solely responsible for the content you publish. You indemnify the publisher against any third-party claim relating to content you have shared in breach of these terms.

### 6. Reporting and removal

If you believe that content infringes your rights or is inappropriate, use the ‘Report’ button or write to [[CONTACT]].

The publisher reviews each report as promptly as possible. It may remove or modify any content, and suspend or delete an account that does not comply with these terms, without prior notice.

### 7. Ratings and comments

Ratings and comments reflect the personal views of their authors. Be kind: critique the recipe, never the person.

### 8. Cooking, health and allergies

Recipes are shared by amateur cooks. The publisher does not guarantee their accuracy, results or nutritional values.

Automatically adjusted quantities and information extracted using artificial intelligence may contain errors: check them before cooking.

If you have an allergy, intolerance or specific dietary requirements, always check the ingredients in the products you use. Follow food hygiene and cooking guidelines, particularly for meat, fish, eggs and raw foods.

### 9. Artificial intelligence

Photos of recipes are analysed by an artificial intelligence model supplied by a third-party provider, solely to extract the recipe and categorise the ingredients. Do not include personal data in them (names, addresses or private documents).

### 10. Personal data

The publisher processes only the minimum data necessary to operate La Popote: email address, first name, household composition, recipes, ratings, comments, favourites, menus and shopping lists.

This data is neither sold nor used for advertising purposes. It is hosted by technical service providers (hosting, database and artificial intelligence services) that may be located outside Switzerland, with appropriate safeguards in place.

Under the Federal Act on Data Protection (FADP), you may access, correct or delete your data at any time, or delete your account, through your Profile or by writing to [[CONTACT]].

When your account is deleted, your personal data is erased. The recipes you have shared are deleted unless you choose to leave them with the community anonymously.

### 11. Availability

La Popote is a pilot project, provided ‘as is’. The publisher does not guarantee uninterrupted availability and may modify, suspend or discontinue it at any time. Remember to keep a copy of your treasured recipes.

### 12. Liability

To the extent permitted by law, the publisher accepts no liability for damage arising from the use of La Popote, content published by users or the unavailability of the service.

### 13. Changes to these terms

The publisher may amend these terms. The new version will be presented to you the next time you log in, and you must accept it to continue using La Popote.

### 14. Governing law and jurisdiction

These terms are governed by Swiss law. Any dispute falls within the jurisdiction of the competent courts of the canton of Vaud.

### 15. Contact

[[CONTACT]]

Thank you for sharing your table with us. Bon appétit !

"""#

    static let termsPrecedenceEN = "This English version is provided for convenience. The French version prevails."

    enum Story {
        static let title = LocalizedText(fr: "L'histoire de", en: "The story of")
        static let whoTitle = LocalizedText(fr: "Tata Suzanne, c'est qui ?", en: "Who is Tata Suzanne?")
        static let who1 = LocalizedText(fr: "Tata Suzanne, c'est Marion. Elle aime rigoler, elle aime cuisiner, et surtout, elle aime partager.", en: "Tata Suzanne is Marion. She loves a laugh, she loves cooking, and above all, she loves sharing.")
        static let who2 = LocalizedText(fr: "Elle a toujours une bonne idée sous le coude. Et sous le coude, il y a beaucoup de choses : des centaines de recettes découpées dans des magazines, des livres de cuisine qui débordent, et des post-it. Beaucoup de post-it. Des post-it sur les post-it.", en: "She always has a good idea tucked away. And there is plenty tucked away: hundreds of recipes cut out of magazines, cookbooks bursting at the seams, and Post-it notes. Lots of Post-it notes. Post-it notes on Post-it notes.")
        static let postit2 = LocalizedText(fr: "Penser au beurre…", en: "Remember the butter…")
        static let bazarTitle = LocalizedText(fr: "Le joyeux bazar", en: "The happy chaos")
        static let bazar1 = LocalizedText(fr: "Il y a aussi les boucles WhatsApp avec la famille et les copines, une app pour les courses, un tableau papier pour le menu de la semaine… et une bonne dose de « on mange quoi ce soir ? ».", en: "Then there are WhatsApp groups with family and friends, a shopping app, a weekly menu chart on paper… and plenty of ‘what’s for dinner tonight?’.")
        static let bazarPostit = LocalizedText(fr: "Au final ? Beaucoup d'énergie dépensée, et une sacrée charge mentale.", en: "The result? A lot of energy spent, and an awful lot to keep track of.")
        static let ideaTitle = LocalizedText(fr: "L'idée de la Popote", en: "The idea behind La Popote")
        static let idea1 = LocalizedText(fr: "La Popote de Tata Suzanne est née d'une envie simple : tout réunir au même endroit.", en: "La Popote de Tata Suzanne began with a simple wish: to bring everything together in one place.")
        static let idea2 = LocalizedText(fr: "Simplifier. Répartir les tâches. Et créer une communauté où l'on partage ses bonnes idées et ses meilleures recettes.", en: "Make life simpler. Share the jobs. And create a community where everyone shares good ideas and favourite recipes.")
        static let idea3 = LocalizedText(fr: "Parce que bien manger, c'est le début de la bonne santé. Et parce que ces bons moments à table, en famille, avec les enfants, entre amis, c'est ce qui nous rassemble.", en: "Because eating well is the first step towards good health. And because those happy moments around the table, with family, children and friends, are what bring us together.")
        static let chefTitle = LocalizedText(fr: "Pas besoin d'être un chef", en: "You don’t need to be a chef")
        static let chef1 = LocalizedText(fr: "Chez Tata Suzanne, on n'a pas besoin d'être un pro pour devenir un vrai cuistot. Les bonnes recettes se transmettent, se testent, se ratent parfois, se réussissent souvent… et se partagent.", en: "At Tata Suzanne, you don’t need to be a professional to become a proper cook. Good recipes are handed down, tried out, sometimes go wrong, often turn out beautifully… and are shared.")
        static let nextTitle = LocalizedText(fr: "Et demain ?", en: "And what’s next?")
        static let next1 = LocalizedText(fr: "La Popote est un pilote. Peut-être qu'un jour, elle deviendra plus grande. Peut-être qu'elle restera l'app de la famille et des copains. Dans les deux cas, elle sera faite avec le même ingrédient : l'envie de partager.", en: "La Popote is a pilot project. Perhaps one day it will grow bigger. Perhaps it will stay an app for family and friends. Either way, it will be made with the same ingredient: a love of sharing.")
        static let thanks = LocalizedText(fr: "Merci de partager votre tablée avec nous.", en: "Thank you for sharing your table with us.")
        static let bonAppetit = LocalizedText(fr: "Et bon appétit !", en: "Bon appétit !")
        static let browse = LocalizedText(fr: "Découvrir les recettes", en: "Browse the recipes")
    }

    static let faqTitle = LocalizedText(fr: "Questions fréquentes", en: "Frequently asked questions")
    static let contactTitle = LocalizedText(fr: "Nous contacter", en: "Contact us")
    static let contactText = LocalizedText(fr: "Une question, une idée ou un souci ? Touche le bouton ci-dessous : ton application de messagerie s'ouvre avec l'e-mail déjà rédigé.", en: "Have a question, an idea or a problem? Tap the button below: your email app opens with the email already drafted.")
    static let sendEmail = LocalizedText(fr: "Envoyer un e-mail", en: "Send an email")
    static let faq: [(question: LocalizedText, answer: LocalizedText)] = [
        (LocalizedText(fr: "Comment ajouter une recette depuis une photo ou un livre ?", en: "How do I add a recipe from a photo or cookbook?"), LocalizedText(fr: "Dans Recettes, touche « Ajouter », choisis la catégorie puis prends une ou plusieurs photos. Les informations sont lues automatiquement ; vérifie les champs surlignés avant d'enregistrer. Tu peux aussi tout saisir à la main.", en: "In Recipes, tap ‘Add’, choose a category, then take one or more photos. The information is read automatically; check the highlighted fields before saving. You can also enter everything by hand.")),
        (LocalizedText(fr: "Comment fonctionne le partage avec ma famille ?", en: "How does sharing with my family work?"), LocalizedText(fr: "Dans Profil, section « Ma famille », copie un lien d'invitation et envoie-le. Une fois la personne inscrite, le menu et la liste de courses sont partagés et se mettent à jour en direct.", en: "In Profile, under ‘My household’, copy an invitation link and send it. Once they have signed up, the menu and shopping list are shared and update in real time.")),
        (LocalizedText(fr: "Comment générer la liste de courses à partir du menu ?", en: "How do I generate a shopping list from the menu?"), LocalizedText(fr: "Remplis le menu de la semaine, puis ouvre Courses et touche « Générer depuis le menu ». Les quantités sont adaptées au nombre de personnes et les ingrédients identiques sont regroupés.", en: "Fill in your weekly menu, then open Shopping and tap ‘Generate from menu’. Quantities are adjusted for the servings and matching ingredients are grouped together.")),
        (LocalizedText(fr: "Puis-je changer les portions sur le menu sans modifier la recette ?", en: "Can I change the servings on the menu without changing the recipe?"), LocalizedText(fr: "Oui. Le nombre de personnes réglé sur une case du menu ne concerne que ce repas ; la recette d'origine reste inchangée.", en: "Yes. The servings you set in a menu slot only apply to that meal; the original recipe stays unchanged.")),
        (LocalizedText(fr: "Comment noter ou commenter une recette ?", en: "How do I rate or comment on a recipe?"), LocalizedText(fr: "Ouvre la fiche d'une recette : touche les étoiles pour donner une note de 1 à 5, et écris ton avis dans la section Commentaires en bas de page.", en: "Open a recipe: tap the stars to rate it from 1 to 5, and share your thoughts in the Comments section at the bottom of the page.")),
    ]
}
