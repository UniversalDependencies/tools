#!/usr/bin/env perl
# Compares tokenization and word segmentation of two CoNLL-U files. Assumes
# that no normalization was performed, that is, the sequence of non-whitespace
# characters is identical on both sides.
# Copyright © 2018 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

# Usage: Merge gold file with lemmas predicted by UDPipe in the shared task:
# tools/conllu-align-tokens.pl UD_Turkish-PUD/tr_pud-ud-test.conllu media/conll17-ud-test-2017-05-09/UFAL-UDPipe-1-2/2017-05-15-02-00-38/output/tr_pud.conllu

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

# One file is considered gold standard, the other is a system's output.
my $goldpath = $ARGV[0];
my $syspath = $ARGV[1];
open(GOLD, $goldpath) or die("Cannot read $goldpath: $!");
open(SYS, $syspath) or die("Cannot read $syspath: $!");
my $gli = 0; # gold line number
my $sli = 0; # system line number
my $gboff = 0;
my $gbuffer = '';
my $sbuffer = '';
while(my $goldline = <GOLD>)
{
    $gli++;
    my $new_gold_token_read = 0;
    my @gf = ();
    # Sentence-level comments start with '#'. Pass through gold comments, ignore system comments.
    # Empty nodes of the enhanced representation start with decimal numbers. Pass through gold, ignore system.
    # Empty line terminates every sentence. Pass through gold, ignore system.
    # Multi-word token.
    if($goldline =~ m/^(\d+)-(\d+)\t/)
    {
        my $from = $1;
        my $to = $2;
        @gf = split(/\t/, $line);
        my $gform = $gf[1];
        # Word forms may contain spaces but we are interested in non-whitespace characters only.
        $gform =~ s/\s//g;
        $gbuffer .= $gform;
        # Read the syntactic words that belong to this multi-word token.
        for(my $i = $from; $i <= $to; $i++)
        {
            print($goldline);
            $goldline = <$fh>;
            $gli++;
        }
        $new_gold_token_read = 1;
    }
    # Single-word token.
    elsif($goldline =~ m/^\d+\t/)
    {
        @gf = split(/\t/, $goldline);
        my $gform = $gf[1];
        # Word forms may contain spaces but we are interested in non-whitespace characters only.
        $gform =~ s/\s//g;
        $gbuffer .= $gform;
        $new_gold_token_read = 1;
    }
    if($new_gold_token_read)
    {
        my $sysline;
        while(length($gbuffer) > length($sbuffer))
        {
            my $nr = read_token_to_buffer(*SYS, \$sli, \$sbuffer, \$sysline);
            if($nr == 0)
            {
                die("The system output ended prematurely. Gold line no. $gli, offset $gboff, buffer '$gbuffer'. System line no. $sli, buffer '$sbuffer'.");
            }
        }
        # If the system buffer equals to the gold buffer, we are synchronized and may go on.
        if($sbuffer eq $gbuffer)
        {
            ###!!! The fact that the two buffers match does not entail that the last words match.
            ###!!! Nevertheless, we will now assume that it is the case, and copy the system lemma to the gold line.
            my @sf = split(/\t/, $sysline);
            if(defined($sf[2]) && $sf[2] ne '')
            {
                $gf[2] = $sf[2];
                $goldline = join("\t", @gf);
            }
            $gboff += length($gbuffer);
            $gbuffer = '';
            $sbuffer = '';
        }
        # If the gold buffer is a prefix of the system buffer, eat the prefix and go to the next gold token.
        elsif(substr($sbuffer, 0, length($gbuffer)) eq $gbuffer)
        {
            my $gbl = length($gbuffer);
            $gboff += $gbl;
            $gbuffer = '';
            $sbuffer = substr($sbuffer, $gbl);
        }
        # Otherwise there must be a mismatch in the non-whitespace characters.
        else
        {
            die("Non-whitespace character mismatch. Gold line no. $gli, offset $gboff, buffer '$gbuffer'. System line no. $sli, buffer '$sbuffer'.");
        }
    }
    print($goldline);
}
close(GOLD);
close(SYS);



#------------------------------------------------------------------------------
# Reads next token from a CoNLL-U file. Adds it to a buffer. Returns the number
# of non-whitespace characters read. (Returns 0 if there are no more tokens in
# the file. The same would happen if there were an empty string instead of the
# word form, i.e., not even the underscore character, but such file would not
# be valid CoNLL-U.)
#------------------------------------------------------------------------------
sub read_token_to_buffer
{
    my $fh = shift; # the handle of the open file
    my $li = shift; # reference to the current line number
    my $buffer = shift; # reference to the buffer
    my $tokenline = shift; # reference to the variable where the line with the last token should be stored
    # Read the next system token.
    my $form;
    while(my $line = <$fh>)
    {
        ${$li}++;
        # Multi-word token.
        if($line =~ m/^(\d+)-(\d+)\t/)
        {
            my $from = $1;
            my $to = $2;
            my @f = split(/\t/, $line);
            $form = $f[1];
            # Word forms may contain spaces but we are interested in non-whitespace characters only.
            $form =~ s/\s//g;
            ${$tokenline} = $line;
            # Read the syntactic words that belong to this multi-word token.
            for(my $i = $from; $i <= $to; $i++)
            {
                $line = <$fh>;
                ${$li}++;
            }
            last;
        }
        # Single-word token.
        elsif($line =~ m/^\d+\t/)
        {
            my @f = split(/\t/, $line);
            $form = $f[1];
            # Word forms may contain spaces but we are interested in non-whitespace characters only.
            $form =~ s/\s//g;
            ${$tokenline} = $line;
            last;
        }
    }
    ${$buffer} .= $form;
    return length($form);
}
