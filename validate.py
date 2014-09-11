#! /usr/bin/python
import sys
import codecs
import argparse
import os.path
import logging
import re
import file_util

THISDIR=os.path.dirname(os.path.abspath(__file__)) #The directory where this script resides

#Constants for the column indices
COLCOUNT=10
ID,FORM,LEMMA,CPOSTAG,POSTAG,FEATS,HEAD,DEPREL,DEPS,MISC=range(COLCOUNT)
COLNAMES=u"ID,FORM,LEMMA,CPOSTAG,POSTAG,FEATS,HEAD,DEPREL,DEPS,MISC".split(u",")

error_counter=0
def warn(msg,lineno=True):
    """
    Print the warning. If lineno is True, print the exact line, otherwise
    print the line on which the current tree starts.
    """
    global curr_line, sentence_line, error_counter, args
    if lineno:
        print u"[Line         %d]: %s"%(curr_line,msg)
    else:
        print u"[Tree on line %d]: %s"%(sentence_line,msg)
    error_counter+=1
    if args.max_err>0 and error_counter==args.max_err:
        sys.exit(1)

def print_tree(comments,tree,out):
    if comments:
        print >> out, u"\n".join(comments)
    for cols in tree:
        print >> out, u"\t".join(cols)
    print >> out


#Two global variables:
curr_line=0 #Current line in the input file
sentence_line=0 #The line in the input file on which the current sentence starts
def trees(inp):
    """
    `inp` a file-like object yielding lines as unicode
    
    This function does elementary checking of the input and yields one
    sentence at a time from the input stream.
    """
    global curr_line, sentence_line
    comments=[] #List of comment lines to go with the current sentence
    lines=[] #List of token/word lines of the current sentence
    for line_counter, line in enumerate(inp):
        curr_line=line_counter+1
        line=line.rstrip()
        if not line: #empty line
            if lines: #Sentence done
                yield comments, lines
                comments=[]
                lines=[]
            else:
                warn(u"Spurious empty line.")
        elif line[0]==u"#":
            comments.append(line)
        elif line[0].isdigit():
            if not lines: #new sentence
                sentence_line=curr_line
            cols=line.split(u"\t")
            if len(cols)!=COLCOUNT:
                warn(u"The line has %d columns, but %d are expected."%(len(cols),COLCOUNT))
            lines.append(cols)
        else: #A line which is not a comment, nor a token/word, nor empty. That's bad!
            warn(u"Spurious line: '%s'. All non-empty lines should start with a digit or the # character."%(line))
    else: #end of file
        if comments or lines: #These should have been yielded on an empty line!
            warn(u"Missing empty line after the last tree.")
            yield comments, lines

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
                warn(u"Spurious token interval definition: '%s'."%cols[ID],lineno=False)
            beg,end=int(match.group(1)),int(match.group(2))
            tokens.append((beg,end))
    #Now let's do some basic sanity checks on the sequences
    if words!=range(1,len(words)+1): #Words should form a sequence 1,2,...
        warn(u"Words do not form a sequence. Got: %s."%(u",".join(unicode(x) for x in words)),lineno=False)
    #TODO: Check sanity of word intervals

whitespace_re=re.compile(ur".*\s",re.U)
def validate_whitespace(cols):
    """
    Checks a single line for disallowed whitespace.
    """
    for col_idx in range(MISC+1): #...all columns up to and including MISC (i.e. all columns ;)
        if whitespace_re.match(cols[col_idx]) is not None:
            warn(u"Column %s is not allowed to contain whitespace: '%s'"%(COLNAMES[col_idx],cols[col_idx]))

attr_val_re=re.compile(ur"^([^=]+)=([^=]+)$",re.U) #TODO: Maybe this can be made tighter?
def validate_features(cols,tag_sets):
    feats=cols[FEATS]
    if feats==u"_":
        return True
    feat_list=feats.split(u"|")
    if feat_list!=sorted(feat_list):
        warn(u"Morphological features must be sorted: '%s'"%feats)
    for f in feat_list:
        match=attr_val_re.match(f)
        if match is None:
            warn(u"Spurious morhological feature: '%s'. Should be of the form attribute=value."%f)
        else:
            #Check that the values are sorted as well
            attr=match.group(1)
            values=match.group(2).split(u"+")
            if values!=sorted(values):
                warn(u"If an attribute has multiple values, these must be sorted as well: '%s'"%f)
            for v in values:
                if tag_sets[FEATS] is not None and attr+u"="+v not in tag_sets[FEATS]:
                    warn(u"Unknown attribute-value pair %s=%s"%(attr,v))

def validate_pos(cols,tag_sets):
    if tag_sets[CPOSTAG] is not None and cols[CPOSTAG] not in tag_sets[CPOSTAG]:
        warn(u"Unknown CPOS tag: %s"%cols[CPOSTAG])
    if tag_sets[POSTAG] is not None and cols[POSTAG] not in tag_sets[POSTAG]:
        warn(u"Unknown POS tag: %s"%cols[POSTAG])
    

