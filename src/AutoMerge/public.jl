"""
    run(env, cicfg::CIService; kwargs...)
"""
function run(env = ENV,
             cicfg::CIService=auto_detect_ci_service(;env=env);
             merge_new_packages::Bool,
             merge_new_versions::Bool,
             new_package_waiting_period,
             new_jll_package_waiting_period,
             new_version_waiting_period,
             new_jll_version_waiting_period,
             registry::String,
             #
             tagbot_enabled::Bool=false,
             #
             authorized_authors::Vector{String},
             authorized_authors_special_jll_exceptions::Vector{String},
             #
             additional_statuses::AbstractVector{<:AbstractString} = String[],
             additional_check_runs::AbstractVector{<:AbstractString} = String[],
             #
             error_exit_if_automerge_not_applicable::Bool = false,
             #
             master_branch::String = "master",
             master_branch_is_default_branch::Bool = true,
             suggest_onepointzero::Bool = true,
             #
             registry_deps::Vector{<:AbstractString} = String[],
             api_url::String="https://api.github.com",
             check_license::Bool=false,
             # A list of public Julia registries (repository URLs)
             # which will be checked for UUID collisions in order to
             # mitigate the dependency confusion vulnerability. See
             # the `dependency_confusion.jl` file for details.
             public_registries::Vector{<:AbstractString} = String[],
             read_only::Bool=false)::Nothing
    all_statuses = deepcopy(additional_statuses)
    all_check_runs = deepcopy(additional_check_runs)
    push!(all_statuses, "automerge/decision")
    unique!(all_statuses)
    unique!(all_check_runs)
    api = GitHub.GitHubWebAPI(HTTP.URI(api_url))

    registry_head = directory_of_cloned_registry(cicfg; env=env)

    # Figure out what type of build this is
    run_pr_build = conditions_met_for_pr_build(cicfg; env=env, master_branch=master_branch)
    run_merge_build = conditions_met_for_merge_build(cicfg; env=env, master_branch=master_branch)

    if !(run_pr_build || run_merge_build)
        throw_not_automerge_applicable(
            AutoMergeWrongBuildType,
            "Build not determined to be either a PR build or a merge build. Exiting.";
            error_exit_if_automerge_not_applicable = error_exit_if_automerge_not_applicable,
        )
        return nothing
    end

    # Authentication
    key = run_pr_build || !tagbot_enabled ? "AUTOMERGE_GITHUB_TOKEN" : "AUTOMERGE_TAGBOT_TOKEN"
    auth = my_retry(() -> GitHub.authenticate(api, env[key]))
    whoami = my_retry(() -> username(api, cicfg; auth=auth))
    @info("Authenticated to GitHub as \"$(whoami)\"")
    registry_repo = my_retry(() -> GitHub.repo(api, registry; auth=auth))

    if run_pr_build
        pr_number = pull_request_number(cicfg; env=env)
        pr_head_commit_sha = current_pr_head_commit_sha(cicfg; env=env)
        pull_request_build(api,
                           pr_number,
                           pr_head_commit_sha,
                           registry_repo,
                           registry_head;
                           auth = auth,
                           authorized_authors = authorized_authors,
                           authorized_authors_special_jll_exceptions = authorized_authors_special_jll_exceptions,
                           error_exit_if_automerge_not_applicable = error_exit_if_automerge_not_applicable,
                           master_branch = master_branch,
                           master_branch_is_default_branch = master_branch_is_default_branch,
                           suggest_onepointzero = suggest_onepointzero,
                           whoami = whoami,
                           registry_deps = registry_deps,
                           check_license = check_license,
                           public_registries = public_registries,
                           read_only = read_only)
    else
        always_assert(run_merge_build)
        cron_or_api_build(api,
                          registry_repo;
                          auth = auth,
                          authorized_authors = authorized_authors,
                          authorized_authors_special_jll_exceptions = authorized_authors_special_jll_exceptions,
                          merge_new_packages = merge_new_packages,
                          merge_new_versions = merge_new_versions,
                          new_package_waiting_period = new_package_waiting_period,
                          new_jll_package_waiting_period = new_jll_package_waiting_period,
                          new_version_waiting_period = new_version_waiting_period,
                          new_jll_version_waiting_period = new_jll_version_waiting_period,
                          whoami = whoami,
                          all_statuses = all_statuses,
                          all_check_runs = all_check_runs,
                          read_only = read_only)
    end
    return nothing
end
