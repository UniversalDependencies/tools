#! /usr/bin/env python3
# Original code (2015) by Filip Ginter and Sampo Pyysalo.
# DZ 2018-11-04: Porting the validator to Python 3.
# DZ: Many subsequent changes. See the git history.
import sys
import io
import argparse
# According to https://stackoverflow.com/questions/1832893/python-regex-matching-unicode-properties,
# the regex module has the same API as re but it can check Unicode character properties using \p{}
# as in Perl.
#import re
import regex as re
# Once we know that the low-level CoNLL-U format is OK, we will be able to use
# the Udapi library to access the data and perform the tests at higher levels.
import udapi.block.read.conllu
# Allow using this module from the root folder of tools even if it is not
# installed as a package: use the relative path validator/src/validator for
# submodules. If the path is not available, try the standard qualification,
# assuming that the user has installed udtools from PyPI and then called
# from udtools import Validator.
try:
    import validator.src.validator.utils as utils
    from validator.src.validator.incident import Incident, Error, Warning, TestClass
    from validator.src.validator.state import State
    import validator.src.validator.data as data
    from validator.src.validator.level5 import Level5
except ModuleNotFoundError:
    import udtools.utils as utils
    from udtools.incident import Incident, Error, Warning, TestClass
    from udtools.state import State
    import udtools.data as data
    from udtools.level5 import Level5



# Constants for the column indices
COLCOUNT=10
ID,FORM,LEMMA,UPOS,XPOS,FEATS,HEAD,DEPREL,DEPS,MISC=range(COLCOUNT)
COLNAMES='ID,FORM,LEMMA,UPOS,XPOS,FEATS,HEAD,DEPREL,DEPS,MISC'.split(',')



class Validator(Level5):
    def __init__(self, lang=None, level=None, check_coref=None, args=None, datapath=None, output=sys.stderr):
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
        if 'max_err' in args_dict:
            self.incfg['max_err'] = args_dict['max_err']
        if 'max_store' in args_dict:
            self.incfg['max_store'] = args_dict['max_store']
        if 'input' in args_dict and len(args_dict['input']) > 1:
            self.incfg['report_filename'] = True
        self.incfg['output'] = output
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
        if not state:
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
        linesok, comments, sentence = self.check_sentence(state, all_lines)
        if not linesok:
            return state
        linenos = utils.get_line_numbers_for_ids(state, sentence)
        # The individual lines were validated already in next_sentence().
        # What follows is tests that need to see the whole tree.
        # Note that low-level errors such as wrong number of columns would be
        # reported in next_sentence() but then the lines would be thrown away
        # and no tree lines would be yielded—meaning that we will not encounter
        # such a mess here.
        idseqok = self.check_id_sequence(state, sentence) # level 1
        self.check_token_ranges(state, sentence) # level 1
        if self.level > 1:
            idrefok = idseqok and self.check_id_references(state, sentence) # level 2
            if not idrefok:
                return state
            treeok = self.check_tree(state, sentence) # level 2 test: tree is single-rooted, connected, cycle-free
            if not treeok:
                return state
            # Tests of individual nodes that operate on pre-Udapi data structures.
            # Some of them (bad feature format) may lead to skipping Udapi completely.
            colssafe = True
            line = state.sentence_line - 1
            for cols in sentence:
                line += 1
                # Multiword tokens and empty nodes can or must have certain fields empty.
                if utils.is_multiword_token(cols):
                    self.check_mwt_empty_vals(state, cols, line)
                if utils.is_empty_node(cols):
                    self.check_empty_node_empty_vals(state, cols, line) # level 2
                if utils.is_word(cols) or utils.is_empty_node(cols):
                    self.check_character_constraints(state, cols, line) # level 2
                    self.check_upos(state, cols, line) # level 2
                    colssafe = self.check_features_level2(state, cols, line) and colssafe # level 2 (level 4 tests will be called later)
                self.check_deps(state, cols, line) # level 2; must operate on pre-Udapi DEPS (to see order of relations)
                self.check_misc(state, cols, line) # level 2; must operate on pre-Udapi MISC
            if not colssafe:
                return state
            # If we successfully passed all the tests above, it is probably
            # safe to give the lines to Udapi and ask it to build the tree data
            # structure for us. Udapi does not want to get the terminating
            # empty line.
            tree = self.build_tree_udapi(all_lines)
            self.check_sent_id(state, comments) # level 2
            self.check_parallel_id(state, comments) # level 2
            self.check_text_meta(state, comments, sentence) # level 2
            # Test that enhanced graphs exist either for all sentences or for
            # none. As a side effect, get line numbers for all nodes including
            # empty ones (here linenos is a dict indexed by cols[ID], i.e., a string).
            # These line numbers are returned in any case, even if there are no
            # enhanced dependencies, hence we can rely on them even with basic
            # trees.
            self.check_deps_all_or_none(state, sentence)
            # Tests of individual nodes with Udapi.
            nodes = tree.descendants_and_empty
            for node in nodes:
                line = linenos[str(node.ord)]
                self.check_deprels(state, node, line) # level 2 and 4
                self.check_root(state, node, line) # level 2: deprel root <=> head 0
                if self.level > 2:
                    self.check_enhanced_orphan(state, node, line) # level 3
                    if self.level > 3:
                        # To disallow words with spaces everywhere, use --lang ud.
                        self.check_words_with_spaces(state, node, line, self.lang) # level 4
                        self.check_features_level4(state, node, line, self.lang) # level 4
                        if self.level > 4:
                            self.check_auxiliary_verbs(state, node, line, self.lang) # level 5
                            self.check_copula_lemmas(state, node, line, self.lang) # level 5
            # Tests on whole trees and enhanced graphs.
            if self.level > 2:
                # Level 3 check universally valid consequences of annotation
                # guidelines. Look at regular nodes and basic tree, not at
                # enhanced graph (which is checked later).
                basic_nodes = tree.descendants
                for node in basic_nodes:
                    lineno = linenos[str(node.ord)]
                    self.check_expected_features(state, node, lineno)
                    self.check_upos_vs_deprel(state, node, lineno)
                    self.check_flat_foreign(state, node, lineno, linenos)
                    self.check_left_to_right_relations(state, node, lineno)
                    self.check_single_subject(state, node, lineno)
                    self.check_single_object(state, node, lineno)
                    self.check_nmod_obl(state, node, lineno)
                    self.check_orphan(state, node, lineno)
                    self.check_functional_leaves(state, node, lineno, linenos)
                    self.check_fixed_span(state, node, lineno)
                    self.check_goeswith_span(state, node, lineno)
                    self.check_goeswith_morphology_and_edeps(state, node, lineno)
                    self.check_projective_punctuation(state, node, lineno)
                self.check_egraph_connected(state, nodes, linenos)
            if self.check_coref:
                self.check_misc_entity(state, comments, sentence) # optional for CorefUD treebanks
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
        all_lines : list(str)
            List of lines in the sentence (comments and tokens), minus final
            empty line, minus newline characters (and minus spurious lines
            that are neither comment lines nor token lines).
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



