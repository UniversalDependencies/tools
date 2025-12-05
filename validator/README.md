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

Instead of printing the errors to STDERR as soon as they are found, you can have them saved in the validation state
and later process them the way you prefer. Note that the number of incidents saved (per category) is limited by
default. This is to save your memory if you do not need to keep the errors (some treebanks have hundreds of thousands
of errors and warnings). By setting `--max-store=0`, this limit is turned off.

```python
import sys
from udtools.argparser import parse_args
from udtools import Validator
from udtools.incident import IncidentType

sys.argv = ['validate.py', '--lang=la', '--quiet', '--max-store=0']
args = parse_args()
validator = Validator(lang='la', args=args)
state = validator.validate_files(['la_proiel-ud-train.conllu', 'la_proiel-ud-dev.conllu', 'la_proiel-ud-test.conllu'])
all_errors = []
# Take only errors, skip warnings.
for testclass in state.error_tracker[IncidentType.ERROR].keys():
   for incident in state.error_tracker[IncidentType.WARNING][testclass]:
       all_errors.append(incident)
all_errors.sort(key=lambda incident: incident.testid)
for error in all_errors:
    print(error)
```

The validator has several other entry points in addition to `validate_files()`:

* `validate_file()` takes just one file name (path), reads that file and tests its validity. If the file name is '-',
  it is interpreted as reading from STDIN. Note that `validate_files()` calls `validate_file()` for each file in turn,
  then it also calls `validate_end()` to perform checks that can only be done after the whole treebank has been read.
  If you call directly `validate_file()`, you should take care of calling `validate_end()` yourself.
  * `validate_end()` takes just the state from the validation performed so far, and checks that the observations saved
    in the state are not in conflict.
* `validate_file_handle()` takes the object associated with an open file (or `sys.stdin`). Otherwise it is analogous
  to `validate_file()` (and is in fact called from `validate_file()`).
* `validate_sentence()` takes a list of CoNLL-U lines corresponding to one sentence, including the sentence-terminating
  empty line. When called from `validate_file_handle()`, it will have at most one empty line and this will be the last
  line in the list, as it is how the file reader detected the sentence end. However, the method is aware that other
  callers could supply lists with empty lines in the middle, and it will report an error if this happens.

All the `validate_*()` methods mentioned above return a `State` object. All of them can optionally take a `State` from
previous runs as an argument (named `state`), in which case they will base their decisions on this state, and save
their observations in it, too.

The validator uses data files with specifications of feature values, lemmas of auxiliaries etc. for each language.
These files change more often than the validator code itself, so it is likely that your pip-installed `udtools` does
not have the most up-to-date version. Therefore, you may want to have a local copy of the tools repository, regularly
update it by calling `git pull`, and tell the validator where to load the data files from (instead of its installation
location):

```python
validator = Validator(lang='la', datapath='/my/copy/of/ud/tools/data')
```

# TO ADD

how to run only some tests?
how to add your own tests? inheritance
