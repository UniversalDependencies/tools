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
    from udtools.src.udtools.incident import Incident, Error, TestClass
    from udtools.src.udtools.level3 import Level3
except ModuleNotFoundError:
    import udtools.utils as utils
    from udtools.incident import Incident, Error, TestClass
    from udtools.level3 import Level3



class Level4(Level3):
#==============================================================================
# Level 4 tests. Language-specific formal tests. Now we can check in which
# words spaces are permitted, and which Feature=Value pairs are defined.
#==============================================================================



    def check_words_with_spaces(self, state, node):
        """
        Checks a single line for disallowed whitespace.
        Here we assume that all language-independent whitespace-related tests have
        already been done on level 1, so we only check for words with spaces that
        are explicitly allowed in a given language.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.
        node : udapi.core.node.Node object
            The node whose incoming relation will be validated. This function
            operates on both regular and empty nodes. Make sure to call it for
            empty nodes, too!

        Reads from state
        ----------------
        current_node_linenos : dict(str: int)
            Mapping from node ids (including empty nodes) to line numbers in
            the input file.

        Incidents
        ---------
        invalid-word-with-space
        """
        Incident.default_lineno = state.current_node_linenos[str(node.ord)]
        Incident.default_level = 4
        Incident.default_testclass = TestClass.FORMAT
        # List of permited words with spaces is language-specific.
        # The current token may be in a different language due to code switching.
        tospacedata = self.data.get_tospace_for_language(self.lang)
        lang = self.lang
        altlang = utils.get_alt_language(node)
        if altlang:
            lang = altlang
            tospacedata = self.data.get_tospace_for_language(altlang)
        for column in ('FORM', 'LEMMA'):
            word = node.form if column == 'FORM' else node.lemma
            # Is there whitespace in the word?
            if utils.crex.ws.search(word):
                # Whitespace found. Does the word pass the regular expression that defines permitted words with spaces in this language?
                if tospacedata:
                    # For the purpose of this test, NO-BREAK SPACE is equal to SPACE.
                    string_to_test = re.sub(r'\xA0', ' ', word)
                    if not tospacedata[1].fullmatch(string_to_test):
                        Error(
                            state=state, config=self.incfg,
                            nodeid=node.ord,
                            testid='invalid-word-with-space',
                            message=f"'{word}' in column {column} is not on the list of exceptions allowed to contain whitespace.",
                            explanation=self.data.explain_tospace(lang)
                        ).confirm()
                else:
                    Error(
                        state=state, config=self.incfg,
                        nodeid=node.ord,
                        testid='invalid-word-with-space',
                        message=f"'{word}' in column {column} is not on the list of exceptions allowed to contain whitespace.",
                        explanation=self.data.explain_tospace(lang)
                    ).confirm()



    def check_feature_values(self, state, node):
        """
        Checks that a feature-value pair is listed as approved. Feature lists are
        language-specific. To disallow non-universal features, test on level 4 with
        language 'ud'.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.
        node : udapi.core.node.Node object
            The node whose incoming relation will be validated. This function
            operates on both regular and empty nodes. Make sure to call it for
            empty nodes, too!

        Reads from state
        ----------------
        current_node_linenos : dict(str: int)
            Mapping from node ids (including empty nodes) to line numbers in
            the input file.

        Incidents
        ---------
        mwt-typo-repeated-at-word
        feature-unknown
        feature-not-permitted
        feature-value-unknown
        feature-upos-not-permitted
        feature-value-upos-not-permitted
        """
        Incident.default_lineno = state.current_node_linenos[str(node.ord)]
        Incident.default_level = 4
        Incident.default_testclass = TestClass.MORPHO
        if str(node.feats) == '_':
            return True
        # List of permited features is language-specific.
        # The current token may be in a different language due to code switching.
        default_lang = self.lang
        default_featset = featset = self.data.get_feats_for_language(self.lang)
        lang = default_lang
        altlang = utils.get_alt_language(node)
        if altlang:
            lang = altlang
            featset = self.data.get_feats_for_language(altlang)
        for f in node.feats:
            values = node.feats[f].split(',')
            for v in values:
                # Level 2 tested character properties and canonical order but not that the f-v pair is known.
                # Level 4 also checks whether the feature value is on the list.
                # If only universal feature-value pairs are allowed, test on level 4 with lang='ud'.
                # The feature Typo=Yes is the only feature allowed on a multi-word token line.
                # If it occurs there, it cannot be duplicated on the lines of the component words.
                if f == 'Typo' and node.multiword_token:
                    mwt = node.multiword_token
                    if mwt.feats['Typo'] == 'Yes':
                        Error(
                            state=state, config=self.incfg,
                            nodeid=node.ord,
                            testid='mwt-typo-repeated-at-word',
                            message=f"Feature Typo cannot occur at word [{node.ord}] if it already occurred at the corresponding multiword token [{mwt.ord_range}]."
                        ).confirm()
                # In case of code switching, the current token may not be in the default language
                # and then its features are checked against a different feature set. An exception
                # is the feature Foreign, which always relates to the default language of the
                # corpus (but Foreign=Yes should probably be allowed for all UPOS categories in
                # all languages).
                effective_featset = featset
                effective_lang = lang
                if f == 'Foreign':
                    # Revert to the default.
                    effective_featset = default_featset
                    effective_lang = default_lang
                if effective_featset is not None:
                    if f not in effective_featset:
                        Error(
                            state=state, config=self.incfg,
                            nodeid=node.ord,
                            testid='feature-unknown',
                            message=f"Feature {f} is not documented for language [{effective_lang}] ('{utils.formtl(node)}', {f}={v}).",
                            explanation=self.data.explain_feats(effective_lang)
                        ).confirm()
                    else:
                        lfrecord = effective_featset[f]
                        if lfrecord['permitted'] == 0:
                            Error(
                                state=state, config=self.incfg,
                                nodeid=node.ord,
                                testid='feature-not-permitted',
                                message=f"Feature {f} is not permitted in language [{effective_lang}] ('{utils.formtl(node)}, {f}={v}').",
                                explanation=self.data.explain_feats(effective_lang)
                            ).confirm()
                        else:
                            values = lfrecord['uvalues'] + lfrecord['lvalues'] + lfrecord['unused_uvalues'] + lfrecord['unused_lvalues']
                            if not v in values:
                                Error(
                                    state=state, config=self.incfg,
                                    nodeid=node.ord,
                                    testid='feature-value-unknown',
                                    message=f"Value {v} is not documented for feature {f} in language [{effective_lang}] ('{utils.formtl(node)}').",
                                    explanation=self.data.explain_feats(effective_lang)
                                ).confirm()
                            elif not node.upos in lfrecord['byupos']:
                                Error(
                                    state=state, config=self.incfg,
                                    nodeid=node.ord,
                                    testid='feature-upos-not-permitted',
                                    message=f"Feature {f} is not permitted with UPOS {node.upos} in language [{effective_lang}] ('{utils.formtl(node)}').",
                                    explanation=self.data.explain_feats(effective_lang)
                                ).confirm()
                            elif not v in lfrecord['byupos'][node.upos] or lfrecord['byupos'][node.upos][v]==0:
                                Error(
                                    state=state, config=self.incfg,
                                    nodeid=node.ord,
                                    testid='feature-value-upos-not-permitted',
                                    message=f"Value {v} of feature {f} is not permitted with UPOS {node.upos} in language [{effective_lang}] ('{utils.formtl(node)}').",
                                    explanation=self.data.explain_feats(effective_lang)
                                ).confirm()



    def check_deprels(self, state, node):
        """
        Checks that a dependency relation label is listed as approved in the
        given language. As a language-specific test, this function belongs to
        level 4. This method currently checks udeprels both in the DEPREL
        column and in the DEPS column.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.
        node : udapi.core.node.Node object
            The node whose incoming relation will be validated.

        Reads from state
        ----------------
        current_node_linenos : dict(str: int)
            Mapping from node ids (including empty nodes) to line numbers in
            the input file.

        Incidents
        ---------
        unknown-deprel
        unknown-edeprel
        """
        Incident.default_lineno = state.current_node_linenos[str(node.ord)]
        Incident.default_level = 4
        Incident.default_testclass = TestClass.SYNTAX
        # List of permited relations is language-specific.
        # The current token may be in a different language due to code switching.
        # Unlike with features and auxiliaries, with deprels it is less clear
        # whether we want to switch the set of labels when the token belongs to
        # another language. Especially with subtypes that are not so much language
        # specific. For example, we may have allowed 'flat:name' for our language,
        # the maintainers of the other language have not allowed it, and then we
        # could not use it when the foreign language is active. (This actually
        # happened in French GSD.) We will thus allow the union of the main and the
        # alternative deprelset when both the parent and the child belong to the
        # same alternative language. Otherwise, only the main deprelset is allowed.
        mainlang = self.lang
        naltlang = utils.get_alt_language(node)
        # The basic relation should be tested on regular nodes but not on empty nodes.
        if not node.is_empty():
            paltlang = utils.get_alt_language(node.parent)
            main_deprelset = self.data.get_deprel_for_language(mainlang)
            alt_deprelset = set()
            if naltlang != None and naltlang != mainlang and naltlang == paltlang:
                alt_deprelset = self.data.get_deprel_for_language(naltlang)
            # Test only the universal part if testing at universal level.
            deprel = node.deprel
            if deprel not in main_deprelset and deprel not in alt_deprelset:
                Error(
                    state=state, config=self.incfg,
                    nodeid=node.ord,
                    testid='unknown-deprel',
                    message=f"Unknown DEPREL label: '{deprel}'",
                    explanation=self.data.explain_deprel(mainlang)
                ).confirm()
        # If there are enhanced dependencies, test their deprels, too.
        # We already know that the contents of DEPS is parsable (deps_list() was
        # first called from check_id_references() and the head indices are OK).
        # The order of enhanced dependencies was already checked in check_deps().
        Incident.default_testclass = TestClass.ENHANCED
        if str(node.deps) != '_':
            main_edeprelset = self.data.get_edeprel_for_language(mainlang)
            alt_edeprelset = self.data.get_edeprel_for_language(naltlang)
            for edep in node.deps:
                parent = edep['parent']
                deprel = edep['deprel']
                paltlang = utils.get_alt_language(parent)
                if not (deprel in main_edeprelset or naltlang != None and naltlang != mainlang and naltlang == paltlang and deprel in alt_edeprelset):
                    Error(
                        state=state, config=self.incfg,
                        nodeid=node.ord,
                        testid='unknown-edeprel',
                        message=f"Unknown enhanced relation type '{deprel}' in '{parent.ord}:{deprel}'",
                        explanation=self.data.explain_edeprel(mainlang)
                    ).confirm()
