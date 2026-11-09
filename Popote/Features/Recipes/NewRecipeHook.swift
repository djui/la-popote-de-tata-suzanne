import SwiftUI

// Entry points into the new-recipe wizard and the edit form (owned by the newrecipe builder).

@MainActor
func newRecipeEntry(startWithPhoto: Bool) -> AnyView {
    AnyView(NewRecipeFlow(startWithPhoto: startWithPhoto))
}

@MainActor
func editRecipeEntry(recipeId: UUID) -> AnyView {
    AnyView(EditRecipeView(recipeId: recipeId))
}
