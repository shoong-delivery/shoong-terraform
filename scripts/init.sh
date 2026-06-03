#!/usr/bin/env bash


set -euo pipefail # 에러나면 무시하지 말고 멈출 것
# -e (errexit): 명령어가 실패(Zero가 아닌 종료 상태 반환)하면 즉시 중단
# -u (nounset): 정의되지 않은 변수를 사용하려고 할 때 에러를 내고 중단
# -o pipefail: 파이프(|) 연결 중 하나라도 실패하면 전체를 실패로 간주


# 실행 전 설정값 로드 (ROOT 경로 + 비밀값)
# env.sh는 비밀값(PAT/DB 자격증명)을 담으므로 git에 올리지 않는다(.gitignore).
# 최초 사용 시 env.sh.example을 복사해서 채울 것: cp env.sh.example env.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/env.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/env.sh"
fi

# ROOT 미설정 시 레포 루트의 상위 디렉토리를 기본값으로 사용
# (이 스크립트는 shoong-terraform/scripts/ 에 있고, shoong-gitops 등 형제 레포를
#  함께 참조하므로 ROOT는 두 단계 위 = 모든 레포가 모인 작업 디렉토리여야 한다)
ROOT="${ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
TF_DIR="$ROOT/shoong-terraform/environments/dev"
GITOPS_DIR="$ROOT/shoong-gitops"

REGION="us-east-1"
CLUSTER_NAME="shoong-dev-cluster"
SSM_INSTANCE_NAME='shoong-dev-ssm-ec2'

DB_NAME="shoong_dev"
DB_PORT="5432"

STEP="${STEP:-1}"

# AWS CLI v2의 pager를 비활성화 (Git Bash에서 --output table 사용 시 tput 에러 방지)
# export AWS_PAGER=""

required_env() {
  local name="$1"

  if [ -z "${!name:-}" ]; then
    echo "***에러***: $name 환경변수가 없습니다."
    echo "  예: export $name='value'"
    exit 1
  fi
}

required_env GITHUB_PAT
required_env DB_USERNAME
required_env DB_PASSWORD

# 테라폼으로 생성된 결과물(output)을 쉘 스크립트 변수로 가져오기 위해 만든 사용자 정의 함수
# tf_output() {
#   terraform -chdir="$TF_DIR" output -raw "$1"
    # -chdir: 명령 실행하기 전에 작업 디렉토리 변경해라
    # -raw: 결과값에서 따옴표나 특수 서식을 제거하고 순수한 값(텍스트)만 출력
    # "$1": 함수를 호출할 때 뒤에 붙이는 첫 번째 인자를 의미
    # tf_output vpc_id 라고 실행하면 $1 자리에 vpc_id가 대입됨. 
    # 그래서 실행되는 명령어는 terraform .... output -raw vpc_id
    # "$1" 처럼 공백 붙이는 이유: 데이터에 공백이 있을 때 하나로 묶기 위함
    # 만약 $1이 My Project라는 글자라면, 따옴표가 없을 때 컴퓨터는 My와 Project를 별개의 명령어로 오해 할 수 있다. "$1"이라고 하면 공백이 있더라도 하나의 데이터로 알려주는 것
# }
# VPC_ID="$(tf_output vpc_id)"


echo "===================================================="
echo "[1] Terraform output 조회"
echo "===================================================="

if [ ! -d "$TF_DIR" ]; then
  echo "***에러***: Terraform 디렉토리가 없습니다: $TF_DIR"
  exit 1
fi

OUTPUT_JSON="$(
  cd "$TF_DIR"
  terraform output -json
)"

# JSON 데이터가 비어있는지 확인
if [ -z "$OUTPUT_JSON" ] || [ "$OUTPUT_JSON" == "{}" ]; then
    echo "***에러***: 테라폼 output을 가져오지 못했습니다. terraform apply 상태를 확인하세요."
    exit 1
fi

# jq를 사용하여 메모리상에서 즉시 파싱
CLUSTER_NAME=$(echo "$OUTPUT_JSON" | jq -r '.cluster_name.value // "N/A"')
VPC_ID=$(echo "$OUTPUT_JSON" | jq -r '.vpc_id.value // "N/A"')
ALB_DNS=$(echo "$OUTPUT_JSON" | jq -r '.alb_dns_name.value // "N/A"')
TG_ARN=$(echo "$OUTPUT_JSON" | jq -r '.target_group_arn.value // "N/A"')
DB_ENDPOINT_RAW=$(echo "$OUTPUT_JSON" | jq -r '.db_endpoint.value // "N/A"')
if [[ "$DB_ENDPOINT_RAW" != "N/A" && "$DB_ENDPOINT_RAW" == *:* ]]; then
  DB_HOST="${DB_ENDPOINT_RAW%:*}"
  DB_PORT="${DB_ENDPOINT_RAW##*:}"
else
  DB_HOST="$DB_ENDPOINT_RAW"
fi
CF_DOMAIN=$(echo "$OUTPUT_JSON" | jq -r '.cloudfront_domain.value // "N/A"')
CF_ID=$(echo "$OUTPUT_JSON" | jq -r '.cloudfront_distribution_id.value // "N/A"')
ECR_URLS=$(echo "$OUTPUT_JSON" | jq -r '.ecr_repository_urls.value | if type=="array" then join(", ") else . end // "N/A"')
GH_ROLE=$(echo "$OUTPUT_JSON" | jq -r '.github_actions_role_arn.value // "N/A"')
ESO_ROLE=$(echo "$OUTPUT_JSON" | jq -r '.eso_role_arn.value // "N/A"')
LBC_ROLE=$(echo "$OUTPUT_JSON" | jq -r '.aws_lb_controller_role_arn.value // "N/A"')

