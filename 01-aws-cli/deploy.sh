#!/bin/bash
# Stage 1 — Full 2-tier architecture rebuild via AWS CLI
# Public ALB -> private Auto Scaling Group -> private RDS, across 2 AZs, bastion as sole SSH entry.

set -e

# --- Networking ---
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=stage1-cli-vpc}]' --query 'Vpc.VpcId' --output text)

PUBLIC_1A=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --availability-zone us-east-1a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=stage1-cli-public-1a}]' --query 'Subnet.SubnetId' --output text)
PUBLIC_1B=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --availability-zone us-east-1b --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=stage1-cli-public-1b}]' --query 'Subnet.SubnetId' --output text)
PRIVATE_1A=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.3.0/24 --availability-zone us-east-1a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=stage1-cli-private-1a}]' --query 'Subnet.SubnetId' --output text)
PRIVATE_1B=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.4.0/24 --availability-zone us-east-1b --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=stage1-cli-private-1b}]' --query 'Subnet.SubnetId' --output text)

IGW_ID=$(aws ec2 create-internet-gateway --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=stage1-cli-igw}]' --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID

PUBLIC_RT=$(aws ec2 create-route-table --vpc-id $VPC_ID --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=stage1-cli-public-rt}]' --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $PUBLIC_RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
aws ec2 associate-route-table --route-table-id $PUBLIC_RT --subnet-id $PUBLIC_1A
aws ec2 associate-route-table --route-table-id $PUBLIC_RT --subnet-id $PUBLIC_1B

EIP_ALLOC=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)
NAT_ID=$(aws ec2 create-nat-gateway --subnet-id $PUBLIC_1A --allocation-id $EIP_ALLOC --tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=stage1-cli-nat}]' --query 'NatGateway.NatGatewayId' --output text)
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_ID

PRIVATE_RT=$(aws ec2 create-route-table --vpc-id $VPC_ID --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=stage1-cli-private-rt}]' --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $PRIVATE_RT --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_ID
aws ec2 associate-route-table --route-table-id $PRIVATE_RT --subnet-id $PRIVATE_1A
aws ec2 associate-route-table --route-table-id $PRIVATE_RT --subnet-id $PRIVATE_1B

# --- Security groups ---
ALB_SG=$(aws ec2 create-security-group --group-name stage1-cli-alb-sg --description "Allows HTTP from internet to load balancer" --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $ALB_SG --protocol tcp --port 80 --cidr 0.0.0.0/0

APP_SG=$(aws ec2 create-security-group --group-name stage1-cli-app-sg --description "Allows HTTP from ALB, SSH from bastion" --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $APP_SG --protocol tcp --port 80 --source-group $ALB_SG

DB_SG=$(aws ec2 create-security-group --group-name stage1-cli-db-sg --description "Allows database access from app servers only" --vpc-id $VPC_ID --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $DB_SG --protocol tcp --port 3306 --source-group $APP_SG

BASTION_SG=$(aws ec2 create-security-group --group-name stage1-cli-bastion-sg --description "Allows SSH from my IP only" --vpc-id $VPC_ID --query 'GroupId' --output text)
MY_IP=$(curl -s -4 ifconfig.me)
aws ec2 authorize-security-group-ingress --group-id $BASTION_SG --protocol tcp --port 22 --cidr ${MY_IP}/32

# Bastion -> app servers SSH rule (required for the internal hop)
aws ec2 authorize-security-group-ingress --group-id $APP_SG --protocol tcp --port 22 --source-group $BASTION_SG

# --- Compute layer ---
AMI_ID=$(MSYS_NO_PATHCONV=1 aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query "Parameters[0].Value" --output text)

USER_DATA=$(echo -e '#!/bin/bash\nyum install nginx -y\nsystemctl start nginx\nsystemctl enable nginx\necho "Hello from $(hostname -f)" > /usr/share/nginx/html/index.html' | base64 -w 0)

aws ec2 create-launch-template \
  --launch-template-name stage1-cli-app-lt \
  --launch-template-data "{\"ImageId\":\"$AMI_ID\",\"InstanceType\":\"t3.micro\",\"KeyName\":\"stage1-key\",\"SecurityGroupIds\":[\"$APP_SG\"],\"UserData\":\"$USER_DATA\"}"

TG_ARN=$(aws elbv2 create-target-group --name stage1-cli-tg --protocol HTTP --port 80 --vpc-id $VPC_ID --target-type instance --query 'TargetGroups[0].TargetGroupArn' --output text)
ALB_ARN=$(aws elbv2 create-load-balancer --name stage1-cli-alb --subnets $PUBLIC_1A $PUBLIC_1B --security-groups $ALB_SG --scheme internet-facing --type application --query 'LoadBalancers[0].LoadBalancerArn' --output text)
aws elbv2 create-listener --load-balancer-arn $ALB_ARN --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=$TG_ARN

aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name stage1-cli-asg \
  --launch-template LaunchTemplateName=stage1-cli-app-lt,Version='$Latest' \
  --min-size 2 --max-size 4 --desired-capacity 2 \
  --vpc-zone-identifier "$PRIVATE_1A,$PRIVATE_1B" \
  --target-group-arns $TG_ARN

# --- Database ---
aws rds create-db-subnet-group \
  --db-subnet-group-name stage1-cli-db-subnet-group \
  --db-subnet-group-description "DB subnet group spanning both private subnets" \
  --subnet-ids $PRIVATE_1A $PRIVATE_1B

aws rds create-db-instance \
  --db-instance-identifier stage1-cli-db \
  --db-instance-class db.t3.micro \
  --engine mysql \
  --master-username admin \
  --master-user-password "CHANGE_ME_BEFORE_RUNNING" \
  --allocated-storage 20 \
  --vpc-security-group-ids $DB_SG \
  --db-subnet-group-name stage1-cli-db-subnet-group \
  --no-publicly-accessible \
  --db-name stage1clidb

aws rds wait db-instance-available --db-instance-identifier stage1-cli-db

# --- Bastion ---
aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t3.micro \
  --key-name stage1-key \
  --security-group-ids $BASTION_SG \
  --subnet-id $PUBLIC_1A \
  --associate-public-ip-address \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=stage1-cli-bastion}]'

echo "Deployment complete. Check target group health and ALB DNS name before testing."
