#! /usr/bin/env python3
# Original code (2015) by Filip Ginter and Sampo Pyysalo.
# DZ 2018-11-04: Porting the validator to Python 3.
# DZ: Many subsequent changes. See the git history.
# 2025-08-31: Refactoring by @AngledLuffa
# 2025-09: Refactoring by @harisont and @ellepannitto

import sys
import argparse
import os
import yaml
import functools

import logging

# According to https://stackoverflow.com/questions/1832893/python-regex-matching-unicode-properties,
# the regex module has the same API as re but it can check Unicode character properties using \p{}
# as in Perl.
import regex as re

import validator.logging_utils as logging_utils

import validator.validate_lib as VLib
import validator.specifications as specifications
import validator.utils as utils
import validator.validate as vlib

logger = logging.getLogger(__name__)
logging_utils.setup_logging(logger)

def _validate(args):

	ud_specs = specifications.UDSpecs(args.data_folder)
	validation_fun = vlib.validate

	if args.config_file:
		with open(args.config_file) as cfg_f:
			cfg = yaml.safe_load(cfg_f)
			validation_fun = functools.partial(vlib.validate_cfg, cfg_obj=cfg)
	# print("@@@@@@@@@@@@@@@@@@@@@@@@", args.input)
	for incidents in validation_fun(args.input):
		if not incidents:
			print(">>>>>>>>> PASSED!")
		else:
			print(">>>>>>>>> FAILED:", incidents)

	# Summarize the warnings and errors.
	passed = True
	nerror = 0
	#if state.error_counter:
	#    for k, v in sorted(state.error_counter.items()):
	#        if k == 'Warning':
	#            errors = 'Warnings'
	#        else:
	#            errors = k+' errors'
	#            nerror += v
	#            passed = False
	#        if not args.quiet:
	#            print(f'{errors}: {v}', file=sys.stderr)
	## Print the final verdict and exit.
	#if passed:
	#    if not args.quiet:
	#        print('*** PASSED ***', file=sys.stderr)
	#    return 0
	#else:
	#    if not args.quiet:
	#        print(f'*** FAILED *** with {nerror} errors', file=sys.stderr)
	#    return 1

def main():

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

	tree_group = opt_parser.add_argument_group("Tree constraints",
												"Options for checking the validity of the tree.")
	tree_group.add_argument("--multiple-roots",
							action="store_false", default=True, dest="single_root",
							help="""Allow trees with several root words
							(single root required by default).""")

	meta_group = opt_parser.add_argument_group("Metadata constraints",
												"Options for checking the validity of tree metadata.")
	meta_group.add_argument("--no-tree-text",
							action="store_false", default=True, dest="check_tree_text",
							help="""Do not test tree text.
							For internal use only, this test is required and on by default.""")
	meta_group.add_argument("--no-space-after",
							action="store_false", default=True, dest="check_space_after",
							help="Do not test presence of SpaceAfter=No.")

	coref_group = opt_parser.add_argument_group("Coreference / entity constraints",
												"Options for checking coreference and entity annotation.")
	coref_group.add_argument('--coref',
							action='store_true', default=False, dest='check_coref',
							help='Test coreference and entity-related annotation in MISC.')

	config_group = opt_parser.add_argument_group("Directories and paths", "TBD") # TODO better helper
	config_group.add_argument('--data-folder', default=os.path.normpath(os.path.join(utils.THIS_DIR,"../../../data")))
	config_group.add_argument('--config-file', type=str)


	opt_parser.set_defaults(func=_validate)
	args = opt_parser.parse_args() #Parsed command-line arguments

	if "func" not in args:
		opt_parser.print_usage()
		exit()

	logger.info("Arguments: \n%s", logging_utils.pprint(vars(args)))

	args.func(args)


if __name__ == "__main__":
	main()