import regex as re
from validator import compiled_regex as crex

def test_ws():
	spaces = [" ",
			"  ",
			"\n",     # ! is this wanted?
			"	"]

	for space in spaces:
		match = crex.ws.fullmatch(space)
		if match:
			assert True
		else:
			assert False

def test_twows():
	spaces_true = ["  ",
				"\n\n",     # ! is this wanted?
				"		"]
	spaces_false = [" ",
			"\n",     # ! is this wanted?
			"	"]

	for space in spaces_true:
		match = crex.ws2.fullmatch(space)
		if match:
			assert True
		else:
			assert False

	for space in spaces_false:
		match = crex.ws2.fullmatch(space)
		if match:
			assert False
		else:
			assert True

def test_integer():
	match = crex.wordid.fullmatch('10')
	if match:
		assert True
	else:
		assert False

	match = crex.wordid.fullmatch('01')
	if match:
		assert False
	else:
		assert True

def test_range():
	ranges_true = ["1-2", "9-10", "15-16"]
	ranges_false = ["0-1", "1-0", "10-", "-10"]

	for range in ranges_true:
		match = crex.mwtid.fullmatch(range)
		if match:
			assert True
		else:
			assert False

	for range in ranges_false:
		match = crex.mwtid.fullmatch(range)
		if match:
			assert False
		else:
			assert True

def test_decimal():
	decimal_true = ["0.1", "1.1", "3.10"]
	decimal_false = ["1.0", "1.", ".1", "1.01"]

	for decimal in decimal_true:
		match = crex.enodeid.fullmatch(decimal)
		if match:
			assert True
		else:
			assert False

	for decimal in decimal_false:
		match = crex.enodeid.fullmatch(decimal)
		if match:
			assert False
		else:
			assert True

def general_test_metadata(regex_name, meta_str, expected):
	obj = getattr(crex, regex_name)
	match = obj.fullmatch(meta_str)

	if (match and expected) or (match is None and not expected):
		assert True
	else:
		assert False

def test_newdoc():
    general_test_metadata("newdoc", "# newdoc", True)
    general_test_metadata("newdoc", "# newdoc newdoc_name", True) # ! is this wanted?
    general_test_metadata("newdoc", "# newdoc = newdoc_name", False) # ! is this wanted?
    general_test_metadata("newdoc", "# newdoc newdoc_name ", False)
