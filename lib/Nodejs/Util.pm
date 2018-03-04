package Nodejs::Util;

# DATE
# VERSION

use 5.010001;
use strict 'subs', 'vars';
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(
                       get_nodejs_path
                       nodejs_path
                       nodejs_available
                       system_nodejs
                       nodejs_module_path
               );

our %SPEC;

my %arg_all = (
    all => {
        schema => 'bool',
        summary => 'Find all node.js instead of the first found',
        description => <<'_',

If this option is set to true, will return an array of paths intead of path.

_
    },
);

$SPEC{nodejs_path} = {
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
sub nodejs_path {
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

*get_nodejs_path = \&nodejs_path;

$SPEC{nodejs_available} = {
    v => 1.1,
    summary => 'Check the availability of Node.js',
    description => <<'_',

This is a more advanced alternative to `nodejs_path()`. Will check for `node` or
`nodejs` in the PATH, like `nodejs_path()`. But you can also specify minimum
version (and other options in the future). And it will return more details.

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
        path => {
            summary => 'Search this instead of PATH environment variable',
            schema => ['str*'],
        },
        %arg_all,
    },
};
sub nodejs_available {
    require IPC::System::Options;

    my %args = @_;
    my $all = $args{all};

    my $paths = do {
        local $ENV{PATH} = $args{path} if defined $args{path};
        nodejs_path(all => 1);
    };
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
        push @versions, defined($v) ? "$v" : undef;
    }

    $res->[2]                 = $all ? \@filtered_paths : $filtered_paths[0];
    $res->[3]{'func.path'}    = $all ? \@filtered_paths : $filtered_paths[0];
    $res->[3]{'func.version'} = $all ? \@versions       : $versions[0];
    $res->[3]{'func.errors'}  = \@errors;

    unless (@filtered_paths) {
        $res->[0] = 412;
        $res->[1] = @errors == 1 ? $errors[0] :
            "No eligible node.js found in PATH";
    }

    $res;
}

sub system_nodejs {
    require IPC::System::Options;
    my $opts = ref($_[0]) eq 'HASH' ? shift : {};

    my $harmony_scoping = delete $opts->{harmony_scoping};
    my $path = delete $opts->{path};

    my %detect_nodejs_args;
    if ($harmony_scoping) {
        $detect_nodejs_args{min_version} = '0.5.10';
    }
    if ($path) {
        $detect_nodejs_args{path} = $path;
    }
    my $detect_res = nodejs_available(%detect_nodejs_args);
    die "No eligible node.js binary available: ".
        "$detect_res->[0] - $detect_res->[1]" unless $detect_res->[0] == 200;

    my @extra_args;
    if ($harmony_scoping) {
        my $node_v = $detect_res->[3]{'func.version'};
        if (version->parse($node_v) < version->parse("2.0.0")) {
            push @extra_args, "--use_strict", "--harmony_scoping";
        } else {
            push @extra_args, "--use_strict";
        }
    }

    IPC::System::Options::system(
        $opts,
        $detect_res->[2],
        @extra_args,
        @_,
    );
}

sub nodejs_module_path {
    my $opts = ref $_[0] eq 'HASH' ? shift : {};
    my $module = shift;

    my ($dir, $name, $ext) = $module =~ m!\A(?:(.*)/)?(.+?)(\.\w+)?\z!;
    #use DD; dd {dir=>$dir, name=>$name, ext=>$ext};

    my  @dirs;
    if (defined $dir) {
        @dirs = ($dir);
    } else {
        my $cwd = do {
            if (defined $opts->{cwd}) {
                $opts->{cwd};
            } else {
                require Cwd;
                Cwd::getcwd();
            }
        };
        $cwd =~ s!/node_modules\z!!;
        while (1) {
            push @dirs, "$cwd/node_modules";
            $cwd =~ s!(.*)/.+!$1!
                or last;
        }
    }

    if (defined $ENV{NODE_PATH}) {
        my $sep = $^O =~ /win32/i ? qr/;/ : qr/:/;
        push @dirs, split($sep, $ENV{NODE_PATH});
    }

    if (defined $ENV{HOME}) {
        push @dirs, "$ENV{HOME}/.node_modules";
        push @dirs, "$ENV{HOME}/.node_libraries";
    }

    if (defined $ENV{PREFIX}) {
        push @dirs, "$ENV{PREFIX}/lib/node";
    }

    #use DD; dd \@dirs;

    my @res;
    for my $d (@dirs) {
        next unless -d $d;
        if (defined $ext) {
            my $p = "$d/$name$ext";
            if (-f $p) {
                push @res, $p;
                last unless $opts->{all};
            }
        } else {
            my $p;
            for my $e (".js", ".json", ".node") {
                $p = "$d/$name$e";
                if (-f $p) {
                    push @res, $p;
                    last unless $opts->{all};
                }
            }
            $p = "$d/$name";
            if (-d $p) {
                if (-f "$p/index.js") {
                    push @res, "$p/index.js";
                    last unless $opts->{all};
                } elsif (-f "$p/package.json") {
                    push @res, "$p/package.json";
                    last unless $opts->{all};
                }
            }
        }
    }

    if ($opts->{all}) {
        return \@res;
    } else {
        return $res[0];
    }
}

1;
# ABSTRACT: Utilities related to Node.js

=for Pod::Coverage ^(get_nodejs_path)$

=head1 append:FUNCTIONS

=head2 system_nodejs

Usage:

 system_nodejs([ \%opts ], @argv)

Will call L<IPC::System::Options>'s system(), but with node.js binary as the
first argument. Known options:

=over

=item * harmony_scoping => bool

If set to 1, will attempt to enable block scoping. This means at least node.js
v0.5.10 (where C<--harmony_scoping> is first recognized). But
C<--harmony_scoping> is no longer needed after v2.0.0 and no longer recognized
in later versions.

=item * path => str

Will be passed to C<nodejs_available()>.

=back

Other options will be passed to C<IPC::System::Options>'s C<system()>.

=head2 nodejs_module_path

Usage:

 nodejs_module_path([ \%opts, ] $module) => str|array

Search module in filesystem according to Node.js rule described in
L<https://nodejs.org/api/modules.html>. C<$module> can be either a
relative/absolute path (e.g. C<./bip39.js>, C<../bip39.js>, or
C</home/foo/bip39.js>), a filename (e.g. C<bip39.js>), or a filename with the
C<.js> removed (e.g. C<bip39>).

Will return undef if no module is found, or string containing the found path.

Known options:

=over

=item * parse_package_json => bool (default: 0)

Not yet implemented.

=item * cwd => str

Use this directory instead of using C<Cwd::get_cwd()>.

=item * all => bool

If set to true, will return an array of all found paths instead of string
containing the first found path.

=back

=cut
