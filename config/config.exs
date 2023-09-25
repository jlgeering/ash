import Config

config :ash, :use_all_identities_in_manage_relationship?, false

config :ash,
  flags: [read_uses_flow?: System.get_env("FLAG_READ_USES_FLOW", "false") == "true"]

if Mix.env() == :dev do
  config :git_ops,
    mix_project: Ash.MixProject,
    changelog_file: "CHANGELOG.md",
    repository_url: "https://github.com/ash-project/ash",
    # Instructs the tool to manage your mix version in your `mix.exs` file
    # See below for more information
    manage_mix_version?: true,
    # Instructs the tool to manage the version in your README.md
    # Pass in `true` to use `"README.md"` or a string to customize
    manage_readme_version: ["README.md", "documentation/tutorials/get-started.md"],
    version_tag_prefix: "v"
end

if Mix.env() == :test do
  config :ash, :ash_apis, [
    Ash.Test.Flow.Api,
    Ash.Test.Support.PolicyRbac.Api,
    Ash.Test.Support.PolicyComplex.Api,
    Ash.Test.Support.PolicySimple.Api
  ]

  config :ash, :validate_api_resource_inclusion?, false
  config :ash, :validate_api_config_inclusion?, false

  config :logger, level: :debug

  config :ash, :policies,
    show_policy_breakdowns?: true,
    log_policy_breakdowns: :info,
    log_successful_policy_breakdowns: :info
end
