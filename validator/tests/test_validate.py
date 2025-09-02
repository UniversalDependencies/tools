from validator.validator_tmp import *

def test_mwt_empty_vals():
    assert validate_mwt_empty_vals(['2-3','_','_','_','_','_','_','_','_','_']) == []
    assert validate_mwt_empty_vals(['2-3','_','_','_','_','_','_','_','_','Feat=Val']) == []
    assert validate_mwt_empty_vals(['2-3','_','_','_','_','Typo=Yes','_','_','_','Feat=Val']) == []

    assert len(validate_mwt_empty_vals(['2','_','_','_','_','_','_','_','_','Feat=Val'])) > 0
    assert len(validate_mwt_empty_vals(['2-3','_','_','_','_','Gender=Masc','_','_','_','Feat=Val'])) > 0
    assert len(validate_mwt_empty_vals(['2-3','_','_','ADJ','_','_','_','_','_','Feat=Val'])) > 0
