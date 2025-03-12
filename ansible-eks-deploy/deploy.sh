#!/bin/bash
# deploy.sh: EKS 클러스터 및 관련 리소스를 한 번에 배포하는 종합 스크립트
# 실행 전 "chmod +x deploy.sh"로 실행 권한 부여하세요.

set -e  # 오류 발생 시 스크립트 중단

echo "====================================="
echo "1. Activating Ansible Virtual Environment (ansible-env)"
echo "====================================="
source ~/ansible-env/bin/activate

echo "====================================="
echo "2. Connecting to EKS Cluster"
echo "====================================="
# 클러스터 이름(my-cluster) 및 리전(ap-northeast-2)은 환경에 맞게 수정하세요.
aws eks --region ap-northeast-2 update-kubeconfig --name my-cluster

echo "====================================="
echo "3. Associating IAM OIDC Provider"
echo "====================================="
eksctl utils associate-iam-oidc-provider --region ap-northeast-2 --cluster my-cluster --approve

echo "====================================="
echo "4. Creating IAM Service Account for AWS Load Balancer Controller"
echo "====================================="
eksctl create iamserviceaccount \
  --cluster my-cluster \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn arn:aws:iam::730335258114:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve

# 확인 후 없으면 수동 생성
if ! kubectl get sa aws-load-balancer-controller -n kube-system >/dev/null 2>&1; then
  echo "Service account not found; creating manually..."
  kubectl create serviceaccount aws-load-balancer-controller -n kube-system
fi

echo "====================================="
echo "5. Installing AWS Load Balancer Controller via Helm"
echo "====================================="

if helm status aws-load-balancer-controller -n kube-system >/dev/null 2>&1; then
  echo "aws-load-balancer-controller is already installed. Uninstalling..."
  helm uninstall aws-load-balancer-controller -n kube-system
fi

helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --version 1.11.0 \
  --set clusterName=my-cluster \
  --set serviceAccount.create=false \
  --set enableWebhook=true \
  --set serviceAccount.name=aws-load-balancer-controlleri

echo "====================================="
echo "6. Waiting for AWS Load Balancer Controller Webhook Endpoints"
echo "====================================="
# 최대 180초 (3분) 동안 20초 간격으로 엔드포인트를 확인합니다.
MAX_WAIT=180
WAIT_INTERVAL=20
WAITED=0
while true; do
  WEBHOOK_EP=$(kubectl get endpoints -n kube-system aws-load-balancer-webhook-service --no-headers | awk '{print $2}')
  if [ -n "$WEBHOOK_EP" ]; then
    echo "Webhook endpoints now available: $WEBHOOK_EP"
    break
  else
    echo "No webhook endpoints yet. Waiting ${WAIT_INTERVAL}s..."
    sleep $WAIT_INTERVAL
    WAITED=$((WAITED + WAIT_INTERVAL))
    if [ $WAITED -ge $MAX_WAIT ]; then
      echo "Error: Webhook endpoints are still not available after $MAX_WAIT seconds. Please check AWS Load Balancer Controller logs:"
      kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50
      exit 1
    fi
  fi
done

echo "====================================="
echo "7. Deploying Kubernetes Resources using Ansible"
echo "====================================="

# 7.1. 네임스페이스 생성
echo ">> Deploying Namespaces..."
ansible-playbook -i inventory.ini roles/eks_namespace/tasks/main.yml

# 7.2. PVC 생성
echo ">> Deploying Persistent Volume Claims (PVCs)..."
ansible-playbook -i inventory.ini roles/eks_pvc/tasks/main.yml

# 7.3. Service 생성
echo ">> Deploying Services..."
ansible-playbook -i inventory.ini roles/eks_service/tasks/main.yml

# 7.4. Ingress 생성
echo ">> Deploying Ingresses..."
ansible-playbook -i inventory.ini roles/eks_ingress/tasks/main.yml

# 7.5. ArgoCD 구성 (RBAC, ConfigMap, Secret, Deployment, Service, Ingress)
echo ">> Deploying ArgoCD Components..."
ansible-playbook -i inventory.ini roles/eks_argocd/tasks/main.yml

# 7.6. DaemonSet 배포 (예: Node Exporter)
echo ">> Deploying DaemonSets..."
ansible-playbook -i inventory.ini roles/eks_daemonset/tasks/main.yml

# 7.7. Stateless 애플리케이션 (Deployment) 배포
echo ">> Deploying Deployments..."
ansible-playbook -i inventory.ini roles/eks_deployment/tasks/main.yml

# 7.8. Stateful 애플리케이션 (StatefulSets for Grafana, Prometheus, MySQL) 배포
echo ">> Deploying StatefulSets..."
ansible-playbook -i inventory.ini roles/eks_statefulset/tasks/main.yml

echo "====================================="
echo "8. Verifying deployed resources"
echo "====================================="
kubectl get all --all-namespaces

echo "====================================="
echo "Deployment complete!"
echo "====================================="