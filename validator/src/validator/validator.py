import regex as re

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
            testid='non-tree',
            message=f'Non-tree structure. Words {str_unreachable} are not reachable from the root 0.'
        ))
    return incidents

def validate_sent_id(comments, lcode, known_sent_ids):
    """
    Checks that sentence id exists, is well-formed and unique.
    
    Parameters
    ----------
    comments : list
        A list of comments, represented as strings.
    lcode : str
        TODO: https://github.com/UniversalDependencies/tools/issues/127
    known_sent_ids : set
        The set of previously encountered sentence IDs.

    Returns
    -------
    incidents : list
        A list of Incidents (empty if validation is successful). 
    """
    incidents = []
    matched = []
    for c in comments:
        match = crex.sentid.fullmatch(c)
        if match:
            matched.append(match)
        else:
            if c.startswith('# sent_id') or c.startswith('#sent_id'):
                incidents.append(Error(
                    testclass=TestClass.METADATA,
                    level=2,
                    testid='invalid-sent-id',
                    message=f"Spurious sent_id line: '{c}' should look like '# sent_id = xxxxx' where xxxxx is not whitespace. Forward slash reserved for special purposes."
                ))
    if not matched:
        incidents.append(Error(
            testclass=TestClass.METADATA,
            level=2,
            testid='missing-sent-id',
            message='Missing the sent_id attribute.'
        ))
    elif len(matched) > 1:
        incidents.append(Error(
            testclass=TestClass.METADATA,
            level=2,
            testid='multiple-sent-id',
            message='Multiple sent_id attributes.'
        ))
    else:
        # Uniqueness of sentence ids should be tested treebank-wide, not just file-wide.
        # For that to happen, all three files should be tested at once.
        sid = matched[0].group(1)
        if sid in known_sent_ids:
            incidents.append(Error(
                testclass=TestClass.METADATA,
                level=2,
                testid='non-unique-sent-id',
                message=f"Non-unique sent_id attribute '{sid}'."
            ))
        if sid.count('/') > 1 or (sid.count('/') == 1 and lcode != 'ud'):
            incidents.append(Error(
                testclass=TestClass.METADATA,
                level=2,
                testid='slash-in-sent-id',
                message=f"The forward slash is reserved for special use in parallel treebanks: '{sid}'"
            ))
        #state.known_sent_ids.add(sid) # TODO: move this to the engine
    return incidents

