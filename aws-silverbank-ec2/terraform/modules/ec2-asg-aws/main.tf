# ============================================================
# modules/ec2-asg-aws/main.tf
# ALB, Target Groups, Launch Templates, ASGs, IAM
# ============================================================

# ------------------------------------------------------------
# IAM Role — allows EC2 to talk to ECR and CloudWatch
# ------------------------------------------------------------

resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-ec2-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-ec2-role-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "ecr" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-profile-${var.environment}"
  role = aws_iam_role.ec2.name
}

# ------------------------------------------------------------
# Application Load Balancer
# ------------------------------------------------------------

resource "aws_lb" "main" {
  name               = "${var.project_name}-alb-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = true

  tags = {
    Name        = "${var.project_name}-alb-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# ------------------------------------------------------------
# Target Groups — Blue and Green
# ------------------------------------------------------------

resource "aws_lb_target_group" "blue" {
  name     = "${var.project_name}-blue-tg-${var.environment}"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/api/health"
    matcher             = "200"
  }

  tags = {
    Name        = "${var.project_name}-blue-tg-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_lb_target_group" "green" {
  name     = "${var.project_name}-green-tg-${var.environment}"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/api/health"
    matcher             = "200"
  }

  tags = {
    Name        = "${var.project_name}-green-tg-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# ------------------------------------------------------------
# ALB Listener — port 80, forwards to Blue by default
# ------------------------------------------------------------

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  tags = {
    Name        = "${var.project_name}-listener-${var.environment}"
    Project     = var.project_name
    Environment = var.environment
  }
}

# ------------------------------------------------------------
# Launch Templates — blueprint for EC2 instances
# ------------------------------------------------------------

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's official AWS account ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_launch_template" "blue" {
  name_prefix   = "${var.project_name}-blue-lt-${var.environment}-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [var.ec2_sg_id]
  }

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    ecr_frontend_url   = var.ecr_frontend_url
    ecr_backend_url    = var.ecr_backend_url
    aws_region         = var.aws_region
    db_name            = var.db_name
    db_username        = var.db_username
    db_password        = var.db_password
    rds_endpoint       = var.rds_endpoint
    jwt_secret         = var.jwt_secret
    jwt_refresh_secret = var.jwt_refresh_secret
    alb_dns_name       = var.alb_dns_name
    environment        = "green"
    image_tag          = "latest"
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-blue-ec2-${var.environment}"
      Project     = var.project_name
      Environment = var.environment
      Color       = "blue"
    }
  }
}

resource "aws_launch_template" "green" {
  name_prefix   = "${var.project_name}-green-lt-${var.environment}-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [var.ec2_sg_id]
  }

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    ecr_frontend_url   = var.ecr_frontend_url
    ecr_backend_url    = var.ecr_backend_url
    aws_region         = var.aws_region
    db_name            = var.db_name
    db_username        = var.db_username
    db_password        = var.db_password
    rds_endpoint       = var.rds_endpoint
    jwt_secret         = var.jwt_secret
    jwt_refresh_secret = var.jwt_refresh_secret
    alb_dns_name       = var.alb_dns_name
    environment        = "green"
    image_tag          = "latest"
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-green-ec2-${var.environment}"
      Project     = var.project_name
      Environment = var.environment
      Color       = "green"
    }
  }
}

# ------------------------------------------------------------
# Auto Scaling Groups — Blue and Green
# ------------------------------------------------------------

resource "aws_autoscaling_group" "blue" {
  name                = "${var.project_name}-blue-asg-${var.environment}"
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_active_desired
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = [aws_lb_target_group.blue.arn]

  launch_template {
    id      = aws_launch_template.blue.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 120

  tag {
    key                 = "Name"
    value               = "${var.project_name}-blue-asg-${var.environment}"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }

  tag {
    key                 = "Color"
    value               = "blue"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_group" "green" {
  name                = "${var.project_name}-green-asg-${var.environment}"
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_idle_desired
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = [aws_lb_target_group.green.arn]

  launch_template {
    id      = aws_launch_template.green.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 120

  tag {
    key                 = "Name"
    value               = "${var.project_name}-green-asg-${var.environment}"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }

  tag {
    key                 = "Color"
    value               = "green"
    propagate_at_launch = true
  }
}