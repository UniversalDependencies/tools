import regex as re



# Constants for the column indices
COLCOUNT=10
ID,FORM,LEMMA,UPOS,XPOS,FEATS,HEAD,DEPREL,DEPS,MISC=range(COLCOUNT)
COLNAMES='ID,FORM,LEMMA,UPOS,XPOS,FEATS,HEAD,DEPREL,DEPS,MISC'.split(',')



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
        # Parallel sentence id comment line. The actual id as well as its predefined parts are bracketed.
        self.parallelid = re.compile(r"#\s*parallel_id\s*=\s*(([a-z]+)/([-0-9a-z]+)(?:/(alt[1-9][0-9]*|part[1-9][0-9]*|alt[1-9][0-9]*part[1-9][0-9]*))?)")
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



# Global variables:
crex = CompiledRegexes()



# Support functions.

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

def lspec2ud(deprel):
    return deprel.split(':', 1)[0]

def formtl(node):
    """
    Returns the word form of a node, possibly accompanied by its
    transliteration (if available in the MISC column).

    Parameters
    ----------
    node : udapi.core.node.Node object
        The node whose form we want to get.

    Returns
    -------
    x : str
        The form and translit, space-separated. Only form if translit
        not available.
    """
    x = node.form
    if node.misc['Translit'] != '':
        x += ' ' + node.misc['Translit']
    return x

def lemmatl(node):
    """
    Returns the lemma of a node, possibly accompanied by its transliteration
    (if available in the MISC column).

    Parameters
    ----------
    node : udapi.core.node.Node object
        The node whose form we want to get.

    Returns
    -------
    x : str
        The lemma and translit, space-separated. Only form if translit not
        available.
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
