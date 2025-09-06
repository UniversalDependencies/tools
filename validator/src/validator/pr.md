# validator.py - the remake
This PR is a substantial refactoring/upgrade of `validate.py` according to the goals listed in #113. 

## Summary of changes

### New configuration file 
(an example is available in `docs/example_config.yaml`)

The file is divided into 8 parts: `file`, `block`, `line`, `token_lines`, `comment_lines`, `cols`, `tree`, `node` (this is still subject to changes).

Each part lists in the right order the checks that should be performed while reading and subsequently parsing the file.
Each entry has the following format:
		
		check_name:            # function name
			level: n           # integer from 0 to 5
			depends_on:
				- test_id_1    # string that uniquely identifies test
				- test_id_2
				- ...
				- test_id_n

This means that this check is performed at level `n` only if none of the test_ids mentioned in the `depends_on` list has failed for the same block/line/tree/...

In case the check cannot be performed because of previous failures, a `Warning` is added to the `incidents`.
This is __not__ the case in the current validation script, but we think it is a rather uncontroversial improvement.

### Modules
(there are also a few other Python files but they will not be part of the final PR)

#### `cli.py`
A command-line interface similar to `validator.py`'s (not fully functional yet), with a few additional flags:

- `--data-folder` > folder where all the json data concerning specifics of UD are stored (i.e., currently `data`)
- `--config-file` > path of `.yaml` file containing the configuration for a specific run of the validator
- `--format` > "LOG" (the current format) or "json" (agreed upon with @bguil). `LOG` is the default and _will_ mimic current behavior, but makes it more personalizable as everything is dumped on a logging file and a level can be set for the console
- `--dest` > destination for the output (stdin/out or path to file)
- `--explanations` > flag to enable longer explanations in the output
- `--lines-content` > flag to display the portions of the files that triggered the errors in the output (requested by @bguil) (please suggest a better name for this!)

#### `validate.py`
This module contains:

- the entry point(s) for the validator (named `validate_xxx`). The most important of these functions is `validate_file()` (see below)
- a library of more or less atomic checks (originally called `validate_xxx`, now renamed to `check_xxx`), all returning a list of [`Incident`](#incidentpy)s (an empty list means that the input passed the check)

The function `validate_file` relies on the `run_checks` function, which takes as parameters:
- the name of a specific `check_xxx` function and the test IDs of the checks it depends on (from the configuration file)
- the required parameters for the `check_xxx` function
- current list of `Incident`s and 
- the validation `State`

It runs the appropriate library function by passing it the parameters and extends the list of incidents.

`validate_file` opens a single filepath, reads blocks of data (sentence candidates) from it and performs the checks.
These are defined to be either file-level, block-level, line-level, token-level, tree-level etc... (this is still subject to changes), and these are run in order (i.e., block-level checks are run before line-level ones).

Checks are not selected by level yet (based on the command-line argument), but we kept the information both in each `Incident` and in the configuration file.

#### `incident.py`
This module contains the "abstract" class `Incident` and its two subclasses `Error` and `Warning`, as well the enum `TestClass`, which replaces testclass strings.

#### `specifications.py`
Contains a `UDSpecs` class that is meant to store all UD-specific information such as list of admitted `upos` or language-specific constraints.

In the future, we might consider adding an abstract class so that more format-specific classes with the same behavior could be integrated (e.g., SUDSpecs).

#### `loaders.py`
Library of functions to load data stored typically in `json` or `yaml` format. These are used to load all UD specific information which is stored in a `UDSpecs` object.

#### `compiled_regex.py`
Compiled regular expressions (mostly unchanged from the `CompiledRegexes` class).

#### `output_utils.py`
Helpers for output, including functions to generate extended explanations (originally part of the `State` class).

#### `utils.py`
Other helper functions.

### Other stuff

#### `pyproject.toml`
File used to manage the python package, listing dependencies, metadata, command line entry points and more to come. Relies on `hatchling`.

#### `logs/`
Output folder for log files.

#### `docs/`
Currently used to store various notes, destination folder for documentation in the future.

#### `tests/`
Test scripts are meant to be run with the `pytest` command:

- `test_cases.py`, which executes the tests stored in the subfolder `test-cases/` (which includes all pre-existing test, plus a few new ones)
- `test_regex.py`: new tests for compiled regular expressions
- `test_utils.py`: utils functions 
- `test_validate.py`: new tests for some atomic checks. These are meant to be replaced by new, ad-hoc test cases

## TODO before this PR is merged
(feel free to add to this list and/or let us know if you feel up to lend us a hand!)

- [ ] move `conllu_spec.yaml` to data folder
- [ ] restore all currently disabled CLI functionalities
- [ ] fully support new options (at least `--lines-content` and `--explanations` are not used yet)
- [ ] complete `valdidate.py` with the missing `check_xxx`s
- [ ] finalize the default config file (so that the new validator runs the same checks as the old one)
- [ ] make `state` a dataclass 
- [ ] configure logging so that it is still possible to display errors as they happen, especially in large treebanks (requested by @LeonieWeissweiler)

## Future work
(feel free to edit this list as well, but maybe not too much, unless you want to help with the implementation!)

- produce PyPI package
- implement an additional `validate_sentence` entry point for validation of individual sentences (requested by @bguil)
- add missing test cases
- reorganize the test cases so that they match `testid`s and list which tests should fail as metadata
- setup CI (both to run the tests and potentially to publish a new version of the package on PyPI for each new tag)

