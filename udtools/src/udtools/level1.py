#! /usr/bin/env python3
# Original code (2015) by Filip Ginter and Sampo Pyysalo.
# DZ 2018-11-04: Porting the validator to Python 3.
# DZ: Many subsequent changes. See the git history.
import unicodedata
# Allow using this module from the root folder of tools even if it is not
# installed as a package: use the relative path validator/src/validator for
# submodules. If the path is not available, try the standard qualification,
# assuming that the user has installed udtools from PyPI and then called
# from udtools import Validator.
try:
    import udtools.src.udtools.utils as utils
    from udtools.src.udtools.incident import Incident, Error, TestClass
except ModuleNotFoundError:
    import udtools.utils as utils
    from udtools.incident import Incident, Error, TestClass



# Constants for the column indices
COLCOUNT=10
ID,FORM,LEMMA,UPOS,XPOS,FEATS,HEAD,DEPREL,DEPS,MISC=range(COLCOUNT)
COLNAMES='ID,FORM,LEMMA,UPOS,XPOS,FEATS,HEAD,DEPREL,DEPS,MISC'.split(',')



class Level1:
#==============================================================================
# Level 1 tests. Only CoNLL-U backbone. Values can be empty or non-UD.
#==============================================================================


    def check_sentence_lines(self, state):
        """
        Low-level tests of a block of input lines that should represent one
        sentence. If we are validating a file or treebank, the block was
        probably obtained by reading lines from the file until the next empty
        line. But it is also possible that the caller is an annotation tool,
        which wants to validate one sentence in isolation.

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
        current_line : int
            The number of the most recently read line from the input file
            (1-based).

        Writes to state
        ----------------
        comment_start_line : int
            The line number (relative to input file, 1-based) of the first line
            in the current sentence, including comments if any.
        sentence_line : int
            The line number (relative to input file, 1-based) of the first
            node/token line in the current sentence.

        Incidents
        ---------
        misplaced-comment
        pseudo-empty-line
        extra-empty-line
        empty-sentence
        invalid-line
        missing-empty-line
        + those issued by check_unicode_normalization()

        Returns
        -------
        ok : bool
            Is it OK to run subsequent checks? It can be OK even after some
            less severe errors.
        """
        Incident.default_level = 1
        Incident.default_testclass = TestClass.FORMAT
        # When we arrive here, state.current_line points to the last line of the
        # sentence, that is, the terminating empty line (if the input is valid).
        lines = state.current_lines
        n_lines = len(lines)
        state.comment_start_line = state.current_line - n_lines + 1
        state.sentence_line = state.comment_start_line # temporarily, until we find the first token
        seen_non_comment = False # once we see non-comment, no further comments allowed
        seen_token_node = False # at least one such line per sentence required
        last_line_is_empty = False
        ok = True # is it ok to run subsequent tests? It can be ok even after some less severe errors.
        for i in range(n_lines):
            lineno = state.comment_start_line + i
            line = lines[i]
            self.check_unicode_normalization(state, line, lineno)
            # Comment lines.
            if line and line[0] == '#':
                # We will really validate sentence ids later. But now we want to remember
                # everything that looks like a sentence id and use it in the error messages.
                # Line numbers themselves may not be sufficient if we are reading multiple
                # files from a pipe.
                match = utils.crex.sentid.fullmatch(line)
                if match:
                    state.sentence_id = match.group(1)
                if seen_non_comment:
                    Error(
                        state=state, config=self.incfg, lineno=lineno,
                        testid='misplaced-comment',
                        message='Spurious comment line. Comments are only allowed before a sentence.'
                    ).confirm()
                    ok = False
            else:
                if not seen_non_comment:
                    state.sentence_line = state.comment_start_line + i
                seen_non_comment = True
                # Token/node lines.
                if line and line[0].isdigit():
                    seen_token_node = True
                # Empty line (end of sentence).
                elif not line or utils.is_whitespace(line):
                    # Lines consisting of space/tab characters are non-empty and invalid,
                    # so we will report an error but otherwise we will treat them as empty
                    # lines to prevent confusing subsequent errors.
                    if utils.is_whitespace(line):
                        Error(
                            state=state, config=self.incfg, lineno=lineno,
                            testid='pseudo-empty-line',
                            message='Spurious line that appears empty but is not; there are whitespace characters.'
                        ).confirm()
                    # If the input lines were read from the input stream, there
                    # will be at most one empty line and it will be the last line
                    # (because it triggered returning a sentence). However, the
                    # list of lines may come from other sources (any user can
                    # ask for validation of their list of lines) and then we may
                    # encounter empty lines anywhere.
                    if i != n_lines-1:
                        Error(
                            state=state, config=self.incfg, lineno=lineno,
                            testid='extra-empty-line',
                            message='Spurious empty line that is not the last line of a sentence.'
                        ).confirm()
                        ok = False
                    else:
                        last_line_is_empty = True
                        if not seen_token_node:
                            Error(
                                state=state, config=self.incfg, lineno=lineno,
                                testid='empty-sentence',
                                message='Sentence must not be empty. Only one empty line is expected after every sentence.'
                            ).confirm()
                            ok = False
                # A line which is neither a comment nor a token/word, nor empty. That's bad!
                else:
                    Error(
                        state=state, config=self.incfg, lineno=lineno,
                        testid='invalid-line',
                        message=f"Spurious line: '{line}'. All non-empty lines should start with a digit or the # character."
                    ).confirm()
                    ok = False
        # If the last line is not empty (e.g. because the file ended prematurely),
        # it is an error.
        if not last_line_is_empty:
            Error(
                state=state, config=self.incfg, lineno=state.current_line,
                testid='missing-empty-line',
                message='Missing empty line after the sentence.'
            ).confirm()
            ok = seen_token_node
        return ok


    def check_sentence_columns(self, state):
        """
        Low-level tests of the token/node lines of one sentence. The lines
        should have been already checked by check_sentence_lines() and all
        should start with a digit. We will split them to columns (cells),
        check that there is the expected number of columns and that they are
        not empty.

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
        comment_start_line : int
            The line number (relative to input file, 1-based) of the first line
            in the current sentence, including comments if any.
        sentence_line : int
            The line number (relative to input file, 1-based) of the first
            node/token line in the current sentence.

        Writes to state
        ----------------
        current_token_node_table : list(list(str))
            The list of multiword token lines / regular node lines / empty node
            lines, each split to fields (columns).

        Incidents
        ---------
        number-of-columns
        + those issued by check_whitespace()

        Returns
        -------
        ok : bool
            Is it OK to run subsequent checks? It can be OK even after some
            less severe errors.
        """
        Incident.default_level = 1
        Incident.default_testclass = TestClass.FORMAT
        n_comment_lines = state.sentence_line-state.comment_start_line
        n_lines = len(state.current_lines)
        # Normally we should exclude the last line because it is the empty line
        # terminating the sentence. But if the empty line is missing (which is
        # an error that we reported elsewhere), we must keep the last line.
        range_end = n_lines-1 if (not state.current_lines[-1] or utils.is_whitespace(state.current_lines[-1])) else n_lines
        token_lines = state.current_lines[n_comment_lines:range_end]
        n_token_lines = len(token_lines)
        token_lines_fields = [] # List of token/word lines of the current sentence, converted from string to list of fields.
        ok = True # is it ok to run subsequent tests? It can be ok even after some less severe errors.
        for i in range(n_token_lines):
            lineno = state.sentence_line + i
            line = token_lines[i]
            cols = line.split("\t")
            token_lines_fields.append(cols)
            # If there is an unexpected number of columns, do not test their contents.
            # Maybe the contents belongs to a different column. And we could see
            # an exception if a column value is missing.
            if len(cols) == COLCOUNT:
                # Low-level tests, mostly universal constraints on whitespace in fields, also format of the ID field.
                self.check_whitespace(state, cols, lineno)
            else:
                Error(
                    state=state, config=self.incfg, lineno=lineno,
                    testid='number-of-columns',
                    message=f'The line has {len(cols)} columns but {COLCOUNT} are expected.'
                ).confirm()
                ok = False
        state.current_token_node_table = token_lines_fields
        return ok



