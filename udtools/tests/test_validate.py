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
    True
    ###!!! The check_ methods of the validator currently do not return the list of incidents, so we cannot test it here.
#    validator = Validator()
#    assert validator.check_mwt_empty_vals(['2-3','_','_','_','_','_','_','_','_','_'], 1) == []
#    assert validator.check_mwt_empty_vals(['2-3','_','_','_','_','_','_','_','_','Feat=Val'], 2) == []
#    assert validator.check_mwt_empty_vals(['2-3','_','_','_','_','Typo=Yes','_','_','_','Feat=Val'], 3) == []
#    assert len(validator.check_mwt_empty_vals(['2','_','_','_','_','_','_','_','_','Feat=Val'], 4)) > 0
#    assert len(validator.check_mwt_empty_vals(['2-3','_','_','_','_','Gender=Masc','_','_','_','Feat=Val'], 5)) > 0
#    assert len(validator.check_mwt_empty_vals(['2-3','_','_','ADJ','_','_','_','_','_','Feat=Val'], 6)) > 0
