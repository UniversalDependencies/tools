#! /usr/bin/python
# Original code (2015) by Filip Ginter and Sampo Pyysalo.
# DZ 2018-11-04: Porting the validator to Python 3.
import fileinput
import sys
import io
import os.path
import argparse
import logging
import traceback
# According to https://stackoverflow.com/questions/1832893/python-regex-matching-unicode-properties,
# the regex module has the same API as re but it can check Unicode character properties using \p{}
# as in Perl.
#import re
import regex as re
import unicodedata


THISDIR=os.path.dirname(os.path.realpath(os.path.abspath(__file__))) # The folder where this script resides.

# Constants for the column indices
COLCOUNT=10
ID,FORM,LEMMA,UPOS,XPOS,FEATS,HEAD,DEPREL,DEPS,MISC=range(COLCOUNT)
COLNAMES='ID,FORM,LEMMA,UPOS,XPOS,FEATS,HEAD,DEPREL,DEPS,MISC'.split(',')
TOKENSWSPACE=MISC+1 #one extra constant

# Global variables:
curr_line=0 # Current line in the input file
sentence_line=0 # The line in the input file on which the current sentence starts
sentence_id=None # The most recently read sentence id
line_of_first_empty_node=None
line_of_first_enhanced_orphan=None

error_counter={} # key: error type value: error count
warn_on_missing_files=set() # langspec files which you should warn about in case they are missing (can be deprel, edeprel, feat_val, tokens_w_space)
def warn(msg, error_type, lineno=True, nodelineno=0, nodeid=0):
    """
    Print the warning.
    If lineno is True, print the number of the line last read from input. Note
    that once we have read a sentence, this is the number of the empty line
    after the sentence, hence we probably do not want to print it.
    If we still have an error that pertains to an individual node, and we know
    the number of the line where the node appears, we can supply it via
    nodelineno. Nonzero nodelineno means that lineno value is ignored.
    If lineno is False, print the number and starting line of the current tree.
    """
    global curr_fname, curr_line, sentence_line, sentence_id, error_counter, tree_counter, args
    error_counter[error_type] = error_counter.get(error_type, 0)+1
    if not args.quiet:
        if args.max_err>0 and error_counter[error_type]==args.max_err:
            print(('...suppressing further errors regarding ' + error_type), file=sys.stderr)
        elif args.max_err>0 and error_counter[error_type]>args.max_err:
            pass #suppressed
        else:
            if len(args.input)>1: #several files, should report which one
                if curr_fname=="-":
                    fn="(in STDIN) "
                else:
                    fn="(in "+os.path.basename(curr_fname)+") "
            else:
                fn=""
            sent = ''
            node = ''
            # Global variable (last read sentence id): sentence_id
            # Originally we used a parameter sid but we probably do not need to override the global value.
            if sentence_id:
                sent = ' Sent ' + sentence_id
            if nodeid:
                node = ' Node ' + str(nodeid)
            if nodelineno:
                print("[%sLine %d%s%s]: %s" % (fn, nodelineno, sent, node, msg), file=sys.stderr)
            elif lineno:
                print("[%sLine %d%s%s]: %s" % (fn, curr_line, sent, node, msg), file=sys.stderr)
            else:
                print("[%sTree number %d on line %d%s%s]: %s" % (fn, tree_counter, sentence_line, sent, node, msg), file=sys.stderr)

###### Support functions

def is_whitespace(line):
    return re.match(r"^\s+$", line)

def is_word(cols):
    return re.match(r"^[1-9][0-9]*$", cols[ID])

def is_multiword_token(cols):
    return re.match(r"^[1-9][0-9]*-[1-9][0-9]*$", cols[ID])

def is_empty_node(cols):
    return re.match(r"^[0-9]+\.[1-9][0-9]*$", cols[ID])

def parse_empty_node_id(cols):
    m = re.match(r"^([0-9]+)\.([0-9]+)$", cols[ID])
    assert m, 'parse_empty_node_id with non-empty node'
    return m.groups()

def shorten(string):
    return string if len(string) < 25 else string[:20]+'[...]'

def lspec2ud(deprel):
    return deprel.split(':', 1)[0]



#==============================================================================
# Level 1 tests. Only CoNLL-U backbone. Values can be empty or non-UD.
#==============================================================================

sentid_re=re.compile('^# sent_id\s*=\s*(\S+)$')
def trees(inp, tag_sets, args):
    """
    `inp` a file-like object yielding lines as unicode
    `tag_sets` and `args` are needed for choosing the tests

    This function does elementary checking of the input and yields one
    sentence at a time from the input stream.
    """
    global curr_line, sentence_line, sentence_id
    comments=[] # List of comment lines to go with the current sentence
    lines=[] # List of token/word lines of the current sentence
    for line_counter, line in enumerate(inp):
        curr_line=line_counter+1
        line=line.rstrip(u"\n")
        if is_whitespace(line):
            warn('Spurious line that appears empty but is not; there are whitespace characters.', 'Format')
            # We will pretend that the line terminates a sentence in order to avoid subsequent misleading error messages.
            if lines:
                yield comments, lines
                comments=[]
                lines=[]
        elif not line: # empty line
            if lines: # sentence done
                yield comments, lines
                comments=[]
                lines=[]
            else:
                warn('Spurious empty line. Only one empty line is expected after every sentence.', 'Format')
        elif line[0]=='#':
            # We will really validate sentence ids later. But now we want to remember
            # everything that looks like a sentence id and use it in the error messages.
            # Line numbers themselves may not be sufficient if we are reading multiple
            # files from a pipe.
            match = sentid_re.match(line)
            if match:
                sentence_id = match.group(1)
            if not lines: # before sentence
                comments.append(line)
            else:
                warn('Spurious comment line. Comments are only allowed before a sentence.', 'Format')
        elif line[0].isdigit():
            validate_unicode_normalization(line)
            if not lines: # new sentence
                sentence_line=curr_line
            cols=line.split(u"\t")
            if len(cols)!=COLCOUNT:
                warn('The line has %d columns but %d are expected.'%(len(cols), COLCOUNT), 'Format')
            lines.append(cols)
            validate_cols_level1(cols)
            if args.level > 1:
                validate_cols(cols,tag_sets,args)
        else: # A line which is neither a comment nor a token/word, nor empty. That's bad!
            warn("Spurious line: '%s'. All non-empty lines should start with a digit or the # character."%(line), 'Format')
    else: # end of file
        if comments or lines: # These should have been yielded on an empty line!
            warn('Missing empty line after the last tree.', 'Format')
            yield comments, lines

###### Tests applicable to a single row indpendently of the others

def validate_unicode_normalization(text):
    """
    Tests that letters composed of multiple Unicode characters (such as a base
    letter plus combining diacritics) conform to NFC normalization (canonical
    decomposition followed by canonical composition).
    """
    normalized_text = unicodedata.normalize('NFC', text)
    if text != normalized_text:
        # Find the first unmatched character and include it in the report.
        firsti = -1
        firstj = -1
        inpfirst = ''
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
                    break
            if firsti >= 0:
                break
        warn("Unicode not normalized: %s.character[%d] is %s, should be %s" % (COLNAMES[firsti], firstj, inpfirst, nfcfirst), 'Unicode')

whitespace_re=re.compile('.*\s',re.U)
whitespace2_re=re.compile('.*\s\s', re.U)
def validate_cols_level1(cols):
    """
    Tests that can run on a single line and pertain only to the CoNLL-U file
    format, not to predefined sets of UD tags.
    """
    # Some whitespace may be permitted in FORM, LEMMA and MISC but not elsewhere.
    for col_idx in range(MISC+1):
        if col_idx >= len(cols):
            break # this has been already reported in trees()
        # Must never be empty
        if not cols[col_idx]:
            warn('Empty value in column %s'%(COLNAMES[col_idx]), 'Format')
        else:
            # Must never have leading/trailing whitespace
            if cols[col_idx][0].isspace():
                warn('Initial whitespace not allowed in column %s'%(COLNAMES[col_idx]), 'Format')
            if cols[col_idx][-1].isspace():
                warn('Trailing whitespace not allowed in column %s'%(COLNAMES[col_idx]), 'Format')
            # Must never contain two consecutive whitespace characters
            if whitespace2_re.match(cols[col_idx]):
                warn('Two or more consecutive whitespace characters not allowed in column %s'%(COLNAMES[col_idx]), 'Format')
    # These columns must not have whitespace
    for col_idx in (ID,UPOS,XPOS,FEATS,HEAD,DEPREL,DEPS):
        if col_idx >= len(cols):
            break # this has been already reported in trees()
        if whitespace_re.match(cols[col_idx]):
            warn("White space not allowed in the %s column: '%s'"%(COLNAMES[col_idx], cols[col_idx]), 'Format')
    # Check for the format of the ID value. (ID must not be empty.)
    if not (is_word(cols) or is_empty_node(cols) or is_multiword_token(cols)):
        warn("Unexpected ID format '%s'" % cols[ID], 'Format')

##### Tests applicable to the whole tree

interval_re=re.compile('^([0-9]+)-([0-9]+)$',re.U)
def validate_ID_sequence(tree):
    """
    Validates that the ID sequence is correctly formed.
    """
    words=[]
    tokens=[]
    current_word_id, next_empty_id = 0, 1
    for cols in tree:
        if not is_empty_node(cols):
            next_empty_id = 1    # reset sequence
        if is_word(cols):
            t_id=int(cols[ID])
            current_word_id = t_id
            words.append(t_id)
            # Not covered by the previous interval?
            if not (tokens and tokens[-1][0]<=t_id and tokens[-1][1]>=t_id):
                tokens.append((t_id,t_id)) # nope - let's make a default interval for it
        elif is_multiword_token(cols):
            match=interval_re.match(cols[ID]) # Check the interval against the regex
            if not match:
                warn("Spurious token interval definition: '%s'."%cols[ID], 'Format', lineno=False)
                continue
            beg,end=int(match.group(1)),int(match.group(2))
            if not ((not words and beg == 1) or (words and beg == words[-1]+1)):
                warn('Multiword range not before its first word', 'Format')
                continue
            tokens.append((beg,end))
        elif is_empty_node(cols):
            word_id, empty_id = (int(i) for i in parse_empty_node_id(cols))
            if word_id != current_word_id or empty_id != next_empty_id:
                warn('Empty node id %s, expected %d.%d' %
                     (cols[ID], current_word_id, next_empty_id), 'Format')
            next_empty_id += 1
    # Now let's do some basic sanity checks on the sequences
    wrdstrseq = ','.join(str(x) for x in words)
    expstrseq = ','.join(str(x) for x in range(1, len(words)+1)) # Words should form a sequence 1,2,...
    if wrdstrseq != expstrseq:
        warn("Words do not form a sequence. Got '%s'. Expected '%s'."%(wrdstrseq, expstrseq), 'Format', lineno=False)
    # Check elementary sanity of word intervals
    for (b,e) in tokens:
        if e<b: # end before beginning
            warn('Spurious token interval %d-%d'%(b,e), 'Format')
            continue
        if b<1 or e>len(words): # out of range
            warn('Spurious token interval %d-%d (out of range)'%(b,e), 'Format')
            continue

