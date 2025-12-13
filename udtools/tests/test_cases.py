import os
import argparse
from validator import cli
from validator.utils import THIS_DIR

TEST_CASES_DIR = os.path.join(os.path.dirname(os.path.realpath(os.path.abspath(__file__))), "test-cases")

CONFIG = {
    "quiet": False,
    "max_err": 20, 
    "single_root": True,
    "check_tree_text": True,
    "check_space_after": True,
    "check_coref": False,
    "data_folder": os.path.normpath(os.path.join(THIS_DIR,"../../../data")),
    "format": "LOG",
    "dest": "-",
    "explanations": False,
    "lines_content": False,
    "config_file": os.path.realpath(os.path.join(THIS_DIR, "../../docs/example_working.yaml"))
}

def general_test_cases(folder_name, expected_value, level=1):
    CONFIG["level"] = level
    cases_dir = os.path.join(TEST_CASES_DIR, folder_name)
    for case in os.listdir(cases_dir):
        case_path = os.path.join(cases_dir,case)
        if level > 3:
            CONFIG["lang"] = case.split("_")[0]
        else:
            CONFIG["lang"] = "ud"
        CONFIG["input"] = [case_path]
        assert cli._validate(argparse.Namespace(**CONFIG)) == expected_value

def test_valid_cases():
    general_test_cases("valid", 0, level=2)

def test_invalid_lv12_cases():
    general_test_cases("invalid-level1-2", 1, level=2)

#def test_invalid_lv3_cases():
#    general_test_cases("invalid-level3", 1, level=3)
#
#def test_invalid_lv45_cases():
#    general_test_cases("invalid-level4-5", 1, level=5)
