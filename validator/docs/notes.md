## Loaders and "getters"
Now in `loaders.py`.

### load_upos_set(filename) -> load_json_data(filename, key)

Loads UPOS/auxiliaries... from json.

### load_feat_set(filename_langspec, lcode)

Loads the list of permitted feature-value pairs and returns it as a set.

### load_deprel_set(filename_langspec, lcode)

Loads the list of permitted relation types and returns it as a set.

### load_edeprel_set(filename_langspec, lcode, basic_deprels)
Loads the list of permitted enhanced relation types (case markers) and returns it as a set.
> basic_deprels are retrieved via load_deprel_set

### load_set( f_name_ud, f_name_langspec, validate_langspec=False, validate_enhanced=False)

Loads a list of values from the two files, and returns their _Python_
set. If f_name_langspec doesn't exist, loads nothing and returns
None (ie this taglist is not checked for the given language). If f_name_langspec
is None, only loads the UD one. This is probably only useful for XPOS which doesn't
allow language-specific extensions. Set validate_langspec=True when loading basic dependencies.
That way the language specific deps will be checked to be truly extensions of UD ones.
Set validate_enhanced=True when loading enhanced dependencies. They will be checked to be
truly extensions of universal relations, too; but a more relaxed regular expression will
be checked because enhanced relations may contain stuff that is forbidden in the basic ones.
> In practice, this only used for loading regex that describes tokens allowed to have spaces.

### load_file(filename)

> Removed (replaced with more general `load_json_data`).

###  get_auxdata_for_language(lcode)
Searches the previously loaded database of auxiliary/copula lemmas. Returns
the AUX and COP lists for a given language code. For most CoNLL-U files,
this function is called only once at the beginning. However, some files
contain code-switched data and we may temporarily need to validate
another language.

### get_featdata_for_language(lcode)
Searches the previously loaded database of feature-value combinations.
Returns the lists for a given language code. For most CoNLL-U files,
this function is called only once at the beginning. However, some files
contain code-switched data and we may temporarily need to validate
another language.

## Validation functions

TODO:
- logging instead of `warn()`
- boolean return type

### validate(inp, out, args, tag_sets, known_sent_ids)
> Entry point for validation.
> Parameters:
> - inp : file obj
> - out : file obj but not used
> - args : cli arguments (argparse result)
> - tag_sets :
> - known_sent_ids :


### validate_unicode_normalization(text)
Tests that letters composed of multiple Unicode characters (such as a base
letter plus combining diacritics) conform to NFC normalization (canonical
decomposition followed by canonical composition).

### validate_cols_level1(cols)
Tests that can run on a single line and pertain only to the CoNLL-U file
format, not to predefined sets of UD tags.

validate_ID_references(tree)
    Validates that HEAD and DEPS reference existing IDs.

validate_ID_sequence(tree)
    Validates that the ID sequence is correctly formed.
    Besides issuing a warning if an error is found, it also returns False to
    the caller so it can avoid building a tree from corrupt ids.

validate_annotation(tree)
    Checks universally valid consequences of the annotation guidelines.

validate_auxiliary_verbs(cols, children, nodes, line, lang, auxlist)
    Verifies that the UPOS tag AUX is used only with lemmas that are known to
    act as auxiliary verbs or particles in the given language.
    Parameters:
      'cols' ....... columns of the head node
      'children' ... list of ids
      'nodes' ...... dictionary where we can translate the node id into its
                     CoNLL-U columns
      'line' ....... line number of the node within the file

validate_character_constraints(cols)
    Checks general constraints on valid characters, e.g. that UPOS
    only contains [A-Z].

validate_cols(cols, tag_sets, args)
    All tests that can run on a single line. Done as soon as the line is read,
    called from trees() if level>1.


validate_copula_lemmas(cols, children, nodes, line, lang, coplist)
    Verifies that the relation cop is used only with lemmas that are known to
    act as copulas in the given language.
    Parameters:
      'cols' ....... columns of the head node
      'children' ... list of ids
      'nodes' ...... dictionary where we can translate the node id into its
                     CoNLL-U columns
      'line' ....... line number of the node within the file

