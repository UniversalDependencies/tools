from validator.utils import *
# import udapi.core.node.Node as Node

def test_shorten():
    short_str = "This is a short string"
    long_str = "This is a string with more than twenty-five characters"
    assert shorten(short_str) == short_str
    assert len(shorten(long_str)) == 25

def test_lspec2ud():
    assert lspec2ud("nmod") == "nmod"
    assert lspec2ud("nmod:poss") == "nmod"

#def test_formtl():
#    node_without_tl = Node(0, form="ኧሁ")
#    node_with_tl = Node(0, form="ኧሁ", misc="'ăhu")
#    assert formtl(node_without_tl) ==