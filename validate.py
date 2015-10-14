#! /usr/bin/python
import sys
import codecs
import os.path
import logging
import re
import file_util

try:
    import argparse
except:
    #we are on Python 2.6 or older
    from compat import argparse


THISDIR=os.path.dirname(os.path.abspath(__file__)) #The directory where this script resides

#Constants for the column indices
COLCOUNT=10
ID,FORM,LEMMA,CPOSTAG,POSTAG,FEATS,HEAD,DEPREL,DEPS,MISC=range(COLCOUNT)
COLNAMES=u"ID,FORM,LEMMA,CPOSTAG,POSTAG,FEATS,HEAD,DEPREL,DEPS,MISC".split(u",")

error_counter={} #key: error type value: error count
def warn(msg,error_type,lineno=True):
    """
    Print the warning. If lineno is True, print the exact line, otherwise
    print the line on which the current tree starts.
    """
    global curr_line, sentence_line, error_counter, tree_counter, args
    error_counter[error_type]=error_counter.get(error_type,0)+1
    if not args.quiet:
        if args.max_err>0 and error_counter[error_type]==args.max_err:
            print >> sys.stderr, (u"...suppressing further errors regarding "+error_type).encode(args.err_enc)
        elif args.max_err>0 and error_counter[error_type]>args.max_err:
            pass #suppressed
        else:
            if lineno:
                print >> sys.stderr, (u"[Line                   %d]: %s"%(curr_line,msg)).encode(args.err_enc)
            else:
                print >> sys.stderr, (u"[Tree number %d on line %d]: %s"%(tree_counter,sentence_line,msg)).encode(args.err_enc)

    ## I think this is no longer needed here
    # if args.max_err>0:
    #     for err_type in and error_counter[error_type]>=args.max_err:
    #     print >> sys.stderr, (u"...aborting due to too many errors. You can use --max-err to adjust the threshold").encode(args.err_enc)
    #     sys.exit(1)


#Two global variables:
curr_line=0 #Current line in the input file
sentence_line=0 #The line in the input file on which the current sentence starts
def trees(inp,tag_sets,args):
    """
    `inp` a file-like object yielding lines as unicode
    `tag_sets` and `args` are needed for choosing the tests
    
    This function does elementary checking of the input and yields one
    sentence at a time from the input stream.
    """
    global curr_line, sentence_line
    comments=[] #List of comment lines to go with the current sentence
    lines=[] #List of token/word lines of the current sentence
    for line_counter, line in enumerate(inp):
        curr_line=line_counter+1
        line=line.rstrip(u"\n")
        if not line: #empty line
            if lines: #Sentence done
                yield comments, lines
                comments=[]
                lines=[]
            else:
                warn(u"Spurious empty line.",u"Format")
        elif line[0]==u"#":
            if not lines: # before sentence
                comments.append(line)
            else:
                warn(u"Spurious comment line.",u"Format")
        elif line[0].isdigit():
            if not lines: #new sentence
                sentence_line=curr_line
            cols=line.split(u"\t")
            if len(cols)!=COLCOUNT:
                warn(u"The line has %d columns, but %d are expected."%(len(cols),COLCOUNT),u"Format")
            lines.append(cols)
            validate_cols(cols,tag_sets,args)
        else: #A line which is not a comment, nor a token/word, nor empty. That's bad!
            warn(u"Spurious line: '%s'. All non-empty lines should start with a digit or the # character."%(line),u"Format")
    else: #end of file
        if comments or lines: #These should have been yielded on an empty line!
            warn(u"Missing empty line after the last tree.",u"Format")
            yield comments, lines

###### Tests applicable to a single row indpendently of the others

def validate_cols(cols,tag_sets,args):
    """
    All tests that can run on a single line. Done as soon as the line is read,
    called from trees()
    """
    validate_whitespace(cols)
    validate_token_empty_vals(cols)
    if not cols[ID].isdigit():
        return #The stuff below applies to words and not tokens
    validate_features(cols,tag_sets)
    validate_pos(cols,tag_sets)
    validate_deprels(cols,tag_sets)
    validate_character_constraints(cols)