echo "----------------------------------------------------"
echo "  [ 인프라 정보 요약 ]"
echo "----------------------------------------------------"
echo "EKS Cluster       : $CLUSTER_NAME"
echo "VPC ID            : $VPC_ID"
echo "ALB DNS           : $ALB_DNS"
echo "Target Group      : $TG_ARN"
echo "DB Endpoint       : $DB_HOST:$DB_PORT"
echo "----------------------------------------------------"
echo "CloudFront Domain : $CF_DOMAIN"
echo "CF Dist ID        : $CF_ID"
echo "ECR Repos         : $ECR_URLS"
echo "----------------------------------------------------"
echo "GitHub Role       : $GH_ROLE"
echo "ESO Role          : $ESO_ROLE"
echo "LBC Role          : $LBC_ROLE"
echo "===================================================="


if [ "$STEP" -le 2 ]; then
echo "===================================================="
echo "[2] GitOps 값 업데이트"
echo "===================================================="

# -C 옵션을 쓰면 cd $GITOPS_DIR 를 안 해도 해당 폴더에서 실행됨
git -C "$GITOPS_DIR" pull origin main

sed -i "s|^vpcId: .*|vpcId: $VPC_ID|" \
  "$GITOPS_DIR/infra/aws-lb-controller/values-dev.yaml"

sed -i "s|^  targetGroupARN: .*|  targetGroupARN: $TG_ARN|" \
  "$GITOPS_DIR/infra/istio-resources/dev/target-group-binding.yaml"

# sed: Stream EDitor. 텍스트 파일을 직접 열지 않고 내용 수정할 때
# sed -i "s|^찾을패턴|바꿀내용|" 파일경로
# -i (in-place): 실제로 파일 내용을 수정해서 저장해라
# s (substitute): 교체하라
# | (구분자): 보통 /를 쓰지만, 값 안에 /가 들어있는 경우(예: ARN 주소) 혼동을 피하기 위해 |를 구분자로 쓰기도 함
# ^ (앵커): 줄의 시작 부분부터 찾아라
# .* (와일드카드): 어떤 글자가 오든 상관없이 끝까지 다 선택해라

fi

if [ "$STEP" -le 3 ]; then
echo "===================================================="
echo "[3] GitOps 레포지토리 업데이트 및 Push"
echo "===================================================="

# 1. GitOps 디렉토리로 이동
cd "$GITOPS_DIR"

# 2. 변경된 파일이 있는지 확인
if [ -n "$(git status --porcelain)" ]; then
  # git status --porcelain: 현재 폴더에 수정된 파일이 있는지 체크
  # 수정 후 git status에서 변경 사항이 없다고 나온다면 YAML 파일 들여쓰기 공백 일치하는지 확인

    echo "저장소 변경 사항 감지. 커밋 진행"
    
    # 3. 변경 사항 스테이징 및 커밋
    git add .
    git commit -m "chore: update infra values from terraform outputs (VPC: $VPC_ID)"
    
    # 4. 원격 저장소로 Push
    # 현재 브랜치 이름을 자동으로 파악해서 push (보통 main 또는 dev)
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    git push origin "$CURRENT_BRANCH"
    # git rev-parse: 현재 내가 어떤 브랜치(main인지 dev인지)에 있는지 자동으로 알아내서 해당 브랜치로 정확히 push
    
    echo "Git Push 완료!"
else
    echo "변경 사항이 없습니다. Push를 건너뜁니다."
fi

# 다시 원래 작업 디렉토리로 복귀 
cd - > /dev/null
# cd -: 바로 직전에 있었던 폴더로 돌아가라
# > /dev/null: 불필요한 메시지 출력 숨겨서 화면에 아무것도 뜨지 않게 하는거

fi


if [ "$STEP" -le 4 ]; then
echo "===================================================="
echo "[4] EKS kubeconfig 설정"
echo "===================================================="

echo "$CLUSTER_NAME 클러스터 접속 정보 업데이트 중..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

echo "현재 EKS 노드 상태를 확인"
kubectl get nodes

fi


if [ "$STEP" -le 5 ]; then
echo "===================================================="
echo "[5] ArgoCD 설치"
echo "===================================================="

cd "$GITOPS_DIR"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# | kubectl apply -f -
# | (파이프): 앞 명령어의 출력 결과(YAML 텍스트)를 뒤 명령어의 입력으로 전달
# kubectl apply -f -: 파일(.yaml) 대신 파이프로 넘어온 표준 입력(-)을 받아서 리소스를 적용
# apply의 특징: 리소스가 이미 있으면 기존 설정을 유지(또는 업데이트)하고 없으면 새로 만듬.
# 이미 설치되어 있는 환경에서도 재실행 가능한 스크립트를 만들기 위함

echo "ArgoCD 매니페스트 배포 중..."
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml \
  --server-side
