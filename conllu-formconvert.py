import sys
import re
import file_util
from file_util import ID,FORM,HEAD,DEPREL,DEPS #column index for the columns we'll need
import argparse

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
    opt_parser = argparse.ArgumentParser(description='Conversion script from word-based CoNLL-U to other formats.')
    opt_parser.add_argument('input', nargs='?', help='Input file name, or "-" or nothing for standard input.')
    opt_parser.add_argument('output', nargs='?', help='Output file name, or "-" or nothing for standard output.')
    opt_parser.add_argument('-f','--output-format', default="dgraph", help='Output format. Currently supported: dgraph (CoreNLP dep output). Default: %(default)s.')
    args = opt_parser.parse_args() #Parsed command-line arguments

    inp,out=file_util.in_out(args)
    for comments,tree in file_util.trees(inp):
        deps=set() #A set of (gov,dep,dType) where gov and dep are zero-based indices
        for line in tree:
            if not line[ID].isdigit(): #token line, skip
                continue
            if line[HEAD] not in (u"_",u"0"):
                deps.add((int(line[HEAD])-1,int(line[ID])-1,line[DEPREL]))
            #Process also the DEPS field
            if line[DEPS]!=u"_":
                for head_col_deprel in line[DEPS].split(u"|"):
                    head,deprel=head_col_deprel.split(u":",1)
                    deps.add((int(head)-1,int(line[ID])-1,line[DEPREL]))
        #Done. Maybe these should be sorted somehow? Also, what to do if we have no deps?
        for gov,dep,deprel in sorted(deps):
            print >> out, u"%s(%s-%d, %s-%d)"%(deprel,tree[gov][FORM],gov+1,tree[dep][FORM],dep+1)
        print >> out

            
            

