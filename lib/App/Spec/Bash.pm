# ABSTRACT: App Module and utilities for appspec-bash
use strict;
use warnings;
package App::Spec::Bash;

our $VERSION = '0.000'; # VERSION

use base 'App::Spec::Run::Cmd';

use Data::Dumper;

sub parser {
    my ($self, $run) = @_;
    my $params = $run->parameters;
    my $bashfile = $params->{output};
    my $specfile = $params->{spec};
    my $spec = App::Spec->read($specfile);

    my $bash = $self->generate_app($spec);
    open my $fh, '>', $bashfile or die $!;
    print $fh $bash;
    close $fh;
}

sub generate_app {
    my ($self, $spec) = @_;
    my $appspec_version = App::Spec->VERSION;
    my $appspec_bash_version = App::Spec::Bash->VERSION;
    my $name = $spec->name;
    my $title = $spec->title;
    my $class = $spec->class;

    my @all_options;
    my $options = $spec->options;
    my $declare_options;
    my $local_declare = '';
    my $global_opt_long = '';
    my $global_opt_short = '';
    if (@$options) {
        ($declare_options, $local_declare, $global_opt_long, $global_opt_short)
            = $self->generate_options(2, $options);
    }
    push @all_options, @$options;

    my $subcommands = $spec->subcommands;
    my $subcmds = $self->generate_subcommands(
        declare_options => \$declare_options,
        subcommands => $subcommands,
        level => 2,
    );

    my $run = '';
    my $bash = <<"EOM";
#!/bin/bash

# Generated by perl modules
# App::Spec v$appspec_version
# App::Spec::Bash v$appspec_bash_version
# $name - $title

$declare_options
declare OP=
declare -a ERRORS=()

DEBUG=false
[[ -n "\$APPSPEC_BASH_DEBUG" ]] && DEBUG=true

APPSPEC.run() {
  APPSPEC.parse \$@
  if (( \${#ERRORS[*]} > 0 )); then
    debug "ERRORS: (\${ERRORS[*]})"
  else
    debug "OP: \$OP"
    $class.\$OP
  fi
}

APPSPEC.parse() {
  local argv=(\$@)
  debug "ARGV: \${argv[*]}"
$local_declare
  while [[ \${#argv} > 0 ]]; do
    debug "processing \${argv[0]}..."
    case "\${argv[0]}" in
$global_opt_long
    -*)
$global_opt_short
    ;;

    # SUBCOMMANDS
$subcmds
    esac
  done

  debug "ARGV: \${argv[*]}"
}

EOM
    $bash .= <<'EOM';
shift_arg() {
    argv=("${argv[@]:1}")
}

debug() {
  $DEBUG && echo $@
}
EOM


}

sub generate_subcommands {
    my ($self, %args) = @_;
    my $level = $args{level};
    my $indent = ' ' x ($level * 2);
    my $subcommands = $args{subcommands};
    my $declare_all_options = $args{declare_options};
    my $code;
    if (%$subcommands) {
        my $case = <<"EOM";
EOM
        for my $name (sort keys %$subcommands) {
            my $spec = $subcommands->{ $name };
            my $sub = $spec->subcommands;
            my $op = $spec->op || '';
            my $subcmds = ''; # TODO
            my $options = $spec->options;
            my $declare_options;
            my $local_declare = '';
            my $global_opt_long = '';
            my $global_opt_short = '';
            if (@$options) {
                ($declare_options, $local_declare, $global_opt_long, $global_opt_short)
                    = $self->generate_options($level + 3, $options);
                $$declare_all_options .= $declare_options;
            }


            $case .= <<"EOM";
${indent}$name)
${indent}  debug COMMAND $name
$local_declare
${indent}  shift_arg
${indent}  OP=$op
${indent}  while [[ \${#argv} > 0 ]]; do
${indent}    case "\${argv[0]}" in
$global_opt_long
${indent}    -*)
$global_opt_short
${indent}    ;;
${indent}    *)
$subcmds
${indent}      shift_arg
${indent}    ;;
${indent}    esac
${indent}  done

${indent}  break
${indent};;
EOM
        }
        $code .= $case;
    }
    $code .= <<"EOM";
${indent}  *)
${indent}  debug "UNKNOWN cmd \${argv[0]}"
${indent}  ERRORS+=("unknown subcommand \${argv[0]}")
${indent}  shift_arg
${indent}  return
${indent}  ;;

EOM
    return $code;
}

sub generate_options {
    my ($self, $level, $options) = @_;
    my $indent = ' ' x ($level * 2);

    my $declare = '';
    my $local_declare = '';
    my $long = <<"EOM";
EOM
    my $short = <<"EOM";
${indent}  local i arg=\${argv[0]/-/}
${indent}  for (( i=0; i < "\${#arg}"; i++ )); do
${indent}    local char="\${arg:\$i:1}"
${indent}    debug "processing short \$char"
${indent}    case "\$char" in
EOM

    for my $option (@$options) {
        my $name = $option->name;
        my $bashname = "OPT_" . uc($name);
        my $long_action = '';
        my $short_action = '';
        $bashname =~ tr/0-9a-zA-Z_/_/c;

        if ($option->type eq 'flag') {
            if ($option->multiple) {
                $declare .= sprintf "declare %s\n", $bashname;
                $local_declare .= sprintf "${indent}declare -g -i %s=0\n", $bashname;
                $long_action = sprintf "${indent}    %s+=1\n", $bashname;
                $short_action = sprintf "${indent}        %s+=1\n", $bashname;
            }
            else {
                $declare .= sprintf "declare %s\n", $bashname;
                $local_declare .= sprintf "${indent}declare -g %s=false\n", $bashname;
                $long_action = sprintf "${indent}    %s=true\n", $bashname;
                $short_action = sprintf "${indent}        %s=true\n", $bashname;
            }
        }
        else {
            if ($option->multiple) {
                $declare .= sprintf "declare %s\n", $bashname;
                $local_declare .= sprintf "${indent}declare -g -a %s=()\n", $bashname;
                $long_action = <<"EOM";
${indent}    shift_arg
${indent}    $bashname+=("\${argv[0]}")
EOM
                $short_action = <<"EOM";
${indent}if (( \$i+1 == \${#arg} )); then
${indent}  shift_arg
${indent}  $bashname+=("\${argv[0]}")
${indent}else
${indent}  $bashname+=("\${arg:\$i+1}")
${indent}fi
#${indent}        $bashname+=("\${arg:\$i+1}")
EOM
            }
            else {
                $declare .= sprintf "declare %s\n", $bashname;
                $local_declare .= sprintf "${indent}declare -g %s=\n", $bashname;
                $long_action = <<"EOM";
${indent}    shift_arg
${indent}    $bashname="\${argv[0]}"
EOM
                $short_action = <<"EOM";
${indent}if (( \$i+1 == \${#arg} )); then
${indent}  shift_arg
${indent}  $bashname="\${argv[0]}"
${indent}else
${indent}  $bashname="\${arg:\$i+1}"
${indent}fi
#${indent}        $bashname="\${arg:\$i+1}"
EOM
            }
            $short_action .= <<"EOM";
${indent}        shift_arg
${indent}        break
EOM
        }
        $long_action .= "${indent}    shift_arg\n";

        my @names = ($name, @{ $option->aliases });
        my @case_long;
        my @case_short;
        for my $n (@names) {
            if (length($n) > 1) {
                push @case_long, "--$n";
            }
            else {
                push @case_short, $n;
            }
        }
        my $case_long = join '|', @case_long;
        my $case_short = join '|', @case_short;
        $long .= <<"EOM";
${indent}$case_long)
${indent}    debug "LONG OPTION $name"
$long_action
${indent};;
EOM
        if (@case_short) {
            $short .= <<"EOM";
${indent}    $case_short)
${indent}        debug "SHORT OPTION $name"
$short_action
${indent}    ;;
EOM
        }
    }

    $long .= <<"EOM";
${indent}--*)
${indent}    debug "!UNKNOWN OPTION \${argv[0]}"
${indent}    ERRORS+=("unknown option \${argv[0]}")
${indent}    shift_arg
${indent}    break
${indent};;
EOM
    $short .= <<"EOM";
${indent}    *)
${indent}      debug "!UNKNOWN option -\$char"
${indent}      ERRORS+=("unknown option -\$char")
${indent}      shift_arg
${indent}      break
${indent}    ;;
${indent}    esac
${indent}  done
${indent}  if (( \$i == \${#arg} )); then
${indent}    shift_arg
${indent}  fi
EOM

    return ($declare, $local_declare, $long), $short;
}

1;
