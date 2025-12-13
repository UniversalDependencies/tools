import os
from collections import defaultdict
# Allow using this module from the root folder of tools even if it is not
# installed as a package: use the relative path validator/src/validator for
# submodules. If the path is not available, try the standard qualification,
# assuming that the user has installed udtools from PyPI and then called
# from udtools import Validator.
try:
    from udtools.src.udtools.incident import IncidentType
except ModuleNotFoundError:
    from udtools.incident import IncidentType



class State:
    """
    The State class holds various global data about where we are in the file
    and what we have seen so far. Typically there will be just one instance of
    this class.
    """
    def __init__(self):
        # Name of the current input file.
        self.current_file_name = None
        # Current line in the input file, or, more precisely, the last line
        # read so far. Once we start looking at tree integrity, we may find
        # errors on previous lines as well.
        self.current_line = 0;
        # The line in the input file on which the current sentence starts,
        # including sentence-level comments.
        self.comment_start_line = 0
        # The line in the input file on which the current sentence starts
        # (the first node/token line, skipping comments).
        self.sentence_line = 0
        # The most recently read sentence id.
        self.sentence_id = None
        # List of input lines representing the current sentence (including
        # comments and the final empty line). Newline characters omitted.
        self.current_lines = []
        # List of token/node lines in the current sentence, each line split
        # to fields (columns). It is thus a list of lists of strings.
        self.current_token_node_table = []
        # Mapping from node ids (including empty nodes) to line numbers in the
        # input file. Dictionary indexed by string.
        self.current_node_linenos = {}
        # Needed to check that no space after last word of sentence does not
        # co-occur with new paragraph or document.
        self.spaceafterno_in_effect = False
        # Incident counter by type. Key: incident type, test class; value: incident count
        # Incremented in Incident.report(), even if reporting is off or over --max_err.
        self.error_counter = defaultdict(lambda: defaultdict(int))
        # Lists of incidents confirmed so far, up to --max_store
        self.error_tracker = []
        # Set of detailed error explanations that have been printed so far.
        # Each explanation will be printed only once. Typically, an explanation
        # can be identified by test id + language code. Nevertheless, we put
        # the whole explanation to the set.
        self.explanation_printed = set()
        # Some feature-related errors can only be reported if the corpus
        # contains feature annotation because features are optional in general.
        # Once we see the first feature, we can flush all accummulated
        # complaints about missing features.
        # Key: testid; value: dict with parameters of the error and the list of
        # its occurrences.
        self.delayed_feature_errors = {}
        # Remember all sentence ids seen in all input files (presumably one
        # corpus). We need it to check that each id is unique.
        self.known_sent_ids = set()
        # Similarly, parallel ids should be unique in a corpus. (If multiple
        # sentences are equivalents of the same virtual sentence in the
        # parallel collection, they should be distinguished with 'altN'.)
        self.known_parallel_ids = set()
        self.parallel_id_lastalt = {}
        self.parallel_id_lastpart = {}
        #----------------------------------------------------------------------
        # Various things that we may have seen earlier in the corpus. The value
        # is None if we have not seen it, otherwise it is the line number of
        # the first occurrence.
        #----------------------------------------------------------------------
        self.seen_morpho_feature = None
        self.seen_enhanced_graph = None
        self.seen_tree_without_enhanced_graph = None
        # Any difference between non-empty DEPS and HEAD:DEPREL.
        # (Because we can see many enhanced graphs but no real enhancements.)
        self.seen_enhancement = None
        self.seen_empty_node = None
        self.seen_enhanced_orphan = None
        # global.entity comment line is needed for Entity annotations in MISC.
        self.seen_global_entity = None
        #----------------------------------------------------------------------
        # Additional observations related to Entity annotation in MISC
        # (only needed when validating entities and coreference).
        #----------------------------------------------------------------------
        # Remember the global.entity attribute string to be able to check that
        # repeated declarations are identical.
        self.global_entity_attribute_string = None
        # The number of entity attributes will be derived from the attribute
        # string and will be used to check that an entity does not have extra
        # attributes.
        self.entity_attribute_number = 0
        # Key: entity attribute name; value: the index of the attribute in the
        # entity attribute list.
        self.entity_attribute_index = {}
        # Key: entity (cluster) id; value: tuple: (type of the entity, identity
        # (Wikipedia etc.), line of the first mention)).
        self.entity_types = {}
        # Indices of known entity ids in this and other documents.
        # (Otherwise, if we only needed to know that an entity is known, we
        # could use self.entity_types above.)
        self.entity_ids_this_document = {}
        self.entity_ids_other_documents = {}
        # List of currently open entity mentions. Items are dictionaries with
        # entity mention information.
        self.open_entity_mentions = []
        # For each entity that has currently open discontinuous mention,
        # describe the last part of the mention. Key: entity id; value is dict,
        # its keys: last_ipart, npart, line.
        self.open_discontinuous_mentions = {}
        # Key: srceid<tgteid pair; value: type of the entity (may be empty).
        self.entity_bridge_relations = {}
        # Key: tgteid; value: sorted list of srceids, serialized to string.
        self.entity_split_antecedents = {}
        # Key: [eid][sentid][str(mention_span)]; value: set of node ids.
        self.entity_mention_spans = {}


    def get_current_file_name(self):
        """
        Returns the current file name in the form suitable for Incident objects
        and their string reports (i.e., 'STDIN' instead of '-', basename for
        paths, 'NONE' otherwise).

        Returns
        -------
        str
            The modified name of the current input file.
        """
        if self.current_file_name:
            if self.current_file_name == '-':
                return 'STDIN'
            else:
                return os.path.basename(self.current_file_name)
        else:
            return 'NONE'


    def __str__(self):
        # Summarize the warnings and errors.
        result = ''
        passed = True
        nerror = 0
        if self.error_counter:
            nwarning = 0
            for k, v in self.error_counter[IncidentType.WARNING].items():
                nwarning += v
            if nwarning > 0:
                result += f"Warnings: {nwarning}\n"
            for k, v in sorted(self.error_counter[IncidentType.ERROR].items()):
                nerror += v
                passed = False
                result += f"{str(k)} errors: {v}\n"
        if passed:
            result += '*** PASSED ***'
        else:
            result += f'*** FAILED *** with {nerror} errors'
        return result


    def passed(self):
        for k, v in self.error_counter[IncidentType.ERROR].items():
            if v > 0:
                return False
        return True


    def __bool__(self):
        return self.passed()
