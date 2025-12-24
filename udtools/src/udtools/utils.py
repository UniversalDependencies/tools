import regex as re
# Allow using this module from the root folder of tools even if it is not
# installed as a package: use the relative path validator/src/validator for
# submodules. If the path is not available, try the standard qualification,
# assuming that the user has installed udtools from PyPI and then called
# from udtools import Validator.
try:
    from udtools.src.udtools.incident import Reference
except ModuleNotFoundError:
    from udtools.incident import Reference



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

def nodeid2tuple(nodeid: str):
    """
    Node ID can look like a decimal number, but 1.1 != 1.10. To be able to
    sort node IDs, we need to be able to convert them to a pair of integers
    (major and minor). For IDs of regular nodes, the ID will be converted to
    int (major) and the minor will be set to zero.
    """
    parts = [int(x) for x in nodeid.split('.', maxsplit=1)]
    if len(parts) == 1:
        parts.append(0)
    return tuple(parts)

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


def next_sentence(state, inp):
    """
    This function yields one sentence at a time from the input stream.

    This function is a generator. The caller can call it in a 'for x in ...'
    loop. In each iteration of the caller's loop, the generator will generate
    the next sentence, that is, it will read the next sentence from the input
    stream. (Technically, the function returns an object, and the object will
    then read the sentences within the caller's loop.)

    Parameters
    ----------
    state : udtools.state.State
        The state of the validation run.
    inp : file handle
        A file open for reading or STDIN.

    Yields
    ------
    sentence_lines : list(str)
        List of CoNLL-U lines that correspond to one sentence, including
        initial comments (if any) and the final empty line.
    """
    sentence_lines = [] # List of lines in the sentence (comments and tokens), minus final empty line, minus newline characters (and minus spurious lines that are neither comment lines nor token lines)
    for line_counter, line in enumerate(inp):
        state.current_line = line_counter + 1
        line = line.rstrip("\n")
        sentence_lines.append(line)
        if not line or is_whitespace(line):
            # If a line is not empty but contains only whitespace, we will
            # pretend that it terminates a sentence in order to avoid
            # subsequent misleading error messages.
            yield sentence_lines
            sentence_lines = []
    else: # end of file
        # If we found additional lines after the last empty line, yield them now.
        if sentence_lines:
            yield sentence_lines


def features_present(state, line):
    """
    In general, the annotation of morphological features is optional, although
    highly encouraged. However, if the treebank does have features, then certain
    features become required. This function is called when the first morphological
    feature is encountered. It remembers that from now on, missing features can
    be reported as errors. In addition, if any such errors have already been
    encountered, they will be reported now.

    Parameters
    ----------
    state : udtools.state.State
        The state of the validation run.
    line : int
        Number of the line where the current node occurs in the file.

    Reads from state
    ----------------
    seen_morpho_feature : int
        Line number of the first occurrence of a morphological feature in the
        corpus. None if no feature has been encountered so far.
    delayed_feature_errors : list(udtools.incident.Incident)
        The number of the most recently read line from the input file
        (1-based).

    Writes to state
    ----------------
    seen_morpho_feature : int
        Line number of the first occurrence of a morphological feature in the
        corpus. None if no feature has been encountered so far.
    """
    if not state.seen_morpho_feature:
        state.seen_morpho_feature = line
        for testid in state.delayed_feature_errors:
            for occurrence in state.delayed_feature_errors[testid]['occurrences']:
                occurrence['incident'].confirm()


def get_caused_nonprojectivities(node):
    """
    Checks whether a node is in a gap of a nonprojective edge. Report true only
    if the node's parent is not in the same gap. (We use this function to check
    that a punctuation node does not cause nonprojectivity. But if it has been
    dragged to the gap with a larger subtree, then we do not blame it.) This
    extra condition makes this function different from node.is_nonprojective_gap();
    another difference is that instead of just detecting the nonprojectivity,
    we return the nonprojective nodes so we can report them.

    Parameters
    ----------
    node : udapi.core.node.Node object
        The tree node to be tested.

    Returns
    -------
    cross : list of udapi.core.node.Node objects
        The nodes whose attachment is nonprojective because of the current node.
    """
    nodes = node.root.descendants
    iid = node.ord
    # We need to find all nodes that are not ancestors of this node and lie
    # on other side of this node than their parent. First get the set of
    # ancestors.
    ancestors = []
    current_node = node
    while not current_node.is_root():
        current_node = current_node.parent
        ancestors.append(current_node)
    maxid = nodes[-1].ord
    # Get the lists of nodes to either side of id.
    # Do not look beyond the parent (if it is in the same gap, it is the parent's responsibility).
    pid = node.parent.ord
    if pid < iid:
        leftidrange = range(pid + 1, iid) # ranges are open from the right (i.e. iid-1 is the last number)
        rightidrange = range(iid + 1, maxid + 1)
    else:
        leftidrange = range(1, iid)
        rightidrange = range(iid + 1, pid)
    left = [n for n in nodes if n.ord in leftidrange]
    right = [n for n in nodes if n.ord in rightidrange]
    # Exclude nodes whose parents are ancestors of id.
    leftna = [x for x in left if x.parent not in ancestors]
    rightna = [x for x in right if x.parent not in ancestors]
    leftcross = [x for x in leftna if x.parent.ord > iid]
    rightcross = [x for x in rightna if x.parent.ord < iid]
    # Once again, exclude nonprojectivities that are caused by ancestors of id.
    if pid < iid:
        rightcross = [x for x in rightcross if x.parent.ord > pid]
    else:
        leftcross = [x for x in leftcross if x.parent.ord < pid]
    # Do not return just a boolean value. Return the nonprojective nodes so we can report them.
    return sorted(leftcross + rightcross)


def get_gap(node):
    """
    Returns the list of nodes between node and its parent that are not dominated
    by the parent. If the list is not empty, the node is attached nonprojectively.

    Note that the Udapi Node class does not have a method like this. It has
    is_nonprojective(), which returns the boolean decision without showing the
    nodes in the gap. There is also the function is_nonprojective_gap() but it,
    too, does not deliver what we need.

    Parameters
    ----------
    node : udapi.core.node.Node object
        The tree node to be tested.

    Returns
    -------
    gap : list of udapi.core.node.Node objects
        The nodes in the gap of the current node's relation to its parent,
        sorted by their ords (IDs).
    """
    iid = node.ord
    pid = node.parent.ord
    if iid < pid:
        rangebetween = range(iid + 1, pid)
    else:
        rangebetween = range(pid + 1, iid)
    gap = []
    if rangebetween:
        gap = [n for n in node.root.descendants if n.ord in rangebetween and not n in node.parent.descendants]
    return sorted(gap)


def create_references(nodes, state, comment=''):
    """
    Takes a list of nodes and converts it to a list of Reference objects to be
    reported with an Incident.

    Parameters
    ----------
    nodes : list(udapi.core.node.Node)
        The nodes to which we wish to refer.
    state : udtools.state.State
        The state of the validation run.
    comment : str
        The comment to add to each reference.

    Returns
    -------
    references : list(udtools.incident.Reference)
    """
    return [Reference(nodeid=str(x.ord), sentid=state.sentence_id, filename=state.get_current_file_name(), lineno=state.current_node_linenos[str(x.ord)], comment=comment) for x in nodes]
