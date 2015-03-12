import sys
import re
import file_util
from file_util import CPOSTAG,FEATS,DEPREL,DEPS #column index for the columns we'll need
import argparse

class Stats(object):

    def __init__(self):
        self.token_count=0
        self.word_count=0
        self.tree_count=0
        self.f_val_counter={} #key:f=val  value: count
        self.deprel_counter={} #key:deprel value: count
        
    def count_cols(self,cols):
        if cols[0].isdigit(): #word
            self.word_count+=1
            self.token_count+=1 #every word is also a one-word token
        else: #token
            b,e=cols[0].split(u"-")
            b,e=int(b),int(e)
            self.token_count-=e-b #every word is counted as a token, so subtract all but one to offset for that
        if cols[CPOSTAG]!=u"_":
            self.f_val_counter[u"CPOSTAG="+cols[CPOSTAG]]=self.f_val_counter.get(u"CPOSTAG="+cols[CPOSTAG],0)+1
        if cols[FEATS]!=u"_":
            for cat_is_vals in cols[FEATS].split(u"|"):
                cat,vals=cat_is_vals.split(u"=",1)
                for val in vals.split(u","):
                    self.f_val_counter[cat+u"="+val]=self.f_val_counter.get(cat+u"="+val,0)+1
        if cols[DEPREL]!=u"_":
            self.deprel_counter[cols[DEPREL]]=self.deprel_counter.get(cols[DEPREL],0)+1
        if cols[DEPS]!=u"_":
            for head_and_deprel in cols[DEPS].split(u"|"):
                head,deprel=head_and_deprel.split(u":",1)
                self.deprel_counter[deprel]=self.deprel_counter.get(deprel,0)+1
    
    def print_basic_stats(self,out):
        print >> out, "Tree count: ", self.tree_count
        print >> out, "Word count: ", self.word_count
        print >> out, "Token count:", self.token_count
        langspec=sum(1 for deprel in self.deprel_counter.iterkeys() if u":" in deprel)
        print >> out, "Dep. relations: %d of which %d language specific"%(len(self.deprel_counter),langspec)
        print >> out, "POS tags:",sum(1 for cat_is_val in self.f_val_counter if cat_is_val.startswith(u"CPOSTAG="))
        print >> out, "Category=value feature pairs:",sum(1 for cat_is_val in self.f_val_counter if not cat_is_val.startswith(u"CPOSTAG="))

    def print_deprels(self,out,which=u"UD+langspec"):
        #which can be UD, langspec
        for deprel,count in sorted(self.deprel_counter.iteritems(),key=lambda x:x[1],reverse=True):
            if u":" in deprel and u"langspec" in which:
                print >> out, deprel
            if u":" not in deprel and u"UD" in which:
                print >> out, deprel

    def print_features(self,out):
        for cat_is_val,count in sorted(self.f_val_counter.iteritems(),key=lambda x:x[1],reverse=True):
            if not cat_is_val.startswith(u"CPOSTAG="):
                print >> out, cat_is_val
        
        

if __name__=="__main__":
    opt_parser = argparse.ArgumentParser(description='Script for basic stats generation. Assumes a validated input.')
    opt_parser.add_argument('input', nargs='+', help='Input file name (can be several files), or "-" or nothing for standard input.')
    opt_parser.add_argument('--stats',action='store_true',default=False, help='Print basic stats')
    opt_parser.add_argument('--deprels',default=None,help='Print deprels. The values can be "UD", "langspec", or "UD+langspec"')
    opt_parser.add_argument('--catvals',action='store_true',default=False,help='Print category=value pairs.')
    args = opt_parser.parse_args() #Parsed command-line arguments
    args.output="-"
    inp,out=file_util.in_out(args,multiple_files=True)

    stats=Stats()
    for comments,tree in file_util.trees(inp):
        stats.tree_count+=1
        for cols in tree:
            stats.count_cols(cols)
    if args.stats:
        stats.print_basic_stats(out)
    if args.deprels:
        stats.print_deprels(out,args.deprels)
    if args.catvals:
        stats.print_features(out)

    