# --server-side: ArgoCD 매니페스트는 양이 방대해서 가끔 kubectl apply 시 "Annotation length" 제한에 걸려 에러가 날 수 있다. 서버 측에서 리소스를 병합해서 이런 문제가 발생하지 않도록 하는 방식.

echo "ArgoCD Server가 준비될 때까지 대기 중 (최대 180초)..."
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd \
  --timeout=180s
# 설치 명령만 내리고 바로 다음 작업을 하면 서버가 뜨기 전이라 에러가 날 수 있으므로 서버가 완전히 뜰 때까지 기다려주기.

fi


if [ "$STEP" -le 6 ]; then
echo "===================================================="
echo "[6] GitOps 레포 자격증명 등록"
echo "===================================================="

# argocd login 없이 K8s Secret으로 직접 등록
# ArgoCD는 argocd.argoproj.io/secret-type=repository 라벨이 붙은 Secret을 자동 감지
# --dry-run=client -o yaml | kubectl apply -f - : 이미 있으면 덮어쓰고, 없으면 새로 만듬
kubectl create secret generic shoong-gitops-repo \
  -n argocd \
  --from-literal=type=git \
  --from-literal=url=https://github.com/shoong-delivery/shoong-gitops \
  --from-literal=username=git \
  --from-literal=password="${GITHUB_PAT}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl label secret shoong-gitops-repo -n argocd \
  argocd.argoproj.io/secret-type=repository \
  --overwrite

echo "레포 자격증명 등록 완료."

fi


if [ "$STEP" -le 7 ]; then
echo "===================================================="
echo "[7] ArgoCD Application bootstrap (App of Apps 패턴)"
echo "===================================================="

# root Application 2개만 apply → root가 argocd/shared, argocd/dev 폴더의
# 자식 Application들을 자동으로 sync (이후 자식 추가는 git push만으로 반영)
# 직접 apply 방식(이전 패턴)은 새 Application 추가 시마다 kubectl apply가 필요했음
echo "App of Apps root 적용..."
kubectl apply -n argocd -f "$GITOPS_DIR/argocd/bootstrap/app-of-apps-shared.yaml"
kubectl apply -n argocd -f "$GITOPS_DIR/argocd/bootstrap/app-of-apps-dev.yaml"

# argocd-cmd-params-cm(insecure 설정)은 GitOps sync 후 적용되지만
# ArgoCD 서버는 ConfigMap 변경을 자동으로 감지하지 않으므로 재시작 필요
echo "ArgoCD insecure 설정 적용 중..."
kubectl apply -f "$GITOPS_DIR/infra/istio-resources/dev/argocd-insecure.yaml"
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd --timeout=120s

fi


if [ "$STEP" -le 8 ]; then
echo "===================================================="
echo "[8] Istio Injection 설정 및 Ingress 확인"
echo "===================================================="

# istio-system 네임스페이스가 생성될 때까지 대기 (최대 60초)
echo "istio-system 네임스페이스 생성 대기 중..."
for i in {1..12}; do
  if kubectl get namespace istio-system >/dev/null 2>&1; then
    echo "istio-system 네임스페이스 생성 완료"
    break
  fi
  if [ $i -eq 12 ]; then
    echo "***타임아웃***: istio-system 네임스페이스가 생성되지 않았습니다."
    exit 1
  fi
  sleep 5
done
# 1부터 12까지 숫자 세면서 루프 돌고, sleep 5(5초대기)가 있으므로 총 60초(12번*5초)동안 기다리겠다라는 의미
# >/dev/null 2>&1: 성공했는지 실패했는지 결과만 체크하겠다.
# istio-system이 없으면 터미널에 "Error: ... not found"라는 지저분한 메시지가 뜨는데 이걸 블랙홀(null)로 보내서 화면에 안 나오게 숨김. 성공메시지도 숨김.
# if [ $i -eq 12 ]; then: 루프를 12번 다 돌았는데도 break를 못하면 실행
# exit 1: 스크립트 전체 실행을 강제로 종료(잘못된 상태로 다음 명령이 실행되는 걸 방지)


echo "Istio 리소스가 동기화될 때까지 대기..."
# Deployment가 생성될 때까지 최대 60초 대기 루프 
for i in {1..12}; do
  if kubectl get deployment istio-ingressgateway -n istio-system >/dev/null 2>&1; then
    echo "istio-ingressgateway Deployment 확인 완료"
    break
  fi

  if [ $i -eq 12 ]; then
    echo "***타임아웃***: ArgoCD가 Deployment를 생성하지 못했습니다. ArgoCD UI를 확인하세요."
    exit 1
  fi
  
  echo "Deployment 생성 대기 중... ($i/12)"
  sleep 5
done

# 혹시 모르니까 안전하게 Rollout Status만 확인
echo "Ingress Gateway 배포 상태 확인 중..."
kubectl rollout restart deployment istio-ingressgateway -n istio-system
kubectl rollout status deployment istio-ingressgateway -n istio-system --timeout=180s

fi


if [ "$STEP" -le 9 ]; then
echo "===================================================="
echo "[9] ESO 설치"
echo "===================================================="

# Helm 레포 설정
helm repo add external-secrets https://charts.external-secrets.io || true
helm repo update

# 선행 조건 확인: ALB Controller가 작동 중이어야 함 
echo "AWS Load Balancer Controller 가용 상태 대기..."
kubectl wait --for=condition=available deployment \
  -l app.kubernetes.io/name=aws-load-balancer-controller \
  -n kube-system \
  --timeout=180s

