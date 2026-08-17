terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "stage2-tf-state-335478984954"
    key            = "stage2/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "stage2-tf-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "stage2_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "stage2-tf-vpc"
  }
}
resource "aws_subnet" "public_1a" {
  vpc_id                  = aws_vpc.stage2_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "stage2-tf-public-1a"
  }
}

resource "aws_subnet" "public_1b" {
  vpc_id                  = aws_vpc.stage2_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "stage2-tf-public-1b"
  }
}

resource "aws_subnet" "private_1a" {
  vpc_id            = aws_vpc.stage2_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "stage2-tf-private-1a"
  }
}

resource "aws_subnet" "private_1b" {
  vpc_id            = aws_vpc.stage2_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "stage2-tf-private-1b"
  }
}


resource "aws_internet_gateway" "stage2_igw" {
  vpc_id = aws_vpc.stage2_vpc.id

  tags = {
    Name = "stage2-tf-igw"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.stage2_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.stage2_igw.id
  }

  tags = {
    Name = "stage2-tf-public-rt"
  }
}

resource "aws_route_table_association" "public_1a_assoc" {
  subnet_id      = aws_subnet.public_1a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_1b_assoc" {
  subnet_id      = aws_subnet.public_1b.id
  route_table_id = aws_route_table.public_rt.id
}


resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "stage2-tf-nat-eip"
  }
}

resource "aws_nat_gateway" "stage2_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_1a.id

  tags = {
    Name = "stage2-tf-nat"
  }

  depends_on = [aws_internet_gateway.stage2_igw]
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.stage2_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.stage2_nat.id
  }

  tags = {
    Name = "stage2-tf-private-rt"
  }
}

resource "aws_route_table_association" "private_1a_assoc" {
  subnet_id      = aws_subnet.private_1a.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_1b_assoc" {
  subnet_id      = aws_subnet.private_1b.id
  route_table_id = aws_route_table.private_rt.id
}


resource "aws_security_group" "alb_sg" {
  name        = "stage2-tf-alb-sg"
  description = "Allows HTTP from internet to load balancer"
  vpc_id      = aws_vpc.stage2_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "stage2-tf-alb-sg"
  }
}

resource "aws_security_group" "app_sg" {
  name        = "stage2-tf-app-sg"
  description = "Allows HTTP from ALB, SSH from bastion"
  vpc_id      = aws_vpc.stage2_vpc.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "stage2-tf-app-sg"
  }
}

resource "aws_security_group" "db_sg" {
  name        = "stage2-tf-db-sg"
  description = "Allows database access from app servers only"
  vpc_id      = aws_vpc.stage2_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "stage2-tf-db-sg"
  }
}

resource "aws_security_group" "bastion_sg" {
  name        = "stage2-tf-bastion-sg"
  description = "Allows SSH from my IP only"
  vpc_id      = aws_vpc.stage2_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["172.59.216.253/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "stage2-tf-bastion-sg"
  }
}


data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_launch_template" "app_lt" {
  name_prefix   = "stage2-tf-app-lt"
  image_id      = data.aws_ssm_parameter.al2023_ami.value
  instance_type = "t3.micro"
  key_name      = "stage1-key"

  vpc_security_group_ids = [aws_security_group.app_sg.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum install nginx -y
    systemctl start nginx
    systemctl enable nginx
    echo "Hello from $(hostname -f)" > /usr/share/nginx/html/index.html
  EOF
  )

  tags = {
    Name = "stage2-tf-app-lt"
  }
}

resource "aws_lb_target_group" "app_tg" {
  name     = "stage2-tf-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.stage2_vpc.id
}

resource "aws_lb" "app_alb" {
  name               = "stage2-tf-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]

  tags = {
    Name = "stage2-tf-alb"
  }
}

resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

resource "aws_autoscaling_group" "app_asg" {
  name                = "stage2-tf-asg"
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  vpc_zone_identifier = [aws_subnet.private_1a.id, aws_subnet.private_1b.id]
  target_group_arns   = [aws_lb_target_group.app_tg.arn]

  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "stage2-tf-app"
    propagate_at_launch = true
  }
}


resource "aws_db_subnet_group" "stage2_db_subnet_group" {
  name       = "stage2-tf-db-subnet-group"
  subnet_ids = [aws_subnet.private_1a.id, aws_subnet.private_1b.id]

  tags = {
    Name = "stage2-tf-db-subnet-group"
  }
}

resource "aws_db_instance" "stage2_db" {
  identifier             = "stage2-tf-db"
  engine                 = "mysql"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = "stage2tfdb"
  username               = "admin"
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.stage2_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  publicly_accessible    = false
  skip_final_snapshot    = true

  tags = {
    Name = "stage2-tf-db"
  }
}


resource "aws_instance" "bastion" {
  ami                          = data.aws_ssm_parameter.al2023_ami.value
  instance_type                = "t3.micro"
  key_name                     = "stage1-key"
  subnet_id                    = aws_subnet.public_1a.id
  vpc_security_group_ids       = [aws_security_group.bastion_sg.id]
  associate_public_ip_address  = true

  tags = {
    Name = "stage2-tf-bastion"
  }
}
