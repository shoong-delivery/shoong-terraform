output "frontend_bucket_id" {
  description = "Frontend S3 버킷 ID"
  value       = aws_s3_bucket.frontend.id
}

output "frontend_bucket_arn" {
  description = "Frontend S3 버킷 ARN"
  value       = aws_s3_bucket.frontend.arn
}

output "frontend_bucket_domain_name" {
  description = "Frontend S3 버킷 도메인(CloudFront 오리진용)"
  value       = aws_s3_bucket.frontend.bucket_regional_domain_name
}
