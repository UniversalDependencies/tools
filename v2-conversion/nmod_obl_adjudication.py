#!/usr/bin/env python3


######################################################################################
#                                                                                    #
# This script converts a CoNLL-U formatted treebank which was annotated according to #
# the v1 guidelines to be compatible with the v2 guidelines.                         #
#                                                                                    #
# Limitations:                                                                       #
#                                                                                    #
# * This script does NOT update gapped constructions with remnant relations. This    #
#   has to be done manually.                                                         #
# * This script does NOT add enhanced dependencies and it does not update the        #
#   contents of the DEPS field.                                                      #
# * In some cases, it is ambiguous whether an nmod relation should be nmod or obl in #
#   v2. If this is the case, the script adds the property ManualCheck=Yes to the     #
#   MISC column of the relation.                                                     #
# * The script does NOT rename, add, or remove any morphological features.           #
#                                                                                    #
# Author: Sebastian Schuster (sebschu@stanford.edu)                                  #
#                                                                                    #
######################################################################################


import sys
import argparse

from depgraph_utils import *


def adjudicate_nmod_obl(graph):
    
    ambiguous_nodes = []
    
    for idx in graph.nodes.keys():
        node = graph.nodes[idx]
        if node.misc != None and "ManualCheck=Yes" in node.misc:
            ambiguous_nodes.append(idx)
    
    if len(ambiguous_nodes) < 1:
        return
    
    graph.print_conllu(f=sys.stderr)
    
    for dep in ambiguous_nodes:
        gov = graph.get_gov(dep)
        node = graph.nodes[dep]
        decision = None
        while decision != "1" and decision !="2":
            decision = input("Should %d-%s be an nmod (1) or obl (2):\n" % (node.index, node.form))
        
        if node.misc == "ManualCheck=Yes":
            node.misc = "_"
        else:
            node.misc = node.misc.replace("|ManualCheck=Yes", "")
        
        if decision == "2":
            graph.remove_edge(gov, dep, "nmod")
            graph.add_edge(gov, dep, "obl")
        #otherwise, don't do anything, already an nmod
        
    
    



def main():
    
    parser = argparse.ArgumentParser(description='Convert a CoNLL-U formatted UD treebank from v1 to v2.')
    parser.add_argument('filename', metavar='FILENAME', type=str, help='Path to CoNLL-U file.')
    parser.add_argument('out_filename', metavar='FILENAME', type=str, help='Path to output CoNLL-U file.')
    
    args = parser.parse_args()
    
    
    
    f = open(args.filename, "r")
    f_out = open(args.out_filename, "w")
    
    
    
    lines = []
    for line in f:
        if line.strip() == "":
            if len(lines) > 0:
                graph = DependencyGraph(lines=lines)
                adjudicate_nmod_obl(graph)
                graph.print_conllu(f=f_out)
            lines = []
        else:
            lines.append(line)
    

if __name__ == '__main__':
    main()
