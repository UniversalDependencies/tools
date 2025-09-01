import os
import json
import re

import validator.globals as g

def load_set(f_name_ud, lang, validate_langspec=False, validate_enhanced=False):
    """
    Loads a list of values from the two files, and returns their
    set. If lang doesn't exist, loads nothing and returns
    None (ie this taglist is not checked for the given language). If lang
    is None, only loads the UD one. This is probably only useful for CPOS which doesn't
    allow language-specific extensions. Set validate_langspec=True when loading basic dependencies.
    That way the language specific deps will be checked to be truly extensions of UD ones.
    Set validate_enhanced=True when loading enhanced dependencies. They will be checked to be
    truly extensions of universal relations, too; but a more relaxed regular expression will
    be checked because enhanced relations may contain stuff that is forbidden in the basic ones.
    """
    res = load_file(os.path.join(g.THISDIR, 'data', f_name_ud))
    # Now res holds UD
    # Next load and optionally check the langspec extensions
    if lang is not None and lang != f_name_ud:
            l_spec = load_file(os.path.join(g.THISDIR,"data","tokens_w_space.json"), lang)
            for v in l_spec:
                if validate_enhanced:
                    # We are reading the list of language-specific dependency relations in the enhanced representation
                    # (i.e., the DEPS column, not DEPREL). Make sure that they match the regular expression that
                    # restricts enhanced dependencies.
                    if not g.edeprel_re.match(v):
                        testlevel = 4
                        testclass = 'Enhanced'
                        testid = 'edeprel-def-regex'
                        testmessage = f"Spurious language-specific enhanced relation '{v}' - it does not match the regular expression that restricts enhanced relations."
                        warn(testmessage, testclass, testlevel, testid, lineno=-1)
                        continue
                elif validate_langspec:
                    # We are reading the list of language-specific dependency relations in the basic representation
                    # (i.e., the DEPREL column, not DEPS). Make sure that they match the regular expression that
                    # restricts basic dependencies. (In particular, that they do not contain extensions allowed in
                    # enhanced dependencies, which should be listed in a separate file.)
                    if not re.match(r"^[a-z]+(:[a-z]+)?$", v):
                        testlevel = 4
                        testclass = 'Syntax'
                        testid = 'deprel-def-regex'
                        testmessage = f"Spurious language-specific relation '{v}' - in basic UD, it must match '^[a-z]+(:[a-z]+)?'."
                        warn(testmessage, testclass, testlevel, testid, lineno=-1)
                        continue
                if validate_langspec or validate_enhanced:
                    try:
                        parts=v.split(':')
                        if parts[0] not in res and parts[0] != 'ref':
                            testlevel = 4
                            testclass = 'Syntax'
                            testid = 'deprel-def-universal-part'
                            testmessage = f"Spurious language-specific relation '{v}' - not an extension of any UD relation."
                            warn(testmessage, testclass, testlevel, testid, lineno=-1)
                            continue
                    except:
                        testlevel = 4
                        testclass = 'Syntax'
                        testid = 'deprel-def-universal-part'
                        testmessage = f"Spurious language-specific relation '{v}' - not an extension of any UD relation."
                        warn(testmessage, testclass, testlevel, testid, lineno=-1)
                        continue
                res.add(v)
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