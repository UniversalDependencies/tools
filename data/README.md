This folder contains internal data needed by the UD validate script.

DO NOT EDIT ANY JSON FILES IN THIS FOLDER!

You could temporarily disrupt the function of the validator. And your changes would be later
overwritten by the validation-documentation system. See the
[documentation](https://universaldependencies.org/release_checklist.html#validation)
on how to enable specific features and relation types in individual languages.

As of UD release 2.8, certain data types for the validation are still registered directly here
and you can edit them here if you need to modify them:
* `edeprel.xx` – list of relations that are permitted in DEPS but not in DEPREL for language xx
* `tokens_w_space.xx` – list of regular expressions describing permitted exceptions where a word
  may contain a space in language xx

In the future, the method of registering these data types will probably change as well.
