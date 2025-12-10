#! /usr/bin/env python3
# Original code (2015) by Filip Ginter and Sampo Pyysalo.
# DZ 2018-11-04: Porting the validator to Python 3.
# DZ: Many subsequent changes. See the git history.
import sys
# Import the Validator class from the package subfolder regardless whether it
# is installed as a package.
from udtools.src.udtools.validator import Validator
from udtools.src.udtools.argparser import parse_args_validator



#==============================================================================
# The main function.
#==============================================================================



def main():
    args = parse_args_validator()
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