#------------------------------------------------------------------------------
# Level 1 tests applicable to a single line independently of the others.
#------------------------------------------------------------------------------



    def check_unicode_normalization(self, state, text, lineno):
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

        Incidents
        ---------
        unicode-normalization
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
            Error(
                state=state, config=self.incfg, lineno=lineno,
                level=1,
                testclass=TestClass.UNICODE,
                testid='unicode-normalization',
                message=testmessage,
                explanation=f"This error usually does not mean that {inpfirst} is an invalid character. Usually it means that this is a base character followed by combining diacritics, and you should replace them by a single combined character.{explanation_second} You can fix normalization errors using the normalize_unicode.pl script from the tools repository."
            ).confirm()



    def check_whitespace(self, state, cols, lineno):
        """
        Checks that columns are not empty and do not contain whitespace characters
        except for patterns that could be allowed at level 4. Applies to all types
        of TAB-containing lines: nodes / words, mwt ranges, empty nodes.

        Parameters
        ----------
        cols : list
            The values of the columns on the current node / token line.

        Incidents
        ---------
        invalid-whitespace-mwt
        invalid-whitespace
        empty-column
        leading-whitespace
        trailing-whitespace
        repeated-whitespace
        """
        Incident.default_level = 1
        Incident.default_testclass = TestClass.FORMAT
        Incident.default_lineno = lineno
        # Some whitespace may be permitted in FORM, LEMMA and MISC but not elsewhere.
        # Multi-word tokens may have whitespaces in MISC but not in FORM or LEMMA.
        # If it contains a space, it does not make sense to treat it as a MWT.
        ismwt = utils.is_multiword_token(cols)
        for col_idx in range(COLCOUNT):
            if col_idx >= len(cols):
                break # this has been already reported in next_sentence()
            if ismwt and col_idx in (FORM, LEMMA) and utils.crex.ws.search(cols[col_idx]):
                Error(
                    state=state, config=self.incfg,
                    testid='invalid-whitespace-mwt',
                    message=f"White space not allowed in multi-word token '{cols[col_idx]}'. If it contains a space, it is not a single surface token."
                ).confirm()
            # These columns must not have whitespace.
            elif col_idx in (ID, UPOS, XPOS, FEATS, HEAD, DEPREL, DEPS) and utils.crex.ws.search(cols[col_idx]):
                Error(
                    state=state, config=self.incfg,
                    testid='invalid-whitespace',
                    message=f"White space not allowed in column {COLNAMES[col_idx]}: '{cols[col_idx]}'."
                ).confirm()
            # Only perform the following tests if we have not found and reported a space above.
            else:
                # Must never be empty
                if not cols[col_idx]:
                    Error(
                        state=state, config=self.incfg,
                        testid='empty-column',
                        message=f"Empty value in column {COLNAMES[col_idx]}: '{cols[col_idx]}'."
                    ).confirm()
                else:
                    # Must never have leading/trailing/repeated whitespace.
                    # This will be only reported for columns that allow whitespace in general.
                    if cols[col_idx][0].isspace():
                        Error(
                            state=state, config=self.incfg,
                            testid='leading-whitespace',
                            message=f"Leading whitespace not allowed in column {COLNAMES[col_idx]}: '{cols[col_idx]}'."
                        ).confirm()
                    if cols[col_idx][-1].isspace():
                        Error(
                            state=state, config=self.incfg,
                            testid='trailing-whitespace',
                            message=f"Trailing whitespace not allowed in column {COLNAMES[col_idx]}: '{cols[col_idx]}'."
                        ).confirm()
                    # Must never contain two consecutive whitespace characters
                    if utils.crex.ws2.search(cols[col_idx]):
                        Error(
                            state=state, config=self.incfg,
                            testid='repeated-whitespace',
                            message=f"Two or more consecutive whitespace characters not allowed in column {COLNAMES[col_idx]}: '{cols[col_idx]}'."
                        ).confirm()



