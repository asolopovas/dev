set -l cmds up down stop restart build ps log new-host remove-host build-webconf bash fish rootssl hostssl import-rootca redis-flush redis-monitor debug supervisor-init supervisor-conf supervisor-restart install dir git-update help
set -l services franken_php mariadb redis phpmyadmin mailpit typesense
set -l debug_modes off develop coverage debug profile trace
set -l site_types wp laravel

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

function __fish_web_newhost_flag_t
    set -l cmd (commandline -opc)
    test (count $cmd) -ge 2; and test $cmd[2] = new-host; and contains -- -t $cmd
end

function __fish_web_hosts
    test -f ~/www/dev/web-hosts.json; and jq -r '.hosts[].name' ~/www/dev/web-hosts.json 2>/dev/null
end

complete -f -c web -n __fish_web_needs_cmd -a "$cmds"
complete -f -c web -n '__fish_web_using_cmd up' -a "$services"
complete -f -c web -n '__fish_web_using_cmd build' -a "$services --no-cache"
complete -f -c web -n '__fish_web_using_cmd debug' -a "$debug_modes"
complete -f -c web -n '__fish_web_using_cmd ps' -a "$services"
complete -f -c web -n '__fish_web_using_cmd log' -a "$services"
complete -f -c web -n '__fish_web_using_cmd restart' -a "$services"
complete -f -c web -n '__fish_web_using_cmd stop' -a "$services"
complete -f -c web -n '__fish_web_using_cmd new-host' -a "-t"
complete -f -c web -n __fish_web_newhost_flag_t -a "$site_types"
complete -f -c web -n '__fish_web_using_cmd remove-host' -a "(__fish_web_hosts)"
complete -f -c web -n '__fish_web_using_cmd hostssl' -a "(__fish_web_hosts)"
complete -f -c web -n '__fish_web_using_cmd supervisor-conf' -a "(__fish_web_hosts)"
complete -f -c web -n __fish_web_build_third -a --no-cache
