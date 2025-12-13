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

def test_naturalnumber():
	match = crex.head.fullmatch('0')
	if match:
		assert True
	else:
		assert False

	match = crex.head.fullmatch('10')
	if match:
		assert True
	else:
		assert False

	match = crex.head.fullmatch('01')
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

def test_decimalwithzero():
	decimal_true = ["0", "0.1", "1.1", "3.10"]
	decimal_false = ["1.0", "1.", ".1", "1.01"]

	for decimal in decimal_true:
		match = crex.ehead.fullmatch(decimal)
		if match:
			assert True
		else:
			assert False

	for decimal in decimal_false:
		match = crex.ehead.fullmatch(decimal)
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
	general_test_metadata("newdoc", "# newdoc newdoc_name", True)     # ! is this wanted?
	general_test_metadata("newdoc", "# newdoc = newdoc_name", False)  # ! is this wanted?
	general_test_metadata("newdoc", "# newdoc newdoc_name ", False)

def test_newpar():
	general_test_metadata("newpar", "# newpar", True)
	general_test_metadata("newpar", "# newpar newpar_name", True)     # ! is this wanted?
	general_test_metadata("newpar", "# newpar = newpar_name", False)  # ! is this wanted?
	general_test_metadata("newpar", "# newpar newpar_name ", False)

def test_sentid():
	general_test_metadata("sentid", "# sent_id", False)
	general_test_metadata("sentid", "# sent_id id_sentence", False)
	general_test_metadata("sentid", "# sent_id = new sent id", False)
	general_test_metadata("sentid", "# sent_id = new_sent_id", True)
	general_test_metadata("sentid", "# sent_id = 9", True)

def test_text():
	general_test_metadata("text", "# text", False)
	general_test_metadata("text", "# text Mary had a little lamb", False)
	general_test_metadata("text", "# text = Mary had a little lamb", True)
	general_test_metadata("text", "# text = Mary had a little lamb ", False) # ! isn't this too strict? Maybe we could to allow trailing whitespaces

def test_uppercasestring():
	strings_true = ["ABC",
					"A"]
	strings_false = ["abc",
					"Abc",
					""]

	for string in strings_true:
		match = crex.upos.fullmatch(string)
		if match:
			assert True
		else:
			assert False

	for string in strings_false:
		match = crex.upos.fullmatch(string)
		if match:
			assert False
		else:
			assert True

def test_featval():
	strings_true = ["Feat=Val",
					"Feat=1,2",
    				"Feat=Val1",
        			"Feat[x]=Value"]
	strings_false = ["Feat=val",
					"feat=Val",
					"Feat",
					""]

	for string in strings_true:
		match = crex.featval.fullmatch(string)
		if match:
			assert True
		else:
			assert False

	for string in strings_false:
		match = crex.featval.fullmatch(string)
		if match:
			assert False
		else:
			assert True

def test_deprel():
	strings_true = ["nmod",
					"nmod:poss",
    				"nmod:p"]
	strings_false = [":poss",
					"nmod:1",
					""]

	for string in strings_true:
		match = crex.deprel.fullmatch(string)
		if match:
			assert True
		else:
			assert False

	for string in strings_false:
		match = crex.deprel.fullmatch(string)
		if match:
			assert False
		else:
			assert True