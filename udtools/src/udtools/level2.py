#! /usr/bin/env python3
# Original code (2015) by Filip Ginter and Sampo Pyysalo.
# DZ 2018-11-04: Porting the validator to Python 3.
# DZ: Many subsequent changes. See the git history.
# According to https://stackoverflow.com/questions/1832893/python-regex-matching-unicode-properties,
# the regex module has the same API as re but it can check Unicode character properties using \p{}
# as in Perl.
#import re
import regex as re
# Allow using this module from the root folder of tools even if it is not
# installed as a package: use the relative path validator/src/validator for
# submodules. If the path is not available, try the standard qualification,
# assuming that the user has installed udtools from PyPI and then called
# from udtools import Validator.
try:
    import udtools.src.udtools.utils as utils
    from udtools.src.udtools.incident import Incident, Error, TestClass, Reference
    from udtools.src.udtools.level1 import Level1
except ModuleNotFoundError:
    import udtools.utils as utils
    from udtools.incident import Incident, Error, TestClass, Reference
    from udtools.level1 import Level1



# Constants for the column indices
COLCOUNT=10
ID,FORM,LEMMA,UPOS,XPOS,FEATS,HEAD,DEPREL,DEPS,MISC=range(COLCOUNT)
COLNAMES='ID,FORM,LEMMA,UPOS,XPOS,FEATS,HEAD,DEPREL,DEPS,MISC'.split(',')



class Level2(Level1):
#==============================================================================
# Level 2 tests. Tree structure, universal tags and deprels. Note that any
# well-formed Feature=Value pair is allowed (because it could be language-
# specific) and any word form or lemma can contain spaces (because language-
# specific guidelines may permit it).
#==============================================================================



