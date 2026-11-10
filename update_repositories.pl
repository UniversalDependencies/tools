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
use Getopt::Long;
# We need to tell Perl where to find my UD and graph modules.
BEGIN
{
    use Cwd;
    my $path = $0;
    my $currentpath = getcwd();
    $currentpath =~ s/\r?\n$//;
    $libpath = $currentpath;
    if($path =~ m:/:)
    {
        $path =~ s:/[^/]*$:/:;
        chdir($path);
        $libpath = getcwd();
        chdir($currentpath);
    }
    $libpath =~ s/\r?\n$//;
    #print STDERR ("libpath=$libpath\n");
}
use lib $libpath;
use udlib;

sub usage
{
    print STDERR ("Usage: perl update_repositories.pl\n");
    print STDERR ("       perl update_repositories.pl --merge\n");
    print STDERR ("       without --merge ... checkout correct branch, pull, check status\n");
    print STDERR ("                           not only for UD_* treebanks but also docs and tools\n");
    print STDERR ("       --merge ... merge dev branches of treebanks into master\n");
}

my $merge = 0;
my $datapath = '.';
my $tbklist;
GetOptions
(
    'merge'      => \$merge,    # action merge dev to master (without it, action checkout dev + pull)
    'datapath=s' => \$datapath, # UD_* folders will be sought in this folder
    'tbklist=s'  => \$tbklist   # path to file with treebank list; if defined, only treebanks on the list will be surveyed
);

# We need absolute path because we will be changing the current folder.
$datapath = udlib::absolutize_path($datapath);
my $treebanks = udlib::read_treebank_list($tbklist);
my @folders = udlib::list_and_filter_ud_folders($datapath, $treebanks, 1, 5);

if($merge)
{
    merge_to_master($datapath, @folders);
}
else # default
{
    update_all($datapath, @folders);
}



#------------------------------------------------------------------------------
# Visits docs, tools, and all UD_* folders that exist in the current working
# folder. Makes sure they are checked out to the correct branch, up-to-date
# (pull from GitHub) and clean (no unpushed changes, no untracked files).
#------------------------------------------------------------------------------
sub update_all
{
    my $path = shift; # the root path of Universal Dependencies
    my @folders = @_;
    my $n = scalar(@folders);
    my @unclean_folders;
    # Update the docs folder.
    print("docs\n");
    chdir("$path/docs") or die("Cannot read '$path/docs': $!");
    git_checkout('pages-source');
    git_pull();
    if(detect_unclean_status())
    {
        print("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX UNCLEAN GIT STATUS XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\n");
        sleep(10);
        push(@unclean_folders, 'docs');
    }
    # Update the tools folder.
    print("tools\n");
    chdir("$path/tools") or die("Cannot read '$path/tools': $!");
    git_checkout('master');
    git_pull();
    if(detect_unclean_status())
    {
        print("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX UNCLEAN GIT STATUS XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\n");
        sleep(10);
        push(@unclean_folders, 'tools');
    }
    # Update individual treebank folders.
    foreach my $folder (@folders)
    {
        print("$folder\n");
        chdir("$path/$folder") or die("Cannot read '$path/$folder': $!");
        git_checkout('dev');
        git_pull();
        if(detect_unclean_status())
        {
            print("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX UNCLEAN GIT STATUS XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\n");
            sleep(10);
            push(@unclean_folders, $folder);
        }
    }
    print("Checked $n UD treebank folders + docs and tools.\n");
    my $n_unclean = scalar(@unclean_folders);
    if($n_unclean)
    {
        print("The following $n_unclean folders are not clean (unpushed changes or untracked files):\n");
        print(join(', ', @unclean_folders), "\n");
    }
    else
    {
        print("The git status of all checked folders is clean.\n");
    }
}



