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
        'enhanced'  => 'E'
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
    my $miscitem = "Edep=$shortcuts{$type}:$id:$deprel";
    push(@{$misc}, $miscitem);
    ###!!! Archive: In enhanced_graph_properties, we also collected the following statistics:
    if(0)
    {
        # enhanced and all other types that are enhanced only edges
        $stats{edge_enhanced_only}++;
        if($report_basenh)
        {
            $stats{basenh}{"edge enhanced only: $iedge->{deprel}"}++;
        }
                # The parent is the same node in basic and in enhanced. What about the relation type?
                    $stats{edge_both_basic_and_enhanced}++;
                    # cased
                        $stats{edge_basic_parent_enhanced_type}++;
                        # relabeled
                        $stats{edge_basic_parent_incompatible_type}++;
                    if($report_basenh)
                    {
                        $stats{basenh}{"edge enhanced type: $biedge->{deprel} --> $iedge->{deprel}"}++;
                    }
                $stats{edge_enhanced_only}++;
                if($report_basenh)
                {
                    $stats{basenh}{"edge enhanced only: $iedge->{deprel}"}++;
                }
            $stats{edge_basic_only}++;
            if($report_basenh)
            {
                # If we want to find the corpus position and investigate whether the annotation is correct,
                # we may need to know the concrete constellation including parent ids.
                my $edeps = $curnode->get_deps_string();
                my $details;
                if($edeps =~ m/^\d+(\.\d+)?:ref$/)
                {
                    $details = "$biedge->{deprel}   ref";
                }
                elsif($edeps =~ m/^\d+\.\d+:([a-z:]+)$/)
                {
                    $details = "1 $biedge->{deprel}   1.1:$1";
                }
                else
                {
                    $details = "$biedge->{id} $biedge->{deprel}   $edeps";
                }
                $stats{basenh}{"edge basic only: $biedge->{deprel} [$details]"}++;
            }
            # coparent
            $stats{conj_effective_parent}++;
            # codepend found
            if($found)
            {
                $stats{conj_shared_dependent}++;
            }
            # xsubj
        if(scalar(@coreprxgpr) > 0)
        {
            $stats{xsubj}++;
        }
        # relcl
                if(scalar(@refpr) > 0)
                {
                    $stats{relcl}++;
                }
    }
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
# Tries to detect various types of enhancements defined in Enhanced UD v2.
#------------------------------------------------------------------------------
sub find_enhancements
{
    my $graph = shift;
    foreach my $curnode ($graph->get_nodes())
    {
        my @iedges = @{$curnode->iedges()};
        my @oedges = @{$curnode->oedges()};
        # Parent propagation in coordination: 'conj' (always?) accompanied by another relation.
        # Shared child propagation: node has at least two parents, one of them is 'conj' of the other.
        my $coparent = 0;
        if(scalar(@iedges) >= 2 &&
           scalar(grep {$_->{deprel} =~ m/^conj(:|$)/} (@iedges)) > 0 &&
           scalar(grep {$_->{deprel} !~ m/^conj(:|$)/} (@iedges)) > 0)
        {
            $coparent = 1;
        }
        my %gpconj;
        if(scalar(@iedges) >= 2)
        {
            # Find grandparents such that their relation to the parent is 'conj' and my relation to the parent is not 'conj'.
            # Later we will ask whether one of those grandparents is also my non-conj parent.
            foreach my $iedge (@iedges)
            {
                if($iedge->{deprel} !~ m/^conj(:|$)/)
                {
                    my @gpedges = @{$graph->node($iedge->{id})->iedges()};
                    foreach my $gpedge (@gpedges)
                    {
                        if($gpedge->{deprel} =~ m/^conj(:|$)/)
                        {
                            $gpconj{$gpedge->{id}}++;
                        }
                    }
                }
            }
        }
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
                if($biedge->{id} != $iedge->{id})
                {
                    my $known_reason = 0;
                    # The parent is different from the basic parent. Is it an empty node?
                    if($iedge->{id} =~ m/\./)
                    {
                        $empty_parent_found = 1;
                        save_edge_type($curnode, 'gapping', $iedge->{id}, $iedge->{deprel});
                        $known_reason = 1;
                    }
                    if($coparent && $iedge->{deprel} !~ m/^conj(:|$)/)
                    {
                        save_edge_type($curnode, 'coparent', $iedge->{id}, $iedge->{deprel});
                        $known_reason = 1;
                    }
                    # Is one of my over-conj grandparents also my non-conj parent?
                    if($iedge->{deprel} !~ m/^conj(:|$)/ && exists($gpconj{$iedge->{id}}))
                    {
                        save_edge_type($curnode, 'codepend', $iedge->{id}, $iedge->{deprel});
                        $known_reason = 1;
                    }
                    # Subject propagation through xcomp: at least two parents, I am subject
                    # or object of one, and subject of the other. The latter parent is xcomp of the former.
                    if($iedge->{deprel} =~ m/^[nc]subj(:|$)/)
                    {
                        my @parent_iedges = @{$graph->node($iedge->{id})->iedges()};
                        foreach my $priedge (@parent_iedges)
                        {
                            if($priedge->{deprel} =~ m/^xcomp(:|$)/)
                            {
                                # $priedge->{id} is my grandparent over nsubj and xcomp (hence it is probably a control verb).
                                # Is it at the same time my parent over a core arg or oblique relation?
                                my $r = relation($priedge->{id}, $curnode->{id}, $graph);
                                if(defined($r) && $r =~ m/^([nc]subj|obj|iobj|obl)(:|$)/)
                                {
                                    # I am the external subject of the xcomp predicate, and a subject or object of the control verb.
                                    save_edge_type($curnode, 'xsubj', $iedge->{id}, $iedge->{deprel});
                                    $known_reason = 1;
                                    last;
                                }
                            }
                        }
                    }
                    # Relative clauses: the ref relation.
                    if($iedge->{deprel} =~ m/^ref(:|$)/)
                    {
                        $ref_edge_found = 1;
                        save_edge_type($curnode, 'relcl', $iedge->{id}, $iedge->{deprel});
                        $known_reason = 1;
                    }
                    # Relative clauses: a cycle (we should also check whether it contains acl:relcl but currently we don't).
                    if(is_path_from_to($graph, $curnode->{id}, $iedge->{id}, {}))
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
                if($coparent && $iedge->{deprel} !~ m/^conj(:|$)/)
                {
                    save_edge_type($curnode, 'coparent', $iedge->{id}, $iedge->{deprel});
                }
                # Is one of my over-conj grandparents also my non-conj parent?
                if($iedge->{deprel} !~ m/^conj(:|$)/ && exists($gpconj{$iedge->{id}}))
                {
                    save_edge_type($curnode, 'codepend', $iedge->{id}, $iedge->{deprel});
                }
                # Subject propagation through xcomp: at least two parents, I am subject
                # or object of one, and subject of the other. The latter parent is xcomp of the former.
                if($iedge->{deprel} =~ m/^[nc]subj(:|$)/)
                {
                    my @parent_iedges = @{$graph->node($iedge->{id})->iedges()};
                    foreach my $priedge (@parent_iedges)
                    {
                        if($priedge->{deprel} =~ m/^xcomp(:|$)/)
                        {
                            # $priedge->{id} is my grandparent over nsubj and xcomp (hence it is probably a control verb).
                            # Is it at the same time my parent over a core arg or oblique relation?
                            my $r = relation($priedge->{id}, $curnode->{id}, $graph);
                            if(defined($r) && $r =~ m/^([nc]subj|obj|iobj|obl)(:|$)/)
                            {
                                # I am the external subject of the xcomp predicate, and a subject or object of the control verb.
                                save_edge_type($curnode, 'xsubj', $iedge->{id}, $iedge->{deprel});
                                last;
                            }
                        }
                    }
                }
                # Relative clauses: the ref relation.
                if($iedge->{deprel} =~ m/^ref(:|$)/)
                {
                    $ref_edge_found = 1;
                    save_edge_type($curnode, 'relcl', $iedge->{id}, $iedge->{deprel});
                }
                # Relative clauses: a cycle (we should also check whether it contains acl:relcl but currently we don't).
                if(is_path_from_to($graph, $curnode->{id}, $iedge->{id}, {}))
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
