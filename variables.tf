variable "region" {
  default = "ap-southeast-1"
}

variable "avz" {
  default = ["ap-southeast-1a"]
}

variable "instance_type" {
  default = "t3a.xlarge"
}

variable "admin_ui_password" {
  description = "Password for Seafile admin UI login"
  type        = string
  sensitive   = true
}

variable "admin_ui_username" {
  description = "Username for Seafile admin UI login"
  type        = string
  sensitive   = true
}

variable "db_username" {
  description = "Username for Seafile database"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Password for Seafile database"
  type        = string
  sensitive   = true
}

variable "mysql_username" {
  description = "Username for MySQL database"
  type        = string
  sensitive   = true
}

variable "mysql_password" {
  description = "Password for MySQL database"
  type        = string
  sensitive   = true
}

variable "docker_username" {
  description = "Username for Docker login"
  type        = string
  sensitive   = true
}

variable "docker_password" {
  description = "Password for Docker login"
  type        = string
  sensitive   = true
}

variable "public_subnets" {
  description = "List of public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}