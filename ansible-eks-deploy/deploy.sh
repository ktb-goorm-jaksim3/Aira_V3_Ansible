#!/bin/bash
# deploy.sh: EKS 클러스터 및 관련 리소스를 한 번에 배포하는 종합 스크립트
# 실행 전 "chmod +x deploy.sh"로 실행 권한 부여하세요.

set -e  # 오류 발생 시 스크립트 중단

echo "====================================="
echo "0. AWS Region Configuration"
echo "====================================="
export AWS_REGION="ap-northeast-2"

echo "====================================="
echo "1. Activating Ansible Virtual Environment (ansible-env)"
echo "====================================="
source ~/Aira_V3_Ansible/ansible-eks-deploy/ansible-env/bin/activate

echo "====================================="
echo "2. Connecting to EKS Cluster"
echo "====================================="
# 클러스터 이름(my-cluster) 및 리전(ap-northeast-2)은 환경에 맞게 수정하세요.
aws eks --region ap-northeast-2 update-kubeconfig --name my-cluster
# eksctl 설치 확인 및 설치 (없을 경우)
if ! command -v eksctl &> /dev/null
then
    echo "eksctl not found. Installing eksctl..."
    curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    sudo mv /tmp/eksctl /usr/local/bin
    echo "eksctl installed."
fi

echo "====================================="
echo "3. Associating IAM OIDC Provider"
echo "====================================="
eksctl utils associate-iam-oidc-provider --region ap-northeast-2 --cluster my-cluster --approve


echo "====================================="
echo "3.5 Installing kubectl"
echo "====================================="
# kubectl 설치 확인 및 설치 (없을 경우)
if ! command -v kubectl &> /dev/null
then
    echo "kubectl not found. Installing kubectl..."
    # 최신 안정 버전 kubectl 다운로드
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    # 바이너리를 /usr/local/bin으로 설치
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
    echo "kubectl installed."
fi

echo "====================================="
echo "4. Creating IAM Service Account for AWS Load Balancer Controller"
echo "====================================="
kubectl delete serviceaccount aws-load-balancer-controller -n kube-system || true
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

#-----------------------------------------------------------------
# 5. Skipping AWS Load Balancer Controller installation via Helm
#     (ALB is managed via Terraform and is already built)
#-----------------------------------------------------------------
echo "====================================="
echo "5. Skipping AWS Load Balancer Controller installation via Helm (managed by Terraform)"
echo "====================================="

#-----------------------------------------------------------------
# 6. Skipping waiting for AWS Load Balancer Controller webhook endpoints
#     (not applicable since LB Controller is not being installed)
#-----------------------------------------------------------------
echo "====================================="
echo "6. Skipping webhook endpoints wait (ALB is managed externally)"
echo "====================================="

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