#==============================================================================
# Level 6 tests for annotation of coreference and named entities. This is
# tested on demand only, as the requirements are not compulsory for UD
# releases.
#==============================================================================



    def check_misc_entity(self, state, comments, sentence):
        """
        Optionally checks the well-formedness of the MISC attributes that pertain
        to coreference and named entities.
        """
        Incident.default_level = 6
        Incident.default_testclass = TestClass.COREF
        iline = 0
        sentid = ''
        for c in comments:
            Incident.default_lineno = state.comment_start_line+iline
            global_entity_match = utils.crex.global_entity.fullmatch(c)
            newdoc_match = utils.crex.newdoc.fullmatch(c)
            sentid_match = utils.crex.sentid.fullmatch(c)
            if global_entity_match:
                # As a global declaration, global.Entity is expected only once per file.
                # However, we may be processing multiple files or people may have created
                # the file by concatening smaller files, so we will allow repeated
                # declarations iff they are identical to the first one.
                if state.seen_global_entity:
                    if global_entity_match.group(1) != state.global_entity_attribute_string:
                        Error(
                            state=state, config=self.incfg,
                            testid='global-entity-mismatch',
                            message=f"New declaration of global.Entity '{global_entity_match.group(1)}' does not match the first declaration '{state.global_entity_attribute_string}' on line {state.seen_global_entity}."
                        ).confirm()
                else:
                    state.seen_global_entity = state.comment_start_line + iline
                    state.global_entity_attribute_string = global_entity_match.group(1)
                    if not re.match(r"^[a-z]+(-[a-z]+)*$", state.global_entity_attribute_string):
                        Error(
                            state=state, config=self.incfg,
                            testid='spurious-global-entity',
                            message=f"Cannot parse global.Entity attribute declaration '{state.global_entity_attribute_string}'."
                        ).confirm()
                    else:
                        global_entity_attributes = state.global_entity_attribute_string.split('-')
                        if not 'eid' in global_entity_attributes:
                            Error(
                                state=state, config=self.incfg,
                                testid='spurious-global-entity',
                                message=f"Global.Entity attribute declaration '{state.global_entity_attribute_string}' does not include 'eid'."
                            ).confirm()
                        elif global_entity_attributes[0] != 'eid':
                            Error(
                                state=state, config=self.incfg,
                                testid='spurious-global-entity',
                                message=f"Attribute 'eid' must come first in global.Entity attribute declaration '{state.global_entity_attribute_string}'."
                            ).confirm()
                        if not 'etype' in global_entity_attributes:
                            Error(
                                state=state, config=self.incfg,
                                testid='spurious-global-entity',
                                message=f"Global.Entity attribute declaration '{state.global_entity_attribute_string}' does not include 'etype'."
                            ).confirm()
                        elif global_entity_attributes[1] != 'etype':
                            Error(
                                state=state, config=self.incfg,
                                testid='spurious-global-entity',
                                message=f"Attribute 'etype' must come second in global.Entity attribute declaration '{state.global_entity_attribute_string}'."
                            ).confirm()
                        if not 'head' in global_entity_attributes:
                            Error(
                                state=state, config=self.incfg,
                                testid='spurious-global-entity',
                                message=f"Global.Entity attribute declaration '{state.global_entity_attribute_string}' does not include 'head'."
                            ).confirm()
                        elif global_entity_attributes[2] != 'head':
                            Error(
                                state=state, config=self.incfg,
                                testid='spurious-global-entity',
                                message=f"Attribute 'head' must come third in global.Entity attribute declaration '{state.global_entity_attribute_string}'."
                            ).confirm()
                        if 'other' in global_entity_attributes and global_entity_attributes[3] != 'other':
                            Error(
                                state=state, config=self.incfg,
                                testid='spurious-global-entity',
                                message=f"Attribute 'other', if present, must come fourth in global.Entity attribute declaration '{state.global_entity_attribute_string}'."
                            ).confirm()
                        # Fill the global dictionary that maps attribute names to list indices.
                        i = 0
                        for a in global_entity_attributes:
                            if a in state.entity_attribute_index:
                                Error(
                                    state=state, config=self.incfg,
                                    testid='spurious-global-entity',
                                    message=f"Attribute '{a}' occurs more than once in global.Entity attribute declaration '{state.global_entity_attribute_string}'."
                                ).confirm()
                            else:
                                state.entity_attribute_index[a] = i
                            i += 1
                        state.entity_attribute_number = len(global_entity_attributes)
            elif newdoc_match:
                for eid in state.entity_ids_this_document:
                    state.entity_ids_other_documents[eid] = state.entity_ids_this_document[eid]
                state.entity_ids_this_document = {}
            elif sentid_match:
                sentid = sentid_match.group(1)
            iline += 1
        iline = 0
        for cols in sentence:
            Incident.default_lineno = state.sentence_line+iline
            # Add the current word to all currently open mentions. We will use it in error messages.
            # Do this for regular and empty nodes but not for multi-word-token lines.
            if not utils.is_multiword_token(cols):
                for m in state.open_entity_mentions:
                    m['span'].append(cols[ID])
                    m['text'] += ' '+cols[FORM]
                    m['length'] += 1
            misc = cols[MISC].split('|')
            entity = [x for x in misc if re.match(r"^Entity=", x)]
            bridge = [x for x in misc if re.match(r"^Bridge=", x)]
            splitante = [x for x in misc if re.match(r"^SplitAnte=", x)]
            if utils.is_multiword_token(cols) and (len(entity)>0 or len(bridge)>0 or len(splitante)>0):
                Error(
                    state=state, config=self.incfg,
                    testid='entity-mwt',
                    message="Entity or coreference annotation must not occur at a multiword-token line."
                ).confirm()
                continue
            if len(entity)>1:
                Error(
                    state=state, config=self.incfg,
                    testid='multiple-entity-statements',
                    message=f"There can be at most one 'Entity=' statement in MISC but we have {str(misc)}."
                ).confirm()
                continue
            if len(bridge)>1:
                Error(
                    state=state, config=self.incfg,
                    testid='multiple-bridge-statements',
                    message=f"There can be at most one 'Bridge=' statement in MISC but we have {str(misc)}."
                ).confirm()
                continue
            if len(splitante)>1:
                Error(
                    state=state, config=self.incfg,
                    testid='multiple-splitante-statements',
                    message=f"There can be at most one 'SplitAnte=' statement in MISC but we have {str(misc)}."
                ).confirm()
                continue
            if len(bridge)>0 and len(entity)==0:
                Error(
                    state=state, config=self.incfg,
                    testid='bridge-without-entity',
                    message=f"The 'Bridge=' statement can only occur together with 'Entity=' in MISC but we have {str(misc)}."
                ).confirm()
                continue
            if len(splitante)>0 and len(entity)==0:
                Error(
                    state=state, config=self.incfg,
                    testid='splitante-without-entity',
                    message=f"The 'SplitAnte=' statement can only occur together with 'Entity=' in MISC but we have {str(misc)}."
                ).confirm()
                continue
            # There is at most one Entity (and only if it is there, there may be also one Bridge and/or one SplitAnte).
            if len(entity)>0:
                if not state.seen_global_entity:
                    Error(
                        state=state, config=self.incfg,
                        testid='entity-without-global-entity',
                        message="No global.Entity comment was found before the first 'Entity' in MISC."
                    ).confirm()
                    continue
                match = re.match(r"^Entity=((?:\([^( )]+(?:-[^( )]+)*\)?|[^( )]+\))+)$", entity[0])
                if not match:
                    Error(
                        state=state, config=self.incfg,
                        testid='spurious-entity-statement',
                        message=f"Cannot parse the Entity statement '{entity[0]}'."
                    ).confirm()
                else:
                    entity_string = match.group(1)
                    # We cannot check the rest if we cannot identify the 'eid' attribute.
                    if 'eid' not in state.entity_attribute_index:
                        continue
                    # Items of entities are pairs of [012] and a string.
                    # 0 ... opening bracket; 1 ... closing bracket; 2 ... both brackets
                    entities = []
                    while entity_string:
                        match = re.match(r"^\(([^( )]+(-[^( )]+)*)\)", entity_string)
                        if match:
                            entities.append((2, match.group(1)))
                            entity_string = re.sub(r"^\([^( )]+(-[^( )]+)*\)", '', entity_string, count=1)
                            continue
                        match = re.match(r"^\(([^( )]+(-[^( )]+)*)", entity_string)
                        if match:
                            entities.append((0, match.group(1)))
                            entity_string = re.sub(r"^\([^( )]+(-[^( )]+)*", '', entity_string, count=1)
                            continue
                        match = re.match(r"^([^( )]+)\)", entity_string)
                        if match:
                            entities.append((1, match.group(1)))
                            entity_string = re.sub(r"^[^( )]+\)", '', entity_string, count=1)
                            continue
                        # If we pre-checked the string well, we should never arrive here!
                        Error(
                            state=state, config=self.incfg,
                            testid='internal-error',
                            message='INTERNAL ERROR'
                        ).confirm()
                    # All 1 cases should precede all 0 cases.
                    # The 2 cases can be either before the first 1 case, or after the last 0 case.
                    seen0 = False
                    seen1 = False
                    seen2 = False
                    # To be able to check validity of Bridge and SplitAnte, we will hash eids of mentions that start here.
                    # To be able to check that no two mentions have the same span, we will hash start-end intervals for mentions that end here.
                    starting_mentions = {}
                    ending_mentions = {}
                    for b, e in entities:
                        # First get attributes, entity id, and if applicable, part of discontinuous mention.
                        attributes = e.split('-')
                        if b==0 or b==2:
                            # Fewer attributes are allowed because trailing empty values can be omitted.
                            # More attributes are not allowed.
                            if len(attributes) > state.entity_attribute_number:
                                Error(
                                    state=state, config=self.incfg,
                                    testid='too-many-entity-attributes',
                                    message=f"Entity '{e}' has {len(attributes)} attributes while only {state.entity_attribute_number} attributes are globally declared."
                                ).confirm()
                            # The raw eid (bracket eid) may include an identification of a part of a discontinuous mention,
                            # as in 'e155[1/2]'. This is fine for matching opening and closing brackets
                            # because the closing bracket must contain it too. However, to identify the
                            # cluster, we need to take the real id.
                            beid = attributes[state.entity_attribute_index['eid']]
                        else:
                            # No attributes other than eid are expected at the closing bracket.
                            if len(attributes) > 1:
                                Error(
                                    state=state, config=self.incfg,
                                    testid='too-many-entity-attributes',
                                    message=f"Entity '{e}' has {len(attributes)} attributes while only eid is expected at the closing bracket."
                                ).confirm()
                            beid = attributes[0]
                        eid = beid
                        ipart = 1
                        npart = 1
                        eidnpart = eid
                        match = re.match(r"^(.+)\[([1-9]\d*)/([1-9]\d*)\]$", beid)
                        if match:
                            eid = match.group(1)
                            ipart = int(match.group(2))
                            npart = int(match.group(3))
                            eidnpart = eid+'['+match.group(3)+']'
                            # We should omit the square brackets if they would be [1/1].
                            if ipart == 1 and npart == 1:
                                Error(
                                    state=state, config=self.incfg,
                                    testid='spurious-entity-id',
                                    message=f"Discontinuous mention must have at least two parts but it has one in '{beid}'."
                                ).confirm()
                            if ipart > npart:
                                Error(
                                    state=state, config=self.incfg,
                                    testid='spurious-entity-id',
                                    message=f"Entity id '{beid}' of discontinuous mention says the current part is higher than total number of parts."
                                ).confirm()
                        else:
                            if re.match(r"[\[\]]", beid):
                                Error(
                                    state=state, config=self.incfg,
                                    testid='spurious-entity-id',
                                    message=f"Entity id '{beid}' contains square brackets but does not have the form used in discontinuous mentions."
                                ).confirm()

                        #--------------------------------------------------------------------------------------------------------------------------------
                        # The code that we will have to execute at single-node continuous parts and at the opening brackets of multi-node continuous parts.
                        # We assume that we have already parsed beid and established whether this is a part of a discontinuous mention.
                        def opening_bracket():
                            attrstring_to_match = ''
                            # If this is a part of a discontinuous mention, remember the attribute string.
                            # At the beginning of each part, we will check that its attribute string is identical to the first part.
                            if npart > 1:
                                # We want to check that values of all attributes are same in all parts (except the eid which differs in the brackets).
                                attributes_without_eid = [attributes[i] for i in range(len(attributes)) if i != state.entity_attribute_index['eid']]
                                # For better readability of the error messages, reintroduce eid anyway, but without the brackets.
                                attrstring_to_match = eid+'-'+('-'.join(attributes_without_eid))
                                if ipart == 1:
                                    # If this is the first part, create a new record for the mention in the global dictionary.
                                    # We actually keep a stack of open mentions with the same eidnpart because they may be nested.
                                    # The length and the span of the mention will be updated when we encounter the closing bracket of the current part.
                                    discontinuous_mention = {'last_ipart': 1, 'npart': npart,
                                                            'first_part_line': state.sentence_line+iline,
                                                            'last_part_line': state.sentence_line+iline,
                                                            'attributes': attrstring_to_match,
                                                            'length': 0, 'span': []}
                                    if eidnpart in state.open_discontinuous_mentions:
                                        state.open_discontinuous_mentions[eidnpart].append(discontinuous_mention)
                                    else:
                                        state.open_discontinuous_mentions[eidnpart] = [discontinuous_mention]
                                else:
                                    if eidnpart in state.open_discontinuous_mentions:
                                        discontinuous_mention = state.open_discontinuous_mentions[eidnpart][-1]
                                        if ipart != discontinuous_mention['last_ipart']+1:
                                            Error(
                                                state=state, config=self.incfg,
                                                testid='misplaced-mention-part',
                                                message=f"Unexpected part of discontinuous mention '{beid}': last part was '{discontinuous_mention['last_ipart']}/{discontinuous_mention['npart']}' on line {discontinuous_mention['last_part_line']}."
                                            ).confirm()
                                            # We will update last_ipart at closing bracket, i.e., after the current part has been entirely processed.
                                            # Otherwise nested discontinuous mentions might wrongly assess where they belong.
                                        elif attrstring_to_match != discontinuous_mention['attributes']:
                                            Error(
                                                state=state, config=self.incfg,
                                                testid='mention-attribute-mismatch',
                                                message=f"Attribute mismatch of discontinuous mention: current part has '{attrstring_to_match}', first part '{discontinuous_mention['attributes']}' was at line {discontinuous_mention['first_part_line']}."
                                            ).confirm()
                                    else:
                                        Error(
                                            state=state, config=self.incfg,
                                            testid='misplaced-mention-part',
                                            message=f"Unexpected part of discontinuous mention '{beid}': this is part {ipart} but we do not have information about the previous parts."
                                        ).confirm()
                                        discontinuous_mention = {'last_ipart': ipart, 'npart': npart,
                                                                'first_part_line': state.sentence_line+iline,
                                                                'last_part_line': state.sentence_line+iline,
                                                                'attributes': attrstring_to_match,
                                                                'length': 0, 'span': []}
                                        state.open_discontinuous_mentions[eidnpart] = [discontinuous_mention]
                            # Check all attributes of the entity, except those that must be examined at the closing bracket.
                            if eid in state.entity_ids_other_documents:
                                Error(
                                    state=state, config=self.incfg,
                                    testid='entity-across-newdoc',
                                    message=f"Same entity id should not occur in multiple documents; '{eid}' first seen on line {state.entity_ids_other_documents[eid]}, before the last newdoc."
                                ).confirm()
                            elif not eid in state.entity_ids_this_document:
                                state.entity_ids_this_document[eid] = state.sentence_line+iline
                            etype = ''
                            identity = ''
                            if 'etype' in state.entity_attribute_index and len(attributes) >= state.entity_attribute_index['etype']+1:
                                etype = attributes[state.entity_attribute_index['etype']]
                                # For etype values tentatively approved for CorefUD 1.0, see
                                # https://github.com/ufal/corefUD/issues/13#issuecomment-1008447464
                                if not re.match(r"^(person|place|organization|animal|plant|object|substance|time|number|abstract|event|other)?$", etype):
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='spurious-entity-type',
                                        message=f"Spurious entity type '{etype}'."
                                    ).confirm()
                            if 'identity' in state.entity_attribute_index and len(attributes) >= state.entity_attribute_index['identity']+1:
                                identity = attributes[state.entity_attribute_index['identity']]
                            # Check the form of the head index now.
                            # The value will be checked at the end of the mention,
                            # when we know the mention length.
                            head = 0
                            if 'head' in state.entity_attribute_index and len(attributes) >= state.entity_attribute_index['head']+1:
                                if not re.match(r"^[1-9][0-9]*$", attributes[state.entity_attribute_index['head']]):
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='spurious-mention-head',
                                        message=f"Entity head index '{attributes[state.entity_attribute_index['head']]}' must be a non-zero-starting integer."
                                    ).confirm()
                                else:
                                    head = int(attributes[state.entity_attribute_index['head']])
                            # If this is the first mention of the entity, remember the values
                            # of the attributes that should be identical at all mentions.
                            if not eid in state.entity_types:
                                state.entity_types[eid] = (etype, identity, state.sentence_line+iline)
                            else:
                                # All mentions of one entity (cluster) must have the same entity type.
                                if etype != state.entity_types[eid][0]:
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='entity-type-mismatch',
                                        message=f"Entity '{eid}' cannot have type '{etype}' that does not match '{state.entity_types[eid][0]}' from the first mention on line {state.entity_types[eid][2]}."
                                    ).confirm()
                                # All mentions of one entity (cluster) must have the same identity (Wikipedia link or similar).
                                if identity != state.entity_types[eid][1]:
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='entity-identity-mismatch',
                                        message=f"Entity '{eid}' cannot have identity '{identity}' that does not match '{state.entity_types[eid][1]}' from the first mention on line {state.entity_types[eid][2]}."
                                    ).confirm()
                            # Remember the line where (the current part of) the entity mention starts.
                            mention = {'beid': beid, 'line': state.sentence_line+iline,
                                       'span': [cols[ID]], 'text': cols[FORM],
                                       'length': 1, 'head': head, 'attrstring': attrstring_to_match}
                            state.open_entity_mentions.append(mention)
                            # The set of mentions starting at the current line will be needed later when checking Bridge and SplitAnte statements.
                            if ipart == 1:
                                starting_mentions[eid] = True

                        #--------------------------------------------------------------------------------------------------------------------------------
                        # The code that we will have to execute at single-node continuous parts and at the closing brackets of multi-node continuous parts.
                        def closing_bracket():
                            # Find the corresponding opening bracket and extract the information we need to know.
                            mention_length = 0
                            mention_span = []
                            head = 0
                            opening_line = 0
                            if len(state.open_entity_mentions)==0:
                                Error(
                                    state=state, config=self.incfg,
                                    testid='ill-nested-entities',
                                    message=f"Cannot close entity '{beid}' because there are no open entities."
                                ).confirm()
                                return
                            else:
                                # If the closing bracket does not occur where expected, it is currently only a warning.
                                # We have crossing mention spans in CorefUD 1.0 and it has not been decided yet whether all of them should be illegal.
                                ###!!! Note that this will not catch ill-nested mentions whose only intersection is one node. The bracketing will
                                ###!!! not be a problem in such cases because one mention will be closed first, then the other will be opened.
                                if beid != state.open_entity_mentions[-1]['beid']:
                                    Warning(
                                        state=state, config=self.incfg,
                                        testclass=TestClass.COREF,
                                        testid='ill-nested-entities-warning',
                                        message=f"Entity mentions are not well nested: closing '{beid}' while the innermost open entity is '{state.open_entity_mentions[-1]['beid']}' from line {state.open_entity_mentions[-1]['line']}: {str(state.open_entity_mentions)}."
                                    ).confirm()
                                # Try to find and close the entity whether or not it was well-nested.
                                for i in reversed(range(len(state.open_entity_mentions))):
                                    if state.open_entity_mentions[i]['beid'] == beid:
                                        mention_length = state.open_entity_mentions[i]['length']
                                        mention_span = state.open_entity_mentions[i]['span']
                                        head = state.open_entity_mentions[i]['head']
                                        opening_line = state.open_entity_mentions[i]['line']
                                        state.open_entity_mentions.pop(i)
                                        break
                                else:
                                    # If we did not find the entity to close, then the warning above was not enough and we have to make it a validation error.
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='ill-nested-entities',
                                        message=f"Cannot close entity '{beid}' because it was not found among open entities: {str(state.open_entity_mentions)}"
                                    ).confirm()
                                    return
                            # If this is a part of a discontinuous mention, update the information about the whole mention.
                            # We do this after reading the new part (and not when we see its opening bracket) so that nested
                            # discontinuous mentions of the same entity are possible.
                            if npart > 1:
                                # Update the attributes that have to be updated after each part.
                                if eidnpart in state.open_discontinuous_mentions:
                                    discontinuous_mention = state.open_discontinuous_mentions[eidnpart][-1]
                                    discontinuous_mention['last_ipart'] = ipart
                                    discontinuous_mention['last_part_line'] = opening_line
                                    discontinuous_mention['length'] += mention_length
                                    discontinuous_mention['span'] += mention_span
                                else:
                                    # This should have been taken care of at the opening bracket.
                                    Error(
                                        state=state, config=self.incfg,
                                        testclass=TestClass.INTERNAL,
                                        testid='internal-error',
                                        message="INTERNAL ERROR: at the closing bracket of a part of a discontinuous mention, still no record in state.open_discontinuous_mentions."
                                    ).confirm()
                                    discontinuous_mention = {'last_ipart': ipart, 'npart': npart,
                                                            'first_part_line': opening_line,
                                                            'last_part_line': opening_line,
                                                            'attributes': '', 'length': mention_length,
                                                            'span': mention_span}
                                    state.open_discontinuous_mentions[eidnpart] = [discontinuous_mention]
                                # Update mention_length and mention_span to reflect the whole span up to this point rather than just the last part.
                                mention_length = state.open_discontinuous_mentions[eidnpart][-1]['length']
                                mention_span = state.open_discontinuous_mentions[eidnpart][-1]['span']
                            # We need to know the length (number of nodes) of the mention to check whether the head attribute is within limits.
                            # We need to know the span (list of nodes) of the mention to check that no two mentions have the same span.
                            # We only check these requirements after the last part of the discontinuous span (or after the single part of a continuous one).
                            if ipart == npart:
                                if mention_length < head:
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='mention-head-out-of-range',
                                        message=f"Entity mention head was specified as {head} on line {opening_line} but the mention has only {mention_length} nodes."
                                    ).confirm()
                                # Check that no two mentions have identical spans (only if this is the last part of a mention).
                                ending_mention_key = str(opening_line)+str(mention_span)
                                if ending_mention_key in ending_mentions:
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='same-span-entity-mentions',
                                        message=f"Entity mentions '{ending_mentions[ending_mention_key]}' and '{beid}' from line {opening_line} have the same span {str(mention_span)}."
                                    ).confirm()
                                else:
                                    ending_mentions[ending_mention_key] = beid
                                # Remember the span of the current mention so that we can later check whether it crosses the span of another mention.
                                # Use the current sentence id to partially qualify the node ids. It will not work well for mentions that span multiple
                                # sentences but we do not expect cross-sentence mentions to be frequent.
                                myset = set(mention_span)
                                # Check whether any other mention of the same entity has span that crosses the current one.
                                if eid in state.entity_mention_spans:
                                    if sentid in state.entity_mention_spans[eid]:
                                        for m in state.entity_mention_spans[eid][sentid]:
                                            ms = state.entity_mention_spans[eid][sentid][m]
                                            if ms.intersection(myset) and not ms.issubset(myset) and not myset.issubset(ms):
                                                Error(
                                                    state=state, config=self.incfg,
                                                    testid='crossing-mentions-same-entity',
                                                    message=f"Mentions of entity '{eid}' have crossing spans: {m} vs. {str(mention_span)}."
                                                ).confirm()
                                    else:
                                        state.entity_mention_spans[eid][sentid] = {}
                                else:
                                    state.entity_mention_spans[eid] = {}
                                    state.entity_mention_spans[eid][sentid] = {}
                                state.entity_mention_spans[eid][sentid][str(mention_span)] = myset
                            # At the end of the last part of a discontinuous mention, remove the information about the mention.
                            if npart > 1 and ipart == npart:
                                if eidnpart in state.open_discontinuous_mentions:
                                    if len(state.open_discontinuous_mentions[eidnpart]) > 1:
                                        state.open_discontinuous_mentions[eidnpart].pop()
                                    else:
                                        state.open_discontinuous_mentions.pop(eidnpart)
                        #--------------------------------------------------------------------------------------------------------------------------------

                        # Now we know the beid, eid, as well as all other attributes.
                        # We can check the well-nestedness of brackets.
                        if b==0:
                            if seen2 and not seen1:
                                Error(
                                    state=state, config=self.incfg,
                                    testid='spurious-entity-statement',
                                    message=f"If there are no closing entity brackets, single-node entity must follow all opening entity brackets in '{entity[0]}'."
                                ).confirm()
                            if seen0 and seen2:
                                Error(
                                    state=state, config=self.incfg,
                                    testid='spurious-entity-statement',
                                    message=f"Single-node entity must either precede all closing entity brackets or follow all opening entity brackets in '{entity[0]}'."
                                ).confirm()
                            seen0 = True
                            seen2 = False
                            opening_bracket()
                        elif b==2:
                            if seen1 and not seen0:
                                Error(
                                    state=state, config=self.incfg,
                                    testid='spurious-entity-statement',
                                    message=f"If there are no opening entity brackets, single-node entity must precede all closing entity brackets in '{entity[0]}'."
                                ).confirm()
                            seen2 = True
                            opening_bracket()
                            closing_bracket()
                        else: # b==1
                            if seen0:
                                Error(
                                    state=state, config=self.incfg,
                                    testid='spurious-entity-statement',
                                    message=f"All closing entity brackets must precede all opening entity brackets in '{entity[0]}'."
                                ).confirm()
                            seen1 = True
                            closing_bracket()
                # Now we are done with checking the 'Entity=' statement.
                # If there are also 'Bridge=' or 'SplitAnte=' statements, check them too.
                if len(bridge) > 0:
                    match = re.match(r"^Bridge=([^(< :>)]+<[^(< :>)]+(:[a-z]+)?(,[^(< :>)]+<[^(< :>)]+(:[a-z]+)?)*)$", bridge[0])
                    if not match:
                        Error(
                            state=state, config=self.incfg,
                            testid='spurious-bridge-statement',
                            message=f"Cannot parse the Bridge statement '{bridge[0]}'."
                        ).confirm()
                    else:
                        bridges = match.group(1).split(',')
                        # Hash src<tgt pairs and make sure they are not repeated.
                        srctgt = {}
                        for b in bridges:
                            match = re.match(r"([^(< :>)]+)<([^(< :>)]+)(?::([a-z]+))?^$", b)
                            if match:
                                srceid = match.group(1)
                                tgteid = match.group(2)
                                relation = match.group(3) # optional
                                bridgekey = srceid+'<'+tgteid
                                if srceid == tgteid:
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='spurious-bridge-relation',
                                        message=f"Bridge must not point from an entity to itself: '{b}'."
                                    ).confirm()
                                if not tgteid in starting_mentions:
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='misplaced-bridge-statement',
                                        message=f"Bridge relation '{b}' must be annotated at the beginning of a mention of entity '{tgteid}'."
                                    ).confirm()
                                if bridgekey in srctgt:
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='repeated-bridge-relation',
                                        message=f"Bridge relation '{bridgekey}' must not be repeated in '{b}'."
                                    ).confirm()
                                else:
                                    srctgt[bridgekey] = True
                                # Check in the global dictionary whether this relation has been specified at another mention.
                                if bridgekey in state.entity_bridge_relations:
                                    if relation != state.entity_bridge_relations[bridgekey]['relation']:
                                        Error(
                                            state=state, config=self.incfg,
                                            testid='bridge-relation-mismatch',
                                            message=f"Bridge relation '{b}' type does not match '{state.entity_bridge_relations[bridgekey]['relation']}' specified earlier on line {state.entity_bridge_relations[bridgekey]['line']}."
                                        ).confirm()
                                else:
                                    state.entity_bridge_relations[bridgekey] = {'relation': relation, 'line': state.sentence_line+iline}
                if len(splitante) > 0:
                    match = re.match(r"^SplitAnte=([^(< :>)]+<[^(< :>)]+(,[^(< :>)]+<[^(< :>)]+)*)$", splitante[0])
                    if not match:
                        Error(
                            state=state, config=self.incfg,
                            testid='spurious-splitante-statement',
                            message=f"Cannot parse the SplitAnte statement '{splitante[0]}'."
                        ).confirm()
                    else:
                        antecedents = match.group(1).split(',')
                        # Hash src<tgt pairs and make sure they are not repeated. Also remember the number of antecedents for each target.
                        srctgt = {}
                        tgtante = {}
                        for a in antecedents:
                            match = re.match(r"^([^(< :>)]+)<([^(< :>)]+)$", a)
                            if match:
                                srceid = match.group(1)
                                tgteid = match.group(2)
                                if srceid == tgteid:
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='spurious-splitante-relation',
                                        message=f"SplitAnte must not point from an entity to itself: '{srceid}<{tgteid}'."
                                    ).confirm()
                                elif not tgteid in starting_mentions:
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='misplaced-splitante-statement',
                                        message=f"SplitAnte relation '{a}' must be annotated at the beginning of a mention of entity '{tgteid}'."
                                    ).confirm()
                                if srceid+'<'+tgteid in srctgt:
                                    str_antecedents = ','.join(antecedents)
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='repeated-splitante-relation',
                                        message=f"SplitAnte relation '{srceid}<{tgteid}' must not be repeated in '{str_antecedents}'."
                                    ).confirm()
                                else:
                                    srctgt[srceid+'<'+tgteid] = True
                                if tgteid in tgtante:
                                    tgtante[tgteid].append(srceid)
                                else:
                                    tgtante[tgteid] = [srceid]
                        for tgteid in tgtante:
                            if len(tgtante[tgteid]) == 1:
                                str_antecedents = ','.join(antecedents)
                                Error(
                                    state=state, config=self.incfg,
                                    testid='only-one-split-antecedent',
                                    message=f"SplitAnte statement '{str_antecedents}' must specify at least two antecedents for entity '{tgteid}'."
                                ).confirm()
                            # Check in the global dictionary whether this relation has been specified at another mention.
                            tgtante[tgteid].sort()
                            if tgteid in state.entity_split_antecedents:
                                if tgtante[tgteid] != state.entity_split_antecedents[tgteid]['antecedents']:
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='split-antecedent-mismatch',
                                        message=f"Split antecedent of entity '{tgteid}' does not match '{state.entity_split_antecedents[tgteid]['antecedents']}' specified earlier on line {state.entity_split_antecedents[tgteid]['line']}."
                                    ).confirm()
                            else:
                                state.entity_split_antecedents[tgteid] = {'antecedents': str(tgtante[tgteid]), 'line': state.sentence_line+iline}
            iline += 1
        if len(state.open_entity_mentions)>0:
            Error(
                state=state, config=self.incfg,
                testid='cross-sentence-mention',
                message=f"Entity mentions must not cross sentence boundaries; still open at sentence end: {str(state.open_entity_mentions)}."
            ).confirm()
            # Close the mentions forcibly. Otherwise one omitted closing bracket would cause the error messages to to explode because the words would be collected from the remainder of the file.
            state.open_entity_mentions = []
        if len(state.open_discontinuous_mentions)>0:
            Error(
                state=state, config=self.incfg,
                testid='cross-sentence-mention',
                message=f"Entity mentions must not cross sentence boundaries; still open at sentence end: {str(state.open_discontinuous_mentions)}."
            ).confirm()
            # Close the mentions forcibly. Otherwise one omission would cause the error messages to to explode because the words would be collected from the remainder of the file.
            state.open_discontinuous_mentions = {}
        # Since we only test mentions within one sentence at present, we do not have to carry all mention spans until the end of the corpus.
        for eid in state.entity_mention_spans:
            if sentid in state.entity_mention_spans[eid]:
                state.entity_mention_spans[eid].pop(sentid)
