#!/usr/bin/env perl
# Reads a CoNLL-U file, compares the basic tree with the enhanced graph and
# guesses which relation belongs to which enhancement type.
# This script is based on enhanced_graph_properties.pl.
# Copyright © 2021 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use List::MoreUtils qw(any);
use Getopt::Long;
# We need to tell Perl where to find my graph modules.
# If this does not work, you can put the script together with Graph.pm and
# Node.pm in a folder of you choice, say, /home/joe/scripts, and then
# invoke Perl explicitly telling it where the modules are:
# perl -I/home/joe/scripts /home/joe/scripts/enhanced_graph_properties.pl inputfile.conllu
BEGIN
{
    use Cwd;
    my $path = $0;
    $path =~ s:\\:/:g;
    my $currentpath = getcwd();
    $libpath = $currentpath;
    if($path =~ m:/:)
    {
        $path =~ s:/[^/]*$:/:;
        chdir($path);
        $libpath = getcwd();
        chdir($currentpath);
    }
    #print STDERR ("libpath=$libpath\n");
}
use lib $libpath;
use Graph;
use Node;

#GetOptions
#(
#    'report-cycles' => \$report_cycles,
#    'report-basenh' => \$report_basenh
#);

my @sentence;
while(<>)
{
    if(m/^\s*$/)
    {
        process_sentence(@sentence);
        @sentence = ();
    }
    else
    {
        s/\r?\n$//;
        push(@sentence, $_);
    }
}
# In case of incorrect files that lack the last empty line:
if(scalar(@sentence) > 0)
{
    process_sentence(@sentence);
}



#------------------------------------------------------------------------------
# Processes one sentence after it has been read.
#------------------------------------------------------------------------------
sub process_sentence
{
    my @sentence = @_;
    my $graph = Graph::from_conllu_lines(@sentence);
    # Only for enhanced UD graphs:
    find_enhancements($graph);
    print_sentence($graph->to_conllu_lines());
}



#------------------------------------------------------------------------------
# Prints a sentence in the CoNLL-U format to the standard output.
#------------------------------------------------------------------------------
sub print_sentence
{
    my @sentence = @_;
    print(join("\n", @sentence), "\n\n");
}



#==============================================================================
# Statistics specific to the Enhanced Universal Dependencies v2.
# 1. Ellipsis (gapping).
# 2. Coordination (propagation of dependencies to conjuncts).
# 3. Control verbs.
# 4. Relative clauses.
# 5. Case markers added to dependency relation types.
#==============================================================================



