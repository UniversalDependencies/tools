#! /usr/bin/env python3
# Original code (2015) by Filip Ginter and Sampo Pyysalo.
# DZ 2018-11-04: Porting the validator to Python 3.
# DZ: Many subsequent changes. See the git history.
# 2025-08-31: Refactoring by @AngledLuffa
# 2025-09: Refactoring by @harisont and @ellepannitto
import sys
from udtools.argparser import parse_args_validator, parse_args_scorer
from udtools.validator import Validator
from udtools.udeval import evaluate_wrapper, build_evaluation_table



#==============================================================================
# The main function.
#==============================================================================



def main():
    args = parse_args_validator()
    validator = Validator(lang=args.lang, level=args.level, max_store=10, args=args)
    state = validator.validate_files(args.input)
    # Summarize the warnings and errors.
    summary = str(state)
    if not args.quiet:
        print(summary, file=sys.stderr)
    if state.passed():
        return 0
    else:
        return 1



def main_eval():
    # Parse arguments
    args = parse_args_scorer()

    # Evaluate
    evaluation = evaluate_wrapper(args)
    results = build_evaluation_table(evaluation, args.verbose, args.counts, args.enhanced)
    print(results)
    return 0



if __name__=="__main__":
    errcode = main()
    sys.exit(errcode)
