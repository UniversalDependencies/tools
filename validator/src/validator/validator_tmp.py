# will contain validator class + all the smallish validation functions validate_xxx

import collections
import regex as re

from validator.incident import Error, Warning, TestClass
import validator.utils as utils
import validator.compiled_regex as crex

def validate_mwt_empty_vals(cols):
	"""
	Checks that a multi-word token has _ empty values in all fields except MISC.
	This is required by UD guidelines although it is not a problem in general,
	therefore a level 2 test.

	Parameters
	----------
	cols : list
		The values of the columns on the current node / token line.
	"""

	if not utils.is_multiword_token(cols):
		ret = Error(level=0,
					testclass=TestClass.INTERNAL,
					testid='internal error')
		return [ret]

	# all columns except the first two (ID, FORM) and the last one (MISC)
	for col_idx in range(utils.LEMMA, utils.MISC):

		# Exception: The feature Typo=Yes may occur in FEATS of a multi-word token.
		if cols[col_idx] != '_' and (col_idx != utils.FEATS or cols[col_idx] not in ['Typo=Yes', '_']):
			ret = Error(level=2,
						testclass=TestClass.FORMAT,
						testid='mwt-nonempty-field',
						message=f"A multi-word token line must have '_' in the column {utils.COLNAMES[col_idx]}. Now: '{cols[col_idx]}'."
						)
			return [ret]

	return []


def validate_empty_node_empty_vals(cols):
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
		ret = Error(level=0,
					testclass=TestClass.INTERNAL,
					testid='internal error')
		return [ret]

	ret = []
	for col_idx in (utils.HEAD, utils.DEPREL): # ! isn't it worth it to check also DEPS here?
		if cols[col_idx]!= '_':
			ret.append(
					Error(
					level=2,
					testclass=TestClass.FORMAT,
					testid='mwt-nonempty-field',
					message=f"An empty node must have '_' in the column {utils.COLNAMES[col_idx]}. Now: '{cols[col_idx]}'."
					)
			)
	return ret