def validate_token_ranges(tree):
    """
    Checks that the word ranges for multiword tokens are valid.
    """
    covered = set()
    for cols in tree:
        if not is_multiword_token(cols):
            continue
        m = interval_re.match(cols[ID])
        if not m:
            warn('Failed to parse ID %s' % cols[ID], 'Format')
            continue
        start, end = m.groups()
        try:
            start, end = int(start), int(end)
        except ValueError:
            assert False, 'internal error' # RE should assure that this works
        if not start < end:
            warn('Invalid range: %s' % cols[ID], 'Format')
            continue
        if covered & set(range(start, end+1)):
            warn('Range overlaps with others: %s' % cols[ID], 'Format')
        covered |= set(range(start, end+1))

def validate_newlines(inp):
    if inp.newlines and inp.newlines!='\n':
        warn('Only the unix-style LF line terminator is allowed', 'Format')



#==============================================================================
# Level 2 tests. Tree structure, universal tags and deprels. Note that any
# well-formed Feature=Valid pair is allowed (because it could be language-
# specific) and any word form or lemma can contain spaces (because language-
# specific guidelines may permit it).
#==============================================================================

###### Metadata tests #########

def validate_sent_id(comments,known_ids,lcode):
    matched=[]
    for c in comments:
        match=sentid_re.match(c)
        if match:
            matched.append(match)
        else:
            if c.startswith('# sent_id') or c.startswith('#sent_id'):
                warn("Spurious sent_id line: '%s' Should look like '# sent_id = xxxxx' where xxxxx is not whitespace. Forward slash reserved for special purposes." %c, 'Metadata')
    if not matched:
        warn('Missing the sent_id attribute.', 'Metadata')
    elif len(matched)>1:
        warn('Multiple sent_id attributes.', 'Metadata')
    else:
        # Uniqueness of sentence ids should be tested treebank-wide, not just file-wide.
        # For that to happen, all three files should be tested at once.
        sid=matched[0].group(1)
        if sid in known_ids:
            warn('Non-unique sent_id the sent_id attribute: '+sid, 'Metadata')
        if sid.count(u"/")>1 or (sid.count(u"/")==1 and lcode!=u"ud" and lcode!=u"shopen"):
            warn('The forward slash is reserved for special use in parallel treebanks: '+sid, 'Metadata')
        known_ids.add(sid)

text_re=re.compile('^# text\s*=\s*(.+)$')
def validate_text_meta(comments,tree):
    matched=[]
    for c in comments:
        match=text_re.match(c)
        if match:
            matched.append(match)
    if not matched:
        warn('Missing the text attribute.', 'Metadata')
    elif len(matched)>1:
        warn('Multiple text attributes.', 'Metadata')
    else:
        stext=matched[0].group(1)
        if stext[-1].isspace():
            warn('The text attribute must not end with whitespace', 'Metadata')
        # Validate the text against the SpaceAfter attribute in MISC.
        skip_words=set()
        mismatch_reported=0 # do not report multiple mismatches in the same sentence; they usually have the same cause
        for cols in tree:
            if MISC >= len(cols):
                # This error has been reported elsewhere but we cannot check MISC now.
                continue
            if 'NoSpaceAfter=Yes' in cols[MISC]: # I leave this without the split("|") to catch all
                warn('NoSpaceAfter=Yes should be replaced with SpaceAfter=No', 'Metadata')
            if '.' in cols[ID]: # empty word
                if 'SpaceAfter=No' in cols[MISC]: # I leave this without the split("|") to catch all
                    warn('There should not be a SpaceAfter=No entry for empty words', 'Metadata')
                continue
            elif '-' in cols[ID]: # multi-word token
                beg,end=cols[ID].split('-')
                try:
                    begi,endi = int(beg),int(end)
                except ValueError as e:
                    warn('Non-integer range %s-%s (%s)'%(beg,end,e), 'Format')
                    begi,endi=1,0
                # If we see a MWtoken, add its words to an ignore-set - these will be skipped, and also checked for absence of SpaceAfter=No
                for i in range(begi, endi+1):
                    skip_words.add(str(i))
            elif cols[ID] in skip_words:
                if 'SpaceAfter=No' in cols[MISC]:
                    warn('There should not be a SpaceAfter=No entry for words which are a part of a multi-word token', 'Metadata')
                continue
            else:
                # Err, I guess we have nothing to do here. :)
                pass
            # So now we have either a MWtoken or a word which is also a token in its entirety
            if not stext.startswith(cols[FORM]):
                if not mismatch_reported:
                    warn("Mismatch between the text attribute and the FORM field. Form[%s] is '%s' but text is '%s...'" %(cols[ID], cols[FORM], stext[:len(cols[FORM])+20]), 'Metadata', False)
                    mismatch_reported=1
            else:
                stext=stext[len(cols[FORM]):] # eat the form
                if 'SpaceAfter=No' not in cols[MISC].split("|"):
                    if args.check_space_after and (stext) and not stext[0].isspace():
                        warn("SpaceAfter=No is missing in the MISC field of node #%s because the text is '%s'" %(cols[ID], shorten(cols[FORM]+stext)), 'Metadata')
                    stext=stext.lstrip()
        if stext:
            warn("Extra characters at the end of the text attribute, not accounted for in the FORM fields: '%s'"%stext, 'Metadata')

##### Tests applicable to a single row indpendently of the others

def validate_cols(cols, tag_sets, args):
    """
    All tests that can run on a single line. Done as soon as the line is read,
    called from trees() if level>1.
    """
    if is_word(cols) or is_empty_node(cols):
        validate_character_constraints(cols) # level 2
        validate_features(cols, tag_sets, args) # level 2 and up (relevant code checks whether higher level is required)
        validate_pos(cols,tag_sets) # level 2
    elif is_multiword_token(cols):
        validate_token_empty_vals(cols)
    # else do nothing; we have already reported wrong ID format at level 1
    if is_word(cols):
        validate_deprels(cols, tag_sets, args) # level 2 and up
    elif is_empty_node(cols):
        validate_empty_node_empty_vals(cols) # level 2
        # TODO check also the following:
        # - DEPS are connected and non-acyclic
        # (more, what?)
    if args.level > 3:
        validate_whitespace(cols, tag_sets) # level 4 (it is language-specific; to disallow everywhere, use --lang ud)

def validate_token_empty_vals(cols):
    """
    Checks that a multi-word token has _ empty values in all fields except MISC.
    This is required by UD guidelines although it is not a problem in general,
    therefore a level 2 test.
    """
    assert is_multiword_token(cols), 'internal error'
    for col_idx in range(LEMMA,MISC): #all columns in the LEMMA-DEPS range
        if cols[col_idx]!=u"_":
            warn("A multi-word token line must have '_' in the column %s. Now: '%s'."%(COLNAMES[col_idx], cols[col_idx]), 'Format')

def validate_empty_node_empty_vals(cols):
    """
    Checks that an empty node has _ empty values in HEAD and DEPREL. This is
    required by UD guidelines but not necessarily by CoNLL-U, therefore
    a level 2 test.
    """
    assert is_empty_node(cols), 'internal error'
    for col_idx in (HEAD, DEPREL):
        if cols[col_idx]!=u"_":
            warn("An empty node must have '_' in the column %s. Now: '%s'."%(COLNAMES[col_idx], cols[col_idx]), 'Format')

# Ll ... lowercase Unicode letters
# Lm ... modifier Unicode letters (e.g., superscript h)
# Lo ... other Unicode letters (all caseless scripts, e.g., Arabic)
# M .... combining diacritical marks
# Underscore is allowed between letters but not at beginning, end, or next to another underscore.
edeprelpart_resrc = '[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(_[\p{Ll}\p{Lm}\p{Lo}\p{M}]+)*';
# There must be always the universal part, consisting only of ASCII letters.
# There can be up to three additional, colon-separated parts: subtype, preposition and case.
# One of them, the preposition, may contain Unicode letters. We do not know which one it is
# (only if there are all four parts, we know it is the third one).
# ^[a-z]+(:[a-z]+)?(:[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(_[\p{Ll}\p{Lm}\p{Lo}\p{M}]+)*)?(:[a-z]+)?$
edeprel_resrc = '^[a-z]+(:[a-z]+)?(:' + edeprelpart_resrc + ')?(:[a-z]+)?$'
edeprel_re = re.compile(edeprel_resrc, re.U)
def validate_character_constraints(cols):
    """
    Checks general constraints on valid characters, e.g. that UPOS
    only contains [A-Z].
    """
    if is_multiword_token(cols):
        return
    if UPOS >= len(cols):
        return # this has been already reported in trees()
    if not (re.match(r"^[A-Z]+$", cols[UPOS]) or
            (is_empty_node(cols) and cols[UPOS] == u"_")):
        warn('Invalid UPOS value %s' % cols[UPOS], 'Morpho')
    if not (re.match(r"^[a-z]+(:[a-z]+)?$", cols[DEPREL]) or
            (is_empty_node(cols) and cols[DEPREL] == u"_")):
        warn('Invalid DEPREL value %s' % cols[DEPREL], 'Syntax')
    try:
        deps = deps_list(cols)
    except ValueError:
        warn('Failed for parse DEPS: %s' % cols[DEPS], 'Syntax')
        return
    if any(deprel for head, deprel in deps_list(cols)
           if not edeprel_re.match(deprel)):
        warn('Invalid value in DEPS: %s' % cols[DEPS], 'Syntax')

