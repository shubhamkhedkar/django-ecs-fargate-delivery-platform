output "repository_url" {
  value = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  value = aws_ecr_repository.this.arn
}

output "repository_name" {
  value = aws_ecr_repository.this.name
}

output "image_tag_mutability" {
  value = aws_ecr_repository.this.image_tag_mutability
}

output "scan_on_push" {
  value = aws_ecr_repository.this.image_scanning_configuration[0].scan_on_push
}

output "encryption_type" {
  value = aws_ecr_repository.this.encryption_configuration[0].encryption_type
}

output "lifecycle_rule_count" {
  value = length(jsondecode(aws_ecr_lifecycle_policy.this.policy).rules)
}
