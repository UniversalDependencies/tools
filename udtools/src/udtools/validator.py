#! /usr/bin/env python3
# Original code (2015) by Filip Ginter and Sampo Pyysalo.
# DZ 2018-11-04: Porting the validator to Python 3.
# DZ: Many subsequent changes. See the git history.
import sys
import io
import argparse
# Once we know that the low-level CoNLL-U format is OK, we will be able to use
# the Udapi library to access the data and perform the tests at higher levels.
import udapi.block.read.conllu
# Allow using this module from the root folder of tools even if it is not
# installed as a package: use the relative path validator/src/validator for
# submodules. If the path is not available, try the standard qualification,
# assuming that the user has installed udtools from PyPI and then called
# from udtools import Validator.
try:
    import udtools.src.udtools.utils as utils
    from udtools.src.udtools.incident import Error, TestClass
    from udtools.src.udtools.state import State
    import udtools.src.udtools.data as data
    from udtools.src.udtools.level6 import Level6
except ModuleNotFoundError:
    import udtools.utils as utils
    from udtools.incident import Error, TestClass
    from udtools.state import State
    import udtools.data as data
    from udtools.level6 import Level6



class Validator(Level6):
    def __init__(self, lang=None, level=None, check_coref=None, args=None, datapath=None, output=sys.stderr, max_store=0):
        """
        Initialization of the Validator class.

        Parameters
        ----------
        lang : str
            ISO code of the main language of the data to be validated.
            If not provided separately, it will be searched for in args.
            If not provided in args either, default is 'ud' (no lang-spec tests).
        level : int
            Validation level ranging from 1 to 5.
            If not provided separately, it will be searched for in args.
            If not provided in args either, default is 5 (all UD tests).
        check_coref: bool
            Should the optional coreference-related tests be performed?
            If not provided separately, it will be searched for in args.
            The default value is False.
        args : argparse.Namespace, optional
            Parsed commandline arguments, if any. The default is None.
            Validator itself does not need to search this namespace unless one
            of its own arguments (lang, level... see above) is not provided
            directly to the constructor. However, there may be other arguments
            that have to be passed to the Incident class whenever an incident
            (error or warning) is recorded by the Validator.
        datapath : str, optional
            Path to the folder with JSON files specifying language-specific
            behavior. If not provided, the Data class will try expected
            locations relative to the module.
        output : outstream object, default sys.stderr
            Where to report incidents when they are encountered. Default is
            sys.stderr, it could be also sys.stdout, an open file handle, or
            None. If it is None, the output is suppressed (same as the --quiet
            command line option) and errors are only saved in state for later
            processing.
        max_store : int, optional
            How many incidents to store in the validation state? Default 0
            means no limit. Limiting this helps save memory with large
            treebanks and large numbers of incidents. Especially if the
            intended use of the Validator object is to immediately report
            incidents without returning to them later. The limit is applied
            separately to each test class.
        """
        self.data = data.Data(datapath=datapath)
        if not args:
            args = argparse.Namespace()
        # Since we allow args that were not created by our ArgumentParser,
        # we must be prepared that some attributes do not exist. It will be
        # thus safer to access them as a dictionary.
        args_dict = vars(args)
        if not lang:
            if 'lang' in args_dict and args_dict['lang'] != None:
                lang = args_dict['lang']
            else:
                lang = 'ud'
        if not level:
            if 'level' in args_dict and args_dict['level'] != None:
                level = args_dict['level']
            else:
                level = 5
        if check_coref == None:
            if 'check_coref' in args_dict and args_dict['check_coref'] != None:
                check_coref = args_dict['check_coref']
            else:
                check_coref = False
        self.lang = lang
        self.level = level
        self.check_coref = check_coref
        # Instead of saving the args namespace, we should just save the
        # configuration of incident storing and reporting.
        self.incfg = {}
        if 'quiet' in args_dict:
            self.incfg['quiet'] = args_dict['quiet']
        if 'no_warnings' in args_dict:
            self.incfg['no_warnings'] = args_dict['no_warnings']
        if 'exclude' in args_dict and args_dict['exclude']:
            self.incfg['exclude'] = args_dict['exclude']
        if 'include_only' in args_dict and args_dict['include_only']:
            self.incfg['include_only'] = args_dict['include_only']
        if 'max_err' in args_dict:
            self.incfg['max_err'] = args_dict['max_err']
        if 'input' in args_dict and len(args_dict['input']) > 1:
            self.incfg['report_filename'] = True
        self.incfg['output'] = output
        self.incfg['max_store'] = max_store
        self.conllu_reader = udapi.block.read.conllu.Conllu()



