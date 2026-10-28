# ─────────────────────────────────────────────
# VPC Outputs
# ─────────────────────────────────────────────
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private app subnet IDs"
  value       = aws_subnet.private[*].id
}

output "db_subnet_ids" {
  description = "List of private database subnet IDs"
  value       = aws_subnet.db[*].id
}

# ─────────────────────────────────────────────
# ALB Outputs
# ─────────────────────────────────────────────
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Route 53 hosted zone ID of the ALB (use for ALIAS records)"
  value       = aws_lb.main.zone_id
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "target_group_arn" {
  description = "ARN of the ALB target group"
  value       = aws_lb_target_group.app.arn
}

output "app_url" {
  description = "Application HTTPS URL"
  value       = "https://${var.domain_name}"
}

# ─────────────────────────────────────────────
# EC2 / ASG Outputs
# ─────────────────────────────────────────────
output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.app.name
}

output "launch_template_id" {
  description = "ID of the Launch Template"
  value       = aws_launch_template.app.id
}

output "ec2_instance_profile_name" {
  description = "IAM Instance Profile name attached to EC2 instances"
  value       = aws_iam_instance_profile.ec2.name
}

# ─────────────────────────────────────────────
# RDS Outputs
# ─────────────────────────────────────────────
output "rds_endpoint" {
  description = "RDS instance endpoint (host:port)"
  value       = "${aws_db_instance.main.address}:${aws_db_instance.main.port}"
}

output "rds_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.main.id
}

# ─────────────────────────────────────────────
# Secrets Manager Output
# ─────────────────────────────────────────────
output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret containing DB credentials"
  value       = aws_secretsmanager_secret.db.arn
  sensitive   = true
}

# ─────────────────────────────────────────────
# S3 Outputs
# ─────────────────────────────────────────────
output "app_s3_bucket_name" {
  description = "Name of the application S3 bucket"
  value       = aws_s3_bucket.app.id
}

output "alb_logs_s3_bucket_name" {
  description = "Name of the ALB access logs S3 bucket"
  value       = aws_s3_bucket.alb_logs.id
}

# ─────────────────────────────────────────────
# KMS Outputs
# ─────────────────────────────────────────────
output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = aws_kms_key.main.arn
}

# ─────────────────────────────────────────────
# SNS Alerts
# ─────────────────────────────────────────────
output "sns_alerts_topic_arn" {
  description = "ARN of the SNS topic for CloudWatch alerts"
  value       = aws_sns_topic.alerts.arn
}
