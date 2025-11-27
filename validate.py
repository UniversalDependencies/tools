#! /usr/bin/env python3
# Original code (2015) by Filip Ginter and Sampo Pyysalo.
# DZ 2018-11-04: Porting the validator to Python 3.
# DZ: Many subsequent changes. See the git history.
import sys
import io
import os.path
import argparse
import traceback
from collections import defaultdict
# According to https://stackoverflow.com/questions/1832893/python-regex-matching-unicode-properties,
# the regex module has the same API as re but it can check Unicode character properties using \p{}
# as in Perl.
#import re
import regex as re
import unicodedata
import json
# Once we know that the low-level CoNLL-U format is OK, we will be able to use
# the Udapi library to access the data and perform the tests at higher levels.
import udapi.block.read.conllu
# Import the Validator class from the package subfolder regardless whether it
# is installed as a package.
# caution: path[0] is reserved for script path (or '' in REPL)
#sys.path.insert(1, 'validator/src/validator')
from validator.src.validator.validate import Validator



# The folder where this script resides.
THISDIR=os.path.dirname(os.path.realpath(os.path.abspath(__file__)))

# Constants for the column indices
COLCOUNT=10
ID,FORM,LEMMA,UPOS,XPOS,FEATS,HEAD,DEPREL,DEPS,MISC=range(COLCOUNT)
COLNAMES='ID,FORM,LEMMA,UPOS,XPOS,FEATS,HEAD,DEPREL,DEPS,MISC'.split(',')



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
        # Needed to check that no space after last word of sentence does not
        # co-occur with new paragraph or document.
        self.spaceafterno_in_effect = False
        # Error counter by error type. Key: error type; value: error count.
        # Incremented in Incident.report().
        self.error_counter = {}
        # Lists of errors for each type, up to --max_store
        # Key: error type; value: a list of the errors
        self.error_tracker = defaultdict(list)
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



