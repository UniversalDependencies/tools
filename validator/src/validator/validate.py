import os
import collections
import regex as re
import unicodedata
import logging
import inspect

from validator.incident import Error, Warning, TestClass, IncidentType
import validator.utils as utils
import validator.compiled_regex as crex
from validator.validate_lib import State
from validator.logging_utils import setup_logging

logger = logging.getLogger(__name__)
setup_logging(logger)

def validate(paths, cfg_obj):
	'''
	Validates the input files.
	'''
	# TODO: complete docstring
	for path in paths:
		yield validate_file(path, cfg_obj)


def run_checks(checks, parameters, incidents, state):
	# print(checks)
	# input()
	for check in checks:
		dependencies = []
		if 'depends_on' in check:
			dependencies = check['depends_on']
		fun = globals()[check]
		# TODO: fix behavior
		if all(err.testid not in dependencies for err in incidents):
			incidents.extend([err.set_state(state) for err in fun(parameters)])
		else:
			incidents.append(
				Warning(
					level=0,
					testclass=TestClass.INTERNAL,
					testid='skipped-check',
					message=f"Check {check} not performed because of previous failures"
				)
			)


def validate_file(path, cfg_obj):
	state = State(current_file_name=os.path.basename(path))
	incidents = []
	# newline='' necessary because otherwise non-unix newlines are
	# automagically converted to \n, see
	# https://docs.python.org/3/library/functions.html#open
	with open(path, newline='') as fin:
		logger.info("opening file %s", path)
		block = []
		for block in utils.next_block(fin):
			state.current_line = block[0][0]

			run_checks(cfg_obj['block'], block, incidents, state)

			block = [(counter,line) for (counter,line) in block if line]

			for (counter,line) in block:
				state.current_line = counter # TODO: +1 when printing
				run_checks(cfg_obj['line'], line, incidents, state)
				# incidents.extend([err.set_state(state) for err in check_unicode_normalization(line)])
				# incidents.extend([err.set_state(state) for err in check_pseudo_empty_line(line)])

			# incidents.extend([err.set_state(state) for err in check_misplaced_comment(block)])
			# incidents.extend([err.set_state(state) for err in check_invalid_lines(block)])

			comments = [(counter,line) for (counter,line) in block if line[0] == "#"]
			tokens = [(counter,line) for (counter,line) in block if line[0].isdigit()]
			for (counter,line) in tokens:
				state.current_line = counter
				run_checks(cfg_obj['token_lines'], line, incidents, state)
				# incidents.extend([err.set_state(state) for err in check_columns_format(line)])
				# run_checks(cfg_obj['token_lines'], line, incidents, state)

			tokens = [(counter,line.split("\t")) for (counter,line) in tokens]
			# for (counter,line) in tokens:
				# state.current_line = counter
				# run_checks(cfg_obj['cols'], line, incidents, state)


		if len(block) == 1 and not block[0][1]:
			incidents.append(Error(
				testid='missing-empty-line',
				message='Missing empty line after the last sentence.'
				))

		run_checks(cfg_obj['file'], fin, incidents, state)
	return incidents

# TODO: docstring + check that test case for this exists
# checks for lines that are not empty, not comments and not tokens
def check_invalid_lines(block):
	incidents = []
	for (_,line) in block: # TODO: refactor as line-level check
		if line and not (line[0].isdigit() or line[0] == "#" or utils.is_whitespace(line)):
			incidents.append(Error(
				testid='invalid-line',
				message=f"Spurious line: '{line}'. All non-empty lines should start with a digit or the # character. The line will be excluded from further tests."
			))
	logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
	return incidents

# TODO: docstring + check that test case for this exists
def check_columns_format(text):
	incidents = []
	cols = text.split("\t")
	if not len(cols) == utils.COLCOUNT:
		incidents.append(Error(
			testid='number-of-columns',
			message=f'The line has {len(cols)} columns but {utils.COLCOUNT} are expected. The line will be excluded from further tests.'
		))
	else:
		for col_idx in range(utils.COLCOUNT):
			# Must never be empty
			if not cols[col_idx]:
				incidents.append(Error(
					testid='empty-column',
					message=f'Empty value in column {utils.COLNAMES[col_idx]}.'
				))
			else:
				# Must never have leading/trailing whitespace
				# ! what if a column only contains a whitespace character?
				if cols[col_idx][0].isspace():
					incidents.append(Error(
						testclass=TestClass.FORMAT,
						testid='leading-whitespace',
						message=f'Leading whitespace not allowed in column {utils.COLNAMES[col_idx]}.'
					))
				if cols[col_idx][-1].isspace():
					incidents.append(Error(
						testclass=TestClass.FORMAT,
						testid='trailing-whitespace',
						message=f'Trailing whitespace not allowed in column {utils.COLNAMES[col_idx]}.'
					))
				# Must never contain two consecutive whitespace characters
				if crex.ws2.search(cols[col_idx]):
					incidents.append(Error(
						testclass=TestClass.FORMAT,
						testid='repeated-whitespace',
						message=f'Two or more consecutive whitespace characters not allowed in column {utils.COLNAMES[col_idx]}.'
					))
		# Multi-word tokens may have whitespaces in MISC but not in FORM or LEMMA.
		# If it contains a space, it does not make sense to treat it as a MWT.
		if utils.is_multiword_token(cols):
			for col_idx in (utils.FORM, utils.LEMMA):
				if crex.ws.search(cols[col_idx]):
					incidents.append(Error(
						testclass=TestClass.FORMAT,
						testid='invalid-whitespace-mwt',
						message=f"White space not allowed in multi-word token '{cols[col_idx]}'. If it contains a space, it is not one surface token."
					))
		# These columns must not have whitespace.
		for col_idx in (utils.ID, utils.UPOS, utils.XPOS, utils.FEATS, utils.HEAD, utils.DEPREL, utils.DEPS):
			if crex.ws.search(cols[col_idx]):
				incidents.append(Error(
					testclass=TestClass.FORMAT,
					testid='invalid-whitespace',
					message=f"White space not allowed in column {utils.COLNAMES[col_idx]}: '{cols[col_idx]}'."
				))
		# We should also check the ID format (e.g., '1' is good, '01' is wrong).
		# Although it is checking just a single column, we will do it in
		# validate_id_sequence() because that function has the power to block
		# further tests, which could choke up on this.
		# ! so?
	logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
	return incidents