whitespace_re=re.compile(ur".*\s",re.U)
def validate_whitespace(cols):
    """
    Checks a single line for disallowed whitespace.
    """
    for col_idx in range(MISC+1): #...all columns up to and including MISC (i.e. all columns ;)
        if not cols[col_idx]:
            warn(u"Empty value in column %s"%(COLNAMES[col_idx]),u"Format")
        if whitespace_re.match(cols[col_idx]) is not None:
            warn(u"Column %s is not allowed to contain whitespace: '%s'"%(COLNAMES[col_idx],cols[col_idx]),u"Format")

def validate_token_empty_vals(cols):
    """
    Checks that a token only has _ empty values in all fields except MISC.
    """
    if cols[ID].isdigit(): #not a token line
        return 
    for col_idx in range(LEMMA,MISC): #all columns in the LEMMA-DEPS range
        if cols[col_idx]!=u"_":
            warn(u"A token line must have '_' in the column %s. Now: '%s'."%(COLNAMES[col_idx],cols[col_idx]),u"Format")
        

attr_val_re=re.compile(ur"^([A-Z0-9][A-Z0-9a-z]*(?:\[[a-z0-9]+\])?)=(([A-Z0-9][A-Z0-9a-z]*)(,([A-Z0-9][A-Z0-9a-z]*))*)$",re.U)
val_re=re.compile(ur"^[A-Z0-9][A-Z0-9a-z]*",re.U)
def validate_features(cols,tag_sets):
    feats=cols[FEATS]
    if feats==u"_":
        return True
    feat_list=feats.split(u"|")
    #the lower() thing is to be on the safe side, since all features must start with [A-Z0-9] anyway
    if [f.lower() for f in feat_list]!=sorted(f.lower() for f in feat_list):
        warn(u"Morphological features must be sorted: '%s'"%feats,u"Morpho")
    attr_set=set() #I'll gather the set of attributes here to check later than none is repeated 
    for f in feat_list:
        match=attr_val_re.match(f)
        if match is None:
            warn(u"Spurious morphological feature: '%s'. Should be of the form attribute=value and must start with [A-Z0-9] and only contain [A-Za-z0-9]."%f,u"Morpho")
        else:
            #Check that the values are sorted as well
            attr=match.group(1)
            attr_set.add(attr)
            values=match.group(2).split(u",")
            if len(values)!=len(set(values)):
                warn(u"Repeated features values are disallowed: %s"%feats,u"Morpho")
            if [v.lower() for v in values]!=sorted(v.lower() for v in values):
                warn(u"If an attribute has multiple values, these must be sorted as well: '%s'"%f,u"Morpho")
            for v in values:
                if not val_re.match(v):
                    warn(u"Incorrect value '%s' in '%s'. Must start with [A-Z0-9] and only contain [A-Za-z0-9]."%(v,f),u"Morpho")
                if tag_sets[FEATS] is not None and attr+u"="+v not in tag_sets[FEATS]:
                    warn(u"Unknown attribute-value pair %s=%s"%(attr,v),u"Morpho")
    if len(attr_set)!=len(feat_list):
        warn(u"Repeated features are disallowed: %s"%feats, u"Morpho")

def validate_pos(cols,tag_sets):
    if tag_sets[CPOSTAG] is not None and cols[CPOSTAG] not in tag_sets[CPOSTAG]:
        warn(u"Unknown CPOS tag: %s"%cols[CPOSTAG],u"Morpho")
    if tag_sets[POSTAG] is not None and cols[POSTAG] not in tag_sets[POSTAG]:
        warn(u"Unknown POS tag: %s"%cols[POSTAG],u"Morpho")
    
def lspec2ud(deprel):
    return deprel.split(u":",1)[0]


def validate_deprels(cols,tag_sets):
    if tag_sets[DEPREL] is not None and cols[DEPREL] not in tag_sets[DEPREL]:
        warn(u"Unknown UD DEPREL: %s"%cols[DEPREL],u"Syntax")
    if tag_sets[DEPS] is not None and cols[DEPS]!=u"_":
        for head_deprel in cols[DEPS].split(u"|"):
            try:
                head,deprel=head_deprel.split(u":",1)
            except ValueError:
                warn(u"Malformed head:deprel pair '%s'"%head_deprel,u"Syntax")
                continue
            if lspec2ud(deprel) not in tag_sets[DEPS]:
                warn(u"Unknown dependency relation '%s' in '%s'"%(deprel,head_deprel),u"Syntax")

