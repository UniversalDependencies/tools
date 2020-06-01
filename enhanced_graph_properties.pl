#!/usr/bin/env perl
# Reads the graph in the DEPS column of a CoNLL-U file and tests it on various graph properties.
# Copyright © 2019 Dan Zeman <zeman@ufal.mff.cuni.cz>
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
    my $currentpath = getcwd();
    $currentpath =~ s/\r?\n$//;
    $libpath = $currentpath;
    if($path =~ m:/:)
    {
        $path =~ s:/[^/]*$:/:;
        chdir($path);
        $libpath = getcwd();
        chdir($currentpath);
    }
    $libpath =~ s/\r?\n$//;
    #print STDERR ("libpath=$libpath\n");
}
use lib $libpath;
use Graph;
use Node;

my $report_cycles = 0; # report each sentence where a cycle is found?
my $report_basenh = 0; # report each type of discrepancy between the basic tree and the enhanced graph?
GetOptions
(
    'report-cycles' => \$report_cycles,
    'report-basenh' => \$report_basenh
);

my %stats =
(
    'n_graphs'  => 0,
    'n_nodes'   => 0,
    'n_empty_nodes' => 0,
    'n_overt_nodes' => 0,
    'n_edges'   => 0,
    'n_single'  => 0,
    'n_in2plus' => 0,
    'n_top1'    => 0,
    'n_top2'    => 0,
    'n_indep'   => 0,
    'n_cyclic_graphs'      => 0,
    'n_unconnected_graphs' => 0,
    'edge_basic_only'                     => 0,
    'edge_both_basic_and_enhanced'        => 0,
    'edge_basic_parent_enhanced_type'     => 0,
    'edge_basic_parent_incompatible_type' => 0,
    'edge_enhanced_only'                  => 0,
    'gapping'               => 0,
    'conj_effective_parent' => 0,
    'conj_shared_dependent' => 0,
    'xsubj'                 => 0,
    'relcl'                 => 0,
    'case_deprel'           => 0
);
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
# Print the statistics.
print("$stats{n_graphs} graphs\n");
print("$stats{n_nodes} nodes\n");
print("  $stats{n_overt_nodes} overt surface nodes\n");
print("  $stats{n_empty_nodes} empty nodes\n");
if(exists($stats{graphs_with_n_empty_nodes}))
{
    my @counts = sort {$a <=> $b} (keys(%{$stats{graphs_with_n_empty_nodes}}));
    if(scalar(@counts)>1 || scalar(@counts)==1 && $counts[0]!=0)
    {
        foreach my $count (@counts)
        {
            print("    $stats{graphs_with_n_empty_nodes}{$count} graphs with $count empty nodes\n");
        }
    }
}
print("$stats{n_edges} edges (not counting dependencies on 0)\n");
print("$stats{n_single} singletons\n");
print("$stats{n_in2plus} nodes with in-degree greater than 1\n");
print("$stats{n_top1} top nodes only depending on 0\n");
print("$stats{n_top2} top nodes with in-degree greater than 1\n");
print("$stats{n_indep} independent non-top nodes (zero in, nonzero out)\n");
print("$stats{n_cyclic_graphs} graphs that contain at least one cycle\n");
print("$stats{n_unconnected_graphs} graphs with multiple non-singleton components\n");
print("Enhancements defined in Enhanced Universal Dependencies v2 (number of observed signals that the enhancement is applied):\n");
print("* Edge basic only:        $stats{edge_basic_only}\n");
print("* Edge basic & enhanced:  $stats{edge_both_basic_and_enhanced}\n");
print("* Edge enhanced type:     $stats{edge_basic_parent_enhanced_type}\n");
print("* Edge incompatible type: $stats{edge_basic_parent_incompatible_type}\n");
print("* Edge enhanced only:     $stats{edge_enhanced_only}\n");
print("* Gapping:                $stats{gapping}\n");
print("* Coord shared parent:    $stats{conj_effective_parent}\n");
print("* Coord shared depend:    $stats{conj_shared_dependent}\n");
print("* Controlled subject:     $stats{xsubj}\n");
print("* Relative clause:        $stats{relcl}\n");
print("* Deprel with case:       $stats{case_deprel}\n");
if($report_basenh)
{
    print("\n");
    my @keys = sort(keys(%{$stats{basenh}}));
    foreach my $key (@keys)
    {
        print("$stats{basenh}{$key}\t$key\n");
    }
}



#------------------------------------------------------------------------------
# Processes one sentence after it has been read.
#------------------------------------------------------------------------------
sub process_sentence
{
    my @sentence = @_;
    my $graph = Graph::from_conllu_lines(@sentence);
    # We now have a complete representation of the graph and can run various
    # functions that will examine it and collect statistics about it.
    find_singletons($graph);
    #print_sentence(@sentence) if(find_cycles(@nodes));
    find_cycles($graph);
    #print_sentence(@sentence) if(find_components(@nodes));
    find_components($graph);
    # Only for enhanced UD graphs:
    find_enhancements($graph);
}