def validate_text_meta(comments, tree, spaceafterno_in_effect):
    """
    Checks metadata other than sentence id, that is, document breaks, paragraph
    breaks and sentence text (which is also compared to the sequence of the
    forms of individual tokens, and the spaces vs. SpaceAfter=No in MISC).
    """
    incidents = []
    newdoc_matched = []
    newpar_matched = []
    text_matched = []
    for c in comments:
        newdoc_match = crex.newdoc.fullmatch(c)
        if newdoc_match:
            newdoc_matched.append(newdoc_match)
        newpar_match = crex.newpar.fullmatch(c)
        if newpar_match:
            newpar_matched.append(newpar_match)
        text_match = crex.text.fullmatch(c)
        if text_match:
            text_matched.append(text_match)
    if len(newdoc_matched) > 1:
        incidents.append(Error(
            testclass=TestClass.METADATA,
            level=2,
            testid='multiple-newdoc',
            message='Multiple newdoc attributes.'
        ))
    if len(newpar_matched) > 1:
        incidents.append(Error(
			testclass=TestClass.METADATA,
			level=2,
            testid='multiple-newpar',
            message='Multiple newpar attributes.'
        ))
    if (newdoc_matched or newpar_matched) and spaceafterno_in_effect:
        incidents.append(Error(
			testclass=TestClass.METADATA,
			level=2,
            testid='spaceafter-newdocpar',
            message='New document or paragraph starts when the last token of the previous sentence says SpaceAfter=No.'
        ))
    if not text_matched:
        incidents.append(Error(
			testclass=TestClass.METADATA,
			level=2,
            testid='missing-text',
            message='Missing the text attribute.'
        ))
    elif len(text_matched) > 1:
        incidents.append(Error(
			testclass=TestClass.METADATA,
			level=2,

            testid='multiple-text',
            message='Multiple text attributes.'
        ))
    else:
        stext = text_matched[0].group(1)
        if stext[-1].isspace():
            incidents.append(Error(
			testclass=TestClass.METADATA,
			level=2,
                testid='text-trailing-whitespace',
                message='The text attribute must not end with whitespace.'
            ))
        # Validate the text against the SpaceAfter attribute in MISC.
        skip_words = set()
        mismatch_reported = 0 # do not report multiple mismatches in the same sentence; they usually have the same cause
        # We will sum state.sentence_line + iline, and state.sentence_line already points at
        # the first token/node line after the sentence comments. Hence iline shall
        # be 0 once we enter the cycle.
        iline = -1
        for cols in tree:
            iline += 1
            if 'NoSpaceAfter=Yes' in cols[utils.MISC]: # I leave this without the split("|") to catch all
                incidents.append(Error(
			testclass=TestClass.METADATA,
			level=2,

                    testid='nospaceafter-yes',
                    message="'NoSpaceAfter=Yes' should be replaced with 'SpaceAfter=No'."
                ))
            if len([x for x in cols[utils.MISC].split('|') if re.match(r"^SpaceAfter=", x) and x != 'SpaceAfter=No']) > 0:
                incidents.append(Error(
			        testclass=TestClass.METADATA,
			        level=2,
                    # TODO: lineno=state.sentence_line+iline, (engine)
                    testid='spaceafter-value',
                    message="Unexpected value of the 'SpaceAfter' attribute in MISC. Did you mean 'SpacesAfter'?"
                ))
            if utils.is_empty_node(cols):
                if 'SpaceAfter=No' in cols[utils.MISC]: # I leave this without the split("|") to catch all
                    incidents.append(Error(
			            testclass=TestClass.METADATA,
			            level=2,
                        # TODO: engine lineno=state.sentence_line+iline,
                        testid='spaceafter-empty-node',
                        message="'SpaceAfter=No' cannot occur with empty nodes."
                    ))
                continue
            elif utils.is_multiword_token(cols):
                beg, end = cols[utils.ID].split('-')
                begi, endi = int(beg), int(end)
                # If we see a multi-word token, add its words to an ignore-set – these will be skipped, and also checked for absence of SpaceAfter=No.
                for i in range(begi, endi+1):
                    skip_words.add(str(i))
            elif cols[utils.ID] in skip_words:
                if 'SpaceAfter=No' in cols[utils.MISC]:
                    incidents.append(Error(
			            testclass=TestClass.METADATA,
			            level=2,
                        # TODO: lineno=state.sentence_line+iline,
                        testid='spaceafter-mwt-node',
                        message="'SpaceAfter=No' cannot occur with words that are part of a multi-word token."
                    ))
                continue
            else:
                # Err, I guess we have nothing to do here. :)
                pass
            # So now we have either a multi-word token or a word which is also a token in its entirety.
            if not stext.startswith(cols[utils.FORM]):
                if not mismatch_reported:
                    extra_message = ''
                    if len(stext) >= 1 and stext[0].isspace():
                        extra_message = ' (perhaps extra SpaceAfter=No at previous token?)'
                    incidents.append(Error(
			            testclass=TestClass.METADATA,
			            level=2,
                        # TODO: lineno=state.sentence_line+iline,
                        testid='text-form-mismatch',
                        message=f"Mismatch between the text attribute and the FORM field. Form[{cols[utils.ID]}] is '{cols[utils.FORM]}' but text is '{stext[:len(cols[utils.FORM])+20]}...'"+extra_message
                    ))
                    mismatch_reported = 1
            else:
                stext = stext[len(cols[utils.FORM]):] # eat the form
                # Remember if SpaceAfter=No applies to the last word of the sentence.
                # This is not prohibited in general but it is prohibited at the end of a paragraph or document.
                if 'SpaceAfter=No' in cols[utils.MISC].split("|"):
                    spaceafterno_in_effect = True
                else:
                    spaceafterno_in_effect = False
                    if (stext) and not stext[0].isspace():
                        incidents.append(Error(
			                testclass=TestClass.METADATA,
			                level=2,
                            # TODO: lineno=state.sentence_line+iline,
                            testid='missing-spaceafter',
                            message=f"'SpaceAfter=No' is missing in the MISC field of node {cols[utils.ID]} because the text is '{utils.shorten(cols[utils.FORM]+stext)}'."
                        ))
                    stext = stext.lstrip()
        if stext:
            incidents.append(Error(
			    testclass=TestClass.METADATA,
			    level=2,
                testid='text-extra-chars',
                message=f"Extra characters at the end of the text attribute, not accounted for in the FORM fields: '{stext}'"
            ))