# 에러 발생--------------------------------------------------------------------
# ESO 컨트롤러 설치 중...
# Release "external-secrets" does not exist. Installing it now.
# Error: Internal error occurred: failed calling webhook "mservice.elbv2.k8s.aws": failed to call webhook: Post "https://aws-load-balancer-webhook-service.kube-system.svc:443/mutate-v1-service?timeout=10s": tls: failed to verify certificate: x509: certificate signed by unknown authority (possibly because of "crypto/rsa: verification error" while trying to verify candidate authority certificate "aws-load-balancer-controller-ca")

# [트러블슈팅] ESO 설치 시 x509 인증서 오류
# 원인: ESO helm install이 Service 리소스를 생성할 때 LBC의 MutatingWebhook이 가로채는데,
#       init.sh를 처음부터 쭉 실행하면 ArgoCD가 LBC를 비동기로 배포하는 특성상
#       LBC Pod가 Available 상태가 돼도 webhook의 CA bundle 업데이트가 완료되기 전에
#       ESO 설치가 시작되어 인증서 불일치(x509) 에러 발생.
# 해결: ESO 설치 전 --dry-run=server로 webhook 동작을 사전 검증.
#       실패 시 webhook config 삭제 + LBC 재시작으로 인증서를 재발급한 뒤 ESO 설치 진행.


# ALB Controller 웹훅 인증서 유효성 확인
# ESO helm install 시 생성되는 Service 리소스가 ALB Controller 웹훅을 거치는데,
# 클러스터 재생성 후 재설치 시 CA bundle 불일치로 인증서 오류가 발생할 수 있음.
echo "AWS LB Controller 웹훅 동작 확인 중..."
if ! kubectl create service clusterip eso-webhook-check --tcp=80:80 \
     --dry-run=server -n kube-system >/dev/null 2>&1; then
  echo "웹훅 인증서 오류 감지. 웹훅 설정 삭제 및 컨트롤러 재시작 중..."
  kubectl delete mutatingwebhookconfigurations aws-load-balancer-webhook 2>/dev/null || true
  kubectl delete validatingwebhookconfigurations aws-load-balancer-webhook 2>/dev/null || true
  kubectl rollout restart deployment -n kube-system \
    -l app.kubernetes.io/name=aws-load-balancer-controller
  kubectl rollout status deployment -n kube-system \
    -l app.kubernetes.io/name=aws-load-balancer-controller --timeout=120s

  echo "웹훅 인증서 재발급 대기 중..."
  for i in {1..12}; do
    if kubectl create service clusterip eso-webhook-check-2 --tcp=80:80 \
         --dry-run=server -n kube-system >/dev/null 2>&1; then
      echo "웹훅 정상화 완료"
      break
    fi
    if [ $i -eq 12 ]; then
      echo "***에러***: 웹훅 복구 실패. AWS LB Controller 상태를 확인하세요."
      kubectl describe deployment -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
      exit 1
    fi
    echo "웹훅 정상화 대기 중... ($i/12)"
    sleep 10
  done
fi

# 이전 설치 시도가 FAILED 상태로 남아있으면 upgrade가 꼬이므로 먼저 제거
# (--wait 타임아웃으로 실패했지만 pods는 정상인 경우에 발생)
ESO_STATUS="$(helm status external-secrets -n external-secrets --output json 2>/dev/null | jq -r '.info.status' 2>/dev/null || echo "")"
if [ "$ESO_STATUS" = "failed" ]; then
  echo "이전 ESO release가 FAILED 상태입니다. 제거 후 재설치합니다."
  helm uninstall external-secrets -n external-secrets
fi

# ESO 설치 (Helm)
echo "ESO 컨트롤러 설치 중..."
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets \
  --create-namespace \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$ESO_ROLE" \
  --wait

fi

sleep 30

if [ "$STEP" -le 10 ]; then
echo "===================================================="
echo "[10] ESO 리소스 ArgoCD Sync"
echo "===================================================="

# ArgoCD 앱 수동 Sync (ESO CRD가 생성된 후 SecretStore 등을 만들기 위함)
echo "infra-eso-dev 어플리케이션 동기화 중..."
kubectl patch application infra-eso-dev \
  -n argocd \
  --type merge \
  -p '{"operation":{"sync":{"prune":false}}}'
# argocd app sync infra-eso-dev --insecure # 좀 더 확실한 명령이지만 포트포워딩, login 필요함..

# Secret이 실제로 생성되었는지 확인 (최대 60초)
echo "infra-eso-dev sync 완료 대기 중..."
for i in {1..36}; do
  SYNC_STATUS="$(
    kubectl get application infra-eso-dev \
      -n argocd \
      -o jsonpath='{.status.sync.status}' 2>/dev/null || true
  )"

  HEALTH_STATUS="$(
    kubectl get application infra-eso-dev \
      -n argocd \
      -o jsonpath='{.status.health.status}' 2>/dev/null || true
  )"

  OPERATION_PHASE="$(
    kubectl get application infra-eso-dev \
      -n argocd \
      -o jsonpath='{.status.operationState.phase}' 2>/dev/null || true
  )"

  echo "ArgoCD 상태: sync=$SYNC_STATUS health=$HEALTH_STATUS phase=$OPERATION_PHASE ($i/36)"

  if [ "$SYNC_STATUS" = "Synced" ] && { [ "$HEALTH_STATUS" = "Healthy" ] || [ "$HEALTH_STATUS" = "Progressing" ]; }; then
    break
  fi

  if [ "$OPERATION_PHASE" = "Failed" ] || [ "$OPERATION_PHASE" = "Error" ]; then
    echo "***에러***: infra-eso-dev sync 실패"
    kubectl describe application infra-eso-dev -n argocd
    exit 1
  fi

  sleep 5
