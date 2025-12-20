#! /usr/bin/env python3
# Original code (2015) by Filip Ginter and Sampo Pyysalo.
# DZ 2018-11-04: Porting the validator to Python 3.
# DZ: Many subsequent changes. See the git history.
# 2025-08-31: Refactoring by @AngledLuffa
# 2025-09: Refactoring by @harisont and @ellepannitto

import sys
import os
import yaml

import logging

import udtools.logging_utils as logging_utils

import udtools.utils as utils
import udtools.validate as vlib
from udtools.argparser import build_argparse_validator

logger = logging.getLogger(__name__)
logging_utils.setup_logging(logger)


def serialize_output(incidents, output_fhandle, explanations, lines_content):
    for incident in incidents:
        print(incident)
    if not incidents:
        print("*** PASSED ***")
    else:
        print(f"*** FAILED *** with {len(incidents)} error(s)")


def _validate(args):
    out_format = args.format
    dest = args.dest
    explanations = args.explanations
    lines_content = args.lines_content
    if dest == '-':
        dest = sys.stdout
    elif dest == 'stderr':
        dest = sys.stderr
    else:
        dest = open(dest, 'w')
    cfg = yaml.safe_load(open(args.config_file))
    for incidents in vlib.validate(args.input, cfg_obj=cfg):
        if out_format == 'json':
            if incidents:
                print('[', file=dest)
                print(',\n'.join([incident.json() for incident in incidents]), file=dest)
                print(']', file=dest)
        else:
            serialize_output(incidents, dest, explanations, lines_content)
    if len(incidents):
        return 1
    else:
        return 0


def main():
    ###!!! For now, load the options currently supported in master, then add new options here. After complete merge, all options should be handled at one place.
    opt_parser = build_argparse_validator()

    config_group = opt_parser.add_argument_group("Directories and paths", "TBD") # TODO better helper
    config_group.add_argument('--data-folder', default=os.path.normpath(os.path.join(utils.THIS_DIR,"../../../data")))
    config_group.add_argument('--config-file', type=str)

    out_format = opt_parser.add_argument_group("Choices of output formats", "TBD")
    out_format.add_argument('--format', default='LOG', choices=['json', 'LOG'],
                        help='Produce output in desired format')
    out_format.add_argument('--dest', default='-', type=str,
                            help="Output destination")
    out_format.add_argument(
        '--explanations',
        action='store_true',
        default=False,
        help="Include longer explanations.")
    out_format.add_argument(
        '--lines-content', # TODO: better names
        action='store_true',
        default=False,
        help="Include the content of the errored lines in the output.")

    opt_parser.set_defaults(func=_validate)
    args = opt_parser.parse_args() #Parsed command-line arguments

    if "func" not in args:
        opt_parser.print_usage()
        exit()

    logger.info("Arguments: \n%s", logging_utils.pprint(vars(args)))

    args.func(args)


if __name__ == "__main__":
    main()
