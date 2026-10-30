# Optional personal-account resources. Defaults preserve the Learner Lab workflow.
locals {
  execution_role_arn = var.create_task_roles ? aws_iam_role.execution[0].arn : data.aws_iam_role.lab[0].arn
  backend_role_arn   = var.create_task_roles ? aws_iam_role.backend[0].arn : data.aws_iam_role.lab[0].arn
  ecs_trust = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role" "execution" {
  count              = var.create_task_roles ? 1 : 0
  name               = "file-transfer-execution"
  assume_role_policy = local.ecs_trust
}

resource "aws_iam_role_policy_attachment" "execution" {
  count      = var.create_task_roles ? 1 : 0
  role       = aws_iam_role.execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "backend" {
  count              = var.create_task_roles ? 1 : 0
  name               = "file-transfer-backend-read"
  assume_role_policy = local.ecs_trust
}

resource "aws_iam_role_policy" "backend_read" {
  count = var.create_task_roles ? 1 : 0
  name  = "ReadExperimentFixtures"
  role  = aws_iam_role.backend[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${data.aws_s3_bucket.files.arn}/${var.files_prefix}*"
    }]
  })
}

resource "aws_s3_bucket" "experiment" {
  count         = var.create_files_bucket ? 1 : 0
  bucket        = var.files_bucket
  force_destroy = true # Dedicated, reproducible fixtures only.
}

resource "aws_s3_bucket_public_access_block" "experiment" {
  count                   = var.create_files_bucket ? 1 : 0
  bucket                  = aws_s3_bucket.experiment[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