done

SECRET_READY=false
for i in {1..12}; do
  if kubectl get secret shoong-config -n shoong >/dev/null 2>&1 && \
     kubectl get secret shoong-db-secret -n shoong >/dev/null 2>&1; then
    SECRET_READY=true
    echo "Secret 동기화 완료!"
    break
  fi
  echo "기다리는 중... ($i/12)"
  sleep 5
done

if [ "$SECRET_READY" != "true" ]; then
  echo "***에러***: shoong-config 또는 shoong-db-secret이 생성되지 않았습니다."
  echo "ESO 리소스 상태:"
  kubectl get clustersecretstore || true
  kubectl get externalsecret -n shoong || true
  exit 1
fi

# 앱 Pod 재시작 (생성된 Secret을 반영하기 위함)
echo "shoong 네임스페이스 배포 리소스 재시작..."
kubectl rollout restart deployment -n shoong

fi

if [ "$STEP" -le 11 ]; then
echo "===================================================="
echo "[11] k6 설치 확인"
echo "===================================================="

if command -v k6 >/dev/null 2>&1; then
  echo "k6 이미 설치됨: $(k6 version | head -n1)"
else
  echo "k6가 설치되어 있지 않습니다. 설치를 시작합니다..."

  if command -v choco >/dev/null 2>&1; then
    echo "Chocolatey로 설치 중..."
    choco install k6 -y
  elif command -v winget >/dev/null 2>&1; then
    echo "winget으로 설치 중..."
    winget install --id GrafanaLabs.k6 -e --accept-package-agreements --accept-source-agreements
  elif command -v brew >/dev/null 2>&1; then
    echo "Homebrew로 설치 중..."
    brew install k6
  elif command -v apt-get >/dev/null 2>&1; then
    echo "apt-get으로 설치 중..."
    sudo gpg --no-default-keyring \
      --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
      --keyserver hkp://keyserver.ubuntu.com:80 \
      --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
    echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" \
      | sudo tee /etc/apt/sources.list.d/k6.list
    sudo apt-get update
    sudo apt-get install -y k6
  else
    echo "***에러***: 지원하는 패키지 매니저(choco/winget/brew/apt-get)를 찾지 못했습니다."
    echo "  수동 설치 방법: https://k6.io/docs/get-started/installation/"
    exit 1
  fi

  # 설치 후 PATH 갱신이 안 된 경우를 대비해 재확인
  if ! command -v k6 >/dev/null 2>&1; then
    echo "***경고***: k6 설치는 완료됐지만 현재 셸에서 PATH가 잡히지 않았습니다."
    echo "  새 터미널을 열거나 셸을 재시작한 후 'k6 version'으로 확인하세요."
  else
    echo "k6 설치 완료: $(k6 version | head -n1)"
  fi
fi

fi


if [ "$STEP" -le 12 ]; then
echo "===================================================="
echo "[12] AWS Secrets Manager DB secret 등록"
echo "===================================================="

SECRET_ID="/shoong/dev/db-credentials"

MSYS_NO_PATHCONV=1 aws secretsmanager put-secret-value \
  --secret-id "$SECRET_ID" \
  --secret-string "{\"username\":\"$DB_USERNAME\",\"password\":\"$DB_PASSWORD\",\"endpoint\":\"$DB_HOST:$DB_PORT\"}" \
  --region "$REGION"

# MSYS_NO_PATHCONV=1: Git Bash가 경로처럼 보이는 문자열을 Windows 경로로 자동 변환하지 못하게 막는 설정

fi


if [ "$STEP" -le 99 ]; then
echo "===================================================="
echo "[13] SSM Instance ID 확인"
echo "===================================================="

SSM_INSTANCE_ID="$(
  aws ec2 describe-instances \
    --region "$REGION" \
    --filters \
      "Name=tag:Name,Values=$SSM_INSTANCE_NAME" \
      "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].InstanceId" \
    --output text
)"

if [ -z "$SSM_INSTANCE_ID" ] || [ "$SSM_INSTANCE_ID" = "None" ]; then
  echo "***에러***: 실행 중인 EC2 인스턴스를 찾지 못했습니다. Name=$SSM_INSTANCE_NAME"
  echo "  SSM_INSTANCE_NAME=$SSM_INSTANCE_NAME"
  echo "  REGION=$REGION"
  exit 1
fi

echo "SSM 인스턴스 ID: $SSM_INSTANCE_ID"