# TODO: docstring + check that test case for this exists
def check_misplaced_comment(block):
	incidents = []
	if len(block) > 1:
		max_comment = len(block)
		min_token = -1
		for (counter,line) in block:
			if line:
				if line[0] == "#":
					max_comment = counter
				else:
					if min_token == -1:
						min_token = counter

		if max_comment >= min_token:
			logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
			incidents.append(Error(
				testclass=TestClass.FORMAT,
				testid='misplaced-comment',
				message='Spurious comment line. Comments are only allo  wed before a sentence.'
				))
	logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
	return incidents

# TODO: docstring + check that test case for this exists
def check_extra_empty_line(block):
	incidents = []
	if len(block) == 1 and utils.is_whitespace(block[0][1]):
		logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
		incidents.append(Error(
			testclass=TestClass.FORMAT,
			testid='extra-empty-line',
			message='Spurious empty line. Only one empty line is expected after every sentence.'
		))
	logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
	return incidents

# TODO: docstring + check that test case for this exists
def check_pseudo_empty_line(text):
	incidents = []
	if utils.is_whitespace(text):
		incidents.append(Error(
					testclass=TestClass.FORMAT,
					testid='pseudo-empty-line',
					message='Spurious line that appears empty but is not; there are whitespace characters.'
				))
	logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
	return incidents