#------------------------------------------------------------------------------
# Saves the information that a particular edge is caused by a particular
# enhancement type. By default, we copy DEPS to MISC and extend the syntax so
# that the enhancement type can be stored next to the edge.
#------------------------------------------------------------------------------
# Known types:
# * basic (B) ... this enhanced edge is identical to an edge in the basic tree (including the deprel)
# * cased (C) ... case-enhanced relation (the relation with the shorter label may or may not exist in the basic tree)
# * relabeled (L) ... the same two nodes are also connected in the basic tree but the deprel is different and the difference does not look like a case enhancement
# * gapping (G) ... the parent or the child is an empty node; the edge was added because of gapping
# * orphan (O) ... basic relation missing from enhanced graph because it was replaced by a relation to/from an empty node (the basic edge is not necessarily labeled 'orphan')
# * coparent (P) ... shared parent of coordination, relation propagated to a non-first conjunct
# * codepend (S) ... shared dependent of coordination, relation propagated from a non-first conjunct
# * xsubj (X) ... relation between a controlled predicate and its external subject
# * relcl (R) ... relation between a node in a relative clause and the modified nominal; also the 'ref' relation between the modified nominal and the coreferential relative pronoun
# * relpron (W) ... basic relation incoming to a relative pronoun is missing from enhanced graph because it was replaced by the 'ref' relation
# * missing (M) ... basic relation is missing from the enhanced graph but none of the above reasons has been recognized
# * enhanced (E) ... this enhanced edge does not exist in the basic tree and none of the above reasons has been recognized
# Some types may be combined. For example, there may be an enhanced relation
# that exists because of 'relcl' and 'coparent', and it would disappear if
# either of the enhancement types were not annotated.
my %shortcuts;
BEGIN
{
    %shortcuts =
    (
        'basic'     => 'B',
        'cased'     => 'C',
        'relabeled' => 'L',
        'gapping'   => 'G',
        'orphan'    => 'O',
        'coparent'  => 'P',
        'codepend'  => 'S',
        'xsubj'     => 'X',
        'relcl'     => 'R',
        'relpron'   => 'W',
        'missing'   => 'M',
        'enhanced'  => 'E',
        # only for debugging: these are subtypes of the above
        'relcl-cycle' => 'Y'
    );
}
sub save_edge_type
{
    my $node = shift; # Node object, the child node of the relation
    my $type = shift;
    my $id = shift; # the ID of the parent node
    my $deprel = shift; # the DEPREL (label) of the relation
    if(!exists($shortcuts{$type}))
    {
        die("Unknown edge type '$type'");
    }
    ###!!! We have to deal with the possibility that there are no MISC attributes so far.
    ###!!! Perhaps there could be support for this directly in the Node class.
    my @misc = ();
    my $misc = $node->misc();
    if(!defined($misc))
    {
        $misc = \@misc;
        $node->set_misc($misc);
    }
    # Extract from MISC all previous Edep attributes.
    my @edep = grep {m/^Edep=/} (@{$misc});
    @{$misc} = grep {!m/^Edep=/} (@{$misc});
    my $miscitem = "Edep=$shortcuts{$type}:$id:$deprel";
    push(@edep, $miscitem);
    # Create a hash so that we can recognize repeated annotations of the same relation.
    if(scalar(@edep) > 1)
    {
        my %edep;
        foreach my $edep (@edep)
        {
            if($edep =~ m/^Edep=([A-Z]+):(\d+(?:\.\d+)?):(.+)$/)
            {
                my $t = $1;
                my $i = $2;
                my $d = $3;
                my $key = "$i:$d";
                if(exists($edep{$key}))
                {
                    # If the previous record of the edge contains the current type, do nothing.
                    # If the current type is not there yet, add it and sort the types alphabetically.
                    my $types = $edep{$key};
                    if($types !~ m/$t/)
                    {
                        $edep{$key} = join('', sort {$a cmp $b} ((split(//, $types)), $t));
                    }
                }
                else
                {
                    $edep{$key} = $t;
                }
            }
            else
            {
                die("Unknown edge record '$edep'");
            }
        }
        # Serialize the edeps again in MISC.
        my @keys = sort
        {
            $a =~ m/^(\d+)(?:\.(\d+))?:(.+)$/;
            my $amaj = $1;
            my $amin = $2 // 0;
            my $adep = $3;
            $b =~ m/^(\d+)(?:\.(\d+))?:(.+)$/;
            my $bmaj = $1;
            my $bmin = $2 // 0;
            my $bdep = $3;
            my $r = $amaj <=> $bmaj;
            unless($r)
            {
                $r = $amin <=> $bmin;
                unless($r)
                {
                    $r = $adep cmp $bdep;
                }
            }
            $r
        }
        (keys(%edep));
        @edep = map {"Edep=$edep{$_}:$_"} (@keys);
    }
    push(@{$misc}, @edep);
}



#------------------------------------------------------------------------------
# Returns the type (label) of the relation between parent $p and child $c.
# Returns undef if the two nodes are not connected with an edge. It is assumed
# that there is at most one relation between any two nodes. Although
# technically it is possible to represent multiple relations in the enhanced
# graph, the guidelines do not support it. The nodes $p and $c are identified
# by their ids.
#------------------------------------------------------------------------------
sub relation
{
    my $p = shift;
    my $c = shift;
    my $graph = shift;
    my @oedges = @{$graph->node($p)->oedges()};
    my @matching_children = grep {$_->{id} == $c} (@oedges);
    if(scalar(@matching_children)==0)
    {
        return undef;
    }
    else
    {
        if(scalar(@matching_children)>1)
        {
            print STDERR ("WARNING: Enhanced graph should not connect the same two nodes twice.\n");
        }
        return $matching_children[0]->{deprel};
    }
}



#------------------------------------------------------------------------------
# Figures out whether there is a dependency path from x (ancestor) to y
# (descendant).
#------------------------------------------------------------------------------
sub is_path_from_to
{
    my $graph = shift;
    my $from = shift; # node id
    my $to = shift; # node id
    my $visited = shift; # hash reference, ids of nodes visited so far
    $visited->{$from}++;
    return 1 if($from eq $to);
    my $fnode = $graph->get_node($from);
    my @oedges = @{$fnode->oedges()};
    foreach my $oedge (@oedges)
    {
        unless($visited->{$oedge->{id}})
        {
            my $result = is_path_from_to($graph, $oedge->{id}, $to, $visited);
            return 1 if($result);
        }
    }
    return 0;
}



#------------------------------------------------------------------------------
# Checks whether an edge can have been propagated from a parent of coordination
# to a non-first conjunct.
#------------------------------------------------------------------------------
sub is_coparent
{
    my $iedge = shift; # the incoming edge to be checked
    my $iedges = shift; # array ref: all incoming edges to the current node
    my $graph = shift;
    # Parent propagation in coordination: a node has at least two parents, one of them is conj,
    # the other is not, and the other's parent is identical to a grandparent reachable via the conj parent.
    if($iedge->{deprel} !~ m/^conj(:|$)/)
    {
        # Look for the other route via 'conj'.
        my @candidates = grep {$_->{id} ne $iedge->{id} && $_->{deprel} =~ m/^conj(:|$)/} (@{$iedges});
        foreach my $candidate (@candidates)
        {
            # The candidate is a conj parent. Check its parents (my grandparents).
            # If one of them is also my parent from the $iedge we are checking,
            # then we have an instance of coparent (we might also want to check
            # whether the deprels are identical, or at least somehow compatible).
            if(any {$_->{id} eq $iedge->{id}} (@{$graph->node($candidate->{id})->iedges()}))
            {
                return 1;
            }
        }
    }
    return 0;
}



#------------------------------------------------------------------------------
# Checks whether an edge can have been propagated from a non-first conjunct to
# a shared dependent of coordination.
#------------------------------------------------------------------------------
sub is_codepend
{
    my $iedge = shift; # the incoming edge to be checked
    my $iedges = shift; # array ref: all incoming edges to the current node
    my $graph = shift;
    # Shared dependent in coordination: at least two non-conj parents
    # (typically but not necessarily with same relation going to me),
    # furthermore, the parents are connected with a conj relation.
    if($iedge->{deprel} !~ m/^conj(:|$)/)
    {
        # Look for the other route via 'conj'.
        my @candidates = grep {$_->{id} ne $iedge->{id} && $_->{deprel} !~ m/^conj(:|$)/} (@{$iedges});
        foreach my $candidate (@candidates)
        {
            # The candidate we are looking for will have my other parent as its
            # conj parent (my grandparent).
            if(any {$_->{id} eq $iedge->{id} && $_->{deprel} =~ m/^conj(:|$)/} (@{$graph->node($candidate->{id})->iedges()}))
            {
                return 1;
            }
        }
    }
    return 0;
}



#------------------------------------------------------------------------------
# Checks whether an edge can have been propagated as an external subject of a
# controlled predicate.
#------------------------------------------------------------------------------
sub is_xsubj
{
    my $iedge = shift; # the incoming edge to be checked
    my $iedges = shift; # array ref: all incoming edges to the current node
    my $graph = shift;
    # Subject propagation through xcomp: at least two parents, I am subject
    # or object of one, and subject of the other. The latter parent is xcomp of the former.
    if($iedge->{deprel} =~ m/^[nc]subj(:|$)/)
    {
        # Look for the other route via subject/object/oblique and 'xcomp'.
        my @candidates = grep {$_->{id} ne $iedge->{id} && $_->{deprel} =~ m/^([nc]subj|obj|iobj|obl)(:|$)/} (@{$iedges});
        foreach my $candidate (@candidates)
        {
            # The candidate is my "direct" predicate parent. If it is a control verb,
            # then the other parent (which we are checking) will be its xcomp child.
            if(any {$_->{id} eq $iedge->{id} && $_->{deprel} =~ m/^xcomp(:|$)/} (@{$graph->node($candidate->{id})->oedges()}))
            {
                return 1;
            }
        }
    }
    return 0;
}



#------------------------------------------------------------------------------
# Checks whether an edge can have been propagated from a nominal modified by
# a copular relative clause (where the relative pronoun is the predicate) to
# the subject of the relative clause.
#------------------------------------------------------------------------------
sub is_subj_of_copular_relcl
{
    my $iedge = shift; # the incoming edge to be checked
    my $iedges = shift; # array ref: all incoming edges to the current node
    my $graph = shift;
    # Copular relative clauses where the relative pronoun is the predicate:
    # we have a subject relation from the modified nominal to the subject of the copular clause.
    # It means that the subject node has two incoming subject relations:
    # one from the predicate of the relative clause (i.e. from the pronoun)
    # and the other from the nominal outside the clause that is coreferential with the pronoun.
    if($iedge->{deprel} =~ m/^[nc]subj(:|$)/)
    {
        # Look for the other path via 'nsubj' and 'acl:relcl'.
        my @candidates = grep {$_->{id} ne $iedge->{id} && $_->{deprel} =~ m/^[nc]subj(:|$)/} (@{$iedges});
        foreach my $candidate (@candidates)
        {
            if(any {$_->{id} eq $iedge->{id} && $_->{deprel} =~ m/^acl(:|$)/} (@{$graph->node($candidate->{id})->iedges()}))
            {
                return 1;
            }
        }
    }
    return 0;
}



#------------------------------------------------------------------------------
# Check whether an edge can come from a relative clause to the nominal the
# clause modifies (i.e., there is a cycle).
#------------------------------------------------------------------------------
sub is_relcl_cycle
{
    my $iedge = shift; # the incoming edge to be checked
    my $curnode = shift; # the current node (child of $iedge)
    my $graph = shift;
    # The incoming relation can be many things (nsubj, obj, obl, nmod etc.)
    # but it cannot be conj.
    return 0 if($iedge->{deprel} =~ m/^conj(:|$)/);
    # The current node must be modified by a relative clause. The deprel should
    # be preferably 'acl:relcl' but let's check just 'acl'.
    my @oedges = @{$curnode->oedges()};
    return 0 if(!any {$_->{deprel} =~ m/^acl(:|$)/} (@oedges));
    # There must be a path from the current mode to $iedge->{id}; that make be
    # cycle. The path must lead over the acl(:relcl) child that we just checked
    # that exists. However, we currently do not verify this detail, we only
    # check that a path exists.
    if(is_path_from_to($graph, $curnode->{id}, $iedge->{id}, {}))
    {
        return 1;
    }
    return 0;
}



#------------------------------------------------------------------------------
# Tries to detect various types of enhancements defined in Enhanced UD v2.
#------------------------------------------------------------------------------
sub find_enhancements
{
    my $graph = shift;
    foreach my $curnode ($graph->get_nodes())
    {
        my @iedges = @{$curnode->iedges()};
        my @oedges = @{$curnode->oedges()};
        # Compare the enhanced incoming edges with the basic incoming edge
        # (if any; an empty node does not participate in any basic edge).
        my $biedge;
        unless($curnode->is_empty())
        {
            $biedge = {'id' => $curnode->bparent(), 'deprel' => $curnode->bdeprel()};
        }
        # If we find certain enhanced edges, it will explain why the basic edge is missing from the enhanced graph.
        my $biedge_found = 0;
        my $empty_parent_found = 0;
        my $ref_edge_found = 0;
        foreach my $iedge (@iedges)
        {
            if($biedge)
            {
                # The parent is different from the basic parent, hence this is an edge added in the enhanced graph.
                # Even if the parent is not different but the new label is 'ref', treat it as a new edge (this can happen with copular relative clauses).
                if($biedge->{id} != $iedge->{id} || $iedge->{deprel} =~ m/^ref(:|$)/)
                {
                    my $known_reason = 0;
                    # The parent is different from the basic parent. Is it an empty node?
                    if($iedge->{id} =~ m/\./)
                    {
                        $empty_parent_found = 1;
                        save_edge_type($curnode, 'gapping', $iedge->{id}, $iedge->{deprel});
                        $known_reason = 1;
                    }
                    # Parent propagation in coordination: a node has at least two parents, one of them is conj,
                    # the other is not, and the other's parent is identical to a grandparent reachable via the conj parent.
                    if(is_coparent($iedge, \@iedges, $graph))
                    {
                        save_edge_type($curnode, 'coparent', $iedge->{id}, $iedge->{deprel});
                        $known_reason = 1;
                    }
                    # Is one of my over-conj grandparents also my non-conj parent?
                    if(is_codepend($iedge, \@iedges, $graph))
                    {
                        save_edge_type($curnode, 'codepend', $iedge->{id}, $iedge->{deprel});
                        $known_reason = 1;
                    }
                    # Subject propagation through xcomp: at least two parents, I am subject
                    # or object of one, and subject of the other. The latter parent is xcomp of the former.
                    if(is_xsubj($iedge, \@iedges, $graph))
                    {
                        save_edge_type($curnode, 'xsubj', $iedge->{id}, $iedge->{deprel});
                        $known_reason = 1;
                    }
                    # Relative clauses: the ref relation.
                    if($iedge->{deprel} =~ m/^ref(:|$)/)
                    {
                        $ref_edge_found = 1;
                        save_edge_type($curnode, 'relcl', $iedge->{id}, $iedge->{deprel});
                        $known_reason = 1;
                    }
                    # Relative clauses: a cycle.
                    if(is_relcl_cycle($iedge, $curnode, $graph))
                    {
                        save_edge_type($curnode, 'relcl', $iedge->{id}, $iedge->{deprel});
                        $known_reason = 1;
                    }
                    # Copular relative clauses where the relative pronoun is the predicate: we have a subject relation from the modified nominal to the subject of the copular clause.
                    # It means that the subject node has two incoming subject relations: one from the predicate of the relative clause (i.e. from the pronoun)
                    # and the other from the nominal outside the clause that is coreferential with the pronoun.
                    if(is_subj_of_copular_relcl($iedge, \@iedges, $graph))
                    {
                        save_edge_type($curnode, 'relcl', $iedge->{id}, $iedge->{deprel});
                        $known_reason = 1;
                    }
                    unless($known_reason)
                    {
                        save_edge_type($curnode, 'enhanced', $iedge->{id}, $iedge->{deprel});
                    }
                }
                # The parent is the same node in basic and in enhanced. What about the relation type?
                elsif($biedge->{deprel} eq $iedge->{deprel})
                {
                    save_edge_type($curnode, 'basic', $iedge->{id}, $iedge->{deprel});
                    $biedge_found++;
                }
                else
                {
                    # Edge differs from basic edge in subtype but not in main type, e.g., basic='obl', enhanced='obl:in'.
                    my $budeprel = $biedge->{deprel};
                    $budeprel =~ s/^([^:]+):.*$/$1/;
                    my $eudeprel = $iedge->{deprel};
                    $eudeprel =~ s/^([^:]+):.*$/$1/;
                    if($budeprel eq $eudeprel)
                    {
                        save_edge_type($curnode, 'cased', $iedge->{id}, $iedge->{deprel});
                    }
                    else
                    {
                        save_edge_type($curnode, 'relabeled', $iedge->{id}, $iedge->{deprel});
                    }
                    $biedge_found++;
                    if(0)
                    {
                        # Adpositions and case features in enhanced relations.
                        ###!!! Non-ASCII characters, underscores, or multiple colons in relation labels signal this enhancement.
                        ###!!! However, none of them is a necessary condition. We can have a simple 'obl:between'.
                        ###!!! We would probably have to look at the basic dependency and compare it with the enhanced relation.
                        my @unusual = grep {$_->{deprel} =~ m/(:.*:|[^a-z:])/} (@iedges);
                        if(scalar(@unusual) > 0)
                        {
                            $stats{case_deprel}++;
                        }
                        else
                        {
                            my $basic_parent = $curnode->bparent();
                            my $basic_deprel = $curnode->bdeprel();
                            my @matchingpr = grep {$_->{id} == $basic_parent} (@iedges);
                            my @extendedpr = grep {$_->{deprel} =~ m/^$basic_deprel:.+/} (@matchingpr);
                            if(scalar(@extendedpr) > 0)
                            {
                                $stats{case_deprel}++;
                            }
                        }
                        ###!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                    }
                }
            }
            else # no basic incoming edge => all incoming edges are enhanced-only
            {
                # If there is no basic incoming edge, it normally means that the current node is empty.
                if(!$curnode->is_empty())
                {
                    print STDERR ("WARNING: There is no incoming basic relation but the current node is not empty.\n");
                    save_edge_type($curnode, 'enhanced', $iedge->{id}, $iedge->{deprel});
                }
                else
                {
                    save_edge_type($curnode, 'gapping', $iedge->{id}, $iedge->{deprel});
                }
                # Parent propagation in coordination: a node has at least two parents, one of them is conj,
                # the other is not, and the other's parent is identical to a grandparent reachable via the conj parent.
                if(is_coparent($iedge, \@iedges, $graph))
                {
                    save_edge_type($curnode, 'coparent', $iedge->{id}, $iedge->{deprel});
                }
                # Is one of my over-conj grandparents also my non-conj parent?
                if(is_codepend($iedge, \@iedges, $graph))
                {
                    save_edge_type($curnode, 'codepend', $iedge->{id}, $iedge->{deprel});
                }
                # Subject propagation through xcomp: at least two parents, I am subject
                # or object of one, and subject of the other. The latter parent is xcomp of the former.
                if(is_xsubj($iedge, \@iedges, $graph))
                {
                    save_edge_type($curnode, 'xsubj', $iedge->{id}, $iedge->{deprel});
                }
                # Relative clauses: the ref relation.
                if($iedge->{deprel} =~ m/^ref(:|$)/)
                {
                    $ref_edge_found = 1;
                    save_edge_type($curnode, 'relcl', $iedge->{id}, $iedge->{deprel});
                }
                # Relative clauses: a cycle.
                if(is_relcl_cycle($iedge, $curnode, $graph))
                {
                    save_edge_type($curnode, 'relcl', $iedge->{id}, $iedge->{deprel});
                }
                # Copular relative clauses where the relative pronoun is the predicate: we have a subject relation from the modified nominal to the subject of the copular clause.
                # It means that the subject node has two incoming subject relations: one from the predicate of the relative clause (i.e. from the pronoun)
                # and the other from the nominal outside the clause that is coreferential with the pronoun.
                if(is_subj_of_copular_relcl($iedge, \@iedges, $graph))
                {
                    save_edge_type($curnode, 'relcl', $iedge->{id}, $iedge->{deprel});
                }
            }
        }
        if($biedge && !$biedge_found)
        {
            if($empty_parent_found)
            {
                save_edge_type($curnode, 'orphan', $biedge->{id}, $biedge->{deprel});
            }
            elsif($ref_edge_found)
            {
                save_edge_type($curnode, 'relpron', $biedge->{id}, $biedge->{deprel});
            }
            else
            {
                save_edge_type($curnode, 'missing', $biedge->{id}, $biedge->{deprel});
            }
        }
    }
}