#------------------------------------------------------------------------------
# Prints a sentence in the CoNLL-U format to the standard output.
#------------------------------------------------------------------------------
sub print_sentence
{
    my @sentence = @_;
    print(join("\n", @sentence), "\n\n");
}



#------------------------------------------------------------------------------
# Finds singletons, i.e., nodes that have no incoming or outgoing edges. Also
# finds various other special types of nodes.
#------------------------------------------------------------------------------
sub find_singletons
{
    my $graph = shift;
    # Remember the total number of graphs.
    $stats{n_graphs}++;
    foreach my $node ($graph->get_nodes())
    {
        # Remember the total number of nodes.
        $stats{n_nodes}++;
        if($node->id() =~ m/\./)
        {
            $stats{n_empty_nodes}++;
        }
        else
        {
            $stats{n_overt_nodes}++;
        }
        my $indegree = $node->get_in_degree();
        my $outdegree = $node->get_out_degree();
        # Count edges except the '0:root' edge.
        $stats{n_edges} += $outdegree;
        if($indegree==0 && $outdegree==0)
        {
            $stats{n_single}++;
        }
        elsif($indegree==0 && $outdegree >= 1)
        {
            # This node is not marked as "top node" because then it would have
            # the incoming edge '0:root' and its in-degree would be 1.
            $stats{n_indep}++;
        }
        elsif($indegree==1 && $node->iedges()->[0]{id} == 0)
        {
            $stats{n_top1}++;
        }
        elsif($indegree > 1)
        {
            $stats{n_in2plus}++;
            if(any {$_->{id}==0} (@{$node->iedges()}))
            {
                $stats{n_top2}++;
            }
        }
    }
}



#------------------------------------------------------------------------------
# Finds directed cycles. Does not try to count all cycles; stops after finding
# the first cycle in the graph.
#------------------------------------------------------------------------------
sub find_cycles
{
    my $graph = shift;
    # @queue is the list of unprocessed partial paths. In the beginning, there
    # is one path for every node of the graph, and the path initially contains
    # only that node.
    my @stack = map {[$_]} ($graph->get_nodes());
    my %processed_node_ids;
    while(my $curpath = pop(@stack))
    {
        # @curpath is the array of nodes that are in the current path.
        # Adding a node that is already in the path would mean that the path contains a cycle.
        my @curpath = @{$curpath};
        # $curnode is the last node of the current path. We will process all its children.
        my $curnode = $curpath[-1];
        # Do not process the node if it has been processed previously.
        unless(exists($processed_node_ids{$curnode->id()}))
        {
            my @curidpath = map {$_->id()} (@curpath);
            #print STDERR ("Processing path ", join(',', @curidpath), "\n");
            # Find all children of the last node in the current path. For each of them
            # create an extension of the current path and add it to the queue of paths.
            my @oedges = @{$curnode->oedges()};
            foreach my $oedge (@oedges)
            {
                my $childnode = $graph->node($oedge->{id});
                my $childid = $childnode->id();
                if(grep {$_==$childid} (@curidpath))
                {
                    $stats{n_cyclic_graphs}++;
                    if($report_cycles) # global option
                    {
                        print("Found a cycle in this sentence:\n");
                        my @comments = @{$graph->comments()};
                        foreach my $comment (@comments)
                        {
                            print("$comment\n");
                        }
                        my @cycle = map {$_->id().':'.$_->form()} (@curpath, $childnode);
                        # The current path may start outside the cycle, so remove the irrelevant prefix.
                        shift(@cycle) while($cycle[0] ne $cycle[-1]);
                        print("The cycle: ".join(' ', @cycle)."\n");
                        print("\n");
                    }
                    return 1;
                }
                my @extpath = @curpath;
                push(@extpath, $childnode);
                push(@stack, \@extpath);
            }
            # $curnode has been processed.
            # We do not have to process it again if we arrive at it via another path.
            # We will not miss a cycle that goes through that $curnode.
            # Note: We could not do this if we used a queue instead of a stack!
            $processed_node_ids{$curnode->id()}++;
        }
    }
}



