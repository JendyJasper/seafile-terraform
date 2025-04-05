locals {
  seafile_buckets = {
    "commit" = "Seafile Commit Objects",
    "fs"     = "Seafile FS Objects",
    "block"  = "Seafile Block Objects"
  }

  # Map of Parameter Store paths to their variable values and descriptions
  seafile_parameters = {
    "admin_ui_login/password" = {
      value       = var.admin_ui_password
      description = "Password for Seafile admin UI login"
    }
    "admin_ui_login/username" = {
      value       = var.admin_ui_username
      description = "Username for Seafile admin UI login"
    }
    "db/username" = {
      value       = var.db_username
      description = "Username for Seafile database"
    }
    "db/password" = {
      value       = var.db_password
      description = "Password for Seafile database"
    }
    "mysql/username" = {
      value       = var.mysql_username
      description = "Username for MySQL database"
    }
    "mysql/password" = {
      value       = var.mysql_password
      description = "Password for MySQL database"
    }
    "docker/username" = {
      value       = var.docker_username
      description = "Username for Docker login"
    }
    "docker/password" = {
      value       = var.docker_password
      description = "Password for Docker login"
    }
  }
}