provider "aws" {
  region = "ap-northeast-1"
}

############################
# VPC
############################
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true # 名前解決できるか
  enable_dns_hostnames = true # 名前を持てるか

  tags = {
    Name = "tracespec-vpc"
  }
}

############################
# Internet Gateway
############################
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "tracespec-igw"
  }
}

############################
# Public Subnets * 2
############################
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "tracespec-public-1"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = true

  tags = {
    Name = "tracespec-public-2"
  }
}

############################
# Private Subnets * 2
############################
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "ap-northeast-1a"

  tags = {
    Name = "tracespec-private-1"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.20.0/24"
  availability_zone = "ap-northeast-1c"

  tags = {
    Name = "tracespec-private-2"
  }
}

############################
# Route Table (Public)
############################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "tracespec-public-rt"
  }
}

############################
# Route Table Association
############################
resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

############################
# Elastic IP for NAT Gateway
############################
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "tracespec-nat-eip"
  }
}

############################
# NAT Gateway
############################
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id

  tags = {
    Name = "tracespec-nat-gateway"
  }

  depends_on = [aws_internet_gateway.igw]
}

############################
# Private Route Table
############################
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "tracespec-private-rt"
  }
}

############################
# Route Table Association (Private)
############################
resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}

############################
# Security Group (ALB用)
############################
resource "aws_security_group" "alb_sg" {
  name        = "tracespec-alb-sg"
  description = "Allow HTTP inbound"
  vpc_id      = aws_vpc.main.id

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

  tags = {
    Name = "tracespec-alb-sg"
  }
}

############################
# Security Group (ECS用)
############################
resource "aws_security_group" "ecs_sg" {
  name        = "tracespec-ecs-sg"
  description = "Allow traffic from ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "tracespec-ecs-sg"
  }
}

############################
# ALB
############################
resource "aws_lb" "main" {
  name               = "tracespec-alb"
  internal           = false         # インターネット公開する
  load_balancer_type = "application" # ALB or NLB
  security_groups    = [aws_security_group.alb_sg.id]
  subnets = [
    aws_subnet.public_1.id,
    aws_subnet.public_2.id
  ]

  tags = {
    Name = "tracespec-alb"
  }
}

############################
# Target Group
############################
resource "aws_lb_target_group" "main" {
  name        = "tracespec-tg"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "tracespec-tg"
  }
}

############################
# Listener
############################
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

############################
# CludWatch Log
############################
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/tracespec"
  retention_in_days = 7

  tags = {
    Name = "tracespec-ecs-log-group"
  }
}

############################
# ECS Task
############################
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "tracespec-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

############################
# ECS Cluster
############################
resource "aws_ecs_cluster" "main" {
  name = "tracespec-cluster"

  tags = {
    Name = "tracespec-cluster"
  }
}

############################
# Existing ECR
############################
data "aws_ecr_repository" "app" {
  name = "tracespec"
}

############################
# ECS Task Definition
############################
resource "aws_ecs_task_definition" "app" {
  family                   = "tracespec-task"
  network_mode             = "awsvpc" # コンテナが1つのEC2みたいにIPを持つ
  requires_compatibilities = ["FARGATE"]
  # コンピュータの世界では2進数なので「1GB = 1024MB」
  cpu                = "256" # 0.25 vCPU = 256
  memory             = "512" # 0.5 GB = 512
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "tracespec-container"
      image     = "${data.aws_ecr_repository.app.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = "ap-northeast-1"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    Name = "tracespec-task"
  }
}

############################
# ECS Service
############################
resource "aws_ecs_service" "tracespec_app" {
  name            = "tracespec-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets = [
      aws_subnet.private_1.id,
      aws_subnet.private_2.id
    ]

    security_groups = [
      aws_security_group.ecs_sg.id
    ]

    assign_public_ip = false # 外から直接アクセス不可（private）= ECSは外に出さない
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn # select target group
    container_name   = "tracespec-container"
    container_port   = 3000
  }

  depends_on = [
    aws_lb_listener.http
  ]

  tags = {
    Name = "tracespec-service"
  }
}