def validate_deprels(cols,tag_sets):
    if tag_sets[DEPREL] is not None and cols[DEPREL] not in tag_sets[DEPREL]:
        warn(u"Unknown DEPREL: %s"%cols[DEPREL])
    if tag_sets[DEPS] is not None and cols[DEPS]!=u"_":
        for head_deprel in cols[DEPS].split(u"|"):
            head,deprel=head_deprel.split(u":")
            if deprel not in tag_sets[DEPS]:
                warn(u"Unknown dependency relation '%s' in '%s'"%(deprel,head_deprel))
                
def subset_to_words(tree):
    """
    Only picks the word lines, skips token lines.
    """
    return [cols for cols in tree if cols[ID].isdigit()]

def proj(node,s,deps):
    """
    Recursive calculation of the projection of a node `node` (1-based
    integer). The nodes, as they get discovered` are added to the set
    `s`. Deps is a dictionary node -> set of children.
    """
    for dependent in deps.get(node,[]):
        s.add(dependent)
        proj(dependent,s,deps)

def validate_tree(tree):
    deps={} #node -> set of children
    word_tree=subset_to_words(tree)
    for cols in word_tree:
        if cols[HEAD]==u"_":
            warn(u"Empty head for word ID %s"%cols[ID],lineno=False)
        else:
            deps.setdefault(int(cols[HEAD]),set()).add(int(cols[ID]))
    root_proj=set()
    proj(0,root_proj,deps)
    unreachable=set(range(1,len(word_tree)+1))-root_proj #all words minus those reachable from root
    if unreachable:
        warn(u"Non-tree structure. Words %s are not reachable from the root 0."%(u",".join(unicode(w) for w in sorted(unreachable))),lineno=False)
    
def validate(inp,out,args,tag_sets):
    for comments,tree in trees(inp):
        validate_ID_sequence(tree)
        for cols in tree:
            validate_whitespace(cols)
            validate_features(cols,tag_sets)
            validate_pos(cols,tag_sets)
            validate_deprels(cols,tag_sets)
        validate_tree(tree)
        if args.echo_input:
            print_tree(comments,tree,out)

def load_set(f_name):
    """
    Loads a list of values from f_name, and returns their set. If
    f_name is "none", return None. If f_name is not found, tries to
    look in the local data dir.
    """
    if f_name.lower()=="none":
        return None
    res=set()
    if not os.path.exists(f_name) and os.path.exists(os.path.join(THISDIR,"data",f_name)):
        f_name=os.path.join(THISDIR,"data",f_name)
    with codecs.open(f_name,"r","utf-8") as f:
        for line in f:
            line=line.strip()
            if not line or line.startswith(u"#"):
                continue
            res.add(line)
    return res

if __name__=="__main__":
    opt_parser = argparse.ArgumentParser(description="CoNLL-U validation script")

    io_group=opt_parser.add_argument_group("Input / output options")
    io_group.add_argument('--noecho', dest="echo_input", action="store_false", default=True, help='Do not echo the input.')
    io_group.add_argument('--max-err', action="store", type=int, default=20, help='How many errors to output before exiting? 0 for all. Default: %(default)d.')
    io_group.add_argument('input', nargs='?', help='Input file name, or "-" or nothing for standard input.')
    io_group.add_argument('output', nargs='?', help='Output file name, or "-" or nothing for standard output.')

    list_group=opt_parser.add_argument_group("Tag sets","Options relevant to checking tag sets. The various file name options can be set to an existing file, a file name in the local data directory, or 'none'.")
    list_group.add_argument("--no-lists", action="store_false", dest="check_lists",default=True, help="Do not check the features, tags and dependency relations against the lists of allowed values. Same as setting all of the files below to 'none'.")
    list_group.add_argument("--cpos-file", action="store", default="GoogleTags", help="A file listing the allowed CPOS tags. Default: %(default)s.")
    list_group.add_argument("--pos-file", action="store", default="FineTags", help="A file listing the allowed POS tags. Default: %(default)s.")
    list_group.add_argument("--feature-file", action="store", default="UniMorphSet", help="A file listing the allowed attribute=value pairs. Default: %(default)s.")
    list_group.add_argument("--deprel-file", action="store", default="USDRels", help="A file listing the allowed dependency relations for DEPREL. Default: %(default)s.")
    list_group.add_argument("--deps-file", action="store", default="USDRels", help="A file listing the allowed dependency relations for DEPS. Default: %(default)s.")

    tree_group=opt_parser.add_argument_group("Tree constraints","Options for checking the validity of the tree.")


    args = opt_parser.parse_args() #Parsed command-line arguments


    tagsets={POSTAG:None,CPOSTAG:None,FEATS:None,DEPREL:None,DEPS:None} #sets of tags for every column that needs to be checked
    #Load the tag lists
    if args.check_lists:
        tagsets[FEATS]=load_set(args.feature_file)
        tagsets[POSTAG]=load_set(args.pos_file)
        tagsets[CPOSTAG]=load_set(args.cpos_file)
        tagsets[DEPREL]=load_set(args.deprel_file)
        tagsets[DEPS]=load_set(args.deps_file)
        

    inp,out=file_util.in_out(args)
    error_counter=0 #Incremented by warn()
    validate(inp,out,args,tagsets)
    if error_counter==0:
        print >> sys.stderr, "*** PASSED ***"
        sys.exit(0)
    else:
        print >> sys.stderr, "*** FAILED *** with %d errors"%error_counter
        sys.exit(1)
    