# TODO: docstring + check that test case for this exists
def check_unicode_normalization(text):
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
		TODO: update return docstring
	"""
	incidents = []
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
			testmessage = f"Unicode not normalized: {utils.COLNAMES[firsti]}.character[{firstj}] is {inpfirst}, should be {nfcfirst}."
		else:
			testmessage = f"Unicode not normalized: character[{firstj}] is {inpfirst}, should be {nfcfirst}."
		# TODO: what did this do?
		explanation_second = f" In this case, your next character is {inpsecond}." if inpsecond else ''
		incidents.append(Error(
			testclass=TestClass.UNICODE,
			testid='unicode-normalization',
			message=testmessage
		))
	logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
	return incidents

def check_mwt_empty_vals(cols):
	"""
	Checks that a multi-word token has _ empty values in all fields except MISC.
	This is required by UD guidelines although it is not a problem in general,
	therefore a level 2 test.

	Parameters
	----------
	cols : list
		The values of the columns on the current node / token line.
	"""
	incidents = []
	#! fix: is this a dependency?
	if not utils.is_multiword_token(cols):
		incidents = [Error(level=0,
					testclass=TestClass.INTERNAL,
					testid='internal-error')]
		logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
		return incidents
	# all columns except the first two (ID, FORM) and the last one (MISC)
	for col_idx in range(utils.LEMMA, utils.MISC):
		# Exception: The feature Typo=Yes may occur in FEATS of a multi-word token.
		if cols[col_idx] != '_' and (col_idx != utils.FEATS or cols[col_idx] not in ['Typo=Yes', '_']):
			incidents.append(
    				Error(level=2,
						testclass=TestClass.FORMAT,
						testid='mwt-nonempty-field',
						message=f"A multi-word token line must have '_' in the column {utils.COLNAMES[col_idx]}. Now: '{cols[col_idx]}'."
					)
			)

	logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
	return incidents

def check_empty_node_empty_vals(cols):
	"""
	Checks that an empty node has _ empty values in HEAD and DEPREL. This is
	required by UD guidelines but not necessarily by CoNLL-U, therefore
	a level 2 test.

	Parameters
	----------
	cols : list
		The values of the columns on the current node / token line.
	"""
	if not utils.is_empty_node(cols):
		incidents = [Error(level=0,
					testclass=TestClass.INTERNAL,
					testid='internal-error')]
		logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
		return incidents

	incidents = []
	for col_idx in (utils.HEAD, utils.DEPREL):
		if cols[col_idx]!= '_':
			# TODO: is this testid ok?
			incidents.append(
					Error(
					level=2,
					testclass=TestClass.FORMAT,
					testid='mwt-nonempty-field',
					message=f"An empty node must have '_' in the column {utils.COLNAMES[col_idx]}. Now: '{cols[col_idx]}'."
					)
			)
	logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
	return incidents

#! proposal: rename into check_deps_deprel_contraints, or also check UPOS format (not value)
#! I don't like that it relies on crex
def check_character_constraints(cols):
	"""
	Checks general constraints on valid characters, e.g. that UPOS
	only contains [A-Z].

	Parameters
	----------
	cols : list
		The values of the columns on the current node / token line.
	"""
	incidents = []
	if utils.is_multiword_token(cols):
		logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
		return incidents

	# Do not test the regular expression crex.upos here. We will test UPOS
	# directly against the list of known tags. That is a level 2 test, too.

	if utils.is_empty_node(cols) and cols[utils.DEPREL] == '_':
		logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
		return incidents

	if not crex.deprel.fullmatch(cols[utils.DEPREL]):
		incidents.append(
			Error(
				level=2,
				testclass=TestClass.SYNTAX,
				testid='invalid-deprel',
				message=f"Invalid DEPREL value '{cols[utils.DEPREL]}'. Only lowercase"
			)
		)

	try:
		deps = utils.deps_list(cols)
	except ValueError:
		incidents.append(
			Error(
					level=2,
					testclass=TestClass.ENHANCED,
					testid='invalid-deps',
					message=f"Failed to parse DEPS: '{cols[utils.DEPS]}'."
			)
		)
		logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
		return incidents

	for _, edep in deps:
		if not crex.edeprel.fullmatch(edep):
			incidents.append(
				Error(
					level=2,
					testclass=TestClass.ENHANCED,
					testid='invalid-edeprel',
					message=f"Invalid enhanced relation type: '{edep}' in '{cols[utils.DEPS]}'."
				)
			)
	logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
	return incidents

def check_upos(cols, specs):
	"""
	Checks that the UPOS field contains one of the 17 known tags.

	Parameters
	----------
	cols : list
		The values of the columns on the current node / token line.
	specs : UDSpecs
		The object containing specific information about the allowed values
	"""
	incidents = []
	#! added checking for mwt?
	if utils.is_multiword_token(cols) and cols[utils.UPOS] == '_':
		logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
		return incidents

	if utils.is_empty_node(cols) and cols[utils.UPOS] == '_':
		logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
		return incidents

	# Just in case, we still match UPOS against the regular expression that
	# checks general character constraints. However, the list of UPOS, loaded
	# from a JSON file, should conform to the regular expression.
	if not crex.upos.fullmatch(cols[utils.UPOS]) or cols[utils.UPOS] not in specs.upos:
		incidents.append(
			Error(
				level=2,
				testclass=TestClass.MORPHO,
				testid='unknown-upos',
				message=f"Unknown UPOS tag: '{cols[utils.UPOS]}'."
			)
		)

	logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
	return incidents

# ! proposal: rename into feature format or something alike
def check_features_level2(cols):
	"""
	Checks general constraints on feature-value format: Permitted characters in
	feature name and value, features must be sorted alphabetically, features
	cannot be repeated etc.

	Parameters
	----------
	cols : list
		The values of the columns on the current node / token line.

	"""
	incidents = []

	feats = cols[utils.FEATS]
	if feats == '_':
		return incidents

	# self.features_present(state) # TODO: do elsewhere

	feat_list = feats.split('|') #! why not a function in utils? Like the one that gets deps
	if [f.lower() for f in feat_list] != list(sorted(f.lower() for f in feat_list)):
		incidents.append(
			Error(
				level=2,
				testclass=TestClass.MORPHO,
				testid='unsorted-features',
				message=f"Morphological features must be alphabetically sorted: '{feats}'."
			)
		)

	# I'll gather the set of features here to check later that none is repeated.
	attr_set = set()
	# Level 2 tests character properties and canonical order but not that the f-v pair is known.

	for feat_val in feat_list:
		match = crex.featval.fullmatch(feat_val)
		if not match:
			incidents.append(
				Error(
					level=2,
					testclass=TestClass.MORPHO,
					testid='invalid-feature',
					message=f"Spurious morphological feature: '{feat_val}'. Should be of the form Feature=Value and must start with [A-Z] and only contain [A-Za-z0-9]."
				)
			)

			# to prevent misleading error "Repeated features are disallowed"
			attr_set.add(feat_val)

		else:
			# Check that the values are sorted as well
			attr = match.group(1)
			attr_set.add(attr)
			values = match.group(2).split(',')
			if len(values) != len(set(values)):
				incidents.append(
					Error(
						level=2,
						testclass=TestClass.MORPHO,
						testid='repeated-feature-value',
						message=f"Repeated feature values are disallowed: '{feats}' (error generated by feature '{attr}')"
					)
				)
			if [v.lower() for v in values] != sorted(v.lower() for v in values):
				incidents.append(
					Error(
						level=2,
						testclass=TestClass.MORPHO,
						testid='unsorted-feature-values',
						message=f"If a feature has multiple values, these must be sorted: '{feat_val}'"
					)
				)
			for v in values:
				if not crex.val.fullmatch(v): # ! can this ever be true? If val.fullmatch() does not match, than also featval.fullmatch() wouldn't
					incidents.append(
						Error(
							level=2,
							testclass=TestClass.MORPHO,
							testid='invalid-feature-value',
							message=f"Spurious value '{v}' in '{feat_val}'. Must start with [A-Z0-9] and only contain [A-Za-z0-9]."
						)
					)

	if len(attr_set) != len(feat_list):
		incidents.append(
			Error(
				level=2,
				testclass=TestClass.MORPHO,
				testid='repeated-feature',
				message=f"Repeated features are disallowed: '{feats}'."
			)
		)

	# Subsequent higher-level tests could fail if a feature is not in the
	# Feature=Value format. If that happens, we return False and the caller
	# can skip the more fragile tests.
	# TODO: the engine has to know that 'invalid-feature' is a testid that prevents from further testing
	return incidents

# TODO: write tests
def check_deps(cols):
	"""
	Validates that DEPS is correctly formatted and that there are no
	self-loops in DEPS (longer cycles are allowed in enhanced graphs but
	self-loops are not).

	This function must be run on raw DEPS before it is fed into Udapi because
	it checks the order of relations, which is not guaranteed to be preserved
	in Udapi. On the other hand, we assume that it is run after
	check_id_references() and only if DEPS is parsable and the head indices
	in it are OK.

	Parameters
	----------
	cols : list
		The values of the columns on the current node / token line.
	"""

	# TODO: the engine must assume that it is run after check_id_references() and only if DEPS is parsable and the head indices in it are OK.

	incidents = []
	if not (utils.is_word(cols) or utils.is_empty_node(cols)):
		logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
		return incidents

	# TODO: move elsewhere
	# Remember whether there is at least one difference between the basic
	# tree and the enhanced graph in the entire dataset.
	#if cols[utils.DEPS] != '_' and cols[utils.DEPS] != cols[utils.HEAD]+':'+cols[utils.DEPREL]:
	#	state.seen_enhancement = line

	# We already know that the contents of DEPS is parsable (deps_list() was
	# first called from check_id_references() and the head indices are OK).
	deps = utils.deps_list(cols)
	###!!! Float will not work if there are 10 empty nodes between the same two
	###!!! regular nodes. '1.10' is not equivalent to '1.1'.
	# ORIGINAL VERSION: heads = [float(h) for h, d in deps]

	# NEW VERSION:
	#! maybe do this only if [0-9]+.[1-9][0-9]+ is present somewhere?
	heads = [h for h, _ in deps]
	floating_len = []
	for h in heads:
		if "." in h:
			floating_len.append(len(h))
		else:
			floating_len.append(0)
	hacked_heads = [h+'00000001' for i, h in enumerate(heads) if floating_len[i]]
	hacked_heads_sorted = sorted(zip(hacked_heads, floating_len), key= lambda x: float(x[0]))
	hacked_heads_restored = []
	for x, y in hacked_heads_sorted:
		if y:
			hacked_heads_sorted.append(x[:y])
		else:
			hacked_heads_sorted.append(x)

	# if heads != sorted(heads): # sort strings keeping the integer-like ordering
	if heads != hacked_heads_restored:
		incidents.append(
			Error(
				level=2,
				testclass=TestClass.FORMAT,
				testid='unsorted-deps',
				message=f"DEPS not sorted by head index: '{cols[utils.DEPS]}'"
			)
		)
	else:
		lasth = None
		lastd = None
		for h, d in deps:
			if h == lasth:
				if d < lastd:
					incidents.append(
						Error(
							level=2,
							testclass=TestClass.FORMAT,
							testid='unsorted-deps-2',
							message=f"DEPS pointing to head '{h}' not sorted by relation type: '{cols[utils.DEPS]}'"
						)
					)
				elif d == lastd:
					incidents.append(
						Error(
							level=2,
							testclass=TestClass.FORMAT,
							testid='unsorted-deps',
							message=f"DEPS contain multiple instances of the same relation '{h}:{d}'"
						)
					)
			lasth = h
			lastd = d

	try:
		id_ = float(cols[utils.ID])
	except ValueError:
		# This error has been reported previously.
		# TODO: check, before there was just a return
		return incidents

	if id_ in heads:
		incidents.append(
			Error(
				level=2,
				testclass=TestClass.ENHANCED,
				testid='deps-self-loop',
				message=f"Self-loop in DEPS for '{cols[utils.ID]}'"
			)
		)

	logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
	return incidents


def check_misc(cols):
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
	"""

	incidents = []

	if cols[utils.MISC] == '_':
		return incidents

	misc = [ma.split('=', 1) for ma in cols[utils.MISC].split('|')] #! why not using a function in utils? Just like the one for features
	mamap = collections.defaultdict(int)
	for ma in misc:
		if ma[0] == '':
			if len(ma) == 1:
				incidents.append(
					Warning(
						level=2,
						testid='empty-misc',
						message="Empty attribute in MISC; possible misinterpreted vertical bar?"
					)
				)
			else:
				incidents.append(
					Warning(
						level=2,
						testid='empty-misc-key',
						message=f"Empty MISC attribute name in '{ma[0]}={ma[1]}'."
					)
				)
		# We do not warn about MISC items that do not contain '='.
		# But the remaining error messages below assume that ma[1] exists.
		if len(ma) == 1:
			ma.append('')
		if re.match(r"^\s", ma[0]) or \
			re.match(r"\s$", ma[0]) or \
			re.match(r"^\s", ma[1]) or \
			re.search(r"\s$", ma[1]):
			incidents.append(Error(
				level=2,
				testid='misc-extra-space',
				message=f"MISC attribute: leading or trailing extra space in '{'='.join(ma)}'."
			)
			)

		if re.match(r"^(SpaceAfter|Lang|Translit|LTranslit|Gloss|LId|LDeriv)$", ma[0]):
			mamap[ma[0]] += 1
		elif re.match(r"^\s*(spaceafter|lang|translit|ltranslit|gloss|lid|lderiv)\s*$", ma[0], re.IGNORECASE):
			incidents.append(
				Warning(
					level=2,
					testid='misc-attr-typo',
					message=f"Possible typo (case or spaces) in MISC attribute '{'='.join(ma)}'."
				)

			)

	for ma in mamap:
		if mamap[ma] > 1:
			incidents.append(
				Error(
					level=2,
					testclass=TestClass.FORMAT,
					testid='repeated-misc',
					message=f"MISC attribute '{ma}' not supposed to occur twice"
				)
			)

	logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
	return incidents

