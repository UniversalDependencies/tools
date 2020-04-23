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
        elsif($line =~ m/^\d+-(\d+)\t/)
        {
            $mwtto = $1;
            my @f = split(/\t/, $line);
            # Make sure that LEMMA, UPOS, XPOS, FEATS, HEAD, DEPREL and DEPS of a multiword token are empty.
            for(my $i = 2; $i <= 8; $i++)
            {
                $f[$i] = '_';
            }
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
            # Make sure that UPOS is not empty.
            if($f[3] eq '_' || $f[3] eq '')
            {
                $f[3] = 'X';
            }
            # Make sure that FEATS is either '_' or it follows the prescribed pattern.
            if($f[5] ne '_')
            {
                my @feats = split(/\|/, $f[5]);
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
                    $fv = "$f=$v";
                }
                @feats = sort {lc($a) cmp lc($b)} (@feats);
                $f[5] = join('|', @feats);
            }
            # Make sure that HEAD is numeric and DEPREL is not empty.
            if($f[6] !~ m/^\d+$/)
            {
                # We will attach node 1 to node 0, and all other nodes to 1.
                # This will produce a valid tree if we apply it to all words,
                # i.e., none of them had a valid parent before. Otherwise, it
                # may not work as we may be introducing cycles!
                if($f[0] == 1)
                {
                    $f[6] = 0;
                    $f[7] = 'root';
                }
                else
                {
                    $f[6] = 1;
                    if($f[7] eq '_' || $f[7] eq '')
                    {
                        $f[7] = 'dep';
                    }
                }
            }
            # Make sure that DEPREL contains only allowed strings (but no language-specific list is checked).
            else
            {
                my $udeprels = 'nsubj|obj|iobj|csubj|ccomp|xcomp|obl|vocative|expl|dislocated|advcl|advmod|discourse|aux|cop|mark|nmod|appos|nummod|acl|amod|det|clf|case|conj|cc|fixed|flat|compound|list|parataxis|orphan|goeswith|reparandum|punct|root|dep';
                if($f[7] =~ m/^root(:|$)/ && $f[6] != 0)
                {
                    $f[7] = 'dep';
                }
                if($f[7] !~ m/^root(:|$)/ && $f[6] == 0)
                {
                    $f[7] = 'root';
                }
                if($f[7] !~ m/^($udeprels)(:[a-z]+)?$/)
                {
                    # First attempt: remove the subtype.
                    $f[7] =~ s/:.*//;
                }
                if($f[7] !~ m/^($udeprels)(:[a-z]+)?$/)
                {
                    # Second attempt: take 'dep'.
                    $f[7] = 'dep';
                }
            }
            $line = join("\t", @f);
        }
        elsif($line =~ m/^\d+\.\d+\t/)
        {
            # Empty nodes must have empty HEAD and DEPREL.
            my @f = split(/\t/, $line);
            $f[6] = '_';
            $f[7] = '_';
            $line = join("\t", @f);
        }
        # For both surface nodes and empty nodes, check the order of deps.
        if($line =~ m/^\d+(\.\d+)?\t/)
        {
            my @f = split(/\t/, $line);
            unless($f[8] eq '_')
            {
                my @deps = split(/\|/, $f[8]);
                # Remove self-loops.
                @deps = grep {my $h; if(m/^(\d+):/) {$h = $1;} defined($h) && $h!=$f[0]} (@deps);
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
                    $dep = "$h:$d";
                }
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
                $f[8] = join('|', @deps);
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
    # Print the fixed sentence.
    print(join('', @sentence));
}
