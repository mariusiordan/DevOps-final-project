# ============================================================
# modules/monitoring-aws/main.tf
# CloudWatch alarms, dashboard, SNS notifications
# ============================================================

# ------------------------------------------------------------
# SNS Topic — alarm notifications go here
# ------------------------------------------------------------

resource "aws_sns_topic" "alarms" {
  name = "${var.project_name}-alarms-${var.environment}"

  tags = {
    Name        = "${var.project_name}-alarms-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ------------------------------------------------------------
# EC2 CPU Alarms — Blue and Green
# ------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "blue_cpu_high" {
  alarm_name          = "${var.project_name}-blue-cpu-high-${var.environment}"
  alarm_description   = "Blue ASG CPU utilization is above 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = var.blue_asg_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Name        = "${var.project_name}-blue-cpu-high-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "green_cpu_high" {
  alarm_name          = "${var.project_name}-green-cpu-high-${var.environment}"
  alarm_description   = "Green ASG CPU utilization is above 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = var.green_asg_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Name        = "${var.project_name}-green-cpu-high-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# ------------------------------------------------------------
# ALB Alarms — 5xx errors and unhealthy hosts
# ------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project_name}-alb-5xx-${var.environment}"
  alarm_description   = "ALB is returning 5xx errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Name        = "${var.project_name}-alb-5xx-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts_blue" {
  alarm_name          = "${var.project_name}-blue-unhealthy-hosts-${var.environment}"
  alarm_description   = "Blue target group has unhealthy hosts"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.blue_tg_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Name        = "${var.project_name}-blue-unhealthy-hosts-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts_green" {
  alarm_name          = "${var.project_name}-green-unhealthy-hosts-${var.environment}"
  alarm_description   = "Green target group has unhealthy hosts"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.green_tg_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Name        = "${var.project_name}-green-unhealthy-hosts-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# ------------------------------------------------------------
# RDS Alarms — CPU and storage
# ------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "${var.project_name}-rds-cpu-high-${var.environment}"
  alarm_description   = "RDS CPU utilization is above 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Name        = "${var.project_name}-rds-cpu-high-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  alarm_name          = "${var.project_name}-rds-storage-low-${var.environment}"
  alarm_description   = "RDS free storage is below 2GB"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 2147483648 # 2GB in bytes
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Name        = "${var.project_name}-rds-storage-low-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# ------------------------------------------------------------
# CloudWatch Dashboard
# ------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title  = "EC2 CPU Utilization — Blue vs Green"
          region = "eu-west-2"
          period = 300
          stat   = "Average"
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.blue_asg_name],
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.green_asg_name]
          ]
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title  = "ALB — Request Count and 5xx Errors"
          region = "eu-west-2"
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", var.alb_arn_suffix]
          ]
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title  = "ALB — Unhealthy Hosts"
          region = "eu-west-2"
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/ApplicationELB", "UnHealthyHostCount", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.blue_tg_arn_suffix],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "LoadBalancer", var.alb_arn_suffix, "TargetGroup", var.green_tg_arn_suffix]
          ]
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title  = "RDS — CPU and Storage"
          region = "eu-west-2"
          period = 300
          stat   = "Average"
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.rds_instance_id],
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.rds_instance_id]
          ]
        }
      }
    ]
  })
}