#! proposal: rename into validate_deps_deprel_contraints, or also check UPOS format (not value)
#! I don't like that it relies on crex
def validate_character_constraints(cols):
	"""
	Checks general constraints on valid characters, e.g. that UPOS
	only contains [A-Z].

	Parameters
	----------
	cols : list
		The values of the columns on the current node / token line.
	"""

	if utils.is_multiword_token(cols):
		return []

	# Do not test the regular expression crex.upos here. We will test UPOS
	# directly against the list of known tags. That is a level 2 test, too.

	if utils.is_empty_node(cols) and cols[utils.DEPREL] == '_':
		return []

	ret = []
	if not crex.deprel.fullmatch(cols[utils.DEPREL]):
		ret.append(
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
		ret.append(
			Error(
					level=2,
					testclass=TestClass.ENHANCED,
					testid='invalid-deps',
					message=f"Failed to parse DEPS: '{cols[utils.DEPS]}'."
			)
		)
		return ret

	for _, edep in deps:
		if not crex.edeprel.fullmatch(edep):
			ret.append(
				Error(
					level=2,
					testclass=TestClass.ENHANCED,
					testid='invalid-edeprel',
					message=f"Invalid enhanced relation type: '{edep}' in '{cols[utils.DEPS]}'."
				)
			)
	return ret

def validate_upos(cols, Fspecs):
	"""
	Checks that the UPOS field contains one of the 17 known tags.

	Parameters
	----------
	cols : list
		The values of the columns on the current node / token line.
	Fspecs : UDSpecs
		The object containing specific information about the allowed values
	"""

	#! added checking for mwt?
	if utils.is_multiword_token(cols) and cols[utils.UPOS] == '_':
		return []

	if utils.is_empty_node(cols) and cols[utils.UPOS] == '_':
		return []

	# Just in case, we still match UPOS against the regular expression that
	# checks general character constraints. However, the list of UPOS, loaded
	# from a JSON file, should conform to the regular expression.
	ret = []
	print(cols[utils.UPOS], crex.upos.fullmatch(cols[utils.UPOS]))
	if not crex.upos.fullmatch(cols[utils.UPOS]) or cols[utils.UPOS] not in Fspecs.upos:
		ret.append(
			Error(
	  			level=2,
				testclass=TestClass.MORPHO,
				testid='unknown-upos',
				message=f"Unknown UPOS tag: '{cols[utils.UPOS]}'."
			)
		)

	return ret

# ! proposal: rename into feature format or something alike
def validate_features_level2(cols):
	"""
	Checks general constraints on feature-value format: Permitted characters in
	feature name and value, features must be sorted alphabetically, features
	cannot be repeated etc.

	Parameters
	----------
	cols : list
		The values of the columns on the current node / token line.

	"""
	ret = []

	feats = cols[utils.FEATS]
	if feats == '_':
		return ret

	# self.features_present(state) # TODO: do elsewhere

	feat_list = feats.split('|') #! why not a function in utils? Like the one that gets deps
	if [f.lower() for f in feat_list] != list(sorted(f.lower() for f in feat_list)):
		ret.append(
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
			ret.append(
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
				ret.append(
					Error(
						level=2,
						testclass=TestClass.MORPHO,
						testid='repeated-feature-value',
						message=f"Repeated feature values are disallowed: '{feats}' (error generated by feature '{attr}')"
					)
				)
			if [v.lower() for v in values] != sorted(v.lower() for v in values):
				ret.append(
					Error(
						level=2,
						testclass=TestClass.MORPHO,
						testid='unsorted-feature-values',
						message=f"If a feature has multiple values, these must be sorted: '{feat_val}'"
					)
				)
			for v in values:
				if not crex.val.fullmatch(v): # ! can this ever be true? If val.fullmatch() does not match, than also featval.fullmatch() wouldn't
					ret.append(
						Error(
							level=2,
							testclass=TestClass.MORPHO,
							testid='invalid-feature-value',
							message=f"Spurious value '{v}' in '{feat_val}'. Must start with [A-Z0-9] and only contain [A-Za-z0-9]."
						)
					)

	if len(attr_set) != len(feat_list):
		ret.append(
			Error(
				level=2,
				testclass=TestClass.MORPHO,
				testid='repeated-feature',
				message=f"Repeated features are disallowed: '{feats}'."
			)
		)

	# Subsequent higher-level tests could fail if a feature is not in the
	# Feature=Value format. If that happens, we will return False and the caller
	# can skip the more fragile tests.
	# TODO: the engine has to know that 'invalid-feature' is a testid that prevents from further
	return ret

# TODO: write tests
def validate_deps(cols):
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
	"""

	# TODO: the engine must assume that it is run after validate_id_references() and only if DEPS is parsable and the head indices in it are OK.

	ret = []
	if not (utils.is_word(cols) or utils.is_empty_node(cols)):
		return ret

	# TODO: move elsewhere
	# Remember whether there is at least one difference between the basic
	# tree and the enhanced graph in the entire dataset.
	#if cols[utils.DEPS] != '_' and cols[utils.DEPS] != cols[utils.HEAD]+':'+cols[utils.DEPREL]:
	#	state.seen_enhancement = line

	# We already know that the contents of DEPS is parsable (deps_list() was
	# first called from validate_id_references() and the head indices are OK).
	deps = utils.deps_list(cols)
	###!!! Float will not work if there are 10 empty nodes between the same two
	###!!! regular nodes. '1.10' is not equivalent to '1.1'.
	# ORIGINAL VERSION: heads = [float(h) for h, d in deps]

	# NEW VERSION:
	#! maybe do this only is [0-9]+.[1-9][0-9]+ is present somewhere?
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
		ret.append(
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
					ret.append(
						Error(
							level=2,
							testclass=TestClass.FORMAT,
							testid='unsorted-deps-2',
							message=f"DEPS pointing to head '{h}' not sorted by relation type: '{cols[utils.DEPS]}'"
						)
					)
				elif d == lastd:
					ret.append(
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
		return ret

	if id_ in heads:
		ret.append(
			Error(
				level=2,
				testclass=TestClass.ENHANCED,
				testid='deps-self-loop',
				message=f"Self-loop in DEPS for '{cols[utils.ID]}'"
			)
		)

	return ret


def validate_misc(cols):
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
	# Incident.default_lineno = line
	# Incident.default_level = 2
	# Incident.default_testclass = 'Warning'

	ret = []

	if cols[utils.MISC] == '_':
		return ret

	misc = [ma.split('=', 1) for ma in cols[utils.MISC].split('|')] #! why not using a function in utils? Just like the one for features
	mamap = collections.defaultdict(int)
	for ma in misc:
		if ma[0] == '':
			if len(ma) == 1:
				ret.append(
					Warning(
						level=2,
						testid='empty-misc',
						message="Empty attribute in MISC; possible misinterpreted vertical bar?"
					)
				)
			else:
				ret.append(
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
			ret.append(
				level=2,
				testid='misc-extra-space',
    			message=f"MISC attribute: leading or trailing extra space in '{'='.join(ma)}'."
			)

		if re.match(r"^(SpaceAfter|Lang|Translit|LTranslit|Gloss|LId|LDeriv)$", ma[0]):
			mamap[ma[0]] += 1
		elif re.match(r"^\s*(spaceafter|lang|translit|ltranslit|gloss|lid|lderiv)\s*$", ma[0], re.IGNORECASE):
			ret.append(
				Warning(
					level=2,
					testid='misc-attr-typo',
					message=f"Possible typo (case or spaces) in MISC attribute '{'='.join(ma)}'."
				)

			)

	for ma in mamap:
		if mamap[ma] > 1:
			ret.append(
				Error(
					level=2,
					testclass=TestClass.FORMAT,
					testid='repeated-misc',
					message=f"MISC attribute '{ma}' not supposed to occur twice"
				)
			)

	return ret

# TODO: write tests
def validate_deps_all_or_none(sentence, seen_enhanced_graph):
	"""
	Takes the list of non-comment lines (line = list of columns) describing
	a sentence. Checks that enhanced dependencies are present if they were
	present at another sentence, and absent if they were absent at another
	sentence.
	"""
	ret = []
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
	# Incident.default_lineno = state.sentence_line
	# Incident.default_level = 2
	# Incident.default_testclass = 'Enhanced'
	if egraph_exists:
		if not seen_enhanced_graph:
			# TODO: do elsewhere
			# state.seen_enhanced_graph = state.sentence_line
			ret.append(
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
				ret.append(
					Error(
						level=2,
						testid='edeps-only-sometimes',
						message=f"Enhanced graph cannot be empty because we saw non-empty DEPS earlier."
					)
				)
				#! we should add something to this message in the engine where we have access to the state:
				#  on line {state.seen_enhanced_graph}

# TODO: move elsewhere
# # If a multi-word token has Typo=Yes, its component words must not have it.
# 			# We must remember the span of the MWT and check it in validate_features_level4().
# 			m = crex.mwtid.fullmatch(cols[ID])
# 			state.mwt_typo_span_end = m.group(2)



if __name__ == "__main__":
	print(validate_mwt_empty_vals(['2-3','_','_','_','_','Typo=Yes','_','_','_','Feat=Val'])[0].message)