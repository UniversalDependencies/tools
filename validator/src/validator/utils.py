import os

from validator.loaders import load_conllu_spec

# TODO: update
#import validator.compiled_regex as crex
import regex as re
class CompiledRegexes:
    """
    The CompiledRegexes class holds various regular expressions needed to
    recognize individual elements of the CoNLL-U format, precompiled to speed
    up parsing. Individual expressions are typically not enclosed in ^...$
    because one can use re.fullmatch() if it is desired that the whole string
    matches the expression.
    """
    def __init__(self):
        # Whitespace.
        self.ws = re.compile(r"\s+")
        # Two consecutive whitespaces.
        self.ws2 = re.compile(r"\s\s")
        # Regular word/node id: integer number.
        self.wordid = re.compile(r"[1-9][0-9]*")
        # Multiword token id: range of integers.
        # The two parts are bracketed so they can be captured and processed separately.
        self.mwtid = re.compile(r"([1-9][0-9]*)-([1-9][0-9]*)")
        # Empty node id: "decimal" number (but 1.10 != 1.1).
        # The two parts are bracketed so they can be captured and processed separately.
        self.enodeid = re.compile(r"([0-9]+)\.([1-9][0-9]*)")
        # New document comment line. Document id, if present, is bracketed.
        self.newdoc = re.compile(r"#\s*newdoc(?:\s+(\S+))?")
        # New paragraph comment line. Paragraph id, if present, is bracketed.
        self.newpar = re.compile(r"#\s*newpar(?:\s+(\S+))?")
        # Sentence id comment line. The actual id is bracketed.
        self.sentid = re.compile(r"#\s*sent_id\s*=\s*(\S+)")
        # Sentence text comment line. The actual text is bracketed.
        self.text = re.compile(r"#\s*text\s*=\s*(.*\S)")
        # Global entity comment is a declaration of entity attributes in MISC.
        # It occurs once per document and it is optional (only CorefUD data).
        # The actual attribute declaration is bracketed so it can be captured in the match.
        self.global_entity = re.compile(r"#\s*global\.Entity\s*=\s*(.+)")
        # UPOS tag.
        self.upos = re.compile(r"[A-Z]+")
        # Feature=value pair.
        # Feature name and feature value are bracketed so that each can be captured separately in the match.
        self.featval = re.compile(r"([A-Z][A-Za-z0-9]*(?:\[[a-z0-9]+\])?)=(([A-Z0-9][A-Z0-9a-z]*)(,([A-Z0-9][A-Z0-9a-z]*))*)")
        self.val = re.compile(r"[A-Z0-9][A-Za-z0-9]*")
        # Basic parent reference (HEAD).
        self.head = re.compile(r"(0|[1-9][0-9]*)")
        # Enhanced parent reference (head).
        self.ehead = re.compile(r"(0|[1-9][0-9]*)(\.[1-9][0-9]*)?")
        # Basic dependency relation (including optional subtype).
        self.deprel = re.compile(r"[a-z]+(:[a-z]+)?")
        # Enhanced dependency relation (possibly with Unicode subtypes).
        # Ll ... lowercase Unicode letters
        # Lm ... modifier Unicode letters (e.g., superscript h)
        # Lo ... other Unicode letters (all caseless scripts, e.g., Arabic)
        # M .... combining diacritical marks
        # Underscore is allowed between letters but not at beginning, end, or next to another underscore.
        edeprelpart_resrc = r'[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(_[\p{Ll}\p{Lm}\p{Lo}\p{M}]+)*'
        # There must be always the universal part, consisting only of ASCII letters.
        # There can be up to three additional, colon-separated parts: subtype, preposition and case.
        # One of them, the preposition, may contain Unicode letters. We do not know which one it is
        # (only if there are all four parts, we know it is the third one).
        # ^[a-z]+(:[a-z]+)?(:[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(_[\p{Ll}\p{Lm}\p{Lo}\p{M}]+)*)?(:[a-z]+)?$
        edeprel_resrc = '^[a-z]+(:[a-z]+)?(:' + edeprelpart_resrc + ')?(:[a-z]+)?$'
        self.edeprel = re.compile(edeprel_resrc)
crex = CompiledRegexes()

THIS_DIR = os.path.dirname(os.path.realpath(os.path.abspath(__file__)))

CONLLU_SPEC = load_conllu_spec(os.path.join(THIS_DIR, "conllu_spec.yaml"))
COLCOUNT = len(CONLLU_SPEC["columns"])
ID, FORM, LEMMA, UPOS, XPOS, FEATS, HEAD, DEPREL, DEPS, MISC = range(COLCOUNT)
COLNAMES = CONLLU_SPEC["columns"]

def is_whitespace(line):
    return crex.ws.fullmatch(line)

def is_word(cols):
    return crex.wordid.fullmatch(cols[ID])

def is_multiword_token(cols):
    return crex.mwtid.fullmatch(cols[ID])

def is_empty_node(cols):
    return crex.enodeid.fullmatch(cols[ID])

def parse_empty_node_id(cols):
    m = crex.enodeid.fullmatch(cols[ID])
    assert m, 'parse_empty_node_id with non-empty node'
    return m.groups()

def shorten(string):
    return string if len(string) < 25 else string[:20]+'[...]'

# ! proposal: rename to drop_subtype
def lspec2ud(deprel):
    return deprel.split(':', 1)[0]

def formtl(node):
    x = node.form
    if node.misc['Translit'] != '':
        x += ' ' + node.misc['Translit']
    return x

def lemmatl(node):
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