attr_val_re=re.compile('^([A-Z0-9][A-Z0-9a-z]*(?:\[[a-z0-9]+\])?)=(([A-Z0-9][A-Z0-9a-z]*)(,([A-Z0-9][A-Z0-9a-z]*))*)$',re.U)
val_re=re.compile('^[A-Z0-9][A-Z0-9a-z]*',re.U)
def validate_features(cols, tag_sets, args):
    """
    Checks general constraints on feature-value format. On level 4 and higher,
    also checks that a feature-value pair is listed as approved. (Every pair
    must be allowed on level 2 because it could be defined as language-specific.
    To disallow non-universal features, test on level 4 with language 'ud'.)
    """
    if FEATS >= len(cols):
        return # this has been already reported in trees()
    feats=cols[FEATS]
    if feats == '_':
        return True
    feat_list=feats.split('|')
    if [f.lower() for f in feat_list]!=sorted(f.lower() for f in feat_list):
        warn("Morphological features must be sorted: '%s'"%feats, 'Morpho')
    attr_set=set() # I'll gather the set of attributes here to check later than none is repeated
    for f in feat_list:
        match=attr_val_re.match(f)
        if match is None:
            warn("Spurious morphological feature: '%s'. Should be of the form attribute=value and must start with [A-Z0-9] and only contain [A-Za-z0-9]."%f, 'Morpho')
            attr_set.add(f) # to prevent misleading error "Repeated features are disallowed"
        else:
            # Check that the values are sorted as well
            attr=match.group(1)
            attr_set.add(attr)
            values=match.group(2).split(u",")
            if len(values)!=len(set(values)):
                warn("Repeated feature values are disallowed: %s"%feats, 'Morpho')
            if [v.lower() for v in values]!=sorted(v.lower() for v in values):
                warn("If an attribute has multiple values, these must be sorted as well: '%s'"%f, 'Morpho')
            for v in values:
                if not val_re.match(v):
                    warn("Incorrect value '%s' in '%s'. Must start with [A-Z0-9] and only contain [A-Za-z0-9]."%(v,f), 'Morpho')
                # Level 2 tests character properties and canonical order but not that the f-v pair is known.
                # Level 4 also checks whether the feature value is on the list.
                # If only universal feature-value pairs are allowed, test on level 4 with lang='ud'.
                if args.level > 3 and tag_sets[FEATS] is not None and attr+'='+v not in tag_sets[FEATS]:
                    warn_on_missing_files.add("feat_val")
                    warn('Unknown attribute-value pair %s=%s'%(attr,v), 'Morpho')
    if len(attr_set)!=len(feat_list):
        warn('Repeated features are disallowed: %s'%feats, 'Morpho')

def validate_upos(cols,tag_sets):
    if UPOS >= len(cols):
        return # this has been already reported in trees()
    if tag_sets[UPOS] is not None and cols[UPOS] not in tag_sets[UPOS]:
        warn('Unknown UPOS tag: %s'%cols[UPOS], 'Morpho')

def validate_xpos(cols,tag_sets):
    if XPOS >= len(cols):
        return # this has been already reported in trees()
    # We currently do not have any list of known XPOS tags, hence tag_sets[XPOS] is None.
    if tag_sets[XPOS] is not None and cols[XPOS] not in tag_sets[XPOS]:
        warn('Unknown XPOS tag: %s'%cols[XPOS], 'Morpho')

def validate_pos(cols,tag_sets):
    if not (is_empty_node(cols) and cols[UPOS] == '_'):
        validate_upos(cols, tag_sets)
    if not (is_empty_node(cols) and cols[XPOS] == '_'):
        validate_xpos(cols, tag_sets)

def validate_deprels(cols, tag_sets, args):
    if DEPREL >= len(cols):
        return # this has been already reported in trees()
    # Test only the universal part if testing at universal level.
    deprel = cols[DEPREL]
    if args.level < 4:
        deprel = lspec2ud(deprel)
    if tag_sets[DEPREL] is not None and deprel not in tag_sets[DEPREL]:
        warn_on_missing_files.add("deprel")
        warn('Unknown UD DEPREL: %s'%cols[DEPREL], 'Syntax')
    if tag_sets[DEPS] is not None and cols[DEPS]!='_':
        for head_deprel in cols[DEPS].split(u"|"):
            try:
                head,deprel=head_deprel.split(u":",1)
            except ValueError:
                warn("Malformed head:deprel pair '%s'"%head_deprel, 'Syntax')
                continue
            if args.level < 4:
                deprel = lspec2ud(deprel)
            if deprel not in tag_sets[DEPS]:
                warn_on_missing_files.add("edeprel")
                warn("Unknown enhanced dependency relation '%s' in '%s'"%(deprel,head_deprel), 'Syntax')

##### Tests applicable to the whole sentence

def subset_to_words_and_empty_nodes(tree):
    """
    Only picks word and empty node lines, skips multiword token lines.
    """
    return [cols for cols in tree if is_word(cols) or is_empty_node(cols)]

def deps_list(cols):
    if DEPS >= len(cols):
        return # this has been already reported in trees()
    if cols[DEPS] == '_':
        deps = []
    else:
        deps = [hd.split(':',1) for hd in cols[DEPS].split('|')]
    if any(hd for hd in deps if len(hd) != 2):
        raise ValueError('malformed DEPS: %s' % cols[DEPS])
    return deps

def validate_ID_references(tree):
    """
    Validates that HEAD and DEPS reference existing IDs.
    """
    word_tree = subset_to_words_and_empty_nodes(tree)
    ids = set([cols[ID] for cols in word_tree])
    def valid_id(i):
        return i in ids or i == '0'
    def valid_empty_head(cols):
        return cols[HEAD] == '_' and is_empty_node(cols)
    for cols in word_tree:
        if HEAD >= len(cols):
            return # this has been already reported in trees()
        if not (valid_id(cols[HEAD]) or valid_empty_head(cols)):
            warn('Undefined ID in HEAD: %s' % cols[HEAD], 'Format')
        try:
            deps = deps_list(cols)
        except ValueError:
            warn("Failed to parse DEPS: '%s'" % cols[DEPS], 'Format')
            continue
        for head, deprel in deps:
            if not valid_id(head):
                warn("Undefined ID in DEPS: '%s'" % head, 'Format')

def validate_root(tree):
    """
    Validates that DEPREL is "root" iff HEAD is 0.
    """
    for cols in tree:
        if not (is_word(cols) or is_empty_node(cols)):
            continue
        if HEAD >= len(cols):
            continue # this has been already reported in trees()
        if cols[HEAD] == '0':
            if cols[DEPREL] != 'root':
                warn("DEPREL must be 'root' if HEAD is 0", 'Syntax')
        else:
            if cols[DEPREL] == 'root':
                warn("DEPREL cannot be 'root' if HEAD is not 0", 'Syntax')

def validate_deps(tree):
    """
    Validates that DEPS is correctly formatted and that there are no
    self-loops in DEPS.
    """
    node_line = sentence_line - 1
    for cols in tree:
        node_line += 1
        if not (is_word(cols) or is_empty_node(cols)):
            continue
        if DEPS >= len(cols):
            continue # this has been already reported in trees()
        try:
            deps = deps_list(cols)
            heads = [float(h) for h, d in deps]
        except ValueError:
            warn("Failed to parse DEPS: '%s'" % cols[DEPS], 'Format', nodelineno=node_line)
            return
        if heads != sorted(heads):
            warn("DEPS not sorted by head index: '%s'" % cols[DEPS], 'Format', nodelineno=node_line)
        else:
            lasth = None
            lastd = None
            for h, d in deps:
                if h == lasth:
                    if d < lastd:
                        warn("DEPS pointing to head '%s' not sorted by relation type: '%s'" % (h, cols[DEPS]), 'Format', nodelineno=node_line)
                    elif d == lastd:
                        warn("DEPS contain multiple instances of the same relation '%s:%s'" % (h, d), 'Format', nodelineno=node_line)
                lasth = h
                lastd = d
                # Like in the basic representation, head 0 implies relation root and vice versa.
                # Note that the enhanced graph may have multiple roots (coordination of predicates).
                ud = lspec2ud(d)
                if h == '0' and ud != 'root':
                    warn("Illegal relation '%s:%s' in DEPS: must be 'root' if head is 0" % (h, d), 'Format', nodelineno=node_line)
                if ud == 'root' and h != '0':
                    warn("Illegal relation '%s:%s' in DEPS: cannot be 'root' if head is not 0" % (h, d), 'Format', nodelineno=node_line)
        try:
            id_ = float(cols[ID])
        except ValueError:
            warn("Non-numeric ID: '%s'" % cols[ID], 'Format', nodelineno=node_line)
            return
        if id_ in heads:
            warn("Self-loop in DEPS for '%s'" % cols[ID], 'Format', nodelineno=node_line)

def build_tree(sentence):
    """
    Takes the list of non-comment lines (line = list of columns) describing
    a sentence. Returns a dictionary with items providing easier access to the
    tree structure. In case of fatal problems (missing HEAD etc.) returns None
    but does not report the error (presumably it has already been reported).

    tree ... dictionary:
      nodes ... array of word lines, i.e., lists of columns;
          mwt and empty nodes are skipped, indices equal to ids (nodes[0] is empty)
      children ... array of sets of children indices (numbers, not strings);
          indices to this array equal to ids (children[0] are the children of the root)
      linenos ... array of line numbers in the file, corresponding to nodes
          (needed in error messages)
    """
    global sentence_line # the line of the first token/word of the current tree (skipping comments!)
    node_line = sentence_line - 1
    children = {} # node -> set of children
    tree = {
        'nodes':    [['0', '_', '_', '_', '_', '_', '_', '_', '_', '_']], # add artificial node 0
        'children': [],
        'linenos':  [sentence_line] # for node 0
    }
    for cols in sentence:
        node_line += 1
        if not is_word(cols):
            continue
        # Even MISC may be needed when checking the annotation guidelines
        # (for instance, SpaceAfter=No must not occur inside a goeswith span).
        if MISC >= len(cols):
            # This error has been reported on lower levels, do not report it here.
            # Do not continue to check annotation if there are elementary flaws.
            return None
        try:
            id_ = int(cols[ID])
        except ValueError:
            # This error has been reported on lower levels, do not report it here.
            # Do not continue to check annotation if there are elementary flaws.
            return None
        try:
            head = int(cols[HEAD])
        except ValueError:
            # This error has been reported on lower levels, do not report it here.
            # Do not continue to check annotation if there are elementary flaws.
            return None
        if head == id_:
            warn('HEAD == ID for %s' % cols[ID], 'Syntax', nodelineno=node_line)
            return None
        tree['nodes'].append(cols)
        tree['linenos'].append(node_line)
        # Incrementally build the set of children of every node.
        children.setdefault(cols[HEAD], set()).add(id_)
    for cols in tree['nodes']:
        tree['children'].append(sorted(children.get(cols[ID], [])))
    # Check that there is just one node with the root relation.
    if len(tree['children'][0]) > 1 and args.single_root:
        warn('Multiple root words: %s' % tree['children'][0], 'Syntax', lineno=False)
    # Return None if there are any cycles. Avoid surprises when working with the graph.
    # Presence of cycles is equivalent to presence of unreachable nodes.
    projection = set()
    get_projection(0, tree, projection)
    unreachable = set(range(1, len(tree['nodes']) - 1)) - projection
    if unreachable:
        warn('Non-tree structure. Words %s are not reachable from the root 0.'%(','.join(str(w) for w in sorted(unreachable))), 'Syntax', lineno=False)
        return None
    return tree

