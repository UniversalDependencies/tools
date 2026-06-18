# Allow using this module from the root folder of tools even if it is not
# installed as a package: use the relative path udtools/src/udtools for
# submodules. If the path is not available, try the standard qualification,
# assuming that the user has installed udtools from PyPI and then called
# from udtools import Validator.
try:
    from udtools.src.udtools.validator import Validator
except ModuleNotFoundError:
    from udtools.validator import Validator

def test_mwt_empty_vals():
    validator = Validator()
    assert validator.check_mwt_empty_vals(['2-3','_','_','_','_','_','_','_','_','_']) == []
    assert validator.check_mwt_empty_vals(['2-3','_','_','_','_','_','_','_','_','Feat=Val']) == []
    assert validator.check_mwt_empty_vals(['2-3','_','_','_','_','Typo=Yes','_','_','_','Feat=Val']) == []

    assert len(validator.check_mwt_empty_vals(['2','_','_','_','_','_','_','_','_','Feat=Val'])) > 0
    assert len(validator.check_mwt_empty_vals(['2-3','_','_','_','_','Gender=Masc','_','_','_','Feat=Val'])) > 0
    assert len(validator.check_mwt_empty_vals(['2-3','_','_','ADJ','_','_','_','_','_','Feat=Val'])) > 0

# def test_empty_node_empty_vals():
# 	assert len(check_empty_node_empty_vals(['1','_','_','_','_','_','_','_','_','_'])) == 1
# 	assert len(check_empty_node_empty_vals(['2-3','_','_','_','_','_','_','_','_','Feat=Val'])) == 1

# 	assert len(check_empty_node_empty_vals(['1.1','word','lemma','ADJ','X','Feat=Val','_','_','_','Feat=Val'])) == 0
# 	assert len(check_empty_node_empty_vals(['1.1','word','lemma','ADJ','X','Feat=Val','2','_','_','Feat=Val'])) == 1
# 	assert len(check_empty_node_empty_vals(['1.1','word','lemma','ADJ','X','Feat=Val','_','root','_','Feat=Val'])) == 1
# 	assert len(check_empty_node_empty_vals(['1.1','word','lemma','ADJ','X','Feat=Val','0','root','_','Feat=Val'])) == 2


# def test_character_constraints():
# 	assert len(check_character_constraints(['2-3','_','_','_','_','_','_','_','_','Feat=Val'])) == 0
# 	assert len(check_character_constraints(['1.1','_','_','_','_','_','_','_','_','Feat=Val'])) == 0

# 	assert len(check_character_constraints(['1','_','_','_','_','_','_','1','_','Feat=Val'])) == 1
# 	assert len(check_character_constraints(['1','_','_','_','_','_','_','root','3','Feat=Val'])) == 1
# 	assert len(check_character_constraints(['1','_','_','_','_','_','_','1','3','Feat=Val'])) == 2
# 	assert len(check_character_constraints(['1','_','_','_','_','_','_','_','3','Feat=Val'])) == 2

# def test_upos():
#     assert len(check_upos(['2-3','_','_','_','_','_','_','_','_','Feat=Val'], Fspecs)) == 0
#     assert len(check_upos(['1.1','_','_','_','_','_','_','_','_','Feat=Val'], Fspecs)) == 0
#     assert len(check_upos(['1','_','_','adj','_','_','_','_','_','Feat=Val'], Fspecs)) == 1
#     assert len(check_upos(['1','_','_','ADJ','_','_','_','_','_','Feat=Val'], Fspecs)) == 0
#     assert len(check_upos(['1','_','_','PROP','_','_','_','_','_','Feat=Val'], Fspecs)) == 1

# def test_features_level2():
#     assert len(check_features_level2(['1','_','_','_','_','_','_','_','_','_'])) == 0
#     assert len(check_features_level2(['1','_','_','_','_','A=1|B=2','_','_','_','_'])) == 0
#     assert len(check_features_level2(['1','_','_','_','_','A=No,Yes|B=2','_','_','_','_'])) == 0
#     assert len(check_features_level2(['1','_','_','_','_','B=1|A=2','_','_','_','_'])) == 1
#     assert len(check_features_level2(['1','_','_','_','_','A=1|B=2|B=2','_','_','_','_'])) == 1
#     # TODO: this should raise 2 errors, not 1
#     assert len(check_features_level2(['1','_','_','_','_','A=1|B=2|B=3','_','_','_','_'])) == 1
#     assert len(check_features_level2(['1','_','_','_','_','A=Yes,No','_','_','_','_'])) == 1
#     assert len(check_features_level2(['1','_','_','_','_','A=Yes,Yes','_','_','_','_'])) == 1
