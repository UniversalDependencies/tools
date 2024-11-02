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
scan_path($path);



#------------------------------------------------------------------------------
# Scans subfolders of given path.
#------------------------------------------------------------------------------
sub scan_path
{
    my $path = shift;
    opendir(DIR, $path) or die("Cannot read folder '$path': $!");
    my @subfolders = grep {-d $_ && !m/^\.\.?$/} (readdir(DIR));
    closedir(DIR);
    foreach my $sf (@subfolders)
    {
        print STDERR ("$path/$sf\n");
        chdir("$path/$sf") or die("Cannot change to folder '$sf': $!");
        my $git = is_git_repo();
        if($git)
        {
            my $origin = get_git_url();
            if(defined($origin))
            {
                print("$path/$sf = $origin\n");
            }
            else
            {
                print("$path/$sf = CANNOT FIND REMOTE ORIGIN\n");
            }
        }
        else
        {
            my $svn = is_svn_repo();
            if($svn)
            {
                my $origin = get_svn_url();
                if(defined($origin))
                {
                    print("$path/$sf = $origin\n");
                }
                else
                {
                    print("$path/$sf = CANNOT FIND SVN URL\n");
                }
            }
            else
            {
                print("$path/$sf = NOT A GIT/SVN REPO\n");
                # Scan recursively.
                scan_path("$path/$sf");
            }
        }
    }
}



#------------------------------------------------------------------------------
# Finds out whether the current folder is a git repository.
#------------------------------------------------------------------------------
sub is_git_repo
{
    ###!!! We should examine other possibilities, e.g. that the git command cannot be executed.
    my $status = `git status 2>&1`;
    return $status !~ m/fatal: not a git repository/s;
}



#------------------------------------------------------------------------------
# Finds out whether the current folder is an svn repository.
#------------------------------------------------------------------------------
sub is_svn_repo
{
    ###!!! We should examine other possibilities, e.g. that the svn command cannot be executed.
    my $status = `svn status 2>&1`;
    return $status !~ m/svn: warning:.*is not a working copy/s;
}



#------------------------------------------------------------------------------
# Assuming the current folder is a git repo, figures out its origin URL.
#------------------------------------------------------------------------------
sub get_git_url
{
    my $origin;
    open(GIT, "git remote -v |") or die("Cannot read from git: $!");
    while(<GIT>)
    {
        if(m/^origin\s+(\S+)/)
        {
            $origin = $1;
            last;
        }
    }
    close(GIT);
    return $origin;
}



#------------------------------------------------------------------------------
# Assuming the current folder is an svn repo, figures out its origin URL.
#------------------------------------------------------------------------------
sub get_svn_url
{
    my $origin;
    open(SVN, "svn info |") or die("Cannot read from git: $!");
    while(<SVN>)
    {
        if(m/^URL:\s+(\S+)/)
        {
            $origin = $1;
            last;
        }
    }
    close(SVN);
    return $origin;
}
