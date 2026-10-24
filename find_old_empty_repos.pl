#!/usr/bin/env perl
# Scans the UD_* folders in the current folder. Checks the following:
# - Whether they are old and empty (i.e., candidates for removal).
# - Whether their treebank id is too long (i.e., candidates for renaming).
# Copyright © 2026 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Cwd;

my $path = getcwd();
opendir(DIR, $path) or die("Cannot read folder '$path': $!");
my @folders = grep {-d "$path/$_" && m/^UD_[A-Za-z_]+-[A-Za-z]+$/} (readdir(DIR));
closedir(DIR);
my @records;
my @lengths; # number of treebanks for each tcode length
foreach my $f (@folders)
{
    my $tcode = '';
    if($f =~ m/^UD_[A-Za-z_]+-([A-Za-z]+)$/)
    {
        $tcode = lc($1);
    }
    my $tcodelength = length($tcode);
    chdir("$path/$f") or die("Cannot change to folder '$path/$f': $!");
    # Assume the repository is already in the correct branch (dev).
    # Get the oldest commit in the history of this branch.
    my $gitlog = `git log --date=short --format="%ad | %an | %s" | tail -n 1`;
    $gitlog =~ s/\r?\n$//;
    my ($date, $committer, $message) = split(/ \| /, $gitlog);
    chdir($path);
    # Are there any data? Get the number of CoNLL-U files.
    opendir(DIR, "$path/$f") or die("Cannot read folder '$path/$f': $!");
    my @conllufiles = grep {-f "$path/$f/$_" && m/\.conllu$/} (readdir(DIR));
    closedir(DIR);
    my $size = scalar(@conllufiles);
    print("$date\t$size\t$f\t$committer\t$message\tlen($tcode) == $tcodelength\n");
    push(@records, [$f, $date, $committer, $message, $size, $tcode, $tcodelength]);
    $lengths[$tcodelength]++;
}
# Print the oldest repositories that are still empty.
@records = sort
{
    my $r = $a->[1] cmp $b->[1];
    unless($r)
    {
        $r = $a->[0] cmp $b->[0];
    }
    $r
}
(@records);
my @filtered = grep {$_->[4] == 0} (@records);
print("\nOldest repositories that are still empty:\n");
for(my $i = 0; $i<20; $i++)
{
    print("$filtered[$i][0]\t$filtered[$i][1]\n");
}
# Print the repositories with the longest treebank code.
@records = sort
{
    my $r = $b->[6] <=> $a->[6];
    unless($r)
    {
        $r = $a->[0] cmp $b->[0];
    }
    $r
}
(@records);
print("\nRepositories with longest treebank code:\n");
for(my $i = 0; $i<20; $i++)
{
    print("$records[$i][0]\t$records[$i][1]\t$records[$i][6]\n");
}
print("\n");
print("tcode length : number of treebanks:\t");
my @ln;
for(my $i = 0; $i <= $#lengths; $i++)
{
    if($lengths[$i] > 0)
    {
        push(@ln, "$i:$lengths[$i]");
    }
}
print(join(', ', @ln), "\n");
