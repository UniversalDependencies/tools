package Node;

use utf8;
use namespace::autoclean;

use Moose;
use MooseX::SemiAffordanceAccessor; # attribute x is written using set_x($value) and read using x()
use List::MoreUtils qw(any);
use Graph;



has 'graph'   => (is => 'rw', isa => 'Maybe[Graph]', documentation => 'Refers to the graph (sentence) this node belongs to.');
has 'id'      => (is => 'rw', isa => 'Str', required => 1, documentation => 'The ID column in CoNLL-U file.');
has 'form'    => (is => 'rw', isa => 'Str', documentation => 'The FORM column in CoNLL-U file.');
has 'lemma'   => (is => 'rw', isa => 'Str', documentation => 'The LEMMA column in CoNLL-U file.');
has 'upos'    => (is => 'rw', isa => 'Str', documentation => 'The UPOS column in CoNLL-U file.');
has 'xpos'    => (is => 'rw', isa => 'Str', documentation => 'The XPOS column in CoNLL-U file.');
has 'feats'   => (is => 'rw', isa => 'HashRef', documentation => 'Hash holding the features from the FEATS column in CoNLL-U file.');
has 'misc'    => (is => 'rw', isa => 'ArrayRef', documentation => 'Array holding the attributes from the MISC column in CoNLL-U file.');
has '_head'   => (is => 'rw', isa => 'Str', documentation => 'Temporary storage for the HEAD column before the graph structure is built.');
has '_deprel' => (is => 'rw', isa => 'Str', documentation => 'Temporary storage for the DEPREL column before the graph structure is built.');
has '_deps'   => (is => 'rw', isa => 'Str', documentation => 'Temporary storage for the DEPS column before the graph structure is built.');
has 'iedges'  => (is => 'rw', isa => 'ArrayRef', default => sub {[]}, documentation => 'Array of records of incoming edges. Each record is a hash ref, keys are id, deprel.');
has 'oedges'  => (is => 'rw', isa => 'ArrayRef', default => sub {[]}, documentation => 'Array of records of outgoing edges. Each record is a hash ref, keys are id, deprel.');
has 'bparent' => (is => 'rw', isa => 'Str', documentation => 'Parent node in the basic tree.');
has 'bdeprel' => (is => 'rw', isa => 'Str', documentation => 'Type of relation between this node and its parent in the basic tree.');
has 'bchildren' => (is=>'rw', isa => 'ArrayRef', default => sub {[]}, documentation => 'Array of ids of children in the basic tree.');
has 'predicate' => (is => 'rw', isa => 'Str', documentation => 'Lemma and frame identifier of the predicate.');
has 'argedges'  => (is => 'rw', isa => 'ArrayRef', default => sub {[]}, documentation => 'Array of records of edges from a predicate to its arguments, labeled with argument labels.');
has 'argpattern' => (is => 'rw', isa => 'Str', documentation => 'Predicate with the pattern of deprels of its arguments.');



#------------------------------------------------------------------------------
# Creates a deep copy of the current node. Attributes such as "id" and "form"
# are copied. WHAT ABOUT EDGES?
#------------------------------------------------------------------------------
sub clone
{
    my $self = shift;
    my %feats = %{$self->feats()};
    my @misc = @{$self->misc()};
    my @bchildren = @{$self->bchildren()};
    my @iedges = @{$self->iedges()};
    my @oedges = @{$self->oedges()};
    my @argedges = @{$self->argedges()};
    # The new copy is not part of the same Graph object. Therefore we do not
    # copy the "graph" attribute. However, the other structural attributes
    # refer to the other nodes through their ids, and we assume that the same
    # ids will also be valid in the new graph. The caller has to call
    # $graph->add_node($node) though.
    my $clone = new Node
    (
        'id'         => $self->id(),
        'form'       => $self->form(),
        'lemma'      => $self->lemma(),
        'upos'       => $self->upos(),
        'xpos'       => $self->xpos(),
        'feats'      => \%feats,
        '_head'      => $self->_head(),
        'bparent'    => $self->bparent(),
        '_deprel'    => $self->_deprel(),
        'bdeprel'    => $self->bdeprel(),
        'bchildren'  => \@bchildren,
        '_deps'      => $self->_deps(),
        'iedges'     => \@iedges,
        'oedges'     => \@oedges,
        'misc'       => \@misc,
        'predicate'  => $self->predicate(),
        'argedges'   => \@argedges,
        'argpattern' => $self->argpattern()
    );
    return $clone;
}



