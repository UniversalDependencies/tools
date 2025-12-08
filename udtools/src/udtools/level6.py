#! /usr/bin/env python3
# Original code (2015) by Filip Ginter and Sampo Pyysalo.
# DZ 2018-11-04: Porting the validator to Python 3.
# DZ: Many subsequent changes. See the git history.
# According to https://stackoverflow.com/questions/1832893/python-regex-matching-unicode-properties,
# the regex module has the same API as re but it can check Unicode character properties using \p{}
# as in Perl.
#import re
import regex as re
# Allow using this module from the root folder of tools even if it is not
# installed as a package: use the relative path validator/src/validator for
# submodules. If the path is not available, try the standard qualification,
# assuming that the user has installed udtools from PyPI and then called
# from udtools import Validator.
try:
    import udtools.src.udtools.utils as utils
    from udtools.src.udtools.incident import Incident, Error, Warning, TestClass
    from udtools.src.udtools.level5 import Level5
except ModuleNotFoundError:
    import udtools.utils as utils
    from udtools.incident import Incident, Error, Warning, TestClass
    from udtools.level5 import Level5



# Constants for the column indices
COLCOUNT=10
ID,FORM,LEMMA,UPOS,XPOS,FEATS,HEAD,DEPREL,DEPS,MISC=range(COLCOUNT)
COLNAMES='ID,FORM,LEMMA,UPOS,XPOS,FEATS,HEAD,DEPREL,DEPS,MISC'.split(',')



