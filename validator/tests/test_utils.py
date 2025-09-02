from validator.utils import *
from udapi.core.node import Node

TEST_CASES_DIR = os.path.join(os.path.dirname(os.path.realpath(os.path.abspath(__file__))), "test-cases")

def test_parse_empty_node_id():
    empty_node = ["1.2", "_", "_", "_", "_", "_", "_", "_", "_", "_"]
    # TODO: update after removing assert in parse_empty_nodes_id
    assert parse_empty_node_id(empty_node) == ("1", "2")

def test_shorten():
    short_str = "This is a short string"
    long_str = "This is a string w more than twenty-five characters"
    assert shorten(short_str) == short_str
    assert len(shorten(long_str)) == 25

def test_lspec2ud():
    assert lspec2ud("nmod") == "nmod"
    assert lspec2ud("nmod:poss") == "nmod"

def test_formtl():
    form = "ኧሁ"
    tl = "'ăhu"
    node_wo_tl = Node(0, form=form)
    node_w_tl = Node(0, form=form, misc="Translit={}".format(tl))
    assert formtl(node_wo_tl) == form
    assert formtl(node_w_tl) == "{} {}".format(form, tl)

def test_lemmatl():
    lemma = "እኔ"
    tl = "'əne"
    node_wo_tl = Node(0, lemma=lemma)
    node_w_tl = Node(0, lemma=lemma, misc="LTranslit={}".format(tl))
    assert lemmatl(node_wo_tl) == lemma
    assert lemmatl(node_w_tl) == "{} {}".format(lemma, tl)

def test_get_alt_language():
    lang = "en"
    node_wo_lang = Node(0)
    node_w_lang = Node(0, misc="Lang={}".format(lang))
    assert get_alt_language(node_wo_lang) == None
    assert get_alt_language(node_w_lang) == lang

def test_deps_list():
    line_wo_deps = ["_", "_", "_", "_", "_", "_", "_", "_", "_", "_"]
    line_w_deps = ["_", "_", "_", "_", "_", "_", "_", "_", "0:root|2:conj", "_"]
    assert deps_list(line_wo_deps) == []
    assert deps_list(line_w_deps) == [["0", "root"], ["2", "conj"]]

def test_get_line_numbers_for_ids():
    pass # TODO: only if State class changes