#------------------------------------------------------------------------------
# Parses the string from the FEATS column of a CoNLL-U file and sets the feats
# hash accordingly. If the feats hash has been set previously, it will be
# discarded and replaced by the new one.
#------------------------------------------------------------------------------
sub set_feats_from_conllu
{
    confess('Incorrect number of arguments') if(scalar(@_) != 2);
    my $self = shift;
    my $feats = shift;
    unless($feats eq '_')
    {
        my @fvpairs = split(/\|/, $feats);
        my %feats;
        foreach my $fv (@fvpairs)
        {
            if($fv =~ m/^([A-Za-z\[\]]+)=([A-Za-z0-9,]+)$/)
            {
                my $f = $1;
                my $v = $2;
                if(exists($feats{$f}))
                {
                    print STDERR ("WARNING: Duplicite feature definition: '$f=$feats{$f}' will be overwritten with '$f=$v'.\n");
                }
                $feats{$f} = $v;
            }
            else
            {
                print STDERR ("WARNING: Unrecognized feature-value pair '$fv'.\n");
            }
        }
        # The feature hash may be empty due to input errors. Set it only if
        # there are meaningful values.
        if(scalar(keys(%feats))>0)
        {
            $self->set_feats(\%feats);
        }
    }
}



#------------------------------------------------------------------------------
# Returns features as string that can be used in a CoNLL-U file.
#------------------------------------------------------------------------------
sub get_feats_string
{
    confess('Incorrect number of arguments') if(scalar(@_) != 1);
    my $self = shift;
    if(!defined($self->feats()))
    {
        return '_';
    }
    my %feats = %{$self->feats()};
    my @keys = sort {lc($a) cmp lc($b)} (keys(%feats));
    if(scalar(@keys)==0)
    {
        return '_';
    }
    else
    {
        return join('|', map {"$_=$feats{$_}"} (@keys));
    }
}



#------------------------------------------------------------------------------
# Parses the string from the MISC column of a CoNLL-U file and sets the misc
# array accordingly. If the misc array has been set previously, it will be
# discarded and replaced by the new one.
#------------------------------------------------------------------------------
sub set_misc_from_conllu
{
    confess('Incorrect number of arguments') if(scalar(@_) != 2);
    my $self = shift;
    my $misc = shift;
    # No CoNLL-U field can contain leading or trailing whitespace characters.
    # In particular, the linte-terminating LF character may have been forgotten
    # when the line was split into fields, but it is not part of the MISC field.
    $misc =~ s/^\s+//;
    $misc =~ s/\s+$//;
    unless($misc eq '_')
    {
        my @misc = split(/\|/, $misc);
        $self->set_misc(\@misc);
    }
}



#------------------------------------------------------------------------------
# Returns MISC attributes as string that can be used in a CoNLL-U file.
#------------------------------------------------------------------------------
sub get_misc_string
{
    confess('Incorrect number of arguments') if(scalar(@_) != 1);
    my $self = shift;
    if(!defined($self->misc()))
    {
        return '_';
    }
    my @misc = @{$self->misc()};
    if(scalar(@misc)==0)
    {
        return '_';
    }
    else
    {
        return join('|', @misc);
    }
}



#------------------------------------------------------------------------------
# Checks whether the node depends (directly or indirectly) on a given other
# node in the basic tree.
#------------------------------------------------------------------------------
sub basic_depends_on
{
    confess('Incorrect number of arguments') if(scalar(@_) != 2);
    my $self = shift;
    confess('Node is not member of a graph') if(!defined($self->graph()));
    my $aid = shift; # ancestor id
    # Avoid deep recursion in large trees (e.g., the Gothic treebank contains
    # a sentence of 165 words that form one long apposition chain). Avoid
    # recursion completely.
    my $graph = $self->graph();
    my $id = $self->bparent();
    while(defined($id))
    {
        if($id==$aid)
        {
            return 1;
        }
        else
        {
            $id = $graph->get_node($id)->bparent();
        }
    }
    return 0;
}