def get_projection(id, tree, projection):
    """
    Like proj() above, but works with the tree data structure. Collects node ids
    in the set called projection.
    """
    for child in tree['children'][id]:
        if child in projection:
            continue # cycle is or will be reported elsewhere
        projection.add(child)
        get_projection(child, tree, projection)
    return projection

def build_egraph(sentence):
    """
    Takes the list of non-comment lines (line = list of columns) describing
    a sentence. Returns a dictionary with items providing easier access to the
    enhanced graph structure. In case of fatal problems returns None
    but does not report the error (presumably it has already been reported).
    However, once the graph has been found and built, this function verifies
    that the graph is connected and generates an error if it is not.

    egraph ... dictionary:
      nodes ... dictionary of dictionaries, each corresponding to a word or an empty node; mwt lines are skipped
          keys equal to node ids (i.e. strings that look like integers or decimal numbers; key 0 is the artificial root node)
          value is a dictionary-record:
              cols ... array of column values from the input line corresponding to the node
              children ... set of children ids (strings)
              lineno ... line number in the file (needed in error messages)
    """
    global sentence_line # the line of the first token/word of the current tree (skipping comments!)
    node_line = sentence_line - 1
    egraph_exists = False # enhanced deps are optional
    rootnode = {
        'cols': ['0', '_', '_', '_', '_', '_', '_', '_', '_', '_'],
        'deps': [],
        'parents': set(),
        'children': set(),
        'lineno': sentence_line
    }
    egraph = {
        '0': rootnode
    } # structure described above
    nodeids = set()
    for cols in sentence:
        node_line += 1
        if is_multiword_token(cols):
            continue
        if MISC >= len(cols):
            # This error has been reported on lower levels, do not report it here.
            # Do not continue to check annotation if there are elementary flaws.
            return None
        try:
            deps = deps_list(cols)
            heads = [h for h, d in deps]
        except ValueError:
            # This error has been reported on lower levels, do not report it here.
            # Do not continue to check annotation if there are elementary flaws.
            return None
        if is_empty_node(cols):
            egraph_exists = True
        nodeids.add(cols[ID])
        # The graph may already contain a record for the current node if one of
        # the previous nodes is its child. If it doesn't, we will create it now.
        egraph.setdefault(cols[ID], {})
        egraph[cols[ID]]['cols'] = cols
        egraph[cols[ID]]['deps'] = deps_list(cols)
        egraph[cols[ID]]['parents'] = set([h for h, d in deps])
        egraph[cols[ID]].setdefault('children', set())
        egraph[cols[ID]]['lineno'] = node_line
        # Incrementally build the set of children of every node.
        for h in heads:
            egraph_exists = True
            egraph.setdefault(h, {})
            egraph[h].setdefault('children', set()).add(cols[ID])
    # We are currently testing the existence of enhanced graphs separately for each sentence.
    # It is thus possible to have one sentence with connected egraph and another without enhanced dependencies.
    if not egraph_exists:
        return None
    # Check that the graph is connected. The UD v2 guidelines do not license unconnected graphs.
    # Compute projection of every node. Beware of cycles.
    projection = set()
    get_graph_projection('0', egraph, projection)
    unreachable = nodeids - projection
    if unreachable:
        sur = sorted(unreachable)
        warn("Enhanced graph is not connected. Nodes %s are not reachable from any root" % sur, 'Syntax', lineno=False)
        return None
    return egraph

def get_graph_projection(id, graph, projection):
    for child in graph[id]['children']:
        if child in projection:
            continue; # skip cycles
        projection.add(child)
        get_graph_projection(child, graph, projection)
    return projection



#==============================================================================
# Level 3 tests. Annotation content vs. the guidelines (only universal tests).
#==============================================================================

def validate_upos_vs_deprel(id, tree):
    """
    For certain relations checks that the dependent word belongs to an expected
    part-of-speech category. Occasionally we may have to check the children of
    the node, too.
    """
    cols = tree['nodes'][id]
    # This is a level 3 test, we will check only the universal part of the relation.
    deprel = lspec2ud(cols[DEPREL])
    childrels = set([lspec2ud(tree['nodes'][x][DEPREL]) for x in tree['children'][id]])
    # Certain relations are reserved for nominals and cannot be used for verbs.
    # Nevertheless, they can appear with adjectives or adpositions if they are promoted due to ellipsis.
    # Unfortunately, we cannot enforce this test because a word can be cited
    # rather than used, and then it can take a nominal function even if it is
    # a verb, as in this Upper Sorbian sentence where infinitives are appositions:
    # [hsb] Z werba danci "rejować" móže substantiw nastać danco "reja", adjektiw danca "rejowanski" a adwerb dance "rejowansce", ale tež z substantiwa martelo "hamor" móže nastać werb marteli "klepać z hamorom", adjektiw martela "hamorowy" a adwerb martele "z hamorom".
    #if re.match(r"^(nsubj|obj|iobj|obl|vocative|expl|dislocated|nmod|appos)", deprel) and re.match(r"^(VERB|AUX|ADV|SCONJ|CCONJ)", cols[UPOS]):
    #    warn("Node %s: '%s' should be a nominal but it is '%s'" % (cols[ID], deprel, cols[UPOS]), 'Syntax', lineno=False)
    # Determiner can alternate with a pronoun.
    if deprel == 'det' and not re.match(r"^(DET|PRON)", cols[UPOS]) and not 'fixed' in childrels:
        warn("'det' should be 'DET' or 'PRON' but it is '%s'" % (cols[UPOS]), 'Syntax', nodeid=id, nodelineno=tree['linenos'][id])
    # Nummod is for numerals only.
    if deprel == 'nummod' and not re.match(r"^(NUM)", cols[UPOS]):
        warn("'nummod' should be 'NUM' but it is '%s'" % (cols[UPOS]), 'Syntax', nodeid=id, nodelineno=tree['linenos'][id])
    # Advmod is for adverbs, perhaps particles but not for prepositional phrases or clauses.
    # Nevertheless, we should allow adjectives because they can be used as adverbs in some languages.
    if deprel == 'advmod' and not re.match(r"^(ADV|ADJ|CCONJ|PART|SYM)", cols[UPOS]) and not 'fixed' in childrels and not 'goeswith' in childrels:
        warn("'advmod' should be 'ADV' but it is '%s'" % (cols[UPOS]), 'Syntax', nodeid=id, nodelineno=tree['linenos'][id])
    # Known expletives are pronouns. Determiners and particles are probably acceptable, too.
    if deprel == 'expl' and not re.match(r"^(PRON|DET|PART)$", cols[UPOS]):
        warn("'expl' should normally be 'PRON' but it is '%s'" % (cols[UPOS]), 'Syntax', nodeid=id, nodelineno=tree['linenos'][id])
    # Auxiliary verb/particle must be AUX.
    if deprel == 'aux' and not re.match(r"^(AUX)", cols[UPOS]):
        warn("'aux' should be 'AUX' but it is '%s'" % (cols[UPOS]), 'Syntax', nodeid=id, nodelineno=tree['linenos'][id])
    # Copula is an auxiliary verb/particle (AUX) or a pronoun (PRON|DET).
    if deprel == 'cop' and not re.match(r"^(AUX|PRON|DET|SYM)", cols[UPOS]):
        warn("'cop' should be 'AUX' or 'PRON'/'DET' but it is '%s'" % (cols[UPOS]), 'Syntax', nodeid=id, nodelineno=tree['linenos'][id])
    # AUX is normally aux or cop. It can appear in many other relations if it is promoted due to ellipsis.
    # However, I believe that it should not appear in compound. From the other side, compound can consist
    # of many different part-of-speech categories but I don't think it can contain AUX.
    if deprel == 'compound' and re.match(r"^(AUX)", cols[UPOS]):
        warn("'compound' should not be 'AUX'", 'Syntax', nodeid=id, nodelineno=tree['linenos'][id])
    # Case is normally an adposition, maybe particle.
    # However, there are also secondary adpositions and they may have the original POS tag:
    # NOUN: [cs] pomocí, prostřednictvím
    # VERB: [en] including
    # Interjection can also act as case marker for vocative, as in Sanskrit: भोः भगवन् / bhoḥ bhagavan / oh sir.
    if deprel == 'case' and re.match(r"^(PROPN|ADJ|PRON|DET|NUM|AUX)", cols[UPOS]) and not 'fixed' in childrels:
        warn("'case' should not be '%s'" % (cols[UPOS]), 'Syntax', nodeid=id, nodelineno=tree['linenos'][id])
    # Mark is normally a conjunction or adposition, maybe particle but definitely not a pronoun.
    if deprel == 'mark' and re.match(r"^(NOUN|PROPN|ADJ|PRON|DET|NUM|VERB|AUX|INTJ)", cols[UPOS]) and not 'fixed' in childrels:
        warn("'mark' should not be '%s'" % (cols[UPOS]), 'Syntax', nodeid=id, nodelineno=tree['linenos'][id])
    # Cc is a conjunction, possibly an adverb or particle.
    if deprel == 'cc' and re.match(r"^(NOUN|PROPN|ADJ|PRON|DET|NUM|VERB|AUX|INTJ)", cols[UPOS]) and not 'fixed' in childrels:
        warn("'cc' should not be '%s'" % (cols[UPOS]), 'Syntax', nodeid=id, nodelineno=tree['linenos'][id])
    if cols[DEPREL] == 'punct' and cols[UPOS] != 'PUNCT':
        warn("'punct' must be 'PUNCT' but it is '%s'" % (cols[UPOS]), 'Syntax', nodeid=id, nodelineno=tree['linenos'][id])
    if cols[UPOS] == 'PUNCT' and not re.match(r"^(punct|root)", deprel):
        warn("if UPOS is 'PUNCT', DEPREL must be 'punct' but is '%s'" % (cols[DEPREL]), 'Syntax', nodeid=id, nodelineno=tree['linenos'][id])

