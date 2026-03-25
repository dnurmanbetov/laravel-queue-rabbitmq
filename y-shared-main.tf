terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 4.0"
    }
  }
}

# ----------------------------------------------------------------
locals {
  # ----------------------------------------------------------------
  # base config
  trigger_base_operation = local.env_app_env == "issue" ? "check" : "deploy"

  bucket_caches = "tf-caches-${local.env_deploy_project}"

  # ----------------------------------------------------------------
  # parse git config and detect if we are running in baseapp
  internal_git_config = file("${path.root}/../../../.git/config")

  internal_origin_block = regexall("(?ms)\\[remote \"origin\"\\][^\\[]*", local.internal_git_config)
  is_base_deployment    = length(local.internal_origin_block) > 0 ? length(regexall("laravel-base-deployment", local.internal_origin_block[0])) > 0 : false

  # ----------------------------------------------------------------
  # read .env.tfconfig files from root dir
  envs_global_tfconfig = { for tuple in regexall("(.*)=(.*)", file("${path.root}/../../../.env.global.tfconfig")) : tuple[0] => trim(tuple[1], "\"") if !startswith(tuple[0], "#") }

  # base-project contains += in envs so we need to handle them additionally
  envs_global_tfconfig_base_extra = { for tuple in regexall("(.*)\\+=(.*)", file("${path.root}/../../../.env.global.base-project.tfconfig")) : tuple[0] => trim(tuple[1], "\"") if !startswith(tuple[0], "#") }
  envs_global_tfconfig_base       = { for tuple in regexall("(.*)=(.*)", file("${path.root}/../../../.env.global.base-project.tfconfig")) : tuple[0] => "${trim(tuple[1], "\"")}${try(local.envs_global_tfconfig_base_extra[tuple[0]], "")}" if !startswith(tuple[0], "#") }

  # read .env.tfconfigs for environment
  internal_env_denv_tfconfig_files = [for file in fileset("${path.root}/../../", ".env.*.tfconfig") : file if length(regexall("swp", file)) == 0]
  internal_env_denv_tfconfig_file = tolist(
    [for file in local.internal_env_denv_tfconfig_files : file if length(regexall("base-project", file)) == 0]
  )[0]
  internal_env_denv_tfconfig_file_base_project = tolist(
    [for file in local.internal_env_denv_tfconfig_files : file if length(regexall("base-project", file)) != 0]
  )[0]
  envs_denv_tfconfig = { for tuple in regexall("(.*)=(.*)", file("${path.root}/../../${local.internal_env_denv_tfconfig_file}")) : tuple[0] => trim(tuple[1], "\"") if !startswith(tuple[0], "#") }

  # base-project contains += in envs so we need to handle them additionally
  envs_denv_tfconfig_base_extra = { for tuple in regexall("(.*)\\+=(.*)", file("${path.root}/../../${local.internal_env_denv_tfconfig_file_base_project}")) : tuple[0] => trim(tuple[1], "\"") if !startswith(tuple[0], "#") }
  envs_denv_tfconfig_base       = { for tuple in regexall("(.*)=(.*)", file("${path.root}/../../${local.internal_env_denv_tfconfig_file_base_project}")) : tuple[0] => "${trim(tuple[1], "\"")}${try(local.envs_denv_tfconfig_base_extra[tuple[0]], "")}" if !startswith(tuple[0], "#") }

  # read .env.tfconfigs for trigger
  internal_env_trigger_tfconfig_files = [for file in fileset("${path.root}/", ".env.*.tfconfig") : file if length(regexall("swp", file)) == 0]
  internal_env_trigger_tfconfig_file = tolist(
    [for file in local.internal_env_trigger_tfconfig_files : file if length(regexall("base-project", file)) == 0]
  )[0]
  internal_env_trigger_tfconfig_file_base_project = tolist(
    [for file in local.internal_env_trigger_tfconfig_files : file if length(regexall("base-project", file)) != 0]
  )[0]
  envs_trigger_tfconfig = { for tuple in regexall("(.*)=(.*)", file("${path.root}/${local.internal_env_trigger_tfconfig_file}")) : tuple[0] => trim(tuple[1], "\"") if !startswith(tuple[0], "#") }

  # base-project contains += in envs so we need to handle them additionally
  envs_trigger_tfconfig_base_extra = { for tuple in regexall("(.*)\\+=(.*)", file("${path.root}/${local.internal_env_trigger_tfconfig_file_base_project}")) : tuple[0] => trim(tuple[1], "\"") if !startswith(tuple[0], "#") }
  envs_trigger_tfconfig_base       = { for tuple in regexall("(.*)=(.*)", file("${path.root}/${local.internal_env_trigger_tfconfig_file_base_project}")) : tuple[0] => "${trim(tuple[1], "\"")}${try(local.envs_trigger_tfconfig_base_extra[tuple[0]], "")}" if !startswith(tuple[0], "#") }

  envs_tfconfig = (local.is_base_deployment ?
    merge(
      local.envs_global_tfconfig,
      local.envs_global_tfconfig_base,
      local.envs_denv_tfconfig,
      local.envs_denv_tfconfig_base,
      local.envs_trigger_tfconfig,
      local.envs_trigger_tfconfig_base,
      ) : merge(
      local.envs_global_tfconfig,
      local.envs_denv_tfconfig,
      local.envs_trigger_tfconfig,
    )
  )

  # set variabled
  env_short_app_name = local.envs_tfconfig["SHORT_APP_NAME"]

  env_gcloud_docker_image    = local.envs_tfconfig["GCLOUD_DOCKER_IMAGE"]
  env_docker_docker_image    = local.envs_tfconfig["DOCKER_DOCKER_IMAGE"]
  env_shared_secrets_project = local.envs_tfconfig["SHARED_SECRETS_PROJECT"]
  env_deploy_project         = local.envs_tfconfig["DEPLOY_PROJECT_ID"]

  env_trigger_enabled     = local.envs_tfconfig["TRIGGER_ENABLED"]
  env_branch              = local.envs_tfconfig["BRANCH"]
  env_github_trigger_mode = local.envs_tfconfig["GITHUB_TRIGGER_MODE"]

  env_cloud_build_ssh_enable     = parseint(local.envs_tfconfig["CLOUD_BUILD_SSH_ENABLED"], 10)
  env_cloud_build_ssh_image      = local.envs_tfconfig["CLOUD_BUILD_SSH_IMAGE"]
  env_cloud_build_ssh_entrypoint = local.envs_tfconfig["CLOUD_BUILD_SSH_ENTRYPOINT"]
  env_cloud_build_ssh_timeout    = local.envs_tfconfig["CLOUD_BUILD_SSH_TIMEOUT"]

  env_sonar_scanner_docker_image = local.envs_tfconfig["SONAR_SCANNER_DOCKER_IMAGE"]

  env_trivy_enabled       = parseint(local.envs_tfconfig["TRIVY_ENABLED"], 10)
  env_trivy_ignore_errors = parseint(local.envs_tfconfig["TRIVY_IGNORE_ERRORS"], 10)

  # yaml files
  k8_files = tolist([for file in fileset("${path.root}/../../k8", "*.yaml") : "${path.root}/../../k8/${file}"])

  env_recommended_resource_enabled = parseint(local.envs_tfconfig["RECOMMENDED_RESOURCE_ENABLED"], 10)
  env_metric_days                  = parseint(local.envs_tfconfig["METRIC_DAYS"], 10)

  # resources files
  resources_files = tolist([for file in fileset("${path.root}/../../resources", ".env.*") : "${path.root}/../../resources/${file}"])

  # use directory name as environment name
  env_app_env = basename(dirname(dirname(abspath(path.root))))
}