validate_deprels(cols, tag_sets, args)

validate_deps(tree)
    Validates that DEPS is correctly formatted and that there are no
    self-loops in DEPS.

validate_empty_node_empty_vals(cols)
    Checks that an empty node has _ empty values in HEAD and DEPREL. This is
    required by UD guidelines but not necessarily by CoNLL-U, therefore
    a level 2 test.

validate_enhanced_annotation(graph)
    Checks universally valid consequences of the annotation guidelines in the
    enhanced representation. Currently tests only phenomena specific to the
    enhanced dependencies; however, we should also test things that are
    required in the basic dependencies (such as left-to-right coordination),
    unless it is obvious that in enhanced dependencies such things are legal.

validate_features(cols, tag_sets, args)
    Checks general constraints on feature-value format. On level 4 and higher,
    also checks that a feature-value pair is listed as approved. (Every pair
    must be allowed on level 2 because it could be defined as language-specific.
    To disallow non-universal features, test on level 4 with language 'ud'.)

validate_fixed_span(node_id, tree)
    Like with goeswith, the fixed relation should not in general skip words that
    are not part of the fixed expression. Unlike goeswith however, there can be
    an intervening punctuation symbol. Moreover, the rule that fixed expressions
    cannot be discontiguous has been challenged with examples from Swedish and
    Coptic, see https://github.com/UniversalDependencies/docs/issues/623.
    Hence, the test was turned off 2019-04-13. I am re-activating it 2023-09-03
    as just a warning.

validate_flat_foreign(node_id, tree)
    flat:foreign is an optional subtype of flat. It is used to connect two words
    in a code-switched segment of foreign words if the annotators did not want
    to provide the analysis according to the source language. If flat:foreign
    is used, both the parent and the child should have the Foreign=Yes feature
    and their UPOS tag should be X.

