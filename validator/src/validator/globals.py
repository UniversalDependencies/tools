# The folder where this script resides.
THISDIR=os.path.dirname(os.path.realpath(os.path.abspath(__file__)))

# Constants for the column indices
COLCOUNT=10
ID,FORM,LEMMA,UPOS,XPOS,FEATS,HEAD,DEPREL,DEPS,MISC=range(COLCOUNT)
COLNAMES='ID,FORM,LEMMA,UPOS,XPOS,FEATS,HEAD,DEPREL,DEPS,MISC'.split(',')
TOKENSWSPACE=MISC+1 # one extra constant
AUX=MISC+2 # another extra constant
COP=MISC+3 # another extra constant

# Global variables:
curr_line = 0 # Current line in the input file
comment_start_line = 0 # The line in the input file on which the current sentence starts, including sentence-level comments.
sentence_line = 0 # The line in the input file on which the current sentence starts (the first node/token line, skipping comments)
sentence_id = None # The most recently read sentence id
line_of_first_morpho_feature = None # features are optional, but if the treebank has features, then some become required
delayed_feature_errors = {}
line_of_first_enhanced_graph = None
line_of_first_tree_without_enhanced_graph = None
line_of_first_enhancement = None # any difference between non-empty DEPS and HEAD:DEPREL
line_of_first_empty_node = None
line_of_first_enhanced_orphan = None
line_of_global_entity = None
global_entity_attribute_string = None # to be able to check that repeated declarations are identical
entity_attribute_number = 0 # to be able to check that an entity does not have extra attributes
entity_attribute_index = {} # key: entity attribute name; value: the index of the attribute in the entity attribute list
entity_types = {} # key: entity (cluster) id; value: tuple: (type of the entity, identity (Wikipedia etc.), line of the first mention)
open_entity_mentions = [] # items are dictionaries with entity mention information
open_discontinuous_mentions = {} # key: entity id; describes last part of a discontinuous mention of that entity; item is dict, its keys: last_ipart, npart, line
entity_ids_this_document = {}
entity_ids_other_documents = {}
entity_bridge_relations = {} # key: srceid<tgteid pair; value: type of the entity (may be empty)
entity_split_antecedents = {} # key: tgteid; value: sorted list of srceids, serialized to string
entity_mention_spans = {} # key: [eid][sentid][str(mention_span)]; value: set of node ids
error_counter = {} # key: error type value: error count
warn_on_missing_files = set() # langspec files which you should warn about in case they are missing (can be deprel, edeprel, feat_val, tokens_w_space)
warn_on_undoc_feats = '' # filled after reading docfeats.json; printed when an unknown feature is encountered in the data
warn_on_undoc_deps = '' # filled after reading docdeps.json; printed when an unknown relation is encountered in the data
warn_on_undoc_edeps = '' # filled after reading edeprels.json; printed when an unknown enhanced relation is encountered in the data
warn_on_undoc_aux = '' # filled after reading data.json; printed when an unknown auxiliary is encountered in the data
warn_on_undoc_cop = '' # filled after reading data.json; printed when an unknown copula is encountered in the data
mwt_typo_span_end = None # if Typo=Yes at multiword token, what is the end of the multiword span?
spaceafterno_in_effect = False # needed to check that no space after last word of sentence does not co-occur with new paragraph or document
featdata = {} # key: language code (feature-value-UPOS data loaded from feats.json)
auxdata = {} # key: language code (auxiliary/copula data loaded from data.json)
depreldata = {} # key: language code (deprel data loaded from deprels.json)
edepreldata = {} # key: language code (edeprel data loaded from edeprels.json)