def validate_left_to_right_relations(id, tree):
    """
    Certain UD relations must always go left-to-right.
    Here we currently check the rule for the basic dependencies.
    The same should also be tested for the enhanced dependencies!
    """
    cols = tree['nodes'][id]
    if is_multiword_token(cols):
        return
    if DEPREL >= len(cols):
        return # this has been already reported in trees()
    # According to the v2 guidelines, apposition should also be left-headed, although the definition of apposition may need to be improved.
    if re.match(r"^(conj|fixed|flat|goeswith|appos)", cols[DEPREL]):
        ichild = int(cols[ID])
        iparent = int(cols[HEAD])
        if ichild < iparent:
            warn("Violation of guidelines: relation '%s' must go left-to-right" % cols[DEPREL], 'Syntax', nodelineno=tree['linenos'][id])

def validate_single_subject(id, tree):
    """
    No predicate should have more than one subject.
    An xcomp dependent normally has no subject, but in some languages the
    requirement may be weaker: it could have an overt subject if it is
    correferential with a particular argument of the matrix verb. Hence we do
    not check zero subjects of xcomp dependents at present.
    Furthermore, in some situations we must allow two subjects (but not three or more).
    If a clause acts as a nonverbal predicate of another clause, and if there is
    no copula, then we must attach two subjects to the predicate of the inner
    clause: one is the predicate of the inner clause, the other is the predicate
    of the outer clause. This could in theory be recursive but in practice it isn't.
    See also issue 34 (https://github.com/UniversalDependencies/tools/issues/34).
    """
    subjects = sorted([x for x in tree['children'][id] if re.search(r"subj", lspec2ud(tree['nodes'][x][DEPREL]))])
    if len(subjects) > 2:
        # We test for more than 2, but in the error message we still say more than 1, so that we do not have to explain the exceptions.
        warn("Violation of guidelines: node has more than one subject: %s" % str(subjects), 'Syntax', nodelineno=tree['linenos'][id])

def validate_deprel_pair(idparent, idchild, tree):
    """
    Certain types of dependents cannot have dependents of their own, or they
    can have only a very limited set of dependents. This test is based mostly
    on deprels but sometimes it is necessary to look at the UPOS tags and
    features as well.
    """
    # This is a level 3 test, we will check only the universal part of the relation.
    pdeprel = lspec2ud(tree['nodes'][idparent][DEPREL])
    # At present we only check children of function words and certain technical
    # nodes, which we recognize by the parent's deprel.
    ###!!! We should also check that 'det' does not have children except for a limited set of exceptions!
    ###!!! (see https://universaldependencies.org/u/overview/syntax.html#function-word-modifiers)
    if not re.match(r"^(case|mark|cc|aux|cop|det|fixed|goeswith|punct)$", pdeprel):
        return
    cdeprel = lspec2ud(tree['nodes'][idchild][DEPREL])
    # The guidelines explicitly say that negation can modify any function word
    # (see https://universaldependencies.org/u/overview/syntax.html#function-word-modifiers).
    # We cannot recognize negation simply by deprel; we have to look at the
    # part-of-speech tag and the Polarity feature as well.
    cupos = tree['nodes'][idchild][UPOS]
    cfeats = tree['nodes'][idchild][FEATS].split('|')
    if pdeprel != 'punct' and cdeprel == 'advmod' and cupos == 'PART' and 'Polarity=Neg' in cfeats:
        return
    # Punctuation should not depend on function words if it can be projectively
    # attached to a content word. But sometimes it cannot. Czech example:
    # "Budou - li však zbývat , ukončíme" (lit. "will - if however remain , we-stop")
    # "však" depends on "ukončíme" while "budou" and "li" depend nonprojectively
    # on "zbývat" (which depends on "ukončíme"). "Budou" is aux and "li" is mark.
    # Yet the hyphen must depend on one of them because any other attachment would
    # be non-projective. Here we assume that if the parent of a punctuation node
    # is attached nonprojectively, punctuation can be attached to it to avoid its
    # own nonprojectivity.
    gap = get_gap(idparent, tree)
    if gap and cdeprel == 'punct':
        return
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
        warn("'%s' not expected to have children (%s:%s:%s --> %s:%s:%s)" % (pdeprel, idparent, tree['nodes'][idparent][FORM], pdeprel, idchild, tree['nodes'][idchild][FORM], cdeprel), 'Syntax', nodelineno=tree['linenos'][idchild])
    ###!!! The pdeprel regex in the following test should probably include "det".
    ###!!! I forgot to add it well in advance of release 2.4, so I am leaving it
    ###!!! out for now, so that people don't have to deal with additional load
    ###!!! of errors.
    if re.match(r"^(aux|cop)$", pdeprel) and not re.match(r"^(goeswith|fixed|reparandum|conj|cc|punct)$", cdeprel):
        warn("'%s' not expected to have children (%s:%s:%s --> %s:%s:%s)" % (pdeprel, idparent, tree['nodes'][idparent][FORM], pdeprel, idchild, tree['nodes'][idchild][FORM], cdeprel), 'Syntax', nodelineno=tree['linenos'][idchild])
    if re.match(r"^(cc)$", pdeprel) and not re.match(r"^(goeswith|fixed|reparandum|conj|punct)$", cdeprel):
        warn("'%s' not expected to have children (%s:%s:%s --> %s:%s:%s)" % (pdeprel, idparent, tree['nodes'][idparent][FORM], pdeprel, idchild, tree['nodes'][idchild][FORM], cdeprel), 'Syntax', nodelineno=tree['linenos'][idchild])
    # Fixed expressions should not be nested, i.e., no chains of fixed relations.
    # As they are supposed to represent functional elements, they should not have
    # other dependents either, with the possible exception of conj.
    ###!!! We also allow a punct child, at least temporarily, because of fixed
    ###!!! expressions that have a hyphen in the middle (e.g. Russian "вперед-назад").
    ###!!! It would be better to keep these expressions as one token. But sometimes
    ###!!! the tokenizer is out of control of the UD data providers and it is not
    ###!!! practical to retokenize.
    elif pdeprel == 'fixed' and not re.match(r"^(goeswith|reparandum|conj|punct)$", cdeprel):
        warn("'%s' not expected to have children (%s:%s:%s --> %s:%s:%s)" % (pdeprel, idparent, tree['nodes'][idparent][FORM], pdeprel, idchild, tree['nodes'][idchild][FORM], cdeprel), 'Syntax', nodelineno=tree['linenos'][idchild])
    # Goeswith cannot have any children, not even another goeswith.
    elif pdeprel == 'goeswith':
        warn("'%s' not expected to have children (%s:%s:%s --> %s:%s:%s)" % (pdeprel, idparent, tree['nodes'][idparent][FORM], pdeprel, idchild, tree['nodes'][idchild][FORM], cdeprel), 'Syntax', nodelineno=tree['linenos'][idchild])
    # Punctuation can exceptionally have other punct children if an exclamation
    # mark is in brackets or quotes. It cannot have other children.
    elif pdeprel == 'punct' and cdeprel != 'punct':
        warn("'%s' not expected to have children (%s:%s:%s --> %s:%s:%s)" % (pdeprel, idparent, tree['nodes'][idparent][FORM], pdeprel, idchild, tree['nodes'][idchild][FORM], cdeprel), 'Syntax', nodelineno=tree['linenos'][idchild])

def validate_functional_leaves(id, tree):
    """
    Most of the time, function-word nodes should be leaves. This function
    checks for known exceptions and warns in the other cases.
    """
    # This is a level 3 test, we will check only the universal part of the relation.
    deprel = lspec2ud(tree['nodes'][id][DEPREL])
    if re.match(r"^(case|mark|cc|aux|cop|det|fixed|goeswith|punct)$", deprel):
        for idchild in tree['children'][id]:
            validate_deprel_pair(id, idchild, tree)

def collect_ancestors(id, tree, ancestors):
    """
    Usage: ancestors = collect_ancestors(nodeid, nodes, [])
    """
    pid = int(tree['nodes'][int(id)][HEAD])
    if pid == 0:
        ancestors.append(0)
        return ancestors
    if pid in ancestors:
        # Cycle has been reported on level 2. But we must jump out of it now.
        return ancestors
    ancestors.append(pid)
    return collect_ancestors(pid, tree, ancestors)

def get_caused_nonprojectivities(id, tree):
    """
    Checks whether a node is in a gap of a nonprojective edge. Report true only
    if the node's parent is not in the same gap. (We use this function to check
    that a punctuation node does not cause nonprojectivity. But if it has been
    dragged to the gap with a larger subtree, then we do not blame it.)

    tree ... dictionary:
      nodes ... array of word lines, i.e., lists of columns; mwt and empty nodes are skipped, indices equal to ids (nodes[0] is empty)
      children ... array of sets of children indices (numbers, not strings); indices to this array equal to ids (children[0] are the children of the root)
      linenos ... array of line numbers in the file, corresponding to nodes (needed in error messages)
    """
    iid = int(id) # just to be sure
    # We need to find all nodes that are not ancestors of this node and lie
    # on other side of this node than their parent. First get the set of
    # ancestors.
    ancestors = collect_ancestors(iid, tree, [])
    maxid = len(tree['nodes']) - 1
    # Get the lists of nodes to either side of id.
    # Do not look beyond the parent (if it is in the same gap, it is the parent's responsibility).
    pid = int(tree['nodes'][iid][HEAD])
    if pid < iid:
        left = range(pid + 1, iid) # ranges are open from the right (i.e. iid-1 is the last number)
        right = range(iid + 1, maxid + 1)
    else:
        left = range(1, iid)
        right = range(iid + 1, pid)
    # Exclude ancestors of id from the ranges.
    sancestors = set(ancestors)
    leftna = set(left) - sancestors
    rightna = set(right) - sancestors
    leftcross = [x for x in leftna if int(tree['nodes'][x][HEAD]) > iid]
    rightcross = [x for x in rightna if int(tree['nodes'][x][HEAD]) < iid]
    # Once again, exclude nonprojectivities that are caused by ancestors of id.
    if pid < iid:
        rightcross = [x for x in rightcross if int(tree['nodes'][x][HEAD]) > pid]
    else:
        leftcross = [x for x in leftcross if int(tree['nodes'][x][HEAD]) < pid]
    # Do not return just a boolean value. Return the nonprojective nodes so we can report them.
    return sorted(leftcross + rightcross)

