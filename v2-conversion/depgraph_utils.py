#!/usr/bin/env python3

from collections import defaultdict
import sys


'''
    Utils for reading in UD trees, working with them, and outputting them in CoNLL-U format.
'''


COMMENT_START_CHAR = "#"

class DependencyGraph(object):
    
    def __init__(self, lines=None):
        
        
        root_node = DependencyGraphNode(0, "ROOT") 
        
        self.nodes = {0: root_node}
        self.edges = set()
        self.outgoingedges = defaultdict(set)
        self.incomingedges = defaultdict(set)
        self.comments = []
        
        
        if lines != None:
            self._parse_conllu(lines)
    
    
    def _parse_conllu(self, lines):
        
        #extract nodes
        for line in lines:
            line = line.strip()
            if line.startswith(COMMENT_START_CHAR):
                self.comments.append(line)
                continue
                
            idx, form, lemma, upos, pos, feats, _, _, deps, misc = line.split("\t")
            idx = int(idx)
            node = DependencyGraphNode(idx, form, lemma=lemma, upos=upos, pos=pos, 
                                      features=feats, misc=misc, enhanced=deps)
            self.nodes[idx] = node
        
        #extract edges
        for line in lines:
            line = line.strip()
            if line.startswith(COMMENT_START_CHAR):
                continue
            
            #TODO: support enhanced dependencies
            idx, _, _, _, _, _, gov, reln, _, _ = line.split("\t")
            idx = int(idx)
            gov = int(gov)
            self.add_edge(gov, idx, reln)
         
    def get_gov(self, dep):
        gov_edges = self.incomingedges[dep]
        if len(gov_edges) < 1:
            raise RuntimeError
        for edge in gov_edges:
            gov, reln = edge
            return gov
        
         
    def add_edge(self, gov, dep, reln):
        edge = DependencyGraphEdge(gov, dep, reln)
        self.edges.add(edge)
        self.outgoingedges[gov].add((dep, reln))
        self.incomingedges[dep].add((gov, reln))
        
    def remove_edge(self, gov, dep, reln=None):
        if reln == None:
            to_remove = set()
            for edge in self.edges:
                if edge.gov == gov and edge.dep == dep:
                    to_remove.add(edge)
                self.outgoingedges[gov].remove((dep, edge.relation))
                self.incomingedges[dep].remove((gov, edge.relation))
            self.edges.difference_update(to_remove)
        else:
            edge = DependencyGraphEdge(gov, dep, reln)
            self.edges.remove(edge)
            self.outgoingedges[gov].remove((dep, reln))
            self.incomingedges[dep].remove((gov, reln))
        
    def has_edge(self, gov, dep, reln=None):
        if reln == None:
            for edge in self.edges:
                if edge.gov == gov and edge.dep == dep:
                    return True
        else:
            edge = DependencyGraphEdge(gov, dep, reln)
            return edge in self.edges
    
    
    '''
        Returns a list of node indices which are attached to gov via reln.
    '''
    def dependendents_with_reln(self, gov, reln):
        results = []
        for (dep, reln2) in self.outgoingedges[gov]:
            if reln == reln2:
                results.append(dep)
        return results;
                    
            
                
    
    def print_conllu(self, f=sys.stdout):
          for comment in self.comments:
              print(comment, file=f)
          
          for idx in sorted(self.nodes.keys()):
              node = self.nodes[idx]
              if idx > 0:
                  parents = self.incomingedges[node.index]
                  gov, reln = next(iter(parents)) if len(parents) > 0 else (-1, "null")
                  print("%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s" % (node.index,
                                                                      node.form,
                                                                      node.lemma,
                                                                      node.upos,
                                                                      node.pos,
                                                                      node.features,
                                                                      gov,
                                                                      reln,
                                                                      node.enhanced,
                                                                      node.misc), file=f)
              
          print(file=f)
        
        
        
class DependencyGraphNode(object):
    
    def __init__(self, index, form, lemma=None, upos=None, pos=None, features=None, enhanced=None, misc=None):
        self.index = index
        self.form = form
        self.lemma = lemma
        self.upos = upos
        self.pos = pos
        self.features = features
        self.misc = misc
        self.enhanced = enhanced 
    
    def __hash__(self):
        return self.index.__hash__() + \
                 self.form.__hash__() + \
                 self.lemma.__hash__() + \
                 self.upos.__hash__() + \
                 self.pos.__hash__() + \
                 self.features.__hash__() + \
                 self.misc.__hash__()
    
    def __eq__(self, other):
        return self.index == other.index and \
                 self.form == other.form and \
                 self.lemma == other.lemma and \
                 self.upos == other.upos and \
                 self.pos == other.pos and \
                 self.features == other.features and \
                 self.misc == other.misc
    
    def __str__(self):
        return self.form + "-" + str(self.index)
           
        
        
class DependencyGraphEdge(object):
    
    def __init__(self, gov, dep, relation):
        self.gov = gov
        self.dep = dep
        self.relation = relation
    
    def __hash__(self):
        return self.gov.__hash__() + self.dep.__hash__() + self.relation.__hash__()
        
    def __eq__(self, other):
        return self.gov == other.gov and self.dep == other.dep and self.relation == other.relation
        