def validate_character_constraints(cols):
    """
    Checks general constraints on valid characters, e.g. that CPOSTAG
    only contains [A-Z].
    """
    if not cols[ID].isdigit():
        return # skip multiword tokens

    if not re.match(r"^[A-Z]+$", cols[CPOSTAG]):
        warn("Invalid CPOSTAG value %s" % cols[CPOSTAG],u"Morpho")
    if not re.match(r"^[a-z][a-z_-]*(:[a-z][a-z_-]*)?$", cols[DEPREL]):
        warn("Invalid DEPREL value %s" % cols[DEPREL],u"Syntax")
    try:
        deps = deps_list(cols)
    except ValueError:
        warn(u"Failed for parse DEPS: %s" % cols[DEPS],u"Syntax")
        return
    if any(deprel for head, deprel in deps_list(cols)
           if not re.match(r"^[a-z][a-z_-]*", deprel)):
        warn("Invalid value in DEPS: %s" % cols[DEPS],u"Syntax")


##### Tests applicable to the whole tree

interval_re=re.compile(ur"^([0-9]+)-([0-9]+)$",re.U)
def validate_ID_sequence(tree):
    """
    Validates that the ID sequence is correctly formed. Assumes word indexing.
    """
    words=[]
    tokens=[]
    for cols in tree:
        if cols[ID].isdigit():
            t_id=int(cols[ID])
            words.append(t_id)
            #Not covered by the previous interval?
            if not (tokens and tokens[-1][0]<=t_id and tokens[-1][1]>=t_id):
                tokens.append((t_id,t_id)) #nope - let's make a default interval for it
        else:
            match=interval_re.match(cols[ID]) #Check the interval against the regex
            if not match:
                warn(u"Spurious token interval definition: '%s'."%cols[ID],u"Format",lineno=False)
                continue
            beg,end=int(match.group(1)),int(match.group(2))
            if not ((not words and beg == 1) or (words and beg == words[-1]+1)):
                warn(u"Multiword range not before its first word",u"Format")
                continue
            tokens.append((beg,end))
    #Now let's do some basic sanity checks on the sequences
    if words!=range(1,len(words)+1): #Words should form a sequence 1,2,...
        warn(u"Words do not form a sequence. Got: %s."%(u",".join(unicode(x) for x in words)),u"Format",lineno=False)
    #TODO: Check sanity of word intervals
                
def subset_to_words(tree):
    """
    Only picks the word lines, skips token lines.
    """
    return [cols for cols in tree if cols[ID].isdigit()]

def deps_list(cols):
    if cols[DEPS] == u'_':
        deps = []
    else:
        deps = [hd.split(u':',1) for hd in cols[DEPS].split(u'|')]
    if any(hd for hd in deps if len(hd) != 2):
        raise ValueError(u'malformed DEPS: %s' % cols[DEPS])
    return deps

def validate_ID_references(tree):
    """
    Validates that HEAD and DEPRELS reference existing IDs.
    """

    word_tree = subset_to_words(tree)
    ids = set([cols[ID] for cols in word_tree])

    def valid_id(i):
        return i in ids or i == u'0'

    for cols in word_tree:
        if not valid_id(cols[HEAD]):
            warn(u"Undefined ID in HEAD: %s" % cols[HEAD],u"Format")
        try:
            deps = deps_list(cols)
        except ValueError:
            warn(u"Failed for parse DEPS: %s" % cols[DEPS],u"Format")
            continue
        for head, deprel in deps:
            if not valid_id(head):
                warn(u"Undefined ID in DEPS: %s" % head,u"Format")

def proj(node,s,deps,depth,max_depth):
    """
    Recursive calculation of the projection of a node `node` (1-based
    integer). The nodes, as they get discovered` are added to the set
    `s`. Deps is a dictionary node -> set of children.
    """
    if max_depth is not None and depth==max_depth:
        return
    for dependent in deps.get(node,[]):
        if dependent in s:
            warn(u"Loop from %s" % dependent,u"Syntax")
            continue
        s.add(dependent)
        proj(dependent,s,deps,depth+1,max_depth)

