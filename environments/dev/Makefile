# 매일 destroy 시 보존할 모듈

# - Route53: 삭제 시 NS 변경 → DNS 전파 재대기 필요하므로 보존
PERSISTENT := \
  -exclude=module.s3 \
  -exclude=module.cloudfront \
  -exclude=module.ecr \
  -exclude=module.route53 \
  -exclude=module.acm \
  -exclude=module.iam_oidc

.PHONY: apply destroy destroy-all

apply:
	terraform apply

# 매일 종료 시: 비용 발생 리소스만 삭제, S3/CF/ECR/DNS는 보존
destroy:
	terraform destroy $(PERSISTENT)

# 완전 삭제가 필요할 때 (주의: S3 파일·ECR 이미지 모두 삭제됨)
destroy-all:
	terraform destroy
