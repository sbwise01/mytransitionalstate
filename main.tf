terraform {
  required_version = "~> 0.12.30"

  backend "s3" {
    bucket  = "bw-terraform-state-us-east-1"
    key     = "transitionalstate.tfstate"
    region  = "us-east-1"
    profile = "foghorn-io-brad"
  }
}

provider "aws" {
  region  = var.region
  profile = var.profile
  version = "~> 3.27"
}

variable "region" {
  default = "us-west-2"
}

variable "profile" {
  default = "foghorn-io-brad"
}

variable "tag_costcenter" {
  default = "brad@foghornconsulting.com"
}

variable "tag_environment" {
  default = "Staging"
}

variable "tag_name" {
  default = "bradtransitional"
}

module "aws_vpc" {
  source = "git@github.com:FoghornConsulting/m-vpc?ref=v1.2.0"

  tag_map = {
    CostCenter  = var.tag_costcenter
    Name        = var.tag_name
    Environment = var.tag_environment
  }
}

resource "aws_security_group" "lb" {
  name_prefix = "${var.tag_name}-lb"
  vpc_id      = module.aws_vpc.vpc.id
}

resource "aws_security_group_rule" "lb_ingress" {
  type              = "ingress"
  from_port         = "80"
  to_port           = "80"
  protocol          = "all"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.lb.id
}

resource "aws_security_group_rule" "lb_egress" {
  type              = "egress"
  from_port         = "0"
  to_port           = "65535"
  protocol          = "all"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.lb.id
}

resource "aws_alb" "main_lb" {
  name_prefix                = "main"
  load_balancer_type         = "application"
  security_groups            = list(aws_security_group.lb.id)
  subnets                    = module.aws_vpc.subnets.public.*.id
  enable_deletion_protection = false
  tags = {
    CostCenter  = var.tag_costcenter
    Name        = var.tag_name
    Environment = var.tag_environment
  }
}

resource "aws_alb_listener" "main_lb_listener" {
  load_balancer_arn = aws_alb.main_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.main_lb_tg.arn
    type             = "forward"
  }
}

resource "aws_alb_target_group" "main_lb_tg" {
  name_prefix = "main"
  vpc_id      = module.aws_vpc.vpc.id
  protocol    = "HTTP"
  port        = 5000
  target_type = "ip"

  health_check {
    interval            = 30
    path                = "/"
    port                = 5000
    protocol            = "HTTP"
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}