#------------------------------------------------------------------------------
# Visits all UD_* folders (provided as a parameter list) and merges their dev
# branch to master, then checks out dev again.
#------------------------------------------------------------------------------
sub merge_to_master
{
    my $path = shift; # the root path of Universal Dependencies
    my @folders = @_;
    my $n = scalar(@folders);
    my @unclean_folders;
    # Update individual treebank folders.
    foreach my $folder (@folders)
    {
        print("$folder\n");
        chdir("$path/$folder") or die("Cannot read '$path/$folder': $!");
        git_checkout('master');
        git_pull();
        git_merge('dev');
        git_push();
        if(detect_unclean_status())
        {
            print("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX UNCLEAN GIT STATUS XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\n");
            sleep(10);
            push(@unclean_folders, $folder);
        }
        git_checkout('dev');
    }
    print("Merged dev of $n UD treebank folders into master.\n");
    my $n_unclean = scalar(@unclean_folders);
    if($n_unclean)
    {
        print("The following $n_unclean folders are not clean:\n");
        print(join(', ', @unclean_folders), "\n");
    }
    else
    {
        print("The git status of all merged folders is clean.\n");
    }
}



#------------------------------------------------------------------------------
# Calls git checkout on a branch it receives as a parameter. Assumes the
# current working folder is the local clone of the repository.
#------------------------------------------------------------------------------
sub git_checkout
{
    my $branch = shift;
    # Expected output:
    #   Switched to branch '$branch'
    #   Your branch is up to date with 'origin/$branch'.
    system("git checkout $branch >/dev/null 2>&1");
}



#------------------------------------------------------------------------------
# Calls git pull on the current branch in the current working folder (assuming
# it is the local clone of a git repository).
#------------------------------------------------------------------------------
sub git_pull
{
    # I used to call "git pull --no-edit" to prevent an editor from launching but my git for Windows lacks the option.
    # Expected output, option 1:
    #   Already up to date.
    system("git pull >/dev/null 2>&1");
}



#------------------------------------------------------------------------------
# Calls git merge from a branch it receives as a parameter. Assumes the
# current working folder is the local clone of the repository, with the target
# branch checked out.
#------------------------------------------------------------------------------
sub git_merge
{
    my $branch = shift;
    # Expected output, option 1:
    #   Already up to date.
    # Expected output, option 2 (example):
    #   Merge made by the 'ort' strategy.
    #    README.md              |    4 +-
    #    ab_abnc-ud-test.conllu | 2974 ++++++++++++++++++++++++++++++++++++++++
    #    stats.xml              |  362 ++++++++++++-------------
    #    3 files changed, 2485 insertions(+), 855 deletions(-)
    my $command = "git merge $branch --no-edit";
    open(my $in, "$command 2>&1 |") or die("Cannot read from pipe '$command': $!");
    my @output;
    my $ok = 0; ###!!! What about exit status of the git command?
    while(<$in>)
    {
        chomp;
        push(@output, $_);
        if(m/(Already up to date|Merge made)/)
        {
            $ok = 1;
        }
    }
    close($in);
    if(!$ok)
    {
        print("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX MERGE ISSUE XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\n");
        print(join("\n", @output)."\n");
        sleep(10);
    }
}



#------------------------------------------------------------------------------
# Calls git push on the current branch in the current working folder (assuming
# it is the local clone of a git repository).
#------------------------------------------------------------------------------
sub git_push
{
    # Expected output, option 1:
    #   Everything up-to-date
    # Expected output, option 2 (example):
    #   Enumerating objects: 4, done.
    #   Counting objects: 100% (4/4), done.
    #   Delta compression using up to 8 threads
    #   Compressing objects: 100% (2/2), done.
    #   Writing objects: 100% (2/2), 296 bytes | 296.00 KiB/s, done.
    #   Total 2 (delta 1), reused 0 (delta 0), pack-reused 0
    #   remote: Resolving deltas: 100% (1/1), completed with 1 local object.
    #   To github.com:UniversalDependencies/UD_Abkhaz-AbNC.git
    #      260e6ca..eab451f  master -> master
    system("git push >/dev/null 2>&1");
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
    open(my $in, "$command 2>&1 |") or die("Cannot read from pipe '$command': $!");
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
