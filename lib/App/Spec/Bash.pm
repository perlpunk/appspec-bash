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

sub genhelp {
    my ($self, $run) = @_;
    my $params = $run->parameters;
    my $bashfile = $params->{output};
    my $specfile = $params->{spec};

    my $spec = App::Spec->read($specfile);
    my $appspec_version = App::Spec->VERSION;
    my $appspec_bash_version = App::Spec::Bash->VERSION;
    my %help;
    my $help = $self->generate_help(
        help => \%help,
        spec => $spec,
        cmdspec => $spec,
        commands => [],
    );
    my $functions = '';
    for my $func (sort keys %help) {
        my $code = <<"EOM";
APPSPEC.help-$func() {
  cat <<EOHELP
$help{ $func }
EOHELP
}

EOM
        $functions .= $code;
    }
    my $bash = <<"EOM";
#!/bin/bash

# Generated by perl modules
# App::Spec v$appspec_version
# App::Spec::Bash v$appspec_bash_version

APPSPEC.help() {
  cat <<EOHELP
Usage
EOHELP
}
$functions

EOM
    open my $fh, '>', $bashfile or die $!;
    print $fh $bash;
    close $fh;
}

sub generate_help {
    my ($self, %args) = @_;
    my $spec = $args{spec};
    my $cmdspec = $args{cmdspec};
    my $help = $args{help};
    my $cmds = $args{commands};
    my $cmdstring = @$cmds ? join '-', @$cmds : 'ROOT';
    my $usage = $spec->usage(
        commands => [ @$cmds ],
        colored => 0,
    );
    $help->{ $cmdstring } = $usage;

    my $subcommands = $cmdspec->subcommands || {};
    for my $key (sort keys %$subcommands) {
        my $cmd = $subcommands->{ $key };
        my $cmdstring = join '-', @$cmds, $key;
        my $usage = $spec->usage(
            commands => [ @$cmds, $key ],
            colored => 0,
        );
        $help->{ $cmdstring } = $usage;
        my $subhelp = $self->generate_help(
            help => $help,
            spec => $spec,
            cmdspec => $cmd,
            commands => [@$cmds, $key],
        );
    }
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
    my $params = $spec->parameters;
    my $local_declare = '';
    my $global_opt_long = '';
    my $global_opt_short = '';
    if (@$options) {
        ($local_declare, $global_opt_long, $global_opt_short)
            = $self->generate_options($options);
    }
    my $parse_params = '';
    if (@$params) {
        my $funcname = '';
        my ($params_declare, $parse_params) = $self->generate_params($funcname, $params);
        $local_declare .= $params_declare;
    }
    push @all_options, @$options;

    my @functions;
    my @commands;

    my $subcommands = $spec->subcommands;
    my $subcmds = $self->generate_subcommands(
        subcommands => $subcommands,
        functions => \@functions,
        commands => \@commands,
    );
    my $functions = join "\n", @functions;
    my $colors = $self->ansi_colors;

    my $run = '';
    my $bash = <<"EOM";
#!/bin/bash

# Generated by perl modules
# App::Spec v$appspec_version
# App::Spec::Bash v$appspec_bash_version
# $name - $title

set -e

declare OP=
declare -a ERRORS=()
declare -a COMMANDS=()
declare stdout_terminal=false stderr_terminal=false
declare END_OF_OPTIONS=false
$colors

DEBUG=false
[[ -n "\$APPSPEC_BASH_DEBUG" ]] && DEBUG=true

APPSPEC.run() {
  APPSPEC.init-terminal
  APPSPEC.parse \$@
}

APPSPEC.run-op() {
  if (( \${#ERRORS[*]} > 0 )); then
    APPSPEC.show_help
    for i in "\${ERRORS[@]}"; do
      APPSPEC.error "\$i"
    done
    exit 1
  else
    debug "OP: \$OP"
  fi
  if [[ \${#argv[@]} -gt 0 ]]; then
    debug "leftover args in ARGV: (\${argv[*]})"
    ARGV=(\${argv[@]})
  fi
  debug "Running $class.\$OP"
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
  if [[ \${#argv[@]} -eq 0 ]]; then
      APPSPEC.add-error "Missing subcommand"
      APPSPEC.run-op
      return
  fi
  while [[ \${#argv[@]} > 0 ]]; do
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

APPSPEC.colored() {
    local fh="$1"
    local message="$2"
    if [[ "$fh" == "stdout" ]] && ! $stdout_terminal; then
        echo "$message"
        return
    fi
    if [[ "$fh" == stderr ]] && ! $stderr_terminal; then
        echo "$message"
        return
    fi
    shift
    shift
    local colornames=($@)
    local varname value colored=

    for i in "${colornames[@]}"; do
        varname="APPSPEC_COLOR_$i"
        value="${!varname}"
        colored+="$value"
    done

    colored+="$message"
    colored+="$APPSPEC_NO_COLOR"
    echo "$colored"

}

APPSPEC.colorize() {
    local fh="$1"
    local message="$2"
    shift
    shift
    [[ "$fh" == stdout ]] && echo -e "$(APPSPEC.colored "$fh" "$message" $@)"
    [[ "$fh" == stderr ]] && echo -e "$(APPSPEC.colored "$fh" "$message" $@)" >&2
}

APPSPEC.say() {
    local message="$1"
    shift
    if [[ $# -gt 0 ]]; then
        echo -e "$(APPSPEC.colored stdout "$message" $@)"
    else
        echo "$message"
    fi
}

APPSPEC.error() {
    local message="$1"
    echo -e "$(APPSPEC.colored stderr "$message" BOLD RED)" >&2
}

APPSPEC.add-error() {
    debug "$1"
    ERRORS+=("$1")
}

APPSPEC.init-terminal() {
  if [[ -t 1 ]]; then
    stdout_terminal=true
  fi
  if [[ -t 2 ]]; then
    stderr_terminal=true
  fi
}


APPSPEC.cmd_help() {
  debug "======== APPSPEC.cmd_help"
  COMMANDS=("${COMMANDS[@]:1}")
  APPSPEC.show_help
}

APPSPEC.show_help() {
  source "$APPSPECDIR/lib/help"
  debug "======== APPSPEC.show_help"
  if [[ -n "$COMMANDS" ]]; then
    local func="${COMMANDS[*]}"
    func="${func/ /-}"
    debug "func $func"
    APPSPEC.help-$func
  else
    APPSPEC.help-ROOT
  fi
}

shift_arg() {
    argv=("${argv[@]:1}")
}

debug() {
  $DEBUG && APPSPEC.colorize stderr "$@" DARKGRAY || true
}
EOM


}

sub generate_subcommands {
    my ($self, %args) = @_;
    my $subcommands = $args{subcommands} || {};
    my $functions = $args{functions};
    my $commands = $args{commands};
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

            my $sreq = ($spec->subcommand_required // 1) && $sub && ! $op ? 1 : 0;

            my $subcmds = $self->generate_subcommands(
                subcommands => $sub,
                functions => $functions,
                commands => [@$commands, $name],
            );
            if ($op) {
                $op = <<"EOM";
      if [[ -z "\$OP" ]]; then
        OP=$op
        APPSPEC.run-op
      fi
EOM
            }
            elsif ($sreq) {
                $op = <<"EOM";
      if [[ -z "\$OP" ]]; then
        APPSPEC.add-error "Missing subcommand"
        APPSPEC.run-op
      fi
EOM
            }
            my $options = $spec->options;
            my ($local_declare, $global_opt_long, $global_opt_short)
                = $self->generate_options($options);
            my $params = $spec->parameters;
            my $parse_params = '';
            my $funcname = join '-', (@$commands, $name);
            if (@$params) {
                (my $params_declare, $parse_params) = $self->generate_params($funcname, $params);
                $local_declare .= $params_declare;
            }

            my $parse_params_call = '';
            if ($parse_params) {
                my $parse_params_func = <<"EOM";
APPSPEC.params-$funcname() {
  debug "APPSPEC.params-$funcname()"
$parse_params
}
EOM
                push @$functions, $parse_params_func;
                $parse_params_call = "      APPSPEC.params-$funcname";
            }


            $case .= <<"EOM";
    $name)
      COMMANDS+=("$name")
$local_declare
      shift_arg
      APPSPEC.parse-$funcname
$parse_params_call
$op
      return
    ;;
EOM

            my $function = <<"EOM";
APPSPEC.parse-$funcname() {
  debug "APPSPEC.parse-$funcname()"
  [[ \${#argv[@]} -eq 0 ]] && return

  while [[ \${#argv[@]} -gt 0 ]]; do
    if APPSPEC.parse-options-$funcname; then
        break
    fi

    case "\${argv[0]}" in
    # SUBCOMMANDS
$subcmds
    esac
  done

}
EOM
            my $function2 = <<"EOM";
APPSPEC.parse-options-$funcname() {
  debug "APPSPEC.parse-options-$funcname()"
  \$END_OF_OPTIONS && return 1
  while [[ \${#argv[@]} -gt 0 ]]; do
    case "\${argv[0]}" in
$global_opt_long
    -*)
$global_opt_short
    ;;

    *) return 1
    ;;
    esac
  done
  return 0
}
EOM
            push @$functions, $function;
            push @$functions, $function2;

        }
        $code .= $case;

        $code .= <<"EOM";
    *)
      APPSPEC.add-error "Unknown subcommand '\${argv[0]}'"
      shift_arg
      APPSPEC.run-op
      return
    ;;

EOM
    }
    else {
        $code .= <<"EOM";
    *) return
    ;;
EOM
    }
    return $code;
}

sub generate_options {
    my ($self, $options) = @_;

    my $local_declare = '';
    my $long = <<"EOM";
EOM
    my $short_preface = <<'EOM';
      local i arg=${argv[0]/-/}
      for (( i=0; i < "${#arg}"; i++ )); do
        local char="${arg:$i:1}"
        value="${arg:$i+1}"
        if (( $i+1 == ${#arg} )); then
          shift_arg
          value="${argv[0]}"
        fi
        debug "processing short $char. arg=$arg value=$value"
        case "$char" in
EOM

    my $short = '';
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
    --) shift_arg; END_OF_OPTIONS=true; break
    ;;
    --*)
        APPSPEC.add-error "Unknown option '\${argv[0]}'"
        shift_arg
        break
    ;;
EOM
    if ($short) {
        $short .= <<"EOM";
        *)
          APPSPEC.add-error "Unknown option '-\$char'"
          shift_arg
          break
        ;;
        esac
      done
EOM
          $short = $short_preface . $short;
    }
    else {
        $short = <<'EOM';
        APPSPEC.add-error "Unknown option '${argv[0]}'"
        shift_arg
        break
EOM
    }

    return ($local_declare, $long), $short;
}

sub generate_params {
    my ($self, $funcname, $params) = @_;

    my $declare = '';
    my $check = '';
    my $parse = <<'EOM';
  while [[ ${#argv[@]} -gt 0 ]]; do
EOM
    for my $p (@$params) {
        my $name = $p->name;
        my $bashname = "PARAM_" . uc($name);
        $bashname =~ tr/0-9a-zA-Z_/_/c;
        if ($p->multiple) {
            $declare .= "      declare -a $bashname=()";
            $parse .= <<"EOM";
    if APPSPEC.parse-options-$funcname; then
        break
    fi
    $bashname+=(\${argv[@]})
    argv=()
EOM
        }
        else {
            $declare .= "      declare $bashname";
            $parse .= <<"EOM";
    if APPSPEC.parse-options-$funcname; then
        break
    fi
    $bashname="\${argv[0]}"
    shift_arg
EOM
        }
        if ($p->required) {
            $declare .= " # REQUIRED";
            $check .= <<"EOM";
  if [[ -z "\$$bashname" ]]; then
    APPSPEC.add-error "Missing required parameter '$name'"
  fi
EOM
        }
        $declare .= "\n";

    }
    $parse .= "    break\n";
    $parse .= "  done\n";
    $parse .= <<"EOM";
  if APPSPEC.parse-options-$funcname; then
    true
  fi
EOM
    $parse .= $check;
    return ($declare, $parse);
}

sub ansi_colors {
    return <<'EOM';
declare APPSPEC_COLOR_BOLD='\x1b[1m'
declare APPSPEC_COLOR_RED='\x1b[31m'
declare APPSPEC_COLOR_ERROR="$GIT_HUB_COLOR_RED$GIT_HUB_COLOR_BOLD"
declare APPSPEC_COLOR_GREEN='\x1b[32m'
declare APPSPEC_COLOR_CYAN='\x1b[36m'
declare APPSPEC_COLOR_MAGENTA='\x1b[35m'
declare APPSPEC_COLOR_YELLOW='\x1b[33m'
declare APPSPEC_COLOR_DARKGRAY='\x1b[90m'
declare APPSPEC_NO_COLOR='\x1b[0m'

EOM
}

1;
