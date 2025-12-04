# UD Tools

This package contains Python tools for [Universal Dependencies](https://universaldependencies.org/).

## The official UD/CoNLL-U validator

Reads a CoNLL-U file and verifies that it complies with the UD specification. For more details on UD validation, visit
[the description](https://universaldependencies.org/contributing/validation.html) on the UD website.

The most up-to-date version of the validator always resides in the master branch of the
[tools](https://github.com/UniversalDependencies/tools) repository on GitHub. It is possible to run the script
`validate.py` from your local copy of the repository even without installing the `udtools` package via pip.
Nevertheless, you will need a few third-party modules the validator depends on. You can install them like this:
`pip install -r requirements.txt`.

If the root folder of the tools repository is in your system `PATH`, you do not have to be in that folder when
launching the script:

```
cat la_proiel-ud-train.conllu | python validate.py --lang la --max-err=0
```

You can run `python validate.py --help` for a list of available options.

### Invoking validation from your Python program

To use the validator from your Python code, first install `udtools` (possibly after creating and activating a virtual
environment). This should give you access to a fairly recent version of the validator but it will not necessarily be
the authoritative version, as it may lack some modifications of the language-specific data.
`pip install --upgrade udtools`

```python
from udtools import Validator

validator = Validator(lang='la')
state = validator.validate_files(['la_proiel-ud-train.conllu', 'la_proiel-ud-dev.conllu', 'la_proiel-ud-test.conllu'])
print(state)
```

The state is an object with various pieces of information collected during the validation run. Its string
representation is a summary of the warnings and errors found, as well as the string "*** PASSED ***" or
"*** FAILED ***". You can also use the state in a boolean context (condition), where "passed" evaluates as `True` and
"failed" as `False`. Note however that the default behavior of the validator is still to print errors and warnings to
STDERR as soon as they are detected. To suppress printing, the only possibility at present is to supply the `--quiet`
option as if it came from the command line:

```python
import sys
from udtools.argparser import parse_args
from udtools import Validator

sys.argv = ['validate.py', '--lang=la', '--quiet']
args = parse_args()
validator = Validator(lang='la', args=args)
state = validator.validate_files(['la_proiel-ud-train.conllu', 'la_proiel-ud-dev.conllu', 'la_proiel-ud-test.conllu'])
if state:
    print('Yay!')
else:
    print('Oh no ☹')
```