def validate_token_ranges(tree):
    """
    Checks that the word ranges for multiword tokens are valid.
    """

    covered = set()

    for cols in tree:
        if cols[ID].isdigit(): # not a multiword token
            continue

        m = interval_re.match(cols[ID])
        if not m:
            warn(u"Failed to parse ID %s" % cols[ID],u"Format")
            continue

        start, end = m.groups()
        try:
            start, end = int(start), int(end)
        except ValueError:
            assert False, 'internal error' # RE should assure that this works

        if not start < end:
            warn(u"Invalid range: %s" % cols[ID],u"Format")
            continue

        if covered & set(range(start, end+1)):
            warn(u"Range overlaps with others: %s" % cols[ID],u"Format")
        covered |= set(range(start, end+1))

def validate_root(tree):
    """
    Validates that DEPREL is "root" iff HEAD is 0.
    """
    for cols in subset_to_words(tree):
        if cols[HEAD] == u'0':
            if cols[DEPREL] != u'root':
                warn(u'DEPREL must be "root" if HEAD is 0',u"Syntax")
        else:
            if cols[DEPREL] == u'root':
                warn(u'DEPREL can only be "root" if HEAD is 0',u"Syntax")

def validate_deps(tree):
    """
    Validates that DEPS is correctly formatted and that there are no
    self-loops in DEPS.
    """
    for cols in subset_to_words(tree):
        try:
            deps = deps_list(cols)
            heads = [int(h) for h, d in deps]
        except ValueError:
            warn(u"Failed for parse DEPS: %s" % cols[DEPS],u"Format")
            return
        if heads != sorted(heads):
            warn(u"DEPS not sorted by head index: %s" % cols[DEPS],u"Format")

        try:
            id_ = int(cols[ID])
        except ValueError:
            warn(u"Non-integer ID: %s" % cols[ID],u"Format")
            return
        if id_ in heads:
            warn(u"ID in DEPS for %s" % cols[ID],u"Format")

def validate_tree(tree):
    """
    Validates that all words can be reached from the root and that
    there are no self-loops in HEAD.
    """
    deps={} #node -> set of children
    word_tree=subset_to_words(tree)
    for cols in word_tree:
        if cols[HEAD]==u"_":
            warn(u"Empty head for word ID %s" % cols[ID], u"Format", lineno=False)
            continue
        try:
            id_ = int(cols[ID])
        except ValueError:
            warn(u"Non-integer ID: %s" % cols[ID], u"Format", lineno=False)
            continue
        try:
            head = int(cols[HEAD])
        except ValueError:
            warn(u"Non-integer head for word ID %s" % cols[ID], u"Format", lineno=False)
            continue
        if head == id_:
            warn(u"HEAD == ID for %s" % cols[ID], u"Format", lineno=False)
            continue
        deps.setdefault(head, set()).add(id_)
    root_deps=set()
    proj(0,root_deps,deps,0,1)
    if len(root_deps)>1 and args.single_root:
        warn(u"Multiple root words: %s"%list(root_deps), u"Syntax", lineno=False)
    root_proj=set()
    proj(0,root_proj,deps,0,None)
    unreachable=set(range(1,len(word_tree)+1))-root_proj #all words minus those reachable from root
    if unreachable:
        warn(u"Non-tree structure. Words %s are not reachable from the root 0."%(u",".join(unicode(w) for w in sorted(unreachable))),u"Syntax",lineno=False)

def validate_newlines(inp):
    if inp.newlines and inp.newlines!='\n':
        warn("Only the unix-style LF line terminator is allowed",u"Format")
    
def validate(inp,out,args,tag_sets):
    global tree_counter
    for comments,tree in trees(inp,tag_sets,args):
        tree_counter+=1
        #the individual lines have been validated already in trees()
        #here go tests which are done on the whole tree
        validate_ID_sequence(tree)
        validate_ID_references(tree)
        validate_token_ranges(tree)
        validate_root(tree)
        validate_deps(tree)
        validate_tree(tree)
        if args.echo_input:
            file_util.print_tree(comments,tree,out)
    validate_newlines(inp)

def load_file(f_name):
    res=set()
    with codecs.open(f_name,"r","utf-8") as f:
        for line in f:
            line=line.strip()
            if not line or line.startswith(u"#"):
                continue
            res.add(line)
    return res

