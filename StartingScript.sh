#!/bin/bash

# ★ 사용자 설정: 아래 변수에 본인의 AWS 자격증명을 입력하세요.
AWS_ACCESS_KEY_ID="AKIA2UC27UYBCIK6VPQH"
AWS_SECRET_ACCESS_KEY="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"
AWS_DEFAULT_REGION="ap-northeast-2"

# [1] 시스템 패키지 업데이트 및 필수 패키지 설치
echo "🛠️  시스템 패키지 업데이트 중..."
sudo apt-get update -y
sudo apt-get install -y software-properties-common

# [2] Python3 및 pip 설치
echo "🐍  Python 및 pip 설치 중..."
sudo apt install -y python3 python3-pip

echo "🔍  Python 및 pip 버전 확인"
python3 --version
pip3 --version

# [2.5] Python 가상환경(ansible-env) 생성 및 활성화
echo "🔧  ansible-env 가상환경 생성 중..."
sudo apt install -y python3.12-venv   # 가상환경 생성 모듈 설치
python3 -m venv ansible-env
source ansible-env/bin/activate
echo "🔍  가상환경 활성화 확인: $(which python)"

# [3] 가상환경 내 Ansible 및 AWS API(boto3) 설치
echo "📦  가상환경 내 Ansible 및 boto3 설치 중..."
pip install ansible boto3
ansible --version

# [4] boto3 버전 확인 (가상환경 내)
echo "🔍  boto3 버전 확인"
python -c "import boto3; print(boto3.__version__)"

# [5] Ansible 인벤토리 파일 설정
echo "📄  Ansible 인벤토리 파일 생성 중..."
cat <<EOF > ~/hosts
[eks]
15.165.8.255 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/Aira-Key.pem
EOF

echo "📑  Ansible 인벤토리 파일 내용:"
cat ~/hosts

# [6] SSH 키 파일 권한 설정
echo "🔑  SSH 키 파일 권한 설정 중..."
chmod 400 ~/.ssh/Aira-Key.pem
ls -l ~/.ssh/Aira-Key.pem

# [7] Ansible 연결 테스트
echo "🔄  Ansible 연결 테스트 중..."
ansible -i ~/hosts eks -m ping

# [8] AWS CLI 설치
echo "☁️  AWS CLI 설치 중..."
sudo apt remove awscli -y
sudo apt update && sudo apt install -y curl unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf awscliv2.zip aws/

echo "🔍  AWS CLI 버전 확인"
aws --version

# [9] AWS CLI 설정 (자동화)
echo "🔑  AWS CLI 설정 중..."
mkdir -p ~/.aws
cat <<EOF > ~/.aws/credentials
[default]
aws_access_key_id = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}
EOF

cat <<EOF > ~/.aws/config
[default]
region = ${AWS_DEFAULT_REGION}
output = json
EOF

echo "🔍  AWS 인증 확인 (STS 호출)"
aws sts get-caller-identity

# [10] Ansible AWS 모듈 설치
echo "📦  Ansible AWS 모듈 설치 중..."
sudo apt install ansible-core -y
ansible-galaxy collection install amazon.aws --force

echo "🔍  설치된 AWS 관련 모듈 확인"
ansible-doc -l | grep aws

# [11] botocore 버전 확인
echo "🔍  botocore 버전 확인"
python -c "import botocore; print(botocore.__version__)"

echo "✅  Ansible 및 AWS 환경 구축 완료!"