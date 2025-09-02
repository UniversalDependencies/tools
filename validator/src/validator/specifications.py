import os
from dataclasses import dataclass, field
from typing import Set, Dict

import validator.loaders as loaders

@dataclass
class UDSpecs:
    """
    The UDSpecs class holds various dictionaries of tags, auxiliaries, regular
    expressions etc. needed for detailed testing, especially for language-
    specific constraints.
    """
    # Universal part of speech tags in the UPOS column. Just a set.
    upos: Set
    # Morphological features in the FEATS column.
    # Key: language code; value: feature-value-UPOS data from feats.json.
    feats: Dict
    # Universal dependency relation types (without subtypes) in the DEPREL
    # column.
    udeprel: Set
    # Dependency relation types in the DEPREL column.
    # Key: language code; value: deprel data from deprels.json.
    # Cached processed version: key: language code; value: set of deprels. #! what is this?
    deprel: Dict
    cached_deprel_for_language: Dict
    # Enhanced dependency relation types in the DEPS column.
    # Key: language code; value: edeprel data from edeprels.json.
    # Cached processed version: key: language code; value: set of edeprels. #! what is this?
    edeprel: Dict
    cached_edeprel_for_language: Dict
    # Auxiliary (and copula) lemmas in the LEMMA column.
    # Key: language code; value: auxiliary/copula data from data.json.
    # Cached processed versions: key: language code; value: list of lemmas. #! what is this?
    auxcop: Dict
    cached_aux_for_language: Dict
    cached_cop_for_language: Dict
    # Tokens with spaces in the FORM and LEMMA columns.
    # Key: language code; value: data from tospace.json.
    # There is one or more regular expressions for each language in the file.
    # If there are multiple expressions, combine them in one and compile it.
    tospace: Dict

    def __post_init__(self, data_folder):

        self.upos = loaders.load_json_data_set(os.path.join(data_folder, "upos.json"), "UPOS")

        self.feats = loaders.load_json_data(os.path.join(data_folder, "feats.json"), "features")

        self.udeprel = loaders.load_json_data_set(os.path.join(data_folder, "udeprels.json"), "udeprels") #! change to plural

        self.deprel = loaders.load_json_data_set(os.path.join(data_folder, "deprels.json"), "deprels") #! change to plural

        self.edeprel = loaders.load_json_data(os.path.join(data_folder,"edeprels.json"), "edeprels")#! change to plural

        self.auxcop = loaders.load_json_data(os.path.join(data_folder,"data.json"), "auxiliaries") #! change to plural

        self.tospace = loaders.load_combinations("tospace.json")

