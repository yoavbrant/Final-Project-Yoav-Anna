variable "aws_region" {
  description = "AWS region for deployment"
  default     = "us-east-1"
}
variable "project_name" {
  description = "A name for the project to prefix resources"
  default     = "statuspage"
}
variable "vpc_cidr" {
  description = "VPC CIDR block"
  default     = "10.1.0.0/16"
}
variable "domain_name" {
  description = "Your registered domain name (e.g., example.com)"
  type        = string
}
variable "subdomain_name" {
  description = "The subdomain for the application"
  default     = "status"
}