#------------------------------------------------------------------------------
# Level 2 tests applicable to a single line independently of the others.
#------------------------------------------------------------------------------



    def check_mwt_empty_vals(self, state, cols, line):
        """
        Checks that a multi-word token has _ empty values in all fields except MISC.
        This is required by UD guidelines although it is not a problem in general,
        therefore a level 2 test.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.
        cols : list
            The values of the columns on the current node / token line.
        line : int
            Number of the line where the node occurs in the file.

        Incidents
        ---------
        mwt-nonempty-field
        """
        assert utils.is_multiword_token(cols), 'internal error'
        for col_idx in range(LEMMA, MISC): # all columns except the first two (ID, FORM) and the last one (MISC)
            # Exception: The feature Typo=Yes may occur in FEATS of a multi-word token.
            if col_idx == FEATS and cols[col_idx] == 'Typo=Yes':
                pass
            elif cols[col_idx] != '_':
                Error(
                    state=state, config=self.incfg,
                    lineno=line,
                    level=2,
                    testclass=TestClass.FORMAT,
                    testid='mwt-nonempty-field',
                    message=f"A multi-word token line must have '_' in the column {COLNAMES[col_idx]}. Now: '{cols[col_idx]}'."
                ).confirm()




    def check_empty_node_empty_vals(self, state, cols, line):
        """
        Checks that an empty node has _ empty values in HEAD and DEPREL. This is
        required by UD guidelines but not necessarily by CoNLL-U, therefore
        a level 2 test.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.
        cols : list
            The values of the columns on the current node / token line.
        line : int
            Number of the line where the node occurs in the file.

        Incidents
        ---------
        empty-node-nonempty-field
        """
        assert utils.is_empty_node(cols), 'internal error'
        for col_idx in (HEAD, DEPREL):
            if cols[col_idx]!= '_':
                Error(
                    state=state, config=self.incfg,
                    lineno=line,
                    level=2,
                    testclass=TestClass.FORMAT,
                    testid='empty-node-nonempty-field',
                    message=f"An empty node must have '_' in the column {COLNAMES[col_idx]}. Now: '{cols[col_idx]}'."
                ).confirm()



    def check_upos(self, state, cols, line):
        """
        Checks that the UPOS field contains one of the 17 known tags.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.
        cols : list
            The values of the columns on the current node / token line.
        line : int
            Number of the line where the node occurs in the file.

        Incidents
        ---------
        unknown-upos
        """
        if utils.is_empty_node(cols) and cols[UPOS] == '_':
            return
        # Just in case, we still match UPOS against the regular expression that
        # checks general character constraints. However, the list of UPOS, loaded
        # from a JSON file, should conform to the regular expression.
        if not utils.crex.upos.fullmatch(cols[UPOS]) or cols[UPOS] not in self.data.upos:
            Error(
                state=state, config=self.incfg,
                lineno=line,
                level=2,
                testclass=TestClass.MORPHO,
                testid='unknown-upos',
                message=f"Unknown UPOS tag: '{cols[UPOS]}'."
            ).confirm()



    def check_feats_format(self, state, cols, line):
        """
        Checks general constraints on feature-value format: Permitted characters in
        feature name and value, features must be sorted alphabetically, features
        cannot be repeated etc.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.
        cols : list
            The values of the columns on the current node / token line.
        line : int
            Number of the line where the node occurs in the file.

        Incidents
        ---------
        unsorted-features
        invalid-feature
        repeated-feature-value
        unsorted-feature-values
        invalid-feature-value
        repeated-feature

        Returns
        -------
        safe : bool
            There were no errors or the errors are not so severe that we should
            refrain from loading the sentence into Udapi.
        """
        Incident.default_lineno = line
        Incident.default_level = 2
        Incident.default_testclass = TestClass.MORPHO
        feats = cols[FEATS]
        if feats == '_':
            return True
        utils.features_present(state, line)
        feat_list = feats.split('|')
        if [f.lower() for f in feat_list] != sorted(f.lower() for f in feat_list):
            Error(
                state=state, config=self.incfg,
                testid='unsorted-features',
                message=f"Morphological features must be sorted: '{feats}'."
            ).confirm()
        attr_set = set() # I'll gather the set of features here to check later that none is repeated.
        # Subsequent higher-level tests could fail if a feature is not in the
        # Feature=Value format. If that happens, we will return False and the caller
        # can skip the more fragile tests.
        safe = True
        for f in feat_list:
            match = utils.crex.featval.fullmatch(f)
            if match is None:
                Error(
                    state=state, config=self.incfg,
                    testid='invalid-feature',
                    message=f"Spurious morphological feature: '{f}'. Should be of the form Feature=Value and must start with [A-Z] and only contain [A-Za-z0-9]."
                ).confirm()
                attr_set.add(f) # to prevent misleading error "Repeated features are disallowed"
                safe = False
            else:
                # Check that the values are sorted as well
                attr = match.group(1)
                attr_set.add(attr)
                values = match.group(2).split(',')
                if len(values) != len(set(values)):
                    Error(
                        state=state, config=self.incfg,
                        testid='repeated-feature-value',
                        message=f"Repeated feature values are disallowed: '{feats}'"
                    ).confirm()
                if [v.lower() for v in values] != sorted(v.lower() for v in values):
                    Error(
                        state=state, config=self.incfg,
                        testid='unsorted-feature-values',
                        message=f"If a feature has multiple values, these must be sorted: '{f}'"
                    ).confirm()
                for v in values:
                    if not utils.crex.val.fullmatch(v):
                        Error(
                            state=state, config=self.incfg,
                            testid='invalid-feature-value',
                            message=f"Spurious value '{v}' in '{f}'. Must start with [A-Z0-9] and only contain [A-Za-z0-9]."
                        ).confirm()
                    # Level 2 tests character properties and canonical order but not that the f-v pair is known.
        if len(attr_set) != len(feat_list):
            Error(
                state=state, config=self.incfg,
                testid='repeated-feature',
                message=f"Repeated features are disallowed: '{feats}'."
            ).confirm()
        return safe



    def check_deprel_format(self, state, cols, line):
        """
        Checks general constraints on valid characters in DEPREL. Furthermore,
        if the general character format is OK, checks that the main relation
        type (udeprel) is defined in UD. Subtypes, if any, are ignored. This is
        a level 2 test and it does not consult language-specific lists. It will
        not report an error even if a main deprel is forbidden in a language.
        This method checks the DEPREL column but not DEPS.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.
        cols : list
            The values of the columns on the current node / token line.
        line : int
            Number of the line where the node occurs in the file.

        Incidents
        ---------
        invalid-deprel
        unknown-deprel
        """
        Incident.default_level = 2
        Incident.default_lineno = line
        if utils.is_multiword_token(cols):
            return
        # Empty nodes must have '_' in DEPREL but that has been already checked
        # in check_empty_node_empty_vals().
        if utils.is_empty_node(cols):
            return
        if not utils.crex.deprel.fullmatch(cols[DEPREL]):
            Error(
                state=state, config=self.incfg,
                testclass=TestClass.SYNTAX,
                testid='invalid-deprel',
                message=f"Invalid DEPREL value '{cols[DEPREL]}'. Only lowercase English letters or a colon are expected."
            ).confirm()
        else:
            # At this level, ignore the language-specific lists and use
            # language 'ud' instead.
            deprelset = self.data.get_deprel_for_language('ud')
            # Test only the universal part if testing at universal level.
            deprel = utils.lspec2ud(cols[DEPREL])
            if deprel not in deprelset:
                Error(
                    state=state, config=self.incfg,
                    testclass=TestClass.SYNTAX,
                    testid='unknown-udeprel',
                    message=f"Unknown main DEPREL type: '{deprel}'."
                ).confirm()



    def check_deps_format(self, state, cols, line):
        """
        Checks that DEPS is correctly formatted and that there are no
        self-loops in DEPS (longer cycles are allowed in enhanced graphs but
        self-loops are not).

        For each relation in DEPS, it also checks the general constraints on
        valid characters in DEPS. If the general character format is OK, checks
        that the main relation type of each relation in DEPS is on the list of
        main deprel types defined in UD. If there is a subtype, it is ignored.
        This is a level 2 test and it does not consult language-specific lists.
        It will not report an error even if a main deprel is forbidden in the
        language.

        This function must be run on raw DEPS before it is fed into Udapi because
        it checks the order of relations, which is not guaranteed to be preserved
        in Udapi. On the other hand, we assume that it is run after
        check_id_references() and only if DEPS is parsable and the head indices
        in it are OK.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.
        cols : list
            The values of the columns on the current node / token line.
        line : int
            Number of the line where the node occurs in the file.

        Incidents
        ---------
        unsorted-deps
        unsorted-deps-2
        repeated-deps
        deps-self-loop
        invalid-edeprel
        unknown-eudeprel
        """
        Incident.default_level = 2
        Incident.default_lineno = line
        if utils.is_multiword_token(cols):
            return
        if cols[DEPS] == '_':
            return
        # Remember whether there is at least one difference between the basic
        # tree and the enhanced graph in the entire dataset.
        if cols[DEPS] != '_' and cols[DEPS] != cols[HEAD]+':'+cols[DEPREL]:
            state.seen_enhancement = line
        # We should have called check_id_references() before (and only come
        # here if that check succeeded); since utils.deps_list() is called
        # there, it should be now guaranteed that the contents of DEPS is
        # parsable.
        edeps = utils.deps_list(cols)
        heads = [utils.nodeid2tuple(h) for h, d in edeps]
        if heads != sorted(heads):
            Error(
                state=state, config=self.incfg,
                testclass=TestClass.FORMAT,
                testid='unsorted-deps',
                message=f"DEPS not sorted by head index: '{cols[DEPS]}'."
            ).confirm()
        else:
            lasth = None
            lastd = None
            for h, d in edeps:
                if h == lasth:
                    if d < lastd:
                        Error(
                            state=state, config=self.incfg,
                            testclass=TestClass.FORMAT,
                            testid='unsorted-deps-2',
                            message=f"DEPS pointing to head '{h}' not sorted by relation type: '{cols[DEPS]}'."
                        ).confirm()
                    elif d == lastd:
                        Error(
                            state=state, config=self.incfg,
                            testclass=TestClass.FORMAT,
                            testid='repeated-deps',
                            message=f"DEPS contain multiple instances of the same relation '{h}:{d}'."
                        ).confirm()
                lasth = h
                lastd = d
        id_ = utils.nodeid2tuple(cols[ID])
        if id_ in heads:
            Error(
                state=state, config=self.incfg,
                testclass=TestClass.ENHANCED,
                testid='deps-self-loop',
                message=f"Self-loop in DEPS for '{cols[ID]}'"
            ).confirm()
        # At this level, ignore the language-specific lists and use language
        # 'ud' instead.
        deprelset = self.data.get_deprel_for_language('ud')
        deprelset.add('ref')
        for head, deprel in edeps:
            if not utils.crex.edeprel.fullmatch(deprel):
                Error(
                    state=state, config=self.incfg,
                    testclass=TestClass.ENHANCED,
                    testid='invalid-edeprel',
                    message=f"Invalid enhanced relation type: '{cols[DEPS]}'."
                ).confirm()
            else:
                # Test only the universal part if testing at universal level.
                udeprel = utils.lspec2ud(deprel)
                if not udeprel in deprelset:
                    Error(
                        state=state, config=self.incfg,
                        testclass=TestClass.ENHANCED,
                        testid='unknown-eudeprel',
                        message=f"Unknown main relation type '{udeprel}' in '{head}:{deprel}'."
                    ).confirm()



    def check_misc(self, state, cols, line):
        """
        In general, the MISC column can contain almost anything. However, if there
        is a vertical bar character, it is interpreted as the separator of two
        MISC attributes, which may or may not have the form of attribute=value pair.
        In general it is not forbidden that the same attribute appears several times
        with different values, but this should not happen for selected attributes
        that are described in the UD documentation.

        This function must be run on raw MISC before it is fed into Udapi because
        Udapi is not prepared for some of the less recommended usages of MISC.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.
        cols : list
            The values of the columns on the current node / token line.
        line : int
            Number of the line where the node occurs in the file.

        Incidents
        ---------
        empty-misc
        empty-misc-key
        misc-extra-space
        misc-attr-typo
        repeated-misc
        """
        Incident.default_lineno = line
        Incident.default_level = 2
        Incident.default_testclass = TestClass.FORMAT
        if cols[MISC] == '_':
            return
        misc = [ma.split('=', 1) for ma in cols[MISC].split('|')]
        mamap = {}
        for ma in misc:
            if ma[0] == '':
                if len(ma) == 1:
                    Warning(
                        state=state, config=self.incfg,
                        testid='empty-misc',
                        message="Empty attribute in MISC; possible misinterpreted vertical bar?"
                    ).confirm()
                else:
                    Warning(
                        state=state, config=self.incfg,
                        testid='empty-misc-key',
                        message=f"Empty MISC attribute name in '{ma[0]}={ma[1]}'."
                    ).confirm()
            # We do not warn about MISC items that do not contain '='.
            # But the remaining error messages below assume that ma[1] exists.
            if len(ma) == 1:
                ma.append('')
            if re.match(r"^\s", ma[0]):
                Warning(
                    state=state, config=self.incfg,
                    testid='misc-extra-space',
                    message=f"MISC attribute name starts with space in '{ma[0]}={ma[1]}'."
                ).confirm()
            elif re.search(r"\s$", ma[0]):
                Warning(
                    state=state, config=self.incfg,
                    testid='misc-extra-space',
                    message=f"MISC attribute name ends with space in '{ma[0]}={ma[1]}'."
                ).confirm()
            elif re.match(r"^\s", ma[1]):
                Warning(
                    state=state, config=self.incfg,
                    testid='misc-extra-space',
                    message=f"MISC attribute value starts with space in '{ma[0]}={ma[1]}'."
                ).confirm()
            elif re.search(r"\s$", ma[1]):
                Warning(
                    state=state, config=self.incfg,
                    testid='misc-extra-space',
                    message=f"MISC attribute value ends with space in '{ma[0]}={ma[1]}'."
                ).confirm()
            if re.match(r"^(SpaceAfter|Lang|Translit|LTranslit|Gloss|LId|LDeriv|Ref)$", ma[0]):
                mamap.setdefault(ma[0], 0)
                mamap[ma[0]] = mamap[ma[0]] + 1
            elif re.match(r"^\s*(spaceafter|lang|translit|ltranslit|gloss|lid|lderiv|ref)\s*$", ma[0], re.IGNORECASE):
                Warning(
                    state=state, config=self.incfg,
                    testid='misc-attr-typo',
                    message=f"Possible typo (case or spaces) in MISC attribute '{ma[0]}={ma[1]}'."
                ).confirm()
        for a in list(mamap):
            if mamap[a] > 1:
                Error(
                    state=state, config=self.incfg,
                    testclass=TestClass.FORMAT, # this one is real error
                    testid='repeated-misc',
                    message=f"MISC attribute '{a}' not supposed to occur twice"
                ).confirm()



