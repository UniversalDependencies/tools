# UD Tools

This package contains Python tools for [Universal Dependencies](https://universaldependencies.org/):

* The official UD/CoNLL-U validator
* The official UD parsing scorer from the CoNLL (2017, 2018) and IWPT (2020, 2021) shared tasks

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
"*** FAILED ***". You can also use the state in a boolean context (condition), where “passed” evaluates as `True` and
“failed” as `False`. Note however that the default behavior of the validator is still to print errors and warnings to
STDERR as soon as they are detected. To suppress printing, add `output=None` to the arguments when constructing the
validator. (The default value of this argument is `sys.stderr`. You could also set it to `sys.stdout` or to a handle
of a file open for writing.)

```python
from udtools import Validator

validator = Validator(lang='la', output=None)
state = validator.validate_files(['la_proiel-ud-train.conllu', 'la_proiel-ud-dev.conllu', 'la_proiel-ud-test.conllu'])
if state:
    print('Yay!')
else:
    print('Oh no ☹')
```

Alternatively, you could simulate supplying the `--quiet` option as if it came from the command line:

```python
import sys
from udtools.argparser import parse_args_validator
from udtools import Validator

sys.argv = ['validate.py', '--lang=la', '--quiet']
args = parse_args_validator()
validator = Validator(lang='la', args=args)
state = validator.validate_files(['la_proiel-ud-train.conllu', 'la_proiel-ud-dev.conllu', 'la_proiel-ud-test.conllu'])
if state:
    print('Yay!')
else:
    print('Oh no ☹')
```

Instead of printing the errors to STDERR as soon as they are found, you can have them saved in the validation state
and later process them the way you prefer. Note that if you use the argparser approach from the previous example, the
number of incidents saved (per category) is limited by default. This is to save your memory if you do not need to keep
the errors (some treebanks have hundreds of thousands of errors and warnings). By setting `--max-store=0`, this limit
is turned off. However, the default limit is set in the argparser, so if you use the simpler approach with
`output=None` and you do not invoke the argparser for other reasons, no limit will be imposed.

```python
from udtools import Validator

validator = Validator(lang='la', output=None)
state = validator.validate_files(['la_proiel-ud-train.conllu', 'la_proiel-ud-dev.conllu', 'la_proiel-ud-test.conllu'])
# Take only errors, skip warnings.
all_errors = [x for x in state.error_tracker if x.is_error()]
all_errors.sort(key=lambda incident: incident.testid)
for error in all_errors:
    print(error)
```

### Entry points

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

### Printing incidents in JSON

Instead of prose error messages suitable for human users, you can print the error descriptions in JSON so it can be
easily read and processed by an external application.

```python
from udtools import Validator

validator = Validator(lang='la', output=None)
state = validator.validate_files(['la_proiel-ud-train.conllu', 'la_proiel-ud-dev.conllu', 'la_proiel-ud-test.conllu'])
incidents = sorted(state.error_tracker, key=lambda incident: incident.testid)
print('[')
print(',\n'.join([incident.json() for incident in incidents]))
print(']')
```

### Selecting only some tests

UD defines several
[levels of validity](https://universaldependencies.org/contributing/validation-rules.html#levels-of-validity)
of CoNLL-U files. By default, validity on the highest level 5 is required; this is the level that UD treebanks must
pass in order to be released as part of Universal Dependencies. It is possible to request a lower level of validity,
for example, only the backbone file structure can be checked, omitting any linguistic checks of the annotation
guidelines. When invoking `validate.py` from the command line, the numeric option `--level` (e.g., `--level 1`)
tells the validator to skip tests on levels 2 and above. The same argument can be given directly to the constructor
of the `Validator` class. The lowest level is not specific to individual languages, so we can give the generic
language "ud" instead.

```python
validator = Validator(lang='ud', level=1)
```

One may want to filter the tests along various other dimensions: errors only (skipping warnings); selected test classes
(FORMAT, MORPHO, SYNTAX, ENHANCED, METADATA etc.); individual test ids (e.g., `obl-should-be-nmod`). It is always
possible to do what we showed above, i.e., collecting all incidents, then processing them and showing only the selected
ones. However, this approach has its drawbacks: We waste time by running tests whose results we do not want to see;
for large treebanks it is not practical to postpone showing first results until the whole treebank is processed; and
it may be also quite heavy to keep all unnecessary incidents in memory.

You may try to get around this by implementing your own alternative to `validate_sentence()` and call individual tests
directly. There are some dangers though, which you should consider first:

* The tests are not documented at present, so you have to consult the source code. The relevant functions are methods
  of `Validator` and their names start with `check_` (as opposed to `validate_`, which signals the better documented
  entry points). Note that one `check_` method may generate multiple different incident types, whose ids are not
  reflected in the name of the method; and a few incidents can even occur outside any `check_` method (e.g., directly
  in a `validate_` method).
* The interface is far from stable. Names of methods may change at any time, as well as the types of incidents they
  generate, the arguments they expect, their return values (if any) or side effects. Some checks only look at
  individual cells in the CoNLL-U tabular format, others expect the fully built tree structure.
* There are dependencies among the tests. Some `check_` methods can be run safely only if other `check_` methods have
  been run previously and did not encounter errors.

### Adding your own tests

You may want to add language-specific consistency tests beyond what the official validator can do (e.g., ensuring that
all personal pronouns have a non-empty value of the `Person` feature), or even treebank/project-specific tests (e.g.,
all tokens should have a valid `Ref` attribute in MISC). One way of doing this would be to derive your own validator
class based on `udtools.Validator`.

```python
from udtools import Validator
from udtools.incident import TestClass, Error

class MyValidator(Validator):

    def validate_sentence(self, lines, state=None):
        state = super().validate_sentence(lines, state)
        self.check_my_own_stuff(state, lines)
        return state

    def check_my_own_stuff(self, state, lines):
        for line in lines:
            if re.match(r'40\t', line):
                Error(
                    state=state, config=self.incfg,
                    level=1,
                    testclass=TestClass.FORMAT,
                    testid='id-40',
                    message="Node ID 40 is not allowed in this treebank."
                ).confirm()

validator = MyValidator(lang='la')
state = validator.validate_files(['la_proiel-ud-train.conllu', 'la_proiel-ud-dev.conllu', 'la_proiel-ud-test.conllu'])
print(state)
```



## The official UD parsing scorer

Reads two CoNLL-U files: gold standard (annotated manually) and system output (predicted by a parsing model). Both
files must be valid at least at level 2, and their underlying text must be compatible, i.e., it can differ in
whitespace but not in other characters. The scorer evaluates similarity of the system output to the gold standard
by computing several metrics that were defined in the UD parsing shared tasks (CoNLL 2017 & 2018, IWPT 2020 & 2021).

To load two files and evaluate their similarity without enhanced dependencies (i.e., in the style of the CoNLL shared
tasks), you can do the following.

```python
from udtools.udeval import load_conllu_file, evaluate, build_evaluation_table

gold_ud = load_conllu_file('gold.conllu')
system_ud = load_conllu_file('system.conllu')
evaluation = evaluate(gold_ud, system_ud)
results = build_evaluation_table(evaluation, verbose=True)
print(results)
```

To use the command line interface and arguments, you can use `parse_args_scorer()` as shown below. If you supply
`--help` as the only argument, you will get the description of the options available.

```python
from udtools.argparser import parse_args_scorer
from udtools.udeval import evaluate_wrapper, build_evaluation_table

args = parse_args_scorer()
evaluation = evaluate_wrapper(args)
results = build_evaluation_table(evaluation, args.verbose, args.counts, args.enhanced)
print(results)
```
