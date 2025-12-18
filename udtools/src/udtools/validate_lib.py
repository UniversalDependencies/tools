# ! REMOVE #/usr/bin/env python3
# ! REMOVE Original code (2015) by Filip Ginter and Sampo Pyysalo.
# ! REMOVE DZ 2018-11-04: Porting the validator to Python 3.
# ! REMOVE DZ: Many subsequent changes. See the git history.
import sys
import io
import os.path
import argparse
import traceback
# ! REMOVE According to https://stackoverflow.com/questions/1832893/python-regex-matching-unicode-properties,
# ! REMOVE the regex module has the same API as re but it can check Unicode character properties using \p{}
# ! REMOVE as in Perl.
#import re
import regex as re
import unicodedata
import json
# Once we know that the low-level CoNLL-U format is OK, we will be able to use
# the Udapi library to access the data and perform the tests at higher levels.
import udapi.block.read.conllu

import udtools.utils as utils
import udtools.output_utils as outils
import udtools.specifications as data



# The folder where this script resides.
# ! OLD THISDIR=os.path.dirname(os.path.realpath(os.path.abspath(__file__)))
THISDIR=os.path.join(os.path.dirname(os.path.realpath(os.path.abspath(__file__))), "../../..")

# Constants for the column indices
COLCOUNT=10
ID,FORM,LEMMA,UPOS,XPOS,FEATS,HEAD,DEPREL,DEPS,MISC=range(COLCOUNT)
COLNAMES='ID,FORM,LEMMA,UPOS,XPOS,FEATS,HEAD,DEPREL,DEPS,MISC'.split(',')


# TODO: turn into data class
class State:
    """
    The State class holds various global data about where we are in the file
    and what we have seen so far. Typically there will be just one instance of
    this class.
    """
    def __init__(self, current_file_name):
        # Name of the current input file.
        self.current_file_name = current_file_name
        # Current line in the input file, or, more precisely, the last line
        # read so far. Once we start looking at tree integrity, we may find
        # errors on previous lines as well.
        self.current_line = 0;
        # The line in the input file on which the current sentence starts,
        # including sentence-level comments.
        self.comment_start_line = 0 # TODO: rename to someting about sentences
        # The line in the input file on which the current sentence starts
        # (the first node/token line, skipping comments).
        self.sentence_line = 0
        # The most recently read sentence id.
        self.sentence_id = None
        # Needed to check that no space after last word of sentence does not
        # co-occur with new paragraph or document. # TODO: smorfiare
        self.spaceafterno_in_effect = False
        # Error counter by error type. Key: error type; value: error count.
        # Incremented in Incident.report().
        self.error_counter = {} # TODO: replace with len(something)
        # Set of detailed error explanations that have been printed so far.
        # Each explanation will be printed only once. Typically, an explanation
        # can be identified by test id + language code. Nevertheless, we put
        # the whole explanation to the set.
        self.explanation_printed = set() # TODO: cestinare
        # Some feature-related errors can only be reported if the corpus
        # contains feature annotation because features are optional in general.
        # Once we see the first feature, we can flush all accumulated
        # complaints about missing features.
        # Key: testid; value: dict with parameters of the error and the list of
        # its occurrences.
        self.delayed_feature_errors = {}
        # Remember all sentence ids seen in all input files (presumably one
        # corpus). We need it to check that each id is unique.
        self.known_sent_ids = set()
        #----------------------------------------------------------------------
        # Various things that we may have seen earlier in the corpus. The value
        # is None if we have not seen it, otherwise it is the line number of
        # the first occurrence.
        #----------------------------------------------------------------------
        self.seen_morpho_feature = None
        self.seen_enhanced_graph = None
        self.seen_tree_without_enhanced_graph = None
        # Any difference between non-empty DEPS and HEAD:DEPREL.
        # (Because we can see many enhanced graphs but no real enhancements.)
        self.seen_enhancement = None
        self.seen_empty_node = None
        self.seen_enhanced_orphan = None

        # If a multi-word token has Typo=Yes, its component words must not have
        # it. When we see Typo=Yes on a MWT line, we will remember the span of
        # the MWT here and will not allow Typo=Yes within that span (which is
        # checked in another function).
        self.mwt_typo_span_end = None

        #----------------------------------------------------------------------
        # Additional observations related to Entity annotation in MISC
        # (only needed when validating entities and coreference).
        #----------------------------------------------------------------------
        # Remember the global.entity attribute string to be able to check that
        # repeated declarations are identical.
        # global.entity comment line is needed for Entity annotations in MISC.
        self.seen_global_entity = None
        self.global_entity_attribute_string = None
        # The number of entity attributes will be derived from the attribute
        # string and will be used to check that an entity does not have extra
        # attributes.
        self.entity_attribute_number = 0
        # Key: entity attribute name; value: the index of the attribute in the
        # entity attribute list.
        self.entity_attribute_index = {}
        # Key: entity (cluster) id; value: tuple: (type of the entity, identity
        # (Wikipedia etc.), line of the first mention)).
        self.entity_types = {}
        # Indices of known entity ids in this and other documents.
        # (Otherwise, if we only needed to know that an entity is known, we
        # could use self.entity_types above.)
        self.entity_ids_this_document = {}
        self.entity_ids_other_documents = {}
        # List of currently open entity mentions. Items are dictionaries with
        # entity mention information.
        self.open_entity_mentions = []
        # For each entity that has currently open discontinuous mention,
        # describe the last part of the mention. Key: entity id; value is dict,
        # its keys: last_ipart, npart, line.
        self.open_discontinuous_mentions = {}
        # Key: srceid<tgteid pair; value: type of the entity (may be empty).
        self.entity_bridge_relations = {}
        # Key: tgteid; value: sorted list of srceids, serialized to string.
        self.entity_split_antecedents = {}
        # Key: [eid][sentid][str(mention_span)]; value: set of node ids.
        self.entity_mention_spans = {}
        self.nodeid = None


class Incident:
    """
    Instances of this class describe individual errors or warnings in the input
    file.
    """
    # TODO: change class variable into
    # We can modify the class-level defaults before a batch of similar tests.
    # Then we do not have to repeat the shared parameters for each test.
    default_level = 1
    default_testclass = 'Format' # TODO: enum?
    default_testid = 'generic-error'
    default_message = 'No error description provided.'
    default_lineno = None
    def __init__(self, state, level=None, testclass=None, testid=None, message=None, lineno=None, nodeid=None, explanation=''):
        # Validation level to which the incident belongs. Integer 1-5.
        self.level = self.default_level if level == None else level
        # Thematic area to which the incident belongs: Format, Meta, Morpho,
        # Syntax, Enhanced, Coref, Warning.
        self.testclass = self.default_testclass if testclass == None else testclass
        # TODO: capire
        # Identifier of the test that lead to the incident. Short string.
        self.testid = self.default_testid if testid == None else testid
        # Verbose description of the error for the user. It does not have to be
        # identical for all errors with the same testid because it can contain
        # instance-specific data (e.g. the word form).
        self.message = self.default_message if message == None else message
        # Additional more verbose information. To be printed with the first
        # incident of a given type.
        # TODO: levare
        self.explanation = explanation
        # File name. The default is the file from which we are reading right
        # now ('-' if reading from STDIN).
        self.filename = 'STDIN' if state.current_file_name == '-' else os.path.basename(state.current_file_name)
        # Line number. The default is the most recently read line as recorded
        # in the state; but in most cases we need to get the number
        # during instantiation, as the most recently read line is the last line
        # of the sentence, and the error was found on one of the words of the
        # sentence.
        self.lineno = lineno if lineno != None else self.default_lineno if self.default_lineno != None else state.current_line
        if self.lineno < 0: # TODO: choose either -1 or None
            self.lineno = state.sentence_line
        # Current (most recently read) sentence id.
        self.sentid = state.sentence_id
        # ID of the node on which the error occurred (if it pertains to one node).
        self.nodeid = nodeid # TODO: add to state

    # TODO: overwrite __str__ or __repr__
    def report(self, state, args):
        # Even if we should be quiet, at least count the error.
        state.error_counter[self.testclass] = state.error_counter.get(self.testclass, 0)+1
        if args.quiet:
            return
        # Suppress error messages of a type of which we have seen too many.
        if args.max_err > 0 and state.error_counter[self.testclass] > args.max_err:
            if state.error_counter[self.testclass] == args.max_err + 1:
                print(f'...suppressing further errors regarding {self.testclass}', file=sys.stderr)
            return # suppressed
        # If we are here, the error message should really be printed.
        # Address of the incident.
        address = f'Line {self.lineno} Sent {self.sentid}'
        if self.nodeid:
            address += f' Node {self.nodeid}'
        # Insert file name if there are several input files.
        if len(args.input) > 1:
            address = f'File {self.filename} ' + address
        # Classification of the incident.
        levelclassid = f'L{self.level} {self.testclass} {self.testid}'
        # Message (+ explanation, if this is the first error of its kind).
        message = self.message
        if self.explanation and self.explanation not in state.explanation_printed:
            message += "\n\n" + self.explanation + "\n"
            state.explanation_printed.add(self.explanation)
        print(f'[{address}]: [{levelclassid}] {message}', file=sys.stderr)


#==============================================================================
# Level 1 tests. Only CoNLL-U backbone. Values can be empty or non-UD.
#==============================================================================



class Validator:
    # TODO: only pass args that are actually useful
    def __init__(self, args, specs):
        self.conllu_reader = udapi.block.read.conllu.Conllu()
        self.args = args
        self.specs = specs

    def OLD_next_sentence(self, state, inp):
        """
        `inp` a file-like object yielding lines as unicode

        This function does elementary checking of the input and yields one
        sentence at a time from the input stream. The function guarantees
        elementary integrity of its yields. Some lines may be skipped (e.g.,
        extra empty lines or misplaced comments), and a whole sentence will be
        skipped if one of its token lines has unexpected number of columns.

        However, some low-level errors currently do not lead to excluding the
        sentence from being yielded and put to subsequent tests. Specifically,
        character constraints on individual fields are tested here but errors
        are not considered fatal.

        This function is a generator. The caller can call it in a 'for x in ...'
        loop. In each iteration of the caller's loop, the generator will generate
        the next sentence, that is, it will read the next sentence from the input
        stream. (Technically, the function returns an object, and the object will
        then read the sentences within the caller's loop.)
        """
        all_lines = [] # List of lines in the sentence (comments and tokens), minus final empty line, minus newline characters (and minus spurious lines that are neither comment lines nor token lines)
        comment_lines = [] # List of comment lines to go with the current sentence; initial part of all_lines
        token_lines_fields = [] # List of token/word lines of the current sentence, converted from string to list of fields
        corrupted = False # In case of wrong number of columns check the remaining lines of the sentence but do not yield the sentence for further processing.
        state.comment_start_line = None

        for line_counter, line in enumerate(inp):
            state.current_line = line_counter+1
            Incident.default_level = 1
            Incident.default_testclass = 'Format'
            Incident.default_lineno = None # use the most recently read line
            if not state.comment_start_line:
                state.comment_start_line = state.current_line
            line = line.rstrip("\n")
            self.validate_unicode_normalization(state, line)
            if utils.is_whitespace(line):
                Incident(
                    state=state,
                    testid='pseudo-empty-line',
                    message='Spurious line that appears empty but is not; there are whitespace characters.'
                ).confirm()
                # We will pretend that the line terminates a sentence in order to
                # avoid subsequent misleading error messages.
                if token_lines_fields:
                    if not corrupted:
                        yield all_lines, comment_lines, token_lines_fields
                    all_lines = []
                    comment_lines = []
                    token_lines_fields = []
                    corrupted = False
                    state.comment_start_line = None
            elif not line: # empty line
                if token_lines_fields: # sentence done
                    if not corrupted:
                        yield all_lines, comment_lines, token_lines_fields
                    all_lines = []
                    comment_lines = []
                    token_lines_fields = []
                    corrupted = False
                    state.comment_start_line = None
                else:
                    Incident(
                        state=state,
                        testid='extra-empty-line',
                        message='Spurious empty line. Only one empty line is expected after every sentence.'
                    ).confirm()
            elif line[0] == '#':
                # We will really validate sentence ids later. But now we want to remember
                # everything that looks like a sentence id and use it in the error messages.
                # Line numbers themselves may not be sufficient if we are reading multiple
                # files from a pipe.
                match = utils.crex.sentid.fullmatch(line)
                if match:
                    state.sentence_id = match.group(1)
                if not token_lines_fields: # before sentence
                    all_lines.append(line)
                    comment_lines.append(line)
                else:
                    Incident(
                        state=state,
                        testid='misplaced-comment',
                        message='Spurious comment line. Comments are only allowed before a sentence.'
                    ).confirm()
            elif line[0].isdigit():
                if not token_lines_fields: # new sentence
                    state.sentence_line = state.current_line
                cols = line.split("\t")
                # If there is an unexpected number of columns, do not test their contents.
                # Maybe the contents belongs to a different column. And we could see
                # an exception if a column value is missing.
                if len(cols) == COLCOUNT:
                    all_lines.append(line)
                    token_lines_fields.append(cols)
                    # Low-level tests, mostly universal constraints on whitespace in fields, also format of the ID field.
                    self.validate_whitespace(state, cols)
                else:
                    Incident(
                        state=state,
                        testid='number-of-columns',
                        message=f'The line has {len(cols)} columns but {COLCOUNT} are expected. The line will be excluded from further tests.'
                    ).confirm()
                    corrupted = True
            else: # A line which is neither a comment nor a token/word, nor empty. That's bad!
                Incident(
                    state=state,
                    testid='invalid-line',
                    message=f"Spurious line: '{line}'. All non-empty lines should start with a digit or the # character. The line will be excluded from further tests."
                ).confirm()
        else: # end of file
            if comment_lines and not token_lines_fields:
                # Comments at the end of the file, no sentence follows them.
                Incident(
                    state=state,
                    testid='misplaced-comment',
                    message='Spurious comment line. Comments are only allowed before a sentence.'
                ).confirm()
            elif comment_lines or token_lines_fields: # These should have been yielded on an empty line!
                Incident(
                    state=state,
                    testid='missing-empty-line',
                    message='Missing empty line after the last sentence.'
                ).confirm()
                if not corrupted:
                    yield all_lines, comment_lines, token_lines_fields