#------------------------------------------------------------------------------
# Level 2 tests applicable to the whole sentence.
#------------------------------------------------------------------------------



    def check_id_references(self, state):
        """
        Verifies that HEAD and DEPS reference existing IDs. If this function does
        not return True, most of the other tests should be skipped for the current
        sentence (in particular anything that considers the tree structure).

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.

        Reads from state
        ----------------
        current_token_node_table : list(list(str))
            The list of multiword token lines / regular node lines / empty node
            lines, each split to fields (columns).
        sentence_line : int
            The line number (relative to input file, 1-based) of the first
            node/token line in the current sentence.

        Incidents
        ---------
        invalid-head
        unknown-head
        invalid-deps
        invalid-ehead
        unknown-ehead

        Returns
        -------
        ok : bool
            Is it OK to run subsequent checks? It can be OK even after some
            less severe errors.
        """
        ok = True
        Incident.default_level = 2
        Incident.default_testclass = TestClass.FORMAT
        ids = set([cols[ID] for cols in state.current_token_node_table if utils.is_word(cols) or utils.is_empty_node(cols)])
        for i in range(len(state.current_token_node_table)):
            lineno = state.sentence_line + i
            cols = state.current_token_node_table[i]
            if utils.is_multiword_token(cols):
                continue
            # Test the basic HEAD only for non-empty nodes.
            # We have checked elsewhere that it is empty for empty nodes.
            if not utils.is_empty_node(cols):
                match = utils.crex.head.fullmatch(cols[HEAD])
                if match is None:
                    Error(
                        state=state, config=self.incfg, lineno=lineno,
                        testid='invalid-head',
                        message=f"Invalid HEAD: '{cols[HEAD]}'."
                    ).confirm()
                    ok = False
                if not (cols[HEAD] in ids or cols[HEAD] == '0'):
                    Error(
                        state=state, config=self.incfg, lineno=lineno,
                        testclass=TestClass.SYNTAX,
                        testid='unknown-head',
                        message=f"Undefined HEAD (no such ID): '{cols[HEAD]}'."
                    ).confirm()
                    ok = False
            try:
                deps = utils.deps_list(cols)
            except ValueError:
                # Similar errors have probably been reported earlier.
                Error(
                    state=state, config=self.incfg, lineno=lineno,
                    testid='invalid-deps',
                    message=f"Failed to parse DEPS: '{cols[DEPS]}'."
                ).confirm()
                ok = False
                continue
            for head, deprel in deps:
                match = utils.crex.ehead.fullmatch(head)
                if match is None:
                    Error(
                        state=state, config=self.incfg, lineno=lineno,
                        testid='invalid-ehead',
                        message=f"Invalid enhanced head reference: '{head}'."
                    ).confirm()
                    ok = False
                if not (head in ids or head == '0'):
                    Error(
                        state=state, config=self.incfg, lineno=lineno,
                        testclass=TestClass.ENHANCED,
                        testid='unknown-ehead',
                        message=f"Undefined enhanced head reference (no such ID): '{head}'."
                    ).confirm()
                    ok = False
        return ok



    def check_tree(self, state):
        """
        Takes the list of non-comment lines (line = list of columns) describing
        a sentence. Returns an array with line number corresponding to each tree
        node. In case of fatal problems (missing HEAD etc.) returns None
        (and reports the error, unless it is something that should have been
        reported earlier).

        We will assume that this function is called only if both ID and HEAD
        values have been found valid for all tree nodes, including the sequence
        of IDs and the references from HEAD to existing IDs.

        This function originally served to build a data structure that would
        describe the tree and make it accessible during subsequent tests. Now we
        use the Udapi data structures instead but we still have to call this
        function first because it will survive and report ill-formed input. In
        such a case, the Udapi data structure will not be built and Udapi-based
        tests will be skipped.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.

        Reads from state
        ----------------
        current_token_node_table : list(list(str))
            The list of multiword token lines / regular node lines / empty node
            lines, each split to fields (columns).
        sentence_line : int
            The line number (relative to input file, 1-based) of the first
            node/token line in the current sentence.

        Incidents
        ---------
        head-self-loop
        multiple-roots
        non-tree

        Returns
        -------
        ok : bool
            Is it OK to run subsequent checks? It can be OK even after some
            less severe errors.
        """
        Incident.default_level = 2
        Incident.default_testclass = TestClass.SYNTAX
        children = {} # int(node id) -> set of children
        n_words = 0
        for i in range(len(state.current_token_node_table)):
            lineno = state.sentence_line + i
            cols = state.current_token_node_table[i]
            if not utils.is_word(cols):
                continue
            n_words += 1
            # ID and HEAD values have been validated before and this function would
            # not be called if they were not OK. So we can now safely convert them
            # to integers.
            id_ = int(cols[ID])
            head = int(cols[HEAD])
            if head == id_:
                Error(
                    state=state, config=self.incfg, lineno=lineno,
                    testid='head-self-loop',
                    message=f'HEAD == ID for {cols[ID]}'
                ).confirm()
                return False
            # Incrementally build the set of children of every node.
            children.setdefault(head, set()).add(id_)
        word_ids = list(range(1, n_words+1))
        # Check that there is just one node with the root relation.
        children_0 = sorted(children.get(0, []))
        if len(children_0) > 1:
            references = [Reference(filename=state.current_file_name,
                                    lineno=state.sentence_line + i,
                                    sentid=state.sentence_id,
                                    nodeid=i)
                          for i in children_0]
            Error(
                state=state, config=self.incfg, lineno=state.sentence_line,
                testid='multiple-roots',
                message=f"Multiple root words: {children_0}",
                references=references
            ).confirm()
            return False
        # Return None if there are any cycles. Otherwise we could not later ask
        # Udapi to built a data structure representing the tree.
        # Presence of cycles is equivalent to presence of unreachable nodes.
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
            Error(
                state=state, config=self.incfg, lineno=state.sentence_line,
                testid='non-tree',
                message=f'Non-tree structure. Words {str_unreachable} are not reachable from the root 0.'
            ).confirm()
            return False
        return True




    def check_deps_all_or_none(self, state):
        """
        Checks that enhanced dependencies are present if they were present in
        another sentence, and absent if they were absent in another sentence.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.

        Reads from state
        ----------------
        current_token_node_table : list(list(str))
            The list of multiword token lines / regular node lines / empty node
            lines, each split to fields (columns).
        sentence_line : int
            The line number (relative to input file, 1-based) of the first
            node/token line in the current sentence.

        Incidents
        ---------
        edeps-only-sometimes
        """
        egraph_exists = False # enhanced deps are optional
        for i in range(len(state.current_token_node_table)):
            cols = state.current_token_node_table[i]
            if utils.is_multiword_token(cols):
                continue
            if utils.is_empty_node(cols) or cols[DEPS] != '_':
                egraph_exists = True
        # We are currently testing the existence of enhanced graphs separately for each sentence.
        # However, we should not allow that one sentence has a connected egraph and another
        # has no enhanced dependencies. Such inconsistency could come as a nasty surprise
        # to the users.
        Incident.default_lineno = state.sentence_line
        Incident.default_level = 2
        Incident.default_testclass = TestClass.ENHANCED
        if egraph_exists:
            if not state.seen_enhanced_graph:
                state.seen_enhanced_graph = state.sentence_line
                if state.seen_tree_without_enhanced_graph:
                    Error(
                        state=state, config=self.incfg,
                        testid='edeps-only-sometimes',
                        message=f"Enhanced graph must be empty because we saw empty DEPS on line {state.seen_tree_without_enhanced_graph}"
                    ).confirm()
        else:
            if not state.seen_tree_without_enhanced_graph:
                state.seen_tree_without_enhanced_graph = state.sentence_line
                if state.seen_enhanced_graph:
                    Error(
                        state=state, config=self.incfg,
                        testid='edeps-only-sometimes',
                        message=f"Enhanced graph cannot be empty because we saw non-empty DEPS on line {state.seen_enhanced_graph}"
                    ).confirm()



    def check_egraph_connected(self, state, nodes):
        """
        Takes the list of nodes (including empty nodes). If there are enhanced
        dependencies in DEPS, builds the enhanced graph and checks that it is
        rooted and connected.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.
        nodes : list of udapi.core.node.Node objects
            List of nodes in the sentence, including empty nodes, sorted by word
            order.

        Reads from state
        ----------------
        current_node_linenos : dict(str: int)
            Mapping from node ids (including empty nodes) to line numbers in
            the input file.

        Incidents
        ---------
        unconnected-egraph
        """
        egraph_exists = False # enhanced deps are optional
        egraph = {'0': {'children': set()}}
        nodeids = set()
        for node in nodes:
            parents = [x['parent'] for x in node.deps]
            if node.is_empty() or len(parents) > 0:
                egraph_exists = True
            nodeids.add(str(node.ord))
            # The graph may already contain a record for the current node if one of
            # the previous nodes is its child. If it doesn't, we will create it now.
            egraph.setdefault(str(node.ord), {})
            egraph[str(node.ord)].setdefault('children', set())
            # Incrementally build the set of children of every node.
            for p in parents:
                egraph.setdefault(str(p.ord), {})
                egraph[str(p.ord)].setdefault('children', set()).add(str(node.ord))
        # If there is no trace of enhanced annotation, there are no requirements
        # on the enhanced graph.
        if not egraph_exists:
            return
        # Check that the graph is rooted and connected. The UD guidelines do not
        # license unconnected graphs. Projection of the technical root (ord '0')
        # must contain all nodes.
        projection = set()
        node_id = '0'
        projnodes = list((node_id,))
        while projnodes:
            node_id = projnodes.pop()
            for child in egraph[node_id]['children']:
                if child in projection:
                    continue # skip cycles
                projection.add(child)
                projnodes.append(child)
        unreachable = nodeids - projection
        if unreachable:
            sur = sorted(unreachable)
            Error(
                state=state, config=self.incfg,
                lineno=state.current_node_linenos[sur[0]],
                level=2,
                testclass=TestClass.ENHANCED,
                testid='unconnected-egraph',
                message=f"Enhanced graph is not connected. Nodes {sur} are not reachable from any root"
            ).confirm()
            return None