class Level6(Level5):
#==============================================================================
# Level 6 tests for annotation of coreference and named entities. This is
# tested on demand only, as the requirements are not compulsory for UD
# releases.
#==============================================================================



    def check_misc_entity(self, state):
        """
        Optionally checks the well-formedness of the MISC attributes that pertain
        to coreference and named entities.

        Parameters
        ----------
        state : udtools.state.State
            The state of the validation run.

        Reads from state
        ----------------
        current_lines : list(str)
            List of lines in the sentence (comments and tokens), including
            final empty line. The lines are not expected to include the final
            newline character.
            First we expect an optional block (zero or more lines) of comments,
            i.e., lines starting with '#'. Then we expect a non-empty block
            (one or more lines) of nodes, empty nodes, and multiword tokens.
            Finally, we expect exactly one empty line.
        comment_start_line : int
            The line number (relative to input file, 1-based) of the first line
            in the current sentence, including comments if any.
        current_token_node_table : list(list(str))
            The list of multiword token lines / regular node lines / empty node
            lines, each split to fields (columns).
        sentence_line : int
            The line number (relative to input file, 1-based) of the first
            node/token line in the current sentence.

        Reads and writes to state
        -------------------------
        global_entity_attribute_string : str
        entity_attribute_number : int
        entity_attribute_index : dict
        entity_types : dict
        entity_ids_this_document : dict
        entity_ids_other_documents : dict
        open_entity_mentions : list
        open_discontinuous_mentions : dict
        entity_bridge_relations : dict
        entity_split_antecedents : dict
        entity_mention_spans : dict

        Incidents
        ---------
        global-entity-mismatch
        spurious-global-entity
        entity-mwt
        multiple-entity-statements
        multiple-bridge-statements
        multiple-splitante-statements
        bridge-without-entity
        splitante-without-entity
        entity-without-global-entity
        spurious-entity-statement
        too-many-entity-attributes
        spurious-entity-id
        misplaced-mention-part
        mention-attribute-mismatch
        entity-across-newdoc
        spurious-entity-type
        spurious-mention-head
        entity-type-mismatch
        entity-identity-mismatch
        ill-nested-entities
        ill-nested-entities-warning
        mention-head-out-of-range
        same-span-entity-mentions
        crossing-mentions-same-entity
        spurious-bridge-statement
        spurious-bridge-relation
        misplaced-bridge-statement
        repeated-bridge-relation
        bridge-relation-mismatch
        spurious-splitante-statement
        spurious-splitante-relation
        misplaced-splitante-statement
        repeated-splitante-relation
        only-one-split-antecedent
        split-antecedent-mismatch
        cross-sentence-mention
        """
        Incident.default_level = 6
        Incident.default_testclass = TestClass.COREF
        n_comment_lines = state.sentence_line-state.comment_start_line
        comments = state.current_lines[0:n_comment_lines]
        iline = 0
        sentid = ''
        for c in comments:
            Incident.default_lineno = state.comment_start_line+iline
            global_entity_match = utils.crex.global_entity.fullmatch(c)
            newdoc_match = utils.crex.newdoc.fullmatch(c)
            sentid_match = utils.crex.sentid.fullmatch(c)
            if global_entity_match:
                # As a global declaration, global.Entity is expected only once per file.
                # However, we may be processing multiple files or people may have created
                # the file by concatening smaller files, so we will allow repeated
                # declarations iff they are identical to the first one.
                if state.seen_global_entity:
                    if global_entity_match.group(1) != state.global_entity_attribute_string:
                        Error(
                            state=state, config=self.incfg,
                            testid='global-entity-mismatch',
                            message=f"New declaration of global.Entity '{global_entity_match.group(1)}' does not match the first declaration '{state.global_entity_attribute_string}' on line {state.seen_global_entity}."
                        ).confirm()
                else:
                    state.seen_global_entity = state.comment_start_line + iline
                    state.global_entity_attribute_string = global_entity_match.group(1)
                    if not re.match(r"^[a-z]+(-[a-z]+)*$", state.global_entity_attribute_string):
                        Error(
                            state=state, config=self.incfg,
                            testid='spurious-global-entity',
                            message=f"Cannot parse global.Entity attribute declaration '{state.global_entity_attribute_string}'."
                        ).confirm()
                    else:
                        global_entity_attributes = state.global_entity_attribute_string.split('-')
                        if not 'eid' in global_entity_attributes:
                            Error(
                                state=state, config=self.incfg,
                                testid='spurious-global-entity',
                                message=f"Global.Entity attribute declaration '{state.global_entity_attribute_string}' does not include 'eid'."
                            ).confirm()
                        elif global_entity_attributes[0] != 'eid':
                            Error(
                                state=state, config=self.incfg,
                                testid='spurious-global-entity',
                                message=f"Attribute 'eid' must come first in global.Entity attribute declaration '{state.global_entity_attribute_string}'."
                            ).confirm()
                        if not 'etype' in global_entity_attributes:
                            Error(
                                state=state, config=self.incfg,
                                testid='spurious-global-entity',
                                message=f"Global.Entity attribute declaration '{state.global_entity_attribute_string}' does not include 'etype'."
                            ).confirm()
                        elif global_entity_attributes[1] != 'etype':
                            Error(
                                state=state, config=self.incfg,
                                testid='spurious-global-entity',
                                message=f"Attribute 'etype' must come second in global.Entity attribute declaration '{state.global_entity_attribute_string}'."
                            ).confirm()
                        if not 'head' in global_entity_attributes:
                            Error(
                                state=state, config=self.incfg,
                                testid='spurious-global-entity',
                                message=f"Global.Entity attribute declaration '{state.global_entity_attribute_string}' does not include 'head'."
                            ).confirm()
                        elif global_entity_attributes[2] != 'head':
                            Error(
                                state=state, config=self.incfg,
                                testid='spurious-global-entity',
                                message=f"Attribute 'head' must come third in global.Entity attribute declaration '{state.global_entity_attribute_string}'."
                            ).confirm()
                        if 'other' in global_entity_attributes and global_entity_attributes[3] != 'other':
                            Error(
                                state=state, config=self.incfg,
                                testid='spurious-global-entity',
                                message=f"Attribute 'other', if present, must come fourth in global.Entity attribute declaration '{state.global_entity_attribute_string}'."
                            ).confirm()
                        # Fill the global dictionary that maps attribute names to list indices.
                        i = 0
                        for a in global_entity_attributes:
                            if a in state.entity_attribute_index:
                                Error(
                                    state=state, config=self.incfg,
                                    testid='spurious-global-entity',
                                    message=f"Attribute '{a}' occurs more than once in global.Entity attribute declaration '{state.global_entity_attribute_string}'."
                                ).confirm()
                            else:
                                state.entity_attribute_index[a] = i
                            i += 1
                        state.entity_attribute_number = len(global_entity_attributes)
            elif newdoc_match:
                for eid in state.entity_ids_this_document:
                    state.entity_ids_other_documents[eid] = state.entity_ids_this_document[eid]
                state.entity_ids_this_document = {}
            elif sentid_match:
                sentid = sentid_match.group(1)
            iline += 1
        for iline in range(len(state.current_token_node_table)):
            cols = state.current_token_node_table[iline]
            Incident.default_lineno = state.sentence_line+iline
            # Add the current word to all currently open mentions. We will use it in error messages.
            # Do this for regular and empty nodes but not for multi-word-token lines.
            if not utils.is_multiword_token(cols):
                for m in state.open_entity_mentions:
                    m['span'].append(cols[ID])
                    m['text'] += ' '+cols[FORM]
                    m['length'] += 1
            misc = cols[MISC].split('|')
            entity = [x for x in misc if re.match(r"^Entity=", x)]
            bridge = [x for x in misc if re.match(r"^Bridge=", x)]
            splitante = [x for x in misc if re.match(r"^SplitAnte=", x)]
            if utils.is_multiword_token(cols) and (len(entity)>0 or len(bridge)>0 or len(splitante)>0):
                Error(
                    state=state, config=self.incfg,
                    testid='entity-mwt',
                    message="Entity or coreference annotation must not occur at a multiword-token line."
                ).confirm()
                continue
            if len(entity)>1:
                Error(
                    state=state, config=self.incfg,
                    testid='multiple-entity-statements',
                    message=f"There can be at most one 'Entity=' statement in MISC but we have {str(misc)}."
                ).confirm()
                continue
            if len(bridge)>1:
                Error(
                    state=state, config=self.incfg,
                    testid='multiple-bridge-statements',
                    message=f"There can be at most one 'Bridge=' statement in MISC but we have {str(misc)}."
                ).confirm()
                continue
            if len(splitante)>1:
                Error(
                    state=state, config=self.incfg,
                    testid='multiple-splitante-statements',
                    message=f"There can be at most one 'SplitAnte=' statement in MISC but we have {str(misc)}."
                ).confirm()
                continue
            if len(bridge)>0 and len(entity)==0:
                Error(
                    state=state, config=self.incfg,
                    testid='bridge-without-entity',
                    message=f"The 'Bridge=' statement can only occur together with 'Entity=' in MISC but we have {str(misc)}."
                ).confirm()
                continue
            if len(splitante)>0 and len(entity)==0:
                Error(
                    state=state, config=self.incfg,
                    testid='splitante-without-entity',
                    message=f"The 'SplitAnte=' statement can only occur together with 'Entity=' in MISC but we have {str(misc)}."
                ).confirm()
                continue
            # There is at most one Entity (and only if it is there, there may be also one Bridge and/or one SplitAnte).
            if len(entity)>0:
                if not state.seen_global_entity:
                    Error(
                        state=state, config=self.incfg,
                        testid='entity-without-global-entity',
                        message="No global.Entity comment was found before the first 'Entity' in MISC."
                    ).confirm()
                    continue
                match = re.match(r"^Entity=((?:\([^( )]+(?:-[^( )]+)*\)?|[^( )]+\))+)$", entity[0])
                if not match:
                    Error(
                        state=state, config=self.incfg,
                        testid='spurious-entity-statement',
                        message=f"Cannot parse the Entity statement '{entity[0]}'."
                    ).confirm()
                else:
                    entity_string = match.group(1)
                    # We cannot check the rest if we cannot identify the 'eid' attribute.
                    if 'eid' not in state.entity_attribute_index:
                        continue
                    # Items of entities are pairs of [012] and a string.
                    # 0 ... opening bracket; 1 ... closing bracket; 2 ... both brackets
                    entities = []
                    while entity_string:
                        match = re.match(r"^\(([^( )]+(-[^( )]+)*)\)", entity_string)
                        if match:
                            entities.append((2, match.group(1)))
                            entity_string = re.sub(r"^\([^( )]+(-[^( )]+)*\)", '', entity_string, count=1)
                            continue
                        match = re.match(r"^\(([^( )]+(-[^( )]+)*)", entity_string)
                        if match:
                            entities.append((0, match.group(1)))
                            entity_string = re.sub(r"^\([^( )]+(-[^( )]+)*", '', entity_string, count=1)
                            continue
                        match = re.match(r"^([^( )]+)\)", entity_string)
                        if match:
                            entities.append((1, match.group(1)))
                            entity_string = re.sub(r"^[^( )]+\)", '', entity_string, count=1)
                            continue
                        # If we pre-checked the string well, we should never arrive here!
                        Error(
                            state=state, config=self.incfg,
                            testid='internal-error',
                            message='INTERNAL ERROR'
                        ).confirm()
                    # All 1 cases should precede all 0 cases.
                    # The 2 cases can be either before the first 1 case, or after the last 0 case.
                    seen0 = False
                    seen1 = False
                    seen2 = False
                    # To be able to check validity of Bridge and SplitAnte, we will hash eids of mentions that start here.
                    # To be able to check that no two mentions have the same span, we will hash start-end intervals for mentions that end here.
                    starting_mentions = {}
                    ending_mentions = {}
                    for b, e in entities:
                        # First get attributes, entity id, and if applicable, part of discontinuous mention.
                        attributes = e.split('-')
                        if b==0 or b==2:
                            # Fewer attributes are allowed because trailing empty values can be omitted.
                            # More attributes are not allowed.
                            if len(attributes) > state.entity_attribute_number:
                                Error(
                                    state=state, config=self.incfg,
                                    testid='too-many-entity-attributes',
                                    message=f"Entity '{e}' has {len(attributes)} attributes while only {state.entity_attribute_number} attributes are globally declared."
                                ).confirm()
                            # The raw eid (bracket eid) may include an identification of a part of a discontinuous mention,
                            # as in 'e155[1/2]'. This is fine for matching opening and closing brackets
                            # because the closing bracket must contain it too. However, to identify the
                            # cluster, we need to take the real id.
                            beid = attributes[state.entity_attribute_index['eid']]
                        else:
                            # No attributes other than eid are expected at the closing bracket.
                            if len(attributes) > 1:
                                Error(
                                    state=state, config=self.incfg,
                                    testid='too-many-entity-attributes',
                                    message=f"Entity '{e}' has {len(attributes)} attributes while only eid is expected at the closing bracket."
                                ).confirm()
                            beid = attributes[0]
                        eid = beid
                        ipart = 1
                        npart = 1
                        eidnpart = eid
                        match = re.match(r"^(.+)\[([1-9]\d*)/([1-9]\d*)\]$", beid)
                        if match:
                            eid = match.group(1)
                            ipart = int(match.group(2))
                            npart = int(match.group(3))
                            eidnpart = eid+'['+match.group(3)+']'
                            # We should omit the square brackets if they would be [1/1].
                            if ipart == 1 and npart == 1:
                                Error(
                                    state=state, config=self.incfg,
                                    testid='spurious-entity-id',
                                    message=f"Discontinuous mention must have at least two parts but it has one in '{beid}'."
                                ).confirm()
                            if ipart > npart:
                                Error(
                                    state=state, config=self.incfg,
                                    testid='spurious-entity-id',
                                    message=f"Entity id '{beid}' of discontinuous mention says the current part is higher than total number of parts."
                                ).confirm()
                        else:
                            if re.match(r"[\[\]]", beid):
                                Error(
                                    state=state, config=self.incfg,
                                    testid='spurious-entity-id',
                                    message=f"Entity id '{beid}' contains square brackets but does not have the form used in discontinuous mentions."
                                ).confirm()

                        #--------------------------------------------------------------------------------------------------------------------------------
                        # The code that we will have to execute at single-node continuous parts and at the opening brackets of multi-node continuous parts.
                        # We assume that we have already parsed beid and established whether this is a part of a discontinuous mention.
                        def opening_bracket():
                            attrstring_to_match = ''
                            # If this is a part of a discontinuous mention, remember the attribute string.
                            # At the beginning of each part, we will check that its attribute string is identical to the first part.
                            if npart > 1:
                                # We want to check that values of all attributes are same in all parts (except the eid which differs in the brackets).
                                attributes_without_eid = [attributes[i] for i in range(len(attributes)) if i != state.entity_attribute_index['eid']]
                                # For better readability of the error messages, reintroduce eid anyway, but without the brackets.
                                attrstring_to_match = eid+'-'+('-'.join(attributes_without_eid))
                                if ipart == 1:
                                    # If this is the first part, create a new record for the mention in the global dictionary.
                                    # We actually keep a stack of open mentions with the same eidnpart because they may be nested.
                                    # The length and the span of the mention will be updated when we encounter the closing bracket of the current part.
                                    discontinuous_mention = {'last_ipart': 1, 'npart': npart,
                                                            'first_part_line': state.sentence_line+iline,
                                                            'last_part_line': state.sentence_line+iline,
                                                            'attributes': attrstring_to_match,
                                                            'length': 0, 'span': []}
                                    if eidnpart in state.open_discontinuous_mentions:
                                        state.open_discontinuous_mentions[eidnpart].append(discontinuous_mention)
                                    else:
                                        state.open_discontinuous_mentions[eidnpart] = [discontinuous_mention]
                                else:
                                    if eidnpart in state.open_discontinuous_mentions:
                                        discontinuous_mention = state.open_discontinuous_mentions[eidnpart][-1]
                                        if ipart != discontinuous_mention['last_ipart']+1:
                                            Error(
                                                state=state, config=self.incfg,
                                                testid='misplaced-mention-part',
                                                message=f"Unexpected part of discontinuous mention '{beid}': last part was '{discontinuous_mention['last_ipart']}/{discontinuous_mention['npart']}' on line {discontinuous_mention['last_part_line']}."
                                            ).confirm()
                                            # We will update last_ipart at closing bracket, i.e., after the current part has been entirely processed.
                                            # Otherwise nested discontinuous mentions might wrongly assess where they belong.
                                        elif attrstring_to_match != discontinuous_mention['attributes']:
                                            Error(
                                                state=state, config=self.incfg,
                                                testid='mention-attribute-mismatch',
                                                message=f"Attribute mismatch of discontinuous mention: current part has '{attrstring_to_match}', first part '{discontinuous_mention['attributes']}' was at line {discontinuous_mention['first_part_line']}."
                                            ).confirm()
                                    else:
                                        Error(
                                            state=state, config=self.incfg,
                                            testid='misplaced-mention-part',
                                            message=f"Unexpected part of discontinuous mention '{beid}': this is part {ipart} but we do not have information about the previous parts."
                                        ).confirm()
                                        discontinuous_mention = {'last_ipart': ipart, 'npart': npart,
                                                                'first_part_line': state.sentence_line+iline,
                                                                'last_part_line': state.sentence_line+iline,
                                                                'attributes': attrstring_to_match,
                                                                'length': 0, 'span': []}
                                        state.open_discontinuous_mentions[eidnpart] = [discontinuous_mention]
                            # Check all attributes of the entity, except those that must be examined at the closing bracket.
                            if eid in state.entity_ids_other_documents:
                                Error(
                                    state=state, config=self.incfg,
                                    testid='entity-across-newdoc',
                                    message=f"Same entity id should not occur in multiple documents; '{eid}' first seen on line {state.entity_ids_other_documents[eid]}, before the last newdoc."
                                ).confirm()
                            elif not eid in state.entity_ids_this_document:
                                state.entity_ids_this_document[eid] = state.sentence_line+iline
                            etype = ''
                            identity = ''
                            if 'etype' in state.entity_attribute_index and len(attributes) >= state.entity_attribute_index['etype']+1:
                                etype = attributes[state.entity_attribute_index['etype']]
                                # For etype values tentatively approved for CorefUD 1.0, see
                                # https://github.com/ufal/corefUD/issues/13#issuecomment-1008447464
                                if not re.match(r"^(person|place|organization|animal|plant|object|substance|time|number|abstract|event|other)?$", etype):
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='spurious-entity-type',
                                        message=f"Spurious entity type '{etype}'."
                                    ).confirm()
                            if 'identity' in state.entity_attribute_index and len(attributes) >= state.entity_attribute_index['identity']+1:
                                identity = attributes[state.entity_attribute_index['identity']]
                            # Check the form of the head index now.
                            # The value will be checked at the end of the mention,
                            # when we know the mention length.
                            head = 0
                            if 'head' in state.entity_attribute_index and len(attributes) >= state.entity_attribute_index['head']+1:
                                if not re.match(r"^[1-9][0-9]*$", attributes[state.entity_attribute_index['head']]):
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='spurious-mention-head',
                                        message=f"Entity head index '{attributes[state.entity_attribute_index['head']]}' must be a non-zero-starting integer."
                                    ).confirm()
                                else:
                                    head = int(attributes[state.entity_attribute_index['head']])
                            # If this is the first mention of the entity, remember the values
                            # of the attributes that should be identical at all mentions.
                            if not eid in state.entity_types:
                                state.entity_types[eid] = (etype, identity, state.sentence_line+iline)
                            else:
                                # All mentions of one entity (cluster) must have the same entity type.
                                if etype != state.entity_types[eid][0]:
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='entity-type-mismatch',
                                        message=f"Entity '{eid}' cannot have type '{etype}' that does not match '{state.entity_types[eid][0]}' from the first mention on line {state.entity_types[eid][2]}."
                                    ).confirm()
                                # All mentions of one entity (cluster) must have the same identity (Wikipedia link or similar).
                                if identity != state.entity_types[eid][1]:
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='entity-identity-mismatch',
                                        message=f"Entity '{eid}' cannot have identity '{identity}' that does not match '{state.entity_types[eid][1]}' from the first mention on line {state.entity_types[eid][2]}."
                                    ).confirm()
                            # Remember the line where (the current part of) the entity mention starts.
                            mention = {'beid': beid, 'line': state.sentence_line+iline,
                                       'span': [cols[ID]], 'text': cols[FORM],
                                       'length': 1, 'head': head, 'attrstring': attrstring_to_match}
                            state.open_entity_mentions.append(mention)
                            # The set of mentions starting at the current line will be needed later when checking Bridge and SplitAnte statements.
                            if ipart == 1:
                                starting_mentions[eid] = True

                        #--------------------------------------------------------------------------------------------------------------------------------
                        # The code that we will have to execute at single-node continuous parts and at the closing brackets of multi-node continuous parts.
                        def closing_bracket():
                            # Find the corresponding opening bracket and extract the information we need to know.
                            mention_length = 0
                            mention_span = []
                            head = 0
                            opening_line = 0
                            if len(state.open_entity_mentions)==0:
                                Error(
                                    state=state, config=self.incfg,
                                    testid='ill-nested-entities',
                                    message=f"Cannot close entity '{beid}' because there are no open entities."
                                ).confirm()
                                return
                            else:
                                # If the closing bracket does not occur where expected, it is currently only a warning.
                                # We have crossing mention spans in CorefUD 1.0 and it has not been decided yet whether all of them should be illegal.
                                ###!!! Note that this will not catch ill-nested mentions whose only intersection is one node. The bracketing will
                                ###!!! not be a problem in such cases because one mention will be closed first, then the other will be opened.
                                if beid != state.open_entity_mentions[-1]['beid']:
                                    Warning(
                                        state=state, config=self.incfg,
                                        testclass=TestClass.COREF,
                                        testid='ill-nested-entities-warning',
                                        message=f"Entity mentions are not well nested: closing '{beid}' while the innermost open entity is '{state.open_entity_mentions[-1]['beid']}' from line {state.open_entity_mentions[-1]['line']}: {str(state.open_entity_mentions)}."
                                    ).confirm()
                                # Try to find and close the entity whether or not it was well-nested.
                                for i in reversed(range(len(state.open_entity_mentions))):
                                    if state.open_entity_mentions[i]['beid'] == beid:
                                        mention_length = state.open_entity_mentions[i]['length']
                                        mention_span = state.open_entity_mentions[i]['span']
                                        head = state.open_entity_mentions[i]['head']
                                        opening_line = state.open_entity_mentions[i]['line']
                                        state.open_entity_mentions.pop(i)
                                        break
                                else:
                                    # If we did not find the entity to close, then the warning above was not enough and we have to make it a validation error.
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='ill-nested-entities',
                                        message=f"Cannot close entity '{beid}' because it was not found among open entities: {str(state.open_entity_mentions)}"
                                    ).confirm()
                                    return
                            # If this is a part of a discontinuous mention, update the information about the whole mention.
                            # We do this after reading the new part (and not when we see its opening bracket) so that nested
                            # discontinuous mentions of the same entity are possible.
                            if npart > 1:
                                # Update the attributes that have to be updated after each part.
                                if eidnpart in state.open_discontinuous_mentions:
                                    discontinuous_mention = state.open_discontinuous_mentions[eidnpart][-1]
                                    discontinuous_mention['last_ipart'] = ipart
                                    discontinuous_mention['last_part_line'] = opening_line
                                    discontinuous_mention['length'] += mention_length
                                    discontinuous_mention['span'] += mention_span
                                else:
                                    # This should have been taken care of at the opening bracket.
                                    Error(
                                        state=state, config=self.incfg,
                                        testclass=TestClass.INTERNAL,
                                        testid='internal-error',
                                        message="INTERNAL ERROR: at the closing bracket of a part of a discontinuous mention, still no record in state.open_discontinuous_mentions."
                                    ).confirm()
                                    discontinuous_mention = {'last_ipart': ipart, 'npart': npart,
                                                            'first_part_line': opening_line,
                                                            'last_part_line': opening_line,
                                                            'attributes': '', 'length': mention_length,
                                                            'span': mention_span}
                                    state.open_discontinuous_mentions[eidnpart] = [discontinuous_mention]
                                # Update mention_length and mention_span to reflect the whole span up to this point rather than just the last part.
                                mention_length = state.open_discontinuous_mentions[eidnpart][-1]['length']
                                mention_span = state.open_discontinuous_mentions[eidnpart][-1]['span']
                            # We need to know the length (number of nodes) of the mention to check whether the head attribute is within limits.
                            # We need to know the span (list of nodes) of the mention to check that no two mentions have the same span.
                            # We only check these requirements after the last part of the discontinuous span (or after the single part of a continuous one).
                            if ipart == npart:
                                if mention_length < head:
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='mention-head-out-of-range',
                                        message=f"Entity mention head was specified as {head} on line {opening_line} but the mention has only {mention_length} nodes."
                                    ).confirm()
                                # Check that no two mentions have identical spans (only if this is the last part of a mention).
                                ending_mention_key = str(opening_line)+str(mention_span)
                                if ending_mention_key in ending_mentions:
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='same-span-entity-mentions',
                                        message=f"Entity mentions '{ending_mentions[ending_mention_key]}' and '{beid}' from line {opening_line} have the same span {str(mention_span)}."
                                    ).confirm()
                                else:
                                    ending_mentions[ending_mention_key] = beid
                                # Remember the span of the current mention so that we can later check whether it crosses the span of another mention.
                                # Use the current sentence id to partially qualify the node ids. It will not work well for mentions that span multiple
                                # sentences but we do not expect cross-sentence mentions to be frequent.
                                myset = set(mention_span)
                                # Check whether any other mention of the same entity has span that crosses the current one.
                                if eid in state.entity_mention_spans:
                                    if sentid in state.entity_mention_spans[eid]:
                                        for m in state.entity_mention_spans[eid][sentid]:
                                            ms = state.entity_mention_spans[eid][sentid][m]
                                            if ms.intersection(myset) and not ms.issubset(myset) and not myset.issubset(ms):
                                                Error(
                                                    state=state, config=self.incfg,
                                                    testid='crossing-mentions-same-entity',
                                                    message=f"Mentions of entity '{eid}' have crossing spans: {m} vs. {str(mention_span)}."
                                                ).confirm()
                                    else:
                                        state.entity_mention_spans[eid][sentid] = {}
                                else:
                                    state.entity_mention_spans[eid] = {}
                                    state.entity_mention_spans[eid][sentid] = {}
                                state.entity_mention_spans[eid][sentid][str(mention_span)] = myset
                            # At the end of the last part of a discontinuous mention, remove the information about the mention.
                            if npart > 1 and ipart == npart:
                                if eidnpart in state.open_discontinuous_mentions:
                                    if len(state.open_discontinuous_mentions[eidnpart]) > 1:
                                        state.open_discontinuous_mentions[eidnpart].pop()
                                    else:
                                        state.open_discontinuous_mentions.pop(eidnpart)
                        #--------------------------------------------------------------------------------------------------------------------------------

                        # Now we know the beid, eid, as well as all other attributes.
                        # We can check the well-nestedness of brackets.
                        if b==0:
                            if seen2 and not seen1:
                                Error(
                                    state=state, config=self.incfg,
                                    testid='spurious-entity-statement',
                                    message=f"If there are no closing entity brackets, single-node entity must follow all opening entity brackets in '{entity[0]}'."
                                ).confirm()
                            if seen0 and seen2:
                                Error(
                                    state=state, config=self.incfg,
                                    testid='spurious-entity-statement',
                                    message=f"Single-node entity must either precede all closing entity brackets or follow all opening entity brackets in '{entity[0]}'."
                                ).confirm()
                            seen0 = True
                            seen2 = False
                            opening_bracket()
                        elif b==2:
                            if seen1 and not seen0:
                                Error(
                                    state=state, config=self.incfg,
                                    testid='spurious-entity-statement',
                                    message=f"If there are no opening entity brackets, single-node entity must precede all closing entity brackets in '{entity[0]}'."
                                ).confirm()
                            seen2 = True
                            opening_bracket()
                            closing_bracket()
                        else: # b==1
                            if seen0:
                                Error(
                                    state=state, config=self.incfg,
                                    testid='spurious-entity-statement',
                                    message=f"All closing entity brackets must precede all opening entity brackets in '{entity[0]}'."
                                ).confirm()
                            seen1 = True
                            closing_bracket()
                # Now we are done with checking the 'Entity=' statement.
                # If there are also 'Bridge=' or 'SplitAnte=' statements, check them too.
                if len(bridge) > 0:
                    match = re.match(r"^Bridge=([^(< :>)]+<[^(< :>)]+(:[a-z]+)?(,[^(< :>)]+<[^(< :>)]+(:[a-z]+)?)*)$", bridge[0])
                    if not match:
                        Error(
                            state=state, config=self.incfg,
                            testid='spurious-bridge-statement',
                            message=f"Cannot parse the Bridge statement '{bridge[0]}'."
                        ).confirm()
                    else:
                        bridges = match.group(1).split(',')
                        # Hash src<tgt pairs and make sure they are not repeated.
                        srctgt = {}
                        for b in bridges:
                            match = re.match(r"([^(< :>)]+)<([^(< :>)]+)(?::([a-z]+))?^$", b)
                            if match:
                                srceid = match.group(1)
                                tgteid = match.group(2)
                                relation = match.group(3) # optional
                                bridgekey = srceid+'<'+tgteid
                                if srceid == tgteid:
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='spurious-bridge-relation',
                                        message=f"Bridge must not point from an entity to itself: '{b}'."
                                    ).confirm()
                                if not tgteid in starting_mentions:
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='misplaced-bridge-statement',
                                        message=f"Bridge relation '{b}' must be annotated at the beginning of a mention of entity '{tgteid}'."
                                    ).confirm()
                                if bridgekey in srctgt:
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='repeated-bridge-relation',
                                        message=f"Bridge relation '{bridgekey}' must not be repeated in '{b}'."
                                    ).confirm()
                                else:
                                    srctgt[bridgekey] = True
                                # Check in the global dictionary whether this relation has been specified at another mention.
                                if bridgekey in state.entity_bridge_relations:
                                    if relation != state.entity_bridge_relations[bridgekey]['relation']:
                                        Error(
                                            state=state, config=self.incfg,
                                            testid='bridge-relation-mismatch',
                                            message=f"Bridge relation '{b}' type does not match '{state.entity_bridge_relations[bridgekey]['relation']}' specified earlier on line {state.entity_bridge_relations[bridgekey]['line']}."
                                        ).confirm()
                                else:
                                    state.entity_bridge_relations[bridgekey] = {'relation': relation, 'line': state.sentence_line+iline}
                if len(splitante) > 0:
                    match = re.match(r"^SplitAnte=([^(< :>)]+<[^(< :>)]+(,[^(< :>)]+<[^(< :>)]+)*)$", splitante[0])
                    if not match:
                        Error(
                            state=state, config=self.incfg,
                            testid='spurious-splitante-statement',
                            message=f"Cannot parse the SplitAnte statement '{splitante[0]}'."
                        ).confirm()
                    else:
                        antecedents = match.group(1).split(',')
                        # Hash src<tgt pairs and make sure they are not repeated. Also remember the number of antecedents for each target.
                        srctgt = {}
                        tgtante = {}
                        for a in antecedents:
                            match = re.match(r"^([^(< :>)]+)<([^(< :>)]+)$", a)
                            if match:
                                srceid = match.group(1)
                                tgteid = match.group(2)
                                if srceid == tgteid:
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='spurious-splitante-relation',
                                        message=f"SplitAnte must not point from an entity to itself: '{srceid}<{tgteid}'."
                                    ).confirm()
                                elif not tgteid in starting_mentions:
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='misplaced-splitante-statement',
                                        message=f"SplitAnte relation '{a}' must be annotated at the beginning of a mention of entity '{tgteid}'."
                                    ).confirm()
                                if srceid+'<'+tgteid in srctgt:
                                    str_antecedents = ','.join(antecedents)
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='repeated-splitante-relation',
                                        message=f"SplitAnte relation '{srceid}<{tgteid}' must not be repeated in '{str_antecedents}'."
                                    ).confirm()
                                else:
                                    srctgt[srceid+'<'+tgteid] = True
                                if tgteid in tgtante:
                                    tgtante[tgteid].append(srceid)
                                else:
                                    tgtante[tgteid] = [srceid]
                        for tgteid in tgtante:
                            if len(tgtante[tgteid]) == 1:
                                str_antecedents = ','.join(antecedents)
                                Error(
                                    state=state, config=self.incfg,
                                    testid='only-one-split-antecedent',
                                    message=f"SplitAnte statement '{str_antecedents}' must specify at least two antecedents for entity '{tgteid}'."
                                ).confirm()
                            # Check in the global dictionary whether this relation has been specified at another mention.
                            tgtante[tgteid].sort()
                            if tgteid in state.entity_split_antecedents:
                                if tgtante[tgteid] != state.entity_split_antecedents[tgteid]['antecedents']:
                                    Error(
                                        state=state, config=self.incfg,
                                        testid='split-antecedent-mismatch',
                                        message=f"Split antecedent of entity '{tgteid}' does not match '{state.entity_split_antecedents[tgteid]['antecedents']}' specified earlier on line {state.entity_split_antecedents[tgteid]['line']}."
                                    ).confirm()
                            else:
                                state.entity_split_antecedents[tgteid] = {'antecedents': str(tgtante[tgteid]), 'line': state.sentence_line+iline}
        if len(state.open_entity_mentions)>0:
            Error(
                state=state, config=self.incfg,
                testid='cross-sentence-mention',
                message=f"Entity mentions must not cross sentence boundaries; still open at sentence end: {str(state.open_entity_mentions)}."
            ).confirm()
            # Close the mentions forcibly. Otherwise one omitted closing bracket would cause the error messages to to explode because the words would be collected from the remainder of the file.
            state.open_entity_mentions = []
        if len(state.open_discontinuous_mentions)>0:
            Error(
                state=state, config=self.incfg,
                testid='cross-sentence-mention',
                message=f"Entity mentions must not cross sentence boundaries; still open at sentence end: {str(state.open_discontinuous_mentions)}."
            ).confirm()
            # Close the mentions forcibly. Otherwise one omission would cause the error messages to to explode because the words would be collected from the remainder of the file.
            state.open_discontinuous_mentions = {}
        # Since we only test mentions within one sentence at present, we do not have to carry all mention spans until the end of the corpus.
        for eid in state.entity_mention_spans:
            if sentid in state.entity_mention_spans[eid]:
                state.entity_mention_spans[eid].pop(sentid)
