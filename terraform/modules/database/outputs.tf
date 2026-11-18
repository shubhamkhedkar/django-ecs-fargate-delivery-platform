output "address" {
  value = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret (JSON with username/password) managed by RDS."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "instance_arn" {
  value = aws_db_instance.this.arn
}

output "identifier" {
  value = aws_db_instance.this.identifier
}

output "publicly_accessible" {
  value = aws_db_instance.this.publicly_accessible
}

output "storage_encrypted" {
  value = aws_db_instance.this.storage_encrypted
}

output "multi_az" {
  value = aws_db_instance.this.multi_az
}

output "manages_master_password" {
  value = aws_db_instance.this.manage_master_user_password
}

output "force_ssl" {
  value = one([for p in aws_db_parameter_group.this.parameter : p.value if p.name == "rds.force_ssl"])
}
