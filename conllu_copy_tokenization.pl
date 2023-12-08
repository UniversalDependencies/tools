#!/usr/bin/env perl
# Assuming that two CoNLL-U files cover the same sequence of non-whitespace
# characters, this script makes sure that the TARGET file has the same
# tokenization and word segmentation as the SOURCE file. Everything else in
# the target file is left as intact as possible. There are some exceptions
# though:
# - If a token is split, it is not clear what the morphological and syntactic
#   annotation of the parts should be. We duplicate the current morphological
#   annotation, and we make all non-first parts syntactically dependent on the
#   first part.
# - If two or more tokens are merged, it is not clear what the morphological
#   and syntactic annotation of the resulting token should be. At present, we
#   simply retain the morphological annotation of the first part. In syntax,
#   we take the first parent that lies outside the span being merged. Any
#   children of any of the merged nodes will depend on the resulting node.
# - In case of merging tokens that are in different sentences, the sentences
#   have to be merged, too. We do not touch sentence segmentation otherwise.
# Copyright © 2018, 2022 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

# Usage: Project tokenization and word segmentation predicted by UDPipe to a file
# where we have other annotations that we do not want to lose:
# conllu_copy_tokenization.pl udpipe-output.conllu tgtfile.conllu

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

if(scalar(@ARGV) != 2)
{
    die("Usage: $0 src.conllu tgt.conllu > tgt-retokenized.conllu");
}
my $srcpath = $ARGV[0];
my $tgtpath = $ARGV[1];
open(TGT, $tgtpath) or die("Cannot read $tgtpath: $!");
open(SRC, $srcpath) or die("Cannot read $srcpath: $!");
my $tli = 0; # tgt line number
my $sli = 0; # src line number
my $tboff = 0;
my $tbuffer = '';
my $sbuffer = '';
my @tgtlines; # token/word lines covering $tbuffer
my @srclines; # token/word lines covering $sbuffer
my $lasttgtid = 0; # last regular node (inside or outside MWT) id in tgt, that was actually printed
while(my $tgtline = <TGT>)
{
    $tli++;
    push(@tgtlines, $tgtline);
    my $new_tgt_token_read = 0;
    # Sentence-level comments start with '#'. Pass through tgt comments, ignore src comments.
    # Empty nodes of the enhanced representation start with decimal numbers. Pass through tgt, ignore src.
    # Empty line terminates every sentence. Pass through tgt, ignore src.
    # Multi-word token.
    if($tgtline =~ m/^(\d+)-(\d+)\t/)
    {
        my $from = $1;
        my $to = $2;
        my @tf = split(/\t/, $tgtline);
        my $tform = $tf[1];
        # Word forms may contain spaces but we are interested in non-whitespace characters only.
        $tform =~ s/\s//g;
        $tbuffer .= $tform;
        # Read the syntactic words that belong to this multi-word token.
        for(my $i = $from; $i <= $to; $i++)
        {
            $tgtline = <TGT>;
            $tli++;
            push(@tgtlines, $tgtline);
        }
        $new_tgt_token_read = 1;
    }
    # Single-word token.
    elsif($tgtline =~ m/^\d+\t/)
    {
        my @tf = split(/\t/, $tgtline);
        my $tform = $tf[1];
        # Word forms may contain spaces but we are interested in non-whitespace characters only.
        $tform =~ s/\s//g;
        $tbuffer .= $tform;
        $new_tgt_token_read = 1;
    }
    # End of sentence.
    elsif($tgtline =~ m/^\s*$/)
    {
        $lasttgtid = 0;
    }
    if($new_tgt_token_read)
    {
        while(length($tbuffer) > length($sbuffer))
        {
            my $nr = read_token_to_buffer(*SRC, \$sli, \$sbuffer, \@srclines);
            if($nr == 0)
            {
                die("The src output ended prematurely. Tgt line no. $tli, offset $tboff, buffer '$tbuffer'. Src line no. $sli, buffer '$sbuffer'.");
            }
        }
        # If the src buffer equals to the tgt buffer, we are synchronized and may go on.
        if($sbuffer eq $tbuffer)
        {
            # The two buffers span the same non-whitespace characters of the
            # surface text but their tokenization differs. Merge the src and
            # the tgt lines. Tgt lines are multi-word token lines or single-
            # word token lines. They do not include sentence-level comments or
            # empty nodes; those have been printed immediately when encountered.
            # Similarly, src lines should be token lines but not comments or
            # empty nodes, which have been discarded.
            ###!!! This actually means that empty nodes may now be out of place!
            # The simplest case: There is one line on each side. Just take the
            # target line.
            if(scalar(@srclines) == 1 && scalar(@tgtlines) == 1)
            {
                # We may have to adjust the node id if there were token splits
                # in this sentence.
                my @tf = split(/\t/, $tgtlines[0]);
                # Sanity check: This should be a regular node, not a multi-word
                # token interval line.
                if($tf[0] =~ m/-/)
                {
                    die("Regular node expected, found '$tf[0]'");
                }
                $tf[0] = ++$lasttgtid;
                $tgtlines[0] = join("\t", @tf);
                @srclines = ();
            }
            # Sanity check: Zero source lines would be an internal error. We
            # should have waited with consuming the previous source lines.
            elsif(scalar(@srclines) == 0)
            {
                my $nt = scalar(@tgtlines);
                die("Both buffers have the same contents '$sbuffer', there are $nt target lines but no source line covering the buffer (sli=$sli, tli=$tli)");
            }
            # If there are multiple source lines, copy them to the target.
            # We also get here if there is 1 source line but multiple target lines.
            # It should not happen that there are no target lines.
            else
            {
                # Before copying the source line to target, copy annotation
                # that should be preserved from target to source.
                ###!!! We do not know how to distribute the original annotation
                ###!!! to the new tokens, so we will simply take the annotation
                ###!!! from the first original token and distribute it to all
                ###!!! new tokens.
                foreach my $tgtline (@tgtlines)
                {
                    if($tgtline =~ m/^\d+\t/)
                    {
                        $tgtline =~ s/\r?\n$//;
                        my @tf = split(/\t/, $tgtline);
                        my @tmisc = grep {!m/^(_|SpaceAfter=No)$/} (split(/\|/, $tf[9]));
                        foreach my $srcline (@srclines)
                        {
                            $srcline =~ s/\r?\n$//;
                            my @sf = split(/\t/, $srcline);
                            if($sf[0] =~ m/^(\d+)-(\d+)$/)
                            {
                                my $diff = $2-$1;
                                $sf[0] = ($lasttgtid+1).'-'.($lasttgtid+1+$diff);
                            }
                            else # regular node
                            {
                                $sf[0] = ++$lasttgtid;
                            }
                            $sf[2] = $tf[2]; # lemma
                            $sf[3] = $tf[3]; # upos
                            $sf[4] = $tf[4]; # xpos
                            $sf[5] = $tf[5]; # feats
                            ###!!! At present we assume that there is no syntactic annotation yet.
                            ###!!! If there is such annotation, then we not only must decide about
                            ###!!! the newly created tokens but we also may have to renumber the
                            ###!!! head references elsewhere in the sentence.
                            $sf[6] = '_'; # head
                            $sf[7] = '_'; # deprel
                            $sf[8] = '_'; # deps
                            # Copy most of MISC from tgt. Only SpaceAfter=No should be adjusted
                            # to the new tokenization.
                            my @misc = @tmisc;
                            if(grep {m/^SpaceAfter=No$/} (split(m/\|/, $sf[9])))
                            {
                                push(@misc, 'SpaceAfter=No');
                            }
                            $sf[9] = scalar(@misc) == 0 ? '_' : join('|', @misc);
                            $srcline = join("\t", @sf)."\n";
                        }
                        last;
                    }
                }
                @tgtlines = @srclines;
                @srclines = ();
            }
            $tboff += length($tbuffer);
            $tbuffer = '';
            $sbuffer = '';
        }
        # If the buffers are not identical, then the target buffer must be
        # a prefix of the source buffer. (The opposite is not possible because
        # we read source lines until the source buffer was at least as long as
        # the target buffer.) If this is not the case, report an input error.
        elsif(substr($sbuffer, 0, length($tbuffer)) ne $tbuffer)
        {
            die("Non-whitespace character mismatch. Tgt line no. $tli, offset $tboff, buffer '$tbuffer'. Src line no. $sli, buffer '$sbuffer'.");
        }
    }
    # Flush remaining target lines if there are no source lines waiting to be matched.
    if(scalar(@srclines) == 0)
    {
        foreach my $tl (@tgtlines)
        {
            print($tl);
        }
        @tgtlines = ();
    }
}
close(TGT);
close(SRC);



