# AWS Academy / Learner Lab accounts cannot create IAM roles, so the tasks reuse LabRole.
data "aws_iam_role" "lab" {
  count = var.create_task_roles ? 0 : 1
  name  = "LabRole"
}

resource "aws_ecs_cluster" "main" {
  name = "file-transfer"
}

resource "aws_cloudwatch_log_group" "gateway" {
  name              = "/ecs/file-transfer-gateway"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/file-transfer-backend"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "backend" {
  depends_on               = [aws_iam_role_policy_attachment.execution, aws_iam_role_policy.backend_read]
  family                   = "file-transfer-backend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = local.execution_role_arn
  task_role_arn            = local.backend_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = "backend"
    image     = "${aws_ecr_repository.backend.repository_url}:${var.image_tag}"
    essential = true
    # Time for the server to drain (5s) and finish running transfers after SIGTERM
    stopTimeout = 60
    portMappings = [
      { containerPort = 8080, protocol = "udp" },
      { containerPort = 8081, protocol = "tcp" },
    ]
    environment = [
      { name = "BUCKET", value = data.aws_s3_bucket.files.bucket },
      { name = "PREFIX", value = var.files_prefix },
      { name = "PORT", value = "8080" },
      { name = "HEALTH_PORT", value = "8081" },
      { name = "WORKERS", value = tostring(var.backend_workers) },
      { name = "SEND_LOSS", value = tostring(var.backend_send_loss) },
      { name = "RECV_LOSS", value = tostring(var.backend_recv_loss) },
      { name = "AWS_REGION", value = "us-west-2" },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.backend.name
        awslogs-region        = "us-west-2"
        awslogs-stream-prefix = "backend"
      }
    }
  }])
}

resource "aws_ecs_task_definition" "gateway" {
  depends_on               = [aws_iam_role_policy_attachment.execution]
  family                   = "file-transfer-gateway"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = local.execution_role_arn
  task_role_arn            = var.create_task_roles ? null : data.aws_iam_role.lab[0].arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name        = "gateway"
    image       = "${aws_ecr_repository.gateway.repository_url}:${var.image_tag}"
    essential   = true
    stopTimeout = 60
    portMappings = [
      { containerPort = 8000, protocol = "tcp" },
    ]
    environment = [
      { name = "LISTEN", value = ":8000" },
      { name = "TRANSPORT", value = "udp" },
      { name = "UPSTREAM", value = "${aws_lb.backend.dns_name}:8080" },
      { name = "MAX_INFLIGHT", value = tostring(var.max_inflight) },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.gateway.name
        awslogs-region        = "us-west-2"
        awslogs-stream-prefix = "gateway"
      }
    }
  }])
}

resource "aws_ecs_service" "backend" {
  name            = "backend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  launch_type     = "FARGATE"
  desired_count   = var.backend_min

  health_check_grace_period_seconds  = 30
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.backend.id]
    assign_public_ip = true # lets the task pull its image from ECR without a NAT gateway
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.backend]

  # The auto scaler owns the desired count after creation
  lifecycle {
    ignore_changes = [desired_count]
  }
}

resource "aws_ecs_service" "gateway" {
  name            = "gateway"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.gateway.arn
  launch_type     = "FARGATE"
  desired_count   = var.gateway_min

  health_check_grace_period_seconds  = 30
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.gateway.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.gateway.arn
    container_name   = "gateway"
    container_port   = 8000
  }

  depends_on = [aws_lb_listener.gateway]

  lifecycle {
    ignore_changes = [desired_count]
  }
}
