#!/usr/bin/env perl
# Reads a CoNLL-U file and tries to fix certain simple errors that would make the file invalid; writes the fixed file to STDOUT.
# Can be used to make a parser output valid.
# * Converts Unicode to the NFC normalized form (i.e., canonical decomposition followed by canonical composition).
# * Makes sure that all sentences have a unique sentence id.
# * Makes sure that all sentences have the full text comment and that it matches the SpaceAfter=No annotations (but if both exist in the input and they don't match, the script gives up).
# Usage: perl conllu-quick-fix.pl < input.conllu > fixed.conllu
# Copyright © 2019, 2020 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Unicode::Normalize;
use Getopt::Long;

my $connect_to_root = 0;
GetOptions
(
    'connect-to-root' => \$connect_to_root
);

my @sentence = ();
my $isent = 0;
while(<>)
{
    push(@sentence, NFC($_));
    if(m/^\s*$/)
    {
        process_sentence(@sentence);
        @sentence = ();
    }
}



#------------------------------------------------------------------------------
# Once a sentence has been read, processes it and prints it.
#------------------------------------------------------------------------------
sub process_sentence
{
    $isent++; # global counter
    my @sentence = @_;
    my $sentid;
    my $text;
    my $resttext;
    my $collected_text = '';
    my $mwtto;
    foreach my $line (@sentence)
    {
        $line =~ s/\r?\n$//;
        if($line =~ m/^\#\s*sent_id\s*=\s*(\S+)$/)
        {
            $sentid = $1;
        }
        elsif($line =~ m/^\#\s*text\s*=\s*(.+)$/)
        {
            $text = $1;
            $resttext = $text;
        }
        # All node/token lines must have exactly ten columns.
        if($line =~ m/^\d/)
        {
            my @f = split(/\t/, $line);
            while(scalar(@f)<10)
            {
                push(@f, '_');
            }
            splice(@f, 10);
            # Now check the contents of the columns.
            $f[2] = fix_lemma($f[0], $f[2]);
            $f[3] = fix_upos($f[0], $f[3]);
            $f[4] = fix_xpos($f[0], $f[4]);
            $f[5] = fix_feats($f[0], $f[5]);
            ($f[6], $f[7]) = fix_head_deprel($f[0], $f[6], $f[7], $f[3]);
            $f[8] = fix_deps($f[0], $f[8]);
            $line = join("\t", @f);
        }
        if($line =~ m/^\d+-(\d+)\t/)
        {
            $mwtto = $1;
            my @f = split(/\t/, $line);
            # Collect text from FORM. We will use it if there was no # text attribute.
            my @misc = split(/\|/, $f[9]);
            $collected_text .= $f[1];
            # If there was a # text attribute, we will check and fix SpaceAfter=No instead.
            if(defined($resttext))
            {
                my $l = length($f[1]);
                if($f[1] eq substr($resttext, 0, $l))
                {
                    $resttext = substr($resttext, $l);
                    # Now check SpaceAfter=No against the resttext. Exception: end of sentence cannot be verified.
                    unless($resttext eq '')
                    {
                        if($resttext =~ s/^\s+//)
                        {
                            # We just removed leading space(s) from $resttext. There must not be SpaceAfter=No in MISC.
                            @misc = grep {!m/^SpaceAfter=No$/} (@misc);
                            if(scalar(@misc) == 0)
                            {
                                push(@misc, '_');
                            }
                        }
                        else
                        {
                            # No spaces follow the form in $resttext. There must be SpaceAfter=No in MISC.
                            if(scalar(@misc) == 1 && $misc[0] eq '_')
                            {
                                $misc[0] = 'SpaceAfter=No';
                            }
                            elsif(!grep {m/^SpaceAfter=No$/} (@misc))
                            {
                                push(@misc, 'SpaceAfter=No');
                            }
                        }
                    }
                }
                else
                {
                    print STDERR ("WARNING: sentence text comment exists and the form '$f[1]' does not match the rest of the text '$resttext'; giving up.\n");
                    $resttext = undef;
                }
            }
            unless(grep {m/^SpaceAfter=No$/} (@misc))
            {
                $collected_text .= ' ';
            }
            $f[9] = join('|', @misc);
            $line = join("\t", @f);
        }
        # Normal nodes (they may or may not be part of a multi-word token).
        elsif($line =~ m/^\d+\t/)
        {
            my @f = split(/\t/, $line);
            unless(defined($mwtto) && $f[0]<=$mwtto)
            {
                # Collect text from FORM. We will use it if there was no # text attribute.
                my @misc = split(/\|/, $f[9]);
                $collected_text .= $f[1];
                # If there was a # text attribute, we will check and fix SpaceAfter=No instead.
                if(defined($resttext))
                {
                    my $l = length($f[1]);
                    if($f[1] eq substr($resttext, 0, $l))
                    {
                        $resttext = substr($resttext, $l);
                        # Now check SpaceAfter=No against the resttext. Exception: end of sentence cannot be verified.
                        unless($resttext eq '')
                        {
                            if($resttext =~ s/^\s+//)
                            {
                                # We just removed leading space(s) from $resttext. There must not be SpaceAfter=No in MISC.
                                @misc = grep {!m/^SpaceAfter=No$/} (@misc);
                                if(scalar(@misc) == 0)
                                {
                                    push(@misc, '_');
                                }
                            }
                            else
                            {
                                # No spaces follow the form in $resttext. There must be SpaceAfter=No in MISC.
                                if(scalar(@misc) == 1 && $misc[0] eq '_')
                                {
                                    $misc[0] = 'SpaceAfter=No';
                                }
                                elsif(!grep {m/^SpaceAfter=No$/} (@misc))
                                {
                                    push(@misc, 'SpaceAfter=No');
                                }
                            }
                        }
                    }
                    else
                    {
                        print STDERR ("WARNING: sentence text comment exists and the form '$f[1]' does not match the rest of the text '$resttext'; giving up.\n");
                        $resttext = undef;
                    }
                }
                unless(grep {m/^SpaceAfter=No$/} (@misc))
                {
                    $collected_text .= ' ';
                }
                $f[9] = join('|', @misc);
            }
            else # MISC of words within a multi-word token must not contain SpaceAfter=No
            {
                my @misc = split(/\|/, $f[9]);
                @misc = grep {!m/^SpaceAfter=No$/} (@misc);
                if(scalar(@misc) == 0)
                {
                    push(@misc, '_');
                }
                $f[9] = join('|', @misc);
            }
            $line = join("\t", @f);
        }
        $line .= "\n";
    }
    # Generate sentence text comment if it is not present.
    if(!defined($text))
    {
        $collected_text =~ s/\s+$//;
        unshift(@sentence, "\# text = $collected_text\n");
    }
    # Generate sentence id if it is not present.
    if(!defined($sentid))
    {
        unshift(@sentence, "\# sent_id = $isent\n");
    }
    # Optionally (with the --connect-to-root switch) add 0:root enhanced relations
    # untill all nodes are reachable from 0.
    if($connect_to_root)
    {
        @sentence = make_all_nodes_reachable(@sentence);
    }
    # Print the fixed sentence.
    print(join('', @sentence));
}



#------------------------------------------------------------------------------
# Makes sure that lemma is valid.
#------------------------------------------------------------------------------
sub fix_lemma
{
    my $id = shift;
    my $lemma = shift;
    # Multi-word token must have the lemma empty.
    if($id =~ m/^\d+-\d+$/)
    {
        return '_';
    }
    # Empty node can have the lemma empty but it is not required.
    if($id =~ m/^\d+\.\d+$/ && $lemma eq '_')
    {
        return $lemma;
    }
    # Normal nodes and empty nodes with non-empty lemmas.
    # Make sure that LEMMA does not contain leading or trailing spaces.
    $lemma =~ s/^\s+//;
    $lemma =~ s/\s+$//;
    $lemma = '_' if($lemma eq '');
    return $lemma;
}



#------------------------------------------------------------------------------
# Makes sure that UPOS is valid.
#------------------------------------------------------------------------------
sub fix_upos
{
    my $id = shift;
    my $upos = shift;
    # Multi-word token must have the UPOS empty.
    if($id =~ m/^\d+-\d+$/)
    {
        return '_';
    }
    # Empty node can have the UPOS empty but it is not required.
    if($id =~ m/^\d+\.\d+$/ && $upos eq '_')
    {
        return $upos;
    }
    # Make sure that UPOS is from the prescribed inventory.
    if($upos !~ m/^(NOUN|PROPN|PRON|ADJ|DET|NUM|VERB|AUX|ADV|ADP|SCONJ|CCONJ|PART|INTJ|SYM|PUNCT|X)$/)
    {
        $upos = 'X';
    }
    return $upos;
}



#------------------------------------------------------------------------------
# Makes sure that XPOS is valid.
#------------------------------------------------------------------------------
sub fix_xpos
{
    my $id = shift;
    my $xpos = shift;
    # Multi-word token must have the XPOS empty.
    if($id =~ m/^\d+-\d+$/)
    {
        return '_';
    }
    # Empty node can have the XPOS empty but it is not required.
    if($id =~ m/^\d+\.\d+$/ && $xpos eq '_')
    {
        return $xpos;
    }
    # Normal nodes and empty nodes with non-empty XPOS.
    # Make sure that XPOS does not contain leading or trailing spaces.
    $xpos =~ s/^\s+//;
    $xpos =~ s/\s+$//;
    $xpos = '_' if($xpos eq '');
    return $xpos;
}



#------------------------------------------------------------------------------
# Makes sure that FEATS is valid.
#------------------------------------------------------------------------------
sub fix_feats
{
    my $id = shift;
    my $feats = shift;
    # Multi-word token must have the FEATS empty.
    if($id =~ m/^\d+-\d+$/)
    {
        return '_';
    }
    # Empty node can have the FEATS empty but it is not required.
    if($id =~ m/^\d+\.\d+$/ && $feats eq '_')
    {
        return $feats;
    }
    # Normal nodes and empty nodes with non-empty FEATS.
    # Make sure that FEATS is either '_' or it follows the prescribed pattern.
    if($feats ne '_')
    {
        my @feats = split(/\|/, $feats);
        # Each element must be a name=value pair.
        # Feature names start with [A-Z] and contain [A-Za-z].
        # Same for feature values, but [0-9] is also allowed there, and comma (',') may separate multi-values.
        # Feature names can additionally contain square brackets with layer ("[psor]").
        foreach my $fv (@feats)
        {
            my ($f, $v);
            if($fv =~ m/^(.+)=(.+)$/)
            {
                $f = $1;
                $v = $2;
            }
            else
            {
                $f = $fv;
                $v = 'Yes';
            }
            $f =~ s/[^A-Za-z\[\]]//g;
            $f =~ s/^(.)/\u\1/;
            $f = 'X'.$f if($f !~ m/^[A-Z]/);
            $v =~ s/[^A-Za-z0-9,]//g;
            $v =~ s/^(.)/\u\1/;
            $v = 'X'.$v if($v !~ m/^[A-Z0-9]/);
            # If the value is a disjunction of multiple values, these must be sorted.
            if($v =~ m/,/)
            {
                my @v = split(/,/, $v);
                @v = sort(@v);
                $v = join(',', @v);
            }
            $fv = "$f=$v";
        }
        @feats = sort {lc($a) cmp lc($b)} (@feats);
        $feats = join('|', @feats);
    }
    return $feats;
}



#------------------------------------------------------------------------------
# Makes sure that HEAD and DEPREL are valid.
#------------------------------------------------------------------------------
sub fix_head_deprel
{
    my $id = shift;
    my $head = shift;
    my $deprel = shift;
    my $upos = shift; # optional UPOS tag of the dependent; we will check whether it is PUNCT
    # Multi-word tokens and empty nodes must have HEAD and DEPREL empty.
    if($id =~ m/^\d+(-|\.)\d+$/)
    {
        return ('_', '_');
    }
    # Make sure that HEAD is numeric and DEPREL is not empty.
    if($head !~ m/^\d+$/)
    {
        # We will attach node 1 to node 0, and all other nodes to 1.
        # This will produce a valid tree if we apply it to all words,
        # i.e., none of them had a valid parent before. Otherwise, it
        # may not work as we may be introducing cycles!
        if($id == 1)
        {
            $head = 0;
            $deprel = 'root';
        }
        else
        {
            $head = 1;
            if($deprel eq '_' || $deprel eq '')
            {
                if(defined($upos) && $upos eq 'PUNCT')
                {
                    $deprel = 'punct';
                }
                else
                {
                    $deprel = 'dep';
                }
            }
        }
    }
    # Make sure that DEPREL contains only allowed strings (but no language-specific list is checked).
    my $udeprels = 'nsubj|obj|iobj|csubj|ccomp|xcomp|obl|vocative|expl|dislocated|advcl|advmod|discourse|aux|cop|mark|nmod|appos|nummod|acl|amod|det|clf|case|conj|cc|fixed|flat|compound|list|parataxis|orphan|goeswith|reparandum|punct|root|dep';
    if($deprel =~ m/^root(:|$)/ && $head != 0)
    {
        $deprel = 'dep';
    }
    if($deprel !~ m/^root(:|$)/ && $head == 0)
    {
        $deprel = 'root';
    }
    if($deprel !~ m/^($udeprels)(:[a-z]+)?$/)
    {
        # First attempt: remove the subtype.
        $deprel =~ s/:.*//;
    }
    if($deprel !~ m/^($udeprels)(:[a-z]+)?$/)
    {
        # Second attempt: take 'dep'.
        $deprel = 'dep';
    }
    return ($head, $deprel);
}



#------------------------------------------------------------------------------
# Makes sure that DEPS is valid.
#------------------------------------------------------------------------------
sub fix_deps
{
    my $id = shift;
    my $deps = shift;
    # Multi-word tokens must have DEPS empty.
    if($id =~ m/^\d+-\d+$/)
    {
        return '_';
    }
    # Empty DEPS is OK. But if not empty, then certain rules must be followed.
    unless($deps eq '_')
    {
        my @deps = split(/\|/, $deps);
        # Remove self-loops.
        @deps = grep {my $h; if(m/^(\d+(?:\.\d+)?):/) {$h = $1;} defined($h) && $h!=$id} (@deps);
        if(scalar(@deps)==0)
        {
            # DEPS was not empty, so there is an enhanced graph and we should not make DEPS empty now.
            push(@deps, '0:root');
        }
        # Make sure that the deps do not contain disallowed characters.
        foreach my $dep (@deps)
        {
            my ($h, $d);
            if($dep =~ m/^(\d+(?:\.\d+)?):(.+)$/)
            {
                $h = $1;
                $d = $2;
            }
            else
            {
                $h = 1;
                $d = $dep;
            }
            if($d !~ m/^[a-z]+(:[a-z]+)?(:[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(_[\p{Ll}\p{Lm}\p{Lo}\p{M}]+)*)?(:[a-z]+)?$/)
            {
                # First attempt: just lowercase and remove strange characters.
                $d = lc($d);
                $d =~ s/[^:_a-z\p{Ll}\p{Lm}\p{Lo}\p{M}]//g;
            }
            if($d !~ m/^[a-z]+(:[a-z]+)?(:[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(_[\p{Ll}\p{Lm}\p{Lo}\p{M}]+)*)?(:[a-z]+)?$/)
            {
                # Second attempt: everything after the first colon is simply 'extra'.
                $d =~ s/^([^:]*):.*$/$1:extra/;
            }
            if($d !~ m/^[a-z]+(:[a-z]+)?(:[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(_[\p{Ll}\p{Lm}\p{Lo}\p{M}]+)*)?(:[a-z]+)?$/)
            {
                # Last attempt: just 'dep'.
                $d = 'dep';
            }
            # Finally, if $h is 0, then $d must be root; and  if $h is not 0, then $d must not be root.
            if($h==0 && $d !~ m/^root(:|$)/)
            {
                $d = 'root';
            }
            if($h!=0 && $d =~ m/^root(:|$)/)
            {
                $d = 'dep';
            }
            $dep = "$h:$d";
        }
        # Remove duplicates from @deps.
        my %deps; map {$deps{$_}++} (@deps);
        @deps = keys(%deps);
        @deps = sort
        {
            my @a = split(/:/, $a);
            my @b = split(/:/, $b);
            my $ah = shift(@a);
            my $bh = shift(@b);
            my $r = $ah <=> $bh;
            unless($r)
            {
                my $ad = join(':', @a);
                my $bd = join(':', @b);
                $r = $ad cmp $bd;
            }
            $r
        }
        (@deps);
        $deps = join('|', @deps);
    }
    return $deps;
}



#------------------------------------------------------------------------------
# For each node of the enhanced graph, finds the set of nodes from which the
# node is reachable, i.e., the set of its enhanced ancestors. If node 0 (the
# virtual root) is not among them, adds gradually 0:root relations until all
# nodes are reachable from the root.
#------------------------------------------------------------------------------
sub make_all_nodes_reachable
{
    my @sentence = @_;
    my @nodes = grep {m/^\d+(\.\d+)?\t/} (@sentence);
    my %unreachable;
    my %parents;
    foreach my $node (@nodes)
    {
        my @f = split(/\t/, $node);
        my $id = $f[0];
        $unreachable{$id}++;
        my $deps = $f[8];
        my @nodeparents = map {m/^(.+):/; $1} (split(/\|/, $deps));
        my %nodeparents; map {$nodeparents{$_}++} (@nodeparents);
        @nodeparents = keys(%nodeparents);
        $parents{$id} = \@nodeparents;
    }
    # Find nodes that are reachable from 0.
    my %reachable;
    $reachable{'0'}++;
    my %attach_to_root; # nodes that will have to be attached to 0
    while(1)
    {
        my @unreachable = sort(keys(%unreachable));
        last if(scalar(@unreachable)==0);
        my $found_new = 0;
        foreach my $id (@unreachable)
        {
            foreach my $parent (@{$parents{$id}})
            {
                if($reachable{$parent})
                {
                    $found_new++;
                    $reachable{$id}++;
                    delete($unreachable{$id});
                    last;
                }
            }
        }
        # If we cannot find a new way how to make an unreachable node reachable,
        # try attaching the first unreachable node directly to the root.
        # We will first try to attach to root the first node (by id, lexicographically).
        # There might be better solutions, e.g., if the unreachable nodes form
        # a component whose root is the last node (with highest id). But we are
        # not trying to find the optimal solution. We just want to make the file
        # valid.
        @unreachable = sort(keys(%unreachable));
        if(scalar(@unreachable)>0 && !$found_new)
        {
            my $node = shift(@unreachable);
            $attach_to_root{$node}++;
            $reachable{$node}++;
            delete($unreachable{$node});
            $found_new = 1;
        }
    }
    # Now take the nodes that should be attached to the root and attach them there.
    foreach my $line (@sentence)
    {
        if($line =~ m/^\d+(\.\d+)?\t/)
        {
            my @f = split(/\t/, $line);
            if($attach_to_root{$f[0]})
            {
                my @deps = split(/\|/, $f[8]);
                @deps = () if(scalar(@deps)==1 && $deps[0] eq '_');
                unshift(@deps, '0:root');
                $f[8] = join('|', @deps);
            }
            $line = join("\t", @f);
        }
    }
    return @sentence;
}
