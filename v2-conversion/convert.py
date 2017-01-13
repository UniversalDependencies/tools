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
from processors_universal import *
from processors_en import *


######################################################################################
# Processors                                                                         #
#                                                                                    #
# Each processor in this list is applied to each UD graph in turn.                   #
# Processors are defined in processors_universal.py and processors_lang              #
#                                                                                    #
# If you implement treebank-specific processors, make sure to add them to this list. #
######################################################################################

processors = [UPosRenameUpdateProcessor("CONJ", "CCONJ"),
              RelnRenameUpdateProcessor("mwe", "fixed"),
              RelnRenameUpdateProcessor("dobj", "obj"),
              RelnRenameUpdateProcessor("nsubjpass", "nsubj:pass"),
              RelnRenameUpdateProcessor("csubjpass", "csubj:pass"),
              RelnRenameUpdateProcessor("auxpass", "aux:pass"),
              RelnRenameUpdateProcessor("name", "flat"),
              NmodUpdateProcessor(),
              CoordinationReattachmentProcessor(),
              NegationProcessor()
              ]


def main():
    
    parser = argparse.ArgumentParser(description='Convert a CoNLL-U formatted UD treebank from v1 to v2.')
    parser.add_argument('filename', metavar='FILENAME', type=str, help='Path to CoNLL-U file.')
    args = parser.parse_args()
    
    
    
    f = open(args.filename, "r")
    lines = []
    for line in f:
        if line.strip() == "":
            if len(lines) > 0:
                graph = DependencyGraph(lines=lines)
                for processor in processors:
                    processor.process(graph)
                graph.print_conllu()
            lines = []
        else:
            lines.append(line)
    

if __name__ == '__main__':
    main()
