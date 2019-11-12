use strict;
use warnings;
package App::Spec::Bash::Spec;

our $VERSION = '0.000'; # VERSION

use base 'Exporter';
our @EXPORT_OK = qw/ $SPEC /;

our $SPEC;

# START INLINE
$SPEC = {
  'abstract' => 'Generate commandline parser, completion and man pages',
  'appspec' => {
    'version' => '0.001'
  },
  'class' => 'App::Spec::Bash',
  'description' => 'This script can generate a commandline parser for bash from a specification
file written in YAML.

Writing a parser for commandline arguments isn\'t rocket science, but it\'s
something you don\'t want to do manually for all of your scripts, especially
in bash. Some tools exist, but they often don\'t support subcommands or
validating of option values.

C<appspec>/C<appspec-bash> can generate pretty much everything for you:

=over

=item Commandline parser for subcommands, options and parameters

=item Usage output

=item Shell completion files

=item man pages

=back

=head2 EXAMPLES

Here is an example of a very simple script.

The following files are needed:

  share/mytool.yaml
  bin/mytool
  lib/mytool
  lib/appspec                       # generated
  share/completion/zsh/_mytool      # generated
  share/completion/bash/mytool.bash # generated
  pod/mytool.pod                    # generated
  lib/help                          # generated

The spec:

  # share/mytool.yaml
  ---
  name: mytool           # commandname
  appspec: { version: 0.001 }
  plugins: [-Meta]       # not supported in bash
  title: My cool tool    # Will be shown in help
  class: MyTool          # "Class name" (means function prefix here)

  subcommands:
    command1:
      op: command1       # The function name (MyTool.command1)
      summary: cmd one   # Will be shown in help and completion
      options:
      - foo|f=s --Foo    # --foo or -f; \'=s\' means string
      - bar|b   --Bar    # --bar or -b; a flag

Your script C<mytool> would look like this:

  # bin/mytool
  #!/bin/bash
  DIR="$( dirname $BASH_SOURCE )"
  source "$DIR/../lib/appspec"
  source "$DIR/../lib/mytool"
  APPSPEC.run $@

The actual app:

  # lib/mytool
  #!/bin/bash
  MyTool.command1() {
      echo "=== OPTION foo: $OPT_FOO"
      echo "=== OPTION bar: $OPT_BAR"
  }

=head3 Generating the parser

Then generate the parser like this:

  $ appspec-bash generate parser share/mytool.yaml lib/appspec


C<APPSPEC.run> will parse the arguments and then call the function
C<MyTool.command1>. In this function you can use the options via
C<$OPT_FOO> and C<$OPT_BAR>.

  $ ./bin/mytool command1 --foo x --bar
  # or
  $ mytool command1 -f x -b
  === OPTION foo: x
  === OPTION bar: true

=head3 Generate completion

    $ appspec completion share/mytool.yaml --zsh >share/completion/zsh/_mytool
    $ appspec completion share/mytool.yaml --bash >share/completion/bash/mytool.bash

=head3 Generate pod

    $ appspec pod share/mytool.yaml > pod/mytool.pod
    $ perldoc pod/mytool.pod

=head3 Generate help

    $ appspec-bash generate help share/mydemo.yaml lib/help

=head2 Generate a new app skeleton

  appspec-bash new --class MyTool --name mytool

This will create your app C<mytool> in the directory C<MyTool> and output
some usage information like this:

  To generate the parser and help, do:

    % cd MyTool
    % appspec-bash generate parser share/mytool.yaml lib/appspec
    % appspec-bash generate help share/mytool.yaml lib/help

  Try it out:

    % bin/mytool cmd1 -ab --opt-x x -yfoo --opt-y bar
    % bin/mytool cmd2 -vvv
    % bin/mytool cmd2 -vvv foo

=head2 OPTION AND PARAMETER PARSING

appspec-bash supports various types of options.

=head3 Flags

    # YAML
    options:
    - verbose|v -- Verbose output

    % mytool --verbose
    % mytool -v

You can also stack several flags:

    % mytool -abc

=head3 Options with values

    # YAML
    options:
    - color|c=s --Specify color

    % mytool --color red
    % mytool -c red
    % mytool -cred
    # Not yet supported
    # mytool --color=red

You can stack flags together with options. If you have the flags C<-a> and
C<-b> and the option C<-c>, then you can use this syntax:

    % mytool -abc23

=head3 Incremental flags

    # YAML
    options:
    - verbose|v+ --Verbose output (incremental)

    % mytool -vvv                # like: declare -i OPT_VERBOSE=3
    % mytool --verbose --verbose # like: declare -i OPT_VERBOSE=2

=head3 Options with multiple values

    # YAML
    options:
    - server|s=s@  --List of servers

    % mytool --server foo --server bar
    % mytool -s foo -s bar

=head3 Parameters

    # YAML
    parameters:
    - name: server
      required: true
      summary: Server name

=head3 Option types

By default, an option is a flag. To accept a value, add a C<=>. Then it will
be a string by default:

    - foo=
    # or
    - foo=s

You can also create integer options:

    - max=i --Specify maximum value

Then you can treat it as an integer and use C<OPT_MAX+=1> for example.

There are also the types C<file>, C<dir>, C<filename> and C<dirname>.
Currently they are only relevant for completion.

    # YAML
    - input= +file      --Input filename
    - source-dir= +dir  --Source directory
    - output= +filename --Output file
    - out-dir= +dirname --Output directory

In the future, C<file> and C<dir> will check for an existing file or
directory. And C<filename> and C<dirname> can be used if the file
or directory doesn\'t exist yet, but the tab completion will still offer
file or directory names.

See the C<mydemo> app in the example directory for examples of options and
parameters.
',
  'markup' => 'pod',
  'name' => 'appspec-bash',
  'options' => [],
  'subcommands' => {
    'generate' => {
      'subcommands' => {
        'help' => {
          'op' => 'genhelp',
          'parameters' => [
            '+spec= +file       --YAML Specification file',
            '+output= +filename --Output file, e.g. lib/help'
          ],
          'summary' => 'Generate help functions'
        },
        'parser' => {
          'op' => 'parser',
          'parameters' => [
            '+spec= +file       --YAML Specification file',
            '+output= +filename --Output file, e.g. lib/appspec'
          ],
          'summary' => 'Generate main commandline parser script'
        }
      },
      'summary' => 'Generate parser, help'
    },
    'new' => {
      'description' => 'This command creates a skeleton for a new app.
It will create a directory for your app and write a skeleton
spec file.

Example:

  appspec-bash new --name mytool --class MyTool MyTool
',
      'op' => 'cmd_new',
      'options' => [
        '+name|n=s    --The (file) name of the app',
        '+class|c=s   --The main "class" (function prefix) for your app implementation',
        'overwrite|o  --Overwrite existing dist directory'
      ],
      'parameters' => [
        'path= +dirname --Path to the distribution directory (default is the classname in current directory)'
      ],
      'summary' => 'Generate new app'
    }
  },
  'title' => 'Command line framework generator for bash'
};
# END INLINE

1;
