# will contain validator class + all the smallish validation functions validate_xxx
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

# TODO: move elsewhere
# # If a multi-word token has Typo=Yes, its component words must not have it.
# 			# We must remember the span of the MWT and check it in validate_features_level4().
# 			m = crex.mwtid.fullmatch(cols[ID])
# 			state.mwt_typo_span_end = m.group(2)



if __name__ == "__main__":
	print(validate_mwt_empty_vals(['2-3','_','_','_','_','Typo=Yes','_','_','_','Feat=Val'])[0].message)