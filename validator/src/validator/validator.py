import validator.utils as utils
import validator.compiled_regex as crex
from validator.incident import Error, Warning, TestClass

def validate_token_ranges(sentence):
    """
    Checks that the word ranges for multiword tokens are valid.

    Parameters
    ----------
    sentence : list
        A list of lists representing a sentence in tabular format.

    Returns
    -------
    _ : list
        A list of Incidents (empty if validation is successful). 
    """
    covered = set()
    incidents = []
    for cols in sentence:
        if not "-" in cols[utils.ID]:
            continue
        m = crex.mwtid.fullmatch(cols[utils.ID])
        if not m: 
            incidents.append(Error(
                testid="invalid-word-interval",
                message=f"Spurious word interval definition: '{cols[utils.ID]}'."
            ))
            continue
        start, end = m.groups()
        start, end = int(start), int(end)
        # Do not test if start >= end: 
        # This is tested in validate_id_sequence().
        if covered & set(range(start, end+1)):
            incidents.append(Error(
                testid='overlapping-word-intervals',
                message=f'Range overlaps with others: {cols[utils.ID]}'))
        covered |= set(range(start, end+1))
    return incidents