def get_gap(id, tree):
    iid = int(id) # just to be sure
    pid = int(tree['nodes'][iid][HEAD])
    if iid < pid:
        rangebetween = range(iid + 1, pid - 1)
    else:
        rangebetween = range(pid + 1, iid - 1)
    gap = set()
    if rangebetween:
        projection = set()
        get_projection(pid, tree, projection)
        gap = set(rangebetween) - projection
    return gap

def validate_goeswith_span(id, tree):
    """
    The relation 'goeswith' is used to connect word parts that are separated
    by whitespace and should be one word instead. We assume that the relation
    goes left-to-right, which is checked elsewhere. Here we check that the
    nodes really were separated by whitespace. If there is another node in the
    middle, it must be also attached via 'goeswith'. The parameter id refers to
    the node whose goeswith children we test.
    """
    gwchildren = sorted([x for x in tree['children'][id] if lspec2ud(tree['nodes'][x][DEPREL]) == 'goeswith'])
    if gwchildren:
        gwlist = sorted([id] + gwchildren)
        gwrange = list(range(id, int(tree['nodes'][gwchildren[-1]][ID]) + 1))
        # All nodes between me and my last goeswith child should be goeswith too.
        if gwlist != gwrange:
            warn("Violation of guidelines: gaps in goeswith group %s != %s" % (str(gwlist), str(gwrange)), 'Syntax', nodelineno=tree['linenos'][id])
        # Non-last node in a goeswith range must have a space after itself.
        nospaceafter = [x for x in gwlist[:-1] if 'SpaceAfter=No' in tree['nodes'][x][MISC].split('|')]
        if nospaceafter:
            warn("'goeswith' cannot connect nodes that are not separated by whitespace", 'Syntax', nodelineno=tree['linenos'][id])

def validate_fixed_span(id, tree):
    """
    Like with goeswith, the fixed relation should not in general skip words that
    are not part of the fixed expression. Unlike goeswith however, there can be
    an intervening punctuation symbol.

    Update 2019-04-13: The rule that fixed expressions cannot be discontiguous
    has been challenged with examples from Swedish and Coptic, see
    https://github.com/UniversalDependencies/docs/issues/623
    For the moment, I am turning this test off. In the future, we should
    distinguish fatal errors from warnings and then this test will perhaps be
    just a warning.
    """
    return ###!!! temporarily turned off
    fxchildren = sorted([i for i in tree['children'][id] if lspec2ud(tree['nodes'][i][DEPREL]) == 'fixed'])
    if fxchildren:
        fxlist = sorted([id] + fxchildren)
        fxrange = list(range(id, int(tree['nodes'][fxchildren[-1]][ID]) + 1))
        # All nodes between me and my last fixed child should be either fixed or punct.
        fxdiff = set(fxrange) - set(fxlist)
        fxgap = [i for i in fxdiff if lspec2ud(tree['nodes'][i][DEPREL]) != 'punct']
        if fxgap:
            warn("Gaps in fixed expression %s" % str(fxlist), 'Syntax', nodelineno=tree['linenos'][id])

def validate_projective_punctuation(id, tree):
    """
    Punctuation is not supposed to cause nonprojectivity or to be attached
    nonprojectively.
    """
    # This is a level 3 test, we will check only the universal part of the relation.
    deprel = lspec2ud(tree['nodes'][id][DEPREL])
    if deprel == 'punct':
        nonprojnodes = get_caused_nonprojectivities(id, tree)
        if nonprojnodes:
            warn("Punctuation must not cause non-projectivity of nodes %s" % nonprojnodes, 'Syntax', nodeid=id, nodelineno=tree['linenos'][id])
        gap = get_gap(id, tree)
        if gap:
            warn("Punctuation must not be attached non-projectively over nodes %s" % sorted(gap), 'Syntax', nodeid=id, nodelineno=tree['linenos'][id])

def validate_annotation(tree):
    """
    Checks universally valid consequences of the annotation guidelines.
    """
    for node in tree['nodes']:
        id = int(node[ID])
        validate_upos_vs_deprel(id, tree)
        validate_left_to_right_relations(id, tree)
        validate_single_subject(id, tree)
        validate_functional_leaves(id, tree)
        validate_fixed_span(id, tree)
        validate_goeswith_span(id, tree)
        validate_projective_punctuation(id, tree)

def validate_enhanced_annotation(graph):
    """
    Checks universally valid consequences of the annotation guidelines in the
    enhanced representation. Currently tests only phenomena specific to the
    enhanced dependencies; however, we should also test things that are
    required in the basic dependencies (such as left-to-right coordination),
    unless it is obvious that in enhanced dependencies such things are legal.
    """
    # Enhanced dependencies should not contain the orphan relation.
    # However, all types of enhancements are optional and orphans are excluded
    # only if this treebank addresses gapping. We do not know it until we see
    # the first empty node.
    global line_of_first_empty_node
    global line_of_first_enhanced_orphan
    for id in graph.keys():
        if is_empty_node(graph[id]['cols']):
            if not line_of_first_empty_node:
                ###!!! This may not be exactly the first occurrence because the ids (keys) are not sorted.
                line_of_first_empty_node = graph[id]['lineno']
                # Empty node itself is not an error. Report it only for the first time
                # and only if an orphan occurred before it.
                if line_of_first_enhanced_orphan:
                    warn("Empty node means that we address gapping and there should be no orphans in the enhanced graph; but we saw one on line %s" % line_of_first_enhanced_orphan, 'Enhanced', nodelineno=graph[id]['lineno'])
        udeprels = set([lspec2ud(d) for h, d in graph[id]['deps']])
        if 'orphan' in udeprels:
            if not line_of_first_enhanced_orphan:
                ###!!! This may not be exactly the first occurrence because the ids (keys) are not sorted.
                line_of_first_enhanced_orphan = graph[id]['lineno']
            # If we have seen an empty node, then the orphan is an error.
            if  line_of_first_empty_node:
                warn("'orphan' not allowed in enhanced graph because we saw an empty node on line %s" % line_of_first_empty_node, 'Enhanced', nodelineno=graph[id]['lineno'])



#==============================================================================
# Level 4 tests. Language-specific formal tests. Now we can check in which
# words spaces are permitted, and which Feature=Value pairs are defined.
#==============================================================================

def validate_whitespace(cols, tag_sets):
    """
    Checks a single line for disallowed whitespace.
    Here we assume that all language-independent whitespace-related tests have
    already been done in validate_cols_level1(), so we only check for words
    with spaces that are explicitly allowed in a given language.
    """
    for col_idx in (FORM,LEMMA):
        if col_idx >= len(cols):
            break # this has been already reported in trees()
        if whitespace_re.match(cols[col_idx]) is not None:
            # Whitespace found - does it pass?
            for regex in tag_sets[TOKENSWSPACE]:
                if regex.fullmatch(cols[col_idx]):
                    break
            else:
                warn_on_missing_files.add('tokens_w_space')
                warn("'%s' in column %s is not on the list of exceptions allowed to contain whitespace (data/tokens_w_space.LANG files)."%(cols[col_idx], COLNAMES[col_idx]), 'Format')



#==============================================================================
# Level 5 tests. Annotation content vs. the guidelines, language-specific.
#==============================================================================