#------------------------------------------------------------------------------
# Reads next token from a CoNLL-U file. Adds it to a buffer. Returns the number
# of non-whitespace characters read. (Returns 0 if there are no more tokens in
# the file. The same would happen if there were an empty string instead of the
# word form, i.e., not even the underscore character, but such file would not
# be valid CoNLL-U.)
#
# This function is currently used to read the source tokens but not the target
# tokens, those are read directly in the main loop.
#------------------------------------------------------------------------------
sub read_token_to_buffer
{
    my $fh = shift; # the handle of the open file
    my $li = shift; # reference to the current line number
    my $buffer = shift; # reference to the buffer
    my $tokenlines = shift; # reference to array where token and word lines should be stored (other lines are thrown away because this is the source of tokenization, nothing else)
    # Read the next token.
    my $form;
    while(my $line = <$fh>)
    {
        ${$li}++;
        # Multi-word token.
        if($line =~ m/^(\d+)-(\d+)\t/)
        {
            my $from = $1;
            my $to = $2;
            push(@{$tokenlines}, $line);
            my @f = split(/\t/, $line);
            $form = $f[1];
            # Word forms may contain spaces but we are interested in non-whitespace characters only.
            $form =~ s/\s//g;
            # Read the syntactic words that belong to this multi-word token.
            for(my $i = $from; $i <= $to; $i++)
            {
                $line = <$fh>;
                ${$li}++;
                push(@{$tokenlines}, $line);
            }
            last;
        }
        # Single-word token.
        elsif($line =~ m/^\d+\t/)
        {
            push(@{$tokenlines}, $line);
            my @f = split(/\t/, $line);
            $form = $f[1];
            # Word forms may contain spaces but we are interested in non-whitespace characters only.
            $form =~ s/\s//g;
            last;
        }
    }
    ${$buffer} .= $form;
    return length($form);
}
