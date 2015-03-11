import sys
import re
import file_util
from file_util import ID,HEAD,DEPS #column index for the columns we'll need
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
            self.token_count-=e-b #every word is counted as a token, so subtract all but one
    
    def print_basic_stats(self,out):
        print >> out, "Tree count: ", self.tree_count
        print >> out, "Word count: ", self.word_count
        print >> out, "Token count:", self.token_count
        

if __name__=="__main__":
    opt_parser = argparse.ArgumentParser(description='Script for basic stats generation. Assumes a validated input.')
    opt_parser.add_argument('input', nargs='?', help='Input file name, or "-" or nothing for standard input.')
    args = opt_parser.parse_args() #Parsed command-line arguments
    args.output="-"
    inp,out=file_util.in_out(args)

    stats=Stats()
    for comments,tree in file_util.trees(inp):
        stats.tree_count+=1
        for cols in tree:
            stats.count_cols(cols)

    stats.print_basic_stats(out)