SSM_PING_STATUS="$(
  aws ssm describe-instance-information \
    --region "$REGION" \
    --filters "Key=InstanceIds,Values=$SSM_INSTANCE_ID" \
    --query "InstanceInformationList[0].PingStatus" \
    --output text
)"

  if [ -z "$SSM_PING_STATUS" ] || [ "$SSM_PING_STATUS" = "None" ]; then
    echo "***에러***: EC2가 SSM 관리 인스턴스로 조회되지 않습니다."
    echo "  instance=$SSM_INSTANCE_ID"
    echo "  SSM Agent/IAM Role/VPC Endpoint 또는 NAT 경로를 확인하세요."
    exit 1
  fi

  if [ "$SSM_PING_STATUS" != "Online" ]; then
    echo "***에러***: EC2가 SSM Online 상태가 아닙니다."
    echo "  instance=$SSM_INSTANCE_ID"
    echo "  status=$SSM_PING_STATUS"
    exit 1
  fi

echo "SSM 상태: $SSM_PING_STATUS"
  echo "SSM 인스턴스 확인 완료"

fi


if [ "$STEP" -le 14 ]; then
echo "===================================================="
echo "[14] EC2 내부에서 psql 확인 및 RDS 접속 테스트 실행"
echo "===================================================="

COMMAND_ID="$(
  aws ssm send-command \
    --region "$REGION" \
    --instance-ids "$SSM_INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --comment "Shoong RDS psql connection test" \
    --parameters "commands=[
      \"set -e\",
      \"echo 'OS 정보 확인'\",
      \"cat /etc/os-release\",
      \"echo 'psql 버전 확인'\",
      \"psql --version || sudo yum install -y postgresql15 || sudo dnf install -y postgresql15 || sudo amazon-linux-extras install postgresql14 -y\",
      \"psql --version\",
      \"echo 'RDS 접속 테스트'\",
      \"PGPASSWORD='$DB_PASSWORD' psql -h '$DB_HOST' -p '$DB_PORT' -U '$DB_USERNAME' -d '$DB_NAME' -c 'SELECT current_database(), current_user;'\"
    ]" \
    --query "Command.CommandId" \
    --output text
  )"

echo "Command ID: $COMMAND_ID"

# 해당 SSM 명령이 EC2에서 실행 완료될 떄까지 기다리기
if ! aws ssm wait command-executed \
  --region "$REGION" \
  --command-id "$COMMAND_ID" \
  --instance-id "$SSM_INSTANCE_ID"; then

echo "***에러***: SSM 명령 실행 실패. 실행 로그 확인"

# 해당 SSM 명령의 실행 결과를 가져올것
  aws ssm get-command-invocation \
    --region "$REGION" \
    --command-id "$COMMAND_ID" \
    --instance-id "$SSM_INSTANCE_ID" \
    --query "{Status:Status,Stdout:StandardOutputContent,Stderr:StandardErrorContent}" \
    --output table

  exit 1
fi

fi


if [ "$STEP" -le 15 ]; then
echo "===================================================="
echo "[15] DB 초기화 SQL 실행"
echo "===================================================="

COMMAND_ID="$(
    aws ssm send-command \
      --region "$REGION" \
      --instance-ids "$SSM_INSTANCE_ID" \
      --document-name "AWS-RunShellScript" \
      --comment "Shoong DB init SQL" \
      --parameters "commands=[
        \"set -e\",
      \"echo 'DB 초기화 SQL 파일 생성'\",
      \"cat > /tmp/shoong-db-init.sql <<'SQL'\",
      \"CREATE TABLE IF NOT EXISTS \\\"User\\\" (id SERIAL PRIMARY KEY, username VARCHAR UNIQUE NOT NULL, created_at TIMESTAMP DEFAULT NOW());\",
      \"CREATE TABLE IF NOT EXISTS \\\"Menu\\\" (id SERIAL PRIMARY KEY, name VARCHAR UNIQUE NOT NULL);\",
      \"CREATE TABLE IF NOT EXISTS \\\"Order\\\" (id SERIAL PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES \\\"User\\\"(id), menu_id INTEGER NOT NULL REFERENCES \\\"Menu\\\"(id), status VARCHAR NOT NULL DEFAULT 'PENDING', created_at TIMESTAMP DEFAULT NOW(), updated_at TIMESTAMP DEFAULT NOW());\",
      \"CREATE TABLE IF NOT EXISTS \\\"KitchenOrder\\\" (id SERIAL PRIMARY KEY, order_id INTEGER UNIQUE NOT NULL REFERENCES \\\"Order\\\"(id), status VARCHAR NOT NULL, cook_started_at TIMESTAMP, cook_finished_at TIMESTAMP);\",
      \"CREATE TABLE IF NOT EXISTS \\\"Delivery\\\" (id SERIAL PRIMARY KEY, order_id INTEGER UNIQUE NOT NULL REFERENCES \\\"Order\\\"(id), status VARCHAR NOT NULL, delivery_started_at TIMESTAMP, delivery_finished_at TIMESTAMP);\",
      \"CREATE TABLE IF NOT EXISTS \\\"Notification\\\" (id SERIAL PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES \\\"User\\\"(id), order_id INTEGER REFERENCES \\\"Order\\\"(id), message VARCHAR NOT NULL, type VARCHAR NOT NULL, is_read BOOLEAN DEFAULT FALSE, created_at TIMESTAMP DEFAULT NOW());\",
      \"INSERT INTO \\\"Menu\\\" (name) VALUES ('불고기 버거'), ('새우 버거'), ('치즈 버거'), ('감자튀김'), ('콜라') ON CONFLICT DO NOTHING;\",
      \"INSERT INTO \\\"User\\\" (username) VALUES ('tester') ON CONFLICT DO NOTHING;\",
      \"SQL\",
      \"echo 'DB 초기화 SQL 실행'\",
      \"PGPASSWORD='$DB_PASSWORD' psql -h '$DB_HOST' -p '$DB_PORT' -U '$DB_USERNAME' -d '$DB_NAME' -v ON_ERROR_STOP=1 -f /tmp/shoong-db-init.sql\",
      \"echo 'DB 초기화 결과 확인'\",
      \"PGPASSWORD='$DB_PASSWORD' psql -h '$DB_HOST' -p '$DB_PORT' -U '$DB_USERNAME' -d '$DB_NAME' -c '\\\\dt'\",
      \"PGPASSWORD='$DB_PASSWORD' psql -h '$DB_HOST' -p '$DB_PORT' -U '$DB_USERNAME' -d '$DB_NAME' -c 'SELECT * FROM \\\"Menu\\\";'\",
      \"PGPASSWORD='$DB_PASSWORD' psql -h '$DB_HOST' -p '$DB_PORT' -U '$DB_USERNAME' -d '$DB_NAME' -c 'SELECT * FROM \\\"User\\\";'\"
    ]" \
    --query "Command.CommandId" \
    --output text
)"

