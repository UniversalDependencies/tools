#!/usr/bin/env perl
# Adds Parallel: pud to the README of all PUD treebanks.
# Copyright © 2025 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use udlib;

my @folders = udlib::list_ud_folders(); # in the current folder
foreach my $folder (@folders)
{
    next unless($folder =~ m/-PUD$/);
    print("$folder\n");
    # Get the most recent revision of the folder.
    chdir($folder) or die("Cannot change to folder '$folder': $!");
    system('git pull --no-edit');
    opendir(DIR, '.');
    my @files = grep {m/\.conllu/} (readdir(DIR));
    closedir(DIR);
    #my $metadata = udlib::read_readme($folder);
    #my $filename = (-f "$folder/README.txt") ? "$folder/README.txt" : "$folder/README.md";
    #my $contents;
    #open(my $in, $filename) or die("Cannot read '$filename': $!");
    #while(<$in>)
    #{
    #    s/^Parallel:\s*no$/Parallel: pud/;
    #    $contents .= $_;
    #}
    #close($in);
    #open(my $out, ">$filename") or die("Cannot write '$filename': $!");
    #print $out $contents;
    #close($out);
    # Push the changes to GitHub.
    foreach my $f (@files)
    {
        my $contents;
        open(my $in, $f) or die("Cannot read '$f': $!");
        while(<$in>)
        {
            $contents .= $_;
            if(m/^\#\s*sent_id\s*=\s*([nw][0-9]+)$/)
            {
                $contents .= "\# parallel_id = pud/$1\n";
            }
        }
        close($in);
        open(my $out, ">$f") or die("Cannot write '$f': $!");
        print $out $contents;
        close($out);
    }
    system("git commit -a -m 'Added Parallel to README.' ; git push");
    chdir('..');
    print("\n");
}
