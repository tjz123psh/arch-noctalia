# Fish completion for pi (AI coding assistant)

function __fish_pi_needs_command
    set -l cmd (commandline -opc)
    if test (count $cmd) -eq 1
        return 0
    end
    set -e cmd[1]
    for arg in $cmd
        switch $arg
            case install remove uninstall update list config auth mcp
                return 1
        end
    end
    return 0
end

function __fish_pi_using_subcommand
    set -l cmd (commandline -opc)
    set -e cmd[1]
    for arg in $cmd
        if test "$arg" = "$argv[1]"
            return 0
        end
    end
    return 1
end

function __fish_pi_models
    if type -q jq; and test -f ~/.pi/agent/models.json
        jq -r '.providers | to_entries[] | .key as $p | .value.models[] | ($p + "/" + .id + "\t" + (.name // ""))' ~/.pi/agent/models.json 2>/dev/null
    else
        echo -e "antigravity/gemini-3.8-flash-tiered\tGemini 3.8 Flash"
        echo -e "workbuddy/global:deepseek-v4.1-flash\tDeepSeek V4.1 Flash Global"
        echo -e "workbuddy/cn:deepseek-v4.1-flash\tDeepSeek V4.1 Flash CN"
        echo -e "workbuddy/global:deepseek-v4.1-flash-sg\tDeepSeek V4.1 Flash SG"
        echo -e "aliyun/qwen3.8-flash\tQwen 3.8 Flash"
        echo -e "aliyun/deepseek-v4-flash-0731\tDeepSeek V4 Flash 0731"
        echo -e "agentrouter/deepseek-v4-flash\tDeepSeek V4 Flash AgentRouter"
    end
end

function __fish_pi_providers
    if type -q jq; and test -f ~/.pi/agent/models.json
        jq -r '.providers | keys[]' ~/.pi/agent/models.json 2>/dev/null
    else
        echo "antigravity"
        echo "workbuddy"
        echo "aliyun"
        echo "agentrouter"
    end
end

function __fish_pi_mcp_servers
    if type -q jq; and test -f ~/.pi/agent/mcp.json
        jq -r '.mcpServers | keys[]' ~/.pi/agent/mcp.json 2>/dev/null
    end
end

# Subcommands
complete -c pi -n "__fish_pi_needs_command" -a install -d "Install extension package and add to settings"
complete -c pi -n "__fish_pi_needs_command" -a remove -d "Remove extension source from settings"
complete -c pi -n "__fish_pi_needs_command" -a uninstall -d "Alias for remove"
complete -c pi -n "__fish_pi_needs_command" -a update -d "Update pi, extensions, or model catalogs"
complete -c pi -n "__fish_pi_needs_command" -a list -d "List installed extensions from settings"
complete -c pi -n "__fish_pi_needs_command" -a config -d "Open TUI to configure package resources"
complete -c pi -n "__fish_pi_needs_command" -a auth -d "Print credentials or check provider readiness"
complete -c pi -n "__fish_pi_needs_command" -a mcp -d "Check MCP servers, sign in/out"

