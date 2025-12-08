import os.path
# According to https://stackoverflow.com/questions/1832893/python-regex-matching-unicode-properties,
# the regex module has the same API as re but it can check Unicode character properties using \p{}
# as in Perl.
#import re
import regex as re
import json



class Data:
    """
    The Data class holds various dictionaries of tags, auxiliaries, regular
    expressions etc. needed for detailed testing, especially for language-
    specific constraints.
    """
    def __init__(self, datapath=None):
        if datapath:
            self.datapath = datapath
        else:
            # The folder where this module resides.
            THISDIR = os.path.dirname(os.path.realpath(os.path.abspath(__file__)))
            # If this module was imported directly from the root folder of the
            # tools repository, the data folder should be a first-level subfolder
            # there. Otherwise, the module is taken from installed udtools and
            # the data is a subfolder here.
            self.datapath = os.path.join(THISDIR, '..', '..', '..', 'data')
            if not os.path.exists(self.datapath):
                self.datapath = os.path.join(THISDIR, 'data')
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
        if not lcode in self.feats:
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
            if lcode in self.deprel:
                for r in self.deprel[lcode]:
                    file = re.sub(r':', r'-', r)
                    if file == 'aux':
                        file = 'aux_'
                    for e in self.deprel[lcode][r]['errors']:
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
        with open(os.path.join(self.datapath, 'upos.json'), 'r', encoding='utf-8') as f:
            contents = json.load(f)
        upos_list = contents['upos']
        self.upos = set(upos_list)
        with open(os.path.join(self.datapath, 'feats.json'), 'r', encoding='utf-8') as f:
            contents = json.load(f)
        self.feats = contents['features']
        with open(os.path.join(self.datapath, 'udeprels.json'), 'r', encoding='utf-8') as f:
            contents = json.load(f)
        udeprel_list = contents['udeprels']
        self.udeprel = set(udeprel_list)
        with open(os.path.join(self.datapath, 'deprels.json'), 'r', encoding='utf-8') as f:
            contents = json.load(f)
        self.deprel = contents['deprels']
        with open(os.path.join(self.datapath, 'edeprels.json'), 'r', encoding='utf-8') as f:
            contents = json.load(f)
        self.edeprel = contents['edeprels']
        with open(os.path.join(self.datapath, 'data.json'), 'r', encoding='utf-8') as f:
            contents = json.load(f)
        self.auxcop = contents['auxiliaries']
        with open(os.path.join(self.datapath, 'tospace.json'), 'r', encoding='utf-8') as f:
            contents = json.load(f)
        # There is one or more regular expressions for each language in the file.
        # If there are multiple expressions, combine them in one and compile it.
        self.tospace = {}
        for l in contents['expressions']:
            combination = '('+'|'.join(sorted(list(contents['expressions'][l])))+')'
            compilation = re.compile(combination)
            self.tospace[l] = (combination, compilation)