def load_set(f_name_ud,f_name_langspec):
    """
    Loads a list of values from the two files, and returns their
    set. If f_name_langspec doesn't exist, loads nothing and returns
    None (ie this taglist is not checked for the given language). If f_name_langspec
    is None, only loads the UD one. This is probably only useful for CPOS which doesn't
    allow language-specific extensions.
    """
    if f_name_langspec is not None and not os.path.exists(os.path.join(THISDIR,"data",f_name_langspec)):
        return None #No lang-spec file but would expect one, do no checking
    res=load_file(os.path.join(THISDIR,"data",f_name_ud))
    if f_name_langspec is not None:
        res.update(load_file(os.path.join(THISDIR,"data",f_name_langspec)))
    return res

if __name__=="__main__":
    opt_parser = argparse.ArgumentParser(description="CoNLL-U validation script")

    io_group=opt_parser.add_argument_group("Input / output options")
    io_group.add_argument('--noecho', dest="echo_input", action="store_false", default=False, help='Do not echo the input CoNLL-U data onto output. (for backward compatibility)')
    io_group.add_argument('--echo', dest="echo_input", action="store_true", default=False, help='Echo the input CoNLL-U data onto output. (for backward compatibility)')
    io_group.add_argument('--quiet', dest="quiet", action="store_true", default=False, help='Do not print any error messages. Exit with 0 on pass, non-zero on fail. Implies --noecho.')
    io_group.add_argument('--max-err', action="store", type=int, default=20, help='How many errors to output before exiting? 0 for all. Default: %(default)d.')
    io_group.add_argument('--err-enc', action="store", default="utf-8", help='Encoding of the error message output. Default: %(default)s. Note that the CoNLL-U output is by definition always utf-8.')
    io_group.add_argument('input', nargs='?', help='Input file name, or "-" or nothing for standard input.')
    io_group.add_argument('output', nargs='?', help='Output file name, or "-" or nothing for standard output.')

    list_group=opt_parser.add_argument_group("Tag sets","Options relevant to checking tag sets.")
    list_group.add_argument("--lang", action="store", required=True, default=None, help="Which langauge are we checking? If you specify this (as a two-letter code), the tags will be checked using the language-specific files in the data/ directory of the validator. It's also possible to use 'ud' for checking compliance with purely ud.")

    tree_group=opt_parser.add_argument_group("Tree constraints","Options for checking the validity of the tree.")
    tree_group.add_argument("--multiple-roots", action="store_false", default=True, dest="single_root", help="Allow trees with several root words (single root required by default).")

    args = opt_parser.parse_args() #Parsed command-line arguments
    error_counter={} #Incremented by warn()  {key: error type value: its count}
    tree_counter=0

    if args.quiet:
        args.echo_input=False

    tagsets={POSTAG:None,CPOSTAG:None,FEATS:None,DEPREL:None,DEPS:None} #sets of tags for every column that needs to be checked

    if args.lang:
        tagsets[DEPREL]=load_set("deprel.ud","deprel."+args.lang)
        if tagsets[DEPREL] is None:
            warn(u"The language-specific file data/deprel.%s could not be found. Dependency relations will not be checked.\nPlease add the language-specific dependency relations using python conllu-stats.py --deprels=langspec yourdata/*.conllu > data/deprel.%s\n Also please check that file for errorneous relations. It's okay if the file is empty, but it must exist.\n\n"%(args.lang,args.lang),"Language specific data missing",lineno=False)
        tagsets[DEPS]=tagsets[DEPREL]
        tagsets[FEATS]=load_set("feat_val.ud","feat_val."+args.lang)
        if tagsets[FEATS] is None:
            warn(u"The language-specific file data/feat_val.%s could not be found. Feature=value pairs will not be checked.\nPlease add the language-specific pairs using python conllu-stats.py --catvals=langspec yourdata/*.conllu > data/featval.%s It's okay if the file is empty, but it must exist.\n \n\n"%(args.lang,args.lang),"Language specific data missing",lineno=False)
        tagsets[CPOSTAG]=load_set("cpos.ud",None)

    inp,out=file_util.in_out(args)



    validate(inp,out,args,tagsets)
    if not error_counter:
        if not args.quiet:
            print >> sys.stderr, "*** PASSED ***"
        sys.exit(0)
    else:
        if not args.quiet:
            print >> sys.stderr, "*** FAILED *** with %d errors"%sum(v for k,v in error_counter.iteritems())
            for k,v in sorted(error_counter.items()):
                print >> sys.stderr, k, "errors:", v
        sys.exit(1)
    
