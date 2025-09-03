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
    incidents : list
        A list of Incidents (empty if validation is successful). 
    """
    incidents = []
    covered = set()
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

def validate_id_sequence(sentence):
    """
    Validates that the ID sequence is correctly formed.
    If this function returns an nonempty list, subsequent tests should not be run.

    Parameters
    ----------
    sentence : list
        A list of lists representing a sentence in tabular format.

    Returns
    -------
    incidents : list
        A list of Incidents (empty if validation is successful). 
    """
    incidents = []
    words=[]
    tokens=[]
    current_word_id, next_empty_id = 0, 1
    for cols in sentence:
        # Check for the format of the ID value. (ID must not be empty.)
        if not (utils.is_word(cols) or utils.is_empty_node(cols) or utils.is_multiword_token(cols)):
            incidents.append(Error(
                testid='invalid-word-id',
                message=f"Unexpected ID format '{cols[utils.ID]}'."
            ))
            continue
        if not utils.is_empty_node(cols):
            next_empty_id = 1    # reset sequence
        if utils.is_word(cols):
            t_id = int(cols[utils.ID])
            current_word_id = t_id
            words.append(t_id)
            # Not covered by the previous interval?
            if not (tokens and tokens[-1][0] <= t_id and tokens[-1][1] >= t_id):
                tokens.append((t_id, t_id)) # nope - let's make a default interval for it

        # ! looks like a duplicate of validate_id_sequence
        elif utils.is_multiword_token(cols):
            match = crex.mwtid.fullmatch(cols[utils.ID]) # Check the interval against the regex
            if not match: # This should not happen. The function utils.is_multiword_token() would then not return True.
                incidents.append(Error(
                    testid='invalid-word-interval',
                    message=f"Spurious word interval definition: '{cols[utils.ID]}'."
                ))
                continue
            beg, end = int(match.group(1)), int(match.group(2))
            if not ((not words and beg >= 1) or (words and beg >= words[-1] + 1)):
                incidents.append(Error(
                    testid='misplaced-word-interval',
                    message='Multiword range not before its first word.'
                ))
                continue
            tokens.append((beg, end))
        elif utils.is_empty_node(cols):
            word_id, empty_id = (int(i) for i in utils.parse_empty_node_id(cols))
            if word_id != current_word_id or empty_id != next_empty_id:
                incidents.append(Error(
                    testid='misplaced-empty-node',
                    message=f'Empty node id {cols[utils.ID]}, expected {current_word_id}.{next_empty_id}'
                ))
            next_empty_id += 1
            # Interaction of multiword tokens and empty nodes if there is an empty
            # node between the first word of a multiword token and the previous word:
            # This sequence is correct: 4 4.1 5-6 5 6
            # This sequence is wrong:   4 5-6 4.1 5 6
            if word_id == current_word_id and tokens and word_id < tokens[-1][0]:
                incidents.append(Error(
                    testid='misplaced-empty-node',
                    message=f"Empty node id {cols[utils.ID]} must occur before multiword token {tokens[-1][0]}-{tokens[-1][1]}."
                ))
    # Now let's do some basic sanity checks on the sequences.
    # Expected sequence of word IDs is 1, 2, ...
    expstrseq = ','.join(str(x) for x in range(1, len(words) + 1))
    wrdstrseq = ','.join(str(x) for x in words)
    if wrdstrseq != expstrseq:
        incidents.append(Error(
            lineno=-1,
            testid='word-id-sequence',
            message=f"Words do not form a sequence. Got '{wrdstrseq}'. Expected '{expstrseq}'."
        ))
    # Check elementary sanity of word intervals.
    # Remember that these are not just multi-word tokens. Here we have intervals even for single-word tokens (b=e)!
    for (b, e) in tokens:
        if e < b: # end before beginning
            incidents.append(Error(
                testid='reversed-word-interval',
                message=f'Spurious token interval {b}-{e}'
            ))
            continue
        if b < 1 or e > len(words): # out of range
            incidents.append(Error(
                testid='word-interval-out',
                message=f'Spurious token interval {b}-{e} (out of range)'
            ))
            continue
    return incidents

def validate_id_references(sentence):
    """
    Verifies that HEAD and DEPS reference existing IDs. If this function returns a nonempty list, most of the other tests should be skipped for the current
    sentence (in particular anything that considers the tree structure).

    Parameters
    ----------
    sentence : list
        A list of lists representing a sentence in tabular format.

    Returns
    -------
    incidents : list
        A list of Incidents (empty if validation is successful). 
    """
    incidents = []
    word_tree = [cols for cols in sentence if utils.is_word(cols) or utils.is_empty_node(cols)]
    ids = set([cols[utils.ID] for cols in word_tree])
    for cols in word_tree:
        # Test the basic HEAD only for non-empty nodes.
        # We have checked elsewhere that it is empty for empty nodes.
        if not utils.is_empty_node(cols):
            match = crex.head.fullmatch(cols[utils.HEAD])
            if match is None:
                incidents.append(Error(
                    testid='invalid-head',
                    message=f"Invalid HEAD: '{cols[utils.HEAD]}'."
                ))
            if not (cols[utils.HEAD] in ids or cols[utils.HEAD] == '0'):
                incidents.append(Error(
                    testclass=TestClass.SYNTAX,
                    testid='unknown-head',
                    message=f"Undefined HEAD (no such ID): '{cols[id.HEAD]}'."
                ))
        try:
            deps = utils.deps_list(cols)
        except ValueError:
            # Similar errors have probably been reported earlier.
            incidents.append(Error(
                testid='invalid-deps',
                message=f"Failed to parse DEPS: '{cols[utils.DEPS]}'."
            ))
            continue
        for head, _ in deps:
            match = crex.ehead.fullmatch(head)
            if match is None:
                incidents.append(Error(
                    testid='invalid-ehead',
                    message=f"Invalid enhanced head reference: '{head}'."
                ))
            if not (head in ids or head == '0'):
                incidents.append(Error(
                    testclass=TestClass.ENHANCED,
                    testid='unknown-ehead',
                    message=f"Undefined enhanced head reference (no such ID): '{head}'."
                ))
    return incidents

def validate_tree(sentence, node_line, single_root):
    """
    Performs basic validation of the tree structure.

    This function originally served to build a data structure that would
    describe the tree and make it accessible during subsequent tests. Now we
    use the Udapi data structures instead but we still have to call this
    function first because it will survive and report ill-formed input. In
    such a case, the Udapi data structure will not be built and Udapi-based
    tests will be skipped.

    This function should be called only if both ID and HEAD values have been
    found valid for all tree nodes, including the sequence of IDs and the references from HEAD to existing IDs.

    Parameters
    ----------
    sentence : list
        A list of lists representing a sentence in tabular format.
    node_line : int
        A file-wide line counter.
    single_root : bool
        A flag indicating whether we should check that there is a single root.

    Returns
    -------
    incidents : list
        A list of Incidents (empty if validation is successful). 
    """
    # node_line = state.sentence_line - 1 TODO: this should be done by the engine
    incidents = []
    children = {} # int(node id) -> set of children
    n_words = 0
    for cols in sentence:
        node_line += 1
        if not utils.is_word(cols):
            continue
        n_words += 1
        # ID and HEAD values have been validated before and this function would
        # not be called if they were not OK. So we can now safely convert them
        # to integers.
        id_ = int(cols[utils.ID])
        head = int(cols[utils.HEAD])
        if head == id_:
            incidents.append(Error(
                testclass=TestClass.SYNTAX,
                lineno=node_line,
                testid='head-self-loop',
                message=f'HEAD == ID for {cols[utils.ID]}'
            ))
        # Incrementally build the set of children of every node.
        children.setdefault(head, set()).add(id_)
    word_ids = list(range(1, n_words+1))
    # Check that there is just one node with the root relation.
    children_0 = sorted(children.get(0, []))
    if len(children_0) > 1 and single_root:
        incidents.append(Error(
            testclass=TestClass.SYNTAX,
            lineno=-1,
            testid='multiple-roots',
            message=f"Multiple root words: {children_0}"
        ))
    projection = set()
    node_id = 0
    nodes = list((node_id,))
    while nodes:
        node_id = nodes.pop()
        children_id = sorted(children.get(node_id, []))
        for child in children_id:
            if child in projection:
                continue # skip cycles
            projection.add(child)
            nodes.append(child)
    unreachable = set(word_ids) - projection
    if unreachable:
        str_unreachable = ','.join(str(w) for w in sorted(unreachable))
        incidents.append(Error(
            testclass=TestClass.SYNTAX,
            lineno=-1,
            testid='non-tree',
            message=f'Non-tree structure. Words {str_unreachable} are not reachable from the root 0.'
        ))
    return incidents
