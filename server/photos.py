"""Compatibility entry point: retains references without downloading photos."""
from .online_photos import online_recipe_data


def hydrate_photos(recipe, *, skip_urls=None):
    normalized = online_recipe_data(recipe)
    recipe.clear()
    recipe.update(normalized)