class Data:
    """
    The Data class holds various dictionaries of tags, auxiliaries, regular
    expressions etc. needed for detailed testing, especially for language-
    specific constraints.
    """
    def __init__(self):
        # Universal part of speech tags in the UPOS column. Just a set.
        # For consistency, they are also read from a file. But these tags do
        # not change, so they could be even hard-coded here.
        self.upos = set()
        # Morphological features in the FEATS column.
        # Key: language code; value: feature-value-UPOS data from feats.json.
        self.feats = {}
        # Universal dependency relation types (without subtypes) in the DEPREL
        # column. For consistency, they are also read from a file. but these
        # labels do not change, so they could be even hard-coded here.
        self.udeprel = set()
        # Dependency relation types in the DEPREL column.
        # Key: language code; value: deprel data from deprels.json.
        # Cached processed version: key: language code; value: set of deprels.
        self.deprel = {}
        self.cached_deprel_for_language = {}
        # Enhanced dependency relation types in the DEPS column.
        # Key: language code; value: edeprel data from edeprels.json.
        # Cached processed version: key: language code; value: set of edeprels.
        self.edeprel = {}
        self.cached_edeprel_for_language = {}
        # Auxiliary (and copula) lemmas in the LEMMA column.
        # Key: language code; value: auxiliary/copula data from data.json.
        # Cached processed versions: key: language code; value: list of lemmas.
        self.auxcop = {}
        self.cached_aux_for_language = {}
        self.cached_cop_for_language = {}
        # Tokens with spaces in the FORM and LEMMA columns.
        # Key: language code; value: data from tospace.json.
        self.tospace = {}
        # Load language-specific data from external JSON files.
        self.load()
        # For each of the language-specific lists, we can generate an
        # explanation for the user in case they use something that is not on
        # the list. The explanation will be printed only once but the explain
        # function may be called thousand times, so let us cache the output to
        # reduce the time waste a little.
        self._explanation_feats = {}
        self._explanation_deprel = {}
        self._explanation_edeprel = {}
        self._explanation_aux = {}
        self._explanation_cop = {}
        self._explanation_tospace = {}

    def get_feats_for_language(self, lcode):
        """
        Searches the previously loaded database of feature-value-UPOS combinations.
        Returns the data for a given language code, organized in dictionaries.
        Returns an empty dict if there are no data for the given language code.
        """
        ###!!! If lcode is 'ud', we should permit all universal feature-value pairs,
        ###!!! regardless of language-specific documentation.
        # Do not crash if the user asks for an unknown language.
        if not lcode in self.feats:
            return {}
        return self.feats[lcode]

    def get_deprel_for_language(self, lcode):
        """
        Searches the previously loaded database of dependency relation labels.
        Returns the set of permitted deprels for a given language code. Also
        saves the result in self so that next time it can be fetched quickly
        (once we loaded the data, we do not expect them to change).
        """
        if lcode in self.cached_deprel_for_language:
            return self.cached_deprel_for_language[lcode]
        deprelset = set()
        # If lcode is 'ud', we should permit all universal dependency relations,
        # regardless of language-specific documentation.
        if lcode == 'ud':
            deprelset = self.udeprel
        elif lcode in self.deprel:
            for r in self.deprel[lcode]:
                if self.deprel[lcode][r]['permitted'] > 0:
                    deprelset.add(r)
        self.cached_deprel_for_language[lcode] = deprelset
        return deprelset

    def get_edeprel_for_language(self, lcode):
        """
        Searches the previously loaded database of enhanced case markers.
        Returns the set of permitted edeprels for a given language code. Also
        saves the result in self so that next time it can be fetched quickly
        (once we loaded the data, we do not expect them to change).
        """
        if lcode in self.cached_edeprel_for_language:
            return self.cached_edeprel_for_language[lcode]
        basic_deprels = self.get_deprel_for_language(lcode)
        edeprelset = basic_deprels | {'ref'}
        for bdeprel in basic_deprels:
            if re.match(r"^[nc]subj(:|$)", bdeprel):
                edeprelset.add(bdeprel+':xsubj')
        if lcode in self.edeprel:
            for c in self.edeprel[lcode]:
                for deprel in self.edeprel[lcode][c]['extends']:
                    for bdeprel in basic_deprels:
                        if bdeprel == deprel or re.match(r"^"+deprel+':', bdeprel):
                            edeprelset.add(bdeprel+':'+c)
        self.cached_edeprel_for_language[lcode] = edeprelset
        return edeprelset

    def get_auxcop_for_language(self, lcode):
        """
        Searches the previously loaded database of auxiliary/copula lemmas.
        Returns the AUX and COP lists for a given language code. Also saves
        the result in self so that next time it can be fetched quickly (once
        we loaded the data, we do not expect them to change).
        """
        if lcode in self.cached_aux_for_language and lcode in self.cached_cop_for_language:
            return self.cached_aux_for_language[lcode], self.cached_cop_for_language[lcode]
        # If any of the functions of the lemma is other than cop.PRON, it counts as an auxiliary.
        # If any of the functions of the lemma is cop.*, it counts as a copula.
        auxlist = []
        coplist = []
        lemmalist = self.auxcop.get(lcode, {}).keys()
        auxlist = [x for x in lemmalist
                   if len([y for y in self.auxcop[lcode][x]['functions']
                    if y['function'] != 'cop.PRON']) > 0]
        coplist = [x for x in lemmalist
                   if len([y for y in self.auxcop[lcode][x]['functions']
                    if re.match(r"^cop\.", y['function'])]) > 0]
        self.cached_aux_for_language[lcode] = auxlist
        self.cached_cop_for_language[lcode] = coplist
        return auxlist, coplist

    def get_aux_for_language(self, lcode):
        """
        An entry point for get_auxcop_for_language() that returns only the aux
        list. It either takes the cached list (if available), or calls
        get_auxcop_for_language().
        """
        if lcode in self.cached_aux_for_language:
            return self.cached_aux_for_language[lcode]
        auxlist, coplist = self.get_auxcop_for_language(lcode)
        return auxlist

    def get_cop_for_language(self, lcode):
        """
        An entry point for get_auxcop_for_language() that returns only the cop
        list. It either takes the cached list (if available), or calls
        get_auxcop_for_language().
        """
        if lcode in self.cached_cop_for_language:
            return self.cached_cop_for_language[lcode]
        auxlist, coplist = self.get_auxcop_for_language(lcode)
        return coplist

    def get_tospace_for_language(self, lcode):
        """
        Searches the previously loaded database of regular expressions describing
        permitted tokens with spaces. Returns the expressions for a given language code.
        """
        # Do not crash if the user asks for an unknown language.
        if not lcode in self.tospace:
            return None
        return self.tospace[lcode]

    def explain_feats(self, lcode):
        """
        Returns explanation message for features of a particular language.
        To be called after language-specific features have been loaded.
        """
        if lcode in self._explanation_feats:
            return self._explanation_feats[lcode]
        featset = self.get_feats_for_language(lcode)
        # Prepare a global message about permitted features and values. We will add
        # it to the first error message about an unknown feature. Note that this
        # global information pertains to the default validation language and it
        # should not be used with code-switched segments in alternative languages.
        msg = ''
        if not lcode in data.feats:
            msg += f"No feature-value pairs have been permitted for language [{lcode}].\n"
            msg += "They can be permitted at the address below (if the language has an ISO code and is registered with UD):\n"
            msg += "https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_feature.pl\n"
        else:
            # Identify feature values that are permitted in the current language.
            for f in featset:
                for e in featset[f]['errors']:
                    msg += f"ERROR in _{lcode}/feat/{f}.md: {e}\n"
            res = set()
            for f in featset:
                if featset[f]['permitted'] > 0:
                    for v in featset[f]['uvalues']:
                        res.add(f+'='+v)
                    for v in featset[f]['lvalues']:
                        res.add(f+'='+v)
            sorted_documented_features = sorted(res)
            msg += f"The following {len(sorted_documented_features)} feature values are currently permitted in language [{lcode}]:\n"
            msg += ', '.join(sorted_documented_features) + "\n"
            msg += "If a language needs a feature that is not documented in the universal guidelines, the feature must\n"
            msg += "have a language-specific documentation page in a prescribed format.\n"
            msg += "See https://universaldependencies.org/contributing_language_specific.html for further guidelines.\n"
            msg += "All features including universal must be specifically turned on for each language in which they are used.\n"
            msg += "See https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_feature.pl for details.\n"
        self._explanation_feats[lcode] = msg
        return msg

    def explain_deprel(self, lcode):
        """
        Returns explanation message for deprels of a particular language.
        To be called after language-specific deprels have been loaded.
        """
        if lcode in self._explanation_deprel:
            return self._explanation_deprel[lcode]
        deprelset = self.get_deprel_for_language(lcode)
        # Prepare a global message about permitted relation labels. We will add
        # it to the first error message about an unknown relation. Note that this
        # global information pertains to the default validation language and it
        # should not be used with code-switched segments in alternative languages.
        msg = ''
        if len(deprelset) == 0:
            msg += f"No dependency relation types have been permitted for language [{lcode}].\n"
            msg += "They can be permitted at the address below (if the language has an ISO code and is registered with UD):\n"
            msg += "https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_deprel.pl\n"
        else:
            # Identify dependency relations that are permitted in the current language.
            # If there are errors in documentation, identify the erroneous doc file.
            # Note that data.deprel[lcode] may not exist even though we have a non-empty
            # set of relations, if lcode is 'ud'.
            if lcode in data.deprel:
                for r in data.deprel[lcode]:
                    file = re.sub(r':', r'-', r)
                    if file == 'aux':
                        file = 'aux_'
                    for e in data.deprel[lcode][r]['errors']:
                        msg += f"ERROR in _{lcode}/dep/{file}.md: {e}\n"
            sorted_documented_relations = sorted(deprelset)
            msg += f"The following {len(sorted_documented_relations)} relations are currently permitted in language [{lcode}]:\n"
            msg += ', '.join(sorted_documented_relations) + "\n"
            msg += "If a language needs a relation subtype that is not documented in the universal guidelines, the relation\n"
            msg += "must have a language-specific documentation page in a prescribed format.\n"
            msg += "See https://universaldependencies.org/contributing_language_specific.html for further guidelines.\n"
            msg += "Documented dependency relations can be specifically turned on/off for each language in which they are used.\n"
            msg += "See https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_deprel.pl for details.\n"
        self._explanation_deprel[lcode] = msg
        return msg

    def explain_edeprel(self, lcode):
        """
        Returns explanation message for edeprels of a particular language.
        To be called after language-specific edeprels have been loaded.
        """
        if lcode in self._explanation_edeprel:
            return self._explanation_edeprel[lcode]
        edeprelset = self.get_edeprel_for_language(lcode)
        # Prepare a global message about permitted relation labels. We will add
        # it to the first error message about an unknown relation. Note that this
        # global information pertains to the default validation language and it
        # should not be used with code-switched segments in alternative languages.
        msg = ''
        if len(edeprelset) == 0:
            msg += f"No enhanced dependency relation types (case markers) have been permitted for language [{lcode}].\n"
            msg += "They can be permitted at the address below (if the language has an ISO code and is registered with UD):\n"
            msg += "https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_edeprel.pl\n"
        else:
            # Identify dependency relations that are permitted in the current language.
            # If there are errors in documentation, identify the erroneous doc file.
            # Note that data.deprel[lcode] may not exist even though we have a non-empty
            # set of relations, if lcode is 'ud'.
            sorted_case_markers = sorted(edeprelset)
            msg += f"The following {len(sorted_case_markers)} enhanced relations are currently permitted in language [{lcode}]:\n"
            msg += ', '.join(sorted_case_markers) + "\n"
            msg += "See https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_edeprel.pl for details.\n"
        self._explanation_deprel[lcode] = msg
        return msg

    def explain_aux(self, lcode):
        """
        Returns explanation message for auxiliaries of a particular language.
        To be called after language-specific auxiliaries have been loaded.
        """
        if lcode in self._explanation_aux:
            return self._explanation_aux[lcode]
        auxdata = self.get_aux_for_language(lcode)
        # Prepare a global message about permitted auxiliary lemmas. We will add
        # it to the first error message about an unknown auxiliary. Note that this
        # global information pertains to the default validation language and it
        # should not be used with code-switched segments in alternative languages.
        msg = ''
        if len(auxdata) == 0:
            msg += f"No auxiliaries have been documented at the address below for language [{lcode}].\n"
            msg += f"https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_auxiliary.pl?lcode={lcode}\n"
        else:
            # Identify auxiliaries that are permitted in the current language.
            msg += f"The following {len(auxdata)} auxiliaries are currently documented in language [{lcode}]:\n"
            msg += ', '.join(auxdata) + "\n"
            msg += f"See https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_auxiliary.pl?lcode={lcode} for details.\n"
        self._explanation_aux[lcode] = msg
        return msg

    def explain_cop(self, lcode):
        """
        Returns explanation message for copulas of a particular language.
        To be called after language-specific copulas have been loaded.
        """
        if lcode in self._explanation_cop:
            return self._explanation_cop[lcode]
        copdata = self.get_cop_for_language(lcode)
        # Prepare a global message about permitted copula lemmas. We will add
        # it to the first error message about an unknown copula. Note that this
        # global information pertains to the default validation language and it
        # should not be used with code-switched segments in alternative languages.
        msg = ''
        if len(copdata) == 0:
            msg += f"No copulas have been documented at the address below for language [{lcode}].\n"
            msg += f"https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_auxiliary.pl?lcode={lcode}\n"
        else:
            # Identify auxiliaries that are permitted in the current language.
            msg += f"The following {len(copdata)} copulas are currently documented in language [{lcode}]:\n"
            msg += ', '.join(copdata) + "\n"
            msg += f"See https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_auxiliary.pl?lcode={lcode} for details.\n"
        self._explanation_cop[lcode] = msg
        return msg

    def explain_tospace(self, lcode):
        """
        Returns explanation message for tokens with spaces of a particular language.
        To be called after language-specific tokens with spaces have been loaded.
        """
        if lcode in self._explanation_tospace:
            return self._explanation_tospace[lcode]
        # Prepare a global message about permitted features and values. We will add
        # it to the first error message about an unknown token with space. Note that
        # this global information pertains to the default validation language and it
        # should not be used with code-switched segments in alternative languages.
        msg = ''
        if not lcode in self.tospace:
            msg += f"No tokens with spaces have been permitted for language [{lcode}].\n"
            msg += "They can be permitted at the address below (if the language has an ISO code and is registered with UD):\n"
            msg += "https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_token_with_space.pl\n"
        else:
            msg += f"Only tokens and lemmas matching the following regular expression are currently permitted to contain spaces in language [{lcode}]:\n"
            msg += self.tospace[lcode][0]
            msg += "\nOthers can be permitted at the address below (if the language has an ISO code and is registered with UD):\n"
            msg += "https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_token_with_space.pl\n"
        self._explanation_tospace[lcode] = msg
        return msg

    def load(self):
        """
        Loads the external validation data such as permitted feature-value
        combinations, and stores them in self. The source JSON files are
        supposed to be in the data subfolder of the folder where the script
        lives.
        """
        with open(os.path.join(THISDIR, 'data', 'upos.json'), 'r', encoding='utf-8') as f:
            contents = json.load(f)
        upos_list = contents['upos']
        self.upos = set(upos_list)
        with open(os.path.join(THISDIR, 'data', 'feats.json'), 'r', encoding='utf-8') as f:
            contents = json.load(f)
        self.feats = contents['features']
        with open(os.path.join(THISDIR, 'data', 'udeprels.json'), 'r', encoding='utf-8') as f:
            contents = json.load(f)
        udeprel_list = contents['udeprels']
        self.udeprel = set(udeprel_list)
        with open(os.path.join(THISDIR, 'data', 'deprels.json'), 'r', encoding='utf-8') as f:
            contents = json.load(f)
        self.deprel = contents['deprels']
        with open(os.path.join(THISDIR, 'data', 'edeprels.json'), 'r', encoding='utf-8') as f:
            contents = json.load(f)
        self.edeprel = contents['edeprels']
        with open(os.path.join(THISDIR, 'data', 'data.json'), 'r', encoding='utf-8') as f:
            contents = json.load(f)
        self.auxcop = contents['auxiliaries']
        with open(os.path.join(THISDIR, 'data', 'tospace.json'), 'r', encoding='utf-8') as f:
            contents = json.load(f)
        # There is one or more regular expressions for each language in the file.
        # If there are multiple expressions, combine them in one and compile it.
        self.tospace = {}
        for l in contents['expressions']:
            combination = '('+'|'.join(sorted(list(contents['expressions'][l])))+')'
            compilation = re.compile(combination)
            self.tospace[l] = (combination, compilation)



