# quick-and-dirty functions just for testing

import os

import validator.utils as utils

TEST_CASES_DIR = os.path.join(os.path.dirname(os.path.realpath(os.path.abspath(__file__))), "test-cases")

# assumes CoNLL-like formatting
def block_to_sentence(string):
    lines = string.split("\n")
    sentence = []
    for line in lines:
        if utils.is_whitespace(line) or line.startswith("#"):
            continue
        sentence.append(line.split("\t"))
    return sentence

# assumes only one sentence (as in all test cases)
def path_to_sentence(path):
    with open(path) as handle:
        txt = handle.read()
    return block_to_sentence(txt)