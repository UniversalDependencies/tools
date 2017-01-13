#!/usr/bin/env python3

import sys

from processors_universal import *

'''
    Turns deprecated "neg" relation into "det" or "advmod" relation, depending on its syntactic
    function (as determined by the POS tag of the negating token).
'''
class NegationProcessor(UpdateProcessor):
    
    def process(self, graph):

        # Stores changes in the form (old_gov, old_dep, old_reln, new_reln).
        # (new_gov = old_gov and new_dep = old_dep, so we don't have to store them.)
        reln_changes = []
        
        for edge in graph.edges:
            if edge.relation == "neg":
                dep = graph.nodes[edge.dep]
                if dep.upos in ['ADV', 'PART']:
                    reln_changes.append((edge.gov, edge.dep, "neg", "advmod"))
                elif dep.upos == "DET":
                    reln_changes.append((edge.gov, edge.dep, "neg", "det"))
                else:
                    print("WARNING: Dependent of neg relation is neither ADV, PART, nor DET." +
                          "You'll have to manually update the relation.", file=sys.stderr)
                    graph.print_conllu(f=sys.stderr)
         
        for (gov, dep, old_reln, new_reln) in reln_changes:
            graph.remove_edge(gov, dep, old_reln)
            graph.add_edge(gov, dep, new_reln)
            
                    