class CompiledRegexes:
    """
    The CompiledRegexes class holds various regular expressions needed to
    recognize individual elements of the CoNLL-U format, precompiled to speed
    up parsing. Individual expressions are typically not enclosed in ^...$
    because one can use re.fullmatch() if it is desired that the whole string
    matches the expression.
    """
    def __init__(self):
        # Whitespace.
        self.ws = re.compile(r"\s+")
        # Two consecutive whitespaces.
        self.ws2 = re.compile(r"\s\s")
        # Regular word/node id: integer number.
        self.wordid = re.compile(r"[1-9][0-9]*")
        # Multiword token id: range of integers.
        # The two parts are bracketed so they can be captured and processed separately.
        self.mwtid = re.compile(r"([1-9][0-9]*)-([1-9][0-9]*)")
        # Empty node id: "decimal" number (but 1.10 != 1.1).
        # The two parts are bracketed so they can be captured and processed separately.
        self.enodeid = re.compile(r"([0-9]+)\.([1-9][0-9]*)")
        # New document comment line. Document id, if present, is bracketed.
        self.newdoc = re.compile(r"#\s*newdoc(?:\s+(\S+))?")
        # New paragraph comment line. Paragraph id, if present, is bracketed.
        self.newpar = re.compile(r"#\s*newpar(?:\s+(\S+))?")
        # Sentence id comment line. The actual id is bracketed.
        self.sentid = re.compile(r"#\s*sent_id\s*=\s*(\S+)")
        # Parallel sentence id comment line. The actual id as well as its predefined parts are bracketed.
        self.parallelid = re.compile(r"#\s*parallel_id\s*=\s*(([a-z]+)/([-0-9a-z]+)(?:/(alt[1-9][0-9]*|part[1-9][0-9]*|alt[1-9][0-9]*part[1-9][0-9]*))?)")
        # Sentence text comment line. The actual text is bracketed.
        self.text = re.compile(r"#\s*text\s*=\s*(.*\S)")
        # Global entity comment is a declaration of entity attributes in MISC.
        # It occurs once per document and it is optional (only CorefUD data).
        # The actual attribute declaration is bracketed so it can be captured in the match.
        self.global_entity = re.compile(r"#\s*global\.Entity\s*=\s*(.+)")
        # UPOS tag.
        self.upos = re.compile(r"[A-Z]+")
        # Feature=value pair.
        # Feature name and feature value are bracketed so that each can be captured separately in the match.
        self.featval = re.compile(r"([A-Z][A-Za-z0-9]*(?:\[[a-z0-9]+\])?)=(([A-Z0-9][A-Z0-9a-z]*)(,([A-Z0-9][A-Z0-9a-z]*))*)")
        self.val = re.compile(r"[A-Z0-9][A-Za-z0-9]*")
        # Basic parent reference (HEAD).
        self.head = re.compile(r"(0|[1-9][0-9]*)")
        # Enhanced parent reference (head).
        self.ehead = re.compile(r"(0|[1-9][0-9]*)(\.[1-9][0-9]*)?")
        # Basic dependency relation (including optional subtype).
        self.deprel = re.compile(r"[a-z]+(:[a-z]+)?")
        # Enhanced dependency relation (possibly with Unicode subtypes).
        # Ll ... lowercase Unicode letters
        # Lm ... modifier Unicode letters (e.g., superscript h)
        # Lo ... other Unicode letters (all caseless scripts, e.g., Arabic)
        # M .... combining diacritical marks
        # Underscore is allowed between letters but not at beginning, end, or next to another underscore.
        edeprelpart_resrc = r'[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(_[\p{Ll}\p{Lm}\p{Lo}\p{M}]+)*'
        # There must be always the universal part, consisting only of ASCII letters.
        # There can be up to three additional, colon-separated parts: subtype, preposition and case.
        # One of them, the preposition, may contain Unicode letters. We do not know which one it is
        # (only if there are all four parts, we know it is the third one).
        # ^[a-z]+(:[a-z]+)?(:[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(_[\p{Ll}\p{Lm}\p{Lo}\p{M}]+)*)?(:[a-z]+)?$
        edeprel_resrc = '^[a-z]+(:[a-z]+)?(:' + edeprelpart_resrc + ')?(:[a-z]+)?$'
        self.edeprel = re.compile(edeprel_resrc)