#------------------------------------------------------------------------------
# Level 2 tests of sentence metadata.
#------------------------------------------------------------------------------



    def check_sent_id(self, state):
        """
        Checks that sentence id exists, is well-formed and unique.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.

        Reads from state
        ----------------
        current_lines : list(str)
            List of lines in the sentence (comments and tokens), including
            final empty line. The lines are not expected to include the final
            newline character.
            First we expect an optional block (zero or more lines) of comments,
            i.e., lines starting with '#'. Then we expect a non-empty block
            (one or more lines) of nodes, empty nodes, and multiword tokens.
            Finally, we expect exactly one empty line.
        comment_start_line : int
            The line number (relative to input file, 1-based) of the first line
            in the current sentence, including comments if any.
        sentence_line : int
            The line number (relative to input file, 1-based) of the first
            node/token line in the current sentence.
        known_sent_ids : set
            Sentence ids already seen in this treebank.

        Writes to state
        ----------------
        known_sent_ids : set
            Sentence ids already seen in this treebank.

        Incidents
        ---------
            invalid-sent-id
            missing-sent-id
            multiple-sent-id
            non-unique-sent-id
            slash-in-sent-id
        """
        Incident.default_level = 2
        Incident.default_testclass = TestClass.METADATA
        Incident.default_lineno = -1 # use the first line after the comments
        n_comment_lines = state.sentence_line-state.comment_start_line
        comments = state.current_lines[0:n_comment_lines]
        matched = []
        for c in comments:
            match = utils.crex.sentid.fullmatch(c)
            if match:
                matched.append(match)
            else:
                if c.startswith('# sent_id') or c.startswith('#sent_id'):
                    Error(
                        state=state, config=self.incfg,
                        testid='invalid-sent-id',
                        message=f"Spurious sent_id line: '{c}' should look like '# sent_id = xxxxx' where xxxxx is not whitespace. Forward slash reserved for special purposes."
                    ).confirm()
        if not matched:
            Error(
                state=state, config=self.incfg,
                testid='missing-sent-id',
                message='Missing the sent_id attribute.'
            ).confirm()
        elif len(matched) > 1:
            Error(
                state=state, config=self.incfg,
                testid='multiple-sent-id',
                message='Multiple sent_id attributes.'
            ).confirm()
        else:
            # Uniqueness of sentence ids should be tested treebank-wide, not just file-wide.
            # For that to happen, all three files should be tested at once.
            sid = matched[0].group(1)
            if sid in state.known_sent_ids:
                Error(
                    state=state, config=self.incfg,
                    testid='non-unique-sent-id',
                    message=f"Non-unique sent_id attribute '{sid}'."
                ).confirm()
            if sid.count('/') > 1 or (sid.count('/') == 1 and self.lang != 'ud'):
                Error(
                    state=state, config=self.incfg,
                    testid='slash-in-sent-id',
                    message=f"The forward slash is reserved for special use in parallel treebanks: '{sid}'"
                ).confirm()
            state.known_sent_ids.add(sid)



    def check_parallel_id(self, state):
        """
        The parallel_id sentence-level comment is used after sent_id of
        sentences that are parallel translations of sentences in other
        treebanks. Like sent_id, it must be well-formed and unique. Unlike
        sent_id, it is optional. Sentences that do not have it are not
        parallel.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.

        Reads from state
        ----------------
        current_lines : list(str)
            List of lines in the sentence (comments and tokens), including
            final empty line. The lines are not expected to include the final
            newline character.
            First we expect an optional block (zero or more lines) of comments,
            i.e., lines starting with '#'. Then we expect a non-empty block
            (one or more lines) of nodes, empty nodes, and multiword tokens.
            Finally, we expect exactly one empty line.
        comment_start_line : int
            The line number (relative to input file, 1-based) of the first line
            in the current sentence, including comments if any.
        sentence_line : int
            The line number (relative to input file, 1-based) of the first
            node/token line in the current sentence.
        known_parallel_ids : set
            Parallel sentence ids already seen in this treebank.
        parallel_id_lastalt : dict
        parallel_id_lastpart : dict

        Writes to state
        ----------------
        known_parallel_ids : set
            Parallel sentence ids already seen in this treebank.
        parallel_id_lastalt : dict
        parallel_id_lastpart : dict

        Incidents
        ---------
            invalid-parallel-id
            multiple-parallel-id
            non-unique-parallel-id
            parallel-id-alt
            parallel-id-part
        """
        Incident.default_level = 2
        Incident.default_testclass = TestClass.METADATA
        Incident.default_lineno = -1 # use the first line after the comments
        n_comment_lines = state.sentence_line-state.comment_start_line
        comments = state.current_lines[0:n_comment_lines]
        matched = []
        for c in comments:
            match = utils.crex.parallelid.fullmatch(c)
            if match:
                matched.append(match)
            else:
                if c.startswith('# parallel_id') or c.startswith('#parallel_id'):
                    Error(
                        state=state, config=self.incfg,
                        testid='invalid-parallel-id',
                        message=f"Spurious parallel_id line: '{c}' should look like '# parallel_id = corpus/sentence' where corpus is [a-z]+ and sentence is [-0-9a-z]. Optionally, '/alt[1-9][0-9]*' and/or 'part[1-9][0-9]*' may follow."
                    ).confirm()
        if len(matched) > 1:
            Error(
                state=state, config=self.incfg,
                testid='multiple-parallel-id',
                message='Multiple parallel_id attributes.'
            ).confirm()
        elif matched:
            # Uniqueness of parallel ids should be tested treebank-wide, not just file-wide.
            # For that to happen, all three files should be tested at once.
            pid = matched[0].group(1)
            if pid in state.known_parallel_ids:
                Error(
                    state=state, config=self.incfg,
                    testid='non-unique-parallel-id',
                    message=f"Non-unique parallel_id attribute '{pid}'."
                ).confirm()
            else:
                # Additional tests when pid has altN or partN.
                # Do them only if the whole pid is unique.
                sid = matched[0].group(2) + '/' + matched[0].group(3)
                alt = None
                part = None
                altpart = matched[0].group(4)
                if altpart:
                    apmatch = re.fullmatch(r"(?:alt([0-9]+))?(?:part([0-9]+))?", altpart)
                    if apmatch:
                        alt = apmatch.group(1)
                        part = apmatch.group(2)
                        if alt:
                            alt = int(alt)
                        if part:
                            part = int(part)
                if sid in state.parallel_id_lastalt:
                    if state.parallel_id_lastalt[sid] == None and alt != None or state.parallel_id_lastalt[sid] != None and alt == None:
                        Error(
                            state=state, config=self.incfg,
                            testid='parallel-id-alt',
                            message=f"Some instances of parallel sentence '{sid}' have the 'alt' suffix while others do not."
                        ).confirm()
                    elif alt != None and alt != state.parallel_id_lastalt[sid] + 1:
                        Error(
                            state=state, config=self.incfg,
                            testid='parallel-id-alt',
                            message=f"The alt suffix of parallel sentence '{sid}' should be {state.parallel_id_lastalt[sid]}+1 but it is {alt}."
                        ).confirm()
                elif alt != None and alt != 1:
                    Error(
                        state=state, config=self.incfg,
                        testid='parallel-id-alt',
                        message=f"The alt suffix of parallel sentence '{sid}' should be 1 but it is {alt}."
                    ).confirm()
                state.parallel_id_lastalt[sid] = alt
                if sid in state.parallel_id_lastpart:
                    if state.parallel_id_lastpart[sid] == None and part != None or state.parallel_id_lastpart[sid] != None and part == None:
                        Error(
                            state=state, config=self.incfg,
                            testid='parallel-id-part',
                            message=f"Some instances of parallel sentence '{sid}' have the 'part' suffix while others do not."
                        ).confirm()
                    elif part != None and part != state.parallel_id_lastpart[sid] + 1:
                        Error(
                            state=state, config=self.incfg,
                            testid='parallel-id-part',
                            message=f"The part suffix of parallel sentence '{sid}' should be {state.parallel_id_lastpart[sid]}+1 but it is {part}."
                        ).confirm()
                elif part != None and part != 1:
                    Error(
                        state=state, config=self.incfg,
                        testid='parallel-id-part',
                        message=f"The part suffix of parallel sentence '{sid}' should be 1 but it is {part}."
                    ).confirm()
                state.parallel_id_lastpart[sid] = part
            state.known_parallel_ids.add(pid)



    def check_text_meta(self, state):
        """
        Checks metadata other than sentence id, that is, document breaks, paragraph
        breaks and sentence text (which is also compared to the sequence of the
        forms of individual tokens, and the spaces vs. SpaceAfter=No in MISC).

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.

        Reads from state
        ----------------
        current_lines : list(str)
            List of lines in the sentence (comments and tokens), including
            final empty line. The lines are not expected to include the final
            newline character.
            First we expect an optional block (zero or more lines) of comments,
            i.e., lines starting with '#'. Then we expect a non-empty block
            (one or more lines) of nodes, empty nodes, and multiword tokens.
            Finally, we expect exactly one empty line.
        comment_start_line : int
            The line number (relative to input file, 1-based) of the first line
            in the current sentence, including comments if any.
        current_token_node_table : list(list(str))
            The list of multiword token lines / regular node lines / empty node
            lines, each split to fields (columns).
        sentence_line : int
            The line number (relative to input file, 1-based) of the first
            node/token line in the current sentence.
        known_parallel_ids : set
            Parallel sentence ids already seen in this treebank.
        parallel_id_lastalt : dict
        parallel_id_lastpart : dict

        Writes to state
        ----------------
        known_parallel_ids : set
            Parallel sentence ids already seen in this treebank.
        parallel_id_lastalt : dict
        parallel_id_lastpart : dict

        Incidents
        ---------
        multiple-newdoc
        multiple-newpar
        spaceafter-newdocpar
        missing-text
        multiple-text
        text-trailing-whitespace
        nospaceafter-yes
        spaceafter-value
        spaceafter-empty-node
        spaceafter-mwt-node
        text-form-mismatch
        missing-spaceafter
        text-extra-chars
        """
        Incident.default_level = 2
        Incident.default_testclass = TestClass.METADATA
        Incident.default_lineno = -1 # use the first line after the comments
        n_comment_lines = state.sentence_line-state.comment_start_line
        comments = state.current_lines[0:n_comment_lines]
        newdoc_matched = []
        newpar_matched = []
        text_matched = []
        for c in comments:
            newdoc_match = utils.crex.newdoc.fullmatch(c)
            if newdoc_match:
                newdoc_matched.append(newdoc_match)
            newpar_match = utils.crex.newpar.fullmatch(c)
            if newpar_match:
                newpar_matched.append(newpar_match)
            text_match = utils.crex.text.fullmatch(c)
            if text_match:
                text_matched.append(text_match)
        if len(newdoc_matched) > 1:
            Error(
                state=state, config=self.incfg,
                testid='multiple-newdoc',
                message='Multiple newdoc attributes.'
            ).confirm()
        if len(newpar_matched) > 1:
            Error(
                state=state, config=self.incfg,
                testid='multiple-newpar',
                message='Multiple newpar attributes.'
            ).confirm()
        if (newdoc_matched or newpar_matched) and state.spaceafterno_in_effect:
            Error(
                state=state, config=self.incfg,
                testid='spaceafter-newdocpar',
                message='New document or paragraph starts when the last token of the previous sentence says SpaceAfter=No.'
            ).confirm()
        if not text_matched:
            Error(
                state=state, config=self.incfg,
                testid='missing-text',
                message='Missing the text attribute.'
            ).confirm()
        elif len(text_matched) > 1:
            Error(
                state=state, config=self.incfg,
                testid='multiple-text',
                message='Multiple text attributes.'
            ).confirm()
        else:
            stext = text_matched[0].group(1)
            if stext[-1].isspace():
                Error(
                    state=state, config=self.incfg,
                    testid='text-trailing-whitespace',
                    message='The text attribute must not end with whitespace.'
                ).confirm()
            # Validate the text against the SpaceAfter attribute in MISC.
            skip_words = set()
            mismatch_reported = 0 # do not report multiple mismatches in the same sentence; they usually have the same cause
            for iline in range(len(state.current_token_node_table)):
                cols = state.current_token_node_table[iline]
                if 'NoSpaceAfter=Yes' in cols[MISC]: # I leave this without the split("|") to catch all
                    Error(
                        state=state, config=self.incfg,
                        testid='nospaceafter-yes',
                        message="'NoSpaceAfter=Yes' should be replaced with 'SpaceAfter=No'."
                    ).confirm()
                if len([x for x in cols[MISC].split('|') if re.match(r"^SpaceAfter=", x) and x != 'SpaceAfter=No']) > 0:
                    Error(
                        state=state, config=self.incfg,
                        lineno=state.sentence_line+iline,
                        testid='spaceafter-value',
                        message="Unexpected value of the 'SpaceAfter' attribute in MISC. Did you mean 'SpacesAfter'?"
                    ).confirm()
                if utils.is_empty_node(cols):
                    if 'SpaceAfter=No' in cols[MISC]: # I leave this without the split("|") to catch all
                        Error(
                            state=state, config=self.incfg,
                            lineno=state.sentence_line+iline,
                            testid='spaceafter-empty-node',
                            message="'SpaceAfter=No' cannot occur with empty nodes."
                        ).confirm()
                    continue
                elif utils.is_multiword_token(cols):
                    beg, end = cols[ID].split('-')
                    begi, endi = int(beg), int(end)
                    # If we see a multi-word token, add its words to an ignore-set – these will be skipped, and also checked for absence of SpaceAfter=No.
                    for i in range(begi, endi+1):
                        skip_words.add(str(i))
                elif cols[ID] in skip_words:
                    if 'SpaceAfter=No' in cols[MISC]:
                        Error(
                            state=state, config=self.incfg,
                            lineno=state.sentence_line+iline,
                            testid='spaceafter-mwt-node',
                            message="'SpaceAfter=No' cannot occur with words that are part of a multi-word token."
                        ).confirm()
                    continue
                else:
                    # Err, I guess we have nothing to do here. :)
                    pass
                # So now we have either a multi-word token or a word which is also a token in its entirety.
                if not stext.startswith(cols[FORM]):
                    if not mismatch_reported:
                        extra_message = ''
                        if len(stext) >= 1 and stext[0].isspace():
                            extra_message = ' (perhaps extra SpaceAfter=No at previous token?)'
                        Error(
                            state=state, config=self.incfg,
                            lineno=state.sentence_line+iline,
                            testid='text-form-mismatch',
                            message=f"Mismatch between the text attribute and the FORM field. Form[{cols[ID]}] is '{cols[FORM]}' but text is '{stext[:len(cols[FORM])+20]}...'"+extra_message
                        ).confirm()
                        mismatch_reported = 1
                else:
                    stext = stext[len(cols[FORM]):] # eat the form
                    # Remember if SpaceAfter=No applies to the last word of the sentence.
                    # This is not prohibited in general but it is prohibited at the end of a paragraph or document.
                    if 'SpaceAfter=No' in cols[MISC].split("|"):
                        state.spaceafterno_in_effect = True
                    else:
                        state.spaceafterno_in_effect = False
                        if (stext) and not stext[0].isspace():
                            Error(
                                state=state, config=self.incfg,
                                lineno=state.sentence_line+iline,
                                testid='missing-spaceafter',
                                message=f"'SpaceAfter=No' is missing in the MISC field of node {cols[ID]} because the text is '{utils.shorten(cols[FORM]+stext)}'."
                            ).confirm()
                        stext = stext.lstrip()
            if stext:
                Error(
                    state=state, config=self.incfg,
                    testid='text-extra-chars',
                    message=f"Extra characters at the end of the text attribute, not accounted for in the FORM fields: '{stext}'"
                ).confirm()