# ||: 앞 명령이 실패하면 뒤 명령을 실행

echo "Command ID: $COMMAND_ID"

  aws ssm wait command-executed \
    --region "$REGION" \
    --command-id "$COMMAND_ID" \
    --instance-id "$SSM_INSTANCE_ID"

  # aws ssm get-command-invocation \
  #   --region "$REGION" \
  #   --command-id "$COMMAND_ID" \
  #   --instance-id "$SSM_INSTANCE_ID" \
  #   --query "{Status:Status,Stdout:StandardOutputContent,Stderr:StandardErrorContent}" \
  #   --output table
fi


if [ "$STEP" -le 16 ]; then
echo "===================================================="
echo "[16] 최종 확인"
echo "===================================================="
FINAL_CHECK_FAILED=0
CHECK_ID="$(date +%s)"

run_check() {
  local title="$1"
  shift

  echo
  echo "----------------------------------------------------"
  echo "$title"
  echo "----------------------------------------------------"
  echo "+ $*"

  if "$@"; then
    echo "[OK] $title"
  else
    echo "[FAIL] $title"
    FINAL_CHECK_FAILED=1
  fi
}

run_check_shell() {
  local title="$1"
  local command="$2"

  echo
  echo "----------------------------------------------------"
  echo "$title"
  echo "----------------------------------------------------"
  echo "+ $command"

  if bash -lc "$command"; then
    echo "[OK] $title"
  else
    echo "[FAIL] $title"
    FINAL_CHECK_FAILED=1
  fi
}

run_ssm_check() {
  local title="$1"
  local comment="$2"
  local commands="$3"
  local command_id

  echo
  echo "----------------------------------------------------"
  echo "$title"
  echo "----------------------------------------------------"

  if ! command_id="$(
    aws ssm send-command \
      --region "$REGION" \
      --instance-ids "$SSM_INSTANCE_ID" \
      --document-name "AWS-RunShellScript" \
      --comment "$comment" \
      --parameters "$commands" \
      --query "Command.CommandId" \
      --output text
  )"; then
    echo "[FAIL] $title - failed to send SSM command"
    FINAL_CHECK_FAILED=1
    return 0
  fi

  echo "Command ID: $command_id"

  if aws ssm wait command-executed \
    --region "$REGION" \
    --command-id "$command_id" \
    --instance-id "$SSM_INSTANCE_ID"; then
    aws ssm get-command-invocation \
      --region "$REGION" \
      --command-id "$command_id" \
      --instance-id "$SSM_INSTANCE_ID" \
      --query "{Status:Status,Stdout:StandardOutputContent,Stderr:StandardErrorContent}" \
      --output table
    echo "[OK] $title"
  else
    aws ssm get-command-invocation \
      --region "$REGION" \
      --command-id "$command_id" \
      --instance-id "$SSM_INSTANCE_ID" \
      --query "{Status:Status,Stdout:StandardOutputContent,Stderr:StandardErrorContent}" \
      --output table || true
    echo "[FAIL] $title"
    FINAL_CHECK_FAILED=1
  fi
}

echo
echo "Final check target"
echo "  Region       : $REGION"
echo "  Cluster      : $CLUSTER_NAME"
echo "  ALB DNS      : $ALB_DNS"
echo "  Target Group : $TG_ARN"
echo "  DB Host      : $DB_HOST:$DB_PORT"

run_check "[1] ArgoCD Application status" \
  kubectl get application -n argocd

run_check "[2-1] ArgoCD pods" \
  kubectl get pods -n argocd

run_check "[2-2] AWS Load Balancer Controller pods" \
  kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

run_check "[2-3] Istio pods" \
  kubectl get pods -n istio-system

run_check "[2-4] External Secrets pods" \
  kubectl get pods -n external-secrets

run_check_shell "[2-5] EBS CSI controller pods" \
  "kubectl get pods -n kube-system | grep ebs-csi-controller"

run_check "[2-6] Monitoring pods" \
  kubectl get pods -n monitoring

