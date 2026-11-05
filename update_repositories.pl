#!/usr/bin/env perl
# Should be run in the root UD folder. Assumes that all UD treebank repositories,
# as well as docs and tools, are cloned as subfolders of the current folder.
# Makes sure that all repositories have the correct branch checked out and
# up-to-date with GitHub. Reports any extra files that are not under version
# control (these must be removed before the folder is included in a UD release).
# Copyright © 2026 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Cwd;

my $path = getcwd();
opendir(DIR, $path) or die("Cannot read '$path': $!");
my @folders = grep {-d "$path/$_" && m/^UD_/} (readdir(DIR));
closedir(DIR);
my $n = scalar(@folders);
# Update the docs folder.
print("docs\n");
chdir("$path/docs") or die("Cannot read '$path/docs': $!");
system("git checkout pages-source ; git pull --no-edit");
# Update the tools folder.
print("tools\n");
chdir("$path/tools") or die("Cannot read '$path/tools': $!");
system("git checkout master ; git pull --no-edit");
# Update individual treebank folders.
foreach my $folder (@folders)
{
    print("$folder\n");
    chdir("$path/$folder") or die("Cannot read '$path/$folder': $!");
    system("git checkout dev ; git pull --no-edit");
}