#------------------------------------------------------------------------------
# Level 1 tests applicable to a single line independently of the others.
#------------------------------------------------------------------------------



    def validate_unicode_normalization(self, state, text):
        """
        Tests that letters composed of multiple Unicode characters (such as a base
        letter plus combining diacritics) conform to NFC normalization (canonical
        decomposition followed by canonical composition).

        Parameters
        ----------
        text : str
            The input line to be tested. If the line consists of TAB-separated
            fields (token line), errors reports will specify the field where the
            error occurred. Otherwise (comment line), the error report will not be
            localized.
        """
        normalized_text = unicodedata.normalize('NFC', text)
        if text != normalized_text:
            # Find the first unmatched character and include it in the report.
            firsti = -1
            firstj = -1
            inpfirst = ''
            inpsecond = ''
            nfcfirst = ''
            tcols = text.split("\t")
            ncols = normalized_text.split("\t")
            for i in range(len(tcols)):
                for j in range(len(tcols[i])):
                    if tcols[i][j] != ncols[i][j]:
                        firsti = i
                        firstj = j
                        inpfirst = unicodedata.name(tcols[i][j])
                        nfcfirst = unicodedata.name(ncols[i][j])
                        if j+1 < len(tcols[i]):
                            inpsecond = unicodedata.name(tcols[i][j+1])
                        break
                if firsti >= 0:
                    break
            if len(tcols) > 1:
                testmessage = f"Unicode not normalized: {COLNAMES[firsti]}.character[{firstj}] is {inpfirst}, should be {nfcfirst}."
            else:
                testmessage = f"Unicode not normalized: character[{firstj}] is {inpfirst}, should be {nfcfirst}."
            explanation_second = f" In this case, your next character is {inpsecond}." if inpsecond else ''
            Incident(
                state=state,
                level=1,
                testclass='Unicode',
                testid='unicode-normalization',
                message=testmessage,
                explanation=f"This error usually does not mean that {inpfirst} is an invalid character. Usually it means that this is a base character followed by combining diacritics, and you should replace them by a single combined character.{explanation_second} You can fix normalization errors using the normalize_unicode.pl script from the tools repository."
            ).confirm()



    def validate_whitespace(self, state, cols):
        """
        Checks that columns are not empty and do not contain whitespace characters
        except for patterns that could be allowed at level 4. Applies to all types
        of TAB-containing lines: nodes / words, mwt ranges, empty nodes.

        Parameters
        ----------
        cols : list
            The values of the columns on the current node / token line.
        """
        Incident.default_level = 1
        Incident.default_testclass = 'Format'
        Incident.default_lineno = None # use the most recently read line
        # Some whitespace may be permitted in FORM, LEMMA and MISC but not elsewhere.
        for col_idx in range(COLCOUNT):
            # Must never be empty
            if not cols[col_idx]:
                Incident(
                    state=state,
                    testid='empty-column',
                    message=f'Empty value in column {COLNAMES[col_idx]}.'
                ).confirm()
            else:
                # Must never have leading/trailing whitespace
                if cols[col_idx][0].isspace():
                    Incident(
                        state=state,
                        testid='leading-whitespace',
                        message=f'Leading whitespace not allowed in column {COLNAMES[col_idx]}.'
                    ).confirm()
                if cols[col_idx][-1].isspace():
                    Incident(
                        state=state,
                        testid='trailing-whitespace',
                        message=f'Trailing whitespace not allowed in column {COLNAMES[col_idx]}.'
                    ).confirm()
                # Must never contain two consecutive whitespace characters
                if utils.crex.ws2.search(cols[col_idx]):
                    Incident(
                        state=state,
                        testid='repeated-whitespace',
                        message=f'Two or more consecutive whitespace characters not allowed in column {COLNAMES[col_idx]}.'
                    ).confirm()
        # Multi-word tokens may have whitespaces in MISC but not in FORM or LEMMA.
        # If it contains a space, it does not make sense to treat it as a MWT.
        if utils.is_multiword_token(cols):
            for col_idx in (FORM, LEMMA):
                if col_idx >= len(cols):
                    break # this has been already reported in next_sentence()
                if utils.crex.ws.search(cols[col_idx]):
                    Incident(
                        state=state,
                        testid='invalid-whitespace-mwt',
                        message=f"White space not allowed in multi-word token '{cols[col_idx]}'. If it contains a space, it is not one surface token."
                    ).confirm()
        # These columns must not have whitespace.
        for col_idx in (ID, UPOS, XPOS, FEATS, HEAD, DEPREL, DEPS):
            if col_idx >= len(cols):
                break # this has been already reported in next_sentence()
            if utils.crex.ws.search(cols[col_idx]):
                Incident(
                    state=state,
                    testid='invalid-whitespace',
                    message=f"White space not allowed in column {COLNAMES[col_idx]}: '{cols[col_idx]}'."
                ).confirm()
        # We should also check the ID format (e.g., '1' is good, '01' is wrong).
        # Although it is checking just a single column, we will do it in
        # validate_id_sequence() because that function has the power to block
        # further tests, which could choke up on this.



#------------------------------------------------------------------------------
# Level 1 tests applicable to the whole sentence.
#------------------------------------------------------------------------------



    def OLD_validate_id_sequence(self, state, sentence):
        """
        Validates that the ID sequence is correctly formed.
        Besides reporting the errors, it also returns False to the caller so it can
        avoid building a tree from corrupt IDs.

        sentence ... array of arrays, each inner array contains columns of one line
        """
        ok = True
        Incident.default_level = 1
        Incident.default_testclass = 'Format'
        Incident.default_lineno = None # use the most recently read line
        words=[]
        tokens=[]
        current_word_id, next_empty_id = 0, 1
        for cols in sentence:
            # Check for the format of the ID value. (ID must not be empty.)
            if not (utils.is_word(cols) or utils.is_empty_node(cols) or utils.is_multiword_token(cols)):
                Incident(
                    state=state,
                    testid='invalid-word-id',
                    message=f"Unexpected ID format '{cols[ID]}'."
                ).confirm()
                ok = False
                continue
            if not utils.is_empty_node(cols):
                next_empty_id = 1    # reset sequence
            if utils.is_word(cols):
                t_id = int(cols[ID])
                current_word_id = t_id
                words.append(t_id)
                # Not covered by the previous interval?
                if not (tokens and tokens[-1][0] <= t_id and tokens[-1][1] >= t_id):
                    tokens.append((t_id, t_id)) # nope - let's make a default interval for it
            elif utils.is_multiword_token(cols):
                match = utils.crex.mwtid.fullmatch(cols[ID]) # Check the interval against the regex
                if not match: # This should not happen. The function utils.is_multiword_token() would then not return True.
                    Incident(
                        state=state,
                        testid='invalid-word-interval',
                        message=f"Spurious word interval definition: '{cols[ID]}'."
                    ).confirm()
                    ok = False
                    continue
                beg, end = int(match.group(1)), int(match.group(2))
                if not ((not words and beg >= 1) or (words and beg >= words[-1] + 1)):
                    Incident(
                        state=state,
                        testid='misplaced-word-interval',
                        message='Multiword range not before its first word.'
                    ).confirm()
                    ok = False
                    continue
                tokens.append((beg, end))
            elif utils.is_empty_node(cols):
                word_id, empty_id = (int(i) for i in utils.parse_empty_node_id(cols))
                if word_id != current_word_id or empty_id != next_empty_id:
                    Incident(
                        state=state,
                        testid='misplaced-empty-node',
                        message=f'Empty node id {cols[ID]}, expected {current_word_id}.{next_empty_id}'
                    ).confirm()
                    ok = False
                next_empty_id += 1
                # Interaction of multiword tokens and empty nodes if there is an empty
                # node between the first word of a multiword token and the previous word:
                # This sequence is correct: 4 4.1 5-6 5 6
                # This sequence is wrong:   4 5-6 4.1 5 6
                if word_id == current_word_id and tokens and word_id < tokens[-1][0]:
                    Incident(
                        state=state,
                        testid='misplaced-empty-node',
                        message=f"Empty node id {cols[ID]} must occur before multiword token {tokens[-1][0]}-{tokens[-1][1]}."
                    ).confirm()
                    ok = False
        # Now let's do some basic sanity checks on the sequences.
        # Expected sequence of word IDs is 1, 2, ...
        expstrseq = ','.join(str(x) for x in range(1, len(words) + 1))
        wrdstrseq = ','.join(str(x) for x in words)
        if wrdstrseq != expstrseq:
            Incident(
                state=state,
                lineno=-1,
                testid='word-id-sequence',
                message=f"Words do not form a sequence. Got '{wrdstrseq}'. Expected '{expstrseq}'."
            ).confirm()
            ok = False
        # Check elementary sanity of word intervals.
        # Remember that these are not just multi-word tokens. Here we have intervals even for single-word tokens (b=e)!
        for (b, e) in tokens:
            if e < b: # end before beginning
                Incident(
                    state=state,
                    testid='reversed-word-interval',
                    message=f'Spurious token interval {b}-{e}'
                ).confirm()
                ok = False
                continue
            if b < 1 or e > len(words): # out of range
                Incident(
                    state=state,
                    testid='word-interval-out',
                    message=f'Spurious token interval {b}-{e} (out of range)'
                ).confirm()
                ok = False
                continue
        return ok



    def OLD_validate_token_ranges(self, state, sentence):
        """
        Checks that the word ranges for multiword tokens are valid.

        sentence ... array of arrays, each inner array contains columns of one line
        """
        Incident.default_level = 1
        Incident.default_testclass = 'Format'
        Incident.default_lineno = None # use the most recently read line
        covered = set()
        for cols in sentence:
            if not utils.is_multiword_token(cols):
                continue
            m = utils.crex.mwtid.fullmatch(cols[ID])
            if not m: # This should not happen. The function utils.is_multiword_token() would then not return True.
                Incident(
                    state=state,
                    testid='invalid-word-interval',
                    message=f"Spurious word interval definition: '{cols[ID]}'."
                ).confirm()
                continue
            start, end = m.groups()
            start, end = int(start), int(end)
            # Do not test if start >= end: This was already tested above in validate_id_sequence().
            if covered & set(range(start, end+1)):
                Incident(
                    state=state,
                    testid='overlapping-word-intervals',
                    message=f'Range overlaps with others: {cols[ID]}'
                ).confirm()
            covered |= set(range(start, end+1))



    def OLD_validate_newlines(self, state, inp):
        """
        Checks that the input file consistently uses linux-style newlines (LF only,
        not CR LF like in Windows). To be run on the input file handle after the
        whole input has been read.
        """
        if inp.newlines and inp.newlines != '\n':
            Incident(
                state=state,
                level=1,
                testclass='Format',
                lineno=state.current_line,
                testid='non-unix-newline',
                message='Only the unix-style LF line terminator is allowed.'
            ).confirm()



#==============================================================================
# Level 2 tests. Tree structure, universal tags and deprels. Note that any
# well-formed Feature=Value pair is allowed (because it could be language-
# specific) and any word form or lemma can contain spaces (because language-
# specific guidelines may permit it).
#==============================================================================



