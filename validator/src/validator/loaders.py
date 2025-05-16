import os
import json
import re

import validator.globals as g

def load_file(filename):
    res = set()
    with open(filename, 'r', encoding='utf-8') as f:
        for line in f:
            line=line.strip()
            if not line or line.startswith('#'):
                continue
            res.add(line)
    return res

def load_json_data(filename, key):
    """
    Loads the list of permitted UPOS tags and returns it as a set.
    """
    with open(os.path.join(g.THISDIR, 'data', filename), encoding="utf-8") as fin:
        res = json.load(fin)
    return res[key]

def load_feat_set(filename_langspec, lcode):
    """
    Loads the list of permitted feature-value pairs and returns it as a set.
    """
    with open(os.path.join(g.THISDIR, 'data', filename_langspec), 'r', encoding='utf-8') as f:
        all_features_0 = json.load(f)
    g.featdata = all_features_0['features']
    featset = get_featdata_for_language(lcode)
    # Prepare a global message about permitted features and values. We will add
    # it to the first error message about an unknown feature. Note that this
    # global information pertains to the default validation language and it
    # should not be used with code-switched segments in alternative languages.
    msg = ''
    if not lcode in g.featdata:
        msg += f"No feature-value pairs have been permitted for language [{lcode}].\n"
        msg += "They can be permitted at the address below (if the language has an ISO code and is registered with UD):\n"
        msg += "https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_feature.pl\n"
        g.warn_on_undoc_feats = msg
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
        warn_on_undoc_feats = msg
    return featset

def get_featdata_for_language(lcode):
    """
    Searches the previously loaded database of feature-value combinations.
    Returns the lists for a given language code. For most CoNLL-U files,
    this function is called only once at the beginning. However, some files
    contain code-switched data and we may temporarily need to validate
    another language.
    """
    ###!!! If lcode is 'ud', we should permit all universal feature-value pairs,
    ###!!! regardless of language-specific documentation.
    # Do not crash if the user asks for an unknown language.
    if not lcode in g.featdata:
        return {} ###!!! or None?
    return g.featdata[lcode]

def get_auxdata_for_language(lcode):
    """
    Searches the previously loaded database of auxiliary/copula lemmas. Returns
    the AUX and COP lists for a given language code. For most CoNLL-U files,
    this function is called only once at the beginning. However, some files
    contain code-switched data and we may temporarily need to validate
    another language.
    """
    auxdata = g.auxdata
    # If any of the functions of the lemma is other than cop.PRON, it counts as an auxiliary.
    # If any of the functions of the lemma is cop.*, it counts as a copula.
    auxlist = []
    coplist = []
    if lcode == 'shopen':
        for lcode1 in auxdata.keys():
            lemmalist = auxdata[lcode1].keys()
            auxlist = auxlist + [x for x in lemmalist
                                 if len([y for y in auxdata[lcode1][x]['functions']
                                    if y['function'] != 'cop.PRON']) > 0]
            coplist = coplist + [x for x in lemmalist
                                 if len([y for y in auxdata[lcode1][x]['functions']
                                    if re.match(r"^cop\.", y['function'])]) > 0]
    else:
        lemmalist = auxdata.get(lcode, {}).keys()
        auxlist = [x for x in lemmalist
                   if len([y for y in auxdata[lcode][x]['functions']
                    if y['function'] != 'cop.PRON']) > 0]
        coplist = [x for x in lemmalist
                   if len([y for y in auxdata[lcode][x]['functions']
                    if re.match(r"^cop\.", y['function'])]) > 0]
    return auxlist, coplist