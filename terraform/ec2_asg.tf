# ─────────────────────────────────────────────
# IAM Role for EC2 (Instance Profile)
# ─────────────────────────────────────────────
resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-${var.environment}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-ec2-role"
  }
}

# SSM Session Manager – allows secure shell access without SSH key
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch Agent – metrics and logs
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Custom: read Secrets Manager secret + app S3 bucket access
resource "aws_iam_role_policy" "ec2_custom" {
  name = "ec2-custom-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadDBSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.db.arn
      },
      {
        Sid    = "AppS3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.app.arn,
          "${aws_s3_bucket.app.arn}/*"
        ]
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.main.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-${var.environment}-ec2-instance-profile"
  role = aws_iam_role.ec2.name
}

# ─────────────────────────────────────────────
# KMS Key (shared – used for RDS, Secrets, S3)
# ─────────────────────────────────────────────
resource "aws_kms_key" "main" {
  description             = "${var.project_name}-${var.environment} encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name = "${var.project_name}-${var.environment}-kms-key"
  }
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.project_name}-${var.environment}"
  target_key_id = aws_kms_key.main.key_id
}

# ─────────────────────────────────────────────
# Launch Template
# ─────────────────────────────────────────────
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project_name}-${var.environment}-lt-"
  image_id      = var.ec2_ami_id
  instance_type = var.ec2_instance_type

  vpc_security_group_ids = [aws_security_group.ec2.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  # EBS root volume – encrypted
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = aws_kms_key.main.arn
      delete_on_termination = true
    }
  }

  # Disable public IP – instances live in private subnets
  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ec2.id]
  }

  # Optional SSH key
  key_name = var.ec2_key_pair_name != "" ? var.ec2_key_pair_name : null

  # Enable detailed monitoring
  monitoring {
    enabled = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 enforced
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh.tpl", {
    aws_region    = var.aws_region
    secret_arn    = aws_secretsmanager_secret.db.arn
    db_host       = aws_db_instance.main.address
    db_name       = var.db_name
    s3_bucket     = aws_s3_bucket.app.id
    project_name  = var.project_name
    environment   = var.environment
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-${var.environment}-ec2"
      Project     = var.project_name
      Environment = var.environment
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────────────────────────────────
# Auto Scaling Group
# ─────────────────────────────────────────────
resource "aws_autoscaling_group" "app" {
  name                = "${var.project_name}-${var.environment}-asg"
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns   = [aws_lb_target_group.app.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 120

  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  # Rolling update – replace instances gradually
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 120
    }
  }

  dynamic "tag" {
    for_each = {
      Name        = "${var.project_name}-${var.environment}-asg"
      Project     = var.project_name
      Environment = var.environment
    }
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}

# ─────────────────────────────────────────────
# Auto Scaling Policies
# ─────────────────────────────────────────────

# Scale-out: CPU > 70%
resource "aws_autoscaling_policy" "scale_out" {
  name                   = "${var.project_name}-${var.environment}-scale-out"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

# Scale-out on high request count per target
resource "aws_autoscaling_policy" "scale_out_requests" {
  name                   = "${var.project_name}-${var.environment}-scale-out-requests"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.main.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
    }
    target_value = 1000.0
  }
}
