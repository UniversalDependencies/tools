#!/usr/bin/env perl
# Visits all immediate subfolders of the current folder. If they are git repos,
# prints their remote URL to STDOUT.
# Copyright © 2024 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Cwd;

my $path = getcwd();
opendir(DIR, $path) or die("Cannot read folder '$path': $!");
my @subfolders = grep {-d $_ && !m/^\.\.?$/} (readdir(DIR));
closedir(DIR);
foreach my $sf (@subfolders)
{
    chdir("$path/$sf") or die("Cannot change to folder '$sf': $!");
    my $origin;
    open(GIT, "git remote -v |") or die("Cannot read from git: $!");
    while(<GIT>)
    {
        if(m/^origin\s+(\S+)/)
        {
            $origin = $1;
        }
    }
    close(GIT);
    if(defined($origin))
    {
        print("$origin\n");
        chdir("$path/00") or die("Cannot change to folder '00': $!");
        system("git clone $origin");
        chdir("$path/00/$sf");
        # Changing to dev will not work for docs, docs-auto, tools, and LICENSE.
        system("git checkout dev");
    }
    else
    {
        print("CANNOT FIND REMOTE ORIGIN FOR '$sf'\n");
    }
}