def validate_auxiliary_verbs(cols, children, nodes, line, lang):
    """
    Verifies that the UPOS tag AUX is used only with lemmas that are known to
    act as auxiliary verbs or particles in the given language.
    Parameters:
      'cols' ....... columns of the head node
      'children' ... list of ids
      'nodes' ...... dictionary where we can translate the node id into its
                     CoNLL-U columns
      'line' ....... line number of the node within the file
    """
    if cols[UPOS] == 'AUX' and cols[LEMMA] != '_':
        ###!!! In the future, lists like this one will be read from a file.
        auxdict = {
            # ChrisManning 2019/04: Allow 'get' as aux for get passive construction. And 'ought'
            'en':  ['be', 'have', 'do', 'will', 'would', 'may', 'might', 'can', 'could', 'shall', 'should', 'must', 'get', 'ought'],
            'nl':  ['zijn', 'hebben', 'worden', 'kunnen', 'mogen', 'zullen', 'moeten'],
            'de':  ['sein', 'haben', 'werden', 'dürfen', 'können', 'mögen', 'wollen', 'sollen', 'müssen'],
            'sv':  ['vara', 'ha', 'bli', 'komma', 'få', 'kunna', 'kunde', 'vilja', 'torde', 'behöva', 'böra', 'skola', 'måste', 'må', 'lär', 'do'], # Note: 'do' is English and is included because of code switching (titles of songs).
            'no':  ['være', 'vere', 'ha', 'verte', 'bli', 'få', 'kunne', 'ville', 'vilje', 'tørre', 'tore', 'burde', 'skulle', 'måtte'],
            'da':  ['være', 'have', 'blive', 'kunne', 'ville', 'turde', 'burde', 'skulle', 'måtte'],
            'fo':  ['vera', 'hava', 'verða', 'koma', 'fara', 'kunna'],
            # DZ: The Portuguese list is much longer than for the other Romance languages
            # and I suspect that maybe not all these verbs are auxiliary in the UD sense,
            # i.e. they neither construct a periphrastic tense, nor modality etc.
            # This should be discussed further and perhaps shortened (and in any
            # case, verbs that stay on the list must be explained in the Portuguese
            # documentation!)
            'pt':  ['ser', 'estar', 'haver', 'ter', 'andar', 'ir', 'poder', 'dever', 'continuar', 'passar', 'ameaçar',
                    'recomeçar', 'ficar', 'começar', 'voltar', 'parecer', 'acabar', 'deixar', 'vir','chegar', 'costumar', 'quer',
                    'querer','parar','procurar','interpretar','tender', 'viver','permitir','agredir','tornar', 'interpelar'],
            'gl':  ['ser', 'estar', 'haber', 'ter', 'ir', 'poder', 'querer', 'deber', 'vir', 'semellar', 'seguir', 'deixar', 'quedar', 'levar', 'acabar'],
            'es':  ['ser', 'estar', 'haber', 'tener', 'ir', 'poder', 'saber', 'querer', 'deber'],
            'ca':  ['ser', 'estar', 'haver', 'anar', 'poder', 'saber'],
            'fr':  ['être', 'avoir', 'faire', 'aller', 'pouvoir', 'savoir', 'vouloir', 'devoir'],
            'it':  ['essere', 'stare', 'avere', 'fare', 'andare', 'venire', 'potere', 'sapere', 'volere', 'dovere'],
            'ro':  ['fi', 'avea', 'putea', 'ști', 'vrea', 'trebui'],
            'cs':  ['být', 'bývat', 'bývávat'],
            'sk':  ['byť', 'bývať', 'by'],
            'hsb': ['być'],
            # zostać is for passive-action, być for passive-state
            # niech* are imperative markers (the only means in 3rd person; alternating with morphological imperative in 2nd person)
            # "to" is a copula and the Polish team insists that, "according to current analyses of Polish", it is a verb and it contributes the present tense feature to the predicate
            'pl':  ['być', 'bywać', 'by', 'zostać', 'zostawać', 'niech', 'niechaj', 'niechajże', 'to'],
            'uk':  ['бути', 'бувати', 'би', 'б'],
            'be':  ['быць', 'б'],
            'ru':  ['быть', 'бы', 'б'],
            # Hanne says that negation is fused with the verb in the present tense and
            # then the negative lemma is used. DZ: I believe that in the future
            # the negative forms should get the affirmative lemma + the feature Polarity=Neg,
            # as it is assumed in the guidelines and done in other languages.
            'orv': ['быти', 'не быти'],
            'sl':  ['biti'],
            'hr':  ['biti', 'htjeti'],
            'sr':  ['biti', 'hteti'],
            'bg':  ['съм', 'бъда', 'бивам', 'би', 'да', 'ще'],
            'cu':  ['бꙑти', 'не.бꙑти'],
            'lt':  ['būti'],
            'lv':  ['būt', 'kļūt', 'tikt', 'tapt'], # see the comment in the list of copulas
            'ga':  ['is'],
            'cy':  ['bod', 'yn', 'wedi', 'newydd', 'heb', 'ar', 'y', 'a', 'mi', 'fe'],
            'br':  ['bezañ'],
            'grc': ['εἰμί'],
            'el':  ['είμαι', 'έχω', 'πρέπει', 'θα', 'ας'],
            'hy':  ['եմ', 'լինել', 'տալ'],
            'kmr': ['bûn'],
            'fa':  ['است'],
            'sa':  ['अस्'],
            'hi':  ['है', 'था'],
            'ur':  ['ہے', 'تھا'],
            'mr':  ['असणे'],
            # Uralic languages.
            'fi':  ['olla', 'ei', 'voida', 'pitää', 'saattaa', 'täytyä', 'joutua', 'aikoa', 'taitaa', 'tarvita', 'mahtaa'],
            'et':  ['olema', 'ei', 'ära', 'võima', 'saama', 'pidama', 'näima', 'paistma', 'tunduma', 'tohtima'],
            # Afro-Asiatic languages.
            'mt':  ['kien', 'għad', 'għadx', 'ġa', 'se', 'ħa', 'qed'],
            # Niger-Congo languages.
            # DZ: Wolof auxiliaries taken from the documentation.
            'wo':  ['di', 'a', 'da', 'la', 'na', 'bu', 'ngi', 'woon', 'avoir', 'être'], # Note: 'avoir' and 'être' are French and are included because of code switching.
            'yo':  ['jẹ́', 'ní', 'kí', 'kìí', 'ń', 'ti', 'tí', 'yóò', 'máa', 'á', 'ó', 'yió', 'ìbá', 'ì', 'bá', 'lè', 'má', 'máà'],
            # Tupian languages.
            'gun': ['iko', "nda'ei", "nda'ipoi", 'ĩ']
        }
        lspecauxs = auxdict.get(lang, None)
        if lspecauxs and not cols[LEMMA] in lspecauxs:
            warn("'%s' is not an auxiliary verb in language [%s]" % (cols[LEMMA], lang), 'Morpho', nodeid=cols[ID], nodelineno=line)

def validate_copula_lemmas(cols, children, nodes, line, lang):
    """
    Verifies that the relation cop is used only with lemmas that are known to
    act as copulas in the given language.
    Parameters:
      'cols' ....... columns of the head node
      'children' ... list of ids
      'nodes' ...... dictionary where we can translate the node id into its
                     CoNLL-U columns
      'line' ....... line number of the node within the file
    """
    if cols[DEPREL] == 'cop' and cols[LEMMA] != '_':
        ###!!! In the future, lists like this one will be read from a file.
        # The UD guidelines narrow down the class of copulas to just the equivalent of "to be" (equivalence).
        # Other verbs that may be considered copulas by the traditional grammar (such as the equivalents of
        # "to become" or "to seem") are not copulas in UD; they head the nominal predicate, which is their xcomp.
        # Existential "to be" can be copula only if it is the same verb as in equivalence ("John is a teacher").
        # If the language uses two different verbs, then the existential one is not a copula.
        # Besides AUX, the copula can also be a pronoun in some languages.
        copdict = {
            'en':  ['be'],
            'af':  ['is', 'wees'],
            'nl':  ['zijn'],
            'de':  ['sein'],
            'sv':  ['vara'],
            'no':  ['være', 'vere'], # 'vere' is the Nynorsk variant
            'da':  ['være'],
            'fo':  ['vera'],
            'pcm': ['na', 'be'],
            # In Romance languages, both "ser" and "estar" qualify as copulas.
            'pt':  ['ser', 'estar'],
            'gl':  ['ser', 'estar'],
            'es':  ['ser', 'estar'],
            'ca':  ['ser', 'estar'],
            'fr':  ['être'],
            'it':  ['essere'],
            'ro':  ['fi'],
            'la':  ['sum'],
            # In Slavic languages, the iteratives are still variants of "to be", although they have a different lemma (derived from the main one).
            # In addition, Polish and Russian also have pronominal copulas ("to" = "this/that").
            'cs':  ['být', 'bývat', 'bývávat'],
            'sk':  ['byť', 'bývať'],
            'hsb': ['być'],
            'pl':  ['być', 'bywać', 'to'],
            'uk':  ['бути', 'бувати'],
            'be':  ['быць', 'гэта'],
            'ru':  ['быть', 'это'],
            # See above (AUX verbs) for the comment on affirmative vs. negative lemma.
            'orv': ['быти', 'не быти'],
            'sl':  ['biti'],
            'hr':  ['biti'],
            'sr':  ['biti'],
            'bg':  ['съм', 'бъда'],
            # See above (AUX verbs) for the comment on affirmative vs. negative lemma.
            'cu':  ['бꙑти', 'не.бꙑти'],
            'lt':  ['būti'],
            # Lauma says that all four should be copulas despite the fact that
            # kļūt and tapt correspond to English "to become", which is not
            # copula in UD. See also the discussion in
            # https://github.com/UniversalDependencies/docs/issues/622
            'lv':  ['būt', 'kļūt', 'tikt', 'tapt'],
            'ga':  ['is'],
            'cy':  ['bod'],
            'br':  ['bezañ'],
            'grc': ['εἰμί'],
            'el':  ['είμαι'],
            'hy':  ['եմ'],
            'kmr': ['bûn'],
            'fa':  ['است'],
            'sa':  ['अस्'],
            'hi':  ['है', 'था'],
            'ur':  ['ہے', 'تھا'],
            'mr':  ['असणे'],
            'eu':  ['izan', 'egon', 'ukan'],
            # Uralic languages.
            'fi':  ['olla'],
            'krl': ['olla'],
            'et':  ['olema'],
            'sme': ['leat'],
            # Jack says about Erzya:
            # The copula is represented by the independent copulas ульнемс (preterit) and улемс (non-past),
            # and the dependent morphology -оль (both preterit and non-past).
            # The neg арась occurs in locative/existential negation, and its
            # positive counterpart is realized in the three copulas above.
            'myv': ['улемс', 'ульнемс', 'оль', 'арась'],
            # Niko says about Komi:
            # Past tense copula is вӧвны, and in the future it is лоны, and both have a few frequentative forms.
            'kpv': ['лоны', 'лолыны', 'вӧвны', 'вӧвлыны', 'вӧвлывлыны'],
            'hu':  ['van'],
            # Altaic languages.
            'tr':  ['ol', 'i'],
            'kk':  ['бол', 'е'],
            'ug':  ['بول', 'ئى'],
            'bxr': ['бай', 'боло'],
            'ko':  ['이+라는'],
            'ja':  ['だ'],
            # Dravidian languages.
            'ta':  ['முயல்'],
            # Sino-Tibetan languages.
            'zh':  ['是'],
            'yue': ['係'],
            # Austro-Asiatic languages.
            'vi':  ['là'],
            # Austronesian languages.
            'id':  ['adalah'],
            'tl':  ['may'],
            # Afro-Asiatic languages.
            'mt':  ['kien'],
            'ar':  ['كَان', 'لَيس', 'لسنا', 'هُوَ'],
            'he':  ['היה', 'הוא', 'זה'],
            'am':  ['ን'],
            'cop': ['ⲡⲉ'],
            # Niger-Congo languages.
            'wo':  ['di', 'la', 'ngi', 'être'], # 'être' is French and is needed because of code switching.
            'yo':  ['jẹ́', 'ní'],
            # Tupian languages.
            # 'iko' is the normal copula, 'nda'ei' and 'nda'ipoi' are negative copulas and 'ĩ' is locative copula.
            'gun': ['iko', "nda'ei", "nda'ipoi", 'ĩ']
        }
        lspeccops = copdict.get(lang, None)
        if lspeccops and not cols[LEMMA] in lspeccops:
            warn("'%s' is not a copula in language [%s]" % (cols[LEMMA], lang), 'Syntax', nodeid=cols[ID], nodelineno=line)

def validate_lspec_annotation(tree, lang):
    """
    Checks language-specific consequences of the annotation guidelines.
    """
    ###!!! Building the information about the tree is repeated and has been done in the other functions before.
    ###!!! We should remember the information and not build it several times!
    global sentence_line # the line of the first token/word of the current tree (skipping comments!)
    node_line = sentence_line - 1
    lines = {} # node id -> line number of that node (for error messages)
    nodes = {} # node id -> columns of that node
    children = {} # node -> set of children
    for cols in tree:
        node_line += 1
        if not is_word(cols):
            continue
        if HEAD >= len(cols):
            # This error has been reported on lower levels, do not report it here.
            # Do not continue to check annotation if there are elementary flaws.
            return
        if cols[HEAD]=='_':
            # This error has been reported on lower levels, do not report it here.
            # Do not continue to check annotation if there are elementary flaws.
            return
        try:
            id_ = int(cols[ID])
        except ValueError:
            # This error has been reported on lower levels, do not report it here.
            # Do not continue to check annotation if there are elementary flaws.
            return
        try:
            head = int(cols[HEAD])
        except ValueError:
            # This error has been reported on lower levels, do not report it here.
            # Do not continue to check annotation if there are elementary flaws.
            return
        # Incrementally build the set of children of every node.
        lines.setdefault(cols[ID], node_line)
        nodes.setdefault(cols[ID], cols)
        children.setdefault(cols[HEAD], set()).add(cols[ID])
    for cols in tree:
        if not is_word(cols):
            continue
        myline = lines.get(cols[ID], sentence_line)
        mychildren = children.get(cols[ID], [])
        validate_auxiliary_verbs(cols, mychildren, nodes, myline, lang)
        validate_copula_lemmas(cols, mychildren, nodes, myline, lang)



