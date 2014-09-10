#! /usr/bin/python
import sys
import codecs
import argparse
import os.path

#Constants for the column indices
ID,FORM,LEMMA,CPOSTAG,POSTAG,FEATS,HEAD,DEPREL,DEPS,MISC=range(10)

if __name__=="__main__":
    opt_parser = argparse.ArgumentParser(description='CoNLL-U validation script')
    opt_parser.add_argument('--ie', default="utf-8", help='Input encoding. Default: %(default)s')
    opt_parser.add_argument('--oe', default="utf-8", help='Output encoding. Default: %(default)s')
    opt_parser.add_argument('input', nargs='?', help='Input file name, or "-" or nothing for standard input.')
    args = opt_parser.parse_args() #Parsed command-line arguments

    #Decide where to get the data from
    if args.input is None or args.input=="-": #Stdin
        inp=codecs.getreader(args.ie)(sys.stdin)
    else: #File name given
        inp=codecs.open(args.input,"r",args.ie)
    #inp is now an iterator over lines, giving unicode strings
