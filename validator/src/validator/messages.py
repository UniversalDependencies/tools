def explain_feats(spec, lcode):
    """
    Returns explanation message for features of a particular language.
    To be called after language-specific features have been loaded.
    """
    if lcode in spec._explanation_feats:
        return spec._explanation_feats[lcode]
    featset = spec.get_feats_for_language(lcode)
    # Prepare a global message about permitted features and values. We will add
    # it to the first error message about an unknown feature. Note that this
    # global information pertains to the default validation language and it
    # should not be used with code-switched segments in alternative languages.
    msg = ''
    if not lcode in spec.feats:
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
    spec._explanation_feats[lcode] = msg
    return msg

def explain_deprel(spec, lcode):
    """
    Returns explanation message for deprels of a particular language.
    To be called after language-specific deprels have been loaded.
    """
    if lcode in spec._explanation_deprel:
        return spec._explanation_deprel[lcode]
    deprelset = spec.get_deprel_for_language(lcode)
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
        # Note that spec.deprel[lcode] may not exist even though we have a non-empty
        # set of relations, if lcode is 'ud'.
        if lcode in spec.deprel:
            for r in spec.deprel[lcode]:
                file = re.sub(r':', r'-', r)
                if file == 'aux':
                    file = 'aux_'
                for e in spec.deprel[lcode][r]['errors']:
                    msg += f"ERROR in _{lcode}/dep/{file}.md: {e}\n"
        sorted_documented_relations = sorted(deprelset)
        msg += f"The following {len(sorted_documented_relations)} relations are currently permitted in language [{lcode}]:\n"
        msg += ', '.join(sorted_documented_relations) + "\n"
        msg += "If a language needs a relation subtype that is not documented in the universal guidelines, the relation\n"
        msg += "must have a language-specific documentation page in a prescribed format.\n"
        msg += "See https://universaldependencies.org/contributing_language_specific.html for further guidelines.\n"
        msg += "Documented dependency relations can be specifically turned on/off for each language in which they are used.\n"
        msg += "See https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_deprel.pl for details.\n"
    spec._explanation_deprel[lcode] = msg
    return msg

def explain_edeprel(spec, lcode):
    """
    Returns explanation message for edeprels of a particular language.
    To be called after language-specific edeprels have been loaded.
    """
    if lcode in spec._explanation_edeprel:
        return spec._explanation_edeprel[lcode]
    edeprelset = spec.get_edeprel_for_language(lcode)
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
        # Note that spec.deprel[lcode] may not exist even though we have a non-empty
        # set of relations, if lcode is 'ud'.
        sorted_case_markers = sorted(edeprelset)
        msg += f"The following {len(sorted_case_markers)} enhanced relations are currently permitted in language [{lcode}]:\n"
        msg += ', '.join(sorted_case_markers) + "\n"
        msg += "See https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_edeprel.pl for details.\n"
    spec._explanation_deprel[lcode] = msg
    return msg

def explain_aux(spec, lcode):
    """
    Returns explanation message for auxiliaries of a particular language.
    To be called after language-specific auxiliaries have been loaded.
    """
    if lcode in spec._explanation_aux:
        return spec._explanation_aux[lcode]
    auxspec = spec.get_aux_for_language(lcode)
    # Prepare a global message about permitted auxiliary lemmas. We will add
    # it to the first error message about an unknown auxiliary. Note that this
    # global information pertains to the default validation language and it
    # should not be used with code-switched segments in alternative languages.
    msg = ''
    if len(auxspec) == 0:
        msg += f"No auxiliaries have been documented at the address below for language [{lcode}].\n"
        msg += f"https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_auxiliary.pl?lcode={lcode}\n"
    else:
        # Identify auxiliaries that are permitted in the current language.
        msg += f"The following {len(auxspec)} auxiliaries are currently documented in language [{lcode}]:\n"
        msg += ', '.join(auxspec) + "\n"
        msg += f"See https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_auxiliary.pl?lcode={lcode} for details.\n"
    spec._explanation_aux[lcode] = msg
    return msg

def explain_cop(spec, lcode):
    """
    Returns explanation message for copulas of a particular language.
    To be called after language-specific copulas have been loaded.
    """
    if lcode in spec._explanation_cop:
        return spec._explanation_cop[lcode]
    copspec = spec.get_cop_for_language(lcode)
    # Prepare a global message about permitted copula lemmas. We will add
    # it to the first error message about an unknown copula. Note that this
    # global information pertains to the default validation language and it
    # should not be used with code-switched segments in alternative languages.
    msg = ''
    if len(copspec) == 0:
        msg += f"No copulas have been documented at the address below for language [{lcode}].\n"
        msg += f"https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_auxiliary.pl?lcode={lcode}\n"
    else:
        # Identify auxiliaries that are permitted in the current language.
        msg += f"The following {len(copspec)} copulas are currently documented in language [{lcode}]:\n"
        msg += ', '.join(copspec) + "\n"
        msg += f"See https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_auxiliary.pl?lcode={lcode} for details.\n"
    spec._explanation_cop[lcode] = msg
    return msg

def explain_tospace(spec, lcode):
    """
    Returns explanation message for tokens with spaces of a particular language.
    To be called after language-specific tokens with spaces have been loaded.
    """
    if lcode in spec._explanation_tospace:
        return spec._explanation_tospace[lcode]
    # Prepare a global message about permitted features and values. We will add
    # it to the first error message about an unknown token with space. Note that
    # this global information pertains to the default validation language and it
    # should not be used with code-switched segments in alternative languages.
    msg = ''
    if not lcode in spec.tospace:
        msg += f"No tokens with spaces have been permitted for language [{lcode}].\n"
        msg += "They can be permitted at the address below (if the language has an ISO code and is registered with UD):\n"
        msg += "https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_token_with_space.pl\n"
    else:
        msg += f"Only tokens and lemmas matching the following regular expression are currently permitted to contain spaces in language [{lcode}]:\n"
        msg += spec.tospace[lcode][0]
        msg += "\nOthers can be permitted at the address below (if the language has an ISO code and is registered with UD):\n"
        msg += "https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_token_with_space.pl\n"
    spec._explanation_tospace[lcode] = msg
    return msg