#==============================================================================
# Entry points.
#==============================================================================


    def validate_files(self, filenames, state=None):
        """
        The main entry point, takes a list of filenames that constitute
        the treebank to be validated. Note that there are tests that consider
        data from the whole treebank across file boundaries, for example the
        uniqueness of sentence ids. Unlike other validation methods, this one
        creates a State object (holding the state of validation) and returns
        it. The other validation methods take the state from the caller and
        use it (read from it and write to it).

        Parameters
        ----------
        filenames : list(str)
            List of paths (filenames) to open and validate together. Filename
            '-' will be interpreted as STDIN.
        state : udtools.state.State, optional
            State from previous validation calls if the current call should
            take them into account. If not provided, a new state will be
            initialized.

        Returns
        -------
        state : udtools.state.State
            The resulting state of the validation. May contain the overview
            of all encountered incidents (errors or warnings) if requested.
        """
        if state == None:
            state = State()
        for filename in filenames:
            self.validate_file(filename, state)
        self.validate_end(state)
        return state


    def validate_file(self, filename, state=None):
        """
        An envelope around validate_file_handle(). Opens a file or uses STDIN,
        then calls validate_file_handle() on it.

        Parameters
        ----------
        filename : str
            Name of the file to be read and validated. '-' means STDIN.
        state : udtools.state.State, optional
            The state of the validation run. If not provided, a new state will
            be initialized.

        Returns
        -------
        state : udtools.state.State
            The resulting state of the validation. May contain the overview
            of all encountered incidents (errors or warnings) if requested.
        """
        if state == None:
            state = State()
        state.current_file_name = filename
        if filename == '-':
            # Set PYTHONIOENCODING=utf-8 before starting Python.
            # See https://docs.python.org/3/using/cmdline.html#envvar-PYTHONIOENCODING
            # Otherwise ANSI will be read in Windows and
            # locale-dependent encoding will be used elsewhere.
            self.validate_file_handle(sys.stdin, state)
        else:
            with io.open(filename, 'r', encoding='utf-8') as inp:
                self.validate_file_handle(inp, state)
        return state


    def validate_file_handle(self, inp, state=None):
        """
        The main entry point for all validation tests applied to one input file.
        It reads sentences from the input stream one by one, each sentence is
        immediately tested.

        Parameters
        ----------
        inp : open file handle
            The CoNLL-U-formatted input stream.
        state : udtools.state.State, optional
            The state of the validation run. If not provided, a new state will
            be initialized.

        Returns
        -------
        state : udtools.state.State
            The resulting state of the validation. May contain the overview
            of all encountered incidents (errors or warnings) if requested.
        """
        if state == None:
            state = State()
        for lines in utils.next_sentence(state, inp):
            self.validate_sentence(lines, state)
        self.check_newlines(state, inp) # level 1
        return state


    def validate_sentence(self, all_lines, state=None):
        """
        Entry point for all validation tests applied to one sentence. It can
        be called from annotation tools to check the sentence once annotated.
        Note that validate_file_handle() calls it after it was able to
        recognize a sequence of lines that constitute a sentence; some low-
        level errors may occur while recognizing the sentence.

        Parameters
        ----------
        all_lines : list(str)
            List of lines in the sentence (comments and tokens), minus final
            empty line, minus newline characters (and minus spurious lines
            that are neither comment lines nor token lines).
        state : udtools.state.State, optional
            The state of the validation run. If not provided, a new state will
            be initialized.

        Returns
        -------
        state : udtools.state.State
            The resulting state of the validation. May contain the overview
            of all encountered incidents (errors or warnings) if requested.
        """
        if state == None:
            state = State()
        state.current_lines = all_lines
        # Low-level errors typically mean that we cannot perform further tests
        # because we could choke on trying to access non-existent data. Or we
        # may succeed in performing them but the error messages may be misleading.
        if not self.check_sentence_lines(state): # level 1
            return state
        if not self.check_sentence_columns(state): # level 1
            return state
        if not self.check_id_sequence(state): # level 1
            return state
        if not self.check_token_range_overlaps(state): # level 1
            return state
        if self.level >= 2:
            if not self.check_id_references(state): # level 2
                return state
            # Check that the basic tree is single-rooted, connected, cycle-free.
            if not self.check_tree(state): # level 2
                return state
            # Tests of individual nodes that operate on pre-Udapi data structures.
            # Some of them (bad feature format) may lead to skipping Udapi completely.
            colssafe = True
            for i in range(len(state.current_token_node_table)):
                lineno = state.sentence_line + i
                cols = state.current_token_node_table[i]
                # Multiword tokens and empty nodes can or must have certain fields empty.
                if utils.is_multiword_token(cols):
                    self.check_mwt_empty_vals(state, cols, lineno)
                if utils.is_empty_node(cols):
                    self.check_empty_node_empty_vals(state, cols, lineno) # level 2
                if utils.is_word(cols) or utils.is_empty_node(cols):
                    self.check_upos(state, cols, lineno) # level 2
                    colssafe = self.check_feats_format(state, cols, lineno) and colssafe # level 2 (level 4 tests will be called later)
                    self.check_deprel_format(state, cols, lineno) # level 2
                    self.check_deps_format(state, cols, lineno) # level 2; must operate on pre-Udapi DEPS (to see order of relations)
                self.check_misc(state, cols, lineno) # level 2; must operate on pre-Udapi MISC
            if not colssafe:
                return state
            # Get line numbers for all nodes including empty ones (here linenos
            # is a dict indexed by cols[ID], i.e., a string).
            state.current_node_linenos = utils.get_line_numbers_for_ids(state, state.current_token_node_table)
            # Check that enhanced graphs exist either for all sentences or for
            # none.
            self.check_deps_all_or_none(state) # level 2
            # Check sentence-level metadata in the comment lines.
            self.check_sent_id(state) # level 2
            self.check_parallel_id(state) # level 2
            self.check_text_meta(state) # level 2
            # If we successfully passed all the critical tests above, it is
            # probably safe to give the lines to Udapi and ask it to build the
            # tree data structure for us. Udapi does not want to get the
            # terminating empty line.
            tree = self.build_tree_udapi(all_lines)
            # Tests of individual nodes with Udapi.
            nodes = tree.descendants_and_empty
            for node in nodes:
                if self.level >= 3:
                    self.check_zero_root(state, node) # level 3
                    self.check_enhanced_orphan(state, node) # level 3
                    if self.level >= 4:
                        # To disallow words with spaces everywhere, use --lang ud.
                        self.check_words_with_spaces(state, node) # level 4
                        self.check_feature_values(state, node) # level 4
                        self.check_deprels(state, node) # level 4
                        if self.level >= 5:
                            self.check_auxiliary_verbs(state, node) # level 5
                            self.check_copula_lemmas(state, node) # level 5
            # Tests on whole trees and enhanced graphs.
            self.check_egraph_connected(state, nodes) # level 2
            if self.level >= 3:
                # Level 3 checks universally valid consequences of annotation
                # guidelines. Look at regular nodes and basic tree, not at
                # enhanced graph.
                basic_nodes = tree.descendants
                for node in basic_nodes:
                    self.check_expected_features(state, node)
                    self.check_upos_vs_deprel(state, node)
                    self.check_flat_foreign(state, node)
                    self.check_left_to_right_relations(state, node)
                    self.check_single_subject(state, node)
                    self.check_single_object(state, node)
                    self.check_nmod_obl(state, node)
                    self.check_orphan(state, node)
                    self.check_functional_leaves(state, node)
                    self.check_fixed_span(state, node)
                    self.check_goeswith_span(state, node)
                    self.check_goeswith_morphology_and_edeps(state, node)
                    self.check_projective_punctuation(state, node)
            # Optional checks for CorefUD treebanks. They operate on MISC and
            # currently do not use the Udapi data structures.
            if self.check_coref:
                self.check_misc_entity(state)
        return state


    def build_tree_udapi(self, lines):
        """
        Calls Udapi to build its data structures from the CoNLL-U lines
        representing one sentence.

        Parameters
        ----------
        lines : list(str)
            Lines as in the CoNLL-U file, including sentence-level comments if
            any, but without the newline character at the end of each line.
            The sentence-terminating empty line is optional in this method.

        Returns
        -------
        root : udapi.core.node.Node object
            The artificial root node (all other nodes and all tree attributes
            can be accessed from it).
        """
        # If the final empty line is present, get rid of it. Udapi would die
        # when trying to access line[0].
        mylines = lines
        if len(mylines) > 0 and (not mylines[-1] or utils.is_whitespace(mylines[-1])):
            mylines = lines[0:-1]
        root = self.conllu_reader.read_tree_from_lines(mylines)
        # We should not return an empty tree (root should not be None).
        # But we should not be here if the lines are so bad that no tree is built.
        assert(root)
        return root


    def validate_end(self, state=None):
        """
        Final tests after processing the entire treebank (possibly multiple files).

        Parameters
        ----------
        state : udtools.state.State, optional
            The state of the validation run. If not provided, a new state will
            be initialized. (This is only to unify the interface of all the
            validate_xxx() methods. Note however that specifically for this
            method, it does not make sense to run it without state from other
            validation calls.)

        Returns
        -------
        state : udtools.state.State
            The resulting state of the validation. May contain the overview
            of all encountered incidents (errors or warnings) if requested.
        """
        if state == None:
            state = State()
        # After reading the entire treebank (perhaps multiple files), check whether
        # the DEPS annotation was not a mere copy of the basic trees.
        if self.level>2 and state.seen_enhanced_graph and not state.seen_enhancement:
            Error(
                state=state, config=self.incfg,
                level=3,
                testclass=TestClass.ENHANCED,
                testid='edeps-identical-to-basic-trees',
                message="Enhanced graphs are copies of basic trees in the entire dataset. This can happen for some simple sentences where there is nothing to enhance, but not for all sentences. If none of the enhancements from the guidelines (https://universaldependencies.org/u/overview/enhanced-syntax.html) are annotated, the DEPS should be left unspecified"
            ).confirm()
        return state
