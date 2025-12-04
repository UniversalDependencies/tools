# UD Tools

This package contains Python tools for [Universal Dependencies](https://universaldependencies.org/).

## The official UD/CoNLL-U validator

Reads a CoNLL-U file and verifies that it complies with the UD specification. For more details on UD validation, visit
[the description](https://universaldependencies.org/contributing/validation.html) on the UD website.

The script runs under Python 3 and needs the third-party module **regex** and **udapi**
(at least version 0.5.0; and udapi has its own dependencies, **colorama** and **termcolor**).
If you do not have the required modules, install them like this:
`pip install -r requirements.txt`.

NOTE: Depending on the configuration of your system, it is possible that both Python 2 and 3 are
installed; then you may have to run `python3` instead of `python`, and `pip3` instead of `pip`.

```
cat la_proiel-ud-train.conllu | python validate.py --lang la --max-err=0
```

You can run `python validate.py --help` for a list of available options.
