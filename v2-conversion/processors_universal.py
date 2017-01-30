#!/usr/bin/env python3

import sys


'''
   Conversion processors that should work for most (or maybe even all?) languages.
'''


class UpdateProcessor(object):
    
    def process(self, graph):
        raise NotImplementedException
        

'''
    Renames all occurences of a universal POS tag.
'''

class UPosRenameUpdateProcessor(UpdateProcessor):
    
    def __init__(self, old_upos, new_upos):
        self.old_upos = old_upos
        self.new_upos = new_upos


    def process(self, graph):
        for idx in graph.nodes.keys():
            node = graph.nodes[idx]
            if node.upos == self.old_upos:
                node.upos = self.new_upos

'''
    Renames all occurences of a relation.
'''
class RelnRenameUpdateProcessor(UpdateProcessor):
    
    def __init__(self, old_reln, new_reln):
        self.old_reln = old_reln
        self.new_reln = new_reln


    def process(self, graph):
        
        # Stores changes in the form (old_gov, old_dep).
        # (new_gov and new_dep are the same and old_reln and new_reln are defined as instance
        # variables.)
        edge_changes = []
        
        for edge in graph.edges:
            if edge.relation == self.old_reln:
                edge_changes.append((edge.gov, edge.dep))
                
        for (gov, dep) in edge_changes:
            graph.remove_edge(gov, dep, self.old_reln)
            graph.add_edge(gov, dep, self.new_reln)

'''
    Splits nmod relation into nmod or oblique and marks ambiguous cases.
'''

class NmodUpdateProcessor(UpdateProcessor):
    
    def process(self, graph):
        
        # Stores changes in the form (old_gov, old_dep, old_reln).
        # (new_gov and new_dep are the same and new_reln is always "obl".)
        edge_changes = []
        
        for edge in graph.edges:
            if edge.relation == "nmod":
                gov_node = graph.nodes[edge.gov]
                dep_node = graph.nodes[edge.dep]

                ambiguous = False


                #check whether gov node is a nominal
                # also include NUM for examples such as "one of the guys"
                # and DET for examples such as "some/all of them"
                if gov_node.upos in ["NOUN","PRON", "PROPN", "NUM", "DET"]:
                    #check whether nominal is a predicate (either has a nsubj/csubj dependendent
                    # or a copula dependent)
                    for gov_edge in graph.outgoingedges[gov_node.index]:
                        if gov_edge[1] in ["nsubj", "csubj", "nsubjpass", "csubjpass", "nsubj:pass", "csubj:pass", "cop"]:
                            ambiguous = True
                            break
                
                elif gov_node.upos in ["VERB","AUX", "ADJ", "ADV"]:
                    # Change dependents of predicate to "obl".
                    edge_changes.append((edge.gov, edge.dep, edge.relation))
                
                else:
                    ambiguous = True


                # Don't change the relation but add comment to MISC column for manual check.
                if ambiguous:
                    dep_node.misc = dep_node.misc + "|ManualCheck=Yes" if dep_node.misc != "_" else "ManualCheck=Yes"


            
        for (old_gov, old_dep, old_reln) in edge_changes:            
            graph.remove_edge(old_gov, old_dep, old_reln)
            graph.add_edge(old_gov, old_dep, "obl")


'''
    Reattaches cc and punctuation that is involved in coordination (e.g., commas) to immediately 
    following conjunct.
'''

class CoordinationReattachmentProcessor(UpdateProcessor):
    
    verbose = True
    
    def process(self, graph):
        
            
        # Stores changes in the form (old_gov, old_dep, old_reln, new_gov).
        # (new_dep = old_dep and new_reln = old_reln, so we don't have to store them.)
        gov_changes = []
        
        for edge in graph.edges:
            
            # reattach coordinating conjunctions
            if edge.relation == "cc":
                conjuncts = graph.dependendents_with_reln(edge.gov, "conj")
                conjuncts.sort()
                f = False
                for c in conjuncts:
                    if c > edge.dep:
                        gov_changes.append((edge.gov, edge.dep, edge.relation, c))
                        f = True
                        break
                
                if self.verbose and not f and edge.gov < edge.dep:
                    print("WARNING: No reattachement of cc!", file=sys.stderr)
                    graph.print_conllu(f=sys.stderr)
            
            # reattach punctuation
            elif edge.relation == "punct":
                conjuncts = graph.dependendents_with_reln(edge.gov, "conj")
                
                if len(conjuncts) < 1:
                    continue

                dep_node = graph.nodes[edge.dep]
                
                #TODO: should we also include other punctuation marks? e.g., semicolons?
                if dep_node.lemma not in  [","]:
                    continue
                
                conjuncts.sort()
                
                for c in conjuncts:
                    if c > edge.dep:
                        gov_changes.append((edge.gov, edge.dep, edge.relation, c))
                        break
                
        
        for (old_gov, old_dep, old_reln, new_gov) in gov_changes:
            graph.remove_edge(old_gov, old_dep, old_reln)
            graph.add_edge(new_gov, old_dep, old_reln)
            
