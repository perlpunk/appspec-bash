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
    my $local_declare = '';
    my $global_opt_long = '';
    my $global_opt_short = '';
    if (@$options) {
        ($local_declare, $global_opt_long, $global_opt_short)
            = $self->generate_options(2, $options);
    }
    push @all_options, @$options;

    my @functions;
    my @commands;

    my $subcommands = $spec->subcommands;
    my $subcmds = $self->generate_subcommands(
        subcommands => $subcommands,
        level => 2,
        functions => \@functions,
        commands => \@commands,
    );
    my $functions = join "\n", @functions;

    my $run = '';
    my $bash = <<"EOM";
#!/bin/bash

# Generated by perl modules
# App::Spec v$appspec_version
# App::Spec::Bash v$appspec_bash_version
# $name - $title

declare OP=
declare -a ERRORS=()

DEBUG=false
[[ -n "\$APPSPEC_BASH_DEBUG" ]] && DEBUG=true

APPSPEC.run() {
  APPSPEC.parse \$@
}

APPSPEC.run-op() {
  if (( \${#ERRORS[*]} > 0 )); then
    debug "ERRORS: (\${ERRORS[*]})"
  else
    debug "OP: \$OP"
  fi
  if [[ -n "\$OP" ]]; then
    $class.\$OP
  else
    echo "No operation found"
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

$functions

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
    my $functions = $args{functions};
    my $code;
    if (%$subcommands) {
        my $case = <<"EOM";
EOM
        for my $name (sort keys %$subcommands) {
            # no support for _meta functions
            next if $name eq '_meta';

            my $spec = $subcommands->{ $name };
            my $sub = $spec->subcommands;
            my $op = $spec->op || '';
            my $subcmds = ''; # TODO
            my $options = $spec->options;
            my $local_declare = '';
            my $global_opt_long = '';
            my $global_opt_short = '';
            if (@$options) {
                ($local_declare, $global_opt_long, $global_opt_short)
                    = $self->generate_options($level + 3, $options);
            }


            $case .= <<"EOM";
    $name)
      debug COMMAND $name
$local_declare
      shift_arg
      OP=$op
      APPSPEC.parse-$name
      APPSPEC.run-op
      return
    ;;
EOM

            my $function = <<"EOM";
APPSPEC.parse-$name() {
  while [[ \${#argv} > 0 ]]; do
    case "\${argv[0]}" in
$global_opt_long
    -*)
$global_opt_short
    ;;
    *)
$subcmds
      shift_arg
    ;;
    esac
  done

}
EOM
            push @$functions, $function;

        }
        $code .= $case;

    }
    $code .= <<"EOM";
    *)
      debug "UNKNOWN cmd \${argv[0]}"
      ERRORS+=("unknown subcommand \${argv[0]}")
      shift_arg
      return
    ;;

EOM
    return $code;
}

sub generate_options {
    my ($self, $level, $options) = @_;
    my $indent = ' ' x ($level * 2);

    my $local_declare = '';
    my $long = <<"EOM";
EOM
    my $short = <<"EOM";
      local i arg=\${argv[0]/-/}
      for (( i=0; i < "\${#arg}"; i++ )); do
        local char="\${arg:\$i:1}"
        value="\${arg:\$i+1}"
        if (( \$i+1 == \${#arg} )); then
          shift_arg
          value="\${argv[0]}"
        fi
        debug "processing short \$char. arg=\$arg value=\$value"
        case "\$char" in
EOM

    for my $option (@$options) {
        my $name = $option->name;
        my $bashname = "OPT_" . uc($name);
        my $long_action = '';
        my $short_action = '';
        $bashname =~ tr/0-9a-zA-Z_/_/c;

        if ($option->type eq 'flag') {
            if ($option->multiple) {
                $local_declare .= sprintf "      declare -i %s=0\n", $bashname;
                $long_action = sprintf "        %s+=1\n", $bashname;
                $short_action = sprintf "          %s+=1\n", $bashname;
            }
            else {
                $local_declare .= sprintf "      declare %s=false\n", $bashname;
                $long_action = sprintf "        %s=true\n", $bashname;
                $short_action = sprintf "          %s=true\n", $bashname;
            }
        }
        else {
            if ($option->multiple) {
                $local_declare .= sprintf "      declare -a %s=()\n", $bashname;
                $long_action = <<"EOM";
        shift_arg
        $bashname+=("\${argv[0]}")
EOM
                $short_action = <<"EOM";
          $bashname+=("\$value")
EOM
            }
            else {
                $local_declare .= sprintf "      declare %s=\n", $bashname;
                $long_action = <<"EOM";
        shift_arg
        $bashname="\${argv[0]}"
EOM
                $short_action = <<"EOM";
          $bashname="\$value"
EOM
            }
            $short_action .= <<"EOM";
          shift_arg
          break
EOM
        }
        $long_action .= "        shift_arg\n";

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
    $case_long)
        debug "LONG OPTION $name"
$long_action
    ;;
EOM
        if (@case_short) {
            $short .= <<"EOM";
        $case_short)
          debug "SHORT OPTION $name"
$short_action
        ;;
EOM
        }
    }

    $long .= <<"EOM";
    --*)
        debug "!UNKNOWN OPTION \${argv[0]}"
        ERRORS+=("unknown option \${argv[0]}")
        shift_arg
        break
    ;;
EOM
    $short .= <<"EOM";
        *)
          debug "!UNKNOWN option -\$char"
          ERRORS+=("unknown option -\$char")
          shift_arg
          break
        ;;
        esac
      done
EOM

    return ($local_declare, $long), $short;
}

1;
