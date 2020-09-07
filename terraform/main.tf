# https://github.com/terraform-aws-modules/terraform-aws-alb

provider "aws" {
  region = var.region
}

# Current logged in user iam details
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "allzones" {}

############################### IAM PART ####################################

# IAM Role for Windows EC2 Instance to pull web application artifacts from s3 bucket
resource "aws_iam_role" "this" {
  name = "tf-test-ec2-pull-s3-artifact-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_policy" "this" {
  name        = "tf-test-ec2-pull-s3-artifact-policy"
  description = "Pull S3 Artiface Policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:Get*",
        "s3:List*"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.this.arn
}

resource "aws_iam_instance_profile" "this" {
  name = "tf-test-lc-iam-instance-role"
  role = aws_iam_role.this.name
}

############################### ASG PART ####################################
data "template_file" "instance_user_data" {
  template = file("DeployAspNet.ps1")
  vars = {
    s3_bucket_region = var.s3_bucket_region
    s3_bucket_name   = var.s3_bucket_name
    s3_artifact_name = var.s3_artifact_name
  }
}

resource "aws_launch_configuration" "test_app_lc" {
  image_id                    = var.image_id
  instance_type               = var.lc_instance_type
  security_groups             = [aws_security_group.test_app_websg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.this.id
  user_data                   = data.template_file.instance_user_data.rendered

  depends_on = [aws_iam_instance_profile.this]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "test_app_asg" {
  name                      = var.aws_autoscaling_group_name
  min_size                  = 1
  max_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 2
  force_delete              = true
  launch_configuration      = aws_launch_configuration.test_app_lc.name
  vpc_zone_identifier       = [aws_subnet.public-sb-1.id, aws_subnet.public-sb-2.id]
  target_group_arns         = [aws_lb_target_group.this.arn]

  lifecycle {
    create_before_destroy = true
  }
}

############################### ALB PART ####################################
resource "aws_lb" "this" {
  name            = "tf-alb-test-app"
  security_groups = [aws_security_group.test_elbsg.id]
  subnets         = [aws_subnet.public-sb-1.id, aws_subnet.public-sb-2.id]
  internal        = false

  tags = {
    Environment = "tf-test-alb"
  }
}

resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = "80"
  protocol          = "HTTP"
  // ssl_policy        = "ELBSecurityPolicy-2016-08"
  // certificate_arn   = "arn:aws:iam::187416307283:server-certificate/test_cert_rab3wuqwgja25ct3n4jdj2tzu4"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

resource "aws_lb_target_group" "this" {
  name     = "tf-test-app-lb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id

  tags = {
    Name = "tf-test-lb-tg"
  }
}

############################### NETWORK PART ####################################
# VPC
resource "aws_vpc" "this" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "tf-test-vpc"
  }
}

# IGW
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "tf-test-igw"
  }
}

resource "aws_security_group" "test_app_websg" {
  name   = "security_group_for_test_app_websg"
  vpc_id = aws_vpc.this.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "test_elbsg" {
  name   = "security_group_for_test_elb"
  vpc_id = aws_vpc.this.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# PUBLIC SUBNET 1
resource "aws_subnet" "public-sb-1" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.allzones.names[0]

  tags = {
    Name = "tf-test-public-sb-1"
  }
}

# PUBLIC SUBNET 2
resource "aws_subnet" "public-sb-2" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.allzones.names[1]

  tags = {
    Name = "tf-test-public-sb-2"
  }
}

# ROUTE TABLE 1 WITH IGW ATTACHED
resource "aws_route_table" "public-rt-1" {
  vpc_id     = aws_vpc.this.id
  depends_on = [aws_internet_gateway.this]

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "tf-test-public-rt-1"
  }
}

# ROUTE TABLE 2 WITH IGW ATTACHED
resource "aws_route_table" "public-rt-2" {
  vpc_id     = aws_vpc.this.id
  depends_on = [aws_internet_gateway.this]

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "tf-test-public-rt-2"
  }
}

# PUBLIC SUBNET 1 AND ROUTE TABLE 1 ATTACHED
resource "aws_route_table_association" "public-1" {
  subnet_id      = aws_subnet.public-sb-1.id
  route_table_id = aws_route_table.public-rt-1.id
}

# PUBLIC SUBNET 2 AND ROUTE TABLE 2 ATTACHED
resource "aws_route_table_association" "public-2" {
  subnet_id      = aws_subnet.public-sb-2.id
  route_table_id = aws_route_table.public-rt-2.id
}