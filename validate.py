#! /usr/bin/env python3
# Original code (2015) by Filip Ginter and Sampo Pyysalo.
# DZ 2018-11-04: Porting the validator to Python 3.
# DZ: Many subsequent changes. See the git history.
import sys
import argparse
# Import the Validator class from the package subfolder regardless whether it
# is installed as a package.
# caution: path[0] is reserved for script path (or '' in REPL)
#sys.path.insert(1, 'validator/src/validator')
from validator.src.validator.validate import Validator



#==============================================================================
# Argument processing.
#==============================================================================


def build_argparse():
    """
    Builds the argument parser for the validation script.

    Returns
    -------
    opt_parser : argparse.ArgumentParser
        The parser object. Call its method parse_args().
    """
    opt_parser = argparse.ArgumentParser(description="CoNLL-U validation script. Python 3 is needed to run it!")

    io_group = opt_parser.add_argument_group("Input / output options")
    io_group.add_argument('--quiet',
                          dest="quiet", action="store_true", default=False,
                          help="""Do not print any error messages.
                          Exit with 0 on pass, non-zero on fail.""")
    io_group.add_argument('--max-err',
                          action="store", type=int, default=20,
                          help="""How many errors to output before exiting? 0 for all.
                          Default: %(default)d.""")
    io_group.add_argument('--max-store',
                          action="store", type=int, default=20,
                          help="""How many errors to save when collecting errors. 0 for all.
                          Default: %(default)d.""")
    io_group.add_argument('input',
                          nargs='*',
                          help="""Input file name(s), or "-" or nothing for standard input.""")

    list_group = opt_parser.add_argument_group("Tag sets", "Options relevant to checking tag sets.")
    list_group.add_argument("--lang",
                            action="store", required=True, default=None,
                            help="""Which langauge are we checking?
                            If you specify this (as a two-letter code), the tags will be checked
                            using the language-specific files in the
                            data/directory of the validator.""")
    list_group.add_argument("--level",
                            action="store", type=int, default=5, dest="level",
                            help="""Level 1: Test only CoNLL-U backbone.
                            Level 2: UD format.
                            Level 3: UD contents.
                            Level 4: Language-specific labels.
                            Level 5: Language-specific contents.""")

    coref_group = opt_parser.add_argument_group("Coreference / entity constraints",
                                                "Options for checking coreference and entity annotation.")
    coref_group.add_argument('--coref',
                             action='store_true', default=False, dest='check_coref',
                             help='Test coreference and entity-related annotation in MISC.')
    return opt_parser


def parse_args(args=None):
    """
    Creates an instance of the ArgumentParser and parses the command line
    arguments.

    Parameters
    ----------
    args : list of strings, optional
        If not supplied, the argument parser will read sys.args instead.
        Otherwise the caller can supply list such as ['--lang', 'en'].

    Returns
    -------
    args : argparse.Namespace
        Values of individual arguments can be accessed as object properties
        (using the dot notation). It is possible to convert it to a dict by
        calling vars(args).
    """
    opt_parser = build_argparse()
    args = opt_parser.parse_args(args=args)
    # Level of validation.
    if args.level < 1:
        print(f'Option --level must not be less than 1; changing from {args.level} to 1',
              file=sys.stderr)
        args.level = 1
    # No language-specific tests for levels 1-3.
    # Anyways, any Feature=Value pair should be allowed at level 3 (because it may be language-specific),
    # and any word form or lemma can contain spaces (because language-specific guidelines may allow it).
    # We can also test language 'ud' on level 4; then it will require that no language-specific features are present.
    if args.level < 4:
        args.lang = 'ud'
    if args.input == []:
        args.input.append('-')
    return args



#==============================================================================
# The main function.
#==============================================================================



def main():
    args = parse_args()
    validator = Validator(lang=args.lang, level=args.level, args=args)
    state = validator.validate_files(args.input)
    # Summarize the warnings and errors.
    summary = str(state)
    if not args.quiet:
        print(summary, file=sys.stderr)
    if state.passed():
        return 0
    else:
        return 1

if __name__=="__main__":
    errcode = main()
    sys.exit(errcode)
