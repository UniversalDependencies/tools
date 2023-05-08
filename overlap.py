#!/usr/bin/env python3

import os
import argparse
import file_util
import sys
import io
import re

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
ID, FORM = 0, 1

def sent_set(inp):
    sents = {} # key: sentence text; value: count
    for comment, lines in file_util.trees(inp):
        txt = ' '.join(line[FORM] for line in lines if line[ID].isdigit())
        # Some corpora have underscores instead of the word forms because of
        # license issues. Avoid comparing and reporting sequences of underscores.
        if re.match(r'^_( _)*$', txt):
            continue
        sents[txt] = sents.get(txt, 0) + 1
    return sents

fname_re = re.compile(r"([a-z_]+)-ud-(train|dev|test(-[a-z])?)\.conllu")
def get_test_pairs(args, names):
    if args.raw:
        return [(i1, i2) for i1 in range(len(names)) for i2 in range(i1 + 1, len(names))]
    pairs=[]
    for i1, f1 in enumerate(names):
        m1 = fname_re.match(os.path.basename(f1))
        if not m1:
            continue
        for i2, f2 in enumerate(names):
            if i2<=i1:
                continue
            m2 = fname_re.match(os.path.basename(f2))
            if not m2:
                continue
            if m1.group(2) == m2.group(2):
                continue
            pairs.append((i1,i2))
    return pairs

if __name__=="__main__":
    opt_parser = argparse.ArgumentParser(description="CoNLL-U overlap detection script. Takes a bunch of UD files and checks them against each other for overlap.")
    opt_parser.add_argument('--raw', default=False, action='store_true', help="Check all-against-all. By default we assume that the list of files given are UD treebanks. The default is to only check files with standard names, and avoid testing train vs. train etc.")
    opt_parser.add_argument('input', nargs='+', help='Input file names to cross-check.')
    args = opt_parser.parse_args()
    sents=[]
    names=[]
    for f_name in args.input:
        if not os.path.exists(f_name):
            continue
        with open(f_name, 'r', encoding='utf-8') as f:
            sents.append(sent_set(f))
            names.append(f_name)
    for i1, i2 in get_test_pairs(args, names):
        o = set(sents[i1].keys()) & set(sents[i2].keys())
        no = len(o)
        print("Overlap:%d\tS1:%s\tS2:%s" % (no, names[i1], names[i2]))
        if no > 0:
            print('-' * 25)
            for s in sorted(o):
                print('   ', s)
