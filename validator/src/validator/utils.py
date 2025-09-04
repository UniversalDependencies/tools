import os
import regex as re

from validator.loaders import load_conllu_spec

import validator.compiled_regex as crex

THIS_DIR = os.path.dirname(os.path.realpath(os.path.abspath(__file__)))

CONLLU_SPEC = load_conllu_spec(os.path.join(THIS_DIR, "conllu_spec.yaml"))
COLCOUNT = len(CONLLU_SPEC["columns"])
ID, FORM, LEMMA, UPOS, XPOS, FEATS, HEAD, DEPREL, DEPS, MISC = range(COLCOUNT)
COLNAMES = CONLLU_SPEC["columns"]

def is_whitespace(line):
    """
    Checks whether a given line of text consists exclusively of whitespace.

    Parameters
    ----------
    line : str
        A line of text.

    Returns
    -------
    _ : bool
    """
    return crex.ws.fullmatch(line)

def is_word(cols):
    """
    Checks whether a CoNLL-U line represents a syntactic word by checking that
    its ID field is an integer.

    Parameters
    ----------
    cols : list
        A CoNLL-U line, represented as a list of strings.

    Returns
    -------
    _ : bool
    """
    return crex.wordid.fullmatch(cols[ID])

def is_multiword_token(cols):
    """
    Checks whether a CoNLL-U line represents a MWT by checking that its ID 
    field is a range, e.g. "3-5".

    Parameters
    ----------
    cols : list
        A CoNLL-U line, represented as a list of strings.

    Returns
    -------
    _ : Match|None
    """
    return crex.mwtid.fullmatch(cols[ID])

def is_empty_node(cols):
    """
    Checks whether a CoNLL-U line represents an empty node by checking 
    that its ID field is a floating-point number.

    Parameters
    ----------
    cols : list
        A CoNLL-U line, represented as a list of strings.

    Returns
    -------
    _ : bool
    """
    return crex.enodeid.fullmatch(cols[ID])

def parse_empty_node_id(cols):
    """
    Parses the ID of an empty node into a 2-uple that separates it into its
    integer and decimal part (e.g. "1.2" -> ("1", "2")).

    Parameters
    ----------
    cols : list
        A CoNLL-U line, represented as a list of strings.

    Returns
    -------
    _ : tuple
        A 2-uple of strings, e.g. ("1", "2").
    """
    m = crex.enodeid.fullmatch(cols[ID])
    # ! REMOVE/CHANGE
    assert m, 'parse_empty_node_id with non-empty node'
    return m.groups()

def shorten(string):
    """
    Truncates a string to 25 characters.

    Parameters
    ----------
    cols : str

    Returns
    -------
    _ : str
    """
    return string if len(string) < 25 else string[:20]+'[...]'

# ! proposal: rename to drop_subtype
def lspec2ud(deprel):
    """
    Drops the relation subtype from the given DEPREL (e.g. "nmod" -> "nmod"; 
    "nmod:poss" -> "nmod").

    Parameters
    ----------
    deprel : str
        A DEPREL (possibly with subtypes, such as "nmod:poss").

    Returns
    -------
    _ : str
        A DEPREL without subtypes, such as "nmod".
    """
    return deprel.split(':', 1)[0]

def formtl(node):
    """
    Joins a node's form and transliteration together in a space-separated 
    string, e.g. "ኧሁ 'ăhu".

    Parameters
    ----------
    node : udapi.core.node.Node
        A word node.

    Returns
    -------
    _ : str
        A string in "FORM Translit" format, e.g. "ኧሁ 'ăhu".
    """
    x = node.form
    if node.misc['Translit'] != '':
        x += ' ' + node.misc['Translit']
    return x

def lemmatl(node):
    """
    Joins a node's lemma and its transliteration together in a space-separated 
    string, e.g. "እኔ 'əne".

    Parameters
    ----------
    node : udapi.core.node.Node
        A word node.

    Returns
    -------
    _ : str
        A string in "LEMMA LTranslit" format, e.g. "እኔ 'əne".
    """
    x = node.lemma
    if node.misc['LTranslit'] != '':
        x += ' ' + node.misc['LTranslit']
    return x

def get_alt_language(node):
    """
    In code-switching analysis of foreign words, an attribute in the MISC column
    will hold the code of the language of the current word. Certain tests will
    then use language-specific lists from that language instead of the main
    language of the document. This function returns the alternative language
    code if present, otherwise it returns None.

    Parameters
    ----------
    node : udapi.core.node.Node object
        The node (word) whose language is being queried.
    """
    if node.misc['Lang'] != '':
        return node.misc['Lang']
    return None

def deps_list(cols):
    """
    Parses the contents of the DEPS column and returns a list of incoming
    enhanced dependencies. This is needed in early tests, before the sentence
    has been fed to Udapi.

    Parameters
    ----------
    cols : list
        The values of the columns on the current node / token line.

    Raises
    ------
    ValueError
        If the contents of DEPS cannot be parsed. Note that this does not catch
        all possible violations of the format, e.g., bad order of the relations
        will not raise an exception.

    Returns
    -------
    deps : list
        Each list item is a two-member list, containing the parent index (head)
        and the relation type (deprel).
    """
    if cols[DEPS] == '_':
        deps = []
    else:
        deps = [hd.split(':', 1) for hd in cols[DEPS].split('|')]
    if any(hd for hd in deps if len(hd) != 2):
        # ! should be an error/incident
        raise ValueError(f'malformed DEPS: {cols[DEPS]}')
    return deps

def get_line_numbers_for_ids(state, sentence):
    """
    Takes a list of sentence lines (mwt ranges, word nodes, empty nodes).
    For each mwt / node / word, gets the number of the line in the input
    file where the mwt / node / word occurs. We will need this in other
    functions to be able to report the line on which an error occurred.

    Parameters
    ----------
    sentence : list
        List of mwt / words / nodes, each represented as a list of columns.

    Returns
    -------
    linenos : dict
        Key: word ID (string, not int; decimal for empty nodes and range for
        mwt lines). Value: 1-based index of the line in the file (int).
    """
    linenos = {}
    node_line = state.sentence_line - 1
    for cols in sentence:
        node_line += 1
        linenos[cols[ID]] = node_line
        # For normal words, add them also under integer keys, just in case
        # we later forget to convert node.ord to string. But we cannot do the
        # same for empty nodes and multiword tokens.
        if is_word(cols):
            linenos[int(cols[ID])] = node_line
    return linenos

def next_block(fin):
    block = []
    for counter, line in enumerate(fin):
        block.append((counter, line.rstrip("\n\r")))
        if re.fullmatch(r"^\s*$", line):
            yield block
            block = []
    if len(block): yield block
    