# TODO: write tests
def check_deps_all_or_none(sentence, seen_enhanced_graph):
	"""
	Takes the list of non-comment lines (line = list of columns) describing
	a sentence. Checks that enhanced dependencies are present if they were
	present at another sentence, and absent if they were absent at another
	sentence.
	"""
	incidents = []
	egraph_exists = False # enhanced deps are optional
	for cols in sentence:
		# if utils.is_multiword_token(cols):
		# 	continue
		if not utils.is_multiword_token(cols) and (utils.is_empty_node(cols) or cols[utils.DEPS] != '_'):
			egraph_exists = True

	# We are currently testing the existence of enhanced graphs separately for each sentence.
	# However, we should not allow that one sentence has a connected egraph and another
	# has no enhanced dependencies. Such inconsistency could come as a nasty surprise
	# to the users.
	if egraph_exists:
		if not seen_enhanced_graph:
			# TODO: do elsewhere
			# state.seen_enhanced_graph = state.sentence_line
			incidents.append(
				Error(
					testclass=TestClass.ENHANCED,
					testid='edeps-only-sometimes',
					message=f"Enhanced graph must be empty because we saw empty DEPS earlier."
				)
			)
			#! we should add something to this message in the engine where we have access to the state:
			#on line {state.seen_tree_without_enhanced_graph}

	else:
