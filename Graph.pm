package Graph;

use utf8;
use namespace::autoclean;

use Carp;
use Moose;
use MooseX::SemiAffordanceAccessor; # attribute x is written using set_x($value) and read using x()
use List::MoreUtils qw(any);
use Node;



has 'comments' => (is => 'ro', isa => 'ArrayRef', default => sub {[]}, documentation => 'Sentence-level CoNLL-U comments.');
has 'nodes'    => (is => 'ro', isa => 'HashRef', default => sub {my $self = shift; {0 => new Node('id' => 0, 'graph' => $self)}});



#------------------------------------------------------------------------------
# Creates a graph from a list of CoNLL-U lines (the list may or may not contain
# the final empty line, it does not matter). This is a static function, it does
# not take a reference to a Graph object but it returns one.
#------------------------------------------------------------------------------
sub from_conllu_lines
{
    my @sentence = @_;
    my $graph = new Graph;
    # Get rid of everything except the node lines. But include empty nodes!
    foreach my $line (@sentence)
    {
        if($line =~ m/^\#/)
        {
            push(@{$graph->comments()}, $line);
        }
        # We need nodes even for the lines that introduce multi-word tokens
        # because we have to store their attributes so we can later print the
        # whole sentence again. However, these "nodes" will not be connected
        # to the rest of the graph neither by basic nor by enhanced edges.
        elsif($line =~ m/^\d/)
        {
            my @fields = split(/\t/, $line);
            my $node = new Node('id' => $fields[0], 'form' => $fields[1], 'lemma' => $fields[2], 'upos' => $fields[3], 'xpos' => $fields[4],
                                '_head' => $fields[6], '_deprel' => $fields[7], '_deps' => $fields[8]);
            $node->set_feats_from_conllu($fields[5]);
            $node->set_misc_from_conllu($fields[9]);
            $graph->add_node($node);
        }
    }
    # Once all nodes have been added to the graph, we can draw edges between them.
    foreach my $node ($graph->get_nodes())
    {
        $node->set_basic_dep_from_conllu();
        $node->set_deps_from_conllu();
    }
    return $graph;
}



#------------------------------------------------------------------------------
# Generates a list of CoNLL-U lines from the current graph; the list does not
# contain the final empty line.
#------------------------------------------------------------------------------
sub to_conllu_lines
{
    confess('Incorrect number of arguments') if(scalar(@_) != 1);
    my $self = shift;
    my @sentence = @{$self->comments()};
    foreach my $node ($self->get_nodes(1))
    {
        my @fields = ($node->id(), $node->form(), $node->lemma(), $node->upos(), $node->xpos(), $node->get_feats_string(),
                      $node->bparent(), $node->bdeprel(), $node->get_deps_string(), $node->get_misc_string());
        push(@sentence, join("\t", @fields));
    }
    return @sentence;
}



#------------------------------------------------------------------------------
# Checks whether there is a node with the given id.
#------------------------------------------------------------------------------
sub has_node
{
    confess('Incorrect number of arguments') if(scalar(@_) != 2);
    my $self = shift;
    my $id = shift;
    confess('Undefined id') if(!defined($id));
    return exists($self->nodes()->{$id});
}



#------------------------------------------------------------------------------
# Returns node with the given id. If there is no such node, returns undef.
#------------------------------------------------------------------------------
sub get_node
{
    confess('Incorrect number of arguments') if(scalar(@_) != 2);
    my $self = shift;
    my $id = shift;
    confess('Undefined id') if(!defined($id));
    return $self->has_node($id) ? $self->nodes()->{$id} : undef;
}



#------------------------------------------------------------------------------
# Returns node with the given id. If there is no such node, returns undef.
# This method is just an alias for get_node().
#------------------------------------------------------------------------------
sub node
{
    my $self = shift;
    my $id = shift;
    return $self->get_node($id);
}



#------------------------------------------------------------------------------
# Returns the list of all nodes except the artificial root node with id 0. The
# list is ordered by node ids. The list excludes fake nodes of multi-word
# tokens by default, but they can be required in the second parameter.
#------------------------------------------------------------------------------
sub get_nodes
{
    confess('Incorrect number of arguments') if(scalar(@_) < 1 || scalar(@_) > 2);
    my $self = shift;
    my $include_mwts = shift;
    my @list = map {$self->get_node($_)} (sort
    {
        Node::cmpids($a, $b)
    }
    (grep {$_ ne '0' && ($include_mwts || $_ !~ m/-/)} (keys(%{$self->nodes()}))));
    return @list;
}



#------------------------------------------------------------------------------
# Adds a node to the graph. The node must have a non-empty id that has not been
# used by any other node previously added to the graph.
#------------------------------------------------------------------------------
sub add_node
{
    confess('Incorrect number of arguments') if(scalar(@_) != 2);
    my $self = shift;
    my $node = shift;
    my $id = $node->id();
    if(!defined($id))
    {
        confess('Cannot add node with undefined ID');
    }
    if($self->has_node($id))
    {
        confess("There is already a node with ID $id in the graph");
    }
    $self->nodes()->{$id} = $node;
    $node->set_graph($self);
}



#------------------------------------------------------------------------------
# Removes a node from the graph. Does not change the ids of the remaining
# nodes. Returns the Node object that has been disconnected from the graph.
# Returns undef if there is no node with the given id.
#------------------------------------------------------------------------------
sub remove_node
{
    confess('Incorrect number of arguments') if(scalar(@_) != 2);
    my $self = shift;
    my $id = shift;
    confess('Undefined id') if(!defined($id));
    my $node = undef;
    if($self->has_node($id))
    {
        $node = $self->nodes()->{$id};
        delete($self->nodes()->{$id});
        $node->set_graph(undef);
    }
    return $node;
}



#------------------------------------------------------------------------------
# Adds an edge between two nodes that are already in the graph.
#------------------------------------------------------------------------------
sub add_edge
{
    confess('Incorrect number of arguments') if(scalar(@_) != 4);
    my $self = shift;
    my $srcid = shift;
    my $tgtid = shift;
    my $deprel = shift;
    my $srcnode = $self->get_node($srcid);
    my $tgtnode = $self->get_node($tgtid);
    confess("Unknown node '$srcid'") if(!defined($srcnode));
    confess("Unknown node '$tgtid'") if(!defined($tgtnode));
    # Outgoing edge from the source (parent).
    my %oe =
    (
        'id'     => $tgtid,
        'deprel' => $deprel
    );
    # Incoming edge to the target (child).
    my %ie =
    (
        'id'     => $srcid,
        'deprel' => $deprel
    );
    # Check that the same edge does not exist already.
    push(@{$srcnode->oedges()}, \%oe) unless(any {$_->{id} eq $tgtid && $_->{deprel} eq $deprel} (@{$srcnode->oedges()}));
    push(@{$tgtnode->iedges()}, \%ie) unless(any {$_->{id} eq $srcid && $_->{deprel} eq $deprel} (@{$tgtnode->iedges()}));
}



#------------------------------------------------------------------------------
# Removes an existing edge between two nodes of the graph.
#------------------------------------------------------------------------------
sub remove_edge
{
    confess('Incorrect number of arguments') if(scalar(@_) != 4);
    my $self = shift;
    my $srcid = shift;
    my $tgtid = shift;
    my $deprel = shift;
    my $srcnode = $self->get_node($srcid);
    my $tgtnode = $self->get_node($tgtid);
    confess("Unknown node '$srcid'") if(!defined($srcnode));
    confess("Unknown node '$tgtid'") if(!defined($tgtnode));
    # Outgoing edge from the source (parent).
    @{$srcnode->oedges()} = grep {!($_->{id} eq $tgtid && $_->{deprel} eq $deprel)} (@{$srcnode->oedges()});
    # Incoming edge to the target (child).
    @{$tgtnode->iedges()} = grep {!($_->{id} eq $srcid && $_->{deprel} eq $deprel)} (@{$tgtnode->iedges()});
}



#------------------------------------------------------------------------------
# Graphs refer to nodes and nodes refer back to graphs. We must break this
# cycle manually when we are done with the graph, otherwise the Perl garbage
# collector will keep the graph and the nodes in the memory forever. Note that
# renaming this method to DEMOLISH will not cause Perl to clean up automati-
# cally. As long as the references are there, the graph will not be destroyed
# and DEMOLISH will not be called.
#
# Debug memory usage like this (watch the VSZ number):
# print STDERR ("Sentence no. $i\n", `ps -p $$ -o vsz,rsz,sz,size`);
#------------------------------------------------------------------------------
sub remove_all_nodes
{
    my $self = shift;
    my @nodes = $self->get_nodes(1);
    foreach my $node (@nodes)
    {
        $self->remove_node($node->id());
        # We don't have to remove edges manually. They contain node ids but not Perl references.
    }
}



__PACKAGE__->meta->make_immutable();

1;



=for Pod::Coverage BUILD

=encoding utf-8

=head1 NAME

Graph

=head1 DESCRIPTION

A C<Graph> holds a list of nodes and can return the C<Node> based on its
C<ID> (the first column in a CoNLL-U file, can be integer or a decimal number).
Edges are stored in nodes.

It is currently necessary to call the method C<remove_all_nodes()> when the
graph is no longer needed. Otherwise cyclic references will prevent Perl from
freeing the memory occupied by the graph and its nodes.

=head1 ATTRIBUTES

=over

=item comments

A read-only attribute (filled during construction) that holds the sentence-level
comments from the CoNLL-U file.

=item nodes

A hash (reference) that holds the individual L<Node> objects, indexed by their
ids from the first column of the CoNLL-U file.

=back

=head1 METHODS

=over

=item $graph = Graph::from_conllu_lines (@sentence);

Creates a graph from a list of CoNLL-U lines (the list may or may not contain
the final empty line, it does not matter). This is a static function, it does
not take a reference to a Graph object but it returns one.

=item @sentence = $graph->to_conllu_lines ();

Generates a list of CoNLL-U lines from the current graph; the list does not
contain the final empty line.

=item $graph->has_node ($id);

Returns a nonzero value if there is a node with the given id in the graph.

=item $graph->get_node ($id);
=item $graph->node ($id);

Returns the object with the node with the given id.

=item @nodes = $graph->get_nodes ();

Returns the list of all nodes except the artificial root node with id 0. The
list is ordered by node ids. The list excludes fake nodes of multi-word tokens
by default, but they can be required in the second parameter.

=item $graph->add_node ($node);

Adds a node (a L<Node> object) to the graph. The node must have a non-empty id
that has not been used by any other node previously added to the graph.

=item $graph->remove_node ($id);

Removes a node from the graph. Does not change the ids of the remaining
nodes. Returns the L<Node> object that has been disconnected from the graph.
Returns undef if there is no node with the given id.

=item $graph->add_edge ($source_id, $target_id, $relation_label);

Adds an edge between two nodes that are already in the graph.

=item $graph->remove_edge ($source_id, $target_id, $relation_label);

Removes an existing edge between two nodes of the graph.

=item $graph->remove_all_nodes ();

Currently the only way of breaking cyclic references when the graph is no
longer needed. Make sure to call this method in order to prevent memory leaks!

=back

=head1 AUTHORS

Daniel Zeman <zeman@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2019, 2020 by Institute of Formal and Applied Linguistics, Charles University in Prague
This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
