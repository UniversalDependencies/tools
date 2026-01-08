# Original code (2015) by Filip Ginter and Sampo Pyysalo.
# DZ 2018-11-04: Porting the validator to Python 3.
# DZ: Many subsequent changes. See the git history.
import sys
import argparse


#==============================================================================
# Argument processing for validate.py.
#==============================================================================


def build_argparse_validator():
    opt_parser = argparse.ArgumentParser(description="CoNLL-U validation script. Python 3 is needed to run it!")

    io_group = opt_parser.add_argument_group("Input / output options")
    io_group.add_argument('-q', '--quiet',
                          dest='quiet', action="store_true", default=False,
                          help="""Do not print anything (errors, warnings, summary).
                          Exit with 0 on pass, non-zero on fail.""")
    io_group.add_argument('--no-warnings',
                          dest='no_warnings', action='store_true', default=False,
                          help="""Print only errors but no warnings.
                          The final summary will still include the number of warnings, although they were not printed.""")
    io_group.add_argument('-e', '--exclude',
                          nargs='+',
                          help="""One or more ids of tests whose incidents should not be printed.
                          For example: --exclude missing-sent-id invalid-sent-id.
                          The tests will still be performed and resulting incidents counted in the final summary.""")
    io_group.add_argument('-i', '--include-only',
                          nargs='+',
                          help="""One or more ids of tests whose incidents should be printed.
                          For example: --include-only missing-sent-id invalid-sent-id.
                          Any other incidents will not be printed.
                          The tests will still be performed and resulting incidents counted in the final summary.""")
    io_group.add_argument('--max-err',
                          action='store', type=int, default=20,
                          help="""How many incidents to print per test class? 0 for all.
                          Default: %(default)d.""")
    io_group.add_argument('input',
                          nargs='*',
                          help="""Input file name(s), or "-" or nothing for standard input.""")

    test_group = opt_parser.add_argument_group("Test configuration options")
    test_group.add_argument('--lang',
                            action='store', required=True, default=None,
                            help="""Which langauge are we checking (ISO 639 code)?
                            Determines the language-specific lists of features,
                            auxiliaries, relation subtypes etc. This is a required
                            argument. Use "ud" as the value if you only want to
                            test the universal part of the UD guidelines.""")
    test_group.add_argument('--level',
                            action='store', type=int, default=5, dest="level",
                            help="""Level 1: Test only CoNLL-U backbone.
                            Level 2: UD format.
                            Level 3: UD contents.
                            Level 4: Language-specific labels.
                            Level 5 (default): Language-specific contents.""")
    test_group.add_argument('--coref',
                            action='store_true', default=False, dest='check_coref',
                            help='Test coreference and entity-related annotation in MISC.')
    return opt_parser



def parse_args_validator(args=None):
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
    opt_parser = build_argparse_validator()
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
# Argument processing for eval.py.
#==============================================================================



def parse_args_scorer(args=None):
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
    parser = argparse.ArgumentParser()
    parser.add_argument('gold_file', type=str,
                        help='Name of the CoNLL-U file with the gold data.')
    parser.add_argument('system_file', type=str,
                        help='Name of the CoNLL-U file with the predicted data.')
    parser.add_argument('--verbose', '-v', default=False, action='store_true',
                        help='Print all metrics.')
    parser.add_argument('--counts', '-c', default=False, action='store_true',
                        help='Print raw counts of correct/gold/system/aligned words instead of precision/recall/F1 for all metrics.')
    parser.add_argument('--no-enhanced', dest='enhanced', action='store_false', default=True,
                        help='Turn off evaluation of enhanced dependencies.')
    parser.add_argument('--enhancements', type=str, default='0',
                        help='Level of enhancements in the gold data (see guidelines) 0=all (default), 1=no gapping, 2=no shared parents, 3=no shared dependents 4=no control, 5=no external arguments, 6=no lemma info, combinations: 12=both 1 and 2 apply, etc.')
    parser.add_argument('--no-empty-nodes', default=False,
                        help='Empty nodes have been collapsed (needed to correctly evaluate enhanced/gapping). Raise exception if an empty node is encountered.')
    parser.add_argument('--multiple-roots-okay', default=False, action='store_true',
                        help='A single sentence can have multiple nodes with HEAD=0.')
    args = parser.parse_args(args=args)
    return args