# Global variables:
data = Data()
crex = CompiledRegexes()



class Incident:
    """
    Instances of this class describe individual errors or warnings in the input
    file.
    """
    # We can modify the class-level defaults before a batch of similar tests.
    # Then we do not have to repeat the shared parameters for each test.
    default_level = 1
    default_testclass = 'Format'
    default_testid = 'generic-error'
    default_message = 'No error description provided.'
    default_lineno = None
    def __init__(self, state, config, level=None, testclass=None, testid=None, message=None, lineno=None, nodeid=None, explanation=''):
        self.state = state
        self.config = config

        # Validation level to which the incident belongs. Integer 1-5.
        self.level = self.default_level if level == None else level
        # Thematic area to which the incident belongs: Format, Meta, Morpho,
        # Syntax, Enhanced, Coref, Warning.
        self.testclass = self.default_testclass if testclass == None else testclass
        # Identifier of the test that lead to the incident. Short string.
        self.testid = self.default_testid if testid == None else testid
        # Verbose description of the error for the user. It does not have to be
        # identical for all errors with the same testid because it can contain
        # instance-specific data (e.g. the word form).
        self.message = self.default_message if message == None else message
        # Additional more verbose information. To be printed with the first
        # incident of a given type.
        self.explanation = explanation
        # File name. The default is the file from which we are reading right
        # now ('-' if reading from STDIN).
        self.filename = 'STDIN' if state.current_file_name == '-' else os.path.basename(state.current_file_name)
        # Line number. The default is the most recently read line as recorded
        # in the state; but in most cases we need to get the number
        # during instantiation, as the most recently read line is the last line
        # of the sentence, and the error was found on one of the words of the
        # sentence.
        self.lineno = lineno if lineno != None else self.default_lineno if self.default_lineno != None else state.current_line
        if self.lineno < 0:
            self.lineno = state.sentence_line
        # Current (most recently read) sentence id.
        self.sentid = state.sentence_id
        # ID of the node on which the error occurred (if it pertains to one node).
        self.nodeid = nodeid

    def report(self):
        # Even if we should be quiet, at least count the error.
        self.state.error_counter[self.testclass] = self.state.error_counter.get(self.testclass, 0)+1
        if not 'max_store' in self.config or self.config['max_store'] <= 0 or len(self.state.error_tracker[self.testclass]) < self.config['max_store']:
            self.state.error_tracker[self.testclass].append(self)
        if 'quiet' in self.config and self.config['quiet']:
            return
        # Suppress error messages of a type of which we have seen too many.
        if 'max_err' in self.config and self.config['max_err'] > 0 and self.state.error_counter[self.testclass] > self.config['max_err']:
            if self.state.error_counter[self.testclass] == self.config['max_err'] + 1:
                print(f'...suppressing further errors regarding {self.testclass}', file=sys.stderr)
            return # suppressed
        # If we are here, the error message should really be printed.
        # Address of the incident.
        address = f'Line {self.lineno} Sent {self.sentid}'
        # Insert file name if there are several input files.
        if 'n_files' in self.config and self.config['n_files'] > 1:
            address = f'File {self.filename} ' + address
        # Classification of the incident.
        levelclassid = f'L{self.level} {self.testclass} {self.testid}'
        # Message (+ explanation, if this is the first error of its kind).
        message = self.message
        if self.explanation and self.explanation not in self.state.explanation_printed:
            message += "\n\n" + self.explanation + "\n"
            self.state.explanation_printed.add(self.explanation)
        print(f'[{address}]: [{levelclassid}] {message}', file=sys.stderr)



