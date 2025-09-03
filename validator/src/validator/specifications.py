import os
from dataclasses import dataclass, field
from typing import Set, Dict
import regex as re

import validator.loaders as loaders

@dataclass
class UDSpecs:
    """
    The UDSpecs class holds various dictionaries of tags, auxiliaries, regular
    expressions etc. needed for detailed testing, especially for language-
    specific constraints.
    """
    data_folder: str
    # Universal part of speech tags in the UPOS column. Just a set.
    upos: Set = field(init=False)
    # Morphological features in the FEATS column.
    # Key: language code; value: feature-value-UPOS data from feats.json.
    feats: Dict = field(init=False)
    # Universal dependency relation types (without subtypes) in the DEPREL
    # column.
    udeprel: Set = field(init=False)
    # Dependency relation types in the DEPREL column.
    # Key: language code; value: deprel data from deprels.json.
    # Cached processed version: key: language code; value: set of deprels. #! what is this?
    deprel: Dict = field(init=False)
    cached_deprel_for_language: Dict = field(init=False)
    # Enhanced dependency relation types in the DEPS column.
    # Key: language code; value: edeprel data from edeprels.json.
    # Cached processed version: key: language code; value: set of edeprels. #! what is this?
    edeprel: Dict = field(init=False)
    cached_edeprel_for_language: Dict = field(init=False)
    # Auxiliary (and copula) lemmas in the LEMMA column.
    # Key: language code; value: auxiliary/copula data from data.json.
    # Cached processed versions: key: language code; value: list of lemmas. #! what is this?
    auxcop: Dict = field(init=False)
    cached_aux_for_language: Dict = field(init=False)
    cached_cop_for_language: Dict = field(init=False)
    # Tokens with spaces in the FORM and LEMMA columns.
    # Key: language code; value: data from tospace.json.
    # There is one or more regular expressions for each language in the file.
    # If there are multiple expressions, combine them in one and compile it.
    tospace: Dict = field(init=False)

    def __post_init__(self):

        self.upos = loaders.load_json_data_set(os.path.join(self.data_folder, "upos.json"), "upos")

        self.feats = loaders.load_json_data(os.path.join(self.data_folder, "feats.json"), "features")

        self.udeprel = loaders.load_json_data_set(os.path.join(self.data_folder, "udeprels.json"), "udeprels") #! change to plural

        self.deprel = loaders.load_json_data_set(os.path.join(self.data_folder, "deprels.json"), "deprels") #! change to plural

        self.cached_deprel_for_language = {}

        self.edeprel = loaders.load_json_data(os.path.join(self.data_folder,"edeprels.json"), "edeprels")#! change to plural

        self.cached_edeprel_for_language =  {} 
        
        self.auxcop = loaders.load_json_data(os.path.join(self.data_folder,"data.json"), "auxiliaries") #! change to plural
        
        self.cached_aux_for_language = {}
        
        self.cached_cop_for_language = {}


        self.tospace = loaders.load_combinations(os.path.join(self.data_folder,"tospace.json"))

    # TODO: understand what do these functions do
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