#------------------------------------------------------------------------------
# Links the node with its parent according to the basic tree. Both the node
# and its parent must be already added to a graph, and the parent must not
# already depend on the node.
#------------------------------------------------------------------------------
sub set_basic_dep_from_conllu
{
    confess('Incorrect number of arguments') if(scalar(@_) != 1);
    my $self = shift;
    confess('Node is not member of a graph') if(!defined($self->graph()));
    my $head = $self->_head();
    my $deprel = $self->_deprel();
    unless(!defined($head) || $head eq '' || $head eq '_')
    {
        # This method is designed for one-time use in the beginning.
        # Therefore we assume that the basic parent has not been set previously.
        # (Otherwise we would have to care first about removing any link to us
        # from the current parent.)
        if(defined($self->bparent()))
        {
            confess('Basic parent already exists');
        }
        if(!$self->graph()->has_node($head))
        {
            confess("Basic dependency '$deprel' from a non-existent node '$head'");
        }
        if($head == $self->id())
        {
            confess("Cannot attach node '$head' to itself in the basic tree");
        }
        if($self->graph()->get_node($head)->basic_depends_on($self->id()))
        {
            my $id = $self->id();
            confess("Cannot attach node '$id' to '$head' in the basic tree because it would make a cycle");
        }
        $self->set_bparent($head);
        $self->set_bdeprel($deprel);
        push(@{$self->graph()->get_node($head)->bchildren()}, $self->id());
    }
    # We must set bparent and bdeprel even if they are undefined ('_').
    # They are undefined on multiword token lines but we must preserve and output '_' on these lines.
    else
    {
        $self->set_bparent('_');
        $self->set_bdeprel('_');
    }
}



#------------------------------------------------------------------------------
# Parses the string stored in _deps and creates the corresponding edges. The
# node must be already added to a graph, and all nodes referenced in the edges
# must also be added to the same graph.
#------------------------------------------------------------------------------
sub set_deps_from_conllu
{
    confess('Incorrect number of arguments') if(scalar(@_) != 1);
    my $self = shift;
    confess('Node is not member of a graph') if(!defined($self->graph()));
    my $deps = $self->_deps();
    unless(!defined($deps) || $deps eq '' || $deps eq '_')
    {
        my @deps = split(/\|/, $deps);
        foreach my $dep (@deps)
        {
            if($dep =~ m/^(\d+(?:\.\d+)?):(.+)$/)
            {
                my $h = $1;
                my $d = $2;
                # Check that the referenced parent node exists.
                if(!$self->graph()->has_node($h))
                {
                    confess("Incoming dependency '$d' from a non-existent node '$h'");
                }
                # Store the parent in my incoming edges.
                my %pr =
                (
                    'id'     => $h,
                    'deprel' => $d
                );
                # Check that the same edge (including label) does not already exist.
                if(any {$_->{id} == $h && $_->{deprel} eq $d} (@{$self->iedges()}))
                {
                    print STDERR ("WARNING: Ignoring repeated declaration of edge '$h --- $d ---> $self->{id}'.\n");
                }
                else
                {
                    push(@{$self->iedges()}, \%pr);
                    # Store me as a child in the parent's object.
                    my %cr =
                    (
                        'id'     => $self->id(),
                        'deprel' => $d
                    );
                    push(@{$self->graph()->get_node($h)->oedges()}, \%cr);
                }
            }
            else
            {
                print STDERR ("WARNING: Cannot understand dep '$dep'\n");
            }
        }
    }
}



#------------------------------------------------------------------------------
# Returns enhanced DEPS as string that can be used in a CoNLL-U file.
#------------------------------------------------------------------------------
sub get_deps_string
{
    confess('Incorrect number of arguments') if(scalar(@_) != 1);
    my $self = shift;
    my @iedges = sort
    {
        my $r = cmpids($a->{id}, $b->{id});
        unless($r)
        {
            $r = $a->{deprel} cmp $b->{deprel};
        }
        $r
    }
    (@{$self->iedges()});
    if(scalar(@iedges)==0)
    {
        return '_';
    }
    else
    {
        return join('|', map {"$_->{id}:$_->{deprel}"} (@iedges));
    }
}