# Support functions.

def is_whitespace(line):
    return crex.ws.fullmatch(line)

def is_word(cols):
    return crex.wordid.fullmatch(cols[ID])

def is_multiword_token(cols):
    return crex.mwtid.fullmatch(cols[ID])

def is_empty_node(cols):
    return crex.enodeid.fullmatch(cols[ID])

def parse_empty_node_id(cols):
    m = crex.enodeid.fullmatch(cols[ID])
    assert m, 'parse_empty_node_id with non-empty node'
    return m.groups()

def shorten(string):
    return string if len(string) < 25 else string[:20]+'[...]'

def lspec2ud(deprel):
    return deprel.split(':', 1)[0]

def formtl(node):
    """
    Returns the word form of a node, possibly accompanied by its
    transliteration (if available in the MISC column).

    Parameters
    ----------
    node : udapi.core.node.Node object
        The node whose form we want to get.

    Returns
    -------
    x : str
        The form and translit, space-separated. Only form if translit
        not available.
    """
    x = node.form
    if node.misc['Translit'] != '':
        x += ' ' + node.misc['Translit']
    return x

def lemmatl(node):
    """
    Returns the lemma of a node, possibly accompanied by its transliteration
    (if available in the MISC column).

    Parameters
    ----------
    node : udapi.core.node.Node object
        The node whose form we want to get.

    Returns
    -------
    x : str
        The lemma and translit, space-separated. Only form if translit not
        available.
    """
    x = node.lemma
    if node.misc['LTranslit'] != '':
        x += ' ' + node.misc['LTranslit']
    return x



