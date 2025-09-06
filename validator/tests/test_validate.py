import os

from validator.validate import *
from validator.specifications import UDSpecs
from validator.utils import THIS_DIR

Fspecs = UDSpecs(os.path.normpath(os.path.join(utils.THIS_DIR,"../../../data")))

def test_mwt_empty_vals():
	assert check_mwt_empty_vals(['2-3','_','_','_','_','_','_','_','_','_']) == []
	assert check_mwt_empty_vals(['2-3','_','_','_','_','_','_','_','_','Feat=Val']) == []
	assert check_mwt_empty_vals(['2-3','_','_','_','_','Typo=Yes','_','_','_','Feat=Val']) == []

	assert len(check_mwt_empty_vals(['2','_','_','_','_','_','_','_','_','Feat=Val'])) > 0
	assert len(check_mwt_empty_vals(['2-3','_','_','_','_','Gender=Masc','_','_','_','Feat=Val'])) > 0
	assert len(check_mwt_empty_vals(['2-3','_','_','ADJ','_','_','_','_','_','Feat=Val'])) > 0

def test_empty_node_empty_vals():
	assert len(check_empty_node_empty_vals(['1','_','_','_','_','_','_','_','_','_'])) == 1
	assert len(check_empty_node_empty_vals(['2-3','_','_','_','_','_','_','_','_','Feat=Val'])) == 1

	assert len(check_empty_node_empty_vals(['1.1','word','lemma','ADJ','X','Feat=Val','_','_','_','Feat=Val'])) == 0
	assert len(check_empty_node_empty_vals(['1.1','word','lemma','ADJ','X','Feat=Val','2','_','_','Feat=Val'])) == 1
	assert len(check_empty_node_empty_vals(['1.1','word','lemma','ADJ','X','Feat=Val','_','root','_','Feat=Val'])) == 1
	assert len(check_empty_node_empty_vals(['1.1','word','lemma','ADJ','X','Feat=Val','0','root','_','Feat=Val'])) == 2


def test_character_constraints():
	assert len(check_character_constraints(['2-3','_','_','_','_','_','_','_','_','Feat=Val'])) == 0
	assert len(check_character_constraints(['1.1','_','_','_','_','_','_','_','_','Feat=Val'])) == 0

	assert len(check_character_constraints(['1','_','_','_','_','_','_','1','_','Feat=Val'])) == 1
	assert len(check_character_constraints(['1','_','_','_','_','_','_','root','3','Feat=Val'])) == 1
	assert len(check_character_constraints(['1','_','_','_','_','_','_','1','3','Feat=Val'])) == 2
	assert len(check_character_constraints(['1','_','_','_','_','_','_','_','3','Feat=Val'])) == 2

def test_upos():
    assert len(check_upos(['2-3','_','_','_','_','_','_','_','_','Feat=Val'], Fspecs)) == 0
    assert len(check_upos(['1.1','_','_','_','_','_','_','_','_','Feat=Val'], Fspecs)) == 0
    assert len(check_upos(['1','_','_','adj','_','_','_','_','_','Feat=Val'], Fspecs)) == 1
    assert len(check_upos(['1','_','_','ADJ','_','_','_','_','_','Feat=Val'], Fspecs)) == 0
    assert len(check_upos(['1','_','_','PROP','_','_','_','_','_','Feat=Val'], Fspecs)) == 1

def test_features_level2():
    assert len(check_features_level2(['1','_','_','_','_','_','_','_','_','_'])) == 0
    assert len(check_features_level2(['1','_','_','_','_','A=1|B=2','_','_','_','_'])) == 0
    assert len(check_features_level2(['1','_','_','_','_','A=No,Yes|B=2','_','_','_','_'])) == 0
    assert len(check_features_level2(['1','_','_','_','_','B=1|A=2','_','_','_','_'])) == 1
    assert len(check_features_level2(['1','_','_','_','_','A=1|B=2|B=2','_','_','_','_'])) == 1
    # TODO: this should raise 2 errors, not 1
    assert len(check_features_level2(['1','_','_','_','_','A=1|B=2|B=3','_','_','_','_'])) == 1
    assert len(check_features_level2(['1','_','_','_','_','A=Yes,No','_','_','_','_'])) == 1
    assert len(check_features_level2(['1','_','_','_','_','A=Yes,Yes','_','_','_','_'])) == 1
