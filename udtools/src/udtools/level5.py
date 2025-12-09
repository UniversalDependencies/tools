#! /usr/bin/env python3
# Original code (2015) by Filip Ginter and Sampo Pyysalo.
# DZ 2018-11-04: Porting the validator to Python 3.
# DZ: Many subsequent changes. See the git history.
# Allow using this module from the root folder of tools even if it is not
# installed as a package: use the relative path validator/src/validator for
# submodules. If the path is not available, try the standard qualification,
# assuming that the user has installed udtools from PyPI and then called
# from udtools import Validator.
try:
    import udtools.src.udtools.utils as utils
    from udtools.src.udtools.incident import Error, TestClass
    from udtools.src.udtools.level4 import Level4
except ModuleNotFoundError:
    import udtools.utils as utils
    from udtools.incident import Error, TestClass
    from udtools.level4 import Level4



class Level5(Level4):
#==============================================================================
# Level 5 tests. Annotation content vs. the guidelines, language-specific.
#==============================================================================



    def check_auxiliary_verbs(self, state, node):
        """
        Verifies that the UPOS tag AUX is used only with lemmas that are known to
        act as auxiliary verbs or particles in the given language.

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
        aux-lemma
        """
        if node.upos == 'AUX' and node.lemma != '_':
            lang = self.lang
            altlang = utils.get_alt_language(node)
            if altlang:
                lang = altlang
            auxlist = self.data.get_aux_for_language(lang)
            if not auxlist or not node.lemma in auxlist:
                Error(
                    state=state, config=self.incfg,
                    lineno=state.current_node_linenos[str(node.ord)],
                    nodeid=node.ord,
                    level=5,
                    testclass=TestClass.MORPHO,
                    testid='aux-lemma',
                    message=f"'{utils.lemmatl(node)}' is not an auxiliary in language [{lang}]",
                    explanation=self.data.explain_aux(lang)
                ).confirm()



    def check_copula_lemmas(self, state, node):
        """
        Verifies that the relation cop is used only with lemmas that are known to
        act as copulas in the given language.

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
        cop-lemma
        """
        if node.udeprel == 'cop' and node.lemma != '_':
            lang = self.lang
            altlang = utils.get_alt_language(node)
            if altlang:
                lang = altlang
            coplist = self.data.get_cop_for_language(lang)
            if not coplist or not node.lemma in coplist:
                Error(
                    state=state, config=self.incfg,
                    lineno=state.current_node_linenos[str(node.ord)],
                    nodeid=node.ord,
                    level=5,
                    testclass=TestClass.SYNTAX,
                    testid='cop-lemma',
                    message=f"'{utils.lemmatl(node)}' is not a copula in language [{lang}]",
                    explanation=self.data.explain_cop(lang)
                ).confirm()