def get_alt_language(node):
    """
    In code-switching analysis of foreign words, an attribute in the MISC column
    will hold the code of the language of the current word. Certain tests will
    then use language-specific lists from that language instead of the main
    language of the document. This function returns the alternative language
    code if present, otherwise it returns None.

    Parameters
    ----------
    node : udapi.core.node.Node object
        The node (word) whose language is being queried.
    """
    if node.misc['Lang'] != '':
        return node.misc['Lang']
    return None


#==============================================================================
# Argument processing.
#==============================================================================


def build_argparse():
    opt_parser = argparse.ArgumentParser(description="CoNLL-U validation script. Python 3 is needed to run it!")

    io_group = opt_parser.add_argument_group("Input / output options")
    io_group.add_argument('--quiet',
                          dest="quiet", action="store_true", default=False,
                          help="""Do not print any error messages.
                          Exit with 0 on pass, non-zero on fail.""")
    io_group.add_argument('--max-err',
                          action="store", type=int, default=20,
                          help="""How many errors to output before exiting? 0 for all.
                          Default: %(default)d.""")
    io_group.add_argument('--max-store',
                          action="store", type=int, default=20,
                          help="""How many errors to save when collecting errors. 0 for all.
                          Default: %(default)d.""")
    io_group.add_argument('input',
                          nargs='*',
                          help="""Input file name(s), or "-" or nothing for standard input.""")

    list_group = opt_parser.add_argument_group("Tag sets", "Options relevant to checking tag sets.")
    list_group.add_argument("--lang",
                            action="store", required=True, default=None,
                            help="""Which langauge are we checking?
                            If you specify this (as a two-letter code), the tags will be checked
                            using the language-specific files in the
                            data/directory of the validator.""")
    list_group.add_argument("--level",
                            action="store", type=int, default=5, dest="level",
                            help="""Level 1: Test only CoNLL-U backbone.
                            Level 2: UD format.
                            Level 3: UD contents.
                            Level 4: Language-specific labels.
                            Level 5: Language-specific contents.""")

    coref_group = opt_parser.add_argument_group("Coreference / entity constraints",
                                                "Options for checking coreference and entity annotation.")
    coref_group.add_argument('--coref',
                             action='store_true', default=False, dest='check_coref',
                             help='Test coreference and entity-related annotation in MISC.')
    return opt_parser

