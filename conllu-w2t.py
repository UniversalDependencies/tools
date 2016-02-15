#!/usr/bin/env python

import sys
import re
import file_util
from file_util import ID,HEAD,DEPS #column index for the columns we'll need
import argparse

interval_re=re.compile(ur"^([0-9]+)-([0-9]+)$",re.U)
def get_tokens(wtree):
    """
    Returns a list of tokens in the tree as integer intervals like so:
    [(1,1),(2,3),(4,4),...]

    `tree` is a tree (as produced by trees()) in the word-indexed format
    """
    tokens=[]
    for cols in wtree:
        if cols[ID].isdigit():
            t_id=int(cols[ID])
            #Not covered by the previous interval?
            if not (tokens and tokens[-1][0]<=t_id and tokens[-1][1]>=t_id):
                tokens.append((t_id,t_id)) #nope - let's make a default interval for it
        else:
            match=interval_re.match(cols[ID]) #Check the interval against the regex
            beg,end=int(match.group(1)),int(match.group(2))
            tokens.append((beg,end))
    return tokens

def w2t(wtree):
    tokens=get_tokens(wtree)
    word_ids=[u"0"] #root remains 0
    line_idx=0 #index of the line in wtree we are editing
    for token_idx,(b,e) in enumerate(tokens): #go over all token ranges and produce new IDs for the words involved
        wtree[line_idx][ID]=unicode(token_idx+1) #Renumber the ID field of the token
        if b==e: #token==word
            word_ids.append("%d"%(token_idx+1))
            line_idx+=1
        else:
            #We have a range, renumber the words
            line_idx+=1
            for word_idx,_ in enumerate(range(b,e+1)): #consume as many lines as there are words in the token
                word_ids.append("%d.%d"%(token_idx+1,word_idx+1))
                wtree[line_idx][ID]=word_ids[-1]
                line_idx+=1
    #word_ids is now a list with 1-based indexing which has the new ID for every single word
    #the ID column has been renumbered by now
    #now we can renumber all of the HEAD columns
    for cols in wtree:
        if cols[HEAD]==u"_": #token
            continue
        cols[HEAD]=word_ids[int(cols[HEAD])]
        if cols[DEPS]!=u"_": #need to renumber secondary deps
            new_pairs=[]
            for head_deprel in cols[DEPS].split(u"|"):
                head,deprel=head_deprel.split(u":")
                new_pairs.append(word_ids[int(head)]+u":"+deprel)
            cols[DEPS]=u"|".join(new_pairs)

if __name__=="__main__":
    opt_parser = argparse.ArgumentParser(description='Conversion script from word-based CoNLL-U to token-based CoNLL-U. This script assumes that the input is validated and does no checking on its own.')
    opt_parser.add_argument('input', nargs='?', help='Input file name, or "-" or nothing for standard input.')
    opt_parser.add_argument('output', nargs='?', help='Output file name, or "-" or nothing for standard output.')
    args = opt_parser.parse_args() #Parsed command-line arguments

    inp,out=file_util.in_out(args)
    for comments,tree in file_util.trees(inp):
        w2t(tree)
        file_util.print_tree(comments,tree,out)