#------------------------------------------------------------------------------
# Finds non-singleton components, i.e., whether the graph is connected.
#------------------------------------------------------------------------------
sub find_components
{
    my $graph = shift;
    my %component_node_ids;
    my $component_size = 0;
    foreach my $node ($graph->get_nodes())
    {
        my $indegree = $node->get_in_degree();
        my $outdegree = $node->get_out_degree();
        # Ignore singletons.
        unless($indegree+$outdegree==0)
        {
            # Did we find a non-singleton component previously?
            if($component_size==0)
            {
                # Collect all nodes in the current component.
                my @nodes_to_process = ($node);
                my %processed_node_ids;
                while(my $curnode = pop(@nodes_to_process))
                {
                    next if(exists($processed_node_ids{$curnode->id()}));
                    foreach my $iedge (@{$curnode->iedges()})
                    {
                        unless($iedge->{id}==0 || exists($processed_node_ids{$iedge->{id}}))
                        {
                            push(@nodes_to_process, $graph->node($iedge->{id}));
                        }
                    }
                    foreach my $oedge (@{$curnode->oedges()})
                    {
                        unless(exists($processed_node_ids{$oedge->{id}}))
                        {
                            push(@nodes_to_process, $graph->node($oedge->{id}));
                        }
                    }
                    $processed_node_ids{$curnode->id()}++;
                }
                %component_node_ids = %processed_node_ids;
                $component_size = scalar(keys(%component_node_ids));
            }
            # If there is already a component, any subsequent non-singleton node
            # is either part of it or of some other component. The only thing
            # we are interested in is to see whether there is a second component.
            else
            {
                if(!exists($component_node_ids{$node->id()}))
                {
                    $stats{n_unconnected_graphs}++;
                    return 1;
                }
            }
        }
    }
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
# Tries to detect various types of enhancements defined in Enhanced UD v2.
#------------------------------------------------------------------------------
sub find_enhancements
{
    my $graph = shift;
    my $n_empty_nodes_in_this_graph = 0;
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
        my $biedge_found = 0;
        foreach my $iedge (@iedges)
        {
            if($biedge)
            {
                if($biedge->{id} != $iedge->{id})
                {
                    $stats{edge_enhanced_only}++;
                    if($report_basenh)
                    {
                        $stats{basenh}{"edge enhanced only: $iedge->{deprel}"}++;
                    }
                }
                # The parent is the same node in basic and in enhanced. What about the relation type?
                elsif($biedge->{deprel} eq $iedge->{deprel})
                {
                    $stats{edge_both_basic_and_enhanced}++;
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
                        $stats{edge_basic_parent_enhanced_type}++;
                    }
                    else
                    {
                        $stats{edge_basic_parent_incompatible_type}++;
                    }
                    $biedge_found++;
                    if($report_basenh)
                    {
                        $stats{basenh}{"edge enhanced type: $biedge->{deprel} --> $iedge->{deprel}"}++;
                    }
                }
            }
            else # no basic incoming edge => all incoming edges are enhanced-only
            {
                $stats{edge_enhanced_only}++;
                if($report_basenh)
                {
                    $stats{basenh}{"edge enhanced only: $iedge->{deprel}"}++;
                }
            }
        }
        if($biedge && !$biedge_found)
        {
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
        }
        # The presence of an empty node signals that gapping is resolved.
        if($curnode->is_empty())
        {
            $stats{gapping}++;
            $n_empty_nodes_in_this_graph++;
            ###!!! We may want to check other attributes of gapping resolution:
            ###!!! 1. there should be no 'orphan' relations in the enhanced graph.
            ###!!! 2. the empty node should be attached as conjunct to a verb. Perhaps it should also have a copy of the verb's form lemma, tag and features.
            ###!!! 3. the empty node should have at least two non-functional children (subj, obj, obl, advmod, ccomp, xcomp, advcl).
        }
        # Parent propagation in coordination: 'conj' (always?) accompanied by another relation.
        # Shared child propagation: node has at least two parents, one of them is 'conj' of the other.
        ###!!! We may also want to check whether there are any contentful dependents of a first conjunct that are not shared.
        if(scalar(@iedges) >= 2 &&
           scalar(grep {$_->{deprel} =~ m/^conj(:|$)/} (@iedges)) > 0 &&
           scalar(grep {$_->{deprel} !~ m/^conj(:|$)/} (@iedges)) > 0)
        {
            $stats{conj_effective_parent}++;
        }
        if(scalar(@iedges) >= 2)
        {
            # Find grandparents such that their relation to the parent is 'conj' and my relation to the parent is not 'conj'.
            my %gpconj;
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
            # Is one of those grandparents also my non-conj parent?
            my $found = 0;
            foreach my $iedge (@iedges)
            {
                if($iedge->{deprel} !~ m/^conj(:|$)/ && exists($gpconj{$iedge->{id}}))
                {
                    $found = 1;
                    last;
                }
            }
            if($found)
            {
                $stats{conj_shared_dependent}++;
            }
        }
        # Subject propagation through xcomp: at least two parents, I am subject
        # or object of one, and subject of the other. The latter parent is xcomp of the former.
        my @subjpr = grep {$_->{deprel} =~ m/^nsubj(:|$)/} (@iedges);
        my @xcompgpr;
        foreach my $pr (@subjpr)
        {
            my @xgpr = grep {$_->{deprel} =~ m/^xcomp(:|$)/} (@{$graph->node($pr->{id})->iedges()});
            push(@xcompgpr, @xgpr);
        }
        my @coreprxgpr = grep {my $r = relation($_->{id}, $curnode->{id}, $graph); defined($r) && $r =~ m/^(nsubj|obj|iobj)(:|$)/} (@xcompgpr);
        if(scalar(@coreprxgpr) > 0)
        {
            $stats{xsubj}++;
        }
        # Relative clauses: the ref relation; a cycle containing acl:relcl
        my @refpr = grep {$_->{deprel} =~ m/^ref(:|$)/} (@iedges);
        if(scalar(@refpr) > 0)
        {
            $stats{relcl}++;
        }
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
    }
    $stats{graphs_with_n_empty_nodes}{$n_empty_nodes_in_this_graph}++;
}