#		if not state.seen_tree_without_enhanced_graph:
			# TODO: do elsewhere
#  			state.seen_tree_without_enhanced_graph = state.sentence_line
			if seen_enhanced_graph:
				incidents.append(
					Error(
						level=2,
						testid='edeps-only-sometimes',
						message=f"Enhanced graph cannot be empty because we saw non-empty DEPS earlier."
					)
				)
				#! we should add something to this message in the engine where we have access to the state:
				#  on line {state.seen_enhanced_graph}

	return incidents

def check_newlines(inp):
	"""
	Checks that the input file consistently uses linux-style newlines (LF only,
	not CR LF like in Windows). To be run on the input file handle after the
	whole input has been read.

	This check is universal and not configurable.
	"""
	incidents = []
	if inp.newlines and inp.newlines != '\n':
		incidents.append(Error(
				level=1,
				testclass=TestClass.FORMAT,
				testid='non-unix-newline',
				message='Only the unix-style LF line terminator is allowed.'
			))

	logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
	return incidents


# TODO: move elsewhere
# # If a multi-word token has Typo=Yes, its component words must not have it.
# 			# We must remember the span of the MWT and check it in check_features_level4().
# 			m = crex.mwtid.fullmatch(cols[ID])
# 			state.mwt_typo_span_end = m.group(2)

def check_token_ranges(sentence):
	"""
	Checks that the word ranges for multiword tokens are valid.

	Parameters
	----------
	sentence : list
		A list of lists representing a sentence in tabular format.

	returns
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
		# This is tested in check_id_sequence().
		if covered & set(range(start, end+1)):
			incidents.append(Error(
				testid='overlapping-word-intervals',
				message=f'Range overlaps with others: {cols[utils.ID]}'))
		covered |= set(range(start, end+1))
	logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
	return incidents

def check_id_sequence(sentence):
	"""
	Validates that the ID sequence is correctly formed.
	If this function returns an nonempty list, subsequent tests should not be run.

	Parameters
	----------
	sentence : list
		A list of lists representing a sentence in tabular format.

	returns
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

		# ! looks like a duplicate of check_id_sequence
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
	logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
	return incidents

def check_id_references(sentence):
	"""
	Verifies that HEAD and DEPS reference existing IDs. If this function
	returns a nonempty list, most of the other tests should be skipped for the current
	sentence (in particular anything that considers the tree structure).

	Parameters
	----------
	sentence : list
		A list of lists representing a sentence in tabular format.

	logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
	returns
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
	logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
	return incidents

def check_tree(sentence, node_line, single_root):
	"""
	Performs basic validation of the tree structure (without UDApi).

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

	logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
	returns
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
	logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
	return incidents

