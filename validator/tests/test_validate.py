import os

from validator.validator import *
import futils 


def test_validate_token_ranges():
    #valid_sent = ...
    invalid_sent = futils.path_to_sentence(os.path.join(futils.TEST_CASES_DIR, "invalid-level1-2/invalid-range-format.conllu"))
    #overlapping_sent = ...
    #invalid_overlapping_sent = ...
    #assert len(validate_token_ranges(valid_sent)) == 0
    assert len(validate_token_ranges(invalid_sent)) == 1
    #assert len(validate_token_ranges(overlapping_sent)) == 1
    #assert len(validate_token_ranges(invalid_overlapping_sent)) == 2