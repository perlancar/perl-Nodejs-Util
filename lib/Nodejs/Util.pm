package Nodejs::Util;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(get_nodejs_path nodejs_available);

our %SPEC;

my %arg_all = (
    all => {
        schema => 'bool',
        summary => 'Find all node.js instead of the first found',
        description => <<'_',

If this option is set to true, will return an array of paths intead of paths.

_
    },
);

$SPEC{get_nodejs_path} = {
    v => 1.1,
    summary => 'Check the availability of Node.js executable in PATH',
    description => <<'_',

Return the path to executable or undef if none is available. Node.js is usually
installed as 'node' or 'nodejs'.

_
    args => {
        %arg_all,
    },
    result_naked => 1,
};
sub get_nodejs_path {
    require File::Which;
    require IPC::System::Options;

    my %args = @_;

    my @paths;
    for my $name (qw/nodejs node/) {
        my $path = File::Which::which($name);
        next unless $path;

        # check if it's really nodejs
        my $out = IPC::System::Options::readpipe(
            $path, '-e', 'console.log(1+1)');
        if ($out =~ /\A2\n?\z/) {
            return $path unless $args{all};
            push @paths, $path;
        } else {
            #say "D:Output of $cmd: $out";
        }
    }
    return undef unless @paths;
    \@paths;
}

$SPEC{nodejs_available} = {
    v => 1.1,
    summary => 'Check the availability of Node.js',
    description => <<'_',

This is a more advanced alternative to `get_nodejs_path()`. Will check for
`node` or `nodejs` in the PATH, like `get_nodejs_path()`. But you can also
specify minimum version (and other options in the future). And it will return
more details.

Will return status 200 if everything is okay. Actual result will return the path
to executable, and result metadata will contain extra result like detected
version in `func.version`.

Will return satus 412 if something is wrong. The return message will tell the
reason.

_
    args => {
        min_version => {
            schema => 'str*',
        },
        # XXX extra_paths (but we can localize $ENV{PATH} to accomplish this)
        %arg_all,
    },
};
sub nodejs_available {
    require IPC::System::Options;

    my %args = @_;
    my $all = $args{all};

    my $paths = get_nodejs_path(all => 1);
    defined $paths or return [412, "node.js not detected in PATH"];

    my $res = [200, "OK"];
    my @filtered_paths;
    my @versions;
    my @errors;

    for my $path (@$paths) {
        my $v;
        if ($args{min_version}) {
            my $out = IPC::System::Options::readpipe(
                $path, '-v');
            $out =~ /^(v\d+\.\d+\.\d+)$/ or do {
                push @errors, "Can't recognize output of $path -v: $out";
                next;
            };
            # node happens to use semantic versioning, which we can parse using
            # version.pm
            $v = version->parse($1);
            $v >= version->parse($args{min_version}) or do {
                push @errors, "Version of $path less than $args{min_version}";
                next;
            };
        }
        push @filtered_paths, $path;
        push @versions, "$v";
    }

    $res->[2]                 = $all ? \@filtered_paths : $filtered_paths[0];
    $res->[3]{'func.path'}    = $all ? \@filtered_paths : $filtered_paths[0];
    $res->[3]{'func.version'} = $all ? \@versions       : $versions[0];
    $res->[3]{'func.errors'}  = \@errors;

    unless (@filtered_paths) {
        $res->[0] = 412;
        $res->[1] = "No eligible node.js found in PATH";
    }

    $res;
}

1;
# ABSTRACT: Utilities related to Node.js

=cut