validate_functional_leaves(node_id, tree)
    Most of the time, function-word nodes should be leaves. This function
    checks for known exceptions and warns in the other cases.
    (https://universaldependencies.org/u/overview/syntax.html#function-word-modifiers)

validate_goeswith_morphology_and_edeps(node_id, tree)
    If a node has the 'goeswith' incoming relation, it is a non-first part of
    a mistakenly interrupted word. The lemma, upos tag and morphological features
    of the word should be annotated at the first part, not here.

validate_goeswith_span(node_id, tree)
    The relation 'goeswith' is used to connect word parts that are separated
    by whitespace and should be one word instead. We assume that the relation
    goes left-to-right, which is checked elsewhere. Here we check that the
    nodes really were separated by whitespace. If there is another node in the
    middle, it must be also attached via 'goeswith'. The parameter id refers to
    the node whose goeswith children we test.

validate_left_to_right_relations(node_id, tree)
    Certain UD relations must always go left-to-right.
    Here we currently check the rule for the basic dependencies.
    The same should also be tested for the enhanced dependencies!

validate_lspec_annotation(tree, lang, tag_sets)
    Checks language-specific consequences of the annotation guidelines.

validate_misc(tree)
    In general, the MISC column can contain almost anything. However, if there
    is a vertical bar character, it is interpreted as the separator of two
    MISC attributes, which may or may not have the form of attribute=value pair.
    In general it is not forbidden that the same attribute appears several times
    with different values, but this should not happen for selected attributes
    that are described in the UD documentation.

validate_misc_entity(comments, sentence)
    Optionally checks the well-formedness of the MISC attributes that pertain
    to coreference and named entities.

validate_newlines(inp)

validate_orphan(node_id, tree)
    The orphan relation is used to attach an unpromoted orphan to the promoted
    orphan in gapping constructions. A common error is that the promoted orphan
    gets the orphan relation too. The parent of orphan is typically attached
    via a conj relation, although some other relations are plausible too.

validate_projective_punctuation(node_id, tree)
    Punctuation is not supposed to cause nonprojectivity or to be attached
    nonprojectively.

validate_required_feature(
    feats,
    fv,
    testmessage,
    testlevel,
    testid,
    nodeid,
    lineno
)
In general, the annotation of morphological features is optional, although
highly encouraged. However, if the treebank does have features, then certain
features become required. This function will check the presence of a feature
and if it is missing, an error will be reported only if at least one feature
has been already encountered. Otherwise the error will be remembered and it
may be reported afterwards if any feature is encountered later.

validate_root(tree)
    Checks that DEPREL is "root" iff HEAD is 0.

validate_sent_id(comments, known_ids, lcode)

validate_single_subject(node_id, tree)
    No predicate should have more than one subject.
    An xcomp dependent normally has no subject, but in some languages the
    requirement may be weaker: it could have an overt subject if it is
    correferential with a particular argument of the matrix verb. Hence we do
    not check zero subjects of xcomp dependents at present.
    Furthermore, in some situations we must allow multiple subjects. If a clause
    acts as a nonverbal predicate of another clause, then we must attach two
    subjects to the predicate of the inner clause: one is the predicate of the
    inner clause, the other is the predicate of the outer clause. This could in
    theory be recursive but in practice it isn't. As of UD 2.10, an amendment
    of the guidelines says that the inner predicate of the predicate clause
    should govern both subjects even if there is a copula (previously such
    cases were an exception from the UD approach that copulas should not be
    heads); however, the outer subjects should be attached as [nc]subj:outer.
    See https://universaldependencies.org/changes.html#multiple-subjects.
    See also issue 34 (https://github.com/UniversalDependencies/tools/issues/34).
    Strictly speaking, :outer is optional because it is a subtype, and some
    treebanks may want to avoid it. For example, in Coptic Scriptorium, there
    is only one occurrence in dev, one in test, and none in train, so it would
    be impossible to train a parser that gets it right. For that reason, it is
    possible to replace the :outer subtype with Subject=Outer in MISC. The MISC
    attribute is just a directive for the validator and no parser is expected
    to predict it.

validate_text_meta(comments, tree, args)

validate_token_empty_vals(cols)
    Checks that a multi-word token has _ empty values in all fields except MISC.
    This is required by UD guidelines although it is not a problem in general,
    therefore a level 2 test.

validate_token_ranges(tree)
    Checks that the word ranges for multiword tokens are valid.

validate_upos(cols, tag_sets)

validate_upos_vs_deprel(node_id, tree)
    For certain relations checks that the dependent word belongs to an expected
    part-of-speech category. Occasionally we may have to check the children of
    the node, too.

validate_whitespace(cols, tag_sets)
    Checks a single line for disallowed whitespace.
    Here we assume that all language-independent whitespace-related tests have
    already been done in validate_cols_level1(), so we only check for words
    with spaces that are explicitly allowed in a given language.

---

FUNCTIONS
    build_egraph(sentence)
        Takes the list of non-comment lines (line = list of columns) describing
        a sentence. Returns a dictionary with items providing easier access to the
        enhanced graph structure. In case of fatal problems returns None
        but does not report the error (presumably it has already been reported).
        However, once the graph has been found and built, this function verifies
        that the graph is connected and generates an error if it is not.

        egraph ... dictionary:
          nodes ... dictionary of dictionaries, each corresponding to a word or an empty node; mwt lines are skipped
              keys equal to node ids (i.e. strings that look like integers or decimal numbers; key 0 is the artificial root node)
              value is a dictionary-record:
                  cols ... array of column values from the input line corresponding to the node
                  children ... set of children ids (strings)
                  lineno ... line number in the file (needed in error messages)

    build_tree(sentence)
        Takes the list of non-comment lines (line = list of columns) describing
        a sentence. Returns a dictionary with items providing easier access to the
        tree structure. In case of fatal problems (missing HEAD etc.) returns None
        but does not report the error (presumably it has already been reported).

        tree ... dictionary:
          nodes ... array of word lines, i.e., lists of columns;
              mwt and empty nodes are skipped, indices equal to ids (nodes[0] is empty)
          children ... array of sets of children indices (numbers, not strings);
              indices to this array equal to ids (children[0] are the children of the root)
          linenos ... array of line numbers in the file, corresponding to nodes
              (needed in error messages)

    collect_ancestors(node_id, tree, ancestors)
        Usage: ancestors = collect_ancestors(nodeid, nodes, [])

    deps_list(cols)

    features_present()
        In general, the annotation of morphological features is optional, although
        highly encouraged. However, if the treebank does have features, then certain
        features become required. This function is called when the first morphological
        feature is encountered. It remembers that from now on, missing features can
        be reported as errors. In addition, if any such errors have already been
        encountered, they will be reported now.

    get_alt_language(misc)
        Takes the value of the MISC column for a token and checks it for the
        attribute Lang=xxx. If present, it is interpreted as the code of the
        language in which the current token is. This is uselful for code switching,
        if a phrase is in a language different from the main language of the
        document. The validator can then temporarily switch to a different set
        of language-specific tests.


    get_caused_nonprojectivities(node_id, tree)
        Checks whether a node is in a gap of a nonprojective edge. Report true only
        if the node's parent is not in the same gap. (We use this function to check
        that a punctuation node does not cause nonprojectivity. But if it has been
        dragged to the gap with a larger subtree, then we do not blame it.)

        tree ... dictionary:
          nodes ... array of word lines, i.e., lists of columns; mwt and empty nodes are skipped, indices equal to ids (nodes[0] is empty)
          children ... array of sets of children indices (numbers, not strings); indices to this array equal to ids (children[0] are the children of the root)
          linenos ... array of line numbers in the file, corresponding to nodes (needed in error messages)

    get_depreldata_for_language(lcode)
        Searches the previously loaded database of dependency relation labels.
        Returns the lists for a given language code. For most CoNLL-U files,
        this function is called only once at the beginning. However, some files
        contain code-switched data and we may temporarily need to validate
        another language.

    get_edepreldata_for_language(lcode, basic_deprels)
        Searches the previously loaded database of enhanced case markers.
        Returns the lists for a given language code. For most CoNLL-U files,
        this function is called only once at the beginning. However, some files
        contain code-switched data and we may temporarily need to validate
        another language.


    get_gap(node_id, tree)

    get_graph_projection(node_id, graph, projection)
        Like get_projection() above, but works with the enhanced graph data structure.
        Collects node ids in the set called projection.

    get_projection(node_id, tree, projection)
        Like proj() above, but works with the tree data structure. Collects node ids
        in the set called projection.

    is_empty_node(cols)

    is_multiword_token(cols)

    is_whitespace(line)

    is_word(cols)



    lspec2ud(deprel)

    parse_empty_node_id(cols)

    shorten(string)

    subset_to_words_and_empty_nodes(tree)
        Only picks word and empty node lines, skips multiword token lines.

    trees(inp, tag_sets, args)
        `inp` a file-like object yielding lines as unicode
        `tag_sets` and `args` are needed for choosing the tests

        This function does elementary checking of the input and yields one
        sentence at a time from the input stream.

        This function is a generator. The caller can call it in a 'for x in ...'
        loop. In each iteration of the caller's loop, the generator will generate
        the next sentence, that is, it will read the next sentence from the input
        stream. (Technically, the function returns an object, and the object will
        then read the sentences within the caller's loop.)

    warn(msg, testclass, testlevel, testid, lineno=0, nodeid=0, explanation=None)
        Print the error/warning message.

        If lineno is 0, print the number of the current line (most recently read from input).
        If lineno is < 0, print the number of the first line of the current sentence.
        If lineno is > 0, print lineno (probably pointing somewhere in the current sentence).

        If explanation contains a string and this is the first time we are reporting
        an error of this type, the string will be appended to the main message. It
        can be used as an extended explanation of the situation.

DATA
    AUX = 11
    COLCOUNT = 10
    COLNAMES = ['ID', 'FORM', 'LEMMA', 'UPOS', 'XPOS', 'FEATS', 'HEAD', 'D...
    COP = 12
    DEPREL = 7
    DEPS = 8
    FEATS = 5
    FORM = 1
    HEAD = 6
    ID = 0
    LEMMA = 2
    MISC = 9
    THISDIR = '/home/harisont/Repos/UniversalDependencies/tools'
    TOKENSWSPACE = 10
    UPOS = 3
    XPOS = 4
    alt_lang_re = regex.Regex('Lang=(.+)', flags=regex.V0)
    attr_val_re = regex.Regex('^([A-Z][A-Za-z0-9]*(?:\\[[a-z0-9]+\...]*)(,...
    auxdata = {}
    basic_head_re = regex.Regex('^(0|[1-9][0-9]*)$', flags=regex.V0)
    comment_start_line = 0
    curr_line = 0
    delayed_feature_errors = {}
    deprel_re = regex.Regex('^[a-z]+(:[a-z]+)?$', flags=regex.V0)
    depreldata = {}
    edeprel_re = regex.Regex('^[a-z]+(:[a-z]+)?(:[\\p{Ll}\\p{Lm}\...}\\p{L...
    edeprel_resrc = r'^[a-z]+(:[a-z]+)?(:[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(_[\p{L...
    edepreldata = {}
    edeprelpart_resrc = r'[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(_[\p{Ll}\p{Lm}\p{Lo}\...
    empty_node_re = regex.Regex('^[0-9]+\\.[1-9][0-9]*$', flags=regex.V0)
    enhanced_head_re = regex.Regex('^(0|[1-9][0-9]*)(\\.[1-9][0-9]*)?$', f...
    entity_attribute_index = {}
    entity_attribute_number = 0
    entity_bridge_relations = {}
    entity_ids_other_documents = {}
    entity_ids_this_document = {}
    entity_mention_spans = {}
    entity_split_antecedents = {}
    entity_types = {}
    error_counter = {}
    featdata = {}
    global_entity_attribute_string = None
    global_entity_re = regex.Regex('^#\\s*global\\.Entity\\s*=\\s*(.+)$', ...
    interval_re = regex.Regex('^([0-9]+)-([0-9]+)$', flags=regex.V0)
    line_of_first_empty_node = None
    line_of_first_enhanced_graph = None
    line_of_first_enhanced_orphan = None
    line_of_first_enhancement = None
    line_of_first_morpho_feature = None
    line_of_first_tree_without_enhanced_graph = None
    line_of_global_entity = None
    mwt_re = regex.Regex('^[1-9][0-9]*-[1-9][0-9]*$', flags=regex.V0)
    mwt_typo_span_end = None
    newdoc_re = regex.Regex('^#\\s*newdoc(\\s|$)', flags=regex.V0)
    newpar_re = regex.Regex('^#\\s*newpar(\\s|$)', flags=regex.V0)
    open_discontinuous_mentions = {}
    open_entity_mentions = []
    sentence_id = None
    sentence_line = 0
    sentid_re = regex.Regex('^# sent_id\\s*=\\s*(\\S+)$', flags=regex.V0)
    spaceafterno_in_effect = False
    text_re = regex.Regex('^#\\s*text\\s*=\\s*(.+)$', flags=regex.V0)
    upos_re = regex.Regex('^[A-Z]+$', flags=regex.V0)
    val_re = regex.Regex('^[A-Z0-9][A-Za-z0-9]*', flags=regex.V0)
    warn_on_missing_files = set()
    warn_on_undoc_aux = ''
    warn_on_undoc_cop = ''
    warn_on_undoc_deps = ''
    warn_on_undoc_edeps = ''
    warn_on_undoc_feats = ''
    whitespace2_re = regex.Regex('.*\\s\\s', flags=regex.V0)
    whitespace_re = regex.Regex('.*\\s', flags=regex.V0)
    word_re = regex.Regex('^[1-9][0-9]*$', flags=regex.V0)
    ws_re = regex.Regex('^\\s+$', flags=regex.V0)

FILE
    /home/harisont/Repos/UniversalDependencies/tools/validate.py