def parse_args(args=None):
    """
    Creates an instance of the ArgumentParser and parses the command line
    arguments.

    Parameters
    ----------
    args : list of strings, optional
        If not supplied, the argument parser will read sys.args instead.
        Otherwise the caller can supply list such as ['--lang', 'en'].

    Returns
    -------
    args : argparse.Namespace
        Values of individual arguments can be accessed as object properties
        (using the dot notation). It is possible to convert it to a dict by
        calling vars(args).
    """
    opt_parser = build_argparse()
    args = opt_parser.parse_args(args=args)
    # Level of validation.
    if args.level < 1:
        print(f'Option --level must not be less than 1; changing from {args.level} to 1',
              file=sys.stderr)
        args.level = 1
    # No language-specific tests for levels 1-3.
    # Anyways, any Feature=Value pair should be allowed at level 3 (because it may be language-specific),
    # and any word form or lemma can contain spaces (because language-specific guidelines may allow it).
    # We can also test language 'ud' on level 4; then it will require that no language-specific features are present.
    if args.level < 4:
        args.lang = 'ud'
    if args.input == []:
        args.input.append('-')
    return args

def main():
    args = parse_args()
    validator = Validator(lang=args.lang, level=args.level, args=args)
    state = validator.validate_files(args.input)

    # Summarize the warnings and errors.
    passed = True
    nerror = 0
    if state.error_counter:
        for k, v in sorted(state.error_counter.items()):
            if k == 'Warning':
                errors = 'Warnings'
            else:
                errors = k+' errors'
                nerror += v
                passed = False
            if not args.quiet:
                print(f'{errors}: {v}', file=sys.stderr)
    # Print the final verdict and exit.
    if passed:
        if not args.quiet:
            print('*** PASSED ***', file=sys.stderr)
        return 0
    else:
        if not args.quiet:
            print(f'*** FAILED *** with {nerror} errors', file=sys.stderr)
        return 1

if __name__=="__main__":
    errcode = main()
    sys.exit(errcode)