# Top-level Options
complete -c pi -n "__fish_pi_needs_command" -s p -l print -d "Non-interactive mode: process prompt and exit"
complete -c pi -n "__fish_pi_needs_command" -s c -l continue -d "Continue previous session"
complete -c pi -n "__fish_pi_needs_command" -s r -l resume -d "Select a session to resume"
complete -c pi -n "__fish_pi_needs_command" -l plan -d "Start in plan mode (read-only exploration)"
complete -c pi -n "__fish_pi_needs_command" -l model -d "Model pattern or ID (provider/id)" -x -a "(__fish_pi_models)"
complete -c pi -n "__fish_pi_needs_command" -l provider -d "Provider to search for --model" -x -a "(__fish_pi_providers)"
complete -c pi -n "__fish_pi_needs_command" -l thinking -d "Set thinking level" -x -a "off minimal low medium high xhigh max"
complete -c pi -n "__fish_pi_needs_command" -l mode -d "Output mode" -x -a "text json rpc"
complete -c pi -n "__fish_pi_needs_command" -l tui-mode -d "TUI mode" -x -a "fullscreen regular"
complete -c pi -n "__fish_pi_needs_command" -s n -l name -d "Set session display name" -r
complete -c pi -n "__fish_pi_needs_command" -s s -l session -d "Use specific session file or partial UUID" -r
complete -c pi -n "__fish_pi_needs_command" -l session-id -d "Use exact project session ID" -r
complete -c pi -n "__fish_pi_needs_command" -l fork -d "Fork specific session file or UUID" -r
complete -c pi -n "__fish_pi_needs_command" -l session-dir -d "Directory for session storage" -r
complete -c pi -n "__fish_pi_needs_command" -l no-session -d "Do not save session (ephemeral)"
complete -c pi -n "__fish_pi_needs_command" -s t -l tools -d "Allowlist of tools" -r
complete -c pi -n "__fish_pi_needs_command" -s xt -l exclude-tools -d "Denylist of tools" -r
complete -c pi -n "__fish_pi_needs_command" -s nt -l no-tools -d "Disable all tools"
complete -c pi -n "__fish_pi_needs_command" -s nbt -l no-builtin-tools -d "Disable built-in tools"
complete -c pi -n "__fish_pi_needs_command" -s e -l extension -d "Load extension file or builtin:<name>" -r
complete -c pi -n "__fish_pi_needs_command" -s ne -l no-extensions -d "Disable extension discovery"
complete -c pi -n "__fish_pi_needs_command" -l skill -d "Load skill file or directory" -r
complete -c pi -n "__fish_pi_needs_command" -s ns -l no-skills -d "Disable skills discovery"
complete -c pi -n "__fish_pi_needs_command" -l prompt-template -d "Load prompt template" -r
complete -c pi -n "__fish_pi_needs_command" -s np -l no-prompt-templates -d "Disable prompt templates"
complete -c pi -n "__fish_pi_needs_command" -s nc -l no-context-files -d "Disable AGENTS.md / CLAUDE.md"
complete -c pi -n "__fish_pi_needs_command" -l list-models -d "List available models"
complete -c pi -n "__fish_pi_needs_command" -s a -l approve -d "Trust project-local files"
complete -c pi -n "__fish_pi_needs_command" -s na -l no-approve -d "Ignore project-local files"
complete -c pi -n "__fish_pi_needs_command" -l export -d "Export session to HTML" -r
complete -c pi -n "__fish_pi_needs_command" -l offline -d "Disable network operations"
complete -c pi -n "__fish_pi_needs_command" -s h -l help -d "Show help"
complete -c pi -n "__fish_pi_needs_command" -s v -l version -d "Show version"

# Subcommand: auth
complete -c pi -n "__fish_pi_using_subcommand auth" -a "print-api-key print-bearer-token check"
complete -c pi -n "__fish_pi_using_subcommand auth" -l provider -d "Provider" -x -a "(__fish_pi_providers)"
complete -c pi -n "__fish_pi_using_subcommand auth" -l model -d "Model" -x -a "(__fish_pi_models)"

# Subcommand: mcp
complete -c pi -n "__fish_pi_using_subcommand mcp" -a "add remove list login logout"
complete -c pi -n "__fish_pi_using_subcommand mcp; and __fish_seen_subcommand_from remove login logout" -a "(__fish_pi_mcp_servers)"
complete -c pi -n "__fish_pi_using_subcommand mcp" -s l -l local -d "Use project-local .pi/mcp.json"

# Subcommand: config
complete -c pi -n "__fish_pi_using_subcommand config" -s l -l local -d "Edit project overrides"
complete -c pi -n "__fish_pi_using_subcommand config" -s a -l approve -d "Trust project-local files"
complete -c pi -n "__fish_pi_using_subcommand config" -s na -l no-approve -d "Ignore project-local files"

# Subcommand: install / remove / update
complete -c pi -n "__fish_pi_using_subcommand install" -s l -l local -d "Install project-locally"
complete -c pi -n "__fish_pi_using_subcommand update" -a "pi self model-catalogs"
