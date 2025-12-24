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
    from udtools.src.udtools.incident import Incident, Error, Warning, TestClass
    from udtools.src.udtools.level2 import Level2
except ModuleNotFoundError:
    import udtools.utils as utils
    from udtools.incident import Incident, Error, Warning, TestClass
    from udtools.level2 import Level2



class Level3(Level2):
#==============================================================================
# Level 3 tests. Annotation content vs. the guidelines (only universal tests).
#==============================================================================


    def check_required_feature(self, state, feats, required_feature, required_value, incident):
        """
        In general, the annotation of morphological features is optional, although
        highly encouraged. However, if the treebank does have features, then certain
        features become required. This function will check the presence of a feature
        and if it is missing, an error will be reported only if at least one feature
        has been already encountered. Otherwise the error will be remembered and it
        may be reported afterwards if any feature is encountered later.

        Parameters
        ----------
        feats : udapi.core.dualdict.DualDict object
            The feature-value set to be tested whether they contain the required one.
        required_feature : str
            The name of the required feature.
        required_value : str
            The required value of the feature. Multivalues are not supported (they
            are just a string value containing one or more commas). If
            required_value is None or an empty string, it means that we require any
            non-empty value of required_feature.
        incident : Incident object
            The message that should be printed if the error is confirmed.
        """
        ok = True
        if required_value:
            if feats[required_feature] != required_value:
                ok = False
        else:
            if feats[required_feature] == '':
                ok = False
        if not ok:
            if state.seen_morpho_feature:
                incident.confirm()
            else:
                if not incident.testid in state.delayed_feature_errors:
                    state.delayed_feature_errors[incident.testid] = {'occurrences': []}
                state.delayed_feature_errors[incident.testid]['occurrences'].append({'incident': incident})


    def check_expected_features(self, state, node):
        """
        Certain features are expected to occur with certain UPOS or certain values
        of other features. This function issues warnings instead of errors, as
        features are in general optional and language-specific. Even the warnings
        are issued only if the treebank has features. Note that the expectations
        tested here are considered (more or less) universal. Checking that a given
        feature-value pair is compatible with a particular UPOS is done using
        language-specific lists at level 4.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.
        node : udapi.core.node.Node object
            The tree node to be tested.

        Reads from state
        ----------------
        current_node_linenos : dict(str: int)
            Mapping from node ids (including empty nodes) to line numbers in
            the input file.

        Incidents
        ---------
        pron-det-without-prontype
        verbform-fin-without-mood
        """
        Incident.default_lineno = state.current_node_linenos[str(node.ord)]
        Incident.default_level = 3
        Incident.default_testclass = TestClass.MORPHO
        if node.upos in ['PRON', 'DET']:
            self.check_required_feature(state, node.feats, 'PronType', None, Warning(
                state=state, config=self.incfg,
                testid='pron-det-without-prontype',
                message=f"The word '{utils.formtl(node)}' is tagged '{node.upos}' but it lacks the 'PronType' feature"
            ))
        # See https://github.com/UniversalDependencies/docs/issues/1155 for
        # complaints about this warning.
        if node.feats['VerbForm'] == 'Fin' and node.feats['Mood'] == '':
            Warning(
                state=state, config=self.incfg,
                testid='verbform-fin-without-mood',
                message=f"Finite verb '{utils.formtl(node)}' lacks the 'Mood' feature"
            ).confirm()
        # We have to exclude AUX from the following test because they could be
        # nonverbal and Mood could be their lexical feature
        # (see https://github.com/UniversalDependencies/docs/issues/1147).
        # Update: Lithuanian seems to need Mood=Nec with participles. Turning the test off.
        #elif node.feats['Mood'] != '' and node.feats['VerbForm'] != 'Fin' and not (node.upos == 'AUX' and node.feats['VerbForm'] == ''):
        #    Warning(
        #        state=state, config=self.incfg,
        #        testid='mood-without-verbform-fin',
        #        message=f"Non-empty 'Mood' feature at a word that is not finite verb ('{utils.formtl(node)}')"
        #    ).confirm()



    def check_zero_root(self, state, node):
        """
        Checks that DEPREL is "root" iff HEAD is 0.

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
        0-is-not-root
        root-is-not-0
        enhanced-0-is-not-root
        enhanced-root-is-not-0
        """
        Incident.default_lineno = state.current_node_linenos[str(node.ord)]
        Incident.default_level = 3
        Incident.default_testclass = TestClass.SYNTAX
        if not node.is_empty():
            if node.parent.ord == 0 and node.udeprel != 'root':
                Error(
                    state=state, config=self.incfg,
                    testid='0-is-not-root',
                    message="DEPREL must be 'root' if HEAD is 0."
                ).confirm()
            if node.parent.ord != 0 and node.udeprel == 'root':
                Error(
                    state=state, config=self.incfg,
                    testid='root-is-not-0',
                    message="DEPREL cannot be 'root' if HEAD is not 0."
                ).confirm()
        # In the enhanced graph, test both regular and empty roots.
        for edep in node.deps:
            if edep['parent'].ord == 0 and utils.lspec2ud(edep['deprel']) != 'root':
                Error(
                    state=state, config=self.incfg,
                    testclass=TestClass.ENHANCED,
                    testid='enhanced-0-is-not-root',
                    message="Enhanced relation type must be 'root' if head is 0."
                ).confirm()
            if edep['parent'].ord != 0 and utils.lspec2ud(edep['deprel']) == 'root':
                Error(
                    state=state, config=self.incfg,
                    testclass=TestClass.ENHANCED,
                    testid='enhanced-root-is-not-0',
                    message="Enhanced relation type cannot be 'root' if head is not 0."
                ).confirm()



    def check_upos_vs_deprel(self, state, node):
        """
        For certain relations checks that the dependent word belongs to an expected
        part-of-speech category. Occasionally we may have to check the children of
        the node, too.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.
        node : udapi.core.node.Node object
            The tree node to be tested.

        Reads from state
        ----------------
        current_node_linenos : dict(str: int)
            Mapping from node ids (including empty nodes) to line numbers in
            the input file.

        Incidents
        ---------
        fixed-without-extpos
        rel-upos-det
        rel-upos-nummod
        rel-upos-advmod
        rel-upos-expl
        rel-upos-aux
        rel-upos-cop
        rel-upos-case
        rel-upos-mark
        rel-upos-cc
        rel-upos-punct
        upos-rel-punct
        rel-upos-fixed
        """
        Incident.default_lineno = state.current_node_linenos[str(node.ord)]
        Incident.default_level = 3
        Incident.default_testclass = TestClass.SYNTAX
        # Occasionally a word may be marked by the feature ExtPos as acting as
        # a part of speech different from its usual one (which is given in UPOS).
        # Typical examples are words that head fixed multiword expressions (the
        # whole expression acts like a word of that alien part of speech), but
        # ExtPos may be used also on single words whose external POS is altered.
        upos = node.upos
        # Nodes with a fixed child may need ExtPos to signal the part of speech of
        # the whole fixed expression.
        if node.feats['ExtPos']:
            upos = node.feats['ExtPos']
        # This is a level 3 test, we will check only the universal part of the relation.
        deprel = node.udeprel
        childrels = set([x.udeprel for x in node.children])
        # It is recommended that the head of a fixed expression always has ExtPos,
        # even if it does not need it to pass the tests in this function.
        if 'fixed' in childrels and not node.feats['ExtPos']:
            fixed_forms = [node.form] + [x.form for x in node.children if x.udeprel == 'fixed']
            str_fixed_forms = ' '.join(fixed_forms)
            Warning(
                state=state, config=self.incfg,
                testid='fixed-without-extpos',
                message=f"Fixed expression '{str_fixed_forms}' does not have the 'ExtPos' feature"
            ).confirm()
        # Certain relations are reserved for nominals and cannot be used for verbs.
        # Nevertheless, they can appear with adjectives or adpositions if they are promoted due to ellipsis.
        # Unfortunately, we cannot enforce this test because a word can be cited
        # rather than used, and then it can take a nominal function even if it is
        # a verb, as in this Upper Sorbian sentence where infinitives are appositions:
        # [hsb] Z werba danci "rejować" móže substantiw nastać danco "reja", adjektiw danca "rejowanski" a adwerb dance "rejowansce", ale tež z substantiwa martelo "hamor" móže nastać werb marteli "klepać z hamorom", adjektiw martela "hamorowy" a adwerb martele "z hamorom".
        # Determiner can alternate with a pronoun.
        if deprel == 'det' and not re.match(r"^(DET|PRON)", upos):
            Error(
                state=state, config=self.incfg,
                testid='rel-upos-det',
                message=f"'det' should be 'DET' or 'PRON' but it is '{upos}' ('{utils.formtl(node)}')"
            ).confirm()
        # Nummod is for "number phrases" only. This could be interpreted as NUM only,
        # but some languages treat some cardinal numbers as NOUNs, and in
        # https://github.com/UniversalDependencies/docs/issues/596,
        # we concluded that the validator will tolerate them.
        if deprel == 'nummod' and not re.match(r"^(NUM|NOUN|SYM)$", upos):
            Error(
                state=state, config=self.incfg,
                testid='rel-upos-nummod',
                message=f"'nummod' should be 'NUM' but it is '{upos}' ('{utils.formtl(node)}')"
            ).confirm()
        # Advmod is for adverbs, perhaps particles but not for prepositional phrases or clauses.
        # Nevertheless, we should allow adjectives because they can be used as adverbs in some languages.
        # https://github.com/UniversalDependencies/docs/issues/617#issuecomment-488261396
        # Bohdan reports that some DET can modify adjectives in a way similar to ADV.
        # I am not sure whether advmod is the best relation for them but the alternative
        # det is not much better, so maybe we should not enforce it. Adding DET to the tolerated UPOS tags.
        if deprel == 'advmod' and not re.match(r"^(ADV|ADJ|CCONJ|DET|PART|SYM)", upos) and not 'goeswith' in childrels:
            Error(
                state=state, config=self.incfg,
                testid='rel-upos-advmod',
                message=f"'advmod' should be 'ADV' but it is '{upos}' ('{utils.formtl(node)}')"
            ).confirm()
        # Known expletives are pronouns. Determiners and particles are probably acceptable, too.
        if deprel == 'expl' and not re.match(r"^(PRON|DET|PART)$", upos):
            Error(
                state=state, config=self.incfg,
                testid='rel-upos-expl',
                message=f"'expl' should normally be 'PRON' but it is '{upos}' ('{utils.formtl(node)}')"
            ).confirm()
        # Auxiliary verb/particle must be AUX.
        if deprel == 'aux' and not re.match(r"^(AUX)", upos):
            Error(
                state=state, config=self.incfg,
                testid='rel-upos-aux',
                message=f"'aux' should be 'AUX' but it is '{upos}' ('{utils.formtl(node)}')"
            ).confirm()
        # Copula is an auxiliary verb/particle (AUX) or a pronoun (PRON|DET).
        if deprel == 'cop' and not re.match(r"^(AUX|PRON|DET|SYM)", upos):
            Error(
                state=state, config=self.incfg,
                testid='rel-upos-cop',
                message=f"'cop' should be 'AUX' or 'PRON'/'DET' but it is '{upos}' ('{utils.formtl(node)}')"
            ).confirm()
        # Case is normally an adposition, maybe particle.
        # However, there are also secondary adpositions and they may have the original POS tag:
        # NOUN: [cs] pomocí, prostřednictvím
        # VERB: [en] including
        # Interjection can also act as case marker for vocative, as in Sanskrit: भोः भगवन् / bhoḥ bhagavan / oh sir.
        if deprel == 'case' and re.match(r"^(PROPN|ADJ|PRON|DET|NUM|AUX)", upos):
            Error(
                state=state, config=self.incfg,
                testid='rel-upos-case',
                message=f"'case' should not be '{upos}' ('{utils.formtl(node)}')"
            ).confirm()
        # Mark is normally a conjunction or adposition, maybe particle but definitely not a pronoun.
        ###!!! February 2022: Temporarily allow mark+VERB ("regarding"). In the future, it should be banned again
        ###!!! by default (and case+VERB too), but there should be a language-specific list of exceptions.
        ###!!! In 2024 I wanted to re-enable the test because people could use the
        ###!!! newly approved ExtPos feature to signal that "regarding" is acting
        ###!!! as a function word, but Amir was opposed to the idea that ExtPos would
        ###!!! now be required also for single-word expressions.
        if deprel == 'mark' and re.match(r"^(NOUN|PROPN|ADJ|PRON|DET|NUM|AUX|INTJ)", upos):
            Error(
                state=state, config=self.incfg,
                testid='rel-upos-mark',
                message=f"'mark' should not be '{upos}' ('{utils.formtl(node)}')"
            ).confirm()
        # Cc is a conjunction, possibly an adverb or particle.
        if deprel == 'cc' and re.match(r"^(NOUN|PROPN|ADJ|PRON|DET|NUM|VERB|AUX|INTJ)", upos):
            Error(
                state=state, config=self.incfg,
                testid='rel-upos-cc',
                message=f"'cc' should not be '{upos}' ('{utils.formtl(node)}')"
            ).confirm()
        if deprel == 'punct' and upos != 'PUNCT':
            Error(
                state=state, config=self.incfg,
                testid='rel-upos-punct',
                message=f"'punct' must be 'PUNCT' but it is '{upos}' ('{utils.formtl(node)}')"
            ).confirm()
        if upos == 'PUNCT' and not re.match(r"^(punct|root)", deprel):
            Error(
                state=state, config=self.incfg,
                testid='upos-rel-punct',
                message=f"'PUNCT' must be 'punct' but it is '{node.deprel}' ('{utils.formtl(node)}')"
            ).confirm()
        if upos == 'PROPN' and (deprel == 'fixed' or 'fixed' in childrels):
            Error(
                state=state, config=self.incfg,
                testid='rel-upos-fixed',
                message=f"'fixed' should not be used for proper nouns ('{utils.formtl(node)}')."
            ).confirm()



    def check_flat_foreign(self, state, node):
        """
        flat:foreign is an optional subtype of flat. It is used to connect two words
        in a code-switched segment of foreign words if the annotators did not want
        to provide the analysis according to the source language. If flat:foreign
        is used, both the parent and the child should have the Foreign=Yes feature
        and their UPOS tag should be X.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.
        node : udapi.core.node.Node object
            The tree node to be tested.

        Reads from state
        ----------------
        current_node_linenos : dict(str: int)
            Mapping from node ids (including empty nodes) to line numbers in
            the input file.

        Incidents
        ---------
        flat-foreign-upos-feats
        """
        Incident.default_level = 3
        Incident.default_testclass = TestClass.MORPHO
        if node.deprel != 'flat:foreign':
            return
        parent = node.parent
        if node.upos != 'X' or str(node.feats) != 'Foreign=Yes':
            Warning(
                state=state, config=self.incfg,
                lineno=state.current_node_linenos[str(node.ord)],
                nodeid=node.ord,
                testid='flat-foreign-upos-feats',
                message="The child of a flat:foreign relation should have UPOS X and Foreign=Yes (but no other features)."
            ).confirm()
        if parent.upos != 'X' or str(parent.feats) != 'Foreign=Yes':
            Warning(
                state=state, config=self.incfg,
                lineno=state.current_node_linenos[str(parent.ord)],
                nodeid=parent.ord,
                testid='flat-foreign-upos-feats',
                message="The parent of a flat:foreign relation should have UPOS X and Foreign=Yes (but no other features)."
            ).confirm()



    def check_left_to_right_relations(self, state, node):
        """
        Certain UD relations must always go left-to-right (in the logical order,
        meaning that parent precedes child, disregarding that some languages have
        right-to-left writing systems).
        Here we currently check the rule for the basic dependencies.
        The same should also be tested for the enhanced dependencies!

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.
        node : udapi.core.node.Node object
            The tree node to be tested.

        Reads from state
        ----------------
        current_node_linenos : dict(str: int)
            Mapping from node ids (including empty nodes) to line numbers in
            the input file.

        Incidents
        ---------
        right-to-left-conj
        right-to-left-fixed
        right-to-left-flat
        right-to-left-goeswith
        right-to-left-appos
        """
        # According to the v2 guidelines, apposition should also be left-headed, although the definition of apposition may need to be improved.
        if node.udeprel in ['conj', 'fixed', 'flat', 'goeswith', 'appos']:
            ichild = node.ord
            iparent = node.parent.ord
            if ichild < iparent:
                # We must recognize the relation type in the test id so we can manage exceptions for legacy treebanks.
                # For conj, flat, and fixed the requirement was introduced already before UD 2.2.
                # For appos and goeswith the requirement was introduced before UD 2.4.
                # The designation "right-to-left" is confusing in languages with right-to-left writing systems.
                # We keep it in the testid but we make the testmessage more neutral.
                Error(
                    state=state, config=self.incfg,
                    lineno=state.current_node_linenos[str(node.ord)],
                    nodeid=node.ord,
                    level=3,
                    testclass=TestClass.SYNTAX,
                    testid=f"right-to-left-{node.udeprel}",
                    message=f"Parent of relation '{node.deprel}' must precede the child in the word order."
                ).confirm()



    def check_single_subject(self, state, node):
        """
        No predicate should have more than one subject.
        An xcomp dependent normally has no subject, but in some languages the
        requirement may be weaker: it could have an overt subject if it is
        correferential with a particular argument of the matrix verb. Hence we do
        not check zero subjects of xcomp dependents at present.
        Furthermore, in some situations we must allow multiple subjects. If a clause
        acts as a nonverbal predicate of another clause, then we must attach two
        subjects to the predicate of the inner clause: one is the predicate of the
        inner clause, the other is the predicate of the outer clause. This could in
        theory be recursive but in practice it isn't. As of UD 2.10, an amendment
        of the guidelines says that the inner predicate of the predicate clause
        should govern both subjects even if there is a copula (previously such
        cases were an exception from the UD approach that copulas should not be
        heads); however, the outer subjects should be attached as [nc]subj:outer.
        See https://universaldependencies.org/changes.html#multiple-subjects.
        See also issue 34 (https://github.com/UniversalDependencies/tools/issues/34).
        Strictly speaking, :outer is optional because it is a subtype, and some
        treebanks may want to avoid it. For example, in Coptic Scriptorium, there
        is only one occurrence in dev, one in test, and none in train, so it would
        be impossible to train a parser that gets it right. For that reason, it is
        possible to replace the :outer subtype with Subject=Outer in MISC. The MISC
        attribute is just a directive for the validator and no parser is expected
        to predict it.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.
        node : udapi.core.node.Node object
            The tree node to be tested.

        Reads from state
        ----------------
        current_node_linenos : dict(str: int)
            Mapping from node ids (including empty nodes) to line numbers in
            the input file.

        Incidents
        ---------
        too-many-subjects
        """

        def is_inner_subject(node):
            """
            Takes a node (udapi.core.node.Node). Tells whether the node's deprel is
            nsubj or csubj without the :outer subtype. Alternatively, instead of the
            :outer subtype, the node could have Subject=Outer in MISC.
            """
            if not re.search(r'subj', node.udeprel):
                return False
            if re.match(r'^[nc]subj:outer$', node.deprel):
                return False
            if node.misc['Subject'] == 'Outer':
                return False
            return True

        subjects = [x for x in node.children if is_inner_subject(x)]
        subject_ids = [x.ord for x in subjects]
        subject_forms = [utils.formtl(x) for x in subjects]
        subject_references = utils.create_references(subjects, state, 'Subject')
        if len(subjects) > 1:
            Error(
                state=state, config=self.incfg,
                lineno=state.current_node_linenos[str(node.ord)],
                nodeid=node.ord,
                level=3,
                testclass=TestClass.SYNTAX,
                testid='too-many-subjects',
                message=f"Multiple subjects {str(subject_ids)} ({str(subject_forms)[1:-1]}) under the predicate '{utils.formtl(node)}' not subtyped as ':outer'.",
                explanation="Outer subjects are allowed if a clause acts as the predicate of another clause.",
                references=subject_references
            ).confirm()



    def check_single_object(self, state, node):
        """
        No predicate should have more than one direct object (number of indirect
        objects is unlimited). Theoretically, ccomp should be understood as a
        clausal equivalent of a direct object, but we do not have an indirect
        equivalent, so it seems better to tolerate additional ccomp at present.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.
        node : udapi.core.node.Node object
            The tree node to be tested.

        Reads from state
        ----------------
        current_node_linenos : dict(str: int)
            Mapping from node ids (including empty nodes) to line numbers in
            the input file.

        Incidents
        ---------
        too-many-objects
        """
        objects = [x for x in node.children if x.udeprel == 'obj']
        object_ids = [x.ord for x in objects]
        object_forms = [utils.formtl(x) for x in objects]
        object_references = utils.create_references(objects, state, 'Object')
        if len(objects) > 1:
            Error(
                state=state, config=self.incfg,
                lineno=state.current_node_linenos[str(node.ord)],
                nodeid=node.ord,
                level=3,
                testclass=TestClass.SYNTAX,
                testid='too-many-objects',
                message=f"Multiple direct objects {str(object_ids)} ({str(object_forms)[1:-1]}) under the predicate '{utils.formtl(node)}'.",
                references=object_references
            ).confirm()



    def check_nmod_obl(self, state, node):
        """
        The difference between nmod and obl is that the former modifies a
        nominal while the latter modifies a predicate of a clause. Typically
        the parent of nmod will be NOUN, PROPN or PRON; the parent of obl is
        usually a VERB, sometimes ADJ or ADV. However, nominals can also be
        predicates and then they may take obl dependents:
            I am the leader of the group (nmod)
            I am the leader on Mondays (obl)
        This function tries to detect at least some cases where the nominal
        is not a predicate and thus cannot take obl dependents.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.
        node : udapi.core.node.Node object
            The tree node to be tested.

        Reads from state
        ----------------
        current_node_linenos : dict(str: int)
            Mapping from node ids (including empty nodes) to line numbers in
            the input file.

        Incidents
        ---------
        obl-should-be-nmod
        """
        if node.udeprel == 'obl' and node.parent.upos in ['NOUN', 'PROPN', 'PRON']:
            # If the parent itself has certain deprels, we know that it is just
            # a nominal and not a predicate. This will reveal some erroneous
            # obliques but not all, because we will not recognize some non-
            # predicative nominals, and even for the predicative ones, some
            # dependents might be better analyzed as nmod.
            if node.parent.udeprel in ['nsubj', 'obj', 'iobj', 'obl', 'vocative', 'dislocated', 'expl', 'nmod']:
                # For the moment (2025-09-20), I am making this a warning only.
                # But I suppose that it will became an error in the future.
                Error(
                    state=state, config=self.incfg,
                    lineno=state.current_node_linenos[str(node.ord)],
                    nodeid=node.ord,
                    level=3,
                    testclass=TestClass.SYNTAX,
                    testid='obl-should-be-nmod',
                    message=f"The parent (node [{node.parent.ord}] '{utils.formtl(node.parent)}') is a nominal (and not a predicate), hence the relation should be 'nmod', not 'obl'.",
                    references=utils.create_references([node.parent], state, 'Parent')
                ).confirm()



    def check_orphan(self, state, node):
        """
        The orphan relation is used to attach an unpromoted orphan to the promoted
        orphan in gapping constructions. A common error is that the promoted orphan
        gets the orphan relation too. The parent of orphan is typically attached
        via a conj relation, although some other relations are plausible too.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.
        node : udapi.core.node.Node object
            The tree node to be tested.

        Reads from state
        ----------------
        current_node_linenos : dict(str: int)
            Mapping from node ids (including empty nodes) to line numbers in
            the input file.

        Incidents
        ---------
        orphan-parent
        """
        # This is a level 3 test, we will check only the universal part of the relation.
        if node.udeprel == 'orphan':
            # We include advcl because gapping (or something very similar) can also
            # occur in subordinate clauses: "He buys companies like my mother [does] vegetables."
            # In theory, a similar pattern could also occur with reparandum.
            # A similar pattern also occurs with acl, e.g. in Latvian:
            # viņš ēd tos ābolus, ko pirms tam [ēda] tārpi ('he eats the same apples, which were [eaten] by worms before that')
            # Other clausal heads (ccomp, csubj) may be eligible as well, e.g. in Latvian
            # (see also issue 635 2019-09-19):
            # atjēdzos, ka bez angļu valodas nekur [netikšu] '[I] realised, that [I will get] nowhere without English'
            # 2023-04-14: Reclassifying the test as warning only. Due to promotion,
            # the parent of orphan may receive many other relations. See issue 635
            # for details and a Latin example.
            if not re.match(r"^(conj|parataxis|root|csubj|ccomp|advcl|acl|reparandum)$", node.parent.udeprel):
                Warning(
                    state=state, config=self.incfg,
                    lineno=state.current_node_linenos[str(node.ord)],
                    nodeid=node.ord,
                    level=3,
                    testclass=TestClass.SYNTAX,
                    testid='orphan-parent',
                    message=f"The parent of 'orphan' should normally be 'conj' but it is '{node.parent.udeprel}'.",
                    references=utils.create_references([node.parent], state, 'Parent')
                ).confirm()



    def check_functional_leaves(self, state, node):
        """
        Most of the time, function-word nodes should be leaves. This function
        checks for known exceptions and warns in the other cases.
        (https://universaldependencies.org/u/overview/syntax.html#function-word-modifiers)

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.
        node : udapi.core.node.Node object
            The tree node to be tested.

        Reads from state
        ----------------
        current_node_linenos : dict(str: int)
            Mapping from node ids (including empty nodes) to line numbers in
            the input file.

        Incidents
        ---------
        leaf-mark-case
        leaf-aux-cop
        leaf-det
        leaf-clf
        leaf-cc
        leaf-fixed
        leaf-goeswith
        leaf-punct
        """
        # This is a level 3 test, we will check only the universal part of the relation.
        deprel = node.udeprel
        if deprel in ['case', 'mark', 'cc', 'aux', 'cop', 'det', 'clf', 'fixed', 'goeswith', 'punct']:
            idparent = node.ord
            pdeprel = deprel
            pfeats = node.feats
            for child in node.children:
                idchild = child.ord
                Incident.default_lineno = state.current_node_linenos[str(idchild)]
                Incident.default_level = 3
                Incident.default_testclass = TestClass.SYNTAX
                cdeprel = child.udeprel
                # The guidelines explicitly say that negation can modify any function word
                # (see https://universaldependencies.org/u/overview/syntax.html#function-word-modifiers).
                # We cannot recognize negation simply by deprel; we have to look at the
                # part-of-speech tag and the Polarity feature as well.
                cupos = child.upos
                cfeats = child.feats
                if pdeprel != 'punct' and cdeprel == 'advmod' and re.match(r"^(PART|ADV)$", cupos) and cfeats['Polarity'] == 'Neg':
                    continue
                # Punctuation should not depend on function words if it can be projectively
                # attached to a content word. But sometimes it cannot. Czech example:
                # "Budou - li však zbývat , ukončíme" (lit. "will - if however remain , we-stop")
                # "však" depends on "ukončíme" while "budou" and "li" depend nonprojectively
                # on "zbývat" (which depends on "ukončíme"). "Budou" is aux and "li" is mark.
                # Yet the hyphen must depend on one of them because any other attachment would
                # be non-projective. Here we assume that if the parent of a punctuation node
                # is attached nonprojectively, punctuation can be attached to it to avoid its
                # own nonprojectivity.
                if node.is_nonprojective() and cdeprel == 'punct':
                    continue
                # Auxiliaries, conjunctions and case markers will tollerate a few special
                # types of modifiers.
                # Punctuation should normally not depend on a functional node. However,
                # it is possible that a functional node such as auxiliary verb is in
                # quotation marks or brackets ("must") and then these symbols should depend
                # on the functional node. We temporarily allow punctuation here, until we
                # can detect precisely the bracket situation and disallow the rest.
                # According to the guidelines
                # (https://universaldependencies.org/u/overview/syntax.html#function-word-modifiers),
                # mark can have a limited set of adverbial/oblique dependents, while the same
                # is not allowed for nodes attached as case. Nevertheless, there are valid
                # objections against this (see https://github.com/UniversalDependencies/docs/issues/618)
                # and we may want to revisit the guideline in UD v3. For the time being,
                # we make the validator more benevolent to 'case' too. (If we now force people
                # to attach adverbials higher, information will be lost and later reversal
                # of the step will not be possible.)
                # Coordinating conjunctions usually depend on a non-first conjunct, i.e.,
                # on a node whose deprel is 'conj'. However, there are paired conjunctions
                # such as "both-and", "either-or". Here the first part is attached to the
                # first conjunct. Since some function nodes (mark, case, aux, cop) can be
                # coordinated, we must allow 'cc' children under these nodes, too. However,
                # we do not want to allow 'cc' under another 'cc'. (Still, 'cc' can have
                # a 'conj' dependent. In "and/or", "or" will depend on "and" as 'conj'.)
                if re.match(r"^(mark|case)$", pdeprel) and not re.match(r"^(advmod|obl|goeswith|fixed|reparandum|conj|cc|punct)$", cdeprel):
                    Error(
                        state=state, config=self.incfg,
                        nodeid=node.ord,
                        testid='leaf-mark-case',
                        message=f"'{pdeprel}' not expected to have children ({idparent}:{node.form}:{pdeprel} --> {idchild}:{child.form}:{cdeprel})"
                    ).confirm()
                if re.match(r"^(aux|cop)$", pdeprel) and not re.match(r"^(goeswith|fixed|reparandum|conj|cc|punct)$", cdeprel):
                    Error(
                        state=state, config=self.incfg,
                        nodeid=node.ord,
                        testid='leaf-aux-cop',
                        message=f"'{pdeprel}' not expected to have children ({idparent}:{node.form}:{pdeprel} --> {idchild}:{child.form}:{cdeprel})"
                    ).confirm()
                # Classifiers must be allowed under demonstrative determiners according to the clf guidelines.
                # People have identified various constructions where the restriction
                # on children of det dependents may have to be relaxed even if not
                # mentioned directly in the universal guidelines.
                # https://universaldependencies.org/workgroups/newdoc/children_of_determiners.html
                # Latvian: There are compound determiners, composed of a PART and a head PRON.
                # They are not fixed, so they need a separate exception for the compound deprel.
                # (Laura, https://github.com/UniversalDependencies/docs/issues/1059#issuecomment-2413484624)
                # Hebrew: Demonstrative pronouns have their own determiners, as in “the men the these” = “these men”.
                # It is also parallel to how adjectival modification works in Modern Hebrew.
                # Maybe determiners under demonstratives could be allowed in some languages but not the others?
                # (Daniel, https://github.com/UniversalDependencies/docs/issues/1059#issuecomment-2400694043)
                # Classical Armenian: Case marker may be repeated both at a noun and at its demonstrative.
                # We probably should allow demonstratives to have their own case child, but ideally we should
                # not allow it for all determiners in all languages because it opens the door for errors
                # (currently there are such errors in Chinese data). ###!!! For now I am allowing it everywhere.
                # (Petr, https://github.com/UniversalDependencies/docs/issues/1059#issuecomment-2441260051)
                # Spoken data:
                # There is a lot of fillers ("euh"), tagged INTJ and attached as discourse
                # "to the most relevant nearby unit" (that is the guideline). The most
                # relevant nearby unit may be a determiner. Similarly, parentheticals
                # should be attached as parataxis to the most relevant unit, and again
                # the unit is not necessarily a clause. For example, Latvian:
                # "tādā godīgā iestādē ieperinājušies daži (tikai daži!) zagļi"
                # “a few (only a few!) thieves have nested in such an honest institution”
                # (Laura, https://github.com/UniversalDependencies/docs/issues/1059#issuecomment-2438448236)
                # Several treebanks have problems with possessive determiners, which
                # are referential and can thus take dependents such as appos, acl:relcl, even nmod.
                # Joakim thinks that such possessives should be nmod rather than det,
                # but that's not how many of us understand the UD guidelines. For now,
                # the test should be thus relaxed if the determiner has Poss=Yes.
                # Flavio also argued that certain multiword det expressions should be
                # connected by flat:redup (rather than fixed), which is why flat should
                # be another exception.
                if re.match(r"^(det)$", pdeprel) and not re.match(r"^(det|case|advmod|obl|clf|goeswith|fixed|flat|compound|reparandum|discourse|parataxis|conj|cc|punct)$", cdeprel) and not (pfeats['Poss'] == 'Yes' and re.match(r"^(appos|acl|nmod)$", cdeprel)):
                    Error(
                        state=state, config=self.incfg,
                        nodeid=node.ord,
                        testid='leaf-det',
                        message=f"'{pdeprel}' not expected to have children ({idparent}:{node.form}:{pdeprel} --> {idchild}:{child.form}:{cdeprel})"
                    ).confirm()
                if re.match(r"^(clf)$", pdeprel) and not re.match(r"^(advmod|obl|goeswith|fixed|reparandum|conj|cc|punct)$", cdeprel):
                    Error(
                        state=state, config=self.incfg,
                        nodeid=node.ord,
                        testid='leaf-clf',
                        message=f"'{pdeprel}' not expected to have children ({idparent}:{node.form}:{pdeprel} --> {idchild}:{child.form}:{cdeprel})"
                    ).confirm()
                if re.match(r"^(cc)$", pdeprel) and not re.match(r"^(goeswith|fixed|reparandum|conj|punct)$", cdeprel):
                    Error(
                        state=state, config=self.incfg,
                        nodeid=node.ord,
                        testid='leaf-cc',
                        message=f"'{pdeprel}' not expected to have children ({idparent}:{node.form}:{pdeprel} --> {idchild}:{child.form}:{cdeprel})"
                    ).confirm()
                # Fixed expressions should not be nested, i.e., no chains of fixed relations.
                # As they are supposed to represent functional elements, they should not have
                # other dependents either, with the possible exception of conj.
                # We also allow a punct child, at least temporarily, because of fixed
                # expressions that have a hyphen in the middle (e.g. Russian "вперед-назад").
                # It would be better to keep these expressions as one token. But sometimes
                # the tokenizer is out of control of the UD data providers and it is not
                # practical to retokenize.
                elif pdeprel == 'fixed' and not re.match(r"^(goeswith|reparandum|conj|punct)$", cdeprel):
                    Error(
                        state=state, config=self.incfg,
                        nodeid=node.ord,
                        testid='leaf-fixed',
                        message=f"'{pdeprel}' not expected to have children ({idparent}:{node.form}:{pdeprel} --> {idchild}:{child.form}:{cdeprel})"
                    ).confirm()
                # Goeswith cannot have any children, not even another goeswith.
                elif pdeprel == 'goeswith':
                    Error(
                        state=state, config=self.incfg,
                        nodeid=node.ord,
                        testid='leaf-goeswith',
                        message=f"'{pdeprel}' not expected to have children ({idparent}:{node.form}:{pdeprel} --> {idchild}:{child.form}:{cdeprel})"
                    ).confirm()
                # Punctuation can exceptionally have other punct children if an exclamation
                # mark is in brackets or quotes. It cannot have other children.
                elif pdeprel == 'punct' and cdeprel != 'punct':
                    Error(
                        state=state, config=self.incfg,
                        nodeid=node.ord,
                        testid='leaf-punct',
                        message=f"'{pdeprel}' not expected to have children ({idparent}:{node.form}:{pdeprel} --> {idchild}:{child.form}:{cdeprel})"
                    ).confirm()



    def check_fixed_span(self, state, node):
        """
        Like with goeswith, the fixed relation should not in general skip words that
        are not part of the fixed expression. Unlike goeswith however, there can be
        an intervening punctuation symbol. Moreover, the rule that fixed expressions
        cannot be discontiguous has been challenged with examples from Swedish and
        Coptic, see https://github.com/UniversalDependencies/docs/issues/623.
        Hence, the test was turned off 2019-04-13. I am re-activating it 2023-09-03
        as just a warning.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.
        node : udapi.core.node.Node object
            The tree node to be tested.

        Reads from state
        ----------------
        current_node_linenos : dict(str: int)
            Mapping from node ids (including empty nodes) to line numbers in
            the input file.

        Incidents
        ---------
        fixed-gap
        """
        fxchildren = [c for c in node.children if c.udeprel == 'fixed']
        if fxchildren:
            fxlist = sorted([node] + fxchildren)
            fxrange = [n for n in node.root.descendants if n.ord >= node.ord and n.ord <= fxchildren[-1].ord]
            # All nodes between me and my last fixed child should be either fixed or punct.
            fxgap = [n for n in fxrange if n.udeprel != 'punct' and n not in fxlist]
            if fxgap:
                fxordlist = [n.ord for n in fxlist]
                fxexpr = ' '.join([(n.form if n in fxlist else '*') for n in fxrange])
                Warning(
                    state=state, config=self.incfg,
                    lineno=state.current_node_linenos[str(node.ord)],
                    nodeid=node.ord,
                    level=3,
                    testclass=TestClass.SYNTAX,
                    testid='fixed-gap',
                    message=f"Gaps in fixed expression {str(fxordlist)} '{fxexpr}'"
                ).confirm()


    def check_goeswith_span(self, state, node):
        """
        The relation 'goeswith' is used to connect word parts that are separated
        by whitespace and should be one word instead. We assume that the relation
        goes left-to-right, which is checked elsewhere. Here we check that the
        nodes really were separated by whitespace. If there is another node in the
        middle, it must be also attached via 'goeswith'. The parameter id refers to
        the node whose goeswith children we test.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.
        node : udapi.core.node.Node object
            The tree node to be tested.

        Reads from state
        ----------------
        current_node_linenos : dict(str: int)
            Mapping from node ids (including empty nodes) to line numbers in
            the input file.

        Incidents
        ---------
        goeswith-gap
        goeswith-nospace
        goeswith-missing-typo
        """
        Incident.default_lineno = state.current_node_linenos[str(node.ord)]
        Incident.default_level = 3
        Incident.default_testclass = TestClass.SYNTAX
        gwchildren = [c for c in node.children if c.udeprel == 'goeswith']
        if gwchildren:
            gwlist = sorted([node] + gwchildren)
            gwrange = [n for n in node.root.descendants if n.ord >= node.ord and n.ord <= gwchildren[-1].ord]
            # All nodes between me and my last goeswith child should be goeswith too.
            if gwlist != gwrange:
                gwordlist = [n.ord for n in gwlist]
                gwordrange = [n.ord for n in gwrange]
                Error(
                    state=state, config=self.incfg,
                    nodeid=node.ord,
                    testid='goeswith-gap',
                    message=f"Gaps in goeswith group {str(gwordlist)} != {str(gwordrange)}."
                ).confirm()
            # Non-last node in a goeswith range must have a space after itself.
            nospaceafter = [x for x in gwlist[:-1] if x.misc['SpaceAfter'] == 'No']
            if nospaceafter:
                Error(
                    state=state, config=self.incfg,
                    nodeid=node.ord,
                    testid='goeswith-nospace',
                    message="'goeswith' cannot connect nodes that are not separated by whitespace."
                ).confirm()
            # This is not about the span of the interrupted word, but since we already
            # know that we are at the head of a goeswith word, let's do it here, too.
            # Every goeswith parent should also have Typo=Yes. However, this is not
            # required if the treebank does not have features at all.
            incident = Error(
                state=state, config=self.incfg,
                nodeid=node.ord,
                testclass=TestClass.MORPHO,
                testid='goeswith-missing-typo',
                message="Since the treebank has morphological features, 'Typo=Yes' must be used with 'goeswith' heads."
            )
            self.check_required_feature(state, node.feats, 'Typo', 'Yes', incident)



    def check_goeswith_morphology_and_edeps(self, state, node):
        """
        If a node has the 'goeswith' incoming relation, it is a non-first part of
        a mistakenly interrupted word. The lemma, upos tag and morphological features
        of the word should be annotated at the first part, not here.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.
        node : udapi.core.node.Node object
            The tree node to be tested.

        Reads from state
        ----------------
        current_node_linenos : dict(str: int)
            Mapping from node ids (including empty nodes) to line numbers in
            the input file.

        Incidents
        ---------
        goeswith-lemma
        goeswith-upos
        goeswith-feats
        goeswith-edeps
        """
        Incident.default_lineno = state.current_node_linenos[str(node.ord)]
        Incident.default_level = 3
        Incident.default_testclass = TestClass.MORPHO
        if node.udeprel == 'goeswith':
            if node.lemma != '_':
                Error(
                    state=state, config=self.incfg,
                    nodeid=node.ord,
                    testid='goeswith-lemma',
                    message="The lemma of a 'goeswith'-connected word must be annotated only at the first part."
                ).confirm()
            if node.upos != 'X':
                Error(
                    state=state, config=self.incfg,
                    nodeid=node.ord,
                    testid='goeswith-upos',
                    message="The UPOS tag of a 'goeswith'-connected word must be annotated only at the first part; the other parts must be tagged 'X'."
                ).confirm()
            if str(node.feats) != '_':
                Error(
                    state=state, config=self.incfg,
                    nodeid=node.ord,
                    testid='goeswith-feats',
                    message="The morphological features of a 'goeswith'-connected word must be annotated only at the first part."
                ).confirm()
            if str(node.raw_deps) != '_' and str(node.raw_deps) != str(node.parent.ord)+':'+node.deprel:
                Error(
                    state=state, config=self.incfg,
                    nodeid=node.ord,
                    testclass=TestClass.ENHANCED,
                    testid='goeswith-edeps',
                    message="A 'goeswith' dependent cannot have any additional dependencies in the enhanced graph."
                ).confirm()



    def check_projective_punctuation(self, state, node):
        """
        Punctuation is not supposed to cause nonprojectivity or to be attached
        nonprojectively.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.
        node : udapi.core.node.Node object
            The tree node to be tested.

        Reads from state
        ----------------
        current_node_linenos : dict(str: int)
            Mapping from node ids (including empty nodes) to line numbers in
            the input file.

        Incidents
        ---------
        punct-causes-nonproj
        punct-is-nonproj
        """
        Incident.default_lineno = state.current_node_linenos[str(node.ord)]
        Incident.default_level = 3
        Incident.default_testclass = TestClass.SYNTAX
        if node.udeprel == 'punct':
            nonprojnodes = utils.get_caused_nonprojectivities(node)
            if nonprojnodes:
                nonprojids = [x.ord for x in nonprojnodes]
                Error(
                    state=state, config=self.incfg,
                    nodeid=node.ord,
                    testid='punct-causes-nonproj',
                    message=f"Punctuation must not cause non-projectivity of nodes {nonprojids}",
                    references=utils.create_references(nonprojnodes, state, 'Node made nonprojective')
                ).confirm()
            gapnodes = utils.get_gap(node)
            if gapnodes:
                gapids = [x.ord for x in gapnodes]
                Error(
                    state=state, config=self.incfg,
                    nodeid=node.ord,
                    testid='punct-is-nonproj',
                    message=f"Punctuation must not be attached non-projectively over nodes {gapids}",
                    references=utils.create_references(gapnodes, state, 'Node in gap')
                ).confirm()



    def check_enhanced_orphan(self, state, node):
        """
        Checks universally valid consequences of the annotation guidelines in the
        enhanced representation. Currently tests only phenomena specific to the
        enhanced dependencies; however, we should also test things that are
        required in the basic dependencies (such as left-to-right coordination),
        unless it is obvious that in enhanced dependencies such things are legal.

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
        empty-node-after-eorphan
        eorphan-after-empty-node
        """
        lineno = state.current_node_linenos[str(node.ord)]
        Incident.default_lineno = lineno
        Incident.default_level = 3
        Incident.default_testclass = TestClass.ENHANCED
        # Enhanced dependencies should not contain the orphan relation.
        # However, all types of enhancements are optional and orphans are excluded
        # only if this treebank addresses gapping. We do not know it until we see
        # the first empty node.
        if str(node.deps) == '_':
            return
        if node.is_empty():
            if not state.seen_empty_node:
                state.seen_empty_node = lineno
                # Empty node itself is not an error. Report it only for the first time
                # and only if an orphan occurred before it.
                if state.seen_enhanced_orphan:
                    Error(
                        state=state, config=self.incfg,
                        nodeid=node.ord,
                        testid='empty-node-after-eorphan',
                        message=f"Empty node means that we address gapping and there should be no orphans in the enhanced graph; but we saw one on line {state.seen_enhanced_orphan}"
                    ).confirm()
        udeprels = set([utils.lspec2ud(edep['deprel']) for edep in node.deps])
        if 'orphan' in udeprels:
            if not state.seen_enhanced_orphan:
                state.seen_enhanced_orphan = lineno
            # If we have seen an empty node, then the orphan is an error.
            if  state.seen_empty_node:
                Error(
                    state=state, config=self.incfg,
                    nodeid=node.ord,
                    testid='eorphan-after-empty-node',
                    message=f"'orphan' not allowed in enhanced graph because we saw an empty node on line {state.seen_empty_node}"
                ).confirm()
