#! /usr/bin/python
import sys
import codecs
import argparse
import os.path
import logging

#Constants for the column indices
COLCOUNT=10
ID,FORM,LEMMA,CPOSTAG,POSTAG,FEATS,HEAD,DEPREL,DEPS,MISC=range(COLCOUNT)

def warn(msg):
    print msg #TODO: encoding

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
        

def validate(inp):
    for comments,lines in trees(inp):
        pass

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
    validate(inp)