#------------------------------------------------------------------------------
# Level 2 tests of sentence metadata.
#------------------------------------------------------------------------------



    def validate_sent_id(self, state, comments, lcode):
        """
        Checks that sentence id exists, is well-formed and unique.
        """
        Incident.default_level = 2
        Incident.default_testclass = 'Metadata'
        Incident.default_lineno = -1 # use the first line after the comments
        matched = []
        for c in comments:
            match = utils.crex.sentid.fullmatch(c)
            if match:
                matched.append(match)
            else:
                if c.startswith('# sent_id') or c.startswith('#sent_id'):
                    Incident(
                        state=state,
                        testid='invalid-sent-id',
                        message=f"Spurious sent_id line: '{c}' should look like '# sent_id = xxxxx' where xxxxx is not whitespace. Forward slash reserved for special purposes."
                    ).confirm()
        if not matched:
            Incident(
                state=state,
                testid='missing-sent-id',
                message='Missing the sent_id attribute.'
            ).confirm()
        elif len(matched) > 1:
            Incident(
                state=state,
                testid='multiple-sent-id',
                message='Multiple sent_id attributes.'
            ).confirm()
        else:
            # Uniqueness of sentence ids should be tested treebank-wide, not just file-wide.
            # For that to happen, all three files should be tested at once.
            sid = matched[0].group(1)
            if sid in state.known_sent_ids:
                Incident(
                    state=state,
                    testid='non-unique-sent-id',
                    message=f"Non-unique sent_id attribute '{sid}'."
                ).confirm()
            if sid.count('/') > 1 or (sid.count('/') == 1 and lcode != 'ud'):
                Incident(
                    state=state,
                    testid='slash-in-sent-id',
                    message=f"The forward slash is reserved for special use in parallel treebanks: '{sid}'"
                ).confirm()
            state.known_sent_ids.add(sid)



    def validate_text_meta(self, state, comments, tree):
        """
        Checks metadata other than sentence id, that is, document breaks, paragraph
        breaks and sentence text (which is also compared to the sequence of the
        forms of individual tokens, and the spaces vs. SpaceAfter=No in MISC).
        """
        Incident.default_level = 2
        Incident.default_testclass = 'Metadata'
        Incident.default_lineno = -1 # use the first line after the comments
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
            Incident(
                state=state,
                testid='multiple-newdoc',
                message='Multiple newdoc attributes.'
            ).confirm()
        if len(newpar_matched) > 1:
            Incident(
                state=state,
                testid='multiple-newpar',
                message='Multiple newpar attributes.'
            ).confirm()
        if (newdoc_matched or newpar_matched) and state.spaceafterno_in_effect:
            Incident(
                state=state,
                testid='spaceafter-newdocpar',
                message='New document or paragraph starts when the last token of the previous sentence says SpaceAfter=No.'
            ).confirm()
        if not text_matched:
            Incident(
                state=state,
                testid='missing-text',
                message='Missing the text attribute.'
            ).confirm()
        elif len(text_matched) > 1:
            Incident(
                state=state,
                testid='multiple-text',
                message='Multiple text attributes.'
            ).confirm()
        else:
            stext = text_matched[0].group(1)
            if stext[-1].isspace():
                Incident(
                    state=state,
                    testid='text-trailing-whitespace',
                    message='The text attribute must not end with whitespace.'
                ).confirm()
            # Validate the text against the SpaceAfter attribute in MISC.
            skip_words = set()
            mismatch_reported = 0 # do not report multiple mismatches in the same sentence; they usually have the same cause
            # We will sum state.sentence_line + iline, and state.sentence_line already points at
            # the first token/node line after the sentence comments. Hence iline shall
            # be 0 once we enter the cycle.
            iline = -1
            for cols in tree:
                iline += 1
                if 'NoSpaceAfter=Yes' in cols[MISC]: # I leave this without the split("|") to catch all
                    Incident(
                        state=state,
                        testid='nospaceafter-yes',
                        message="'NoSpaceAfter=Yes' should be replaced with 'SpaceAfter=No'."
                    ).confirm()
                if len([x for x in cols[MISC].split('|') if re.match(r"^SpaceAfter=", x) and x != 'SpaceAfter=No']) > 0:
                    Incident(
                        state=state,
                        lineno=state.sentence_line+iline,
                        testid='spaceafter-value',
                        message="Unexpected value of the 'SpaceAfter' attribute in MISC. Did you mean 'SpacesAfter'?"
                    ).confirm()
                if utils.is_empty_node(cols):
                    if 'SpaceAfter=No' in cols[MISC]: # I leave this without the split("|") to catch all
                        Incident(
                            state=state,
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
                        Incident(
                            state=state,
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
                        Incident(
                            state=state,
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
                            Incident(
                                state=state,
                                lineno=state.sentence_line+iline,
                                testid='missing-spaceafter',
                                message=f"'SpaceAfter=No' is missing in the MISC field of node {cols[ID]} because the text is '{utils.shorten(cols[FORM]+stext)}'."
                            ).confirm()
                        stext = stext.lstrip()
            if stext:
                Incident(
                    state=state,
                    testid='text-extra-chars',
                    message=f"Extra characters at the end of the text attribute, not accounted for in the FORM fields: '{stext}'"
                ).confirm()



#------------------------------------------------------------------------------
# Level 2 tests applicable to a single line independently of the others.
#------------------------------------------------------------------------------

    def OLD_validate_mwt_empty_vals(self, state, cols, line):
        """
        Checks that a multi-word token has _ empty values in all fields except MISC.
        This is required by UD guidelines although it is not a problem in general,
        therefore a level 2 test.

        Parameters
        ----------
        cols : list
            The values of the columns on the current node / token line.
        line : int
            Number of the line where the node occurs in the file.
        """
        assert utils.is_multiword_token(cols), 'internal error'
        for col_idx in range(LEMMA, MISC): # all columns except the first two (ID, FORM) and the last one (MISC)
            # Exception: The feature Typo=Yes may occur in FEATS of a multi-word token.
            if col_idx == FEATS and cols[col_idx] == 'Typo=Yes':
                # If a multi-word token has Typo=Yes, its component words must not have it.
                # We must remember the span of the MWT and check it in validate_features_level4().
                m = utils.crex.mwtid.fullmatch(cols[ID])
                state.mwt_typo_span_end = m.group(2)
            elif cols[col_idx] != '_':
                Incident(
                    state=state,
                    lineno=line,
                    level=2,
                    testclass='Format',
                    testid='mwt-nonempty-field',
                    message=f"A multi-word token line must have '_' in the column {COLNAMES[col_idx]}. Now: '{cols[col_idx]}'."
                ).confirm()




    def OLD_validate_empty_node_empty_vals(self, state, cols, line):
        """
        Checks that an empty node has _ empty values in HEAD and DEPREL. This is
        required by UD guidelines but not necessarily by CoNLL-U, therefore
        a level 2 test.

        Parameters
        ----------
        cols : list
            The values of the columns on the current node / token line.
        line : int
            Number of the line where the node occurs in the file.
        """
        assert utils.is_empty_node(cols), 'internal error'
        for col_idx in (HEAD, DEPREL):
            if cols[col_idx]!= '_':
                Incident(
                    state=state,
                    lineno=line,
                    level=2,
                    testclass='Format',
                    testid='mwt-nonempty-field',
                    message=f"An empty node must have '_' in the column {COLNAMES[col_idx]}. Now: '{cols[col_idx]}'."
                ).confirm()



    def OLD_validate_character_constraints(self, state, cols, line):
        """
        Checks general constraints on valid characters, e.g. that UPOS
        only contains [A-Z].

        Parameters
        ----------
        cols : list
            The values of the columns on the current node / token line.
        line : int
            Number of the line where the node occurs in the file.
        """
        Incident.default_level = 2
        Incident.default_lineno = line
        if utils.is_multiword_token(cols):
            return
        # Do not test the regular expression utils.crex.upos here. We will test UPOS
        # directly against the list of known tags. That is a level 2 test, too.
        if not (utils.crex.deprel.fullmatch(cols[DEPREL]) or (utils.is_empty_node(cols) and cols[DEPREL] == '_')):
            Incident(
                state=state,
                testclass='Syntax',
                testid='invalid-deprel',
                message=f"Invalid DEPREL value '{cols[DEPREL]}'. Only lowercase English letters or a colon are expected."
            ).confirm()
        try:
            utils.deps_list(cols)
        except ValueError:
            Incident(
                state=state,
                testclass='Enhanced',
                testid='invalid-deps',
                message=f"Failed to parse DEPS: '{cols[DEPS]}'."
            ).confirm()
            return
        if any(deprel for head, deprel in utils.deps_list(cols)
            if not utils.crex.edeprel.fullmatch(deprel)):
                Incident(
                    state=state,
                    testclass='Enhanced',
                    testid='invalid-edeprel',
                    message=f"Invalid enhanced relation type: '{cols[DEPS]}'."
                ).confirm()



    def OLD_validate_upos(self, state, cols, line):
        """
        Checks that the UPOS field contains one of the 17 known tags.

        Parameters
        ----------
        cols : list
            The values of the columns on the current node / token line.
        line : int
            Number of the line where the node occurs in the file.
        """
        if utils.is_empty_node(cols) and cols[UPOS] == '_':
            return
        # Just in case, we still match UPOS against the regular expression that
        # checks general character constraints. However, the list of UPOS, loaded
        # from a JSON file, should conform to the regular expression.
        if not utils.crex.upos.fullmatch(cols[UPOS]) or cols[UPOS] not in self.specs.upos:
            Incident(
                state=state,
                lineno=line,
                level=2,
                testclass='Morpho',
                testid='unknown-upos',
                message=f"Unknown UPOS tag: '{cols[UPOS]}'."
            ).confirm()



    def OLD_validate_features_level2(self, state, cols, line):
        """
        Checks general constraints on feature-value format: Permitted characters in
        feature name and value, features must be sorted alphabetically, features
        cannot be repeated etc.

        Parameters
        ----------
        cols : list
            The values of the columns on the current node / token line.
        line : int
            Number of the line where the node occurs in the file.

        Returns
        -------
        safe : bool
            There were no errors or the errors are not so severe that we should
            refrain from loading the sentence into Udapi.
        """
        Incident.default_lineno = line
        Incident.default_level = 2
        Incident.default_testclass = 'Morpho'
        feats = cols[FEATS]
        if feats == '_':
            return True
        self.features_present(state)
        feat_list = feats.split('|')
        if [f.lower() for f in feat_list] != sorted(f.lower() for f in feat_list):
            Incident(
                state=state,
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
                Incident(
                    state=state,
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
                    Incident(
                        state=state,
                        testid='repeated-feature-value',
                        message=f"Repeated feature values are disallowed: '{feats}'"
                    ).confirm()
                if [v.lower() for v in values] != sorted(v.lower() for v in values):
                    Incident(
                        state=state,
                        testid='unsorted-feature-values',
                        message=f"If a feature has multiple values, these must be sorted: '{f}'"
                    ).confirm()
                for v in values:
                    if not utils.crex.val.fullmatch(v):
                        Incident(
                            state=state,
                            testid='invalid-feature-value',
                            message=f"Spurious value '{v}' in '{f}'. Must start with [A-Z0-9] and only contain [A-Za-z0-9]."
                        ).confirm()
                    # Level 2 tests character properties and canonical order but not that the f-v pair is known.
        if len(attr_set) != len(feat_list):
            Incident(
                state=state,
                testid='repeated-feature',
                message=f"Repeated features are disallowed: '{feats}'."
            ).confirm()
        return safe



    @staticmethod
    def features_present(state):
        """
        In general, the annotation of morphological features is optional, although
        highly encouraged. However, if the treebank does have features, then certain
        features become required. This function is called when the first morphological
        feature is encountered. It remembers that from now on, missing features can
        be reported as errors. In addition, if any such errors have already been
        encountered, they will be reported now.
        """
        if not state.seen_morpho_feature:
            state.seen_morpho_feature = state.current_line
            for testid in state.delayed_feature_errors:
                for occurrence in state.delayed_feature_errors[testid]['occurrences']:
                    occurrence.confirm()



    def OLD_validate_deps(self, state, cols, line):
        """
        Validates that DEPS is correctly formatted and that there are no
        self-loops in DEPS (longer cycles are allowed in enhanced graphs but
        self-loops are not).

        This function must be run on raw DEPS before it is fed into Udapi because
        it checks the order of relations, which is not guaranteed to be preserved
        in Udapi. On the other hand, we assume that it is run after
        validate_id_references() and only if DEPS is parsable and the head indices
        in it are OK.

        Parameters
        ----------
        cols : list
            The values of the columns on the current node / token line.
        line : int
            Number of the line where the node occurs in the file.
        """
        Incident.default_lineno = line
        Incident.default_level = 2
        Incident.default_testclass = 'Format'
        if not (utils.is_word(cols) or utils.is_empty_node(cols)):
            return
        # Remember whether there is at least one difference between the basic
        # tree and the enhanced graph in the entire dataset.
        if cols[DEPS] != '_' and cols[DEPS] != cols[HEAD]+':'+cols[DEPREL]:
            state.seen_enhancement = line
        # We already know that the contents of DEPS is parsable (deps_list() was
        # first called from validate_id_references() and the head indices are OK).
        deps = utils.deps_list(cols)
        ###!!! Float will not work if there are 10 empty nodes between the same two
        ###!!! regular nodes. '1.10' is not equivalent to '1.1'.
        heads = [float(h) for h, d in deps]
        if heads != sorted(heads):
            Incident(
                state=state,
                testid='unsorted-deps',
                message=f"DEPS not sorted by head index: '{cols[DEPS]}'"
            ).confirm()
        else:
            lasth = None
            lastd = None
            for h, d in deps:
                if h == lasth:
                    if d < lastd:
                        Incident(
                            state=state,
                            testid='unsorted-deps-2',
                            message=f"DEPS pointing to head '{h}' not sorted by relation type: '{cols[DEPS]}'"
                        ).confirm()
                    elif d == lastd:
                        Incident(
                            state=state,
                            testid='repeated-deps',
                            message=f"DEPS contain multiple instances of the same relation '{h}:{d}'"
                        ).confirm()
                lasth = h
                lastd = d
        try:
            id_ = float(cols[ID])
        except ValueError:
            # This error has been reported previously.
            return
        if id_ in heads:
            Incident(
                state=state,
                testclass='Enhanced',
                testid='deps-self-loop',
                message=f"Self-loop in DEPS for '{cols[ID]}'"
            ).confirm()



    def OLD_validate_misc(self, state, cols, line):
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
        cols : list
            The values of the columns on the current node / token line.
        line : int
            Number of the line where the node occurs in the file.
        """
        Incident.default_lineno = line
        Incident.default_level = 2
        Incident.default_testclass = 'Warning'
        if cols[MISC] == '_':
            return
        misc = [ma.split('=', 1) for ma in cols[MISC].split('|')]
        mamap = {}
        for ma in misc:
            if ma[0] == '':
                if len(ma) == 1:
                    Incident(
                        state=state,
                        testid='empty-misc',
                        message="Empty attribute in MISC; possible misinterpreted vertical bar?"
                    ).confirm()
                else:
                    Incident(
                        state=state,
                        testid='empty-misc-key',
                        message=f"Empty MISC attribute name in '{ma[0]}={ma[1]}'."
                    ).confirm()
            # We do not warn about MISC items that do not contain '='.
            # But the remaining error messages below assume that ma[1] exists.
            if len(ma) == 1:
                ma.append('')
            if re.match(r"^\s", ma[0]):
                Incident(
                    state=state,
                    testid='misc-extra-space',
                    message=f"MISC attribute name starts with space in '{ma[0]}={ma[1]}'."
                ).confirm()
            elif re.search(r"\s$", ma[0]):
                Incident(
                    state=state,
                    testid='misc-extra-space',
                    message=f"MISC attribute name ends with space in '{ma[0]}={ma[1]}'."
                ).confirm()
            elif re.match(r"^\s", ma[1]):
                Incident(
                    state=state,
                    testid='misc-extra-space',
                    message=f"MISC attribute value starts with space in '{ma[0]}={ma[1]}'."
                ).confirm()
            elif re.search(r"\s$", ma[1]):
                Incident(
                    state=state,
                    testid='misc-extra-space',
                    message=f"MISC attribute value ends with space in '{ma[0]}={ma[1]}'."
                ).confirm()
            if re.match(r"^(SpaceAfter|Lang|Translit|LTranslit|Gloss|LId|LDeriv)$", ma[0]):
                mamap.setdefault(ma[0], 0)
                mamap[ma[0]] = mamap[ma[0]] + 1
            elif re.match(r"^\s*(spaceafter|lang|translit|ltranslit|gloss|lid|lderiv)\s*$", ma[0], re.IGNORECASE):
                Incident(
                    state=state,
                    testid='misc-attr-typo',
                    message=f"Possible typo (case or spaces) in MISC attribute '{ma[0]}={ma[1]}'."
                ).confirm()
        for a in list(mamap):
            if mamap[a] > 1:
                Incident(
                    state=state,
                    testclass='Format', # this one is real error
                    testid='repeated-misc',
                    message=f"MISC attribute '{a}' not supposed to occur twice"
                ).confirm()



#------------------------------------------------------------------------------
# Level 2 tests applicable to the whole sentence.
#------------------------------------------------------------------------------



    def OLD_validate_id_references(self, state, sentence):
        """
        Verifies that HEAD and DEPS reference existing IDs. If this function does
        not return True, most of the other tests should be skipped for the current
        sentence (in particular anything that considers the tree structure).

        Parameters
        ----------
        sentence : list
            Lines (arrays of columns): words, mwt tokens, empty nodes.

        Returns
        -------
        ok : bool
        """
        ok = True
        Incident.default_level = 2
        Incident.default_testclass = 'Format'
        word_tree = [cols for cols in sentence if utils.is_word(cols) or utils.is_empty_node(cols)]
        ids = set([cols[ID] for cols in word_tree])
        for cols in word_tree:
            # Test the basic HEAD only for non-empty nodes.
            # We have checked elsewhere that it is empty for empty nodes.
            if not utils.is_empty_node(cols):
                match = utils.crex.head.fullmatch(cols[HEAD])
                if match is None:
                    Incident(
                        state=state,
                        testid='invalid-head',
                        message=f"Invalid HEAD: '{cols[HEAD]}'."
                    ).confirm()
                    ok = False
                if not (cols[HEAD] in ids or cols[HEAD] == '0'):
                    Incident(
                        state=state,
                        testclass='Syntax',
                        testid='unknown-head',
                        message=f"Undefined HEAD (no such ID): '{cols[HEAD]}'."
                    ).confirm()
                    ok = False
            try:
                deps = utils.deps_list(cols)
            except ValueError:
                # Similar errors have probably been reported earlier.
                Incident(
                    state=state,
                    testid='invalid-deps',
                    message=f"Failed to parse DEPS: '{cols[DEPS]}'."
                ).confirm()
                ok = False
                continue
            for head, deprel in deps:
                match = utils.crex.ehead.fullmatch(head)
                if match is None:
                    Incident(
                        state=state,
                        testid='invalid-ehead',
                        message=f"Invalid enhanced head reference: '{head}'."
                    ).confirm()
                    ok = False
                if not (head in ids or head == '0'):
                    Incident(
                        state=state,
                        testclass='Enhanced',
                        testid='unknown-ehead',
                        message=f"Undefined enhanced head reference (no such ID): '{head}'."
                    ).confirm()
                    ok = False
        return ok


    def validate_tree(self, state, sentence):
        """
        Takes the list of non-comment lines (line = list of columns) describing
        a sentence. Returns an array with line number corresponding to each tree
        node. In case of fatal problems (missing HEAD etc.) returns None
        (and reports the error, unless it is something that should have been
        reported earlier).

        We will assume that this function is called only if both ID and HEAD values
        have been found valid for all tree nodes, including the sequence of IDs
        and the references from HEAD to existing IDs.

        This function originally served to build a data structure that would
        describe the tree and make it accessible during subsequent tests. Now we
        use the Udapi data structures instead but we still have to call this
        function first because it will survive and report ill-formed input. In
        such a case, the Udapi data structure will not be built and Udapi-based
        tests will be skipped.

        Parameters
        ----------
        sentence : list
            Lines (arrays of columns): words, mwt tokens, empty nodes.

        Returns
        -------
        ok : bool
        """
        Incident.default_level = 2
        Incident.default_testclass = 'Syntax'
        node_line = state.sentence_line - 1
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
            id_ = int(cols[ID])
            head = int(cols[HEAD])
            if head == id_:
                Incident(
                    state=state,
                    lineno=node_line,
                    testid='head-self-loop',
                    message=f'HEAD == ID for {cols[ID]}'
                ).confirm()
                return False
            # Incrementally build the set of children of every node.
            children.setdefault(head, set()).add(id_)
        word_ids = list(range(1, n_words+1))
        # Check that there is just one node with the root relation.
        children_0 = sorted(children.get(0, []))
        if len(children_0) > 1 and self.args.single_root:
            Incident(
                state=state,
                lineno=-1,
                testid='multiple-roots',
                message=f"Multiple root words: {children_0}"
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
            Incident(
                state=state,
                lineno=-1,
                testid='non-tree',
                message=f'Non-tree structure. Words {str_unreachable} are not reachable from the root 0.'
            ).confirm()
            return False
        return True


    def validate_root(self, state, node, line):
        """
        Checks that DEPREL is "root" iff HEAD is 0.

        Parameters
        ----------
        node : udapi.core.node.Node object
            The node whose incoming relation will be validated. This function
            operates on both regular and empty nodes. Make sure to call it for
            empty nodes, too!
        line : int
            Number of the line where the node occurs in the file.
        """
        Incident.default_lineno = line
        Incident.default_level = 2
        Incident.default_testclass = 'Syntax'
        if not node.is_empty():
            if node.parent.ord == 0 and node.udeprel != 'root':
                Incident(
                    state=state,
                    testid='0-is-not-root',
                    message="DEPREL must be 'root' if HEAD is 0."
                ).confirm()
            if node.parent.ord != 0 and node.udeprel == 'root':
                Incident(
                    state=state,
                    testid='root-is-not-0',
                    message="DEPREL cannot be 'root' if HEAD is not 0."
                ).confirm()
        # In the enhanced graph, test both regular and empty roots.
        for edep in node.deps:
            if edep['parent'].ord == 0 and utils.lspec2ud(edep['deprel']) != 'root':
                Incident(
                    state=state,
                    testclass='Enhanced',
                    testid='enhanced-0-is-not-root',
                    message="Enhanced relation type must be 'root' if head is 0."
                ).confirm()
            if edep['parent'].ord != 0 and utils.lspec2ud(edep['deprel']) == 'root':
                Incident(
                    state=state,
                    testclass='Enhanced',
                    testid='enhanced-root-is-not-0',
                    message="Enhanced relation type cannot be 'root' if head is not 0."
                ).confirm()


    def OLD_validate_deps_all_or_none(self, state, sentence):
        """
        Takes the list of non-comment lines (line = list of columns) describing
        a sentence. Checks that enhanced dependencies are present if they were
        present at another sentence, and absent if they were absent at another
        sentence.
        """
        egraph_exists = False # enhanced deps are optional
        for cols in sentence:
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
        Incident.default_testclass = 'Enhanced'
        if egraph_exists:
            if not state.seen_enhanced_graph:
                state.seen_enhanced_graph = state.sentence_line
                if state.seen_tree_without_enhanced_graph:
                    Incident(
                        state=state,
                        testid='edeps-only-sometimes',
                        message=f"Enhanced graph must be empty because we saw empty DEPS on line {state.seen_tree_without_enhanced_graph}"
                    ).confirm()
        else:
            if not state.seen_tree_without_enhanced_graph:
                state.seen_tree_without_enhanced_graph = state.sentence_line
                if state.seen_enhanced_graph:
                    Incident(
                        state=state,
                        testid='edeps-only-sometimes',
                        message=f"Enhanced graph cannot be empty because we saw non-empty DEPS on line {state.seen_enhanced_graph}"
                    ).confirm()


    def validate_egraph_connected(self, state, nodes, linenos):
        """
        Takes the list of nodes (including empty nodes). If there are enhanced
        dependencies in DEPS, builds the enhanced graph and checks that it is
        rooted and connected.

        Parameters
        ----------
        nodes : list of udapi.core.node.Node objects
            List of nodes in the sentence, including empty nodes, sorted by word
            order.
        linenos : dict
            Indexed by node ID (string), contains the line number on which the node
            occurs.
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
            Incident(
                state=state,
                lineno=linenos[sur[0]],
                level=2,
                testclass='Enhanced',
                testid='unconnected-egraph',
                message=f"Enhanced graph is not connected. Nodes {sur} are not reachable from any root"
            ).confirm()
            return None



#==============================================================================
# Level 3 tests. Annotation content vs. the guidelines (only universal tests).
#==============================================================================


    def validate_required_feature(self, state, feats, required_feature, required_value, incident):
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


    def validate_expected_features(self, state, node, lineno):
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
        node : udapi.core.node.Node object
            The tree node to be tested.
        lineno : int
            The 1-based index of the line where the node occurs.
        """
        Incident.default_lineno = lineno
        Incident.default_level = 3
        Incident.default_testclass = 'Warning'
        if node.upos in ['PRON', 'DET']:
            self.validate_required_feature(state, node.feats, 'PronType', None, Incident(
                state=state,
                testid='pron-det-without-prontype',
                message=f"The word '{utils.formtl(node)}' is tagged '{node.upos}' but it lacks the 'PronType' feature"
            ))
        if node.feats['VerbForm'] == 'Fin' and node.feats['Mood'] == '':
            Incident(
                state=state,
                testid='verbform-fin-without-mood',
                message=f"Finite verb '{utils.formtl(node)}' lacks the 'Mood' feature"
            ).confirm()
        elif node.feats['Mood'] != '' and node.feats['VerbForm'] != 'Fin':
            Incident(
                state=state,
                testid='mood-without-verbform-fin',
                message=f"Non-empty 'Mood' feature at a word that is not finite verb ('{utils.formtl(node)}')"
            ).confirm()



    def validate_upos_vs_deprel(self, state, node, lineno):
        """
        For certain relations checks that the dependent word belongs to an expected
        part-of-speech category. Occasionally we may have to check the children of
        the node, too.

        Parameters
        ----------
        node : udapi.core.node.Node object
            The tree node to be tested.
        lineno : int
            The 1-based index of the line where the node occurs.
        """
        Incident.default_lineno = lineno
        Incident.default_level = 3
        Incident.default_testclass = 'Syntax'
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
            Incident(
                state=state,
                testclass='Warning',
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
            Incident(
                state=state,
                testid='rel-upos-det',
                message=f"'det' should be 'DET' or 'PRON' but it is '{upos}' ('{utils.formtl(node)}')"
            ).confirm()
        # Nummod is for "number phrases" only. This could be interpreted as NUM only,
        # but some languages treat some cardinal numbers as NOUNs, and in
        # https://github.com/UniversalDependencies/docs/issues/596,
        # we concluded that the validator will tolerate them.
        if deprel == 'nummod' and not re.match(r"^(NUM|NOUN|SYM)$", upos):
            Incident(
                state=state,
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
            Incident(
                state=state,
                testid='rel-upos-advmod',
                message=f"'advmod' should be 'ADV' but it is '{upos}' ('{utils.formtl(node)}')"
            ).confirm()
        # Known expletives are pronouns. Determiners and particles are probably acceptable, too.
        if deprel == 'expl' and not re.match(r"^(PRON|DET|PART)$", upos):
            Incident(
                state=state,
                testid='rel-upos-expl',
                message=f"'expl' should normally be 'PRON' but it is '{upos}' ('{utils.formtl(node)}')"
            ).confirm()
        # Auxiliary verb/particle must be AUX.
        if deprel == 'aux' and not re.match(r"^(AUX)", upos):
            Incident(
                state=state,
                testid='rel-upos-aux',
                message=f"'aux' should be 'AUX' but it is '{upos}' ('{utils.formtl(node)}')"
            ).confirm()
        # Copula is an auxiliary verb/particle (AUX) or a pronoun (PRON|DET).
        if deprel == 'cop' and not re.match(r"^(AUX|PRON|DET|SYM)", upos):
            Incident(
                state=state,
                testid='rel-upos-cop',
                message=f"'cop' should be 'AUX' or 'PRON'/'DET' but it is '{upos}' ('{utils.formtl(node)}')"
            ).confirm()
        # Case is normally an adposition, maybe particle.
        # However, there are also secondary adpositions and they may have the original POS tag:
        # NOUN: [cs] pomocí, prostřednictvím
        # VERB: [en] including
        # Interjection can also act as case marker for vocative, as in Sanskrit: भोः भगवन् / bhoḥ bhagavan / oh sir.
        if deprel == 'case' and re.match(r"^(PROPN|ADJ|PRON|DET|NUM|AUX)", upos):
            Incident(
                state=state,
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
            Incident(
                state=state,
                testid='rel-upos-mark',
                message=f"'mark' should not be '{upos}' ('{utils.formtl(node)}')"
            ).confirm()
        # Cc is a conjunction, possibly an adverb or particle.
        if deprel == 'cc' and re.match(r"^(NOUN|PROPN|ADJ|PRON|DET|NUM|VERB|AUX|INTJ)", upos):
            Incident(
                state=state,
                testid='rel-upos-cc',
                message=f"'cc' should not be '{upos}' ('{utils.formtl(node)}')"
            ).confirm()
        if deprel == 'punct' and upos != 'PUNCT':
            Incident(
                state=state,
                testid='rel-upos-punct',
                message=f"'punct' must be 'PUNCT' but it is '{upos}' ('{utils.formtl(node)}')"
            ).confirm()
        if upos == 'PUNCT' and not re.match(r"^(punct|root)", deprel):
            Incident(
                state=state,
                testid='upos-rel-punct',
                message=f"'PUNCT' must be 'punct' but it is '{node.deprel}' ('{utils.formtl(node)}')"
            ).confirm()
        if upos == 'PROPN' and (deprel == 'fixed' or 'fixed' in childrels):
            Incident(
                state=state,
                testid='rel-upos-fixed',
                message=f"'fixed' should not be used for proper nouns ('{utils.formtl(node)}')."
            ).confirm()



    def validate_flat_foreign(self, state, node, lineno, linenos):
        """
        flat:foreign is an optional subtype of flat. It is used to connect two words
        in a code-switched segment of foreign words if the annotators did not want
        to provide the analysis according to the source language. If flat:foreign
        is used, both the parent and the child should have the Foreign=Yes feature
        and their UPOS tag should be X.

        Parameters
        ----------
        node : udapi.core.node.Node object
            The tree node to be tested.
        lineno : int
            The 1-based index of the line where the node occurs.
        linenos : dict
            Key is node ID (string, not int or float!) Value is the 1-based index
            of the line where the node occurs (int).
        """
        Incident.default_level = 3
        Incident.default_testclass = 'Warning' # or Morpho
        if node.deprel != 'flat:foreign':
            return
        parent = node.parent
        if node.upos != 'X' or str(node.feats) != 'Foreign=Yes':
            Incident(
                state=state,
                lineno=lineno,
                nodeid=node.ord,
                testid='flat-foreign-upos-feats',
                message="The child of a flat:foreign relation should have UPOS X and Foreign=Yes (but no other features)."
            ).confirm()
        if parent.upos != 'X' or str(parent.feats) != 'Foreign=Yes':
            Incident(
                state=state,
                lineno=linenos[str(parent.ord)],
                nodeid=parent.ord,
                testid='flat-foreign-upos-feats',
                message="The parent of a flat:foreign relation should have UPOS X and Foreign=Yes (but no other features)."
            ).confirm()



    def validate_left_to_right_relations(self, state, node, lineno):
        """
        Certain UD relations must always go left-to-right (in the logical order,
        meaning that parent precedes child, disregarding that some languages have
        right-to-left writing systems).
        Here we currently check the rule for the basic dependencies.
        The same should also be tested for the enhanced dependencies!

        Parameters
        ----------
        node : udapi.core.node.Node object
            The tree node to be tested.
        lineno : int
            The 1-based index of the line where the node occurs.
        """
        # According to the v2 guidelines, apposition should also be left-headed, although the definition of apposition may need to be improved.
        if re.match(r"^(conj|fixed|flat|goeswith|appos)", node.deprel):
            ichild = node.ord
            iparent = node.parent.ord
            if ichild < iparent:
                # We must recognize the relation type in the test id so we can manage exceptions for legacy treebanks.
                # For conj, flat, and fixed the requirement was introduced already before UD 2.2.
                # For appos and goeswith the requirement was introduced before UD 2.4.
                # The designation "right-to-left" is confusing in languages with right-to-left writing systems.
                # We keep it in the testid but we make the testmessage more neutral.
                Incident(
                    state=state,
                    lineno=lineno,
                    nodeid=node.ord,
                    level=3,
                    testclass='Syntax',
                    testid=f"right-to-left-{node.udeprel}",
                    message=f"Parent of relation '{node.deprel}' must precede the child in the word order."
                ).confirm()



    def validate_single_subject(self, state, node, lineno):
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
        node : udapi.core.node.Node object
            The tree node to be tested.
        lineno : int
            The 1-based index of the line where the node occurs.
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
        if len(subjects) > 1:
            Incident(
                state=state,
                lineno=lineno,
                nodeid=node.ord,
                level=3,
                testclass='Syntax',
                testid='too-many-subjects',
                message=f"Multiple subjects {str(subject_ids)} ({str(subject_forms)[1:-1]}) not subtyped as ':outer'.",
                explanation="Outer subjects are allowed if a clause acts as the predicate of another clause."
            ).confirm()



    def validate_single_object(self, state, node, lineno):
        """
        No predicate should have more than one direct object (number of indirect
        objects is unlimited). Theoretically, ccomp should be understood as a
        clausal equivalent of a direct object, but we do not have an indirect
        equivalent, so it seems better to tolerate additional ccomp at present.

        Parameters
        ----------
        node : udapi.core.node.Node object
            The tree node to be tested.
        lineno : int
            The 1-based index of the line where the node occurs.
        """
        objects = [x for x in node.children if x.udeprel == 'obj']
        object_ids = [x.ord for x in objects]
        object_forms = [utils.formtl(x) for x in objects]
        if len(objects) > 1:
            Incident(
                state=state,
                lineno=lineno,
                nodeid=node.ord,
                level=3,
                testclass='Syntax',
                testid='too-many-objects',
                message=f"Multiple direct objects {str(object_ids)} ({str(object_forms)[1:-1]}) under one predicate."
            ).confirm()



    def validate_orphan(self, state, node, lineno):
        """
        The orphan relation is used to attach an unpromoted orphan to the promoted
        orphan in gapping constructions. A common error is that the promoted orphan
        gets the orphan relation too. The parent of orphan is typically attached
        via a conj relation, although some other relations are plausible too.

        Parameters
        ----------
        node : udapi.core.node.Node object
            The tree node to be tested.
        lineno : int
            The 1-based index of the line where the node occurs.
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
                Incident(
                    state=state,
                    lineno=lineno,
                    nodeid=node.ord,
                    level=3,
                    testclass='Warning',
                    testid='orphan-parent',
                    message=f"The parent of 'orphan' should normally be 'conj' but it is '{node.parent.udeprel}'."
                ).confirm()



    def validate_functional_leaves(self, state, node, lineno, linenos):
        """
        Most of the time, function-word nodes should be leaves. This function
        checks for known exceptions and warns in the other cases.
        (https://universaldependencies.org/u/overview/syntax.html#function-word-modifiers)

        Parameters
        ----------
        node : udapi.core.node.Node object
            The tree node to be tested.
        lineno : int
            The 1-based index of the line where the node occurs.
        linenos : dict
            Key is node ID (string, not int or float!) Value is the 1-based index
            of the line where the node occurs (int).
        """
        # This is a level 3 test, we will check only the universal part of the relation.
        deprel = node.udeprel
        if re.match(r"^(case|mark|cc|aux|cop|det|clf|fixed|goeswith|punct)$", deprel):
            idparent = node.ord
            pdeprel = deprel
            pfeats = node.feats
            for child in node.children:
                idchild = child.ord
                Incident.default_lineno = linenos[str(idchild)]
                Incident.default_level = 3
                Incident.default_testclass = 'Syntax'
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
                    Incident(
                        state=state,
                        nodeid=node.ord,
                        testid='leaf-mark-case',
                        message=f"'{pdeprel}' not expected to have children ({idparent}:{node.form}:{pdeprel} --> {idchild}:{child.form}:{cdeprel})"
                    ).confirm()
                if re.match(r"^(aux|cop)$", pdeprel) and not re.match(r"^(goeswith|fixed|reparandum|conj|cc|punct)$", cdeprel):
                    Incident(
                        state=state,
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
                    Incident(
                        state=state,
                        nodeid=node.ord,
                        testid='leaf-det',
                        message=f"'{pdeprel}' not expected to have children ({idparent}:{node.form}:{pdeprel} --> {idchild}:{child.form}:{cdeprel})"
                    ).confirm()
                if re.match(r"^(clf)$", pdeprel) and not re.match(r"^(advmod|obl|goeswith|fixed|reparandum|conj|cc|punct)$", cdeprel):
                    Incident(
                        state=state,
                        nodeid=node.ord,
                        testid='leaf-clf',
                        message=f"'{pdeprel}' not expected to have children ({idparent}:{node.form}:{pdeprel} --> {idchild}:{child.form}:{cdeprel})"
                    ).confirm()
                if re.match(r"^(cc)$", pdeprel) and not re.match(r"^(goeswith|fixed|reparandum|conj|punct)$", cdeprel):
                    Incident(
                        state=state,
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
                    Incident(
                        state=state,
                        nodeid=node.ord,
                        testid='leaf-fixed',
                        message=f"'{pdeprel}' not expected to have children ({idparent}:{node.form}:{pdeprel} --> {idchild}:{child.form}:{cdeprel})"
                    ).confirm()
                # Goeswith cannot have any children, not even another goeswith.
                elif pdeprel == 'goeswith':
                    Incident(
                        state=state,
                        nodeid=node.ord,
                        testid='leaf-goeswith',
                        message=f"'{pdeprel}' not expected to have children ({idparent}:{node.form}:{pdeprel} --> {idchild}:{child.form}:{cdeprel})"
                    ).confirm()
                # Punctuation can exceptionally have other punct children if an exclamation
                # mark is in brackets or quotes. It cannot have other children.
                elif pdeprel == 'punct' and cdeprel != 'punct':
                    Incident(
                        state=state,
                        nodeid=node.ord,
                        testid='leaf-punct',
                        message=f"'{pdeprel}' not expected to have children ({idparent}:{node.form}:{pdeprel} --> {idchild}:{child.form}:{cdeprel})"
                    ).confirm()



    def validate_fixed_span(self, state, node, lineno):
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
        node : udapi.core.node.Node object
            The tree node to be tested.
        lineno : int
            The 1-based index of the line where the node occurs.
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
                Incident(
                    state=state,
                    lineno=lineno,
                    nodeid=node.ord,
                    level=3,
                    testclass='Warning',
                    testid='fixed-gap',
                    message=f"Gaps in fixed expression {str(fxordlist)} '{fxexpr}'"
                ).confirm()


    def validate_goeswith_span(self, state, node, lineno):
        """
        The relation 'goeswith' is used to connect word parts that are separated
        by whitespace and should be one word instead. We assume that the relation
        goes left-to-right, which is checked elsewhere. Here we check that the
        nodes really were separated by whitespace. If there is another node in the
        middle, it must be also attached via 'goeswith'. The parameter id refers to
        the node whose goeswith children we test.

        Parameters
        ----------
        node : udapi.core.node.Node object
            The tree node to be tested.
        lineno : int
            The 1-based index of the line where the node occurs.
        """
        Incident.default_lineno = lineno
        Incident.default_level = 3
        Incident.default_testclass = 'Syntax'
        gwchildren = [c for c in node.children if c.udeprel == 'goeswith']
        if gwchildren:
            gwlist = sorted([node] + gwchildren)
            gwrange = [n for n in node.root.descendants if n.ord >= node.ord and n.ord <= gwchildren[-1].ord]
            # All nodes between me and my last goeswith child should be goeswith too.
            if gwlist != gwrange:
                gwordlist = [n.ord for n in gwlist]
                gwordrange = [n.ord for n in gwrange]
                Incident(
                    state=state,
                    nodeid=node.ord,
                    testid='goeswith-gap',
                    message=f"Gaps in goeswith group {str(gwordlist)} != {str(gwordrange)}."
                ).confirm()
            # Non-last node in a goeswith range must have a space after itself.
            nospaceafter = [x for x in gwlist[:-1] if x.misc['SpaceAfter'] == 'No']
            if nospaceafter:
                Incident(
                    state=state,
                    nodeid=node.ord,
                    testid='goeswith-nospace',
                    message="'goeswith' cannot connect nodes that are not separated by whitespace."
                ).confirm()
            # This is not about the span of the interrupted word, but since we already
            # know that we are at the head of a goeswith word, let's do it here, too.
            # Every goeswith parent should also have Typo=Yes. However, this is not
            # required if the treebank does not have features at all.
            incident = Incident(
                state=state,
                nodeid=node.ord,
                testclass='Morpho',
                testid='goeswith-missing-typo',
                message="Since the treebank has morphological features, 'Typo=Yes' must be used with 'goeswith' heads."
            )
            self.validate_required_feature(state, node.feats, 'Typo', 'Yes', incident)



    def validate_goeswith_morphology_and_edeps(self, state, node, lineno):
        """
        If a node has the 'goeswith' incoming relation, it is a non-first part of
        a mistakenly interrupted word. The lemma, upos tag and morphological features
        of the word should be annotated at the first part, not here.

        Parameters
        ----------
        node : udapi.core.node.Node object
            The tree node to be tested.
        lineno : int
            The 1-based index of the line where the node occurs.
        """
        Incident.default_lineno = lineno
        Incident.default_level = 3
        Incident.default_testclass = 'Morpho'
        if node.udeprel == 'goeswith':
            if node.lemma != '_':
                Incident(
                    state=state,
                    nodeid=node.ord,
                    testid='goeswith-lemma',
                    message="The lemma of a 'goeswith'-connected word must be annotated only at the first part."
                ).confirm()
            if node.upos != 'X':
                Incident(
                    state=state,
                    nodeid=node.ord,
                    testid='goeswith-upos',
                    message="The UPOS tag of a 'goeswith'-connected word must be annotated only at the first part; the other parts must be tagged 'X'."
                ).confirm()
            if str(node.feats) != '_':
                Incident(
                    state=state,
                    nodeid=node.ord,
                    testid='goeswith-feats',
                    message="The morphological features of a 'goeswith'-connected word must be annotated only at the first part."
                ).confirm()
            if str(node.raw_deps) != '_' and str(node.raw_deps) != str(node.parent.ord)+':'+node.deprel:
                Incident(
                    state=state,
                    nodeid=node.ord,
                    testclass='Enhanced',
                    testid='goeswith-edeps',
                    message="A 'goeswith' dependent cannot have any additional dependencies in the enhanced graph."
                ).confirm()



    def validate_projective_punctuation(self, state, node, lineno):
        """
        Punctuation is not supposed to cause nonprojectivity or to be attached
        nonprojectively.

        Parameters
        ----------
        node : udapi.core.node.Node object
            The tree node to be tested.
        lineno : int
            The 1-based index of the line where the node occurs.
        """
        Incident.default_lineno = lineno
        Incident.default_level = 3
        Incident.default_testclass = 'Syntax'
        if node.udeprel == 'punct':
            nonprojnodes = utils.get_caused_nonprojectivities(node)
            if nonprojnodes:
                Incident(
                    state=state,
                    nodeid=node.ord,
                    testid='punct-causes-nonproj',
                    message=f"Punctuation must not cause non-projectivity of nodes {nonprojnodes}"
                ).confirm()
            gap = utils.get_gap(node)
            if gap:
                Incident(
                    state=state,
                    nodeid=node.ord,
                    testid='punct-is-nonproj',
                    message=f"Punctuation must not be attached non-projectively over nodes {sorted(gap)}"
                ).confirm()


    # TODO: rename to something more meaningful
    def validate_annotation(self, state, tree, linenos):
        """
        Checks universally valid consequences of the annotation guidelines. Looks
        at regular nodes and basic tree, not at enhanced graph (which is checked
        elsewhere).

        Parameters
        ----------
        tree : udapi.core.root.Root object
        linenos : dict
            Key is node ID (string, not int or float!) Value is the 1-based index
            of the line where the node occurs (int).
        """
        nodes = tree.descendants
        for node in nodes:
            lineno = linenos[str(node.ord)]
            self.validate_expected_features(state, node, lineno)
            self.validate_upos_vs_deprel(state, node, lineno)
            self.validate_flat_foreign(state, node, lineno, linenos)
            self.validate_left_to_right_relations(state, node, lineno)
            self.validate_single_subject(state, node, lineno)
            self.validate_single_object(state, node, lineno)
            self.validate_orphan(state, node, lineno)
            self.validate_functional_leaves(state, node, lineno, linenos)
            self.validate_fixed_span(state, node, lineno)
            self.validate_goeswith_span(state, node, lineno)
            self.validate_goeswith_morphology_and_edeps(state, node, lineno)
            self.validate_projective_punctuation(state, node, lineno)



    def validate_enhanced_orphan(self, state, node, line):
        """
        Checks universally valid consequences of the annotation guidelines in the
        enhanced representation. Currently tests only phenomena specific to the
        enhanced dependencies; however, we should also test things that are
        required in the basic dependencies (such as left-to-right coordination),
        unless it is obvious that in enhanced dependencies such things are legal.

        Parameters
        ----------
        node : udapi.core.node.Node object
            The node whose incoming relations will be validated. This function
            operates on both regular and empty nodes. Make sure to call it for
            empty nodes, too!
        line : int
            Number of the line where the node occurs in the file.
        """
        Incident.default_lineno = line
        Incident.default_level = 3
        Incident.default_testclass = 'Enhanced'
        # Enhanced dependencies should not contain the orphan relation.
        # However, all types of enhancements are optional and orphans are excluded
        # only if this treebank addresses gapping. We do not know it until we see
        # the first empty node.
        if str(node.deps) == '_':
            return
        if node.is_empty():
            if not state.seen_empty_node:
                state.seen_empty_node = line
                # Empty node itself is not an error. Report it only for the first time
                # and only if an orphan occurred before it.
                if state.seen_enhanced_orphan:
                    Incident(
                        state=state,
                        nodeid=node.ord,
                        testid='empty-node-after-eorphan',
                        message=f"Empty node means that we address gapping and there should be no orphans in the enhanced graph; but we saw one on line {state.seen_enhanced_orphan}"
                    ).confirm()
        udeprels = set([utils.lspec2ud(edep['deprel']) for edep in node.deps])
        if 'orphan' in udeprels:
            if not state.seen_enhanced_orphan:
                state.seen_enhanced_orphan = line
            # If we have seen an empty node, then the orphan is an error.
            if  state.seen_empty_node:
                Incident(
                    state=state,
                    nodeid=node.ord,
                    testid='eorphan-after-empty-node',
                    message=f"'orphan' not allowed in enhanced graph because we saw an empty node on line {state.seen_empty_node}"
                ).confirm()



#==============================================================================
# Level 4 tests. Language-specific formal tests. Now we can check in which
# words spaces are permitted, and which Feature=Value pairs are defined.
#==============================================================================



    def validate_words_with_spaces(self, state, node, line, lang):
        """
        Checks a single line for disallowed whitespace.
        Here we assume that all language-independent whitespace-related tests have
        already been done on level 1, so we only check for words with spaces that
        are explicitly allowed in a given language.

        Parameters
        ----------
        node : udapi.core.node.Node object
            The node to be validated.
        line : int
            Number of the line where the node occurs in the file.
        lang : str
            Code of the main language of the corpus.
        """
        Incident.default_lineno = line
        Incident.default_level = 4
        Incident.default_testclass = 'Format'
        # List of permited words with spaces is language-specific.
        # The current token may be in a different language due to code switching.
        tospacedata = self.specs.get_tospace_for_language(lang)
        altlang = utils.get_alt_language(node)
        if altlang:
            lang = altlang
            tospacedata = self.specs.get_tospace_for_language(altlang)
        for column in ('FORM', 'LEMMA'):
            word = node.form if column == 'FORM' else node.lemma
            # Is there whitespace in the word?
            if utils.crex.ws.search(word):
                # Whitespace found. Does the word pass the regular expression that defines permitted words with spaces in this language?
                if tospacedata:
                    # For the purpose of this test, NO-BREAK SPACE is equal to SPACE.
                    string_to_test = re.sub(r'\xA0', ' ', word)
                    if not tospacedata[1].fullmatch(string_to_test):
                        Incident(
                            state=state,
                            nodeid=node.ord,
                            testid='invalid-word-with-space',
                            message=f"'{word}' in column {column} is not on the list of exceptions allowed to contain whitespace.",
                            explanation=outils.explain_tospace(lang)
                        ).confirm()
                else:
                    Incident(
                        state=state,
                        nodeid=node.ord,
                        testid='invalid-word-with-space',
                        message=f"'{word}' in column {column} is not on the list of exceptions allowed to contain whitespace.",
                        explanation=outils.explain_tospace(lang)
                    ).confirm()



    def validate_features_level4(self, state, node, line, lang):
        """
        Checks that a feature-value pair is listed as approved. Feature lists are
        language-specific. To disallow non-universal features, test on level 4 with
        language 'ud'.

        Parameters
        ----------
        node : udapi.core.node.Node object
            The node to be validated.
        line : int
            Number of the line where the node occurs in the file.
        lang : str
            Code of the main language of the corpus.
        """
        Incident.default_lineno = line
        Incident.default_level = 4
        Incident.default_testclass = 'Morpho'
        if str(node.feats) == '_':
            return True
        # List of permited features is language-specific.
        # The current token may be in a different language due to code switching.
        default_lang = lang
        default_featset = featset = self.specs.get_feats_for_language(lang)
        altlang = utils.get_alt_language(node)
        if altlang:
            lang = altlang
            featset = self.specs.get_feats_for_language(altlang)
        for f in node.feats:
            values = node.feats[f].split(',')
            for v in values:
                # Level 2 tested character properties and canonical order but not that the f-v pair is known.
                # Level 4 also checks whether the feature value is on the list.
                # If only universal feature-value pairs are allowed, test on level 4 with lang='ud'.
                # The feature Typo=Yes is the only feature allowed on a multi-word token line.
                # If it occurs there, it cannot be duplicated on the lines of the component words.
                if f == 'Typo' and state.mwt_typo_span_end and node.ord <= state.mwt_typo_span_end:
                    Incident(
                        state=state,
                        nodeid=node.ord,
                        testid='mwt-typo-repeated-at-word',
                        message="Feature Typo cannot occur at a word if it already occurred at the corresponding multi-word token."
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
                        Incident(
                            state=state,
                            nodeid=node.ord,
                            testid='feature-unknown',
                            message=f"Feature {f} is not documented for language [{effective_lang}] ('{utils.formtl(node)}').",
                            explanation=outils.explain_feats(effective_lang)
                        ).confirm()
                    else:
                        lfrecord = effective_featset[f]
                        if lfrecord['permitted'] == 0:
                            Incident(
                                state=state,
                                nodeid=node.ord,
                                testid='feature-not-permitted',
                                message=f"Feature {f} is not permitted in language [{effective_lang}] ('{utils.formtl(node)}').",
                                explanation=outils.explain_feats(effective_lang)
                            ).confirm()
                        else:
                            values = lfrecord['uvalues'] + lfrecord['lvalues'] + lfrecord['unused_uvalues'] + lfrecord['unused_lvalues']
                            if not v in values:
                                Incident(
                                    state=state,
                                    nodeid=node.ord,
                                    testid='feature-value-unknown',
                                    message=f"Value {v} is not documented for feature {f} in language [{effective_lang}] ('{utils.formtl(node)}').",
                                    explanation=outils.explain_feats(effective_lang)
                                ).confirm()
                            elif not node.upos in lfrecord['byupos']:
                                Incident(
                                    state=state,
                                    nodeid=node.ord,
                                    testid='feature-upos-not-permitted',
                                    message=f"Feature {f} is not permitted with UPOS {node.upos} in language [{effective_lang}] ('{utils.formtl(node)}').",
                                    explanation=outils.explain_feats(effective_lang)
                                ).confirm()
                            elif not v in lfrecord['byupos'][node.upos] or lfrecord['byupos'][node.upos][v]==0:
                                Incident(
                                    state=state,
                                    nodeid=node.ord,
                                    testid='feature-value-upos-not-permitted',
                                    message=f"Value {v} of feature {f} is not permitted with UPOS {node.upos} in language [{effective_lang}] ('{utils.formtl(node)}').",
                                    explanation=outils.explain_feats(effective_lang)
                                ).confirm()
        if state.mwt_typo_span_end and int(state.mwt_typo_span_end) <= int(node.ord):
            state.mwt_typo_span_end = None



    def OLD_validate_deprels(self, state, node, line):
        """
        Checks that a dependency relation label is listed as approved in the given
        language. As a language-specific test, this function generally belongs to
        level 4, but it can be also used on levels 2 and 3, in which case it will
        check only the main dependency type and ignore any subtypes.

        Parameters
        ----------
        node : udapi.core.node.Node object
            The node whose incoming relation will be validated.
        line : int
            Number of the line where the node occurs in the file.
        """
        Incident.default_lineno = line
        Incident.default_level = 4
        Incident.default_testclass = 'Syntax'
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
        mainlang = self.args.lang
        naltlang = utils.get_alt_language(node)
        # The basic relation should be tested on regular nodes but not on empty nodes.
        if not node.is_empty():
            paltlang = utils.get_alt_language(node.parent)
            main_deprelset = self.specs.get_deprel_for_language(mainlang)
            alt_deprelset = set()
            if naltlang != None and naltlang != mainlang and naltlang == paltlang:
                alt_deprelset = self.specs.get_deprel_for_language(naltlang)
            # Test only the universal part if testing at universal level.
            deprel = node.deprel
            if self.args.level < 4:
                deprel = node.udeprel
                Incident.default_level = 2
            if deprel not in main_deprelset and deprel not in alt_deprelset:
                Incident(
                    state=state,
                    nodeid=node.ord,
                    testid='unknown-deprel',
                    message=f"Unknown DEPREL label: '{deprel}'",
                    explanation=outils.explain_deprel(mainlang)
                ).confirm()
        # If there are enhanced dependencies, test their deprels, too.
        # We already know that the contents of DEPS is parsable (deps_list() was
        # first called from validate_id_references() and the head indices are OK).
        # The order of enhanced dependencies was already checked in validate_deps().
        Incident.default_testclass = 'Enhanced'
        if str(node.deps) != '_':
            main_edeprelset = self.specs.get_edeprel_for_language(mainlang)
            alt_edeprelset = self.specs.get_edeprel_for_language(naltlang)
            for edep in node.deps:
                parent = edep['parent']
                deprel = edep['deprel']
                paltlang = utils.get_alt_language(parent)
                if self.args.level < 4:
                    deprel = utils.lspec2ud(deprel)
                    Incident.default_level = 2
                if not (deprel in main_edeprelset or naltlang != None and naltlang != mainlang and naltlang == paltlang and deprel in alt_edeprelset):
                    Incident(
                        state=state,
                        nodeid=node.ord,
                        testid='unknown-edeprel',
                        message=f"Unknown enhanced relation type '{deprel}' in '{parent.ord}:{deprel}'",
                        explanation=outils.explain_edeprel(mainlang)
                    ).confirm()



#==============================================================================
# Level 5 tests. Annotation content vs. the guidelines, language-specific.
#==============================================================================



    def validate_auxiliary_verbs(self, state, node, line, lang):
        """
        Verifies that the UPOS tag AUX is used only with lemmas that are known to
        act as auxiliary verbs or particles in the given language.

        Parameters
        ----------
        node : udapi.core.node.Node object
            The node to be validated.
        line : int
            Number of the line where the node occurs in the file.
        lang : str
            Code of the main language of the corpus.
        """
        if node.upos == 'AUX' and node.lemma != '_':
            altlang = utils.get_alt_language(node)
            if altlang:
                lang = altlang
            auxlist = self.specs.get_aux_for_language(lang)
            if not auxlist or not node.lemma in auxlist:
                Incident(
                    state=state,
                    lineno=line,
                    nodeid=node.ord,
                    level=5,
                    testclass='Morpho',
                    testid='aux-lemma',
                    message=f"'{node.lemma}' is not an auxiliary in language [{lang}]",
                    explanation=outils.explain_aux(lang)
                ).confirm()



    def validate_copula_lemmas(self, state, node, line, lang):
        """
        Verifies that the relation cop is used only with lemmas that are known to
        act as copulas in the given language.

        Parameters
        ----------
        node : udapi.core.node.Node object
            The node to be validated.
        line : int
            Number of the line where the node occurs in the file.
        lang : str
            Code of the main language of the corpus.
        """
        if node.udeprel == 'cop' and node.lemma != '_':
            altlang = utils.get_alt_language(node)
            if altlang:
                lang = altlang
            coplist = self.specs.get_cop_for_language(lang)
            if not coplist or not node.lemma in coplist:
                Incident(
                    state=state,
                    lineno=line,
                    nodeid=node.ord,
                    level=5,
                    testclass='Syntax',
                    testid='cop-lemma',
                    message=f"'{node.lemma}' is not a copula in language [{lang}]",
                    explanation=outils.explain_cop(lang)
                ).confirm()



#==============================================================================
# Level 6 tests for annotation of coreference and named entities. This is
# tested on demand only, as the requirements are not compulsory for UD
# releases.
#==============================================================================



    def validate_misc_entity(self, state, comments, sentence):
        """
        Optionally checks the well-formedness of the MISC attributes that pertain
        to coreference and named entities.
        """
        Incident.default_level = 6
        Incident.default_testclass = 'Coref'
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
                        Incident(
                            state=state,
                            testid='global-entity-mismatch',
                            message=f"New declaration of global.Entity '{global_entity_match.group(1)}' does not match the first declaration '{state.global_entity_attribute_string}' on line {state.seen_global_entity}."
                        ).confirm()
                else:
                    state.seen_global_entity = state.comment_start_line + iline
                    state.global_entity_attribute_string = global_entity_match.group(1)
                    if not re.match(r"^[a-z]+(-[a-z]+)*$", state.global_entity_attribute_string):
                        Incident(
                            state=state,
                            testid='spurious-global-entity',
                            message=f"Cannot parse global.Entity attribute declaration '{state.global_entity_attribute_string}'."
                        ).confirm()
                    else:
                        global_entity_attributes = state.global_entity_attribute_string.split('-')
                        if not 'eid' in global_entity_attributes:
                            Incident(
                                state=state,
                                testid='spurious-global-entity',
                                message=f"Global.Entity attribute declaration '{state.global_entity_attribute_string}' does not include 'eid'."
                            ).confirm()
                        elif global_entity_attributes[0] != 'eid':
                            Incident(
                                state=state,
                                testid='spurious-global-entity',
                                message=f"Attribute 'eid' must come first in global.Entity attribute declaration '{state.global_entity_attribute_string}'."
                            ).confirm()
                        if not 'etype' in global_entity_attributes:
                            Incident(
                                state=state,
                                testid='spurious-global-entity',
                                message=f"Global.Entity attribute declaration '{state.global_entity_attribute_string}' does not include 'etype'."
                            ).confirm()
                        elif global_entity_attributes[1] != 'etype':
                            Incident(
                                state=state,
                                testid='spurious-global-entity',
                                message=f"Attribute 'etype' must come second in global.Entity attribute declaration '{state.global_entity_attribute_string}'."
                            ).confirm()
                        if not 'head' in global_entity_attributes:
                            Incident(
                                state=state,
                                testid='spurious-global-entity',
                                message=f"Global.Entity attribute declaration '{state.global_entity_attribute_string}' does not include 'head'."
                            ).confirm()
                        elif global_entity_attributes[2] != 'head':
                            Incident(
                                state=state,
                                testid='spurious-global-entity',
                                message=f"Attribute 'head' must come third in global.Entity attribute declaration '{state.global_entity_attribute_string}'."
                            ).confirm()
                        if 'other' in global_entity_attributes and global_entity_attributes[3] != 'other':
                            Incident(
                                state=state,
                                testid='spurious-global-entity',
                                message=f"Attribute 'other', if present, must come fourth in global.Entity attribute declaration '{state.global_entity_attribute_string}'."
                            ).confirm()
                        # Fill the global dictionary that maps attribute names to list indices.
                        i = 0
                        for a in global_entity_attributes:
                            if a in state.entity_attribute_index:
                                Incident(
                                    state=state,
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
                Incident(
                    state=state,
                    testid='entity-mwt',
                    message="Entity or coreference annotation must not occur at a multiword-token line."
                ).confirm()
                continue
            if len(entity)>1:
                Incident(
                    state=state,
                    testid='multiple-entity-statements',
                    message=f"There can be at most one 'Entity=' statement in MISC but we have {str(misc)}."
                ).confirm()
                continue
            if len(bridge)>1:
                Incident(
                    state=state,
                    testid='multiple-bridge-statements',
                    message=f"There can be at most one 'Bridge=' statement in MISC but we have {str(misc)}."
                ).confirm()
                continue
            if len(splitante)>1:
                Incident(
                    state=state,
                    testid='multiple-splitante-statements',
                    message=f"There can be at most one 'SplitAnte=' statement in MISC but we have {str(misc)}."
                ).confirm()
                continue
            if len(bridge)>0 and len(entity)==0:
                Incident(
                    state=state,
                    testid='bridge-without-entity',
                    message=f"The 'Bridge=' statement can only occur together with 'Entity=' in MISC but we have {str(misc)}."
                ).confirm()
                continue
            if len(splitante)>0 and len(entity)==0:
                Incident(
                    state=state,
                    testid='splitante-without-entity',
                    message=f"The 'SplitAnte=' statement can only occur together with 'Entity=' in MISC but we have {str(misc)}."
                ).confirm()
                continue
            # There is at most one Entity (and only if it is there, there may be also one Bridge and/or one SplitAnte).
            if len(entity)>0:
                if not state.seen_global_entity:
                    Incident(
                        state=state,
                        testid='entity-without-global-entity',
                        message="No global.Entity comment was found before the first 'Entity' in MISC."
                    ).confirm()
                    continue
                match = re.match(r"^Entity=((?:\([^( )]+(?:-[^( )]+)*\)?|[^( )]+\))+)$", entity[0])
                if not match:
                    Incident(
                        state=state,
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
                        Incident(
                            state=state,
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
                                Incident(
                                    state=state,
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
                                Incident(
                                    state=state,
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
                                Incident(
                                    state=state,
                                    testid='spurious-entity-id',
                                    message=f"Discontinuous mention must have at least two parts but it has one in '{beid}'."
                                ).confirm()
                            if ipart > npart:
                                Incident(
                                    state=state,
                                    testid='spurious-entity-id',
                                    message=f"Entity id '{beid}' of discontinuous mention says the current part is higher than total number of parts."
                                ).confirm()
                        else:
                            if re.match(r"[\[\]]", beid):
                                Incident(
                                    state=state,
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
                                            Incident(
                                                state=state,
                                                testid='misplaced-mention-part',
                                                message=f"Unexpected part of discontinuous mention '{beid}': last part was '{discontinuous_mention['last_ipart']}/{discontinuous_mention['npart']}' on line {discontinuous_mention['last_part_line']}."
                                            ).confirm()
                                            # We will update last_ipart at closing bracket, i.e., after the current part has been entirely processed.
                                            # Otherwise nested discontinuous mentions might wrongly assess where they belong.
                                        elif attrstring_to_match != discontinuous_mention['attributes']:
                                            Incident(
                                                state=state,
                                                testid='mention-attribute-mismatch',
                                                message=f"Attribute mismatch of discontinuous mention: current part has '{attrstring_to_match}', first part '{discontinuous_mention['attributes']}' was at line {discontinuous_mention['first_part_line']}."
                                            ).confirm()
                                    else:
                                        Incident(
                                            state=state,
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
                                Incident(
                                    state=state,
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
                                    Incident(
                                        state=state,
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
                                    Incident(
                                        state=state,
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
                                    Incident(
                                        state=state,
                                        testid='entity-type-mismatch',
                                        message=f"Entity '{eid}' cannot have type '{etype}' that does not match '{state.entity_types[eid][0]}' from the first mention on line {state.entity_types[eid][2]}."
                                    ).confirm()
                                # All mentions of one entity (cluster) must have the same identity (Wikipedia link or similar).
                                if identity != state.entity_types[eid][1]:
                                    Incident(
                                        state=state,
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
                                Incident(
                                    state=state,
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
                                    Incident(
                                        state=state,
                                        testclass='Warning',
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
                                    Incident(
                                        state=state,
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
                                    Incident(
                                        state=state,
                                        testclass='Internal',
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
                                    Incident(
                                        state=state,
                                        testid='mention-head-out-of-range',
                                        message=f"Entity mention head was specified as {head} on line {opening_line} but the mention has only {mention_length} nodes."
                                    ).confirm()
                                # Check that no two mentions have identical spans (only if this is the last part of a mention).
                                ending_mention_key = str(opening_line)+str(mention_span)
                                if ending_mention_key in ending_mentions:
                                    Incident(
                                        state=state,
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
                                                Incident(
                                                    state=state,
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
                                Incident(
                                    state=state,
                                    testid='spurious-entity-statement',
                                    message=f"If there are no closing entity brackets, single-node entity must follow all opening entity brackets in '{entity[0]}'."
                                ).confirm()
                            if seen0 and seen2:
                                Incident(
                                    state=state,
                                    testid='spurious-entity-statement',
                                    message=f"Single-node entity must either precede all closing entity brackets or follow all opening entity brackets in '{entity[0]}'."
                                ).confirm()
                            seen0 = True
                            seen2 = False
                            opening_bracket()
                        elif b==2:
                            if seen1 and not seen0:
                                Incident(
                                    state=state,
                                    testid='spurious-entity-statement',
                                    message=f"If there are no opening entity brackets, single-node entity must precede all closing entity brackets in '{entity[0]}'."
                                ).confirm()
                            seen2 = True
                            opening_bracket()
                            closing_bracket()
                        else: # b==1
                            if seen0:
                                Incident(
                                    state=state,
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
                        Incident(
                            state=state,
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
                                    Incident(
                                        state=state,
                                        testid='spurious-bridge-relation',
                                        message=f"Bridge must not point from an entity to itself: '{b}'."
                                    ).confirm()
                                if not tgteid in starting_mentions:
                                    Incident(
                                        state=state,
                                        testid='misplaced-bridge-statement',
                                        message=f"Bridge relation '{b}' must be annotated at the beginning of a mention of entity '{tgteid}'."
                                    ).confirm()
                                if bridgekey in srctgt:
                                    Incident(
                                        state=state,
                                        testid='repeated-bridge-relation',
                                        message=f"Bridge relation '{bridgekey}' must not be repeated in '{b}'."
                                    ).confirm()
                                else:
                                    srctgt[bridgekey] = True
                                # Check in the global dictionary whether this relation has been specified at another mention.
                                if bridgekey in state.entity_bridge_relations:
                                    if relation != state.entity_bridge_relations[bridgekey]['relation']:
                                        Incident(
                                            state=state,
                                            testid='bridge-relation-mismatch',
                                            message=f"Bridge relation '{b}' type does not match '{state.entity_bridge_relations[bridgekey]['relation']}' specified earlier on line {state.entity_bridge_relations[bridgekey]['line']}."
                                        ).confirm()
                                else:
                                    state.entity_bridge_relations[bridgekey] = {'relation': relation, 'line': state.sentence_line+iline}
                if len(splitante) > 0:
                    match = re.match(r"^SplitAnte=([^(< :>)]+<[^(< :>)]+(,[^(< :>)]+<[^(< :>)]+)*)$", splitante[0])
                    if not match:
                        Incident(
                            state=state,
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
                                    Incident(
                                        state=state,
                                        testid='spurious-splitante-relation',
                                        message=f"SplitAnte must not point from an entity to itself: '{srceid}<{tgteid}'."
                                    ).confirm()
                                elif not tgteid in starting_mentions:
                                    Incident(
                                        state=state,
                                        testid='misplaced-splitante-statement',
                                        message=f"SplitAnte relation '{a}' must be annotated at the beginning of a mention of entity '{tgteid}'."
                                    ).confirm()
                                if srceid+'<'+tgteid in srctgt:
                                    str_antecedents = ','.join(antecedents)
                                    Incident(
                                        state=state,
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
                                Incident(
                                    state=state,
                                    testid='only-one-split-antecedent',
                                    message=f"SplitAnte statement '{str_antecedents}' must specify at least two antecedents for entity '{tgteid}'."
                                ).confirm()
                            # Check in the global dictionary whether this relation has been specified at another mention.
                            tgtante[tgteid].sort()
                            if tgteid in state.entity_split_antecedents:
                                if tgtante[tgteid] != state.entity_split_antecedents[tgteid]['antecedents']:
                                    Incident(
                                        state=state,
                                        testid='split-antecedent-mismatch',
                                        message=f"Split antecedent of entity '{tgteid}' does not match '{state.entity_split_antecedents[tgteid]['antecedents']}' specified earlier on line {state.entity_split_antecedents[tgteid]['line']}."
                                    ).confirm()
                            else:
                                state.entity_split_antecedents[tgteid] = {'antecedents': str(tgtante[tgteid]), 'line': state.sentence_line+iline}
            iline += 1
        if len(state.open_entity_mentions)>0:
            Incident(
                state=state,
                testid='cross-sentence-mention',
                message=f"Entity mentions must not cross sentence boundaries; still open at sentence end: {str(state.open_entity_mentions)}."
            ).confirm()
            # Close the mentions forcibly. Otherwise one omitted closing bracket would cause the error messages to to explode because the words would be collected from the remainder of the file.
            state.open_entity_mentions = []
        if len(state.open_discontinuous_mentions)>0:
            Incident(
                state=state,
                testid='cross-sentence-mention',
                message=f"Entity mentions must not cross sentence boundaries; still open at sentence end: {str(state.open_discontinuous_mentions)}."
            ).confirm()
            # Close the mentions forcibly. Otherwise one omission would cause the error messages to to explode because the words would be collected from the remainder of the file.
            state.open_discontinuous_mentions = {}
        # Since we only test mentions within one sentence at present, we do not have to carry all mention spans until the end of the corpus.
        for eid in state.entity_mention_spans:
            if sentid in state.entity_mention_spans[eid]:
                state.entity_mention_spans[eid].pop(sentid)



#==============================================================================
# Main part.
#==============================================================================
    # TODO: put in utils or similar
    def build_tree_udapi(self, lines):
        root = self.conllu_reader.read_tree_from_lines(lines)
        return root

    def validate_file(self, state, inp):
        """
        The main entry point for all validation tests applied to one input file.
        It reads sentences from the input stream one by one, each sentence is
        immediately tested.

        Parameters
        ----------
        inp : open file handle
            The CoNLL-U-formatted input stream.
        """
        for all_lines, comments, sentence in self.OLD_next_sentence(state, inp):
            linenos = utils.get_line_numbers_for_ids(state, sentence)
            # The individual lines were validated already in next_sentence().
            # What follows is tests that need to see the whole tree.
            # Note that low-level errors such as wrong number of columns would be
            # reported in next_sentence() but then the lines would be thrown away
            # and no tree lines would be yielded—meaning that we will not encounter
            # such a mess here.
            idseqok = self.OLD_validate_id_sequence(state, sentence) # level 1
            self.OLD_validate_token_ranges(state, sentence) # level 1
            # TODO: config file so that levels are not checked here
            if self.args.level > 1:
                idrefok = idseqok and self.OLD_validate_id_references(state, sentence) # level 2
                if not idrefok:
                    continue
                treeok = self.validate_tree(state, sentence) # level 2 test: tree is single-rooted, connected, cycle-free
                if not treeok:
                    continue
                # Tests of individual nodes that operate on pre-Udapi data structures.
                # Some of them (bad feature format) may lead to skipping Udapi completely.
                colssafe = True
                line = state.sentence_line - 1
                for cols in sentence: # TODO: cols->line
                    line += 1
                    # Multiword tokens and empty nodes can or must have certain fields empty.
                    if utils.is_multiword_token(cols):
                        self.OLD_validate_mwt_empty_vals(state, cols, line)
                    if utils.is_empty_node(cols): # TODO: elif?
                        self.OLD_validate_empty_node_empty_vals(state, cols, line) # level 2
                    if utils.is_word(cols) or utils.is_empty_node(cols): # TODO: elif?
                        self.OLD_validate_character_constraints(state, cols, line) # level 2
                        self.OLD_validate_upos(state, cols, line) # level 2
                        colssafe = colssafe and self.OLD_validate_features_level2(state, cols, line) # level 2 (level 4 tests will be called later)
                    self.OLD_validate_deps(state, cols, line) # level 2; must operate on pre-Udapi DEPS (to see order of relations)
                    self.OLD_validate_misc(state, cols, line) # level 2; must operate on pre-Udapi MISC
                if not colssafe:
                    continue
                # If we successfully passed all the tests above, it is probably
                # safe to give the lines to Udapi and ask it to build the tree data
                # structure for us.
                tree = self.build_tree_udapi(all_lines)
                self.validate_sent_id(state, comments, self.args.lang) # level 2
                self.validate_text_meta(state, comments, sentence) # level 2
                # Test that enhanced graphs exist either for all sentences or for
                # none. As a side effect, get line numbers for all nodes including
                # empty ones (here linenos is a dict indexed by cols[ID], i.e., a string).
                # These line numbers are returned in any case, even if there are no
                # enhanced dependencies, hence we can rely on them even with basic
                # trees.
                self.OLD_validate_deps_all_or_none(state, sentence)
                # Tests of individual nodes with Udapi.
                nodes = tree.descendants_and_empty
                for node in nodes:
                    line = linenos[str(node.ord)]
                    self.OLD_validate_deprels(state, node, line) # level 2 and 4
                    self.validate_root(state, node, line) # level 2: deprel root <=> head 0
                    if self.args.level > 2:
                        self.validate_enhanced_orphan(state, node, line) # level 3
                        if self.args.level > 3:
                            # To disallow words with spaces everywhere, use --lang ud.
                            self.validate_words_with_spaces(state, node, line, self.args.lang) # level 4
                            self.validate_features_level4(state, node, line, self.args.lang) # level 4
                            if self.args.level > 4:
                                self.validate_auxiliary_verbs(state, node, line, self.args.lang) # level 5
                                self.validate_copula_lemmas(state, node, line, self.args.lang) # level 5
                # Tests on whole trees and enhanced graphs.
                if self.args.level > 2:
                    self.validate_annotation(state, tree, linenos) # level 3
                    self.validate_egraph_connected(state, nodes, linenos)
                if self.args.check_coref:
                    self.validate_misc_entity(state, comments, sentence) # optional for CorefUD treebanks
        self.OLD_validate_newlines(state, inp) # level 1



    def validate_end(self, state):
        """
        Final tests after processing the entire treebank (possibly multiple files).
        """
        # After reading the entire treebank (perhaps multiple files), check whether
        # the DEPS annotation was not a mere copy of the basic trees.
        if self.args.level>2 and state.seen_enhanced_graph and not state.seen_enhancement:
            Incident(
                state=state,
                level=3,
                testclass='Enhanced',
                testid='edeps-identical-to-basic-trees',
                message="Enhanced graphs are copies of basic trees in the entire dataset. This can happen for some simple sentences where there is nothing to enhance, but not for all sentences. If none of the enhancements from the guidelines (https://universaldependencies.org/u/overview/enhanced-syntax.html) are annotated, the DEPS should be left unspecified"
            ).confirm()


    def validate_files(self, filenames):
        state = State()
        try:
            for fname in filenames:
                state.current_file_name = fname
                if fname == '-':
                    # Set PYTHONIOENCODING=utf-8 before starting Python.
                    # See https://docs.python.org/3/using/cmdline.html#envvar-PYTHONIOENCODING
                    # Otherwise ANSI will be read in Windows and
                    # locale-dependent encoding will be used elsewhere.
                    self.validate_file(state, sys.stdin)
                else:
                    with io.open(fname, 'r', encoding='utf-8') as inp:
                        self.validate_file(state, inp)
            self.validate_end(state)
        except:
            Incident(
                state=state,
                level=0,
                testclass='Internal',
                testid='exception',
                message="Exception caught!"
            ).confirm()
            # If the output is used in an HTML page, it must be properly escaped
            # because the traceback can contain e.g. "<module>". However, escaping
            # is beyond the goal of validation, which can be also run in a console.
            traceback.print_exc()
        return state


#==============================================================================
# Argument processing.
#==============================================================================


def build_argparse():
    opt_parser = argparse.ArgumentParser(description="CoNLL-U validation script. Python 3 is needed to run it!")

    io_group = opt_parser.add_argument_group("Input / output options")
    io_group.add_argument('--quiet',
                          dest="quiet", action="store_true", default=False,
                          help="""Do not print any error messages.
                          Exit with 0 on pass, non-zero on fail.""")
    io_group.add_argument('--max-err',
                          action="store", type=int, default=20,
                          help="""How many errors to output before exiting? 0 for all.
                          Default: %(default)d.""")
    io_group.add_argument('input',
                          nargs='*',
                          help="""Input file name(s), or "-" or nothing for standard input.""")

    list_group = opt_parser.add_argument_group("Tag sets", "Options relevant to checking tag sets.")
    list_group.add_argument("--lang",
                            action="store", required=True, default=None,
                            help="""Which langauge are we checking?
                            If you specify this (as a two-letter code), the tags will be checked
                            using the language-specific files in the
                            data/directory of the validator.""")
    list_group.add_argument("--level",
                            action="store", type=int, default=5, dest="level",
                            help="""Level 1: Test only CoNLL-U backbone.
                            Level 2: UD format.
                            Level 3: UD contents.
                            Level 4: Language-specific labels.
                            Level 5: Language-specific contents.""")

    tree_group = opt_parser.add_argument_group("Tree constraints",
                                               "Options for checking the validity of the tree.")
    tree_group.add_argument("--multiple-roots",
                            action="store_false", default=True, dest="single_root",
                            help="""Allow trees with several root words
                            (single root required by default).""")

    coref_group = opt_parser.add_argument_group("Coreference / entity constraints",
                                                "Options for checking coreference and entity annotation.")
    coref_group.add_argument('--coref',
                             action='store_true', default=False, dest='check_coref',
                             help='Test coreference and entity-related annotation in MISC.')
    return opt_parser

def parse_args():
    opt_parser = build_argparse()
    args = opt_parser.parse_args() #Parsed command-line arguments

    # Level of validation
    if args.level < 1:
        print(f'Option --level must not be less than 1; changing from {args.level} to 1',
              file=sys.stderr)
        args.level = 1
    # No language-specific tests for levels 1-3
    # Anyways, any Feature=Value pair should be allowed at level 3 (because it may be language-specific),
    # and any word form or lemma can contain spaces (because language-specific guidelines may allow it).
    # We can also test language 'ud' on level 4; then it will require that no language-specific features are present.
    if args.level < 4:
        args.lang = 'ud'
    if args.input == []:
        args.input.append('-')
    return args

def main():
    args = parse_args()
    validator = Validator(args)
    state = validator.validate_files(args.input)

    # Summarize the warnings and errors.
    passed = True
    nerror = 0
    if state.error_counter:
        for k, v in sorted(state.error_counter.items()):
            if k == 'Warning':
                errors = 'Warnings'
            else:
                errors = k+' errors'
                nerror += v
                passed = False
            if not args.quiet:
                print(f'{errors}: {v}', file=sys.stderr)
    # Print the final verdict and exit.
    if passed:
        if not args.quiet:
            print('*** PASSED ***', file=sys.stderr)
        return 0
    else:
        if not args.quiet:
            print(f'*** FAILED *** with {nerror} errors', file=sys.stderr)
        return 1

if __name__=="__main__":
    errcode = main()
    sys.exit(errcode)
