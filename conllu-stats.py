import sys
import re
import file_util
from file_util import FORM,LEMMA,CPOSTAG,FEATS,DEPREL,DEPS #column index for the columns we'll need
import argparse
import os
import codecs 
import json
import traceback

THISDIR=os.path.dirname(os.path.abspath(__file__))

class Stats(object):

    def __init__(self):
        self.token_count=0
        self.word_count=0
        self.tree_count=0
        self.words_with_lemma_count=0
        self.words_with_deps_count=0
        self.f_val_counter={} #key:f=val  value: count
        self.deprel_counter={} #key:deprel value: count
        
    def count_cols(self,cols):
        if cols[0].isdigit() or u"." in cols[0]: #word or empty word
            self.word_count+=1
            self.token_count+=1 #every word is also a one-word token
        else: #token
            b,e=cols[0].split(u"-")
            b,e=int(b),int(e)
            self.token_count-=e-b #every word is counted as a token, so subtract all but one to offset for that
        if cols[LEMMA]!=u"_" or (cols[LEMMA]==u"_" and cols[FORM]==u"_"):
            self.words_with_lemma_count+=1
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
            self.words_with_deps_count+=1
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

    def get_stats(self):
        """Returns a dictionary of elementary stats"""
        langspec=sum(1 for deprel in self.deprel_counter.iterkeys() if u":" in deprel)
        ud_rels=len(set(deprel.split(u":")[0] for deprel in self.deprel_counter.iterkeys()))
        d={"tree_count":self.tree_count,"word_count":self.word_count,"token_count":self.token_count,"deprels":len(self.deprel_counter),"langspec_deprels":langspec, "universal_deprels":ud_rels, "postags":sum(1 for cat_is_val in self.f_val_counter if cat_is_val.startswith(u"CPOSTAG=")),"catvals":sum(1 for cat_is_val in self.f_val_counter if not cat_is_val.startswith(u"CPOSTAG=")),"words_with_lemma_count":self.words_with_lemma_count,"words_with_deps_count":self.words_with_deps_count}
        return d
        


    def print_deprels(self,out,which=u"UD+langspec",sort="freq"):
        #which can be UD, langspec
        if sort=="freq":
            key=lambda x:-x[1]
        elif sort=="alph":
            key=lambda x:x[0].lower()
        else:
            print >> sys.stderr, "Unknown sort order: %s. Use --sort=freq or --sort=alph."
            sys.exit(1)
        for deprel,count in sorted(self.deprel_counter.iteritems(),key=key):
            if u":" in deprel and u"langspec" in which:
                print >> out, deprel
            if u":" not in deprel and u"UD" in which:
                print >> out, deprel

    def print_features(self,out,which=u"UD+langspec",sort="freq"):
        #1) get UD features
        ud_cats=set()
        with codecs.open(os.path.join(THISDIR,"data","feats.ud"),"r","utf-8") as f:
            for line in f:
                line=line.strip()
                if not line or line.startswith(u"#"):
                    continue
                ud_cats.add(line)
        if sort=="freq":
            key=lambda x:-x[1]
        elif sort=="alph":
            key=lambda x:x[0].lower()
        else:
            print >> sys.stderr, "Unknown sort order: %s. Use --sort=freq or --sort=alph."
            sys.exit(1)
        for cat_is_val,count in sorted(self.f_val_counter.iteritems(),key=key):
            cat,val=cat_is_val.split(u"=",1)
            if not cat==u"CPOSTAG" and ((u"UD" in which and cat in ud_cats) or (u"langspec" in which and cat not in ud_cats)):
                print >> out, cat_is_val
        
        

if __name__=="__main__":
    opt_parser = argparse.ArgumentParser(description='Script for basic stats generation. Assumes a validated input.')
    opt_parser.add_argument('input', nargs='+', help='Input file name (can be several files), or "-" or nothing for standard input.')
    opt_parser.add_argument('--stats',action='store_true',default=False, help='Print basic stats')
    opt_parser.add_argument('--jsonstats',action='store_true',default=False, help='Print basic stats as json dictionary')
    opt_parser.add_argument('--deprels',default=None,help='Print deprels. The option can be "UD", "langspec", or "UD+langspec".')
    opt_parser.add_argument('--catvals',default=None,help='Print category=value pairs. The option can be "UD", "langspec", or "UD+langspec". This distinction is based on the feature, not the value.')
    opt_parser.add_argument('--sort',default='freq',help='Sort the values by their frequency (freq) or alphabetically (alph). Default: %(default)s.')
    args = opt_parser.parse_args() #Parsed command-line arguments
    args.output="-"
    inp,out=file_util.in_out(args,multiple_files=True)
    trees=file_util.trees(inp)

    stats=Stats()
    try:
        for comments,tree in trees:
            stats.tree_count+=1
            for cols in tree:
                stats.count_cols(cols)
    except:
        traceback.print_exc()
        print >> sys.stderr, "\n\n ------- STATS MAY BE EMPTY OR INCOMPLETE ----------"
        pass
    if args.stats:
        stats.print_basic_stats(out)
    if args.jsonstats:
        d=stats.get_stats()
        print json.dumps(d)
    if args.deprels:
        stats.print_deprels(out,args.deprels,args.sort)
    if args.catvals:
        stats.print_features(out,args.catvals,args.sort)

    


