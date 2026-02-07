set -l cmds up down stop restart build ps log new-host remove-host build-webconf bash fish rootssl hostssl import-rootca redis-flush redis-monitor debug supervisor-conf supervisor-restart install dir git-update
set -l containers franken_php mariadb redis phpmyadmin mailhog
set -l debug_modes off develop coverage debug profile trace

function __fish_web_needs_cmd
    test (count (commandline -opc)) -eq 1
end

function __fish_web_using_cmd
    set -l cmd (commandline -opc)
    test (count $cmd) -eq 2; and test $cmd[2] = $argv[1]
end

function __fish_web_build_third
    set -l cmd (commandline -opc)
    test (count $cmd) -eq 3; and test $cmd[2] = build
end

complete -f -c web -n __fish_web_needs_cmd -a "$cmds"
complete -f -c web -n '__fish_web_using_cmd build' -a "$containers --no-cache"
complete -f -c web -n '__fish_web_using_cmd debug' -a "$debug_modes"
complete -f -c web -n '__fish_web_using_cmd ps' -a "$containers"
complete -f -c web -n '__fish_web_using_cmd log' -a "$containers"
complete -f -c web -n '__fish_web_using_cmd restart' -a "$containers"
complete -f -c web -n '__fish_web_using_cmd stop' -a "$containers"
complete -f -c web -n __fish_web_build_third -a --no-cache
