import regex as re

def explain_feats(specs, lcode):
    """
    Returns explanation message for features of a particular language.
    To be called after language-specific features have been loaded.

    Parameters
    ----------
    specs : UDSpecs object
        The UD specification.
    lcode : str
        The language code.

    Returns
    -------
    name : str
        The explanation message for the features of the given language.
    """
    featset = specs.get_feats_for_language(lcode)
    # Prepare a global message about permitted features and values. We will add
    # it to the first error message about an unknown feature. Note that this
    # global information pertains to the default validation language and it
    # should not be used with code-switched segments in alternative languages.
    msg = ''
    if not lcode in specs.feats:
        msg = (
            f"No feature-value pairs have been permitted for language [{lcode}].\n"
             "They can be permitted at the address below (if the language has an ISO code and is registered with UD):\n"
             "https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_feature.pl\n")
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
        msg += (
            f"The following {len(sorted_documented_features)} feature values are currently permitted in language [{lcode}]:\n"
             f"{', '.join(sorted_documented_features)}\n"
             "If a language needs a feature that is not documented in the universal guidelines, the feature must\n"
             "have a language-specific documentation page in a prescribed format\n"
             "See https://universaldependencies.org/contributing_language_specific.html for further guidelines.\n"
             "All features including universal must be specifically turned on for each language in which they are used.\n"
             "See https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_feature.pl for details.\n")
    return msg

def explain_deprel(specs, lcode):
    """
    Returns explanation message for deprels of a particular language.
    To be called after language-specific deprels have been loaded.

    Parameters
    ----------
    specs : UDSpecs object
        The UD specification.
    lcode : str
        The language code.

    Returns
    -------
    name : str
        The explanation message for the deprels of the given language.
    """
    deprelset = specs.get_deprel_for_language(lcode)
    # Prepare a global message about permitted relation labels. We will add
    # it to the first error message about an unknown relation. Note that this
    # global information pertains to the default validation language and it
    # should not be used with code-switched segments in alternative languages.
    msg = ''
    if len(deprelset) == 0:
        msg = (
            f"No dependency relation types have been permitted for language [{lcode}].\n"
             "They can be permitted at the address below (if the language has an ISO code and is registered with UD):\n"
             "https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_deprel.pl\n")
    else:
        # Identify dependency relations that are permitted in the current language.
        # If there are errors in documentation, identify the erroneous doc file.
        # Note that specs.deprel[lcode] may not exist even though we have a non-empty
        # set of relations, if lcode is 'ud'.
        if lcode in specs.deprel:
            for r in specs.deprel[lcode]:
                file = re.sub(r':', r'-', r)
                if file == 'aux':
                    file = 'aux_'
                for e in specs.deprel[lcode][r]['errors']:
                    msg += f"ERROR in _{lcode}/dep/{file}.md: {e}\n"
        sorted_documented_relations = sorted(deprelset)
        msg += (
            f"The following {len(sorted_documented_relations)} relations are currently permitted in language [{lcode}]:\n"
            f"{', '.join(sorted_documented_relations)}\n"
             "If a language needs a relation subtype that is not documented in the universal guidelines, the relation\n"
             "must have a language-specific documentation page in a prescribed format.\n"
             "See https://universaldependencies.org/contributing_language_specific.html for further guidelines.\n"
             "Documented dependency relations can be specifically turned on/off for each language in which they are used.\n"
             "See https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_deprel.pl for details.\n")
    return msg

def explain_edeprel(specs, lcode):
    """
    Returns explanation message for enhanced deprels of a particular language.
    To be called after language-specific enhanced deprels have been loaded.

    Parameters
    ----------
    specs : UDSpecs object
        The UD specification.
    lcode : str
        The language code.

    Returns
    -------
    name : str
        The explanation message for the enhanced deprels of the given language.
    """
    if lcode in specs._explanation_edeprel:
        return specs._explanation_edeprel[lcode]
    edeprelset = specs.get_edeprel_for_language(lcode)
    # Prepare a global message about permitted relation labels. We will add
    # it to the first error message about an unknown relation. Note that this
    # global information pertains to the default validation language and it
    # should not be used with code-switched segments in alternative languages.
    msg = ''
    if len(edeprelset) == 0:
        msg = (
            f"No enhanced dependency relation types (case markers) have been permitted for language [{lcode}].\n"
             "They can be permitted at the address below (if the language has an ISO code and is registered with UD):\n"
             "https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_edeprel.pl\n")
    else:
        # Identify dependency relations that are permitted in the current language.
        # If there are errors in documentation, identify the erroneous doc file.
        # Note that specs.deprel[lcode] may not exist even though we have a non-empty
        # set of relations, if lcode is 'ud'.
        sorted_case_markers = sorted(edeprelset)
        msg += (
            f"The following {len(sorted_case_markers)} enhanced relations are currently permitted in language [{lcode}]:\n"
            f"{', '.join(sorted_case_markers)}\n"
             "See https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_edeprel.pl for details.\n")
    specs._explanation_deprel[lcode] = msg
    return msg

