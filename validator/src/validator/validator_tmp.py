# will contain validator class + all the smallish validation functions validate_xxx
from validator.incident import Error, Warning, TestClass
import validator.utils as utils

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


# # TODO: move elsewhere
# # If a multi-word token has Typo=Yes, its component words must not have it.
# 			# We must remember the span of the MWT and check it in validate_features_level4().
# 			m = crex.mwtid.fullmatch(cols[ID])
# 			state.mwt_typo_span_end = m.group(2)



if __name__ == "__main__":
    print(validate_mwt_empty_vals(['2-3','_','_','_','_','Typo=Yes','_','_','_','Feat=Val'])[0].message)