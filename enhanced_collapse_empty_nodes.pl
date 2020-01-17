#!/usr/bin/env perl
# Processes enhanced graphs in a CoNLL-U file so that empty nodes are removed
# and paths that traverse them are collapsed into individual edges whose labels
# show the original path, either with or without the ids of the empty nodes:
# "conj>33.1>nsubj" or "conj>nsubj".
# Copyright © 2020 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use List::MoreUtils qw(any);
###!!! We need to tell Perl where to find my graph modules. But we should
###!!! modify it so that it works on any computer! Right now it depends on
###!!! the 'pwd' command, which is not available on Windows.
###!!! If this does not work, you can put the script together with Graph.pm and
###!!! Node.pm in a folder of you choice, say, /home/joe/scripts, and then
###!!! invoke Perl explicitly telling it where the modules are:
###!!! perl -I/home/joe/scripts /home/joe/scripts/enhanced_graph_properties.pl inputfile.conllu
BEGIN
{
    my $path = $0;
    my $currentpath = `pwd`;
    $currentpath =~ s/\r?\n$//;
    $libpath = $currentpath;
    if($path =~ m:/:)
    {
        $path =~ s:/[^/]*$:/:;
        chdir($path);
        $libpath = `pwd`;
        chdir($currentpath);
    }
    $libpath =~ s/\r?\n$//;
    #print STDERR ("libpath=$libpath\n");
}
use lib $libpath;
use Graph;
use Node;

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
    my $graph = new Graph;
    # Get rid of everything except the node lines. But include empty nodes!
    my @nodelines = grep {m/^\d+(\.\d+)?\t/} (@sentence);
    foreach my $nodeline (@nodelines)
    {
        my @fields = split(/\t/, $nodeline);
        my $node = new Node('id' => $fields[0], 'form' => $fields[1], 'lemma' => $fields[2], 'upos' => $fields[3], 'xpos' => $fields[4],
                            '_head' => $fields[6], '_deprel' => $fields[7], '_deps' => $fields[8]);
        $node->set_feats_from_conllu($fields[5]);
        $node->set_misc_from_conllu($fields[9]);
        $graph->add_node($node);
    }
    # Once all nodes have been added to the graph, we can draw edges between them.
    foreach my $node ($graph->get_nodes())
    {
        $node->set_basic_dep_from_conllu();
        $node->set_deps_from_conllu();
    }
    # We now have a complete representation of the graph.
    collapse_empty_nodes($graph);
    # Now get the list of CoNLL-U lines from the modified graph.
    @sentence = ();
    foreach my $node ($graph->get_nodes())
    {
        my @fields = ($node->id(), $node->form(), $node->lemma(), $node->upos(), $node->xpos(), $node->get_feats_string(),
                      $node->bparent(), $node->bdeprel(), $node->get_deps_string(), $node->get_misc_string());
        push(@sentence, join("\t", @fields));
    }
    print_sentence(@sentence);
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
# Processes the enhanced graph and collapses paths traversing empty nodes.
#------------------------------------------------------------------------------
sub collapse_empty_nodes
{
    my $graph = shift; # a Graph object
    my @nodes = $graph->get_nodes();
    my @edges;
    foreach my $node (@nodes)
    {
        my $cid = $node->id();
        my @iedges = @{$node->iedges()};
        foreach my $iedge (@iedges)
        {
            my $pid = $iedge->{id};
            my $deprel = $iedge->{deprel};
            push(@edges, [$pid, $deprel, $cid]);
        }
    }
    my @okedges = grep {$_->[0] =~ m/^\d+$/ && $_->[-1] =~ m/^\d+$/} (@edges);
    my @epedges = grep {$_->[0] =~ m/^\d+\.\d+$/} (@edges); # including those that have also empty child
    my @ecedges = grep {$_->[-1] =~ m/^\d+\.\d+$/} (@edges); # including those that have also empty parent
    while(@epedges)
    {
        my $epedge = shift(@epedges);
        my @myecedges = grep {$_->[-1] eq $epedge->[0]} (@ecedges);
        foreach my $ecedge (@myecedges)
        {
            my @newedge = @{$ecedge};
            pop(@newedge);
            push(@newedge, @{$epedge});
            # If there are cycles involving the empty nodes, ignore them.
            my $cycle = 0;
            my %map;
            for(my $i = 0; $i <= $#newedge; $i += 2)
            {
                if(exists($map{$newedge[$i]}))
                {
                    $cycle = 1;
                    last;
                }
                $map{$newedge[$i]}++;
            }
            unless($cycle)
            {
                if($newedge[0] =~ m/^\d+$/ && $newedge[-1] =~ m/^\d+$/)
                {
                    push(@okedges, \@newedge);
                }
                else
                {
                    if($newedge[0] =~ m/^\d+\.\d+$/)
                    {
                        push(@epedges, \@newedge);
                    }
                    if($newedge[-1] =~ m/^\d+\.\d+$/)
                    {
                        push(@ecedges, \@newedge);
                    }
                }
            }
            else
            {
                print STDERR ('Ignoring enhanced path '.join('>', @newedge)."\n");
            }
        }
    }
    # Now there are no more @epedges (while @ecedges grew over time but we do not care now).
    # All edges in @okedges have non-empty ends.
    @okedges = sort {my $r = $a->[-1] <=> $b->[-1]; unless($r) {$r = $a->[0] <=> $b->[0]} $r} (@okedges);
    # Remove all edges going to or from an empty node, then remove the empty nodes as well.
    foreach my $node (@nodes)
    {
        if($node->id() =~ m/\./)
        {
            my @iedges = @{$node->iedges()};
            foreach my $iedge (@iedges)
            {
                $graph->remove_edge($iedge->{id}, $node->id(), $iedge->{deprel});
            }
            my @oedges = @{$node->oedges()};
            foreach my $oedge (@oedges)
            {
                $graph->remove_edge($node->id(), $oedge->{id}, $oedge->{deprel});
            }
            $graph->remove_node($node->id());
        }
    }
    # Add the new collapsed edges to the graph.
    foreach my $edge (@okedges)
    {
        my @edge = @{$edge};
        my $pid = shift(@edge);
        my $cid = pop(@edge);
        # Skip simple edges because they are already in the graph.
        next unless(scalar(@edge) > 1);
        my $deprel = join('>', @edge);
        # Remove the ids of the empty nodes from the path.
        ###!!! We may want to parameterize this step because we may want to preserve
        ###!!! the ids in some use cases. However, for the sake of the evaluation of
        ###!!! the EUD shared task, we want to get rid of them.
        $deprel =~ s/>\d+\.\d+>/>/g;
        # Add the collapsed edge to the graph.
        $graph->add_edge($pid, $cid, $deprel);
    }
}