run_check "[2-7] Kiali pod" \
  kubectl get pods -n istio-system -l app=kiali

run_check "[3-1] Namespace labels" \
  kubectl get namespace shoong istio-system --show-labels

run_check "[3-2] Shoong app pods" \
  kubectl get pods -n shoong

run_check "[4-1] ClusterSecretStore status" \
  kubectl get clustersecretstore

run_check "[4-2] ExternalSecret status" \
  kubectl get externalsecret -n shoong

run_check "[4-3] K8s secrets created by ESO" \
  kubectl get secret shoong-db-secret shoong-config -n shoong

run_check "[5-1] Istio ingressgateway service" \
  kubectl get svc -n istio-system istio-ingressgateway

if [ -n "${TG_ARN:-}" ] && [ "$TG_ARN" != "N/A" ]; then
  run_check "[5-2] Target Group health" \
    aws elbv2 describe-target-health \
      --target-group-arn "$TG_ARN" \
      --region "$REGION" \
      --query "TargetHealthDescriptions[].[Target.Id,TargetHealth.State,TargetHealth.Reason]" \
      --output table
else
  echo
  echo "[FAIL] [5-2] Target Group health - TG_ARN is empty or N/A"
  FINAL_CHECK_FAILED=1
fi

run_check "[5-3] TargetGroupBinding" \
  kubectl get targetgroupbinding -A

# if [ -n "${SSM_INSTANCE_ID:-}" ]; then
#   run_ssm_check "[6] DB tables and menu data" "Shoong final DB check" "commands=[
#     \"set -e\",
#     \"PGPASSWORD='$DB_PASSWORD' psql -h '$DB_HOST' -p '$DB_PORT' -U '$DB_USERNAME' -d '$DB_NAME' -c '\\\\dt'\",
#     \"PGPASSWORD='$DB_PASSWORD' psql -h '$DB_HOST' -p '$DB_PORT' -U '$DB_USERNAME' -d '$DB_NAME' -c 'SELECT * FROM \\\"Menu\\\";'\"
#   ]"
# else
#   echo
#   echo "[FAIL] [6] DB tables and menu data - SSM_INSTANCE_ID is empty"
#   FINAL_CHECK_FAILED=1
# fi

run_check "[7-1] order-service internal health" \
  kubectl run "curl-order-health-$CHECK_ID" --rm -i --image=curlimages/curl --restart=Never -n shoong -- curl -fsS http://dev-shoong-order:3001/health

run_check "[7-2] kitchen-service internal health" \
  kubectl run "curl-kitchen-health-$CHECK_ID" --rm -i --image=curlimages/curl --restart=Never -n shoong -- curl -fsS http://dev-shoong-kitchen:3002/health

run_check "[7-3] delivery-service internal health" \
  kubectl run "curl-delivery-health-$CHECK_ID" --rm -i --image=curlimages/curl --restart=Never -n shoong -- curl -fsS http://dev-shoong-delivery:3003/health

run_check "[7-4] notification-service internal health" \
  kubectl run "curl-notification-health-$CHECK_ID" --rm -i --image=curlimages/curl --restart=Never -n shoong -- curl -fsS http://dev-shoong-notification:3004/health

if [ -n "${ALB_DNS:-}" ] && [ "$ALB_DNS" != "N/A" ]; then
  run_check "[8-1] External order health via ALB/Istio" \
    curl -fsS "http://$ALB_DNS/api/orders/health"

  run_check "[8-2] External notification health via ALB/Istio" \
    curl -fsS "http://$ALB_DNS/api/notifications/health"

  run_check "[8-3] External menu API via ALB/Istio" \
    curl -fsS "http://$ALB_DNS/api/orders/menu"

  run_check "[8-4] External order create via ALB/Istio" \
    curl -fsS -X POST "http://$ALB_DNS/api/orders/1?userName=tester"

  run_check "[8-5] External order list via ALB/Istio" \
    curl -fsS "http://$ALB_DNS/api/orders/list?userName=tester"
else
  echo
  echo "[FAIL] [8] External access - ALB_DNS is empty or N/A"
  FINAL_CHECK_FAILED=1
fi

run_check "[9-1] ArgoCD order image summary" \
  kubectl get application dev-shoong-order -n argocd -o jsonpath="{.status.summary.images}"

echo
run_check "[9-2] Current order pod image" \
  kubectl get pods -n shoong -l app=dev-shoong-order -o jsonpath="{.items[0].spec.containers[*].image}"

echo
run_check_shell "[10] k6 설치 확인" \
  "command -v k6 >/dev/null 2>&1 && k6 version | head -n1"

echo
echo "----------------------------------------------------"
echo "Manual checks"
echo "----------------------------------------------------"
echo "Grafana port-forward:"
echo "  kubectl port-forward svc/infra-monitoring-grafana -n monitoring 3000:80"
echo "Kiali port-forward:"
echo "  kubectl port-forward svc/kiali -n istio-system 20001:20001"
echo "CI/CD smoke test example:"
echo "  cd $ROOT/shoong-order-api"
echo "  git commit --allow-empty -m \"ci: smoke test\""
echo "  git push origin develop"

if [ "$FINAL_CHECK_FAILED" -ne 0 ]; then
  echo
  echo "***ERROR***: final check failed. Review the [FAIL] sections above."
  exit 1
fi

echo
echo "All final checks completed successfully."
fi