def check_sent_id(comments, allow_slash, known_sent_ids):
	"""
	Checks that sentence id exists, is well-formed and unique.

	Parameters
	----------
	comments : list
		A list of comments, represented as strings.
	allow_slash : bool
		Whether exactly one "/" character is allowed (this is reserved for
		parallel treebanks). This parameter replaces lang, which was used to
		allow slashes when equal to "ud".
	known_sent_ids : set
		The set of previously encountered sentence IDs.

	logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
	returns
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
		if sid.count('/') > 1 or (sid.count('/') == 1 and allow_slash):
			incidents.append(Error(
				testclass=TestClass.METADATA,
				level=2,
				testid='slash-in-sent-id',
				message=f"The forward slash is reserved for special use in parallel treebanks: '{sid}'"
			))
		#state.known_sent_ids.add(sid) # TODO: move this to the engine
	logger.debug("%d incidents occurred in %s", len(incidents), inspect.stack()[0][3])
	return incidents

def check_text_meta(comments, tree, spaceafterno_in_effect):
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

def check_deprels_level2(node, deprels, lang):
	"""
	Checks that a dependency relation label is listed as approved in the given
	language. As a language-specific test, this function generally belongs to
	level 4, but it can be also used on levels 2 and 3, in which case it will
	check only the main dependency type and ignore any subtypes.

	Parameters
	----------
	node : udapi.core.node.Node object
		The node whose incoming relation will be validated.
	deps: TODO
	lang: TODO
	"""

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

	incidents = []

	naltlang = utils.get_alt_language(node)

	# The basic relation should be tested on regular nodes but not on empty nodes.
	if not node.is_empty():
		paltlang = utils.get_alt_language(node.parent)

		  # Test only the universal part if testing at universal level.
		deprel = node.udeprel
		check = False
		if deprel in deprels[lang] and deprels[lang][deprel]["permitted"]:
			check = True

		if naltlang != None and naltlang != lang and naltlang == paltlang:
			if deprel in deprels[naltlang] and deprels[lang][naltlang]["permitted"]:
				check = True

		if not check:
			incidents.append(
				Error(
					level=2,
					testclass=TestClass.SYNTAX,
					testid='unknown-deprel',
					message=f"Unknown DEPREL label: '{deprel}'"
				)
			)
	# If there are enhanced dependencies, test their deprels, too.
	# We already know that the contents of DEPS is parsable (deps_list() was
	# first called from validate_id_references() and the head indices are OK).
	# The order of enhanced dependencies was already checked in validate_deps().
	# Incident.default_testclass = 'Enhanced'
	if str(node.deps) != '_':
		# main_edeprelset = self.specs.get_edeprel_for_language(mainlang)
		# alt_edeprelset = self.specs.get_edeprel_for_language(naltlang)
		for edep in node.deps:
			parent = edep['parent']
			deprel = utils.lspec2ud(edep['deprel'])
			paltlang = utils.get_alt_language(parent)

			check = False
			if deprel in deprels[lang] and deprels[lang][deprel]["permitted"]:
				check = True

			if naltlang != None and naltlang != lang and naltlang == paltlang:
				if deprel in deprels[naltlang] and deprels[lang][naltlang]["permitted"]:
					check = True

			if not check:
				incidents.append(
					Error(
						level=2,
						testclass=TestClass.ENHANCED,
						testid='unknown-edeprel',
						message=f"Unknown enhanced relation type '{deprel}' in '{parent.ord}:{deprel}'"
					)
				)

	return incidents

def check_deprels_level4(node, deprels, lang):
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
	# Incident.default_lineno = line
	# Incident.default_level = 4
	# Incident.default_testclass = 'Syntax'

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

	incidents = []

	naltlang = utils.get_alt_language(node)

	# The basic relation should be tested on regular nodes but not on empty nodes.
	if not node.is_empty():
		paltlang = utils.get_alt_language(node.parent)

		  # main_deprelset = self.specs.get_deprel_for_language(mainlang)
		# alt_deprelset = set()
		# if naltlang != None and naltlang != mainlang and naltlang == paltlang:
			# alt_deprelset = self.specs.get_deprel_for_language(naltlang)

		  # Test only the universal part if testing at universal level.
		deprel = node.deprel

		check = False
		if deprel in deprels[lang] and deprels[lang][deprel]["permitted"]:
			check = True

		if naltlang != None and naltlang != lang and naltlang == paltlang:
			if deprel in deprels[naltlang] and deprels[lang][naltlang]["permitted"]:
				check = True

		if not check:
			incidents.append(
				Error(
					level=4,
					testclass=TestClass.SYNTAX,
					testid='unknown-deprel',
					message=f"Unknown DEPREL label: '{deprel}'"
				)
			)
	# If there are enhanced dependencies, test their deprels, too.
	# We already know that the contents of DEPS is parsable (deps_list() was
	# first called from validate_id_references() and the head indices are OK).
	# The order of enhanced dependencies was already checked in validate_deps().
	# Incident.default_testclass = 'Enhanced'
	if str(node.deps) != '_':
		# main_edeprelset = self.specs.get_edeprel_for_language(mainlang)
		# alt_edeprelset = self.specs.get_edeprel_for_language(naltlang)
		for edep in node.deps:
			parent = edep['parent']
			deprel = edep['deprel']
			paltlang = utils.get_alt_language(parent)

			check = False
			if deprel in deprels[lang] and deprels[lang][deprel]["permitted"]:
				check = True

			if naltlang != None and naltlang != lang and naltlang == paltlang:
				if deprel in deprels[naltlang] and deprels[lang][naltlang]["permitted"]:
					check = True

			if not check:
				incidents.append(
					Error(
						level=4,
						testclass=TestClass.ENHANCED,
						testid='unknown-edeprel',
						message=f"Unknown enhanced relation type '{deprel}' in '{parent.ord}:{deprel}'"
					)
				)

	return incidents

def check_root(node):
	"""
	Checks that DEPREL is "root" iff HEAD is 0.

	Parameters
	----------
	node : udapi.core.node.Node object
		The node whose incoming relation will be validated. This function
		operates on both regular and empty nodes. Make sure to call it for
		empty nodes, too!

	returns
	-------
	incidents : list
		A list of Incidents (empty if validation is successful).
	"""
	incidents = []
	if not node.is_empty():
		if node.parent.ord == 0 and node.udeprel != 'root':
			incidents.append(Error(
				level=2,
				testclass=TestClass.SYNTAX,
				testid='0-is-not-root',
				message="DEPREL must be 'root' if HEAD is 0."
			))
		if node.parent.ord != 0 and node.udeprel == 'root':
			incidents.append(Error(
				level=2,
				testclass=TestClass.SYNTAX,
				testid='root-is-not-0',
				message="DEPREL cannot be 'root' if HEAD is not 0."
			))
	# In the enhanced graph, test both regular and empty roots.
	for edep in node.deps:
		if edep['parent'].ord == 0 and utils.lspec2ud(edep['deprel']) != 'root':
			incidents.append(Error(
				level=2,
				testclass=TestClass.SYNTAX,
				testid='enhanced-0-is-not-root',
				message="Enhanced relation type must be 'root' if head is 0."
			))
		if edep['parent'].ord != 0 and utils.lspec2ud(edep['deprel']) == 'root':
			incidents.append(Error(
				level=2,
				testclass=TestClass.SYNTAX,
				testid='enhanced-root-is-not-0',
				message="Enhanced relation type cannot be 'root' if head is not 0."
			))
	return incidents

def check_enhanced_orphan(node, seen_empty_node, seen_enhanced_orphan):
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

	returns
	-------
	incidents : list
		A list of Incidents (empty if validation is successful).
	"""
	incidents = []
	# Enhanced dependencies should not contain the orphan relation.
	# However, all types of enhancements are optional and orphans are excluded
	# only if this treebank addresses gapping. We do not know it until we see
	# the first empty node.
	if str(node.deps) == '_':
		return
	if node.is_empty():
		if not seen_empty_node:
			#TODO: outside of this function: state.seen_empty_node = line
			# Empty node itself is not an error. Report it only for the first time
			# and only if an orphan occurred before it.
			if seen_enhanced_orphan:
				incidents.append(Error(
					level=3,
					testclass=TestClass.ENHANCED,
					nodeid=node.ord,
					testid='empty-node-after-eorphan',
					message=f"Empty node means that we address gapping and there should be no orphans in the enhanced graph; but we saw one on line {state.seen_enhanced_orphan}"
				))
	udeprels = set([utils.lspec2ud(edep['deprel']) for edep in node.deps])
	if 'orphan' in udeprels:
		if not seen_enhanced_orphan:
			pass
			# TODO: outside of this function: state.seen_enhanced_orphan = line
		# If we have seen an empty node, then the orphan is an error.
		if seen_empty_node:
			incidents.append(Error(
				level=3,
				testclass=TestClass.ENHANCED,
				nodeid=node.ord,
				testid='eorphan-after-empty-node',
				message=f"'orphan' not allowed in enhanced graph because we saw an empty node on line {state.seen_empty_node}"
			))
	return incidents

