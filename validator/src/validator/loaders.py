import os
import json

import yaml
import regex as re

def load_conllu_spec(spec_path):
    with open(spec_path, encoding="utf-8") as spec_handle:
        return yaml.safe_load(spec_handle)


def load_json_data_set(filename, key=None):
    """
    Loads the set of permitted tags from a json file.
    If a key is specified, it returns only the selected key.
    """
    with open(filename, encoding="utf-8") as fin:
        res = json.load(fin)

    if key:
        return set(res[key])
    else:
        return res


def load_json_data(filename, key=None):
    """
    Loads permitted tags from a json file.
    If a key is specified, it returns only the selected key.
    """
    with open(filename, encoding="utf-8") as fin:
        res = json.load(fin)
    if key:
        return res[key]
    else:
        return res

def load_combinations(filename):

    res = {}
    content = load_json_data(filename, "expressions")
    for lang_code, lang_dicts in content.items():
        lang_regexes = list(sorted(lang_dicts.keys()))
        combination = '('+'|'.join(lang_regexes)+')'
        compiled_regex = re.compile(combination)
        res[lang_code] = (combination, compiled_regex)

    return res