#------------------------------------------------------------------------------
# Compares ids of two nodes or multi-word tokens and returns -1, 0, or 1,
# reflecting the order in which the lines must appear in a CoNLL-U file.
# This is a static function that does not take a pointer to a Node object.
#------------------------------------------------------------------------------
sub cmpids
{
    my $a = shift;
    my $b = shift;
    # Ids of empty nodes look like decimal numbers but in fact, 3.14 is
    # considered greater than 3.2.
    # Furthermore, there may be interval ids of multi-word tokens (e.g. 3-4).
    # The intervals cannot overlap within one sentence, but the line must be
    # before the lines of the tokens in the interval.
    $a =~ m/^(\d+)(?:\.(\d+))?(?:-(\d+))?$/;
    my $amaj = $1; confess("Unexpected node id '$a->{id}'") if(!defined($amaj));
    my $amin = defined($2) ? $2 : 0;
    my $amwt = defined($3) ? $3 : 0;
    $b =~ m/^(\d+)(?:\.(\d+))?(?:-(\d+))?$/;
    my $bmaj = $1; confess("Unexpected node id '$b->{id}'") if(!defined($bmaj));
    my $bmin = defined($2) ? $2 : 0;
    my $bmwt = defined($3) ? $3 : 0;
    my $r = $amaj <=> $bmaj;
    unless($r)
    {
        $r = $amin <=> $bmin;
        unless($r)
        {
            # MWT line goes before the first word line. Hence any nonzero xmwt
            # is "smaller" than zero.
            $r = $bmwt <=> $amwt;
        }
    }
    return $r;
}



#------------------------------------------------------------------------------
# Checks whether the node corresponds to a multi-word token (which means it is
# not a normal node, just a storage place for the token's attributes).
#------------------------------------------------------------------------------
sub is_mwt
{
    confess('Incorrect number of arguments') if(scalar(@_) != 1);
    my $self = shift;
    return $self->id() =~ m/-/;
}



#------------------------------------------------------------------------------
# Checks whether the node is empty, i.e., it does not correspond to an overt
# surface token and has a decimal id.
#------------------------------------------------------------------------------
sub is_empty
{
    confess('Incorrect number of arguments') if(scalar(@_) != 1);
    my $self = shift;
    return $self->id() =~ m/\./;
}



#------------------------------------------------------------------------------
# Returns the number of incoming edges.
#------------------------------------------------------------------------------
sub get_in_degree
{
    confess('Incorrect number of arguments') if(scalar(@_) != 1);
    my $self = shift;
    return scalar(@{$self->iedges()});
}



#------------------------------------------------------------------------------
# Returns the number of outgoing edges.
#------------------------------------------------------------------------------
sub get_out_degree
{
    confess('Incorrect number of arguments') if(scalar(@_) != 1);
    my $self = shift;
    return scalar(@{$self->oedges()});
}



#------------------------------------------------------------------------------
# Returns predicate-argument edges as string that can be used in a CoNLL-U Plus
# file.
#------------------------------------------------------------------------------
sub get_args_string
{
    confess('Incorrect number of arguments') if(scalar(@_) != 1);
    my $self = shift;
    my @argedges = @{$self->argedges()};
    if(scalar(@argedges)==0)
    {
        return '_'; ###!!! $config{empty} in the main module may actually require '*' or something else here. Should we make it an optional parameter?
    }
    else
    {
        return join('|', map {my $a = $_; my $ids = ref($a->{id}) eq 'ARRAY' ? join(',', @{$a->{id}}) : $a->{id}; "$a->{deprel}:$ids"} (@argedges));
    }
}



__PACKAGE__->meta->make_immutable();

1;



=for Pod::Coverage BUILD

=encoding utf-8

=head1 NAME

Node

=head1 DESCRIPTION

A C<Node> corresponds to a line in a CoNLL-U file: a word, an empty node, or
even a multi-word token.

=head1 ATTRIBUTES

=over

=item id

The ID of the node. Column 0 of the line.

=back

=head1 METHODS

=over

=item $node->set_feats_from_conllu ($feats);

Parses the string from the FEATS column of a CoNLL-U file and sets the feats
hash accordingly. If the feats hash has been set previously, it will be
discarded and replaced by the new one.

=item $feats = $node->get_feats_string ();

Returns features as a string that can be used in a CoNLL-U file.

=item $node->is_mwt ();

Checks whether the node corresponds to a multi-word token (which means it is
not a normal node, just a storage place for the token's attributes).

=item $node->is_empty ();

Checks whether the node is empty, i.e., it does not correspond to an overt
surface token and has a decimal id.

=item $indeg = $node->get_in_degree ();

Returns the number of incoming edges to the node.

=item $outdeg = $node->get_out_degree ();

Returns the number of outgoing edges from the node.

=back

=head1 AUTHORS

Daniel Zeman <zeman@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2019, 2020 by Institute of Formal and Applied Linguistics, Charles University in Prague
This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
