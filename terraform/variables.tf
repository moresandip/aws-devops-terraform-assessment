# ─────────────────────────────────────────────
# General
# ─────────────────────────────────────────────
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project; used as a prefix for all resources"
  type        = string
  default     = "devops-assessment"
}

variable "environment" {
  description = "Deployment environment (prod / staging / dev)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "environment must be one of: prod, staging, dev."
  }
}

# ─────────────────────────────────────────────
# Networking
# ─────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs to use (must be at least 2)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets – app tier (one per AZ)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "db_subnet_cidrs" {
  description = "CIDR blocks for private subnets – database tier (one per AZ)"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

# ─────────────────────────────────────────────
# EC2 / Auto Scaling
# ─────────────────────────────────────────────
variable "ec2_ami_id" {
  description = "AMI ID for EC2 instances (Amazon Linux 2023 recommended)"
  type        = string
  default     = "ami-0c02fb55956c7d316" # Amazon Linux 2 (us-east-1) – update before deploy
}

variable "ec2_instance_type" {
  description = "EC2 instance type for the ASG"
  type        = string
  default     = "t3.micro"
}

variable "ec2_key_pair_name" {
  description = "Name of an existing EC2 Key Pair for SSH access"
  type        = string
  default     = ""
}

variable "asg_min_size" {
  description = "Minimum number of EC2 instances in the ASG"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of EC2 instances in the ASG"
  type        = number
  default     = 6
}

variable "asg_desired_capacity" {
  description = "Desired number of EC2 instances in the ASG"
  type        = number
  default     = 2
}

# ─────────────────────────────────────────────
# Application Load Balancer
# ─────────────────────────────────────────────
variable "domain_name" {
  description = "Fully-qualified domain name for the application (used for ACM cert)"
  type        = string
  default     = "app.devops-assessment.example.com"
}

variable "certificate_arn" {
  description = "ARN of the ACM certificate to use on the HTTPS listener. If empty, Terraform will request one."
  type        = string
  default     = ""
}

# ─────────────────────────────────────────────
# RDS
# ─────────────────────────────────────────────
variable "db_name" {
  description = "Name of the MySQL database"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for the RDS instance"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage for the RDS instance in GB"
  type        = number
  default     = 20
}

variable "db_multi_az" {
  description = "Enable Multi-AZ for RDS"
  type        = bool
  default     = true
}

variable "db_deletion_protection" {
  description = "Enable deletion protection on the RDS instance"
  type        = bool
  default     = true
}

# ─────────────────────────────────────────────
# S3
# ─────────────────────────────────────────────
variable "app_s3_bucket_name" {
  description = "Name of the S3 bucket used for application storage (must be globally unique)"
  type        = string
  default     = "devops-assessment-app-storage"
}

variable "alb_logs_s3_bucket_name" {
  description = "Name of the S3 bucket for ALB access logs (must be globally unique)"
  type        = string
  default     = "devops-assessment-alb-logs"
}