def check_words_with_spaces(node, lang, specs):
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
	specs : UDSpecs
		The object containing specific information about the allowed values

	returns
	-------
	incidents : list
		A list of Incidents (empty if validation is successful).
	"""
	incidents = []
	# List of permitted words with spaces is language-specific.
	# The current token may be in a different language due to code switching.
	tospacedata = specs.get_tospace_for_language(lang)
	altlang = utils.get_alt_language(node)
	if altlang:
		lang = altlang
		tospacedata = specs.get_tospace_for_language(altlang)
	for column in ('FORM', 'LEMMA'):
		word = node.form if column == 'FORM' else node.lemma
		# Is there whitespace in the word?
		if crex.ws.search(word):
			# Whitespace found. Does the word pass the regular expression that defines permitted words with spaces in this language?
			if tospacedata:
				# For the purpose of this test, NO-BREAK SPACE is equal to SPACE.
				string_to_test = re.sub(r'\xA0', ' ', word)
				if not tospacedata[1].fullmatch(string_to_test):
					incidents.append(Error(
						level=4,
						testclass=TestClass.FORMAT,
						nodeid=node.ord,
						testid='invalid-word-with-space',
						message=f"'{word}' in column {column} is not on the list of exceptions allowed to contain whitespace.",
					))
			else:
				incidents.append(Error(
					level=4,
					testclass=TestClass.FORMAT,
					nodeid=node.ord,
					testid='invalid-word-with-space',
					message=f"'{word}' in column {column} is not on the list of exceptions allowed to contain whitespace.",
				))
	return incidents

def validate_features_level4(node, lang, specs, mwt_typo_span_end):
	"""
	Checks that a feature-value pair is listed as approved. Feature lists are
	language 'ud'. # ?

	Parameters
	----------
	node : udapi.core.node.Node object
		The node to be validated.
	lang : str
		Code of the main language of the corpus.
	specs : UDSpecs
		The object containing specific information about the allowed values
	mwt_typo_span_end : TODO: add type and description

	returns
	-------
	incidents : list
		A list of Incidents (empty if validation is successful).
	"""
	incidents = []
	if str(node.feats) == '_':
		return True
	# List of permitted features is language-specific.
	# The current token may be in a different language due to code switching.
	default_lang = lang
	default_featset = featset = specs.get_feats_for_language(lang)
	altlang = utils.get_alt_language(node)
	if altlang:
		lang = altlang
		featset = specs.get_feats_for_language(altlang)
	for f in node.feats:
		values = node.feats[f].split(',')
		for v in values:
			# Level 2 tested character properties and canonical order but not that the f-v pair is known.
			# Level 4 also checks whether the feature value is on the list.
			# If only universal feature-value pairs are allowed, test on level 4 with lang='ud'.
			# The feature Typo=Yes is the only feature allowed on a multi-word token line.
			# If it occurs there, it cannot be duplicated on the lines of the component words.
			if f == 'Typo' and mwt_typo_span_end and node.ord <= mwt_typo_span_end:
				incidents.append(Error(
					level=4,
					testclass=TestClass.MORPHO,
					nodeid=node.ord,
					testid='mwt-typo-repeated-at-word',
					message="Feature Typo cannot occur at a word if it already occurred at the corresponding multi-word token."
				))
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
					incidents.append(Error(
					level=4,
					testclass=TestClass.MORPHO,
						nodeid=node.ord,
						testid='feature-unknown',
						message=f"Feature {f} is not documented for language [{effective_lang}] ('{utils.formtl(node)}').",
					))
				else:
					lfrecord = effective_featset[f]
					if lfrecord['permitted'] == 0:
						incidents.append(Error(
							level=4,
							testclass=TestClass.MORPHO,
							nodeid=node.ord,
							testid='feature-not-permitted',
							message=f"Feature {f} is not permitted in language [{effective_lang}] ('{utils.formtl(node)}').",
						))
					else:
						values = lfrecord['uvalues'] + lfrecord['lvalues'] + lfrecord['unused_uvalues'] + lfrecord['unused_lvalues']
						if not v in values:
							incidents.append(Error(
								level=4,
								testclass=TestClass.MORPHO,
								nodeid=node.ord,
								testid='feature-value-unknown',
								message=f"Value {v} is not documented for feature {f} in language [{effective_lang}] ('{utils.formtl(node)}').",
							))
						elif not node.upos in lfrecord['byupos']:
							incidents.append(Error(
								level=4,
								testclass=TestClass.MORPHO,
								nodeid=node.ord,
								testid='feature-upos-not-permitted',
								message=f"Feature {f} is not permitted with UPOS {node.upos} in language [{effective_lang}] ('{utils.formtl(node)}').",
							))
						elif not v in lfrecord['byupos'][node.upos] or lfrecord['byupos'][node.upos][v]==0:
							incidents.append(Error(
								level=4,
								testclass=TestClass.MORPHO,
								nodeid=node.ord,
								testid='feature-value-upos-not-permitted',
								message=f"Value {v} of feature {f} is not permitted with UPOS {node.upos} in language [{effective_lang}] ('{utils.formtl(node)}').",
							))
	# TODO: (outside of this function)
	#if mwt_typo_span_end and int(mwt_typo_span_end) <= int(node.ord):
	#	state.mwt_typo_span_end = None

	return incidents

# ! proposal: rename to validate_auxiliaries, since some ar particles as per
# the docstring below
def validate_auxiliary_verbs(node, lang, specs):
	"""
	Verifies that the UPOS tag AUX is used only with lemmas that are known to
	act as auxiliary verbs or particles in the given language.


	Parameters
	----------
	node : udapi.core.node.Node object
		The node to be validated.
	lang : str
		Code of the main language of the corpus.
	specs : UDSpecs
		The object containing specific information about the allowed values

	returns
	-------
	incidents : list
		A list of Incidents (empty if validation is successful).
	"""
	incidents = []
	if node.upos == 'AUX' and node.lemma != '_':
		altlang = utils.get_alt_language(node)
		if altlang:
			lang = altlang
		auxlist = specs.get_aux_for_language(lang)
		if not auxlist or not node.lemma in auxlist:
			incidents.append(Error(
				nodeid=node.ord,
				level=5,
				testclass=TestClass.MORPHO,
				testid='aux-lemma',
				message=f"'{node.lemma}' is not an auxiliary in language [{lang}]",
			))
	return incidents

def validate_copula_lemmas(node, lang, specs):
	"""
	Verifies that the relation cop is used only with lemmas that are known to
	act as copulas in the given language.

	Parameters
	----------
	node : udapi.core.node.Node object
		The node to be validated.
	lang : str
		Code of the main language of the corpus.
	specs : UDSpecs
		The object containing specific information about the allowed values

	returns
	-------
	incidents : list
		A list of Incidents (empty if validation is successful).
	"""
	incidents = []
	if node.udeprel == 'cop' and node.lemma != '_':
		altlang = utils.get_alt_language(node)
		if altlang:
			lang = altlang
		coplist = specs.get_cop_for_language(lang)
		if not coplist or not node.lemma in coplist:
			incidents.append(Error(
				nodeid=node.ord,
				level=5,
				testclass=TestClass.SYNTAX,
				testid='cop-lemma',
				message=f"'{node.lemma}' is not a copula in language [{lang}]",
			))
	return incidents

# ! proposal: remove entirely and put in tree block of the validator, or at
# least rename to check_universal_guidelines (this function simply groups a
# few checks together, and the tree section of the engine kinda does the same
# thing), not to mention that removing this function spares us passing line
# numbers around
def validate_annotation(tree, linenos):
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

	returns
	-------
	incidents : list
		A list of Incidents (empty if validation is successful).
	"""
	incidents = []
	nodes = tree.descendants
	for node in nodes:
		lineno = linenos[str(node.ord)]
		incidents.extend(validate_expected_features(node, lineno))
		#incidents.extend(validate_upos_vs_deprel(node, lineno))
		#incidents.extend(validate_flat_foreign(node, lineno, linenos))
		#incidents.extend(validate_left_to_right_relations(node, lineno))
		#incidents.extend(validate_single_subject(node, lineno))
		#incidents.extend(validate_single_object(node, lineno))
		#incidents.extend(validate_orphan(node, lineno))
		#incidents.extend(validate_functional_leaves(node, lineno, linenos))
		#incidents.extend(validate_fixed_span(node, lineno))
		#incidents.extend(validate_goeswith_span(node, lineno))
		#incidents.extend(validate_goeswith_morphology_and_edeps(node, lineno))
		#incidents.extend(validate_projective_punctuation(node, lineno))
	incidents = []

