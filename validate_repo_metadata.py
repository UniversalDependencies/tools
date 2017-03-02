#!/usr/bin/python
"""
This is a git pre-commit hook to verify UD guidelines are met.
Currently implemented:
- Required files (LICENSE.txt, train and dev files) exist
- README file exists and contains metadata section
"""

# python 2/3 compatibility stuff
from __future__ import print_function
from __future__ import unicode_literals
from io import open

import os
import sys
import re
import argparse
import glob

CURRENT_RELEASE = "UD v2.0"


# verify non-README files exist
def verify_req_files(args):
    files = [f for f in os.listdir(args.repodir[0]) if os.path.isfile(os.path.join(args.repodir[0],f))]
    found_train = False
    found_dev = False
    found_license = False
    dev_re = re.compile('^..-ud-dev.conllu$')
    train_re = re.compile('^..-ud-train.conllu$')
    for file_name in files:
        if file_name == 'LICENSE.txt':
            found_license = True
        if dev_re.match(file_name):
            found_dev = True
        if train_re.match(file_name):
            found_train = True

    if not found_license:
        return ("LICENSE.txt is a required file and not present in the repository", 1)
    if not found_train:
        return ("xx-ud-train.conllu is a required file but does not exist in the repository", 1)
    if not found_dev:
        return ("xx-ud-dev.conllu is a required file but does not exist in the repository", 1)
    return (None, 0)


# verify metadata section of README
def verify_readme_metadata(args):
    READMES = ['README.md', 'README.txt']
    CHANGELOG = "changelog"
    REQUIRED_FIELDS = {
        'Documentation status': ['complete', 'partial', 'stub'],
        'Data source': ['automatic', 'semi-automatic', 'manual'],
        'Data available since': ['UD v1.0', 'UD v1.1', 'UD v1.2', 'UD v1.3', 'UD v1.4', 'UD v2.0'],
        'License': ['*'],
        'Genre': ['*'],
        'Contributors': ['*'],
        'Contact': ['*'],
    }

    # look for README
    files = [f for f in os.listdir(args.repodir[0]) if os.path.isfile(os.path.join(args.repodir[0],f)) and f in READMES]
    if len(files) == 0:
        return ("No README file found, expected one of [%s]" % ', '.join(READMES), 1)
    if len(files) > 1:
        return ("More than one README file found, expected one of [%s]" % ', '.join(READMES), 1)

    README = []
    try:
        f = open(os.path.join(args.repodir[0],files[0]), 'rt')
        README = [line.strip() for line in f.readlines()]
    except:
        return ("Failed reading README file %s" % files[0], 1)
    finally:
        f.close()

    # get metadata lines, look for changelog
    metadata = dict()
    prefix_found = False
    postfix_found = False
    changelog_line_num = 0
    for i, line in enumerate(README, start=1):
        if "Machine-readable metadata" in line:
            if prefix_found:
                return ("Line %d: Found more than one metadata section, there should only be one" % i, 2)
            prefix_found = True
            continue
        if "=====" in line:
            postfix_found = True
            continue
        if prefix_found and not postfix_found:
            prop = line.split(": ")
            if len(prop) != 2:
                return ("Line %d: Invalid metadata property line [%s]" % (i, line), 2)
            metadata[prop[0]] = prop[1]
        if line.lower() == CHANGELOG:
            if changelog_line_num > 0:
                return ("Line %d: Found more than one changelog", 3)
            changelog_line_num = i

    if not (prefix_found and postfix_found):
        print("Metadata section not found")
        sys.exit(2)

    # verify metadata
    for (prop_name, prop_value) in metadata.items():
        allowed_list = REQUIRED_FIELDS.pop(prop_name, None)
        if not allowed_list:
            return ("Unknown metadata property %s" % prop_name, 3)
        if allowed_list != ['*']:
            if prop_value not in allowed_list:
                return ("Unknown value for metadata property '%s': %s, can be [%s]"
                      % (prop_name, prop_value, ', '.join(allowed_list)), 3)

    if len(REQUIRED_FIELDS) > 0:
        return ("Metadata is missing the following properties: %s" % ', '.join(REQUIRED_FIELDS.keys()), 3)

    # verify changelog
    if metadata['Data available since'] != CURRENT_RELEASE:
        if changelog_line_num == 0:
            return ("No changelog found, should be present if current version is not an initial release", 4)

    return (None, 0)


if __name__=="__main__":
    parser = argparse.ArgumentParser(description='Validate a UD repository for metadata')
    parser.add_argument('repodir', nargs=1, help='The directory where the repo resides')
    args = parser.parse_args()

    TESTS = [verify_req_files, verify_readme_metadata]

    passed=True
    for test_func in TESTS:
        (reason, err_code) = test_func(args=args)
        if err_code != 0:
            print("*** Repository metadata errors ***")
            print(reason)
            passed=False

    if passed:
        sys.exit(0)
    else:
        sys.exit(1)