def explain_aux(specs, lcode):
    """
    Returns explanation message for auxiliaries of a particular language.
    To be called after language-specific auxiliaries have been loaded.

    Parameters
    ----------
    specs : UDSpecs object
        The UD specification.
    lcode : str
        The language code.

    Returns
    -------
    name : str
        The explanation message for the auxiliaries of the given language.
    """
    auxspec = specs.get_aux_for_language(lcode)
    # Prepare a global message about permitted auxiliary lemmas. We will add
    # it to the first error message about an unknown auxiliary. Note that this
    # global information pertains to the default validation language and it
    # should not be used with code-switched segments in alternative languages.
    if len(auxspec) == 0:
        return (
            f"No auxiliaries have been documented at the address below for language [{lcode}].\n"
            f"https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_auxiliary.pl?lcode={lcode}\n")
    else:
        # Identify auxiliaries that are permitted in the current language.
        return (
            f"The following {len(auxspec)} auxiliaries are currently documented in language [{lcode}]:\n"
            f"{', '.join(auxspec)}\n"
            f"See https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_auxiliary.pl?lcode={lcode} for details.\n")

def explain_cop(specs, lcode):
    """
    Returns explanation message for copulas of a particular language.
    To be called after language-specific copulas have been loaded.

    Parameters
    ----------
    specs : UDSpecs object
        The UD specification.
    lcode : str
        The language code.

    Returns
    -------
    name : str
        The explanation message for the copulas of the given language.
    """
    copspec = specs.get_cop_for_language(lcode)
    # Prepare a global message about permitted copula lemmas. We will add
    # it to the first error message about an unknown copula. Note that this
    # global information pertains to the default validation language and it
    # should not be used with code-switched segments in alternative languages.
    if len(copspec) == 0:
        return (
            f"No copulas have been documented at the address below for language [{lcode}].\n"
            f"https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_auxiliary.pl?lcode={lcode}\n")
    else:
        # Identify auxiliaries that are permitted in the current language.
        return (
            f"The following {len(copspec)} copulas are currently documented in language [{lcode}]:\n"
            f"{', '.join(copspec)}\n"
            f"See https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_auxiliary.pl?lcode={lcode} for details.\n")

def explain_tospace(specs, lcode):
    """
    Returns explanation message for tokens with spaces of a particular language.
    To be called after language-specific tokens with spaces have been loaded.

    Parameters
    ----------
    specs : UDSpecs object
        The UD specification.
    lcode : str
        The language code.

    Returns
    -------
    name : str
        The explanation message for the tokens with spaces of the given language.
    """
    # Prepare a global message about permitted features and values. We will add
    # it to the first error message about an unknown token with space. Note that
    # this global information pertains to the default validation language and it
    # should not be used with code-switched segments in alternative languages.
    if not lcode in specs.tospace:
        return(
            f"No tokens with spaces have been permitted for language [{lcode}].\n"
             "They can be permitted at the address below (if the language has an ISO code and is registered with UD):\n"
             "https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_token_with_space.pl\n")
    else:
        return (
            f"Only tokens and lemmas matching the following regular expression are currently permitted to contain spaces in language [{lcode}]:\n"
            f"{specs.tospace[lcode][0]}\n"
             "\nOthers can be permitted at the address below (if the language has an ISO code and is registered with UD):\n"
             "https://quest.ms.mff.cuni.cz/udvalidator/cgi-bin/unidep/langspec/specify_token_with_space.pl\n")

def serialize_output(incidents, output_fhandle, explanations, lines_content):

    for incident in incidents:
        print(incident)


    if not incidents:
        print("*** PASSED ***")
    else:
        print(f"*** FAILED *** with {len(incidents)} error(s)")