def validate_expected_features(node, seen_morpho_feature, delayed_feature_errors):
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
	incidents = []
	# TODO:
	if node.upos in ['PRON', 'DET']:
		incidents.extend(validate_required_feature(
			node, 'PronType', None,
			seen_morpho_feature, delayed_feature_errors,
			IncidentType.ERROR, TestClass.MORPHO, 'pron-det-without-prontype'
			))
	if node.feats['VerbForm'] == 'Fin' and node.feats['Mood'] == '':
		incidents.append(Warning(
			level=3,
			# ! used to be Incident with testclass="Warning", but now Warning is an alternative to Error and TestClass.MORPHO makes sense here
			testclass=TestClass.MORPHO,
			testid='verbform-fin-without-mood',
			message=f"Finite verb '{utils.formtl(node)}' lacks the 'Mood' feature"
		))
	elif node.feats['Mood'] != '' and node.feats['VerbForm'] != 'Fin':
		incidents.append(Warning(
			level=3,
			# ! used to be Incident with testclass="Warning", but now Warning is an alternative to Error and TestClass.MORPHO makes sense here
			testclass=TestClass.MORPHO,
			testid='mood-without-verbform-fin',
			message=f"Non-empty 'Mood' feature at a word that is not finite verb ('{utils.formtl(node)}')"
		))

def validate_required_feature(node, required_feature, required_value, seen_morpho_feature, delayed_feature_errors, incident_type, testclass, testid):
	"""
	In general, the annotation of morphological features is optional, although
	highly encouraged. However, if the treebank does have features, then certain
	features become required. This function will check the presence of a feature
	and if it is missing, an error will be reported only if at least one feature
	has been already encountered. Otherwise the error will be remembered and it
	may be reported afterwards if any feature is encountered later.

	Parameters
	----------
	node : TODO: update
	required_feature : str
		The name of the required feature.
	required_value : str
		The required value of the feature. Multivalues are not supported (they
		are just a string value containing one or more commas). If
		required_value is None or an empty string, it means that we require any
		non-empty value of required_feature.
	TODO: update
	"""
	incidents = []
	feats = node.feats
	if required_value:
		if feats[required_feature] != required_value or feats[required_feature] == '':
			if seen_morpho_feature:
				incidents.append(Error if incident_type == IncidentType.ERROR else Warning(
					level=3,
					testclass=testclass,
					testid=testid,
					message=f"The word '{utils.formtl(node)}' is tagged '{node.upos}' but it lacks the 'PronType' feature"
			))
			# TODO: outside of this function
			#else:
			#	if not testid in delayed_feature_errors:
			#		state.delayed_feature_errors[incident.testid] = {'occurrences': []}
			#	state.delayed_feature_errors[incident.testid]['occurrences'].append({'incident': incident})
	return incidents