#==============================================================================
# Main part.
#==============================================================================

def validate(inp, out, args, tag_sets, known_sent_ids):
    global tree_counter
    for comments, sentence in trees(inp, tag_sets, args):
        tree_counter += 1
        #the individual lines have been validated already in trees()
        #here go tests which are done on the whole tree
        validate_ID_sequence(sentence) # level 1
        validate_token_ranges(sentence) # level 1
        if args.level > 1:
            validate_sent_id(comments, known_sent_ids, args.lang) # level 2
            if args.check_tree_text:
                validate_text_meta(comments, sentence) # level 2
            validate_root(sentence) # level 2
            validate_ID_references(sentence) # level 2
            validate_deps(sentence) # level 2 and up
            tree = build_tree(sentence) # level 2 test: tree is single-rooted, connected, cycle-free
            egraph = build_egraph(sentence) # level 2 test: egraph is connected
            if tree:
                if args.level > 2:
                    validate_annotation(tree) # level 3
                    if args.level > 4:
                        validate_lspec_annotation(sentence, args.lang) # level 5
            else:
                warn("Skipping annotation tests because of corrupt tree structure", 'Format', lineno=False)
            if egraph:
                if args.level > 2:
                    validate_enhanced_annotation(egraph) # level 3
    validate_newlines(inp) # level 1

def load_file(f_name):
    res=set()
    with io.open(f_name, 'r', encoding='utf-8') as f:
        for line in f:
            line=line.strip()
            if not line or line.startswith('#'):
                continue
            res.add(line)
    return res

def load_set(f_name_ud,f_name_langspec,validate_langspec=False,validate_enhanced=False):
    """
    Loads a list of values from the two files, and returns their
    set. If f_name_langspec doesn't exist, loads nothing and returns
    None (ie this taglist is not checked for the given language). If f_name_langspec
    is None, only loads the UD one. This is probably only useful for CPOS which doesn't
    allow language-specific extensions. Set validate_langspec=True when loading basic dependencies.
    That way the language specific deps will be checked to be truly extensions of UD ones.
    Set validate_enhanced=True when loading enhanced dependencies. They will be checked to be
    truly extensions of universal relations, too; but a more relaxed regular expression will
    be checked because enhanced relations may contain stuff that is forbidden in the basic ones.
    """
    res=load_file(os.path.join(THISDIR,"data",f_name_ud))
    #Now res holds UD
    #Next load and optionally check the langspec extensions
    if f_name_langspec is not None and f_name_langspec!=f_name_ud:
        path_langspec = os.path.join(THISDIR,"data",f_name_langspec)
        if os.path.exists(path_langspec):
            global curr_fname
            curr_fname = path_langspec # so warn() does not fail on undefined curr_fname
            l_spec=load_file(path_langspec)
            for v in l_spec:
                if validate_enhanced:
                    # We are reading the list of language-specific dependency relations in the enhanced representation
                    # (i.e., the DEPS column, not DEPREL). Make sure that they match the regular expression that
                    # restricts enhanced dependencies.
                    if not edeprel_re.match(v):
                        warn("Spurious language-specific enhanced relation '%s' - it does not match the regular expression that restricts enhanced relations."%v, 'Syntax', lineno=False)
                        continue
                elif validate_langspec:
                    # We are reading the list of language-specific dependency relations in the basic representation
                    # (i.e., the DEPREL column, not DEPS). Make sure that they match the regular expression that
                    # restricts basic dependencies. (In particular, that they do not contain extensions allowed in
                    # enhanced dependencies, which should be listed in a separate file.)
                    if not re.match(r"^[a-z]+(:[a-z]+)?$", v):
                        warn("Spurious language-specific relation '%s' - in basic UD, it must match '^[a-z]+(:[a-z]+)?'."%v, 'Syntax', lineno=False)
                        continue
                if validate_langspec or validate_enhanced:
                    try:
                        parts=v.split(':')
                        if parts[0] not in res:
                            warn("Spurious language-specific relation '%s' - not an extension of any UD relation."%v, 'Syntax', lineno=False)
                            continue
                    except:
                        warn("Spurious language-specific relation '%s' - not an extension of any UD relation."%v, 'Syntax', lineno=False)
                        continue
                res.add(v)
    return res

if __name__=="__main__":
    opt_parser = argparse.ArgumentParser(description="CoNLL-U validation script")

    io_group=opt_parser.add_argument_group("Input / output options")
    io_group.add_argument('--quiet', dest="quiet", action="store_true", default=False, help='Do not print any error messages. Exit with 0 on pass, non-zero on fail.')
    io_group.add_argument('--max-err', action="store", type=int, default=20, help='How many errors to output before exiting? 0 for all. Default: %(default)d.')
    io_group.add_argument('input', nargs='*', help='Input file name(s), or "-" or nothing for standard input.')
    #I don't think output makes much sense now that we allow multiple inputs, so it will default to /dev/stdout
    #io_group.add_argument('output', nargs='', help='Output file name, or "-" or nothing for standard output.')

    list_group=opt_parser.add_argument_group("Tag sets","Options relevant to checking tag sets.")
    list_group.add_argument("--lang", action="store", required=True, default=None, help="Which langauge are we checking? If you specify this (as a two-letter code), the tags will be checked using the language-specific files in the data/ directory of the validator. It's also possible to use 'ud' for checking compliance with purely ud.")

    tree_group=opt_parser.add_argument_group("Tree constraints","Options for checking the validity of the tree.")
    tree_group.add_argument("--level", action="store", type=int, default=5, dest="level", help="Level 1: Test only CoNLL-U backbone. Level 2: UD format. Level 3: UD contents. Level 4: Language-specific labels. Level 5: Language-specific contents.")
    tree_group.add_argument("--multiple-roots", action="store_false", default=True, dest="single_root", help="Allow trees with several root words (single root required by default).")

    meta_group=opt_parser.add_argument_group("Metadata constraints","Options for checking the validity of tree metadata.")
    meta_group.add_argument("--no-tree-text", action="store_false", default=True, dest="check_tree_text", help="Do not test tree text. For internal use only, this test is required and on by default.")
    meta_group.add_argument("--no-space-after", action="store_false", default=True, dest="check_space_after", help="Do not test presence of SpaceAfter=No.")

    args = opt_parser.parse_args() #Parsed command-line arguments
    error_counter={} #Incremented by warn()  {key: error type value: its count}
    tree_counter=0

    # Level of validation
    if args.level < 1:
        print('Option --level must not be less than 1; changing from %d to 1' % args.level, file=sys.stderr)
        args.level = 1
    # No language-specific tests for levels 1-3
    # Anyways, any Feature=Value pair should be allowed at level 3 (because it may be language-specific),
    # and any word form or lemma can contain spaces (because language-specific guidelines may allow it).
    # We can also test language 'ud' on level 4; then it will require that no language-specific features are present.
    if args.level < 4:
        args.lang = 'ud'

    tagsets={XPOS:None,UPOS:None,FEATS:None,DEPREL:None,DEPS:None,TOKENSWSPACE:None} #sets of tags for every column that needs to be checked, plus (in v2) other sets, like the allowed tokens with space

    if args.lang:
        tagsets[DEPREL]=load_set("deprel.ud","deprel."+args.lang,validate_langspec=True)
        # All relations available in DEPREL are also allowed in DEPS.
        # In addition, there might be relations that are only allowed in DEPS.
        # One of them, "ref", is universal and we currently list it directly in the code here, instead of creating a file "edeprel.ud".
        tagsets[DEPS]=tagsets[DEPREL]|{"ref"}|load_set("deprel.ud","edeprel."+args.lang,validate_enhanced=True)
        tagsets[FEATS]=load_set("feat_val.ud","feat_val."+args.lang)
        tagsets[UPOS]=load_set("cpos.ud",None)
        tagsets[TOKENSWSPACE]=load_set("tokens_w_space.ud","tokens_w_space."+args.lang)
        tagsets[TOKENSWSPACE]=[re.compile(regex,re.U) for regex in tagsets[TOKENSWSPACE]] #...turn into compiled regular expressions

    out=sys.stdout # hard-coding - does this ever need to be anything else?

    try:
        known_sent_ids=set()
        open_files=[]
        if args.input==[]:
            args.input.append('-')
        for fname in args.input:
            if fname=='-':
                # Set PYTHONIOENCODING=utf-8 before starting Python. See https://docs.python.org/3/using/cmdline.html#envvar-PYTHONIOENCODING
                # Otherwise ANSI will be read in Windows and locale-dependent encoding will be used elsewhere.
                open_files.append(sys.stdin)
            else:
                open_files.append(io.open(fname, 'r', encoding='utf-8'))
        for curr_fname,inp in zip(args.input,open_files):
            validate(inp,out,args,tagsets,known_sent_ids)
    except:
        warn('Exception caught!', 'Format')
        # If the output is used in an HTML page, it must be properly escaped
        # because the traceback can contain e.g. "<module>". However, escaping
        # is beyond the goal of validation, which can be also run in a console.
        traceback.print_exc()
    if not error_counter:
        if not args.quiet:
            print('*** PASSED ***', file=sys.stderr)
        sys.exit(0)
    else:
        if not args.quiet:
            for k,v in sorted(error_counter.items()):
                print('%s errors: %d' %(k, v), file=sys.stderr)
            print('*** FAILED *** with %d errors'%sum(v for k,v in iter(error_counter.items())), file=sys.stderr)
        for f_name in sorted(warn_on_missing_files):
            filepath = os.path.join(THISDIR, 'data', f_name+'.'+args.lang)
            if not os.path.exists(filepath):
                print('The language-specific file %s does not exist.'%filepath, file=sys.stderr)
        sys.exit(1)
