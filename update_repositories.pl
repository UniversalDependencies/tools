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
my @folders = sort(grep {-d "$path/$_" && m/^UD_/} (readdir(DIR)));
closedir(DIR);
my $n = scalar(@folders);
# Update the docs folder.
print("docs\n");
chdir("$path/docs") or die("Cannot read '$path/docs': $!");
# I used to call "git pull --no-edit" to prevent an editor from launching but my git for Windows lacks the option.
system("git checkout pages-source");
system("git pull");
# Update the tools folder.
print("tools\n");
chdir("$path/tools") or die("Cannot read '$path/tools': $!");
# I used to call "git pull --no-edit" to prevent an editor from launching but my git for Windows lacks the option.
system("git checkout master");
system("git pull");
# Update individual treebank folders.
my @unclean_folders;
foreach my $folder (@folders)
{
    print("$folder\n");
    chdir("$path/$folder") or die("Cannot read '$path/$folder': $!");
    # I used to call "git pull --no-edit" to prevent an editor from launching but my git for Windows lacks the option.
    system("git checkout dev");
    system("git pull");
    if(detect_unclean_status())
    {
        print("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX UNCLEAN GIT STATUS XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\n");
        sleep(10);
        push(@unclean_folders, $folder);
    }
}
print("Checked $n UD treebank folders.\n");
my $n_unclean = scalar(@unclean_folders);
if($n_unclean)
{
    print("The following $n_unclean folders are not clean (unpushed commits or untracked files):\n");
    print(join(', ', @unclean_folders), "\n");
}



#------------------------------------------------------------------------------
# If run inside a git repository, checks whether there are any issues with its
# status: Either there are untracked files (we must remove them before releasing
# the repository) or there are commits not pushed to GitHub (we probably ran
# pull before coming here, but pull would not do anything with local commits
# (except if there is conflict), and those may render the repository invalid),
# or there are even uncommitted changes.
#------------------------------------------------------------------------------
sub detect_unclean_status
{
    # if git status --ignored | grep -P '(Untracked files|Ignored files|Changes|ahead of)' > /dev/null ; then echo XXX ; fi
    # The --ignored option ensures that we detect untracked files even if they
    # match .gitignore. We do not want to release those either.
    my $command = "git status --ignored";
    open(my $in, "$command |") or die("Cannot read from pipe '$command': $!");
    while(<$in>)
    {
        if(m/(Untracked files|Ignored files|Changes|ahead of)/)
        {
            close($in);
            return 1;
        }
    }
    close($in);
    return 0;
}
