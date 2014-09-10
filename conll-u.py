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

def warn(msg):
    print msg #TODO: encoding

def print_tree(comments,tree,out):
    if comments:
        print >> out, u"\n".join(comments)
    for cols in tree:
        print >> out, u"\t".join(cols)
    print >> out

def trees(inp):
    """
    `inp` a file-like object yielding lines as unicode
    
    This function does elementary checking of the input and yields one
    sentence at a time from the input stream.
    """
    comments=[] #List of comment lines to go with the current sentence
    lines=[] #List of token/word lines of the current sentence
    for line_counter, line in enumerate(inp):
        line=line.rstrip()
        if not line: #empty line
            if lines: #Sentence done
                yield comments, lines
                comments=[]
                lines=[]
            else:
                warn(u"Line %d: Spurious empty line."%(line_counter+1))
        elif line[0]==u"#":
            comments.append(line)
        elif line[0].isdigit():
            cols=line.split(u"\t")
            if len(cols)!=COLCOUNT:
                warn(u"Line %d: The line has %d columns, but %d are expected. Giving up."%(line_counter+1,len(cols),COLCOUNT))
                sys.exit(1)
            lines.append(cols)
        else: #A line which is not a comment, nor a token/word, nor empty. That's bad!
            warn(u"Line %d: Spurious line: '%s'. Giving up."%(line_counter+1,line))
            sys.exit(1) #Give a non-zero exit code
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
                warn(u"Spurious token interval definition: '%s'. Giving up."%cols[ID])
                sys.exit(1)
            beg,end=int(match.group(1)),int(match.group(2))
            tokens.append((beg,end))
    #Now let's do some basic sanity checks on the sequences
    if words!=range(1,len(words)+1): #Words should form a sequence 1,2,...
        warn(u"Words do not form a sequence in the preceding tree. Got: %s. Giving up."%(u",".join(unicode(x) for x in words)))
        sys.exit(1)
    #TODO: Check sanity of word intervals

whitespace_re=re.compile(ur"\s",re.U)
def validate_whitespace(cols):
    """
    Checks a single line for disallowed whitespace.
    """
    for col_idx in range(DEPS+1): #...all columns up to and including DEPS
        if whitespace_re.match(cols[col_idx]) is not None:
            warn(u"Column %s is not allowed to contain whitespace: '%s'"%(COLNAMES[col_idx],cols[col_idx]))
            return False #failed
    return True #passed

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
    
def validate(inp,out,args,tag_sets):
    for comments,tree in trees(inp):
        validate_ID_sequence(tree)
        for cols in tree:
            validate_whitespace(cols)
            validate_features(cols,tag_sets)
            validate_pos(cols,tag_sets)
            validate_deprels(cols,tag_sets)
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
    opt_parser = argparse.ArgumentParser(description='CoNLL-U validation script')

    opt_parser.add_argument("--no-lists", action="store_false", dest="check_lists",default=True, help="Do not check the features, tags and dependency relations against the lists of allowed values. Same as setting all of the files below to 'none'.")
    opt_parser.add_argument("--cpos-file", action="store", default="GoogleTags", help="A file listing the allowed CPOS tags. Default: %(default)s.")
    opt_parser.add_argument("--pos-file", action="store", default="GoogleTags", help="A file listing the allowed POS tags. Default: %(default)s.")
    opt_parser.add_argument("--feature-file", action="store", default="UniMorphSet", help="A file listing the allowed attribute=value pairs. Default: %(default)s.")
    opt_parser.add_argument("--deprel-file", action="store", default="USDRels", help="A file listing the allowed dependency relations for DEPREL. Default: %(default)s.")
    opt_parser.add_argument("--deps-file", action="store", default="USDRels", help="A file listing the allowed dependency relations for DEPS. Default: %(default)s.")

    opt_parser.add_argument('--noecho', dest="echo_input", action="store_false", default=True, help='Do not echo the input.')
    opt_parser.add_argument('input', nargs='?', help='Input file name, or "-" or nothing for standard input.')
    opt_parser.add_argument('output', nargs='?', help='Output file name, or "-" or nothing for standard output.')
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
    validate(inp,out,args,tagsets)