#------------------------------------------------------------------------------
# Level 1 tests applicable to the whole sentence.
#------------------------------------------------------------------------------



    def check_id_sequence(self, state):
        """
        Validates that the ID sequence is correctly formed.
        Besides reporting the errors, it also returns False to the caller so it can
        avoid building a tree from corrupt IDs.

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
        invalid-word-id
        invalid-word-interval
        misplaced-word-interval
        misplaced-empty-node
        word-id-sequence
        reversed-word-interval
        word-interval-out

        Returns
        -------
        ok : bool
            Is it OK to run subsequent checks? It can be OK even after some
            less severe errors.
        """
        ok = True
        Incident.default_level = 1
        Incident.default_testclass = TestClass.FORMAT
        words=[]
        tokens=[]
        current_word_id, next_empty_id = 0, 1
        for i in range(len(state.current_token_node_table)):
            lineno = state.sentence_line + i
            cols = state.current_token_node_table[i]
            # Check for the format of the ID value. (ID must not be empty.)
            if not (utils.is_word(cols) or utils.is_empty_node(cols) or utils.is_multiword_token(cols)):
                Error(
                    state=state, config=self.incfg, lineno=lineno,
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
                    tokens.append((t_id, t_id, lineno)) # nope - let's make a default interval for it
            elif utils.is_multiword_token(cols):
                match = utils.crex.mwtid.fullmatch(cols[ID]) # Check the interval against the regex
                if not match: # This should not happen. The function utils.is_multiword_token() would then not return True.
                    Error(
                        state=state, config=self.incfg, lineno=lineno,
                        testid='invalid-word-interval',
                        message=f"Spurious word interval definition: '{cols[ID]}'."
                    ).confirm()
                    ok = False
                    continue
                beg, end = int(match.group(1)), int(match.group(2))
                if not ((not words and beg >= 1) or (words and beg >= words[-1] + 1)):
                    Error(
                        state=state, config=self.incfg, lineno=lineno,
                        testid='misplaced-word-interval',
                        message='Multiword range not before its first word.'
                    ).confirm()
                    ok = False
                    continue
                tokens.append((beg, end, lineno))
            elif utils.is_empty_node(cols):
                word_id, empty_id = (int(i) for i in utils.parse_empty_node_id(cols))
                if word_id != current_word_id or empty_id != next_empty_id:
                    Error(
                        state=state, config=self.incfg, lineno=lineno,
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
                    Error(
                        state=state, config=self.incfg, lineno=lineno,
                        testid='misplaced-empty-node',
                        message=f"Empty node id {cols[ID]} must occur before multiword token {tokens[-1][0]}-{tokens[-1][1]}."
                    ).confirm()
                    ok = False
        # Now let's do some basic sanity checks on the sequences.
        # Expected sequence of word IDs is 1, 2, ...
        expstrseq = ','.join(str(x) for x in range(1, len(words) + 1))
        wrdstrseq = ','.join(str(x) for x in words)
        if wrdstrseq != expstrseq:
            Error(
                state=state, config=self.incfg, lineno=-1,
                testid='word-id-sequence',
                message=f"Words do not form a sequence. Got '{wrdstrseq}'. Expected '{expstrseq}'."
            ).confirm()
            ok = False
        # Check elementary sanity of word intervals.
        # Remember that these are not just multi-word tokens. Here we have intervals even for single-word tokens (b=e)!
        for (b, e, lineno) in tokens:
            if e < b: # end before beginning
                Error(
                    state=state, config=self.incfg, lineno=lineno,
                    testid='reversed-word-interval',
                    message=f'Spurious token interval {b}-{e}'
                ).confirm()
                ok = False
                continue
            if b < 1 or e > len(words): # out of range
                Error(
                    state=state, config=self.incfg, lineno=lineno,
                    testid='word-interval-out',
                    message=f'Spurious token interval {b}-{e} (out of range)'
                ).confirm()
                ok = False
                continue
        return ok



    def check_token_range_overlaps(self, state):
        """
        Checks that the word ranges for multiword tokens do not overlap.

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
        invalid-word-interval
        overlapping-word-intervals

        Returns
        -------
        ok : bool
            Is it OK to run subsequent checks? It can be OK even after some
            less severe errors.
        """
        ok = True
        Incident.default_level = 1
        Incident.default_testclass = TestClass.FORMAT
        covered = set()
        for i in range(len(state.current_token_node_table)):
            lineno = state.sentence_line + i
            cols = state.current_token_node_table[i]
            if not utils.is_multiword_token(cols):
                continue
            m = utils.crex.mwtid.fullmatch(cols[ID])
            if not m: # This should not happen. The function utils.is_multiword_token() would then not return True.
                Error(
                    state=state, config=self.incfg, lineno=lineno,
                    testid='invalid-word-interval',
                    message=f"Spurious word interval definition: '{cols[ID]}'."
                ).confirm()
                continue
            start, end = m.groups()
            start, end = int(start), int(end)
            # Do not test if start >= end: This was already tested above in check_id_sequence().
            if covered & set(range(start, end+1)):
                Error(
                    state=state, config=self.incfg, lineno=lineno,
                    testid='overlapping-word-intervals',
                    message=f'Range overlaps with others: {cols[ID]}'
                ).confirm()
                ok = False
            covered |= set(range(start, end+1))
        return ok



#------------------------------------------------------------------------------
# Level 1 tests applicable to the whole input file.
#------------------------------------------------------------------------------



    def check_newlines(self, state, inp):
        """
        Checks that the input file consistently uses linux-style newlines (LF
        only, not CR LF like in Windows). To be run on the input file handle
        after the whole input has been read.

        Incidents
        ---------
        non-unix-newline
        """
        if inp.newlines and inp.newlines != '\n':
            Error(
                state=state, config=self.incfg,
                level=1,
                testclass=TestClass.FORMAT,
                lineno=state.current_line,
                testid='non-unix-newline',
                message='Only the unix-style LF line terminator is allowed.'
            ).confirm()
