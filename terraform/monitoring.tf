# ─────────────────────────────────────────────
# CloudWatch Dashboard
# ─────────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-${var.environment}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type       = "metric"
        x          = 0; y = 0; width = 12; height = 6
        properties = {
          title   = "ALB Request Count"
          metrics = [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.main.arn_suffix]]
          period  = 60
          stat    = "Sum"
          region  = var.aws_region
          view    = "timeSeries"
        }
      },
      {
        type       = "metric"
        x          = 12; y = 0; width = 12; height = 6
        properties = {
          title   = "ALB 5XX Errors"
          metrics = [["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", aws_lb.main.arn_suffix]]
          period  = 60
          stat    = "Sum"
          region  = var.aws_region
          view    = "timeSeries"
        }
      },
      {
        type       = "metric"
        x          = 0; y = 6; width = 12; height = 6
        properties = {
          title   = "ASG CPU Utilization"
          metrics = [["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.app.name]]
          period  = 60
          stat    = "Average"
          region  = var.aws_region
          view    = "timeSeries"
        }
      },
      {
        type       = "metric"
        x          = 12; y = 6; width = 12; height = 6
        properties = {
          title   = "RDS CPU & Free Storage"
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.main.id],
            ["AWS/RDS", "FreeStorageSpace",  "DBInstanceIdentifier", aws_db_instance.main.id]
          ]
          period = 60
          stat   = "Average"
          region = var.aws_region
          view   = "timeSeries"
        }
      }
    ]
  })
}

# ─────────────────────────────────────────────
# CloudWatch Alarms
# ─────────────────────────────────────────────
resource "aws_sns_topic" "alerts" {
  name              = "${var.project_name}-${var.environment}-alerts"
  kms_master_key_id = aws_kms_key.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-alerts-sns"
  }
}

# ALB 5XX alarm
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project_name}-${var.environment}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "ALB returning > 10 5XX errors per minute"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }
}

# High CPU alarm
resource "aws_cloudwatch_metric_alarm" "ec2_high_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-ec2-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "ASG average CPU > 85%"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }
}

# RDS storage alarm
resource "aws_cloudwatch_metric_alarm" "rds_low_storage" {
  alarm_name          = "${var.project_name}-${var.environment}-rds-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5368709120 # 5 GB in bytes
  alarm_description   = "RDS free storage < 5 GB"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }
}

# Unhealthy host count alarm
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.project_name}-${var.environment}-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "At least one unhealthy host in the target group"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }
}
