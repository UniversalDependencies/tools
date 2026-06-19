# Allow using this module from the root folder of tools even if it is not
# installed as a package: use the relative path udtools/src/udtools for
# submodules. If the path is not available, try the standard qualification,
# assuming that the user has installed udtools from PyPI and then called
# from udtools import Validator.
try:
    import udtools.src.udtools.utils as utils
except ModuleNotFoundError:
    import udtools.utils as utils
from udapi.core.node import Node

def test_parse_empty_node_id():
    empty_node = ["1.2", "_", "_", "_", "_", "_", "_", "_", "_", "_"]
    # TODO: update after removing assert in parse_empty_nodes_id
    assert utils.parse_empty_node_id(empty_node) == ("1", "2")

def test_shorten():
    short_str = "This is a short string"
    long_str = "This is a string w more than twenty-five characters"
    assert utils.shorten(short_str) == short_str
    assert len(utils.shorten(long_str)) == 25

def test_lspec2ud():
    assert utils.lspec2ud("nmod") == "nmod"
    assert utils.lspec2ud("nmod:poss") == "nmod"

def test_formtl():
    form = "ኧሁ"
    tl = "'ăhu"
    node_wo_tl = Node(0, form=form)
    node_w_tl = Node(0, form=form, misc="Translit={}".format(tl))
    assert utils.formtl(node_wo_tl) == form
    assert utils.formtl(node_w_tl) == "{} {}".format(form, tl)

def test_lemmatl():
    lemma = "እኔ"
    tl = "'əne"
    node_wo_tl = Node(0, lemma=lemma)
    node_w_tl = Node(0, lemma=lemma, misc="LTranslit={}".format(tl))
    assert utils.lemmatl(node_wo_tl) == lemma
    assert utils.lemmatl(node_w_tl) == "{} {}".format(lemma, tl)

def test_get_alt_language():
    lang = "en"
    node_wo_lang = Node(0)
    node_w_lang = Node(0, misc="Lang={}".format(lang))
    assert utils.get_alt_language(node_wo_lang) == None
    assert utils.get_alt_language(node_w_lang) == lang

def test_deps_list():
    line_wo_deps = ["_", "_", "_", "_", "_", "_", "_", "_", "_", "_"]
    line_w_deps = ["_", "_", "_", "_", "_", "_", "_", "_", "0:root|2:conj", "_"]
    assert utils.deps_list(line_wo_deps) == []
    assert utils.deps_list(line_w_deps) == [["0", "root"], ["2", "conj"]]
